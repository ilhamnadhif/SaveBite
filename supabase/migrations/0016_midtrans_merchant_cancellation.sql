-- SaveBite: provider-first merchant cancellation for Midtrans orders.
--
-- Apply after 0015_pickup_payment_hardening.sql. A merchant cancellation is
-- first persisted as a fulfilment hold. The Edge Function then asks Midtrans
-- to cancel an unsettled transaction or fully refund a settled transaction.
-- Stock and the local terminal status still change only when the existing
-- authoritative Midtrans state machine observes `cancel` or `refund`.

begin;

-- Claiming is service-only because the actor ID must come from an independently
-- verified Auth session in the Edge Function. The persistent review marker is
-- also the crash/timeout recovery record: retries reuse the same provider
-- action and refund key, while migration 0015 blocks ready/token/redeem paths.
create or replace function public.claim_midtrans_merchant_cancellation(
  p_order_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_order public.orders;
  v_attempt public.payment_attempts;
  v_owner uuid;
  v_mode text := 'claim';
begin
  perform private.require_service_role();
  if p_order_id is null or p_actor_id is null then
    raise exception 'order not found';
  end if;

  -- Preserve the global payment lock order: order, then attempt.
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found then raise exception 'order not found'; end if;

  select * into v_attempt
  from public.payment_attempts
  where order_id = v_order.id
  for update;
  if not found then raise exception 'payment attempt not found'; end if;

  select user_id into v_owner
  from public.merchants
  where id = v_order.merchant_id;
  if v_owner is distinct from p_actor_id then
    raise exception 'order not found';
  end if;

  if v_order.status in ('cancelled', 'refunded')
     and v_attempt.status in ('cancelled', 'refunded') then
    return jsonb_build_object(
      'mode', 'completed',
      'order_id', v_order.id,
      'midtrans_order_id', v_attempt.provider_order_id,
      'payment_status', v_attempt.status
    );
  end if;

  if v_attempt.review_reason = 'merchant_cancellation_requested' then
    v_mode := 'resume';
  else
    if v_order.status not in ('paid', 'preparing', 'ready')
       or v_order.expires_at <= now() then
      raise exception 'order cannot be cancelled from status %', v_order.status;
    end if;
    if v_attempt.status <> 'paid'
       or v_attempt.paid_at is null
       or v_attempt.reservation_state <> 'held'
       or v_attempt.requires_manual_review
       or v_order.is_simulation
       or v_order.payment_verified_at is null
       or nullif(
         btrim(coalesce(v_order.payment_provider_reference, '')),
         ''
       ) is null then
      raise exception 'payment cancellation requires manual review'
        using errcode = '55000';
    end if;

    update public.payment_attempts
    set requires_manual_review = true,
        review_reason = 'merchant_cancellation_requested',
        last_error_code = null
    where id = v_attempt.id
    returning * into v_attempt;

    -- A QR already displayed before this request must not survive the hold.
    update public.orders
    set pickup_token_hash = null,
        pickup_code_hint = null,
        pickup_token_issued_at = null,
        pickup_token_expires_at = null,
        pickup_token_used_at = null,
        updated_at = now()
    where id = v_order.id;
  end if;

  return jsonb_build_object(
    'mode', v_mode,
    'order_id', v_order.id,
    'midtrans_order_id', v_attempt.provider_order_id,
    'provider_transaction_id', v_attempt.provider_transaction_id,
    'payment_status', v_attempt.status,
    'payment_type', v_attempt.payment_type,
    'gross_amount', v_attempt.expected_amount
  );
end
$$;

-- Provider timeouts are ambiguous. Keep the fulfilment hold and store only a
-- bounded, non-secret diagnostic code so a webhook or an idempotent retry can
-- finish reconciliation without ever assuming that the mutation failed.
create or replace function public.record_midtrans_merchant_cancellation_error(
  p_order_id uuid,
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
  set last_error_code = left(
        coalesce(nullif(btrim(p_error_code), ''), 'cancellation_unknown'),
        100
      )
  where order_id = p_order_id
    and requires_manual_review
    and review_reason = 'merchant_cancellation_requested';
end
$$;

-- The existing state machine intentionally treats an unexpected provider
-- cancel after verified payment as a dispute. This narrowly-scoped trigger
-- distinguishes the expected, merchant-requested cancel/refund using the
-- durable marker above. It does not trust an Edge response: provider_status is
-- populated only by apply_midtrans_payment_status after authoritative GET.
create or replace function private.finalize_requested_midtrans_cancellation()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
begin
  if old.review_reason is distinct from 'merchant_cancellation_requested' then
    return new;
  end if;

  if new.provider_status = 'cancel'
     and new.status = 'disputed'
     and exists (
       select 1 from public.orders o
       where o.id = new.order_id and o.status = 'cancelled'
     ) then
    new.status := 'cancelled';
    new.reservation_release_reason := 'payment_cancelled';
    new.requires_manual_review := false;
    new.review_reason := null;
    new.last_error_code := null;
  elsif new.provider_status = 'refund'
        and new.status = 'refunded'
        and exists (
          select 1 from public.orders o
          where o.id = new.order_id and o.status = 'refunded'
        ) then
    new.requires_manual_review := false;
    new.review_reason := null;
    new.last_error_code := null;
  end if;
  return new;
end
$$;

drop trigger if exists finalize_requested_midtrans_cancellation
  on public.payment_attempts;
create trigger finalize_requested_midtrans_cancellation
before update of status, provider_status, requires_manual_review, review_reason
on public.payment_attempts
for each row execute function private.finalize_requested_midtrans_cancellation();

-- Midtrans `transaction_status=refund` means the refund was recorded, but the
-- destination rail can confirm the actual transfer later. Keep every consumer
-- refund notification honest until `bank_confirmed_at` is persisted separately.
create or replace function private.clarify_midtrans_refund_notification()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
begin
  if new.type = 'payment'
     and new.dedupe_key like 'order:%:refunded' then
    new.title := 'Refund diproses';
    new.body := 'Refund telah dikonfirmasi Midtrans untuk diproses. Waktu dana masuk mengikuti metode pembayaran.';
  end if;
  return new;
end
$$;

drop trigger if exists clarify_midtrans_refund_notification
  on public.notifications;
create trigger clarify_midtrans_refund_notification
before insert on public.notifications
for each row execute function private.clarify_midtrans_refund_notification();

update public.notifications
set title = 'Refund diproses',
    body = 'Refund telah dikonfirmasi Midtrans untuk diproses. Waktu dana masuk mengikuti metode pembayaran.'
where type = 'payment'
  and dedupe_key like 'order:%:refunded';

revoke all on function public.claim_midtrans_merchant_cancellation(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.claim_midtrans_merchant_cancellation(uuid,uuid)
  to service_role;
revoke all on function public.record_midtrans_merchant_cancellation_error(uuid,text)
  from public, anon, authenticated;
grant execute on function public.record_midtrans_merchant_cancellation_error(uuid,text)
  to service_role;
revoke all on function private.finalize_requested_midtrans_cancellation()
  from public, anon, authenticated, service_role;
revoke all on function private.clarify_midtrans_refund_notification()
  from public, anon, authenticated, service_role;

comment on function public.claim_midtrans_merchant_cancellation(uuid,uuid) is
  'Service-only idempotent claim that verifies merchant ownership and freezes fulfilment before a provider cancel/refund.';
comment on function public.record_midtrans_merchant_cancellation_error(uuid,text) is
  'Persists a bounded provider cancellation diagnostic while retaining the fail-closed fulfilment hold.';
comment on function private.finalize_requested_midtrans_cancellation() is
  'Clears a merchant cancellation hold only after authoritative Midtrans cancel/refund status has driven the local terminal transition.';
comment on function private.clarify_midtrans_refund_notification() is
  'Describes Midtrans refund as recorded without claiming destination-bank confirmation that is not yet tracked.';
comment on function public.cancel_merchant_order(uuid) is
  'Cancels legacy non-Midtrans orders only; real Midtrans orders use the provider-first midtrans-cancel Edge Function.';

commit;
