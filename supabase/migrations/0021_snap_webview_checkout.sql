-- SaveBite: QRIS-only Midtrans Snap checkout for an in-app WebView.
--
-- New checkouts use one short-lived Snap redirect URL restricted to Other QRIS.
-- Historical native Core QRIS attempts remain reconcilable, but their creation
-- and QR backfill entry points are retired after this coordinated cutover.
-- Apply after 0020_gopay_native_qris.sql while checkout creation is paused.

begin;

-- Freeze payment/order writes for the short cutover transaction. This closes
-- the race where a Core checkout could be claimed after the preflight SELECT
-- but before the old completion RPCs are revoked.
lock table public.orders, public.payment_attempts
  in share row exclusive mode;

-- A provider order ID is single-use.  Do not cut over while an unverified Core
-- reservation or checkout lease can still be using one; drain/expire it first.
do $$
begin
  if exists (
    select 1
    from public.payment_attempts pa
    join public.orders o on o.id = pa.order_id
    where o.payment_verified_at is null
      and (
        (
          pa.status in ('creating', 'checkout_created', 'pending')
          and pa.payment_expires_at > now()
        )
        or pa.checkout_lease_expires_at > now()
      )
  ) then
    raise exception
      'Snap rollout blocked by an active unverified Core checkout';
  end if;
end
$$;

-- A Snap token is an opaque, case-sensitive browser credential, while the
-- redirect URL carries a separate UUID resource.  Both official redirect
-- generations are accepted for existing history.  Query strings, fragments,
-- alternate ports, credentials, and non-Midtrans origins cannot satisfy this
-- constraint.
alter table public.payment_attempts
  drop constraint if exists payment_attempts_snap_pair_check;
alter table public.payment_attempts
  drop constraint if exists payment_attempts_snap_length_check;
alter table public.payment_attempts
  drop constraint if exists payment_attempts_snap_contract_check;
alter table public.payment_attempts
  add constraint payment_attempts_snap_contract_check
  check (
    (
      snap_token is null
      and redirect_url is null
    )
    or (
      snap_token is not null
      and redirect_url is not null
      and length(snap_token) between 8 and 512
      and snap_token ~ '^[A-Za-z0-9_-]+$'
      and length(redirect_url) <= 2048
      and redirect_url ~ '^https://app(\.sandbox)?\.midtrans\.com/snap/(v2/vtweb|v3/redirection|v4/redirection)/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
    )
  );

alter table public.payment_attempts
  drop constraint if exists payment_attempts_checkout_artifact_check;
alter table public.payment_attempts
  add constraint payment_attempts_checkout_artifact_check
  check (
    qr_code_url is null
    or (snap_token is null and redirect_url is null)
  );

comment on column public.payment_attempts.snap_token is
  'Opaque Midtrans Snap.js token exposed only to its owning consumer while checkout is live and not review-held.';
comment on column public.payment_attempts.redirect_url is
  'Short-lived Midtrans Snap redirect URL exposed only to its owning consumer while live and not review-held.';

-- The function row type gains the Snap.js token, so remove and recreate its
-- dependent consumer view explicitly.  A manual-review hold is also a checkout
-- hold: neither browser credential remains visible while payment identity or
-- state is quarantined.
drop view public.consumer_orders;
drop function public.get_consumer_payment_projection(uuid);

