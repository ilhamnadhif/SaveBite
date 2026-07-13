-- SaveBite: lifecycle and least-privilege follow-up.
-- Apply after 0008_simulation_safety.sql.

begin;

-- `preparing` became an active order state in 0004 and must expire just like
-- paid/ready orders. Rebuild the partial index so the cron query stays bounded.
drop index if exists public.orders_expiry_idx;
create index orders_expiry_idx
  on public.orders (expires_at)
  where status in ('paid', 'preparing', 'ready');

create or replace function public.expire_orders(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_count integer;
begin
  if session_user::text not in ('postgres', 'supabase_admin', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'limit must be between 1 and 5000';
  end if;

  with candidates as (
    select id
    from public.orders
    where status in ('paid', 'preparing', 'ready')
      and expires_at <= now()
    order by expires_at
    for update skip locked
    limit p_limit
  )
  update public.orders o
  set status = 'expired', expired_at = now()
  from candidates c
  where o.id = c.id;

  get diagnostics v_count = row_count;
  return v_count;
end
$$;

revoke all on function public.expire_orders(integer)
  from public, anon, authenticated;
grant execute on function public.expire_orders(integer) to service_role;

-- Narrow SECURITY DEFINER predicates let RLS and client-safe views determine
-- ownership without granting every authenticated user SELECT on user_id.
create or replace function public.current_user_has_merchant()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.merchants m
    where m.user_id = auth.uid() and m.deleted_at is null
  )
$$;

create or replace function public.get_my_merchant()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select to_jsonb(owned)
  from (
    select m.id, m.store_name, m.description, m.address, m.distance,
           m.lat, m.lng, m.category, m.open_time, m.close_time, m.logo_url,
           m.status, m.rating, m.review_count, m.bags_saved,
           m.created_at, m.updated_at, m.deleted_at
    from public.merchants m
    where m.user_id = auth.uid()
      and m.deleted_at is null
    limit 1
  ) owned
$$;

revoke all on function public.current_user_has_merchant()
  from public, anon, authenticated;
grant execute on function public.current_user_has_merchant() to authenticated;
revoke all on function public.get_my_merchant()
  from public, anon, authenticated;
grant execute on function public.get_my_merchant() to authenticated;

drop policy if exists bags_insert_owner on public.surprise_bags;
create policy bags_insert_owner on public.surprise_bags for insert
  with check (
    public.current_user_owns_merchant(merchant_id)
    and public.current_account_is_active()
  );

drop policy if exists bags_update_owner on public.surprise_bags;
create policy bags_update_owner on public.surprise_bags for update
  using (
    public.current_user_owns_merchant(merchant_id)
    and public.current_account_is_active()
  )
  with check (
    public.current_user_owns_merchant(merchant_id)
    and public.current_account_is_active()
  );

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select using (
  consumer_id = auth.uid()
  or public.current_user_owns_merchant(merchant_id)
);

drop policy if exists tx_owner_read on public.transactions;
create policy tx_owner_read on public.transactions for select using (
  trusted and public.current_user_owns_merchant(merchant_id)
);

drop policy if exists bank_accounts_owner_read on public.bank_accounts;
create policy bank_accounts_owner_read on public.bank_accounts for select using (
  public.current_user_owns_merchant(merchant_id)
);

drop policy if exists payout_requests_owner_read on public.payout_requests;
create policy payout_requests_owner_read on public.payout_requests for select using (
  public.current_user_owns_merchant(merchant_id)
);

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
    or public.current_user_has_merchant()
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
    or public.current_user_has_merchant()
  )
);

