-- SaveBite: support Midtrans's documented GoPay Core QRIS image flow.
--
-- A Core charge starts as payment_type=gopay and returns a
-- /v2/gopay/{transaction_id}/qr-code image. When that image is scanned,
-- Midtrans may authoritatively transition the provider payment type to qris.
-- The customer still receives only a native QRIS image; no deeplink is stored.

begin;

alter table public.payment_attempts
  drop constraint if exists payment_attempts_qr_code_url_check;
alter table public.payment_attempts
  add constraint payment_attempts_qr_code_url_check
  check (
    qr_code_url is null
    or (
      length(qr_code_url) <= 2048
      and qr_code_url ~ '^https://api(\.sandbox)?\.midtrans\.com/v2/(qris|gopay)/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/qr-code$'
    )
  );

alter table public.payment_attempts
  drop constraint if exists payment_attempts_qris_identity_check;

-- Midtrans transaction IDs are UUIDs. Store one canonical representation so
-- provider snapshots cannot create false conflicts from letter casing alone.
update public.payment_attempts
set provider_transaction_id = lower(provider_transaction_id)
where lower(coalesce(requested_method, '')) = 'qris'
  and provider_transaction_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$';

alter table public.payment_attempts
  add constraint payment_attempts_qris_identity_check
  check (
    qr_code_url is null
    or (
      lower(coalesce(requested_method, '')) = 'qris'
      and
      provider_transaction_id is not null
      and provider_transaction_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
      and (
        (
          qr_code_url ~ '/v2/qris/'
          and payment_type is not distinct from 'qris'
          and lower(right(
            qr_code_url,
            length('/v2/qris/' || provider_transaction_id || '/qr-code')
          )) = lower('/v2/qris/' || provider_transaction_id || '/qr-code')
        )
        or (
          qr_code_url ~ '/v2/gopay/'
          and payment_type is not null
          and payment_type in ('gopay', 'qris')
          and lower(right(
            qr_code_url,
            length('/v2/gopay/' || provider_transaction_id || '/qr-code')
          )) = lower('/v2/gopay/' || provider_transaction_id || '/qr-code')
        )
      )
    )
  );

comment on column public.payment_attempts.qr_code_url is
  'Short-lived native QRIS image URL from Midtrans Core QRIS or GoPay QRIS flow. Exposed only to the owning consumer while live.';

-- A review hold is a payment quarantine, not only a fulfilment hold. Never
-- return a still-live provider image while an anomalous status is unresolved.
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
            and not pa.requires_manual_review
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

-- Preserve the audited claim implementation and add one narrow fail-closed
-- gate before it can reuse an existing QR or issue a fresh provider lease.
alter function public.claim_midtrans_checkout(uuid,uuid)
  rename to claim_midtrans_checkout_base_qris;

revoke all on function public.claim_midtrans_checkout_base_qris(uuid,uuid)
  from public, anon, authenticated, service_role;

