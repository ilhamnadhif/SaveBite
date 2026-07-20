-- SaveBite: authoritative Midtrans Snap payments.
--
-- The client may reserve an order and open a checkout, but it can never mark
-- money as paid.  Only the service-role RPC below may apply a status that was
-- fetched from Midtrans by an Edge Function.
-- Apply after 0011_backend_integrity.sql.

begin;

-- ---------------------------------------------------------------------------
-- Payment attempts and least-privilege reads
-- ---------------------------------------------------------------------------

create table public.payment_attempts (
  id uuid primary key default extensions.gen_random_uuid(),
  order_id uuid not null unique
    references public.orders(id) on delete cascade,
  consumer_id uuid references auth.users(id) on delete set null,
  merchant_id uuid not null
    references public.merchants(id),
  provider text not null default 'midtrans',
  provider_order_id text not null unique,
  expected_amount integer not null,
  currency text not null default 'IDR',
  idempotency_key text not null,
  requested_method text not null,
  status text not null default 'creating',
  provider_status text,
  fraud_status text,
  status_code text,
  provider_transaction_id text,
  payment_type text,
  snap_token text,
  redirect_url text,
  payment_expires_at timestamptz not null,
  checkout_lease_token text,
  checkout_lease_expires_at timestamptz,
  reservation_state text not null default 'held',
  reservation_release_reason text,
  stock_released_at timestamptz,
  stock_reacquired_at timestamptz,
  paid_at timestamptz,
  terminal_at timestamptz,
  last_provider_event_at timestamptz,
  last_synced_at timestamptz,
  requires_manual_review boolean not null default false,
  review_reason text,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_attempts_provider_check
    check (provider = 'midtrans'),
  constraint payment_attempts_provider_order_id_check
    check (
      length(provider_order_id) <= 50
      and provider_order_id ~ '^SB-[A-F0-9]{32}$'
    ),
  constraint payment_attempts_amount_check
    check (expected_amount > 0 and expected_amount <= 2000000000),
  constraint payment_attempts_currency_check
    check (currency = 'IDR'),
  constraint payment_attempts_idempotency_check
    check (length(idempotency_key) between 8 and 128),
  constraint payment_attempts_method_check
    check (length(btrim(requested_method)) between 1 and 64),
  constraint payment_attempts_status_check
    check (status in (
      'creating', 'checkout_created', 'pending', 'paid', 'failed',
      'cancelled', 'expired', 'refunded', 'partial_refund', 'disputed'
    )),
  constraint payment_attempts_reservation_check
    check (reservation_state in ('held', 'released', 'conflict')),
  constraint payment_attempts_release_reason_check
    check (
      reservation_release_reason is null
      or reservation_release_reason in (
        'payment_failed', 'payment_cancelled', 'payment_expired',
        'pickup_expired', 'refunded', 'disputed'
      )
    ),
  constraint payment_attempts_snap_pair_check
    check ((snap_token is null) = (redirect_url is null)),
  constraint payment_attempts_snap_length_check
    check (
      (snap_token is null or length(snap_token) between 8 and 4096)
      and (redirect_url is null or length(redirect_url) <= 2048)
    ),
  constraint payment_attempts_lease_pair_check
    check (
      (checkout_lease_token is null) =
      (checkout_lease_expires_at is null)
    ),
  constraint payment_attempts_expiry_check
    check (payment_expires_at > created_at),
  constraint payment_attempts_review_check
    check (
      not requires_manual_review
      or length(btrim(coalesce(review_reason, ''))) between 3 and 500
    )
);

create index payment_attempts_consumer_created_idx
  on public.payment_attempts (consumer_id, created_at desc);
create index payment_attempts_merchant_created_idx
  on public.payment_attempts (merchant_id, created_at desc);
create index payment_attempts_pending_expiry_idx
  on public.payment_attempts (payment_expires_at)
  where status in ('creating', 'checkout_created', 'pending');

create trigger t_payment_attempts_updated
before update on public.payment_attempts
for each row execute function public.touch_updated_at();

alter table public.payment_attempts enable row level security;

create policy payment_attempts_read_own
on public.payment_attempts
for select
using (consumer_id = auth.uid());

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
for select
using (
  consumer_id = auth.uid()
  or (
    public.current_user_owns_merchant(merchant_id)
    and payment_verified_at is not null
  )
);

revoke all on public.payment_attempts
  from public, anon, authenticated;
grant select (
  id, order_id, consumer_id, provider, provider_order_id, status,
  payment_type, payment_expires_at, last_synced_at,
  requires_manual_review, review_reason, created_at, updated_at
) on public.payment_attempts to authenticated;
grant all on public.payment_attempts to service_role;