create or replace view public.merchant_orders
with (security_invoker = true) as
select o.id, o.id as order_id, o.order_reference,
       o.consumer_id, o.consumer_name,
       o.consumer_anonymized, o.merchant_id, o.bag_id, o.status, o.quantity,
       o.payment_method, o.created_at, o.updated_at, o.paid_at, o.ready_at,
       o.expires_at, o.redeemed_at, o.cancelled_at, o.expired_at,
       o.subtotal, o.service_fee, o.total_amount, o.commission_amount,
       o.merchant_net_amount,
       o.pickup_start_at, o.pickup_end_at,
       o.bag_title, o.bag_description, o.bag_image_url, o.unit_price,
       o.original_price_snapshot, o.pickup_window_snapshot,
       o.merchant_name_snapshot as merchant_name,
       o.merchant_category_snapshot as merchant_category,
       o.merchant_address_snapshot as merchant_address,
       o.merchant_logo_url_snapshot as merchant_logo_url,
       o.merchant_rating_snapshot as merchant_rating,
       o.merchant_review_count_snapshot as merchant_review_count
from public.orders o
where public.current_user_owns_merchant(o.merchant_id);

create or replace view public.my_bank_accounts
with (security_invoker = true) as
select id, merchant_id, bank_code, bank_name, account_holder,
       account_number_last4, status, is_default, created_at, updated_at
from public.bank_accounts
where public.current_user_owns_merchant(merchant_id);

create or replace view public.merchant_balance
with (security_invoker = true) as
select m.id as merchant_id,
       coalesce(sum(case t.kind
         when 'income' then t.amount
         when 'withdrawal' then -t.amount
         when 'withdrawal_reversal' then t.amount
         else 0 end), 0)::integer as available
from public.merchants m
left join public.transactions t on t.merchant_id = m.id and t.trusted
where public.current_user_owns_merchant(m.id)
group by m.id;