create or replace function public.claim_midtrans_checkout(
  p_order_id uuid,
  p_consumer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_order public.orders;
  v_attempt public.payment_attempts;
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
  where order_id = p_order_id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;

  if v_attempt.requires_manual_review then
    update public.payment_attempts
    set checkout_lease_token = null,
        checkout_lease_expires_at = null
    where id = v_attempt.id;
    return jsonb_build_object(
      'mode', 'completed',
      'order_id', v_order.id,
      'payment_status', v_attempt.status
    );
  end if;

  return public.claim_midtrans_checkout_base_qris(
    p_order_id,
    p_consumer_id
  );
end
$$;

revoke all on function public.claim_midtrans_checkout(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.claim_midtrans_checkout(uuid,uuid)
  to service_role;

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
  v_qr_resource_type text;
  v_type_matches boolean;
begin
  perform private.require_service_role();
  if p_order_id is null then raise exception 'order not found'; end if;
  if p_lease_token is null or p_lease_token !~ '^[0-9a-f]{48}$' then
    raise exception 'invalid checkout lease';
  end if;
  if p_payment_qr_url is null or length(p_payment_qr_url) > 2048
     or p_payment_qr_url !~ '^https://api(\.sandbox)?\.midtrans\.com/v2/(qris|gopay)/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/qr-code$' then
    raise exception 'invalid Midtrans QRIS URL';
  end if;
  if p_provider_transaction_id is null
     or p_provider_transaction_id !~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' then
    raise exception 'invalid Midtrans transaction ID';
  end if;

  v_qr_resource_type := case
    when p_payment_qr_url ~ '/v2/gopay/' then 'gopay'
    else 'qris'
  end;
  if lower(right(
       p_payment_qr_url,
       length('/v2/' || v_qr_resource_type || '/' ||
              p_provider_transaction_id || '/qr-code')
     )) <> lower('/v2/' || v_qr_resource_type || '/' ||
                  p_provider_transaction_id || '/qr-code') then
    raise exception 'QRIS URL does not match Midtrans transaction ID';
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
  if v_attempt.requires_manual_review then
    -- The provider response may race an anomalous status snapshot. A held
    -- attempt must never regain or expose a payable QR through completion.
    return;
  end if;

  v_type_matches := case
    when v_qr_resource_type = 'qris' then v_attempt.payment_type = 'qris'
    else v_attempt.payment_type in ('gopay', 'qris')
  end;

  if v_attempt.qr_code_url = p_payment_qr_url
     and lower(v_attempt.provider_transaction_id) = lower(p_provider_transaction_id)
     and v_type_matches then
    return;
  end if;

  if v_attempt.qr_code_url is not null
     and v_attempt.qr_code_url <> p_payment_qr_url then
    raise exception 'QRIS URL conflicts with existing checkout'
      using errcode = '55000';
  end if;
  if v_attempt.provider_transaction_id is not null
     and lower(v_attempt.provider_transaction_id) <> lower(p_provider_transaction_id) then
    raise exception 'Midtrans transaction ID conflicts with existing checkout'
      using errcode = '55000';
  end if;
  if v_attempt.payment_type is not null and v_type_matches is not true then
    raise exception 'Midtrans payment type conflicts with QRIS checkout'
      using errcode = '55000';
  end if;

  if v_attempt.checkout_lease_token = p_lease_token then
    update public.payment_attempts
    set qr_code_url = p_payment_qr_url,
        provider_transaction_id = lower(p_provider_transaction_id),
        payment_type = case
          when v_qr_resource_type = 'gopay' and payment_type = 'qris'
            then 'qris'
          else v_qr_resource_type
        end,
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

  if v_attempt.checkout_lease_token is null
     and lower(v_attempt.provider_transaction_id) = lower(p_provider_transaction_id)
     and v_type_matches then
    if v_attempt.status = 'pending' then
      update public.payment_attempts
      set qr_code_url = p_payment_qr_url,
          snap_token = null,
          redirect_url = null,
          last_error_code = null
      where id = v_attempt.id;
    end if;
    return;
  end if;

  raise exception 'checkout lease is no longer valid' using errcode = '55000';
end
$$;

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
  v_qr_resource_type text;
  v_type_matches boolean;
begin
  perform private.require_service_role();
  if p_order_id is null then raise exception 'order not found'; end if;
  if p_payment_qr_url is null or length(p_payment_qr_url) > 2048
     or p_payment_qr_url !~ '^https://api(\.sandbox)?\.midtrans\.com/v2/(qris|gopay)/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/qr-code$' then
    raise exception 'invalid Midtrans QRIS URL';
  end if;
  if p_provider_transaction_id is null
     or p_provider_transaction_id !~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' then
    raise exception 'invalid Midtrans transaction ID';
  end if;

  v_qr_resource_type := case
    when p_payment_qr_url ~ '/v2/gopay/' then 'gopay'
    else 'qris'
  end;
  if lower(right(
       p_payment_qr_url,
       length('/v2/' || v_qr_resource_type || '/' ||
              p_provider_transaction_id || '/qr-code')
     )) <> lower('/v2/' || v_qr_resource_type || '/' ||
                  p_provider_transaction_id || '/qr-code') then
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
  if v_attempt.requires_manual_review then
    return;
  end if;

  v_type_matches := case
    when v_qr_resource_type = 'qris' then v_attempt.payment_type = 'qris'
    else v_attempt.payment_type in ('gopay', 'qris')
  end;

  if v_attempt.qr_code_url = p_payment_qr_url
     and lower(v_attempt.provider_transaction_id) = lower(p_provider_transaction_id)
     and v_type_matches then
    return;
  end if;
  if v_attempt.qr_code_url is not null
     or lower(v_attempt.provider_transaction_id) <> lower(p_provider_transaction_id)
     or v_type_matches is not true
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
  v_fraud text := lower(btrim(coalesce(p_fraud_status, '')));
  v_transaction_id text := lower(
    nullif(btrim(coalesce(p_transaction_id, '')), '')
  );
  v_payment_type text := lower(nullif(
    left(btrim(coalesce(p_payment_type, '')), 100),
    ''
  ));
  v_is_qris_flow boolean;
  v_is_paid boolean;
  v_guard_reason text;
begin
  perform private.require_service_role();

  -- Keep the wrapper's validation order identical to the base state machine.
  -- No fail-closed branch may turn malformed, mismatched, or stale input into a
  -- newer provider fact.
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

  if p_gross_amount::numeric <> v_attempt.expected_amount::numeric then
    return public.apply_midtrans_payment_status_base(
      p_provider_order_id,
      p_transaction_status,
      p_fraud_status,
      p_status_code,
      p_gross_amount,
      v_transaction_id,
      v_payment_type,
      p_provider_event_at
    );
  end if;

  if p_provider_event_at is not null
     and v_attempt.last_provider_event_at is not null
     and p_provider_event_at < v_attempt.last_provider_event_at then
    return public.apply_midtrans_payment_status_base(
      p_provider_order_id,
      p_transaction_status,
      p_fraud_status,
      p_status_code,
      p_gross_amount,
      v_transaction_id,
      v_payment_type,
      p_provider_event_at
    );
  end if;

  -- requested_method is the immutable local product contract. The provider
  -- may validly change gopay -> qris after this native QR image is scanned.
  v_is_qris_flow := lower(coalesce(v_attempt.requested_method, '')) = 'qris'
    or v_attempt.qr_code_url is not null
    or v_payment_type = 'qris';
  v_is_paid := v_status = 'settlement'
    or (v_status = 'capture' and v_fraud = 'accept');

  if v_is_qris_flow
     and v_transaction_id is not null
     and v_transaction_id !~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' then
    v_guard_reason := 'qris_transaction_id_invalid';
  elsif v_is_qris_flow
        and v_attempt.provider_transaction_id is not null
        and v_transaction_id is not null
        and lower(v_attempt.provider_transaction_id) <> v_transaction_id then
    v_guard_reason := 'qris_transaction_id_changed';
  end if;

  if v_guard_reason is not null and not v_is_paid then
    update public.payment_attempts
    set requires_manual_review = true,
        review_reason = coalesce(review_reason, v_guard_reason),
        checkout_lease_token = null,
        checkout_lease_expires_at = null,
        last_synced_at = now(),
        last_error_code = v_guard_reason
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false,
      'reason', case
        when v_guard_reason = 'qris_transaction_id_changed'
          then 'transaction_id_conflict'
        else v_guard_reason
      end,
      'order_id', v_order.id,
      'payment_status', v_attempt.status,
      'order_status', v_order.status,
      'requires_manual_review', true
    );
  end if;

  if v_is_qris_flow and v_is_paid then
    if v_transaction_id is null then
      v_guard_reason := coalesce(
        v_guard_reason,
        'qris_transaction_id_missing'
      );
    elsif v_payment_type is distinct from 'qris' then
      v_guard_reason := coalesce(
        v_guard_reason,
        'qris_provider_type_not_confirmed'
      );
    end if;
  end if;

  -- The native GoPay response also carries a deeplink, but SaveBite never
  -- exposes it. A paid QRIS checkout therefore requires both an immutable UUID
  -- transaction identity and authoritative payment_type=qris. Any first paid
  -- snapshot that cannot prove both is quarantined before fulfilment.
  if v_guard_reason is not null
     and v_is_qris_flow
     and v_is_paid then
    if v_attempt.status in ('refunded', 'partial_refund', 'disputed') then
      update public.payment_attempts
      set last_synced_at = now()
      where id = v_attempt.id;
      return jsonb_build_object(
        'applied', false,
        'reason', 'terminal_state_preserved',
        'order_id', v_order.id,
        'payment_status', v_attempt.status,
        'order_status', v_order.status,
        'requires_manual_review', v_attempt.requires_manual_review
      );
    end if;

    if v_order.payment_verified_at is null
       and v_order.status = 'pending'
       and v_attempt.status in ('creating', 'checkout_created', 'pending') then
      perform private.release_midtrans_reservation(v_attempt.id, 'disputed');
      update public.orders
      set status = 'cancelled',
          cancelled_at = coalesce(cancelled_at, now()),
          payment_verified_at = coalesce(payment_verified_at, now()),
          payment_provider_reference = coalesce(
            payment_provider_reference,
            case
              when v_transaction_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
                then v_transaction_id
              else null
            end,
            v_attempt.provider_order_id
          ),
          pickup_token_hash = null,
          pickup_code_hint = null,
          pickup_token_issued_at = null,
          pickup_token_expires_at = null,
          updated_at = now()
      where id = v_order.id;

      update public.payment_attempts
      set status = 'disputed',
          provider_status = v_status,
          fraud_status = nullif(v_fraud, ''),
          status_code = p_status_code,
          provider_transaction_id = case
            when v_transaction_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
                 and (
                   provider_transaction_id is null
                   or lower(provider_transaction_id) = v_transaction_id
                 )
              then coalesce(provider_transaction_id, v_transaction_id)
            else provider_transaction_id
          end,
          payment_type = case
            when qr_code_url ~ '/v2/qris/' then payment_type
            when v_payment_type in ('gopay', 'qris') then v_payment_type
            else payment_type
          end,
          paid_at = coalesce(paid_at, now()),
          terminal_at = coalesce(terminal_at, now()),
          checkout_lease_token = null,
          checkout_lease_expires_at = null,
          last_provider_event_at = coalesce(
            p_provider_event_at,
            last_provider_event_at
          ),
          last_synced_at = now(),
          last_error_code = v_guard_reason,
          requires_manual_review = true,
          review_reason = coalesce(review_reason, v_guard_reason)
      where id = v_attempt.id;
      return jsonb_build_object(
        'applied', true,
        'reason', v_guard_reason,
        'order_id', v_order.id,
        'payment_status', 'disputed',
        'order_status', 'cancelled',
        'requires_manual_review', true
      );
    end if;

    if v_order.status = 'redeemed' then
      perform private.hold_redeemed_order_income(v_order.id, v_guard_reason);
    end if;
    update public.orders
    set payment_verified_at = coalesce(payment_verified_at, now()),
        payment_provider_reference = coalesce(
          payment_provider_reference,
          case
            when v_transaction_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
              then v_transaction_id
            else null
          end,
          v_attempt.provider_order_id
        ),
        pickup_token_hash = case
          when status = 'redeemed' then pickup_token_hash else null end,
        pickup_code_hint = case
          when status = 'redeemed' then pickup_code_hint else null end,
        pickup_token_issued_at = case
          when status = 'redeemed' then pickup_token_issued_at else null end,
        pickup_token_expires_at = case
          when status = 'redeemed' then pickup_token_expires_at else null end,
        updated_at = now()
    where id = v_order.id;
    update public.payment_attempts
    set status = case
          when status in (
            'creating', 'checkout_created', 'pending', 'failed',
            'cancelled', 'expired'
          ) then 'disputed'
          else status
        end,
        provider_status = v_status,
        fraud_status = nullif(v_fraud, ''),
        status_code = p_status_code,
        provider_transaction_id = case
          when v_transaction_id ~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
               and (
                 provider_transaction_id is null
                 or lower(provider_transaction_id) = v_transaction_id
               )
            then coalesce(provider_transaction_id, v_transaction_id)
          else provider_transaction_id
        end,
        payment_type = case
          when qr_code_url ~ '/v2/qris/' then payment_type
          when v_payment_type in ('gopay', 'qris') then v_payment_type
          else payment_type
        end,
        paid_at = coalesce(paid_at, now()),
        terminal_at = case
          when status in (
            'creating', 'checkout_created', 'pending', 'failed',
            'cancelled', 'expired'
          ) then coalesce(terminal_at, now())
          else terminal_at
        end,
        checkout_lease_token = null,
        checkout_lease_expires_at = null,
        last_provider_event_at = coalesce(
          p_provider_event_at,
          last_provider_event_at
        ),
        last_synced_at = now(),
        last_error_code = v_guard_reason,
        requires_manual_review = true,
        review_reason = coalesce(review_reason, v_guard_reason)
    where id = v_attempt.id;
    return jsonb_build_object(
      'applied', false,
      'reason', v_guard_reason,
      'order_id', v_order.id,
      'payment_status', case
        when v_attempt.status in (
          'creating', 'checkout_created', 'pending', 'failed',
          'cancelled', 'expired'
        ) then 'disputed'
        else v_attempt.status
      end,
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
    v_transaction_id,
    v_payment_type,
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

  if lower(coalesce(v_attempt.requested_method, '')) <> 'qris'
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
    'requires_manual_review', v_attempt.requires_manual_review
  );
end
$$;

revoke all on function public.complete_midtrans_qris_checkout(uuid,text,text,text)
  from public, anon, authenticated;
revoke all on function public.backfill_midtrans_qris_checkout(uuid,text,text)
  from public, anon, authenticated;
revoke all on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated;
grant execute on function public.complete_midtrans_qris_checkout(uuid,text,text,text)
  to service_role;
grant execute on function public.backfill_midtrans_qris_checkout(uuid,text,text)
  to service_role;
grant execute on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) to service_role;

comment on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) is
  'Applies authoritative Midtrans state for native QRIS, including the documented GoPay-to-QRIS provider-type transition.';

commit;
