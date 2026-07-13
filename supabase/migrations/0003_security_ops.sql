-- SaveBite - operational and security follow-up.
--
-- Apply after 0002_security_hardening.sql. This migration remains deliberately
-- independent from every payment gateway. It adds the trusted operational
-- primitives needed by the existing manual payout workflow, scheduled bag
-- notifications, and retry-safe account deletion.

begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

revoke all on schema private from public, anon, authenticated, service_role;
revoke all on table private.app_settings
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Private account-number vault and access audit
-- ---------------------------------------------------------------------------

insert into private.app_settings (key, int_value, text_value)
values (
  'bank_encryption_key',
  null,
  encode(extensions.gen_random_bytes(32), 'hex')
)
on conflict (key) do nothing;

create table if not exists private.bank_account_secrets (
  bank_account_id uuid primary key
    references public.bank_accounts(id) on delete cascade,
  account_number_cipher bytea not null,
  cipher_version smallint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bank_account_secrets_cipher_version_check
    check (cipher_version = 1)
);

create table if not exists private.bank_secret_access_audit (
  id uuid primary key default extensions.gen_random_uuid(),
  bank_account_id uuid not null,
  payout_request_id uuid,
  purpose text not null,
  reason text not null,
  actor text not null,
  actor_role text not null,
  accessed_at timestamptz not null default now(),
  constraint bank_secret_access_purpose_check
    check (purpose in ('verification', 'payout')),
  constraint bank_secret_access_reason_check
    check (length(btrim(reason)) between 8 and 500)
);

create index if not exists bank_secret_access_bank_time_idx
  on private.bank_secret_access_audit (bank_account_id, accessed_at desc);
create index if not exists bank_secret_access_payout_time_idx
  on private.bank_secret_access_audit (payout_request_id, accessed_at desc)
  where payout_request_id is not null;

revoke all on table private.bank_account_secrets
  from public, anon, authenticated, service_role;
revoke all on table private.bank_secret_access_audit
  from public, anon, authenticated, service_role;

