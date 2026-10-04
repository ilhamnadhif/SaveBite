-- SaveBite: hosted Midtrans Snap checkout with every payment method.
--
-- The web app sends the customer straight to the Midtrans-hosted Snap page and
-- lets them choose any payment method active on the merchant account. That
-- checkout is requested as `MIDTRANS`. `QRIS` keeps its Other-QRIS-only Snap
-- contract and its paid-rail guard in apply_midtrans_payment_status.
--
-- No state machine changes: apply_midtrans_payment_status (0021) already sends
-- every Snap attempt that was not requested as QRIS through the audited
-- multi-channel base from 0012, which keeps deny/failure retryable so the
-- customer can pick another channel on the same Snap page.
-- Apply after 0021_snap_webview_checkout.sql.

begin;

-- The sole authenticated reservation entry point accepts both checkout kinds
-- and stores the canonical upper-case method.
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
declare
  v_method text := lower(btrim(coalesce(p_method, '')));
begin
  if v_method not in ('qris', 'midtrans') then
    raise exception 'payment method must be QRIS or MIDTRANS';
  end if;
  return public.purchase_bag_base(
    p_bag_id,
    p_qty,
    upper(v_method),
    p_idempotency_key
  );
end
$$;

revoke all on function public.purchase_bag(uuid,integer,text,text)
  from public, anon, authenticated;
grant execute on function public.purchase_bag(uuid,integer,text,text)
  to authenticated;

-- Same claim as 0021, except that a MIDTRANS attempt is claimable and the
-- claim reports the attempt's own method, which selects the Snap payload.
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

  if lower(btrim(v_attempt.requested_method)) not in ('qris', 'midtrans') then
    raise exception 'payment method must be QRIS or MIDTRANS'
      using errcode = '55000';
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
    'requested_method', upper(btrim(v_attempt.requested_method)),
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

revoke all on function public.claim_midtrans_checkout(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.claim_midtrans_checkout(uuid,uuid)
  to service_role;

comment on function public.purchase_bag(uuid,integer,text,text) is
  'Authenticated wrapper around the atomic reservation implementation; accepts QRIS or the hosted all-method MIDTRANS checkout.';
comment on function public.claim_midtrans_checkout(uuid,uuid) is
  'Service-only idempotent Snap claim/reuse for QRIS and MIDTRANS attempts; browser credentials are later exposed only through the owner- and review-safe consumer projection.';

commit;
