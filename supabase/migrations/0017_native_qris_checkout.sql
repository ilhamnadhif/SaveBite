-- SaveBite: QRIS-only checkout rendered directly by the client.
--
-- The QR image is created by Midtrans Core API on the server.  Only the
-- owning consumer may read its short-lived URL; merchants and anonymous
-- clients never receive it.  Apply after 0016_midtrans_merchant_cancellation.sql.

begin;

alter table public.payment_attempts
  add column if not exists qr_code_url text;

alter table public.payment_attempts
  drop constraint if exists payment_attempts_qr_code_url_check;
alter table public.payment_attempts
  add constraint payment_attempts_qr_code_url_check
  check (
    qr_code_url is null
    or (
      length(qr_code_url) <= 2048
      and qr_code_url ~ '^https://api(\.sandbox)?\.midtrans\.com/v2/qris/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/qr-code$'
    )
  );

alter table public.payment_attempts
  drop constraint if exists payment_attempts_qris_identity_check;
alter table public.payment_attempts
  add constraint payment_attempts_qris_identity_check
  check (
    qr_code_url is null
    or (
      payment_type is not distinct from 'qris'
      and provider_transaction_id is not null
      and provider_transaction_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
      and right(
        qr_code_url,
        length('/v2/qris/' || provider_transaction_id || '/qr-code')
      ) = ('/v2/qris/' || provider_transaction_id || '/qr-code')
    )
  );

-- A live Snap reservation cannot be resumed by the QRIS-only client and its
-- provider order ID cannot safely be reused for a Core charge.  Fail rollout
-- closed instead of stranding that customer; operators must drain/expire it.
do $$
begin
  if exists (
    select 1
    from public.payment_attempts pa
    join public.orders o on o.id = pa.order_id
    where (
        pa.snap_token is not null
        or pa.checkout_lease_expires_at > now()
      )
      and pa.status in ('creating', 'checkout_created', 'pending')
      and pa.payment_expires_at > now()
      and o.payment_verified_at is null
  ) then
    raise exception
      'native QRIS rollout blocked by a live legacy Snap checkout';
  end if;
end
$$;

comment on column public.payment_attempts.qr_code_url is
  'Short-lived Midtrans QRIS image URL. Exposed only to the owning consumer while payment is live.';