create function public.get_consumer_payment_projection(
  p_order_id uuid
)
returns table (
  payment_redirect_url text,
  status text,
  payment_expires_at timestamptz,
  payment_type text,
  provider_order_id text,
  requires_manual_review boolean,
  payment_snap_token text
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
            and pa.snap_token is not null
            and pa.redirect_url is not null
            and pa.qr_code_url is null
           then pa.redirect_url
           else null
         end,
         pa.status,
         pa.payment_expires_at,
         pa.payment_type,
         pa.provider_order_id,
         pa.requires_manual_review,
         case
           when pa.status in ('creating', 'checkout_created', 'pending')
            and pa.payment_expires_at > now()
            and not pa.requires_manual_review
            and pa.snap_token is not null
            and pa.redirect_url is not null
            and pa.qr_code_url is null
           then pa.snap_token
           else null
         end
  from public.payment_attempts pa
  join public.orders o on o.id = pa.order_id
  where pa.order_id = p_order_id
    and o.consumer_id = auth.uid()
$$;

revoke all on function public.get_consumer_payment_projection(uuid)
  from public, anon, authenticated;
grant execute on function public.get_consumer_payment_projection(uuid)
  to authenticated;

-- Preserve every existing consumer_orders column in place and append the
-- review-safe Snap.js token.  merchant_orders is intentionally unchanged.
create view public.consumer_orders
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
       qris.payment_qr_url,
       pa.payment_snap_token
from public.orders o
left join lateral public.get_consumer_payment_projection(o.id) pa on true
left join lateral public.get_consumer_qris_projection(o.id) qris on true
where o.consumer_id = auth.uid();

grant select on public.consumer_orders to authenticated;

-- Claim or reuse one Snap session.  Only the service receives creation inputs;
-- after completion the owning consumer receives the validated Snap.js token
-- and redirect URL through the review-safe projection below.
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

  -- Global payment lock order: order, then attempt.
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

  if v_order.payment_verified_at is not null
     or v_order.status <> 'pending'
     or v_attempt.status in (
       'paid', 'failed', 'cancelled', 'expired', 'refunded',
       'partial_refund', 'disputed'
     ) then
    return jsonb_build_object(
      'mode', 'completed',
      'order_id', v_order.id,
      'payment_status', v_attempt.status
    );
  end if;

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

  if lower(btrim(v_attempt.requested_method)) <> 'qris' then
    raise exception 'payment method must be QRIS' using errcode = '55000';
  end if;
  if v_attempt.reservation_state <> 'held' then
    raise exception 'payment is no longer eligible' using errcode = '55000';
  end if;
  if v_attempt.payment_expires_at <= now() then
    raise exception 'payment reservation has expired';
  end if;

  if v_attempt.snap_token is not null and v_attempt.redirect_url is not null then
    if v_attempt.qr_code_url is not null then
      raise exception 'conflicting checkout artifacts' using errcode = '55000';
    end if;
    return jsonb_build_object(
      'mode', 'reuse',
      'order_id', v_order.id,
      'payment_status', v_attempt.status,
      'redirect_url', v_attempt.redirect_url
    );
  end if;

  -- A Core QR is bound to this provider order ID and can never be converted to
  -- Snap in place.  Historical Core reconciliation remains available below.
  if v_attempt.qr_code_url is not null then
    raise exception 'active Core QR checkout cannot be reused by Snap'
      using errcode = '55000';
  end if;

  -- A provider event without a persisted checkout artifact is ambiguous.  Do
  -- not reuse its single-use provider order ID for another Snap create call.
  if v_attempt.provider_status is not null
     or v_attempt.provider_transaction_id is not null then
    update public.payment_attempts
    set requires_manual_review = true,
        review_reason = coalesce(
          review_reason,
          'checkout_artifact_missing_after_provider_event'
        ),
        checkout_lease_token = null,
        checkout_lease_expires_at = null,
        last_error_code = 'checkout_artifact_missing_after_provider_event'
    where id = v_attempt.id;
    return jsonb_build_object(
      'mode', 'completed',
      'order_id', v_order.id,
      'payment_status', v_attempt.status
    );
  end if;

  if v_attempt.checkout_lease_expires_at is not null
     and v_attempt.checkout_lease_expires_at > now() then
    return jsonb_build_object(
      'mode', 'in_progress',
      'order_id', v_order.id,
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
  from public.profiles p
  where p.id = v_order.consumer_id;

  return jsonb_build_object(
    'mode', 'create',
    'lease_token', v_lease,
    'order_id', v_order.id,
    'midtrans_order_id', v_attempt.provider_order_id,
    'gross_amount', v_attempt.expected_amount,
    'payment_expires_at', v_attempt.payment_expires_at,
    'requested_method', 'QRIS',
    'customer', jsonb_build_object(
      'first_name', left(
        coalesce(nullif(btrim(v_order.consumer_name), ''), 'Pelanggan'),
        255
      ),
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
          'id', 'service-fee',
          'price', v_order.service_fee,
          'quantity', 1,
          'name', 'Biaya layanan'
        )
      )
      else '[]'::jsonb
    end
  );
end
$$;

-- Persist a Snap checkout only against the exact live lease that created it.
-- Repeating the same completion is harmless; every conflicting artifact fails
-- closed before the URL can reach the consumer projection.
create or replace function public.complete_midtrans_snap_checkout(
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
declare
  v_order public.orders;
  v_attempt public.payment_attempts;
begin
  perform private.require_service_role();
  if p_order_id is null then raise exception 'order not found'; end if;
  if p_lease_token is null or p_lease_token !~ '^[0-9a-f]{48}$' then
    raise exception 'invalid checkout lease';
  end if;
  if p_snap_token is null
     or length(p_snap_token) not between 8 and 512
     or p_snap_token !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'invalid Snap token';
  end if;
  if p_redirect_url is null
     or length(p_redirect_url) > 2048
     or p_redirect_url !~ '^https://app(\.sandbox)?\.midtrans\.com/snap/(v2/vtweb|v3/redirection|v4/redirection)/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' then
    raise exception 'invalid Midtrans Snap redirect URL';
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

  if v_attempt.snap_token = p_snap_token
     and v_attempt.redirect_url = p_redirect_url
     and v_attempt.qr_code_url is null then
    if v_attempt.requires_manual_review then
      raise exception 'payment requires manual review' using errcode = '55000';
    end if;
    return;
  end if;

  if v_attempt.requires_manual_review then
    raise exception 'payment requires manual review' using errcode = '55000';
  end if;
  if v_attempt.snap_token is not null
     or v_attempt.redirect_url is not null
     or v_attempt.qr_code_url is not null then
    raise exception 'conflicting checkout artifact' using errcode = '55000';
  end if;
  if v_attempt.provider_status is not null
     or v_attempt.provider_transaction_id is not null
     or v_attempt.payment_type is not null then
    raise exception 'provider order already has transaction state'
      using errcode = '55000';
  end if;
  if v_order.status <> 'pending'
     or v_order.payment_verified_at is not null
     or v_attempt.status not in ('creating', 'pending')
     or v_attempt.reservation_state <> 'held'
     or v_attempt.payment_expires_at <= now()
     or v_attempt.checkout_lease_token is distinct from p_lease_token
     or v_attempt.checkout_lease_expires_at <= now() then
    raise exception 'checkout lease is no longer valid' using errcode = '55000';
  end if;

  update public.payment_attempts
  set snap_token = p_snap_token,
      redirect_url = p_redirect_url,
      status = 'checkout_created',
      checkout_lease_token = null,
      checkout_lease_expires_at = null,
      last_error_code = null
  where id = v_attempt.id;
end
$$;

-- The status function returns no checkout artifact, but tells the Edge layer
-- which reconciliation contract owns this provider order.
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
  v_checkout_mode text;
begin
  perform private.require_service_role();
  select * into v_order
  from public.orders
  where id = p_order_id;
  if not found then raise exception 'order not found'; end if;

  select * into v_attempt
  from public.payment_attempts
  where order_id = v_order.id;
  if not found then raise exception 'payment attempt not found'; end if;

  if v_order.consumer_id = p_actor_id then
    v_actor_kind := 'consumer';
  else
    select user_id into v_owner
    from public.merchants
    where id = v_order.merchant_id;
    if v_owner is distinct from p_actor_id
       or v_order.payment_verified_at is null then
      raise exception 'order not found';
    end if;
    v_actor_kind := 'merchant';
  end if;

  v_checkout_mode := case
    when v_attempt.snap_token is not null
     and v_attempt.redirect_url is not null
     and v_attempt.qr_code_url is null then 'snap'
    when v_attempt.qr_code_url is not null
     and v_attempt.snap_token is null
     and v_attempt.redirect_url is null then 'core_qris'
    else 'uninitialized'
  end;

  return jsonb_build_object(
    'order_id', v_order.id,
    'actor_kind', v_actor_kind,
    'checkout_mode', v_checkout_mode,
    'midtrans_order_id', v_attempt.provider_order_id,
    'payment_status', v_attempt.status,
    'payment_expires_at', v_attempt.payment_expires_at,
    'requires_manual_review', v_attempt.requires_manual_review
  );
end
$$;

-- Retain 0020's single-identity Core QRIS reconciliation under a private name.
-- New Snap attempts dispatch to the original multi-attempt state machine.
alter function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) rename to apply_midtrans_payment_status_core_history;
alter function public.apply_midtrans_payment_status_core_history(
  text,text,text,text,text,text,text,timestamptz
) set schema private;

revoke all on function private.apply_midtrans_payment_status_core_history(
  text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated;
grant execute on function private.apply_midtrans_payment_status_core_history(
  text,text,text,text,text,text,text,timestamptz
) to service_role;

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
  v_order public.orders;
  v_attempt public.payment_attempts;
  v_status text := lower(btrim(coalesce(p_transaction_status, '')));
  v_fraud text := lower(btrim(coalesce(p_fraud_status, '')));
  v_transaction_id text := lower(nullif(
    btrim(coalesce(p_transaction_id, '')),
    ''
  ));
  v_payment_type text := lower(nullif(
    left(btrim(coalesce(p_payment_type, '')), 100),
    ''
  ));
  v_is_snap boolean;
  v_is_paid boolean;
  v_guard_reason text;
  v_result jsonb;
begin
  perform private.require_service_role();

  -- Match the generic state machine's validation and lock order before any
  -- Snap-specific quarantine can persist a provider fact.
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

  -- Let the generic base own amount-mismatch and stale-event behavior so the
  -- ordering remains identical for Core history and Snap.
  if p_gross_amount::numeric <> v_attempt.expected_amount::numeric
     or (
       p_provider_event_at is not null
       and v_attempt.last_provider_event_at is not null
       and p_provider_event_at < v_attempt.last_provider_event_at
     ) then
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

  v_is_snap := v_attempt.snap_token is not null
    and v_attempt.redirect_url is not null
    and v_attempt.qr_code_url is null;

  if not v_is_snap then
    return private.apply_midtrans_payment_status_core_history(
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

  v_is_paid := v_status = 'settlement'
    or (v_status = 'capture' and v_fraud = 'accept');

  -- Only the current QRIS-only product contract rejects another paid rail.
  -- Historical Snap methods remain reconcilable through the generic base.
  if v_is_paid and lower(btrim(v_attempt.requested_method)) = 'qris' then
    if p_status_code <> '200' then
      v_guard_reason := 'snap_success_status_code_invalid';
    elsif v_transaction_id is null then
      v_guard_reason := 'snap_transaction_id_missing';
    elsif v_transaction_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_guard_reason := 'snap_transaction_id_invalid';
    elsif v_payment_type is distinct from 'qris' then
      v_guard_reason := 'snap_provider_type_not_confirmed';
    end if;
  end if;

  if v_guard_reason is not null then
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
              when v_transaction_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
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
    else
      if v_order.status = 'redeemed' then
        perform private.hold_redeemed_order_income(
          v_order.id,
          v_guard_reason
        );
      end if;
      update public.orders
      set payment_verified_at = coalesce(payment_verified_at, now()),
          payment_provider_reference = coalesce(
            payment_provider_reference,
            case
              when v_transaction_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
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
    end if;

    update public.payment_attempts
    set status = 'disputed',
        provider_status = v_status,
        fraud_status = nullif(v_fraud, ''),
        status_code = p_status_code,
        provider_transaction_id = case
          when v_transaction_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            then v_transaction_id
          else provider_transaction_id
        end,
        payment_type = coalesce(v_payment_type, payment_type),
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
      'order_status', case
        when v_order.payment_verified_at is null and v_order.status = 'pending'
          then 'cancelled'
        else v_order.status
      end,
      'requires_manual_review', true
    );
  end if;

  -- The generic audited Snap state machine intentionally keeps deny/failure
  -- retryable before payment, permits a later transaction ID for the same Snap
  -- order, and retains exactly-once stock/refund/dispute behavior.
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
  return v_result;
end
$$;

-- All payment RPCs remain service-role only.  Core creation/backfill is retired,
-- while the private Core history state machine stays callable for reconciliation.
revoke all on function public.claim_midtrans_checkout(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.complete_midtrans_snap_checkout(uuid,text,text,text)
  from public, anon, authenticated;
revoke all on function public.get_midtrans_sync_target(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated;
revoke all on function public.apply_midtrans_payment_status_base(
  text,text,text,text,text,text,text,timestamptz
) from public, anon, authenticated;

grant execute on function public.claim_midtrans_checkout(uuid,uuid)
  to service_role;
grant execute on function public.complete_midtrans_snap_checkout(uuid,text,text,text)
  to service_role;
grant execute on function public.get_midtrans_sync_target(uuid,uuid)
  to service_role;
grant execute on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) to service_role;
grant execute on function public.apply_midtrans_payment_status_base(
  text,text,text,text,text,text,text,timestamptz
) to service_role;

revoke all on function public.complete_midtrans_checkout(uuid,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_midtrans_qris_checkout(uuid,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.backfill_midtrans_qris_checkout(uuid,text,text)
  from public, anon, authenticated, service_role;

comment on function public.claim_midtrans_checkout(uuid,uuid) is
  'Service-only idempotent Snap claim/reuse; browser credentials are later exposed only through the owner- and review-safe consumer projection.';
comment on function public.complete_midtrans_snap_checkout(uuid,text,text,text) is
  'Persists one exact, validated Midtrans Snap checkout against its live creation lease.';
comment on function public.get_midtrans_sync_target(uuid,uuid) is
  'Authorizes payment synchronization and identifies Snap, historical Core QRIS, or uninitialized checkout state without exposing artifacts.';
comment on function public.apply_midtrans_payment_status(
  text,text,text,text,text,text,text,timestamptz
) is
  'Dispatches authoritative Midtrans state to retryable Snap semantics or immutable historical Core QRIS reconciliation.';

commit;