create or replace function public.get_my_merchant_reviews()
returns table (
  review_id uuid,
  order_id uuid,
  order_reference text,
  customer_name text,
  rating integer,
  tags text[],
  comment text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public, pg_catalog
as $$
  select
    r.id as review_id,
    r.order_id,
    o.order_reference,
    case
      when o.consumer_anonymized then 'Pelanggan'
      else coalesce(nullif(btrim(o.consumer_name), ''), 'Pelanggan')
    end as customer_name,
    r.rating,
    r.tags,
    r.comment,
    r.created_at
  from public.reviews r
  join public.orders o
    on o.id = r.order_id
   and o.merchant_id = r.merchant_id
  where public.current_user_owns_merchant(r.merchant_id)
  order by r.created_at desc, r.id desc
$$;

revoke all on function public.get_my_merchant_reviews()
  from public, anon, authenticated;
grant execute on function public.get_my_merchant_reviews() to authenticated;

-- A table-level SELECT grant overrides column restrictions. Remove it first,
-- then expose only the columns used by public discovery. Owners retrieve their
-- complete safe row through get_my_merchant().
revoke select on table public.merchants
  from public, anon, authenticated;
grant select (
  id, store_name, description, address, distance, lat, lng, category,
  open_time, close_time, logo_url, status, rating, review_count, bags_saved,
  created_at, updated_at
) on public.merchants to anon, authenticated;

-- A shared service-role credential has no reliable human subject. Require the
-- worker/operator to supply a stable actor label and preserve both that label
-- and all available database/JWT context on every plaintext access.
alter table private.bank_secret_access_audit
  add column if not exists actor_context jsonb not null default '{}'::jsonb;

create or replace function public.get_bank_account_verification_data(
  p_bank_account_id uuid,
  p_actor text,
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
  v_actor text := btrim(coalesce(p_actor, ''));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_subject text := nullif(auth.jwt() ->> 'sub', '');
begin
  perform private.require_service_role();
  if length(v_actor) not between 3 and 120 then
    raise exception 'audit actor must contain 3-120 characters';
  end if;
  if length(v_reason) not between 8 and 500 then
    raise exception 'audit reason must contain 8-500 characters';
  end if;

  select * into v_account
  from public.bank_accounts
  where id = p_bank_account_id and status = 'pending'
  for share;
  if not found then
    raise exception 'pending bank account not found';
  end if;

  select s.account_number_cipher into v_cipher
  from private.bank_account_secrets s
  where s.bank_account_id = v_account.id
  for share;
  if not found then
    raise exception 'bank account must be re-registered to restore its secret';
  end if;

  select text_value into v_key
  from private.app_settings
  where key = 'bank_encryption_key';
  if v_key is null then
    raise exception 'bank security configuration is unavailable';
  end if;
  v_number := extensions.pgp_sym_decrypt(v_cipher, v_key);

  insert into private.bank_secret_access_audit (
    bank_account_id, payout_request_id, purpose, reason,
    actor, actor_role, actor_context
  ) values (
    v_account.id,
    null,
    'verification',
    v_reason,
    coalesce(v_subject, v_actor),
    coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text),
    jsonb_strip_nulls(jsonb_build_object(
      'requested_actor', v_actor,
      'jwt_sub', v_subject,
      'jwt_role', nullif(auth.jwt() ->> 'role', ''),
      'session_user', session_user::text,
      'current_user', current_user::text,
      'client_address', inet_client_addr()::text
    ))
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
  p_actor text,
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
  v_actor text := btrim(coalesce(p_actor, ''));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_subject text := nullif(auth.jwt() ->> 'sub', '');
begin
  perform private.require_service_role();
  if length(v_actor) not between 3 and 120 then
    raise exception 'audit actor must contain 3-120 characters';
  end if;
  if length(v_reason) not between 8 and 500 then
    raise exception 'audit reason must contain 8-500 characters';
  end if;

  select * into v_request
  from public.payout_requests
  where id = p_request_id and status in ('requested', 'processing')
  for share;
  if not found then
    raise exception 'active payout request not found';
  end if;

  select * into v_account
  from public.bank_accounts
  where id = v_request.bank_account_id
    and merchant_id = v_request.merchant_id
    and status = 'verified'
  for share;
  if not found then
    raise exception 'verified payout destination not found';
  end if;

  select s.account_number_cipher into v_cipher
  from private.bank_account_secrets s
  where s.bank_account_id = v_account.id
  for share;
  if not found then
    raise exception 'bank account must be re-registered to restore its secret';
  end if;

  select text_value into v_key
  from private.app_settings
  where key = 'bank_encryption_key';
  if v_key is null then
    raise exception 'bank security configuration is unavailable';
  end if;
  v_number := extensions.pgp_sym_decrypt(v_cipher, v_key);

  insert into private.bank_secret_access_audit (
    bank_account_id, payout_request_id, purpose, reason,
    actor, actor_role, actor_context
  ) values (
    v_account.id,
    v_request.id,
    'payout',
    v_reason,
    coalesce(v_subject, v_actor),
    coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text),
    jsonb_strip_nulls(jsonb_build_object(
      'requested_actor', v_actor,
      'jwt_sub', v_subject,
      'jwt_role', nullif(auth.jwt() ->> 'role', ''),
      'session_user', session_user::text,
      'current_user', current_user::text,
      'client_address', inet_client_addr()::text
    ))
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

revoke all on function public.get_bank_account_verification_data(uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.get_bank_account_verification_data(uuid,text,text)
  to service_role;
revoke all on function public.get_payout_destination(uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.get_payout_destination(uuid,text,text)
  to service_role;

-- Remove the legacy overloads so callers cannot omit actor attribution.
drop function if exists public.get_bank_account_verification_data(uuid,text);
drop function if exists public.get_payout_destination(uuid,text);

comment on function public.get_my_merchant() is
  'Returns the signed-in owner merchant without exposing merchants.user_id.';
comment on function public.expire_orders(integer) is
  'Expires paid, preparing, and ready orders whose expires_at has elapsed; service role only.';
comment on function public.get_bank_account_verification_data(uuid,text,text) is
  'Service-only audited plaintext access for a pending bank-account verification; requires actor and reason.';
comment on function public.get_payout_destination(uuid,text,text) is
  'Service-only audited plaintext access for an active payout; requires actor and reason.';

commit;
