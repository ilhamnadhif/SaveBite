-- SaveBite: explicit one-time QRIS expiry alignment marker and local identity.
-- Apply after 0018_qris_reconciliation_hardening.sql.

begin;

alter table public.payment_attempts
  add column if not exists qris_expiry_aligned_at timestamptz;

update public.payment_attempts
set qris_expiry_aligned_at = coalesce(qris_expiry_aligned_at, now())
where qr_code_url is not null;

alter table public.payment_attempts
  drop constraint if exists payment_attempts_qris_expiry_marker_check;
alter table public.payment_attempts
  add constraint payment_attempts_qris_expiry_marker_check
  check (qr_code_url is null or qris_expiry_aligned_at is not null);

comment on column public.payment_attempts.qris_expiry_aligned_at is
  'Set exactly once when the local QRIS deadline is conservatively aligned to Midtrans whole-minute expiry.';

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
    if old.qris_expiry_aligned_at is null then
      new.payment_expires_at := old.payment_expires_at - interval '1 minute';
      new.qris_expiry_aligned_at := now();
    else
      new.payment_expires_at := least(
        new.payment_expires_at,
        old.payment_expires_at
      );
      new.qris_expiry_aligned_at := old.qris_expiry_aligned_at;
    end if;
  elsif old.qr_code_url is not null and new.qr_code_url is not null then
    new.payment_expires_at := least(
      new.payment_expires_at,
      old.payment_expires_at
    );
    new.qris_expiry_aligned_at := coalesce(
      old.qris_expiry_aligned_at,
      new.qris_expiry_aligned_at,
      now()
    );
  end if;
  return new;
end
$$;

revoke all on function private.align_new_qris_payment_expiry()
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
  v_result jsonb;
  v_order public.orders;
  v_attempt public.payment_attempts;
  v_status text := lower(btrim(coalesce(p_transaction_status, '')));
  v_transaction_id text := nullif(btrim(coalesce(p_transaction_id, '')), '');
  v_is_qris boolean;
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

  -- Provider input can confirm QRIS but can never override local QRIS identity.
  v_is_qris := lower(coalesce(
      v_attempt.payment_type,
      v_attempt.requested_method,
      ''
    )) = 'qris'
    or lower(btrim(coalesce(p_payment_type, ''))) = 'qris';

  if v_is_qris
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
  'Applies authoritative Midtrans state with immutable local QRIS transaction identity.';

commit;