create or replace function private.require_service_role()
returns void
language plpgsql
stable
security definer
set search_path = private, pg_catalog
as $$
begin
  if session_user::text not in ('postgres', 'supabase_admin', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
end
$$;

revoke all on function private.require_service_role()
  from public, anon, authenticated, service_role;

-- Locks the profile row for the duration of the calling transaction. The lock
-- serializes normal user mutations with prepare_delete_my_account(), so a new
-- checkout or payout cannot slip in after the deletion marker is committed.
create or replace function private.assert_account_active(p_uid uuid)
returns void
language plpgsql
volatile
security definer
set search_path = private, public, pg_catalog
as $$
declare
  v_deleted_at timestamptz;
begin
  if p_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select p.deleted_at
  into v_deleted_at
  from public.profiles p
  where p.id = p_uid
  for share;

  if not found then
    raise exception 'account is unavailable' using errcode = '55000';
  end if;
  if v_deleted_at is not null then
    raise exception 'account deletion is pending' using errcode = '55000';
  end if;
end
$$;

revoke all on function private.assert_account_active(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.assert_merchant_account_active(
  p_merchant_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = private, public, pg_catalog
as $$
declare
  v_status text;
  v_deleted_at timestamptz;
begin
  select m.status, p.deleted_at
  into v_status, v_deleted_at
  from public.merchants m
  join public.profiles p on p.id = m.user_id
  where m.id = p_merchant_id
  for share of p;

  if not found or v_status <> 'active' then
    raise exception 'merchant is unavailable' using errcode = '55000';
  end if;
  if v_deleted_at is not null then
    raise exception 'merchant account deletion is pending'
      using errcode = '55000';
  end if;
end
$$;

revoke all on function private.assert_merchant_account_active(uuid)
  from public, anon, authenticated, service_role;

-- A second line of defence for security-definer RPCs and future write paths.
-- Trusted database/service jobs have no end-user UID and remain allowed.
create or replace function public.guard_active_account_mutation()
returns trigger
language plpgsql
security definer
set search_path = private, public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if current_setting('savebite.account_deletion', true) = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if v_uid is null then
    if session_user::text in ('postgres', 'supabase_admin', 'service_role')
       or v_role = 'service_role' then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  perform private.assert_account_active(v_uid);
  if tg_table_schema = 'public' and tg_table_name = 'surprise_bags' then
    perform private.assert_merchant_account_active(
      case when tg_op = 'DELETE' then old.merchant_id else new.merchant_id end
    );
  elsif tg_table_schema = 'public' and tg_table_name = 'orders' then
    perform private.assert_merchant_account_active(
      case when tg_op = 'DELETE' then old.merchant_id else new.merchant_id end
    );
  elsif tg_table_schema = 'public' and tg_table_name = 'reviews' then
    perform private.assert_merchant_account_active(
      case when tg_op = 'DELETE' then old.merchant_id else new.merchant_id end
    );
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$$;

revoke all on function public.guard_active_account_mutation()
  from public, anon, authenticated;

revoke all on function public.notify_new_bag()
  from public, anon, authenticated;

drop trigger if exists guard_active_account on public.merchants;
create trigger guard_active_account
  before insert or update or delete on public.merchants
  for each row execute function public.guard_active_account_mutation();

drop trigger if exists guard_active_account on public.surprise_bags;
create trigger guard_active_account
  before insert or update or delete on public.surprise_bags
  for each row execute function public.guard_active_account_mutation();

drop trigger if exists guard_active_account on public.orders;
create trigger guard_active_account
  before insert or update or delete on public.orders
  for each row execute function public.guard_active_account_mutation();

drop trigger if exists guard_active_account on public.reviews;
create trigger guard_active_account
  before insert or update or delete on public.reviews
  for each row execute function public.guard_active_account_mutation();

drop trigger if exists guard_active_account on public.favorites;
create trigger guard_active_account
  before insert or update or delete on public.favorites
  for each row execute function public.guard_active_account_mutation();

-- ---------------------------------------------------------------------------
-- Due-bag notification publication
-- ---------------------------------------------------------------------------

-- Immediate trigger publication is limited to bags currently discoverable on
-- the Jakarta calendar. Future-dated bags are picked up by the service-only
-- scheduler below when their date arrives; <= also provides safe catch-up
-- after a scheduler outage when the pickup window is still open.
create or replace function public.notify_new_bag()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if new.status = 'active'
     and new.available_on <= v_today
     and new.quantity_left > 0
     and (new.pickup_end_at is null or new.pickup_end_at > now())
     and (
       tg_op = 'INSERT'
       or old.status is distinct from new.status
       or old.available_on is distinct from new.available_on
     )
     and exists (
       select 1
       from public.merchants m
       join public.profiles p on p.id = m.user_id and p.deleted_at is null
       where m.id = new.merchant_id and m.status = 'active'
     ) then
    insert into public.notifications
      (user_id, title, body, type, group_label, read, dedupe_key,
       entity_type, entity_id, data)
    select f.consumer_id,
           'Surprise Bag baru',
           new.title || ' tersedia dari merchant favoritmu.',
           'newBag', 'Hari ini', false,
           'bag:' || new.id || ':' || new.available_on,
           'bag', new.id,
           jsonb_build_object('available_on', new.available_on)
    from public.favorites f
    join public.profiles p
      on p.id = f.consumer_id and p.deleted_at is null
    where f.merchant_id = new.merchant_id
    on conflict (user_id, dedupe_key) do nothing;
  end if;
  return new;
end
$$;

-- The limit applies to notification recipients, not bags. Selecting only
-- recipient/bag pairs without an existing dedupe row prevents an early page of
-- already-published bags from starving later bags.
create or replace function public.publish_due_bag_notifications(
  p_limit integer default 1000
)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_count integer;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  perform private.require_service_role();
  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'limit must be between 1 and 10000';
  end if;

  with due as (
    select b.id as bag_id,
           b.title as bag_title,
           b.available_on,
           f.consumer_id,
           'bag:' || b.id || ':' || b.available_on as dedupe_key
    from public.surprise_bags b
    join public.merchants m
      on m.id = b.merchant_id and m.status = 'active'
    join public.profiles mp
      on mp.id = m.user_id and mp.deleted_at is null
    join public.favorites f on f.merchant_id = b.merchant_id
    join public.profiles cp
      on cp.id = f.consumer_id and cp.deleted_at is null
    left join public.notifications n
      on n.user_id = f.consumer_id
     and n.dedupe_key = 'bag:' || b.id || ':' || b.available_on
    where b.status = 'active'
      and b.available_on <= v_today
      and b.quantity_left > 0
      and (b.pickup_end_at is null or b.pickup_end_at > now())
      and n.id is null
    order by b.created_at, b.id, f.consumer_id
    limit p_limit
  )
  insert into public.notifications
    (user_id, title, body, type, group_label, read, dedupe_key,
     entity_type, entity_id, data)
  select d.consumer_id,
         'Surprise Bag baru',
         d.bag_title || ' tersedia dari merchant favoritmu.',
         'newBag', 'Hari ini', false, d.dedupe_key,
         'bag', d.bag_id,
         jsonb_build_object('available_on', d.available_on)
  from due d
  on conflict (user_id, dedupe_key) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end
$$;

-- ---------------------------------------------------------------------------
-- Secure bank registration and trusted secret access
-- ---------------------------------------------------------------------------

create or replace function public.register_bank_account(
  p_bank_code text,
  p_account_holder text,
  p_account_number text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_merchant_id uuid;
  v_number text;
  v_hash bytea;
  v_legacy_hash bytea;
  v_pepper text;
  v_encryption_key text;
  v_bank_code text := upper(btrim(p_bank_code));
  v_bank_name text;
  v_account public.bank_accounts;
  v_cipher bytea;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform private.assert_account_active(v_uid);

  select id into v_merchant_id
  from public.merchants
  where user_id = v_uid and status in ('active', 'pending')
  for update;
  if not found then raise exception 'merchant not found'; end if;

  if v_bank_code is null or v_bank_code !~ '^[A-Z0-9_]{2,20}$' then
    raise exception 'invalid bank code';
  end if;
  if length(btrim(coalesce(p_account_holder, ''))) not between 2 and 100 then
    raise exception 'invalid account holder';
  end if;
  if p_idempotency_key is null
     or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency key must contain 8-128 characters';
  end if;

  v_number := regexp_replace(
    coalesce(p_account_number, ''), '[^0-9]', '', 'g'
  );
  if length(v_number) not between 6 and 20 then
    raise exception 'invalid account number';
  end if;

  select text_value into v_pepper
  from private.app_settings where key = 'bank_hash_pepper';
  select text_value into v_encryption_key
  from private.app_settings where key = 'bank_encryption_key';
  if v_pepper is null or v_encryption_key is null then
    raise exception 'bank security configuration is unavailable';
  end if;

  -- Including bank_code prevents equal digit strings at different banks from
  -- being treated as the same destination.
  v_hash := extensions.hmac(
    v_bank_code || ':' || v_number,
    v_pepper,
    'sha256'
  );
  -- Accepted only to migrate a 0002 account when its owner re-registers it.
  v_legacy_hash := extensions.hmac(v_number, v_pepper, 'sha256');
  v_bank_name := case v_bank_code
    when 'BCA' then 'Bank Central Asia'
    when 'MANDIRI' then 'Bank Mandiri'
    when 'BNI' then 'Bank Negara Indonesia'
    when 'BRI' then 'Bank Rakyat Indonesia'
    else v_bank_code
  end;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_merchant_id::text || ':bank:' || p_idempotency_key,
      0
    )
  );
  -- Different request keys registering the same destination are serialized as
  -- well, so the partial unique index never becomes the normal control flow.
  perform pg_advisory_xact_lock(
    hashtextextended(
      v_merchant_id::text || ':bank-destination:' || encode(v_hash, 'hex'),
      0
    )
  );

  select * into v_account
  from public.bank_accounts
  where merchant_id = v_merchant_id
    and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_account.status not in ('pending', 'verified') then
      raise exception
        'bank account registration is no longer active; use a new idempotency key';
    end if;
    if v_account.bank_code <> v_bank_code
       or v_account.account_number_hash not in (v_hash, v_legacy_hash)
       or v_account.account_holder <> btrim(p_account_holder) then
      raise exception
        'idempotency key was already used with different parameters';
    end if;
  else
    select * into v_account
    from public.bank_accounts
    where merchant_id = v_merchant_id
      and bank_code = v_bank_code
      and account_number_hash in (v_hash, v_legacy_hash)
      and status in ('pending', 'verified')
    order by (account_number_hash = v_hash) desc, created_at
    limit 1
    for update;

    if not found then
      insert into public.bank_accounts (
        merchant_id, bank_code, bank_name, account_holder,
        account_number_hash, account_number_last4, status,
        is_default, idempotency_key
      ) values (
        v_merchant_id, v_bank_code, v_bank_name, btrim(p_account_holder),
        v_hash, right(v_number, 4), 'pending',
        not exists (
          select 1 from public.bank_accounts
          where merchant_id = v_merchant_id
            and status in ('pending', 'verified')
        ),
        p_idempotency_key
      )
      returning * into v_account;
    end if;
  end if;

  -- Migrate the 0002 number-only hash after matching it with the submitted
  -- value. This update never stores the raw number in the public schema.
  if v_account.account_number_hash = v_legacy_hash then
    update public.bank_accounts
    set account_number_hash = v_hash
    where id = v_account.id
    returning * into v_account;
  end if;

  select s.account_number_cipher into v_cipher
  from private.bank_account_secrets s
  where s.bank_account_id = v_account.id
  for update;

  if found then
    if extensions.pgp_sym_decrypt(v_cipher, v_encryption_key) <> v_number then
      raise exception 'stored bank destination does not match registration';
    end if;
  else
    insert into private.bank_account_secrets (
      bank_account_id, account_number_cipher, cipher_version
    ) values (
      v_account.id,
      extensions.pgp_sym_encrypt(
        v_number,
        v_encryption_key,
        'cipher-algo=aes256,compress-algo=0'
      ),
      1
    );
  end if;

  return jsonb_build_object(
    'id', v_account.id,
    'merchant_id', v_account.merchant_id,
    'bank_code', v_account.bank_code,
    'bank_name', v_account.bank_name,
    'account_holder', v_account.account_holder,
    'account_number_last4', v_account.account_number_last4,
    'status', v_account.status,
    'is_default', v_account.is_default,
    'created_at', v_account.created_at
  );
end
$$;

create or replace function public.set_default_bank_account(
  p_bank_account_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_merchant_id uuid;
  v_account public.bank_accounts;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform private.assert_account_active(v_uid);

  select id into v_merchant_id
  from public.merchants
  where user_id = v_uid and status in ('active', 'pending')
  for update;
  if not found then raise exception 'merchant not found'; end if;

  select * into v_account
  from public.bank_accounts
  where id = p_bank_account_id
    and merchant_id = v_merchant_id
    and status in ('pending', 'verified')
  for update;
  if not found then raise exception 'bank account not found'; end if;

  update public.bank_accounts
  set is_default = false
  where merchant_id = v_merchant_id and is_default;
  update public.bank_accounts
  set is_default = true
  where id = v_account.id
  returning * into v_account;

  return jsonb_build_object(
    'id', v_account.id,
    'bank_code', v_account.bank_code,
    'bank_name', v_account.bank_name,
    'account_number_last4', v_account.account_number_last4,
    'status', v_account.status,
    'is_default', v_account.is_default
  );
end
$$;

-- Trusted verification keeps the public bank row masked. A verified account
-- must have a vault entry, while rejection erases the no-longer-needed secret.
create or replace function public.verify_bank_account(
  p_bank_account_id uuid,
  p_status text,
  p_provider_recipient_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_account public.bank_accounts;
  v_uid uuid;
begin
  perform private.require_service_role();
  if p_status is null or p_status not in ('verified', 'rejected') then
    raise exception 'invalid verification status';
  end if;
  if p_status = 'verified'
     and length(btrim(coalesce(p_provider_recipient_id, ''))) < 3 then
    raise exception
      'provider recipient id is required for a verified account';
  end if;

  select * into v_account
  from public.bank_accounts
  where id = p_bank_account_id and status in ('pending', 'verified')
  for update;
  if not found then raise exception 'bank account not found'; end if;

  if p_status = 'verified' and not exists (
    select 1
    from private.bank_account_secrets s
    where s.bank_account_id = v_account.id
  ) then
    raise exception
      'bank account must be re-registered before verification';
  end if;

  update public.bank_accounts
  set status = p_status,
      provider_recipient_id = case
        when p_status = 'verified' then btrim(p_provider_recipient_id)
        else null
      end,
      is_default = case
        when p_status = 'rejected' then false else is_default
      end
  where id = v_account.id
  returning * into v_account;

  if p_status = 'rejected' then
    delete from private.bank_account_secrets
    where bank_account_id = v_account.id;
  end if;

  select user_id into v_uid
  from public.merchants where id = v_account.merchant_id;
  perform public.enqueue_notification(
    v_uid,
    case
      when p_status = 'verified' then 'Rekening terverifikasi'
      else 'Verifikasi rekening gagal'
    end,
    v_account.bank_name || ' *' || v_account.account_number_last4,
    'payout',
    'bank-account:' || v_account.id || ':' || p_status,
    'bank_account',
    v_account.id,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object(
    'id', v_account.id,
    'merchant_id', v_account.merchant_id,
    'bank_code', v_account.bank_code,
    'bank_name', v_account.bank_name,
    'account_holder', v_account.account_holder,
    'account_number_last4', v_account.account_number_last4,
    'status', v_account.status,
    'is_default', v_account.is_default,
    'updated_at', v_account.updated_at
  );
end
$$;

create or replace function public.request_withdrawal(
  p_bank_account_id uuid,
  p_amount integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_merchant public.merchants;
  v_bank public.bank_accounts;
  v_request public.payout_requests;
  v_available bigint;
  v_fee integer := private.setting_int('withdrawal_fee');
  v_minimum integer := private.setting_int('minimum_withdrawal');
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform private.assert_account_active(v_uid);

  if p_amount is null or p_amount < v_minimum then
    raise exception 'minimum withdrawal is Rp% ', v_minimum;
  end if;
  if p_amount <= v_fee then
    raise exception 'withdrawal amount must exceed its fee';
  end if;
  if p_idempotency_key is null
     or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency key must contain 8-128 characters';
  end if;

  select * into v_merchant
  from public.merchants
  where user_id = v_uid and status = 'active'
  for update;
  if not found then raise exception 'active merchant not found'; end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_merchant.id::text || ':payout:' || p_idempotency_key,
      0
    )
  );

  select * into v_request
  from public.payout_requests
  where merchant_id = v_merchant.id
    and idempotency_key = p_idempotency_key;
  if found then
    if v_request.amount <> p_amount
       or v_request.bank_account_id is distinct from p_bank_account_id then
      raise exception
        'idempotency key was already used with different parameters';
    end if;
    return to_jsonb(v_request);
  end if;

  select * into v_bank
  from public.bank_accounts
  where id = p_bank_account_id
    and merchant_id = v_merchant.id
    and status = 'verified'
  for update;
  if not found then raise exception 'verified bank account not found'; end if;

  if not exists (
    select 1 from private.bank_account_secrets s
    where s.bank_account_id = v_bank.id
  ) then
    raise exception
      'bank destination must be re-registered before withdrawal';
  end if;

  select coalesce(sum(case t.kind
    when 'income' then t.amount
    when 'withdrawal' then -t.amount
    when 'withdrawal_reversal' then t.amount
    else 0 end), 0)
  into v_available
  from public.transactions t
  where t.merchant_id = v_merchant.id and t.trusted;

  if v_available < p_amount then
    raise exception 'insufficient available balance';
  end if;

  insert into public.payout_requests (
    merchant_id, bank_account_id, bank_code, bank_name,
    account_number_last4, amount, fee_amount, net_amount,
    status, idempotency_key
  ) values (
    v_merchant.id, v_bank.id, v_bank.bank_code, v_bank.bank_name,
    v_bank.account_number_last4, p_amount, v_fee, p_amount - v_fee,
    'requested', p_idempotency_key
  )
  returning * into v_request;

  insert into public.transactions (
    merchant_id, title, subtitle, amount, kind, reference_type,
    reference_id, idempotency_key, metadata, created_by
  ) values (
    v_merchant.id,
    'Penarikan ke ' || v_bank.bank_name,
    'Diproses - rekening *' || v_bank.account_number_last4,
    p_amount, 'withdrawal', 'payout', v_request.id,
    'payout:' || p_idempotency_key,
    jsonb_build_object(
      'fee_amount', v_fee,
      'net_amount', p_amount - v_fee
    ),
    v_uid
  );

  return to_jsonb(v_request);
end
$$;

create or replace function public.get_bank_account_verification_data(
  p_bank_account_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_account public.bank_accounts;
  v_cipher bytea;
  v_key text;
  v_number text;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  perform private.require_service_role();
  if length(v_reason) not between 8 and 500 then
    raise exception 'audit reason must contain 8-500 characters';
  end if;

  select * into v_account
  from public.bank_accounts
  where id = p_bank_account_id and status in ('pending', 'verified')
  for share;
  if not found then raise exception 'bank account not found'; end if;

  select s.account_number_cipher into v_cipher
  from private.bank_account_secrets s
  where s.bank_account_id = v_account.id
  for share;
  if not found then
    raise exception 'bank account must be re-registered to restore its secret';
  end if;

  select text_value into v_key
  from private.app_settings where key = 'bank_encryption_key';
  if v_key is null then
    raise exception 'bank security configuration is unavailable';
  end if;
  v_number := extensions.pgp_sym_decrypt(v_cipher, v_key);

  insert into private.bank_secret_access_audit (
    bank_account_id, payout_request_id, purpose, reason, actor, actor_role
  ) values (
    v_account.id, null, 'verification', v_reason,
    coalesce(nullif(auth.jwt() ->> 'sub', ''), session_user::text),
    coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text)
  );

  return jsonb_build_object(
    'bank_account_id', v_account.id,
    'merchant_id', v_account.merchant_id,
    'bank_code', v_account.bank_code,
    'bank_name', v_account.bank_name,
    'account_holder', v_account.account_holder,
    'account_number', v_number,
    'account_number_last4', v_account.account_number_last4,
    'status', v_account.status
  );
end
$$;

create or replace function public.get_payout_destination(
  p_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_request public.payout_requests;
  v_account public.bank_accounts;
  v_cipher bytea;
  v_key text;
  v_number text;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  perform private.require_service_role();
  if length(v_reason) not between 8 and 500 then
    raise exception 'audit reason must contain 8-500 characters';
  end if;

  select * into v_request
  from public.payout_requests
  where id = p_request_id and status in ('requested', 'processing')
  for share;
  if not found then raise exception 'active payout request not found'; end if;

  select * into v_account
  from public.bank_accounts
  where id = v_request.bank_account_id
    and merchant_id = v_request.merchant_id
    and status = 'verified'
  for share;
  if not found then raise exception 'verified payout destination not found'; end if;

  select s.account_number_cipher into v_cipher
  from private.bank_account_secrets s
  where s.bank_account_id = v_account.id
  for share;
  if not found then
    raise exception 'bank account must be re-registered to restore its secret';
  end if;

  select text_value into v_key
  from private.app_settings where key = 'bank_encryption_key';
  if v_key is null then
    raise exception 'bank security configuration is unavailable';
  end if;
  v_number := extensions.pgp_sym_decrypt(v_cipher, v_key);

  insert into private.bank_secret_access_audit (
    bank_account_id, payout_request_id, purpose, reason, actor, actor_role
  ) values (
    v_account.id, v_request.id, 'payout', v_reason,
    coalesce(nullif(auth.jwt() ->> 'sub', ''), session_user::text),
    coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text)
  );

  return jsonb_build_object(
    'payout_request_id', v_request.id,
    'merchant_id', v_request.merchant_id,
    'bank_account_id', v_account.id,
    'bank_code', v_request.bank_code,
    'bank_name', v_request.bank_name,
    'account_holder', v_account.account_holder,
    'account_number', v_number,
    'account_number_last4', v_request.account_number_last4,
    'provider_recipient_id', v_account.provider_recipient_id,
    'amount', v_request.amount,
    'fee_amount', v_request.fee_amount,
    'net_amount', v_request.net_amount,
    'status', v_request.status
  );
end
$$;

-- ---------------------------------------------------------------------------
-- Two-phase, retry-safe account deletion
-- ---------------------------------------------------------------------------

create or replace function public.prepare_delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_merchant_id uuid;
  v_requested_at timestamptz;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid
  for update;
  if not found then raise exception 'account is unavailable'; end if;

  select id into v_merchant_id
  from public.merchants
  where user_id = v_uid
  for update;

  if v_merchant_id is not null and exists (
    select 1
    from public.payout_requests
    where merchant_id = v_merchant_id
      and status in ('requested', 'processing')
  ) then
    raise exception
      'account cannot be deleted while a payout is in progress';
  end if;
  if v_merchant_id is not null and exists (
    select 1
    from public.orders
    where merchant_id = v_merchant_id
      and status in ('pending', 'paid', 'preparing', 'ready')
  ) then
    raise exception
      'account cannot be deleted while an order is still active';
  end if;
  if exists (
    select 1
    from public.orders
    where consumer_id = v_uid
      and status in ('pending', 'paid', 'preparing', 'ready')
  ) then
    raise exception
      'account cannot be deleted while a consumer order is still active';
  end if;

  if v_profile.deleted_at is null then
    update public.profiles
    set deleted_at = now()
    where id = v_uid
    returning deleted_at into v_requested_at;
  else
    v_requested_at := v_profile.deleted_at;
  end if;

  return jsonb_build_object(
    'prepared', true,
    'user_id', v_uid,
    'requested_at', v_requested_at,
    'storage_prefix', v_uid::text
  );
end
$$;

create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_merchant_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid
  for update;
  if not found then raise exception 'account is unavailable'; end if;
  if v_profile.deleted_at is null then
    raise exception 'account deletion must be prepared first'
      using errcode = '55000';
  end if;

  select id into v_merchant_id
  from public.merchants
  where user_id = v_uid
  for update;

  if v_merchant_id is not null and exists (
    select 1
    from public.payout_requests
    where merchant_id = v_merchant_id
      and status in ('requested', 'processing')
  ) then
    raise exception
      'account cannot be deleted while a payout is in progress';
  end if;
  if v_merchant_id is not null and exists (
    select 1
    from public.orders
    where merchant_id = v_merchant_id
      and status in ('pending', 'paid', 'preparing', 'ready')
  ) then
    raise exception
      'account cannot be deleted while an order is still active';
  end if;
  if exists (
    select 1
    from public.orders
    where consumer_id = v_uid
      and status in ('pending', 'paid', 'preparing', 'ready')
  ) then
    raise exception
      'account cannot be deleted while a consumer order is still active';
  end if;

  -- Phase two is not allowed to orphan public Storage objects. Upload/update
  -- policies are already blocked by the phase-one marker, so this check cannot
  -- race with a new object from the deleting account.
  if exists (
    select 1
    from storage.objects o
    where o.bucket_id in ('bag-images', 'store-logos', 'avatars')
      and (storage.foldername(o.name))[1] = v_uid::text
  ) then
    raise exception 'storage cleanup is incomplete'
      using errcode = '55000';
  end if;

  -- This local marker allows only this transaction to pass the mutation guard
  -- while it anonymizes retained accounting/order records.
  perform set_config('savebite.account_deletion', 'on', true);

  update public.orders
  set consumer_id = null,
      consumer_name = 'Pengguna dihapus',
      consumer_anonymized = true
  where consumer_id = v_uid;

  update public.reviews
  set consumer_id = null, tags = '{}'::text[], comment = ''
  where consumer_id = v_uid;

  if v_merchant_id is not null then
    -- Cascades remove the encrypted vault entry. Historical payout and access
    -- audit rows contain only masked identifiers/snapshots and remain intact.
    delete from public.bank_accounts where merchant_id = v_merchant_id;
    update public.merchants
    set user_id = null,
        store_name = 'Toko ditutup',
        description = '',
        address = '',
        distance = '',
        lat = null,
        lng = null,
        logo_url = null,
        status = 'deleted',
        deleted_at = now()
    where id = v_merchant_id;
    update public.surprise_bags
    set status = 'inactive'
    where merchant_id = v_merchant_id and status = 'active';
  end if;

  delete from auth.users where id = v_uid;
  return jsonb_build_object('deleted', true, 'user_id', v_uid);
end
$$;

-- ---------------------------------------------------------------------------
-- RLS/public discovery alignment and explicit privileges
-- ---------------------------------------------------------------------------

-- RLS expressions use these narrow SECURITY DEFINER predicates instead of
-- querying profiles directly. This keeps profiles private while allowing anon
-- discovery policies to verify that a merchant owner is still active.
create or replace function public.current_account_is_active()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid() and p.deleted_at is null
  )
$$;

create or replace function public.merchant_is_public(p_merchant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1
    from public.merchants m
    join public.profiles p on p.id = m.user_id
    where m.id = p_merchant_id
      and m.status = 'active'
      and m.user_id is not null
      and p.deleted_at is null
  )
$$;

create or replace function public.current_user_owns_merchant(
  p_merchant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.merchants m
    where m.id = p_merchant_id and m.user_id = auth.uid()
  )
$$;

create or replace function public.current_user_ordered_bag(p_bag_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.orders o
    where o.bag_id = p_bag_id and o.consumer_id = auth.uid()
  )
$$;

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update
  using (auth.uid() = id and deleted_at is null)
  with check (auth.uid() = id and deleted_at is null);

drop policy if exists merchants_read on public.merchants;
create policy merchants_read on public.merchants for select using (
  public.merchant_is_public(id)
  or user_id = auth.uid()
);

drop policy if exists merchants_insert_owner on public.merchants;
create policy merchants_insert_owner on public.merchants for insert
  with check (
    auth.uid() = user_id
    and public.current_account_is_active()
  );

drop policy if exists merchants_update_owner on public.merchants;
create policy merchants_update_owner on public.merchants for update
  using (
    auth.uid() = user_id
    and public.current_account_is_active()
  )
  with check (
    auth.uid() = user_id
    and public.current_account_is_active()
  );

drop policy if exists bags_read on public.surprise_bags;
create policy bags_read on public.surprise_bags for select using (
  (
    status = 'active'
    and available_on <= (now() at time zone 'Asia/Jakarta')::date
    and (pickup_end_at is null or pickup_end_at > now())
    and public.merchant_is_public(merchant_id)
  )
  or public.current_user_owns_merchant(merchant_id)
  or public.current_user_ordered_bag(id)
);

drop policy if exists bags_insert_owner on public.surprise_bags;
create policy bags_insert_owner on public.surprise_bags for insert
  with check (
    merchant_id in (
      select m.id
      from public.merchants m
      where m.user_id = auth.uid()
    )
    and public.current_account_is_active()
  );

drop policy if exists bags_update_owner on public.surprise_bags;
create policy bags_update_owner on public.surprise_bags for update
  using (
    merchant_id in (
      select m.id
      from public.merchants m
      where m.user_id = auth.uid()
    )
    and public.current_account_is_active()
  )
  with check (
    merchant_id in (
      select m.id
      from public.merchants m
      where m.user_id = auth.uid()
    )
    and public.current_account_is_active()
  );

drop policy if exists favorites_self on public.favorites;
create policy favorites_self on public.favorites for all
  using (
    auth.uid() = consumer_id
    and public.current_account_is_active()
  )
  with check (
    auth.uid() = consumer_id
    and public.current_account_is_active()
  );

-- Phase-one deletion must still permit cleanup DELETEs, but it must prevent a
-- concurrent client from uploading or replacing an object after cleanup has
-- started. The existing storage_auth_delete policy is intentionally retained.
drop policy if exists storage_auth_write on storage.objects;
create policy storage_auth_write on storage.objects
for insert to authenticated with check (
  public.current_account_is_active()
  and bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(coalesce(storage.extension(name), ''))
      in ('jpg', 'jpeg', 'png', 'webp', 'heic', 'heif')
  and (
    bucket_id in ('avatars', 'store-logos')
    or exists (
      select 1 from public.merchants m where m.user_id = auth.uid()
    )
  )
);

drop policy if exists storage_auth_update on storage.objects;
create policy storage_auth_update on storage.objects
for update to authenticated using (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
) with check (
  public.current_account_is_active()
  and bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(coalesce(storage.extension(name), ''))
      in ('jpg', 'jpeg', 'png', 'webp', 'heic', 'heif')
  and (
    bucket_id in ('avatars', 'store-logos')
    or exists (
      select 1 from public.merchants m where m.user_id = auth.uid()
    )
  )
);

-- security_invoker views must only reference base columns granted to their
-- caller. Ownership liveness remains enforced by merchants_read RLS, avoiding
-- a need to expose merchants.user_id through either public view.
create or replace view public.public_merchants
with (security_invoker = true) as
select id, store_name, description, address, distance, lat, lng, category,
       open_time, close_time, logo_url, status, rating, review_count,
       bags_saved, created_at, updated_at
from public.merchants
where status = 'active';

create or replace view public.available_bags
with (security_invoker = true) as
select b.id, b.merchant_id, b.title, b.description, b.original_price,
       b.sale_price, b.quantity_total, b.quantity_left, b.pickup_window,
       b.image_url, b.contents, b.status, b.available_on,
       b.pickup_start_at, b.pickup_end_at, b.created_at, b.updated_at,
       m.store_name as merchant_name,
       m.category as merchant_category,
       m.address as merchant_address,
       m.distance as merchant_distance,
       m.lat as merchant_lat,
       m.lng as merchant_lng,
       m.open_time as merchant_open_time,
       m.close_time as merchant_close_time,
       m.logo_url as merchant_logo_url,
       m.rating as merchant_rating,
       m.review_count as merchant_review_count,
       m.bags_saved as merchant_bags_saved
from public.surprise_bags b
join public.merchants m
  on m.id = b.merchant_id and m.status = 'active'
where b.status = 'active'
  and b.available_on <= (now() at time zone 'Asia/Jakarta')::date
  and (b.pickup_end_at is null or b.pickup_end_at > now());

grant usage on schema public to anon, authenticated;
revoke all on public.public_merchants, public.available_bags
  from public, anon, authenticated;
grant select on public.public_merchants, public.available_bags
  to anon, authenticated;

revoke all on public.favorites from public, anon, authenticated;
grant select, delete on public.favorites to authenticated;
grant insert (consumer_id, merchant_id)
  on public.favorites to authenticated;

revoke all on function public.current_account_is_active()
  from public, anon;
grant execute on function public.current_account_is_active()
  to authenticated;

revoke all on function public.merchant_is_public(uuid)
  from public, anon, authenticated;
grant execute on function public.merchant_is_public(uuid)
  to anon, authenticated;

revoke all on function public.current_user_owns_merchant(uuid)
  from public, anon, authenticated;
grant execute on function public.current_user_owns_merchant(uuid)
  to anon, authenticated;

revoke all on function public.current_user_ordered_bag(uuid)
  from public, anon, authenticated;
grant execute on function public.current_user_ordered_bag(uuid)
  to anon, authenticated;

-- Default function EXECUTE is granted to PUBLIC by PostgreSQL, so every new
-- RPC is explicitly closed before the minimum role is granted.
revoke all on function public.publish_due_bag_notifications(integer)
  from public, anon, authenticated;
grant execute on function public.publish_due_bag_notifications(integer)
  to service_role;

revoke all on function public.get_bank_account_verification_data(uuid,text)
  from public, anon, authenticated;
grant execute on function public.get_bank_account_verification_data(uuid,text)
  to service_role;

revoke all on function public.get_payout_destination(uuid,text)
  from public, anon, authenticated;
grant execute on function public.get_payout_destination(uuid,text)
  to service_role;

revoke all on function public.prepare_delete_my_account()
  from public, anon;
grant execute on function public.prepare_delete_my_account()
  to authenticated;

revoke all on function public.register_bank_account(text,text,text,text)
  from public, anon;
revoke all on function public.set_default_bank_account(uuid)
  from public, anon;
revoke all on function public.request_withdrawal(uuid,integer,text)
  from public, anon;
revoke all on function public.verify_bank_account(uuid,text,text)
  from public, anon, authenticated;
revoke all on function public.delete_my_account()
  from public, anon;
grant execute on function public.register_bank_account(text,text,text,text)
  to authenticated;
grant execute on function public.set_default_bank_account(uuid)
  to authenticated;
grant execute on function public.request_withdrawal(uuid,integer,text)
  to authenticated;
grant execute on function public.verify_bank_account(uuid,text,text)
  to service_role;
grant execute on function public.delete_my_account()
  to authenticated;

comment on table private.bank_account_secrets is
  'Encrypted account-number vault. Never expose this table through the Data API.';
comment on table private.bank_secret_access_audit is
  'Append-only audit trail for service-role decryption of bank destinations.';
comment on function public.publish_due_bag_notifications(integer) is
  'Service-only scheduler that publishes deduplicated notifications for bags currently due in Jakarta.';
comment on function public.get_bank_account_verification_data(uuid,text) is
  'Service-only audited access to a decrypted bank destination for manual verification.';
comment on function public.get_payout_destination(uuid,text) is
  'Service-only audited access to an active manual payout destination.';
comment on function public.register_bank_account(text,text,text,text) is
  'Registers a masked public bank row and stores its full number encrypted in the private vault; hash includes bank_code.';
comment on function public.verify_bank_account(uuid,text,text) is
  'Service-only bank verification; verified accounts require a private vault entry and rejected secrets are erased.';
comment on function public.prepare_delete_my_account() is
  'Phase one: block new mutations and verify that no payout is active before client Storage cleanup.';
comment on function public.delete_my_account() is
  'Phase two: retry-safe final anonymization after prepare_delete_my_account and Storage cleanup.';

commit;