-- Keep the URL out of direct table grants.  This projection binds the lookup
-- to auth.uid() and hides stale or terminal QR codes.
create or replace function public.get_consumer_qris_projection(
  p_order_id uuid
)
returns table (
  payment_qr_url text
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select case
           when pa.status in ('creating', 'checkout_created', 'pending')
            and pa.payment_expires_at > now()
           then pa.qr_code_url
           else null
         end
  from public.payment_attempts pa
  join public.orders o on o.id = pa.order_id
  where pa.order_id = p_order_id
    and o.consumer_id = auth.uid()
$$;

revoke all on function public.get_consumer_qris_projection(uuid)
  from public, anon, authenticated;
grant execute on function public.get_consumer_qris_projection(uuid)
  to authenticated;

-- Preserve the established view order and append the new field so existing
-- clients retain an identical contract.  The merchant view remains unchanged.
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
       pa.requires_manual_review as requires_payment_review,
       qris.payment_qr_url
from public.orders o
left join lateral public.get_consumer_payment_projection(o.id) pa on true
left join lateral public.get_consumer_qris_projection(o.id) qris on true
where o.consumer_id = auth.uid();

grant select on public.consumer_orders to authenticated;

-- A Core charge needs at least one whole provider minute.  Keep a two-minute
-- database margin so the order cannot commit and then fail before the Edge
-- Function receives the reservation payload.
create or replace function private.enforce_new_qris_payment_window()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if new.status = 'pending'
     and new.payment_verified_at is null
     and new.expires_at <= now() + interval '2 minutes' then
    raise exception 'pickup window ends too soon for payment'
      using errcode = '55000';
  end if;
  return new;
end
$$;

revoke all on function private.enforce_new_qris_payment_window()
  from public, anon, authenticated, service_role;

drop trigger if exists enforce_new_qris_payment_window on public.orders;
create trigger enforce_new_qris_payment_window
before insert on public.orders
for each row execute function private.enforce_new_qris_payment_window();

-- Keep the original, already-audited reservation body as a private base and
-- put the QRIS-only invariant at the sole authenticated database entry point.
alter function public.purchase_bag(uuid,integer,text,text)
  rename to purchase_bag_base;

revoke all on function public.purchase_bag_base(uuid,integer,text,text)
  from public, anon, authenticated, service_role;

create or replace function public.purchase_bag(
  p_bag_id uuid,
  p_qty integer,
  p_method text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if p_method is null or lower(btrim(p_method)) <> 'qris' then
    raise exception 'payment method must be QRIS';
  end if;
  return public.purchase_bag_base(
    p_bag_id,
    p_qty,
    'QRIS',
    p_idempotency_key
  );
end
$$;

revoke all on function public.purchase_bag(uuid,integer,text,text)
  from public, anon, authenticated;
grant execute on function public.purchase_bag(uuid,integer,text,text)
  to authenticated;

comment on function public.purchase_bag(uuid,integer,text,text) is
  'QRIS-only authenticated wrapper around the atomic reservation implementation.';

-- Lease creation is now satisfied only by a native QRIS charge.  Legacy Snap
-- fields may remain on historical attempts, but they are never reused here.
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
  if v_attempt.qr_code_url is not null then
    return jsonb_build_object(
      'mode', 'reuse',
      'order_id', v_order.id,
      'payment_status', v_attempt.status,
      'payment_qr_url', v_attempt.qr_code_url
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
    'requested_method', 'QRIS',
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

-- The Core API response is persisted only while the matching short lease is
-- held.  A webhook that wins the race is never downgraded from paid/terminal.
create or replace function public.complete_midtrans_qris_checkout(
  p_order_id uuid,
  p_lease_token text,
  p_payment_qr_url text,
  p_provider_transaction_id text
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_order public.orders;
  v_attempt public.payment_attempts;
begin
  perform private.require_service_role();
  if p_order_id is null then
    raise exception 'order not found';
  end if;
  if p_lease_token is null or p_lease_token !~ '^[0-9a-f]{48}$' then
    raise exception 'invalid checkout lease';
  end if;
  if p_payment_qr_url is null or length(p_payment_qr_url) > 2048
     or p_payment_qr_url !~ '^https://api(\.sandbox)?\.midtrans\.com/v2/qris/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/qr-code$' then
    raise exception 'invalid Midtrans QRIS URL';
  end if;
  if p_provider_transaction_id is null
     or p_provider_transaction_id !~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' then
    raise exception 'invalid Midtrans transaction ID';
  end if;
  if right(
       p_payment_qr_url,
       length('/v2/qris/' || p_provider_transaction_id || '/qr-code')
     ) <> ('/v2/qris/' || p_provider_transaction_id || '/qr-code') then
    raise exception 'QRIS URL does not match Midtrans transaction ID';
  end if;

  -- Use the same global lock order as provider status reconciliation.
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found then raise exception 'order not found'; end if;

  select * into v_attempt
  from public.payment_attempts
  where order_id = p_order_id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;

  -- An exact replay is successful even after the first commit cleared the
  -- lease.  This covers a lost RPC response without permitting new values.
  if v_attempt.qr_code_url = p_payment_qr_url
     and v_attempt.provider_transaction_id = p_provider_transaction_id
     and v_attempt.payment_type = 'qris' then
    return;
  end if;

  if v_attempt.qr_code_url is not null
     and v_attempt.qr_code_url <> p_payment_qr_url then
    raise exception 'QRIS URL conflicts with existing checkout'
      using errcode = '55000';
  end if;
  if v_attempt.provider_transaction_id is not null
     and v_attempt.provider_transaction_id <> p_provider_transaction_id then
    raise exception 'Midtrans transaction ID conflicts with existing checkout'
      using errcode = '55000';
  end if;
  if v_attempt.payment_type is not null and v_attempt.payment_type <> 'qris' then
    raise exception 'Midtrans payment type conflicts with QRIS checkout'
      using errcode = '55000';
  end if;

  if v_attempt.checkout_lease_token = p_lease_token then
    update public.payment_attempts
    set qr_code_url = p_payment_qr_url,
        provider_transaction_id = p_provider_transaction_id,
        payment_type = 'qris',
        provider_status = coalesce(provider_status, 'pending'),
        status = case when status = 'creating' then 'pending' else status end,
        snap_token = null,
        redirect_url = null,
        checkout_lease_token = null,
        checkout_lease_expires_at = null,
        last_error_code = null
    where id = v_attempt.id;
    return;
  end if;

  -- A Midtrans webhook/Get Status can authoritatively write the transaction
  -- and clear the lease before the charge response is persisted.  Accept only
  -- the exact same QRIS transaction; never infer this from local state alone.
  if v_attempt.checkout_lease_token is null
     and v_attempt.provider_transaction_id = p_provider_transaction_id
     and v_attempt.payment_type = 'qris' then
    if v_attempt.status in ('pending', 'paid') then
      update public.payment_attempts
      set qr_code_url = p_payment_qr_url,
          snap_token = null,
          redirect_url = null,
          last_error_code = null
      where id = v_attempt.id;
    end if;
    -- Terminal provider state is also authoritative.  There is no reason to
    -- retain or expose a now-useless QR, but completion itself is successful.
    return;
  end if;

  raise exception 'checkout lease is no longer valid' using errcode = '55000';
end
$$;

-- Status/webhook reconciliation can repair the narrow case where Midtrans
-- created the charge but both completion RPC responses were lost.  It may
-- backfill only a provider-confirmed pending QRIS transaction after the lease
-- has been cleared by the authoritative state machine.
create or replace function public.backfill_midtrans_qris_checkout(
  p_order_id uuid,
  p_payment_qr_url text,
  p_provider_transaction_id text
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_order public.orders;
  v_attempt public.payment_attempts;
begin
  perform private.require_service_role();
  if p_order_id is null then raise exception 'order not found'; end if;
  if p_payment_qr_url is null or length(p_payment_qr_url) > 2048
     or p_payment_qr_url !~ '^https://api(\.sandbox)?\.midtrans\.com/v2/qris/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/qr-code$' then
    raise exception 'invalid Midtrans QRIS URL';
  end if;
  if p_provider_transaction_id is null
     or p_provider_transaction_id !~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
     or right(
       p_payment_qr_url,
       length('/v2/qris/' || p_provider_transaction_id || '/qr-code')
     ) <> ('/v2/qris/' || p_provider_transaction_id || '/qr-code') then
    raise exception 'invalid Midtrans transaction identity';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found then raise exception 'order not found'; end if;

  select * into v_attempt
  from public.payment_attempts
  where order_id = p_order_id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;

  if v_attempt.qr_code_url = p_payment_qr_url
     and v_attempt.provider_transaction_id = p_provider_transaction_id
     and v_attempt.payment_type = 'qris' then
    return;
  end if;
  if v_attempt.qr_code_url is not null
     or v_attempt.provider_transaction_id <> p_provider_transaction_id
     or v_attempt.payment_type <> 'qris'
     or v_attempt.provider_status <> 'pending'
     or v_attempt.status <> 'pending'
     or v_attempt.checkout_lease_token is not null
     or v_attempt.payment_expires_at <= now()
     or v_order.status <> 'pending'
     or v_order.payment_verified_at is not null then
    raise exception 'QRIS checkout is not eligible for backfill'
      using errcode = '55000';
  end if;

  update public.payment_attempts
  set qr_code_url = p_payment_qr_url,
      snap_token = null,
      redirect_url = null,
      last_error_code = null
  where id = v_attempt.id;
end
$$;

-- The 0012 state machine intentionally kept Snap deny/failure retryable so a
-- customer could choose another channel.  A native QRIS charge has one fixed
-- transaction and Midtrans defines deny/failure as terminal.  Wrap the audited
-- base implementation and finalize only its explicit retryable-Snap result
-- when the authoritative payment type is QRIS.
alter function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) rename to apply_midtrans_payment_status_base;

revoke all on function public.apply_midtrans_payment_status_base(
  text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated, service_role;

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
  v_result jsonb;
  v_order public.orders;
  v_attempt public.payment_attempts;
  v_status text := lower(btrim(coalesce(p_transaction_status, '')));
begin
  perform private.require_service_role();

  v_result := public.apply_midtrans_payment_status_base(
    p_provider_order_id,
    p_transaction_status,
    p_fraud_status,
    p_status_code,
    p_gross_amount,
    p_transaction_id,
    p_payment_type,
    p_provider_event_at
  );

  if v_status not in ('deny', 'failure')
     or (v_result ->> 'reason') is distinct from 'retryable_snap_attempt' then
    return v_result;
  end if;

  -- The base function already acquired these locks in this transaction.  Read
  -- them again in the global order -> attempt order before finalizing QRIS.
  select o.* into v_order
  from public.orders o
  join public.payment_attempts pa on pa.order_id = o.id
  where pa.provider_order_id = p_provider_order_id
  for update of o;
  if not found then return v_result; end if;

  select * into v_attempt
  from public.payment_attempts
  where provider_order_id = p_provider_order_id
  for update;
  if not found then return v_result; end if;

  if lower(coalesce(v_attempt.payment_type, v_attempt.requested_method, ''))
       <> 'qris'
     or v_attempt.provider_status <> v_status
     or v_attempt.status <> 'pending'
     or v_order.status <> 'pending'
     or v_order.payment_verified_at is not null then
    return v_result;
  end if;

  perform private.release_midtrans_reservation(
    v_attempt.id,
    'payment_failed'
  );

  update public.orders
  set status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, now()),
      pickup_token_hash = null,
      pickup_code_hint = null,
      pickup_token_issued_at = null,
      pickup_token_expires_at = null,
      updated_at = now()
  where id = v_order.id
    and payment_verified_at is null;

  update public.payment_attempts
  set status = 'failed',
      terminal_at = coalesce(terminal_at, now()),
      checkout_lease_token = null,
      checkout_lease_expires_at = null,
      last_error_code = 'provider_attempt_' || v_status
  where id = v_attempt.id;

  return jsonb_build_object(
    'applied', true,
    'reason', 'qris_terminal_failure',
    'order_id', v_order.id,
    'payment_status', 'failed',
    'order_status', 'cancelled',
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
  'Applies authoritative Midtrans state and makes QRIS deny/failure terminal.';

revoke all on function public.claim_midtrans_checkout(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.complete_midtrans_qris_checkout(uuid,text,text,text)
  from public, anon, authenticated;
revoke all on function public.backfill_midtrans_qris_checkout(uuid,text,text)
  from public, anon, authenticated;
revoke all on function public.complete_midtrans_checkout(uuid,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_midtrans_checkout(uuid,uuid)
  to service_role;
grant execute on function public.complete_midtrans_qris_checkout(uuid,text,text,text)
  to service_role;
grant execute on function public.backfill_midtrans_qris_checkout(uuid,text,text)
  to service_role;

commit;