create or replace function public.get_consumer_payment_projection(
  p_order_id uuid
)
returns table (
  payment_redirect_url text,
  status text,
  payment_expires_at timestamptz,
  payment_type text,
  provider_order_id text,
  requires_manual_review boolean
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select case
           when pa.status in ('creating', 'checkout_created', 'pending')
            and pa.payment_expires_at > now()
           then pa.redirect_url
           else null
         end,
         pa.status, pa.payment_expires_at, pa.payment_type,
         pa.provider_order_id, pa.requires_manual_review
  from public.payment_attempts pa
  join public.orders o on o.id = pa.order_id
  where pa.order_id = p_order_id and o.consumer_id = auth.uid()
$$;

revoke all on function public.get_consumer_payment_projection(uuid)
  from public, anon, authenticated;
grant execute on function public.get_consumer_payment_projection(uuid)
  to authenticated;

-- Merchant reads go through this narrow SECURITY DEFINER projection.  The
-- ownership predicate is mandatory, unverified attempts are omitted, and the
-- function can never return a Snap token or redirect URL.
create or replace function public.get_merchant_payment_projection(
  p_order_id uuid
)
returns table (
  status text,
  payment_expires_at timestamptz,
  payment_type text,
  provider_order_id text,
  requires_manual_review boolean
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select pa.status, pa.payment_expires_at, pa.payment_type,
         pa.provider_order_id, pa.requires_manual_review
  from public.payment_attempts pa
  join public.orders o on o.id = pa.order_id
  where pa.order_id = p_order_id
    and o.payment_verified_at is not null
    and public.current_user_owns_merchant(o.merchant_id)
$$;

revoke all on function public.get_merchant_payment_projection(uuid)
  from public, anon, authenticated;
grant execute on function public.get_merchant_payment_projection(uuid)
  to authenticated;

comment on table public.payment_attempts is
  'Server-managed Midtrans attempts. Snap tokens and checkout leases are never granted to clients.';
comment on column public.payment_attempts.status is
  'Effective app state. Raw Midtrans deny/failure is retained in provider_status while this remains pending so another Snap payment attempt may succeed.';
comment on column public.payment_attempts.provider_transaction_id is
  'Latest attempt transaction ID until payment is verified; changes after verified payment require manual review.';

-- 0008 could only mark simulation income untrusted; it intentionally had no
-- real gateway proof to promote a ledger row.  A redeemed order is now trusted
-- precisely when this migration's service-only payment verifier has populated
-- both verification fields and the money-safety trigger cleared simulation.
create or replace function private.mark_simulation_ledger_untrusted()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
declare
  v_is_verified boolean;
begin
  if new.kind = 'income' and new.reference_type = 'order' then
    select not o.is_simulation
       and o.payment_verified_at is not null
       and nullif(btrim(coalesce(o.payment_provider_reference, '')), '') is not null
    into v_is_verified
    from public.orders o
    where o.id = new.reference_id;

    if coalesce(v_is_verified, false) then
      new.trusted := true;
      new.metadata := coalesce(new.metadata, '{}'::jsonb)
        || jsonb_build_object('simulation', false, 'payment_verified', true);
    else
      new.trusted := false;
      new.subtitle := 'Simulasi — tidak dapat ditarik';
      new.metadata := coalesce(new.metadata, '{}'::jsonb)
        || jsonb_build_object('simulation', true, 'payment_verified', false);
    end if;
  end if;
  return new;
end
$$;

revoke all on function private.mark_simulation_ledger_untrusted()
  from public, anon, authenticated;

create or replace function private.reject_disabled_payouts()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
begin
  if private.setting_int('payouts_enabled') <> 1 then
    raise exception
      'payouts are disabled until provider reconciliation is fully enabled';
  end if;
  return new;
end
$$;

revoke all on function private.reject_disabled_payouts()
  from public, anon, authenticated;

-- Preserve the existing view column order, then append payment aliases used by
-- the Flutter mapper.  A redirect is visible only to its consumer and only
-- while the payment window is still live.
create or replace view public.consumer_orders
with (security_invoker = true) as
select o.id, o.id as order_id, o.order_reference,
       o.consumer_id, o.merchant_id, o.bag_id,
       o.status, o.quantity, o.payment_method, o.created_at, o.updated_at,
       o.paid_at, o.ready_at, o.expires_at, o.redeemed_at,
       o.cancelled_at, o.expired_at,
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
       o.merchant_review_count_snapshot as merchant_review_count,
       exists (select 1 from public.reviews r where r.order_id = o.id) as reviewed,
       (select r.id from public.reviews r where r.order_id = o.id limit 1) as review_id,
       pa.payment_redirect_url,
       pa.status as payment_status,
       pa.payment_expires_at,
       pa.payment_type,
       pa.provider_order_id as midtrans_order_id,
       o.payment_verified_at,
       pa.requires_manual_review as requires_payment_review
from public.orders o
left join lateral public.get_consumer_payment_projection(o.id) pa on true
where o.consumer_id = auth.uid();

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
       o.merchant_review_count_snapshot as merchant_review_count,
       null::text as payment_redirect_url,
       pa.status as payment_status,
       pa.payment_expires_at,
       pa.payment_type,
       pa.provider_order_id as midtrans_order_id,
       o.payment_verified_at,
       pa.requires_manual_review as requires_payment_review
from public.orders o
left join lateral public.get_merchant_payment_projection(o.id) pa on true
where public.current_user_owns_merchant(o.merchant_id)
  and o.payment_verified_at is not null;

grant select on public.consumer_orders, public.merchant_orders
  to authenticated;

-- ---------------------------------------------------------------------------
-- Atomic reservation.  Prices and all snapshots are computed by PostgreSQL.
-- ---------------------------------------------------------------------------

create or replace function public.purchase_bag(
  p_bag_id uuid,
  p_qty integer,
  p_method text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_bag public.surprise_bags;
  v_merchant public.merchants;
  v_order public.orders;
  v_existing public.orders;
  v_attempt public.payment_attempts;
  v_name text;
  v_fee integer := private.setting_int('service_fee');
  v_commission_bps integer := private.setting_int('merchant_commission_bps');
  v_subtotal integer;
  v_commission integer;
  v_expires_at timestamptz;
  v_payment_expires_at timestamptz;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform private.assert_account_active(v_uid);
  if private.setting_int('payments_enabled') <> 1 then
    raise exception 'payments are temporarily unavailable' using errcode = '55000';
  end if;
  if p_qty is null or p_qty < 1 or p_qty > 100 then
    raise exception 'quantity must be between 1 and 100';
  end if;
  if p_method is null or length(btrim(p_method)) not between 1 and 64 then
    raise exception 'invalid payment method';
  end if;
  if p_idempotency_key is null
     or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency key must contain 8-128 characters';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_uid::text || ':' || p_idempotency_key, 0)
  );

  select * into v_existing
  from public.orders
  where consumer_id = v_uid and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.bag_id <> p_bag_id
       or v_existing.quantity <> p_qty
       or v_existing.payment_method <> btrim(p_method) then
      raise exception
        'idempotency key was already used with different parameters';
    end if;
    select * into v_attempt
    from public.payment_attempts
    where order_id = v_existing.id;
    return (to_jsonb(v_existing) - 'pickup_token_hash' - 'pickup_code')
      || jsonb_build_object(
        'order_id', v_existing.id,
        'pickup_code', null,
        'payment_status', v_attempt.status,
        'payment_redirect_url', case
          when v_attempt.status in ('creating', 'checkout_created', 'pending')
           and v_attempt.payment_expires_at > now()
          then v_attempt.redirect_url
          else null end,
        'payment_expires_at', v_attempt.payment_expires_at,
        'payment_type', v_attempt.payment_type,
        'midtrans_order_id', v_attempt.provider_order_id
      );
  end if;

  select * into v_bag
  from public.surprise_bags
  where id = p_bag_id
  for update;
  if not found then raise exception 'bag not found'; end if;

  select * into v_merchant
  from public.merchants
  where id = v_bag.merchant_id;
  if not found or v_merchant.status <> 'active'
     or v_merchant.user_id is null then
    raise exception 'merchant is unavailable';
  end if;
  if v_bag.status <> 'active' then raise exception 'bag is not active'; end if;
  if v_bag.available_on > v_today then
    raise exception 'bag is not available yet';
  end if;
  if v_bag.pickup_end_at is not null and v_bag.pickup_end_at <= now() then
    raise exception 'pickup window has ended';
  end if;
  if v_bag.quantity_left < p_qty then raise exception 'insufficient stock'; end if;

  v_subtotal := v_bag.sale_price * p_qty;
  v_commission := round(v_subtotal * v_commission_bps / 10000.0)::integer;
  v_expires_at := case
    when v_bag.pickup_end_at is not null then v_bag.pickup_end_at
    else now() + interval '72 hours'
  end;
  v_payment_expires_at := least(now() + interval '15 minutes', v_expires_at);
  select name into v_name from public.profiles where id = v_uid;

  update public.surprise_bags
  set quantity_left = quantity_left - p_qty,
      status = case when quantity_left - p_qty = 0 then 'sold_out' else status end
  where id = p_bag_id;

  insert into public.orders (
    consumer_id, consumer_name, bag_id, merchant_id, quantity,
    subtotal, service_fee, total_amount, unit_price, original_price_snapshot,
    commission_amount, merchant_net_amount, payment_method, status,
    pickup_code,
    bag_title, bag_description, bag_image_url, pickup_window_snapshot,
    merchant_name_snapshot, merchant_category_snapshot,
    merchant_address_snapshot, merchant_logo_url_snapshot,
    merchant_rating_snapshot, merchant_review_count_snapshot,
    pickup_start_at, pickup_end_at, expires_at, paid_at, idempotency_key
  ) values (
    v_uid, coalesce(v_name, 'Pelanggan'), v_bag.id, v_bag.merchant_id, p_qty,
    v_subtotal, v_fee, v_subtotal + v_fee, v_bag.sale_price,
    v_bag.original_price, v_commission, v_subtotal - v_commission,
    btrim(p_method), 'pending', null,
    v_bag.title, v_bag.description, v_bag.image_url, v_bag.pickup_window,
    v_merchant.store_name, v_merchant.category, v_merchant.address,
    v_merchant.logo_url, v_merchant.rating, v_merchant.review_count,
    v_bag.pickup_start_at, v_bag.pickup_end_at, v_expires_at, null,
    p_idempotency_key
  ) returning * into v_order;

  insert into public.payment_attempts (
    order_id, consumer_id, merchant_id, provider_order_id, expected_amount,
    idempotency_key, requested_method, status, payment_expires_at
  ) values (
    v_order.id, v_uid, v_order.merchant_id,
    'SB-' || upper(replace(v_order.id::text, '-', '')),
    v_order.total_amount, p_idempotency_key, btrim(p_method), 'creating',
    v_payment_expires_at
  ) returning * into v_attempt;

  return (to_jsonb(v_order) - 'pickup_token_hash' - 'pickup_code')
    || jsonb_build_object(
      'order_id', v_order.id,
      'pickup_code', null,
      'payment_status', v_attempt.status,
      'payment_redirect_url', null,
      'payment_expires_at', v_attempt.payment_expires_at,
      'payment_type', null,
      'midtrans_order_id', v_attempt.provider_order_id
    );
end
$$;

revoke all on function public.purchase_bag(uuid,integer,text,text)
  from public, anon, authenticated;
grant execute on function public.purchase_bag(uuid,integer,text,text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Checkout creation leases.  All three functions are service-role only.
-- ---------------------------------------------------------------------------

create or replace function public.claim_midtrans_checkout(
  p_order_id uuid,
  p_consumer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_order public.orders;
  v_attempt public.payment_attempts;
  v_lease text;
  v_email text;
  v_phone text;
begin
  perform private.require_service_role();
  if p_order_id is null or p_consumer_id is null then
    raise exception 'order not found';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found or v_order.consumer_id is distinct from p_consumer_id then
    raise exception 'order not found';
  end if;

  select * into v_attempt
  from public.payment_attempts
  where order_id = v_order.id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;

  if v_order.payment_verified_at is not null then
    return jsonb_build_object(
      'mode', 'completed', 'order_id', v_order.id,
      'payment_status', v_attempt.status
    );
  end if;
  if v_order.status <> 'pending'
     or v_attempt.status in (
       'failed', 'cancelled', 'expired', 'refunded', 'partial_refund',
       'disputed'
     ) then
    return jsonb_build_object(
      'mode', 'completed', 'order_id', v_order.id,
      'payment_status', v_attempt.status
    );
  end if;
  if v_attempt.payment_expires_at <= now() then
    raise exception 'payment reservation has expired';
  end if;
  if v_attempt.snap_token is not null and v_attempt.redirect_url is not null then
    return jsonb_build_object(
      'mode', 'reuse',
      'order_id', v_order.id,
      'payment_status', v_attempt.status,
      'redirect_url', v_attempt.redirect_url
    );
  end if;
  if v_attempt.checkout_lease_expires_at is not null
     and v_attempt.checkout_lease_expires_at > now() then
    return jsonb_build_object(
      'mode', 'in_progress', 'order_id', v_order.id,
      'payment_status', v_attempt.status
    );
  end if;

  v_lease := encode(extensions.gen_random_bytes(24), 'hex');
  update public.payment_attempts
  set status = 'creating',
      checkout_lease_token = v_lease,
      checkout_lease_expires_at = now() + interval '2 minutes',
      last_error_code = null
  where id = v_attempt.id
  returning * into v_attempt;

  select p.email, p.phone into v_email, v_phone
  from public.profiles p where p.id = v_order.consumer_id;

  return jsonb_build_object(
    'mode', 'create',
    'lease_token', v_lease,
    'order_id', v_order.id,
    'midtrans_order_id', v_attempt.provider_order_id,
    'gross_amount', v_attempt.expected_amount,
    'payment_expires_at', v_attempt.payment_expires_at,
    'requested_method', v_attempt.requested_method,
    'customer', jsonb_build_object(
      'first_name', left(coalesce(nullif(btrim(v_order.consumer_name), ''), 'Pelanggan'), 255),
      'email', nullif(left(btrim(coalesce(v_email, '')), 255), ''),
      'phone', nullif(left(btrim(coalesce(v_phone, '')), 32), '')
    ),
    'items', jsonb_build_array(
      jsonb_build_object(
        'id', 'bag-' || left(replace(v_order.bag_id::text, '-', ''), 32),
        'price', v_order.unit_price,
        'quantity', v_order.quantity,
        'name', left(v_order.bag_title, 50)
      )
    ) || case
      when v_order.service_fee > 0 then jsonb_build_array(
        jsonb_build_object(
          'id', 'service-fee', 'price', v_order.service_fee,
          'quantity', 1, 'name', 'Biaya layanan'
        )
      )
      else '[]'::jsonb
    end
  );
end
$$;

create or replace function public.complete_midtrans_checkout(
  p_order_id uuid,
  p_lease_token text,
  p_snap_token text,
  p_redirect_url text
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  perform private.require_service_role();
  if p_snap_token is null or length(p_snap_token) not between 8 and 4096 then
    raise exception 'invalid Snap token';
  end if;
  if p_redirect_url is null or length(p_redirect_url) > 2048
     or p_redirect_url !~ '^https://(app\.)?(sandbox\.)?midtrans\.com/' then
    raise exception 'invalid Midtrans redirect URL';
  end if;

  update public.payment_attempts
  set snap_token = p_snap_token,
      redirect_url = p_redirect_url,
      status = case
        when status in ('creating', 'pending') then 'checkout_created'
        else status end,
      checkout_lease_token = null,
      checkout_lease_expires_at = null,
      last_error_code = null
  where order_id = p_order_id
    and checkout_lease_token = p_lease_token;
  if not found then
    raise exception 'checkout lease is no longer valid' using errcode = '55000';
  end if;
end
$$;

create or replace function public.fail_midtrans_checkout(
  p_order_id uuid,
  p_lease_token text,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  perform private.require_service_role();
  update public.payment_attempts
  set status = case when status = 'creating' then 'pending' else status end,
      checkout_lease_token = null,
      checkout_lease_expires_at = null,
      last_error_code = left(coalesce(nullif(btrim(p_error_code), ''), 'gateway_error'), 100)
  where order_id = p_order_id
    and checkout_lease_token = p_lease_token;
end
$$;

create or replace function public.get_midtrans_sync_target(
  p_order_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_order public.orders;
  v_attempt public.payment_attempts;
  v_owner uuid;
  v_actor_kind text;
begin
  perform private.require_service_role();
  select * into v_order from public.orders where id = p_order_id;
  if not found then raise exception 'order not found'; end if;
  select * into v_attempt
  from public.payment_attempts where order_id = v_order.id;
  if not found then raise exception 'payment attempt not found'; end if;

  if v_order.consumer_id = p_actor_id then
    v_actor_kind := 'consumer';
  else
    select user_id into v_owner
    from public.merchants where id = v_order.merchant_id;
    if v_owner is distinct from p_actor_id
       or v_order.payment_verified_at is null then
      raise exception 'order not found';
    end if;
    v_actor_kind := 'merchant';
  end if;

  return jsonb_build_object(
    'order_id', v_order.id,
    'actor_kind', v_actor_kind,
    'midtrans_order_id', v_attempt.provider_order_id,
    'payment_status', v_attempt.status,
    'payment_expires_at', v_attempt.payment_expires_at
  );
end
$$;

revoke all on function public.claim_midtrans_checkout(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.complete_midtrans_checkout(uuid,text,text,text)
  from public, anon, authenticated;
revoke all on function public.fail_midtrans_checkout(uuid,text,text)
  from public, anon, authenticated;
revoke all on function public.get_midtrans_sync_target(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.claim_midtrans_checkout(uuid,uuid)
  to service_role;
grant execute on function public.complete_midtrans_checkout(uuid,text,text,text)
  to service_role;
grant execute on function public.fail_midtrans_checkout(uuid,text,text)
  to service_role;
grant execute on function public.get_midtrans_sync_target(uuid,uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- Reservation helpers and the sole payment-state writer
-- ---------------------------------------------------------------------------

create or replace function private.release_midtrans_reservation(
  p_attempt_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_attempt public.payment_attempts;
  v_order public.orders;
begin
  if p_reason is null or p_reason not in (
    'payment_failed', 'payment_cancelled', 'payment_expired',
    'pickup_expired', 'refunded', 'disputed'
  ) then
    raise exception 'invalid reservation release reason';
  end if;

  select * into v_attempt
  from public.payment_attempts
  where id = p_attempt_id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;
  if v_attempt.reservation_state <> 'held' then return false; end if;

  select * into v_order
  from public.orders
  where id = v_attempt.order_id
  for update;
  if not found then raise exception 'order not found'; end if;

  update public.surprise_bags b
  set quantity_left = least(
        b.quantity_total,
        b.quantity_left + v_order.quantity
      ),
      status = case
        when b.status = 'inactive' then 'inactive'
        when b.available_on < (now() at time zone 'Asia/Jakarta')::date
          then 'inactive'
        when b.pickup_end_at is not null and b.pickup_end_at <= now()
          then 'inactive'
        when least(b.quantity_total, b.quantity_left + v_order.quantity) = 0
          then 'sold_out'
        else 'active'
      end,
      updated_at = now()
  where b.id = v_order.bag_id;
  if not found then raise exception 'bag not found for order'; end if;

  update public.payment_attempts
  set reservation_state = 'released',
      reservation_release_reason = p_reason,
      stock_released_at = coalesce(stock_released_at, now())
  where id = v_attempt.id
    and reservation_state = 'held';
  return found;
end
$$;

create or replace function private.reacquire_midtrans_reservation(
  p_attempt_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_attempt public.payment_attempts;
  v_order public.orders;
  v_bag public.surprise_bags;
begin
  select * into v_attempt
  from public.payment_attempts
  where id = p_attempt_id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;
  if v_attempt.reservation_state = 'held' then return true; end if;
  if v_attempt.reservation_state <> 'released'
     or v_attempt.reservation_release_reason not in (
       'payment_failed', 'payment_cancelled', 'payment_expired'
     ) then
    return false;
  end if;

  select * into v_order
  from public.orders
  where id = v_attempt.order_id
  for update;
  if not found then raise exception 'order not found'; end if;
  if v_order.expires_at <= now() then return false; end if;

  select * into v_bag
  from public.surprise_bags
  where id = v_order.bag_id
  for update;
  if not found
     or v_bag.status <> 'active'
     or v_bag.available_on > (now() at time zone 'Asia/Jakarta')::date
     or (v_bag.pickup_end_at is not null and v_bag.pickup_end_at <= now())
     or v_bag.quantity_left < v_order.quantity then
    update public.payment_attempts
    set reservation_state = 'conflict',
        requires_manual_review = true,
        review_reason = 'paid_after_reservation_unavailable'
    where id = v_attempt.id;
    return false;
  end if;

  update public.surprise_bags
  set quantity_left = quantity_left - v_order.quantity,
      status = case
        when quantity_left - v_order.quantity = 0 then 'sold_out'
        else status end,
      updated_at = now()
  where id = v_bag.id;

  update public.payment_attempts
  set reservation_state = 'held',
      reservation_release_reason = null,
      stock_reacquired_at = now()
  where id = v_attempt.id;
  return true;
end
$$;

-- A refund/chargeback discovered after pickup cannot restore consumed food.
-- Instead, append one conservative, immutable balance hold against the trusted
-- income.  The existing `withdrawal` kind is intentionally reused so all
-- balance calculations and the current Flutter mapper treat it as a debit.
create or replace function private.hold_redeemed_order_income(
  p_order_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_order public.orders;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found or v_order.status <> 'redeemed'
     or v_order.is_simulation
     or v_order.payment_verified_at is null then
    return false;
  end if;
  if not exists (
    select 1 from public.transactions t
    where t.reference_type = 'order'
      and t.reference_id = v_order.id
      and t.kind = 'income'
      and t.trusted
  ) then
    return false;
  end if;

  insert into public.transactions (
    merchant_id, title, subtitle, amount, kind, reference_type,
    reference_id, idempotency_key, metadata, trusted
  ) values (
    v_order.merchant_id,
    'Penyesuaian ' || v_order.order_reference,
    'Saldo ditahan untuk rekonsiliasi pembayaran',
    v_order.merchant_net_amount,
    'withdrawal', 'order_adjustment', v_order.id,
    'order-adjustment:' || v_order.id,
    jsonb_build_object(
      'order_id', v_order.id,
      'reason', left(coalesce(nullif(btrim(p_reason), ''), 'payment_dispute'), 100),
      'automatic_hold', true
    ),
    true
  )
  on conflict (reference_type, reference_id, kind)
    where reference_type is not null and reference_id is not null
    do nothing;
  return found;
end
$$;

revoke all on function private.release_midtrans_reservation(uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function private.reacquire_midtrans_reservation(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.hold_redeemed_order_income(uuid,text)
  from public, anon, authenticated, service_role;

create or replace function public.apply_midtrans_payment_status(
  p_provider_order_id text,
  p_transaction_status text,
  p_fraud_status text,
  p_status_code text,
  p_gross_amount text,
  p_transaction_id text,
  p_payment_type text,
  p_provider_event_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_order_id uuid;
  v_order public.orders;
  v_attempt public.payment_attempts;
  v_status text := lower(btrim(coalesce(p_transaction_status, '')));
  v_fraud text := lower(btrim(coalesce(p_fraud_status, '')));
  v_transaction_id text := nullif(btrim(coalesce(p_transaction_id, '')), '');
  v_payment_type text := nullif(left(btrim(coalesce(p_payment_type, '')), 100), '');
  v_is_paid boolean;
  v_reacquired boolean;
  v_effective text;
  v_release_reason text;
begin
  perform private.require_service_role();

  if p_provider_order_id is null or length(p_provider_order_id) > 50 then
    raise exception 'invalid provider order ID';
  end if;
  if v_status not in (
    'pending', 'authorize', 'capture', 'settlement', 'deny', 'failure',
    'cancel', 'expire', 'refund', 'partial_refund', 'chargeback',
    'partial_chargeback'
  ) then
    raise exception 'unsupported Midtrans transaction status';
  end if;
  if p_status_code is null or p_status_code !~ '^[0-9]{3}$' then
    raise exception 'invalid Midtrans status code';
  end if;
  if p_gross_amount is null
     or p_gross_amount !~ '^[0-9]+([.][0-9]{1,2})?$' then
    raise exception 'invalid Midtrans gross amount';
  end if;

  select pa.order_id into v_order_id
  from public.payment_attempts pa
  where pa.provider_order_id = p_provider_order_id;
  if not found then raise exception 'payment attempt not found'; end if;

  -- Global lock order is order -> attempt -> bag.  Webhook, status refresh, and
  -- expiry therefore serialize without double-restoring a reservation.
  select * into v_order
  from public.orders
  where id = v_order_id
  for update;
  select * into v_attempt
  from public.payment_attempts
  where id = (select id from public.payment_attempts
              where provider_order_id = p_provider_order_id)
  for update;

  if p_gross_amount::numeric <> v_attempt.expected_amount::numeric then
    update public.payment_attempts
    set requires_manual_review = true,
        review_reason = 'provider_amount_mismatch',
        last_synced_at = now()
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false, 'reason', 'amount_mismatch',
      'order_id', v_order.id, 'payment_status', v_attempt.status,
      'order_status', v_order.status, 'requires_manual_review', true
    );
  end if;

  -- A slower request must not replay an older provider snapshot over a newer
  -- one.  Refund/dispute transitions are still handled when timestamps match.
  if p_provider_event_at is not null
     and v_attempt.last_provider_event_at is not null
     and p_provider_event_at < v_attempt.last_provider_event_at then
    update public.payment_attempts
    set last_synced_at = now()
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false, 'reason', 'stale_provider_event',
      'order_id', v_order.id, 'payment_status', v_attempt.status,
      'order_status', v_order.status,
      'requires_manual_review', v_attempt.requires_manual_review
    );
  end if;

  -- Different transaction IDs are normal for retryable attempts on the same
  -- Snap order.  They become suspicious only after a successful payment has
  -- already been recorded (and only after stale snapshots were discarded).
  if (v_order.payment_verified_at is not null
      or v_attempt.status in ('paid', 'refunded', 'partial_refund', 'disputed'))
     and v_attempt.provider_transaction_id is not null
     and v_transaction_id is not null
     and v_attempt.provider_transaction_id <> v_transaction_id then
    update public.payment_attempts
    set requires_manual_review = true,
        review_reason = 'provider_transaction_id_changed',
        last_synced_at = now()
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false, 'reason', 'transaction_id_conflict',
      'order_id', v_order.id, 'payment_status', v_attempt.status,
      'order_status', v_order.status, 'requires_manual_review', true
    );
  end if;

  v_is_paid := v_status = 'settlement'
    or (v_status = 'capture' and v_fraud = 'accept');

  -- One Snap order may contain multiple customer payment attempts.  Midtrans
  -- can report an early deny/failure (with its own transaction_id) and later a
  -- successful attempt on another channel.  Until money is verified, those
  -- events are diagnostic only: keep the reservation and effective `pending`
  -- state.  Provider cancel/expire or the local payment deadline is terminal.
  if v_status in ('deny', 'failure')
     and v_order.payment_verified_at is null
     and v_attempt.status not in ('refunded', 'partial_refund', 'disputed') then
    update public.payment_attempts
    set status = case
          when status in ('creating', 'checkout_created', 'pending', 'failed')
            then 'pending'
          else status end,
        provider_status = v_status,
        fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
        provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
        payment_type = coalesce(v_payment_type, payment_type),
        last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
        last_synced_at = now(),
        last_error_code = 'provider_attempt_' || v_status
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', true, 'reason', 'retryable_snap_attempt',
      'order_id', v_order.id,
      'payment_status', case
        when v_attempt.status in ('creating', 'checkout_created', 'pending', 'failed')
          then 'pending' else v_attempt.status end,
      'order_status', v_order.status,
      'requires_manual_review', v_attempt.requires_manual_review
    );
  end if;

  if v_attempt.status = 'disputed' and v_status = 'partial_refund' then
    update public.payment_attempts set last_synced_at = now()
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false, 'reason', 'dispute_state_preserved',
      'order_id', v_order.id, 'payment_status', v_attempt.status,
      'order_status', v_order.status, 'requires_manual_review', true
    );
  end if;
  if v_attempt.status = 'refunded' and v_status = 'partial_refund' then
    update public.payment_attempts set last_synced_at = now()
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false, 'reason', 'full_refund_preserved',
      'order_id', v_order.id, 'payment_status', v_attempt.status,
      'order_status', v_order.status,
      'requires_manual_review', v_attempt.requires_manual_review
    );
  end if;

  -- Full refunds are absorbing.  They restore only an unconsumed reservation;
  -- redeemed food is historical and therefore cannot be put back into stock.
  if v_status = 'refund' then
    if v_order.status <> 'redeemed' then
      perform private.release_midtrans_reservation(v_attempt.id, 'refunded');
      update public.orders
      set status = 'refunded',
          payment_verified_at = coalesce(payment_verified_at, now()),
          payment_provider_reference = coalesce(
            payment_provider_reference, v_transaction_id,
            v_attempt.provider_order_id
          ),
          pickup_token_hash = null,
          pickup_code_hint = null,
          pickup_token_issued_at = null,
          pickup_token_expires_at = null,
          updated_at = now()
      where id = v_order.id;
    else
      update public.orders
      set payment_verified_at = coalesce(payment_verified_at, now()),
          payment_provider_reference = coalesce(
            payment_provider_reference, v_transaction_id,
            v_attempt.provider_order_id
          ),
          updated_at = now()
      where id = v_order.id;
    end if;
    if v_order.status = 'redeemed' then
      perform private.hold_redeemed_order_income(v_order.id, v_status);
      perform public.enqueue_notification(
        v_order.consumer_id, 'Pembayaran dikembalikan',
        'Pengembalian dana setelah pengambilan sedang direkonsiliasi.',
        'payment', 'order:' || v_order.id || ':refunded',
        'order', v_order.id, jsonb_build_object('status', 'refunded')
      );
      perform public.enqueue_notification(
        (select user_id from public.merchants where id = v_order.merchant_id),
        'Saldo pesanan ditahan',
        'Refund setelah pengambilan memerlukan rekonsiliasi.',
        'payment', 'merchant-order:' || v_order.id || ':payment-review',
        'order', v_order.id, jsonb_build_object('status', 'refunded')
      );
    end if;
    update public.payment_attempts
    set status = 'refunded', provider_status = v_status,
        fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
        provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
        payment_type = coalesce(v_payment_type, payment_type),
        terminal_at = coalesce(terminal_at, now()),
        last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
        last_synced_at = now(),
        requires_manual_review = requires_manual_review or v_order.status = 'redeemed',
        review_reason = case when v_order.status = 'redeemed'
          then 'refund_after_redemption' else review_reason end
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', true, 'order_id', v_order.id,
      'payment_status', 'refunded',
      'order_status', case when v_order.status = 'redeemed' then 'redeemed' else 'refunded' end,
      'requires_manual_review', v_order.status = 'redeemed'
    );
  end if;

  -- Partial refunds and chargebacks cannot be converted into an invented local
  -- payout/refund.  Stop unfulfilled pickup and require an operator decision.
  if v_status in ('partial_refund', 'chargeback', 'partial_chargeback') then
    if v_order.status <> 'redeemed' then
      perform private.release_midtrans_reservation(v_attempt.id, 'disputed');
      update public.orders
      set status = 'cancelled',
          cancelled_at = coalesce(cancelled_at, now()),
          payment_verified_at = coalesce(payment_verified_at, now()),
          payment_provider_reference = coalesce(
            payment_provider_reference, v_transaction_id,
            v_attempt.provider_order_id
          ),
          pickup_token_hash = null,
          pickup_code_hint = null,
          pickup_token_issued_at = null,
          pickup_token_expires_at = null,
          updated_at = now()
      where id = v_order.id;
    end if;
    if v_order.status = 'redeemed' then
      perform private.hold_redeemed_order_income(v_order.id, v_status);
      perform public.enqueue_notification(
        v_order.consumer_id, 'Pembayaran perlu ditinjau',
        'Ada perubahan pembayaran setelah pesanan diambil.',
        'payment', 'order:' || v_order.id || ':payment-review',
        'order', v_order.id, jsonb_build_object('status', 'disputed')
      );
      perform public.enqueue_notification(
        (select user_id from public.merchants where id = v_order.merchant_id),
        'Saldo pesanan ditahan',
        'Perubahan pembayaran memerlukan rekonsiliasi.',
        'payment', 'merchant-order:' || v_order.id || ':payment-review',
        'order', v_order.id, jsonb_build_object('status', 'disputed')
      );
    end if;
    -- The current client has no trustworthy partial-refund fulfilment state;
    -- expose it as disputed so it cannot be mistaken for an ordinary success.
    v_effective := 'disputed';
    update public.payment_attempts
    set status = v_effective, provider_status = v_status,
        fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
        provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
        payment_type = coalesce(v_payment_type, payment_type),
        terminal_at = coalesce(terminal_at, now()),
        last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
        last_synced_at = now(), requires_manual_review = true,
        review_reason = case
          when v_status = 'partial_refund' then 'partial_refund_requires_reconciliation'
          else 'chargeback_requires_reconciliation' end
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', true, 'order_id', v_order.id,
      'payment_status', v_effective,
      'order_status', case when v_order.status = 'redeemed' then 'redeemed' else 'cancelled' end,
      'requires_manual_review', true
    );
  end if;

  if v_is_paid then
    -- Refund/dispute states are absorbing against a late settlement snapshot.
    if v_attempt.status in ('refunded', 'partial_refund', 'disputed') then
      update public.payment_attempts set last_synced_at = now()
      where id = v_attempt.id;
      return jsonb_build_object(
        'applied', false, 'reason', 'terminal_state_preserved',
        'order_id', v_order.id, 'payment_status', v_attempt.status,
        'order_status', v_order.status,
        'requires_manual_review', v_attempt.requires_manual_review
      );
    end if;

    -- Capture(accept) followed by settlement is an ordinary upgrade, not a new
    -- reservation.  It must also not resurrect a pickup-expired order.
    if v_attempt.status = 'paid' and v_order.payment_verified_at is not null then
      update public.payment_attempts
      set provider_status = v_status,
          fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
          provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
          payment_type = coalesce(v_payment_type, payment_type),
          last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
          last_synced_at = now()
      where id = v_attempt.id;
      return jsonb_build_object(
        'applied', true, 'reason', 'paid_state_refreshed',
        'order_id', v_order.id, 'payment_status', 'paid',
        'order_status', v_order.status,
        'requires_manual_review', v_attempt.requires_manual_review
      );
    end if;

    v_reacquired := private.reacquire_midtrans_reservation(v_attempt.id);
    if not v_reacquired then
      update public.orders
      set status = case when status = 'pending' then 'cancelled' else status end,
          cancelled_at = case when status = 'pending'
            then coalesce(cancelled_at, now()) else cancelled_at end,
          payment_verified_at = coalesce(payment_verified_at, now()),
          payment_provider_reference = coalesce(
            payment_provider_reference, v_transaction_id,
            v_attempt.provider_order_id
          ),
          updated_at = now()
      where id = v_order.id;
      update public.payment_attempts
      set status = 'disputed', provider_status = v_status,
          fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
          provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
          payment_type = coalesce(v_payment_type, payment_type),
          paid_at = coalesce(paid_at, now()),
          terminal_at = coalesce(terminal_at, now()),
          last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
          last_synced_at = now(), requires_manual_review = true,
          review_reason = 'paid_after_reservation_unavailable'
      where id = v_attempt.id;
      return jsonb_build_object(
        'applied', true, 'order_id', v_order.id,
        'payment_status', 'disputed',
        'order_status', case when v_order.status = 'pending' then 'cancelled' else v_order.status end,
        'requires_manual_review', true
      );
    end if;

    update public.orders
    set status = case
          when status in ('preparing', 'ready', 'redeemed') then status
          else 'paid' end,
        paid_at = coalesce(paid_at, now()),
        cancelled_at = case when status in ('cancelled', 'expired')
          then null else cancelled_at end,
        expired_at = case when status in ('cancelled', 'expired')
          then null else expired_at end,
        payment_verified_at = coalesce(payment_verified_at, now()),
        payment_provider_reference = coalesce(
          payment_provider_reference, v_transaction_id,
          v_attempt.provider_order_id
        ),
        updated_at = now()
    where id = v_order.id;
    update public.payment_attempts
    set status = 'paid', provider_status = v_status,
        fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
        provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
        payment_type = coalesce(v_payment_type, payment_type),
        paid_at = coalesce(paid_at, now()), terminal_at = null,
        checkout_lease_token = null, checkout_lease_expires_at = null,
        last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
        last_synced_at = now(), last_error_code = null,
        requires_manual_review = case
          when review_reason = 'capture_requires_fraud_accept' then false
          else requires_manual_review end,
        review_reason = case
          when review_reason = 'capture_requires_fraud_accept' then null
          else review_reason end
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', true, 'order_id', v_order.id,
      'payment_status', 'paid',
      'order_status', case when v_order.status in ('preparing', 'ready', 'redeemed')
        then v_order.status else 'paid' end,
      'requires_manual_review', case
        when v_attempt.review_reason = 'capture_requires_fraud_accept'
          then false else v_attempt.requires_manual_review end
    );
  end if;

  -- A challenged capture is not paid.  It remains pending until Midtrans says
  -- fraud_status=accept or returns settlement.
  if v_status in ('pending', 'authorize', 'capture') then
    if v_attempt.status in (
      'paid', 'failed', 'cancelled', 'expired', 'refunded',
      'partial_refund', 'disputed'
    ) then
      update public.payment_attempts set last_synced_at = now()
      where id = v_attempt.id;
      return jsonb_build_object(
        'applied', false, 'reason', 'effective_state_preserved',
        'order_id', v_order.id, 'payment_status', v_attempt.status,
        'order_status', v_order.status,
        'requires_manual_review', v_attempt.requires_manual_review
      );
    end if;
    update public.payment_attempts
    set status = 'pending', provider_status = v_status,
        fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
        provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
        payment_type = coalesce(v_payment_type, payment_type),
        checkout_lease_token = null, checkout_lease_expires_at = null,
        last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
        last_synced_at = now(),
        requires_manual_review = requires_manual_review
          or (v_status = 'capture' and v_fraud not in ('', 'accept')),
        review_reason = case
          when v_status = 'capture' and v_fraud not in ('', 'accept')
            then 'capture_requires_fraud_accept'
          else review_reason end
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', true, 'order_id', v_order.id,
      'payment_status', 'pending', 'order_status', v_order.status,
      'requires_manual_review',
        v_status = 'capture' and v_fraud not in ('', 'accept')
    );
  end if;

  -- Provider-side failure before payment releases exactly once.  A negative
  -- transition observed after verified payment is treated as a dispute and
  -- never silently rewrites paid history.
  v_effective := case
    when v_status in ('deny', 'failure') then 'failed'
    when v_status = 'cancel' then 'cancelled'
    else 'expired' end;
  v_release_reason := case
    when v_status in ('deny', 'failure') then 'payment_failed'
    when v_status = 'cancel' then 'payment_cancelled'
    else 'payment_expired' end;

  if v_attempt.status in ('refunded', 'partial_refund', 'disputed') then
    update public.payment_attempts set last_synced_at = now()
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false, 'reason', 'terminal_state_preserved',
      'order_id', v_order.id, 'payment_status', v_attempt.status,
      'order_status', v_order.status,
      'requires_manual_review', v_attempt.requires_manual_review
    );
  end if;

  if v_attempt.status = 'paid' or v_order.payment_verified_at is not null then
    if v_order.status <> 'redeemed' then
      perform private.release_midtrans_reservation(v_attempt.id, 'disputed');
      update public.orders
      set status = case when v_status = 'expire' then 'expired' else 'cancelled' end,
          cancelled_at = case when v_status <> 'expire'
            then coalesce(cancelled_at, now()) else cancelled_at end,
          expired_at = case when v_status = 'expire'
            then coalesce(expired_at, now()) else expired_at end,
          pickup_token_hash = null,
          pickup_code_hint = null,
          pickup_token_issued_at = null,
          pickup_token_expires_at = null,
          updated_at = now()
      where id = v_order.id;
    end if;
    if v_order.status = 'redeemed' then
      perform private.hold_redeemed_order_income(v_order.id, v_status);
      perform public.enqueue_notification(
        v_order.consumer_id, 'Pembayaran perlu ditinjau',
        'Ada perubahan pembayaran setelah pesanan diambil.',
        'payment', 'order:' || v_order.id || ':payment-review',
        'order', v_order.id, jsonb_build_object('status', 'disputed')
      );
      perform public.enqueue_notification(
        (select user_id from public.merchants where id = v_order.merchant_id),
        'Saldo pesanan ditahan',
        'Perubahan pembayaran memerlukan rekonsiliasi.',
        'payment', 'merchant-order:' || v_order.id || ':payment-review',
        'order', v_order.id, jsonb_build_object('status', 'disputed')
      );
    end if;
    update public.payment_attempts
    set status = 'disputed', provider_status = v_status,
        fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
        provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
        payment_type = coalesce(v_payment_type, payment_type),
        terminal_at = coalesce(terminal_at, now()),
        last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
        last_synced_at = now(), requires_manual_review = true,
        review_reason = 'negative_status_after_verified_payment'
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', true, 'order_id', v_order.id,
      'payment_status', 'disputed',
      'order_status', case when v_order.status = 'redeemed' then 'redeemed'
        when v_status = 'expire' then 'expired' else 'cancelled' end,
      'requires_manual_review', true
    );
  end if;

  perform private.release_midtrans_reservation(v_attempt.id, v_release_reason);
  update public.orders
  set status = case when v_status = 'expire' then 'expired' else 'cancelled' end,
      cancelled_at = case when v_status <> 'expire'
        then coalesce(cancelled_at, now()) else cancelled_at end,
      expired_at = case when v_status = 'expire'
        then coalesce(expired_at, now()) else expired_at end,
      pickup_token_hash = null,
      pickup_code_hint = null,
      pickup_token_issued_at = null,
      pickup_token_expires_at = null,
      updated_at = now()
  where id = v_order.id;
  update public.payment_attempts
  set status = v_effective, provider_status = v_status,
      fraud_status = nullif(v_fraud, ''), status_code = p_status_code,
      provider_transaction_id = coalesce(v_transaction_id, provider_transaction_id),
      payment_type = coalesce(v_payment_type, payment_type),
      terminal_at = coalesce(terminal_at, now()),
      checkout_lease_token = null, checkout_lease_expires_at = null,
      last_provider_event_at = coalesce(p_provider_event_at, last_provider_event_at),
      last_synced_at = now()
  where id = v_attempt.id;
  return jsonb_build_object(
    'applied', true, 'order_id', v_order.id,
    'payment_status', v_effective,
    'order_status', case when v_status = 'expire' then 'expired' else 'cancelled' end,
    'requires_manual_review', false
  );
end
$$;

revoke all on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) to service_role;

comment on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) is
  'Service-only idempotent state machine: authoritative GET only; retryable deny/failure remains pending, only verified paid is fulfillable, and terminal inventory release is exactly once.';

-- Pending checkout reservations are deliberately silent.  A consumer success
-- and merchant "new order" notification are emitted only by the same
-- transaction that records an authoritative verified paid transition.
create or replace function public.notify_order_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_merchant_user uuid;
  v_became_verified_paid boolean;
begin
  select user_id into v_merchant_user
  from public.merchants where id = new.merchant_id;

  if tg_op = 'INSERT' then
    v_became_verified_paid := new.status = 'paid'
      and new.payment_verified_at is not null;
  else
    v_became_verified_paid := new.status = 'paid'
      and new.payment_verified_at is not null
      and (
        old.status is distinct from 'paid'
        or old.payment_verified_at is null
      );
  end if;

  if v_became_verified_paid then
    perform public.enqueue_notification(
      new.consumer_id,
      'Pembayaran berhasil',
      new.bag_title || ' siap diproses. Total Rp' || new.total_amount,
      'payment', 'order:' || new.id || ':paid', 'order', new.id,
      jsonb_build_object('status', new.status, 'verified', true)
    );
    perform public.enqueue_notification(
      v_merchant_user,
      'Pesanan baru sudah dibayar',
      new.quantity || 'x ' || new.bag_title,
      'order', 'merchant-order:' || new.id || ':new', 'order', new.id,
      jsonb_build_object('status', new.status, 'verified', true)
    );
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'ready' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pesanan siap diambil', new.bag_title || ' sudah siap.',
        'ready', 'order:' || new.id || ':ready', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    elsif new.status = 'redeemed' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pesanan selesai',
        'Bag sudah diambil. Beri penilaian untuk merchant.',
        'rating', 'order:' || new.id || ':redeemed', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    elsif new.status = 'expired' then
      perform public.enqueue_notification(
        new.consumer_id,
        case when old.status = 'pending'
          then 'Waktu pembayaran habis' else 'Pesanan kedaluwarsa' end,
        case when old.status = 'pending'
          then 'Reservasi ' || new.bag_title || ' telah dilepas.'
          else new.bag_title || ' melewati batas pengambilan.' end,
        case when old.status = 'pending' then 'payment' else 'order' end,
        'order:' || new.id || ':expired', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    elsif new.status = 'cancelled' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pesanan dibatalkan',
        new.bag_title || ' telah dibatalkan.',
        'order', 'order:' || new.id || ':cancelled', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    elsif new.status = 'refunded' then
      perform public.enqueue_notification(
        new.consumer_id, 'Pembayaran dikembalikan',
        'Pengembalian dana untuk ' || new.bag_title || ' tercatat.',
        'payment', 'order:' || new.id || ':refunded', 'order', new.id,
        jsonb_build_object('status', new.status)
      );
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists notify_order_change on public.orders;
create trigger notify_order_change
after insert or update of status, payment_verified_at on public.orders
for each row execute function public.notify_order_change();

revoke all on function public.notify_order_change()
  from public, anon, authenticated;

-- A merchant must not locally cancel an order after real money was accepted.
-- Midtrans cancellation/refund has to be observed first through the status
-- state machine, otherwise stock and money would diverge.
create or replace function public.cancel_merchant_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders;
  v_owner uuid;
  v_has_midtrans_attempt boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_order_id is null then raise exception 'order not found'; end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found then raise exception 'order not found'; end if;

  select user_id into v_owner
  from public.merchants
  where id = v_order.merchant_id;
  if v_owner is distinct from v_uid then
    raise exception 'order does not belong to your merchant';
  end if;

  if v_order.status = 'cancelled' then
    return to_jsonb(v_order) || jsonb_build_object(
      'order_id', v_order.id, 'stock_restored', false,
      'already_cancelled', true
    );
  end if;
  if v_order.status not in ('paid', 'preparing', 'ready') then
    raise exception 'order cannot be cancelled from status %', v_order.status;
  end if;

  select exists (
    select 1 from public.payment_attempts pa where pa.order_id = v_order.id
  ) into v_has_midtrans_attempt;
  if v_has_midtrans_attempt then
    raise exception
      'Midtrans order must be cancelled or refunded at the provider first'
      using errcode = '55000';
  end if;

  -- Retain safe behaviour for legacy non-Midtrans rows.
  update public.orders
  set status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, now()),
      pickup_token_hash = null,
      pickup_code_hint = null,
      pickup_token_issued_at = null,
      pickup_token_expires_at = null,
      pickup_token_used_at = null,
      updated_at = now()
  where id = v_order.id
    and status in ('paid', 'preparing', 'ready')
  returning * into v_order;
  if not found then
    raise exception 'order status changed; reload and try again';
  end if;

  update public.surprise_bags b
  set quantity_left = least(b.quantity_total, b.quantity_left + v_order.quantity),
      status = case
        when b.status = 'inactive' then 'inactive'
        when b.available_on < (now() at time zone 'Asia/Jakarta')::date
          then 'inactive'
        when b.pickup_end_at is not null and b.pickup_end_at <= now()
          then 'inactive'
        when least(b.quantity_total, b.quantity_left + v_order.quantity) = 0
          then 'sold_out'
        else 'active'
      end,
      updated_at = now()
  where b.id = v_order.bag_id;
  if not found then raise exception 'bag not found for order'; end if;

  return to_jsonb(v_order) || jsonb_build_object(
    'order_id', v_order.id, 'stock_restored', true,
    'already_cancelled', false
  );
end
$$;

revoke all on function public.cancel_merchant_order(uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_merchant_order(uuid)
  to authenticated;

-- Payment timeout and pickup timeout are intentionally separate clocks.  A
-- late, genuinely paid Midtrans status can reacquire only a still-valid
-- payment-timeout reservation; pickup expiry is never resurrected.
create or replace function public.expire_orders(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_candidate record;
  v_attempt public.payment_attempts;
  v_count integer := 0;
  v_remaining integer;
begin
  perform private.require_service_role();
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'limit must be between 1 and 5000';
  end if;

  -- First release checkout reservations whose independent 15-minute payment
  -- window elapsed.  Authoritative late settlement remains reconcilable.
  for v_candidate in
    select o.id as order_id, pa.id as attempt_id
    from public.orders o
    join public.payment_attempts pa on pa.order_id = o.id
    where o.status = 'pending'
      and pa.status in ('creating', 'checkout_created', 'pending')
      and pa.payment_expires_at <= now()
    order by pa.payment_expires_at
    limit p_limit
    for update of o skip locked
  loop
    select * into v_attempt
    from public.payment_attempts
    where id = v_candidate.attempt_id
    for update;
    if v_attempt.status not in ('creating', 'checkout_created', 'pending')
       or v_attempt.payment_expires_at > now() then
      continue;
    end if;

    perform private.release_midtrans_reservation(
      v_attempt.id, 'payment_expired'
    );
    update public.orders
    set status = 'expired', expired_at = coalesce(expired_at, now()),
        pickup_token_hash = null, pickup_code_hint = null,
        pickup_token_issued_at = null, pickup_token_expires_at = null,
        updated_at = now()
    where id = v_candidate.order_id and status = 'pending';
    if found then
      update public.payment_attempts
      set status = 'expired', terminal_at = coalesce(terminal_at, now()),
          checkout_lease_token = null, checkout_lease_expires_at = null,
          last_error_code = 'local_payment_timeout'
      where id = v_attempt.id
        and status in ('creating', 'checkout_created', 'pending');
      v_count := v_count + 1;
    end if;
  end loop;

  -- Then expire operational pickup windows using orders.expires_at.  The
  -- payment remains paid; only its food reservation is released.
  v_remaining := p_limit - v_count;
  if v_remaining > 0 then
    for v_candidate in
      select o.id as order_id,
             (select pa.id from public.payment_attempts pa
              where pa.order_id = o.id) as attempt_id,
             o.bag_id, o.quantity
      from public.orders o
      where o.status in ('paid', 'preparing', 'ready')
        and o.expires_at <= now()
      order by o.expires_at
      limit v_remaining
      for update of o skip locked
    loop
      if v_candidate.attempt_id is not null then
        select * into v_attempt
        from public.payment_attempts
        where id = v_candidate.attempt_id
        for update;
        perform private.release_midtrans_reservation(
          v_attempt.id, 'pickup_expired'
        );
      else
        update public.surprise_bags b
        set quantity_left = least(
              b.quantity_total, b.quantity_left + v_candidate.quantity
            ),
            status = case
              when b.status = 'inactive' then 'inactive'
              when b.available_on < (now() at time zone 'Asia/Jakarta')::date
                then 'inactive'
              when b.pickup_end_at is not null and b.pickup_end_at <= now()
                then 'inactive'
              when least(
                b.quantity_total, b.quantity_left + v_candidate.quantity
              ) = 0 then 'sold_out'
              else 'active'
            end,
            updated_at = now()
        where b.id = v_candidate.bag_id;
        if not found then raise exception 'bag not found for order'; end if;
      end if;

      update public.orders
      set status = 'expired', expired_at = coalesce(expired_at, now()),
          pickup_token_hash = null, pickup_code_hint = null,
          pickup_token_issued_at = null, pickup_token_expires_at = null,
          updated_at = now()
      where id = v_candidate.order_id
        and status in ('paid', 'preparing', 'ready');
      if found then v_count := v_count + 1; end if;
    end loop;
  end if;

  return v_count;
end
$$;

revoke all on function public.expire_orders(integer)
  from public, anon, authenticated;
grant execute on function public.expire_orders(integer)
  to service_role;

-- Hosted Supabase includes pg_cron.  Running every five minutes bounds the
-- lifetime of an abandoned stock hold without relying on a user reopening the
-- app.  The named job is replaced idempotently on migration replay.
create extension if not exists pg_cron;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'savebite-expire-orders'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'savebite-expire-orders',
    '*/5 * * * *',
    'select public.expire_orders(500);'
  );
end
$$;

-- Real payments are now enabled.  Payouts remain deliberately disabled until
-- provider refunds/chargebacks and outbound payout execution are integrated;
-- a verified redemption ledger alone is not enough to make withdrawals safe.
insert into private.app_settings (key, int_value, text_value)
values
  ('payments_enabled', 1, null),
  ('payouts_enabled', 0, null)
on conflict (key) do update
set int_value = excluded.int_value,
    text_value = excluded.text_value;

comment on function public.purchase_bag(uuid,integer,text,text) is
  'Reserves inventory and creates one pending Midtrans attempt; server computes every monetary field.';
comment on function public.cancel_merchant_order(uuid) is
  'Cancels legacy orders only; real Midtrans orders require provider-first cancellation/refund.';
comment on function public.expire_orders(integer) is
  'Expires payment windows separately from pickup windows and releases each reservation at most once.';

commit;
