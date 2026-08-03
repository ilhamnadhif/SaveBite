-- SaveBite: final QRIS expiry and transaction-identity reconciliation guards.
-- Apply after 0017_native_qris_checkout.sql.

begin;

-- Any active pre-QR row at rollout can represent a provider order ID already
-- consumed by Snap even when its redirect write was lost.  Stop instead of
-- trying to reuse that ID for a Core charge.
do $$
begin
  if exists (
    select 1
    from public.payment_attempts pa
    join public.orders o on o.id = pa.order_id
    where pa.status in ('creating', 'checkout_created', 'pending')
      and pa.payment_expires_at > now()
      and pa.qr_code_url is null
      and o.payment_verified_at is null
  ) then
    raise exception
      'QRIS hardening rollout blocked by an active checkout without a QR';
  end if;
end
$$;

-- Midtrans accepts only a whole-minute custom expiry.  The Edge Function uses
-- floor(remaining minutes), so the provider QR can expire up to 59.999 seconds
-- before the original database deadline.  Shorten the local deadline by one
-- minute exactly once when the QR is first persisted; the app can never show a
-- QR after its provider expiry.
create or replace function private.align_new_qris_payment_expiry()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if old.qr_code_url is null and new.qr_code_url is not null then
    if old.payment_expires_at <= now() + interval '1 minute' then
      raise exception 'payment reservation is too close to expiry'
        using errcode = '55000';
    end if;
    new.payment_expires_at := new.payment_expires_at - interval '1 minute';
  end if;
  return new;
end
$$;

revoke all on function private.align_new_qris_payment_expiry()
  from public, anon, authenticated, service_role;

drop trigger if exists align_new_qris_payment_expiry
  on public.payment_attempts;
create trigger align_new_qris_payment_expiry
before update of qr_code_url on public.payment_attempts
for each row execute function private.align_new_qris_payment_expiry();

-- No QR checkout should exist during this coordinated rollout, but keep an
-- idempotent repair for environments that deployed 0017 moments earlier.
update public.payment_attempts
set payment_expires_at = payment_expires_at - interval '1 minute'
where qr_code_url is not null
  and status in ('creating', 'checkout_created', 'pending')
  and payment_expires_at > created_at + interval '1 minute';

-- A Core QRIS order has one transaction ID.  Guard that identity before the
-- legacy Snap base can apply a settlement from a different transaction, then
-- retain 0017's terminal handling for QRIS deny/failure.
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
  v_transaction_id text := nullif(btrim(coalesce(p_transaction_id, '')), '');
  v_effective_type text;
begin
  perform private.require_service_role();

  select o.* into v_order
  from public.orders o
  join public.payment_attempts pa on pa.order_id = o.id
  where pa.provider_order_id = p_provider_order_id
  for update of o;
  if not found then raise exception 'payment attempt not found'; end if;

  select * into v_attempt
  from public.payment_attempts
  where provider_order_id = p_provider_order_id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;

  v_effective_type := lower(coalesce(
    nullif(btrim(coalesce(p_payment_type, '')), ''),
    v_attempt.payment_type,
    v_attempt.requested_method,
    ''
  ));

  if v_effective_type = 'qris'
     and v_attempt.provider_transaction_id is not null
     and v_transaction_id is not null
     and v_attempt.provider_transaction_id <> v_transaction_id
     and p_gross_amount ~ '^[0-9]+([.][0-9]{1,2})?$'
     and p_gross_amount::numeric = v_attempt.expected_amount::numeric
     and (
       p_provider_event_at is null
       or v_attempt.last_provider_event_at is null
       or p_provider_event_at >= v_attempt.last_provider_event_at
     ) then
    update public.payment_attempts
    set requires_manual_review = true,
        review_reason = 'qris_transaction_id_changed',
        last_synced_at = now()
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false,
      'reason', 'transaction_id_conflict',
      'order_id', v_order.id,
      'payment_status', v_attempt.status,
      'order_status', v_order.status,
      'requires_manual_review', true
    );
  end if;

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

  -- The base retains the same locks; refresh its writes before finalization.
  select * into v_attempt
  from public.payment_attempts
  where provider_order_id = p_provider_order_id
  for update;

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
  'Applies authoritative Midtrans state with fixed QRIS transaction identity and terminal failure semantics.';

commit;
