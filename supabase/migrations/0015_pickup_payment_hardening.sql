-- SaveBite: bind pickup capabilities to their time window and verified money.
--
-- Apply after 0014_security_advisor_hardening.sql.  Legacy orders without a
-- payment_attempts row keep their existing pickup behaviour.  For gateway
-- orders, readiness, token issuance, and redemption require the authoritative
-- paid state written by the Midtrans service-role state machine.

begin;

-- This predicate deliberately returns true for legacy/non-gateway orders.
-- Once an order has a gateway attempt, however, every independent proof used
-- by the payment state machine must agree and a manual-review hold must block
-- fulfilment. Callers lock the order before evaluating this predicate; the
-- Midtrans state machine uses the same order-first lock order.
create or replace function private.pickup_payment_is_verified(p_order_id uuid)
returns boolean
language sql
stable
set search_path = public, private, pg_catalog
as $$
  select
    not exists (
      select 1
      from public.payment_attempts pa
      where pa.order_id = p_order_id
    )
    or exists (
      select 1
      from public.payment_attempts pa
      join public.orders o on o.id = pa.order_id
      where pa.order_id = p_order_id
        and pa.status = 'paid'
        and pa.paid_at is not null
        and pa.reservation_state = 'held'
        and not pa.requires_manual_review
        and not o.is_simulation
        and o.payment_verified_at is not null
        and nullif(
          btrim(coalesce(o.payment_provider_reference, '')),
          ''
        ) is not null
    )
$$;

revoke all on function private.pickup_payment_is_verified(uuid)
  from public, anon, authenticated;

-- Capabilities issued by older code before the pickup window (or capabilities
-- attached to a gateway order whose payment proof no longer agrees) cannot be
-- grandfathered into the stricter contract. They are hash-only and renewable,
-- so clearing them loses no order data and the consumer can obtain a fresh QR
-- once every guard passes.
update public.orders o
set pickup_code = null,
    pickup_token_hash = null,
    pickup_code_hint = null,
    pickup_token_issued_at = null,
    pickup_token_expires_at = null
where o.pickup_token_hash is not null
  and (
    (
      o.pickup_start_at is not null
      and (
        o.pickup_token_issued_at is null
        or o.pickup_token_issued_at < o.pickup_start_at
      )
    )
    or not private.pickup_payment_is_verified(o.id)
  );

-- Protect the same time invariant even from future server-side code that
-- writes token columns directly instead of going through issue_pickup_token.
alter table public.orders
  drop constraint if exists orders_pickup_token_window_check;
alter table public.orders
  add constraint orders_pickup_token_window_check check (
    pickup_token_hash is null
    or pickup_start_at is null
    or (
      pickup_token_issued_at is not null
      and pickup_token_issued_at >= pickup_start_at
    )
  );

create or replace function public.mark_order_ready(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders;
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

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
  if v_order.status <> 'paid' then
    raise exception 'only paid orders can be marked ready';
  end if;
  if not private.pickup_payment_is_verified(v_order.id) then
    -- Keep the established client-facing error contract while refusing an
    -- inconsistent or review-held gateway payment.
    raise exception 'only paid orders can be marked ready';
  end if;
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;

  update public.orders
  set status = 'ready', ready_at = now()
  where id = v_order.id
  returning * into v_order;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_reference', v_order.order_reference,
    'status', v_order.status,
    'ready_at', v_order.ready_at,
    'expires_at', v_order.expires_at
  );
end
$$;

create or replace function public.issue_pickup_token(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders;
  v_token text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;
  if not found or v_order.consumer_id is distinct from v_uid then
    raise exception 'order not found';
  end if;
  if v_order.status <> 'ready' then
    raise exception 'order is not ready for pickup';
  end if;
  if not private.pickup_payment_is_verified(v_order.id) then
    raise exception 'order is not ready for pickup';
  end if;
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;
  if v_order.pickup_start_at is not null
     and now() < v_order.pickup_start_at then
    raise exception 'pickup window has not started';
  end if;
  if v_order.pickup_end_at is not null
     and now() >= v_order.pickup_end_at then
    raise exception 'pickup window has ended';
  end if;

  -- encode(bytea, 'hex') emits exactly 48 lowercase hexadecimal characters.
  v_token := 'SB2_' || encode(extensions.gen_random_bytes(24), 'hex');
  update public.orders
  set pickup_token_hash = extensions.digest(v_token, 'sha256'),
      pickup_code_hint = right(v_token, 6),
      pickup_token_issued_at = now(),
      pickup_token_used_at = null
  where id = v_order.id
  returning * into v_order;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_reference', v_order.order_reference,
    'pickup_code', v_token,
    'pickup_code_hint', right(v_token, 6),
    'expires_at', v_order.pickup_token_expires_at,
    'order_expires_at', v_order.expires_at
  );
end
$$;

create or replace function public.redeem_order(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  v_order public.orders;
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_code is null
     or octet_length(p_code) <> 52
     or p_code !~ '^SB2_[0-9A-Fa-f]{48}$' then
    raise exception 'invalid pickup token';
  end if;

  select * into v_order
  from public.orders
  where pickup_token_hash = extensions.digest(p_code, 'sha256')
  for update;
  if not found then raise exception 'order not found'; end if;

  select user_id into v_owner
  from public.merchants
  where id = v_order.merchant_id;
  if v_owner is distinct from v_uid then
    raise exception 'order does not belong to your merchant';
  end if;
  if v_order.status <> 'ready' then
    raise exception 'order is not redeemable';
  end if;
  if not private.pickup_payment_is_verified(v_order.id) then
    raise exception 'order is not redeemable';
  end if;
  if v_order.pickup_token_expires_at is null
     or v_order.pickup_token_expires_at <= now() then
    raise exception 'pickup token has expired';
  end if;
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;
  if v_order.pickup_start_at is not null
     and now() < v_order.pickup_start_at then
    raise exception 'pickup window has not started';
  end if;
  if v_order.pickup_end_at is not null
     and now() >= v_order.pickup_end_at then
    raise exception 'pickup window has ended';
  end if;

  update public.orders
  set status = 'redeemed',
      redeemed_at = now(),
      pickup_token_used_at = now(),
      pickup_token_hash = null,
      pickup_code_hint = null,
      pickup_token_issued_at = null,
      pickup_token_expires_at = null
  where id = v_order.id
  returning * into v_order;

  insert into public.transactions
    (merchant_id, title, subtitle, amount, kind, reference_type,
     reference_id, idempotency_key, metadata, created_by)
  values
    (v_order.merchant_id,
     'Order ' || v_order.order_reference,
     'Pendapatan bersih setelah komisi Rp' || v_order.commission_amount,
     v_order.merchant_net_amount, 'income', 'order', v_order.id,
     'order:' || v_order.id, jsonb_build_object(
       'subtotal', v_order.subtotal,
       'commission_amount', v_order.commission_amount,
       'service_fee', v_order.service_fee
     ), v_uid)
  on conflict (reference_type, reference_id, kind)
    where reference_type is not null and reference_id is not null
    do nothing;

  update public.merchants
  set bags_saved = bags_saved + v_order.quantity
  where id = v_order.merchant_id;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_reference', v_order.order_reference,
    'pickup_code', v_order.order_reference,
    'quantity', v_order.quantity,
    'customer_name', v_order.consumer_name,
    'bag_title', v_order.bag_title,
    'created_at', v_order.created_at,
    'redeemed_at', v_order.redeemed_at,
    'merchant_net_amount', v_order.merchant_net_amount
  );
end
$$;

-- Reassert the existing public API. Signatures and return shapes are unchanged.
revoke all on function public.mark_order_ready(uuid)
  from public, anon, authenticated;
grant execute on function public.mark_order_ready(uuid) to authenticated;
revoke all on function public.issue_pickup_token(uuid)
  from public, anon, authenticated;
grant execute on function public.issue_pickup_token(uuid) to authenticated;
revoke all on function public.redeem_order(text)
  from public, anon, authenticated;
grant execute on function public.redeem_order(text) to authenticated;

comment on function private.pickup_payment_is_verified(uuid) is
  'Legacy-compatible pickup gate: gateway orders require one authoritative paid, held, non-review attempt and matching verified order proof.';
comment on function public.mark_order_ready(uuid) is
  'Owner-only readiness transition; gateway orders must have authoritative verified payment.';
comment on function public.issue_pickup_token(uuid) is
  'Issues a rotating 192-bit pickup token only during the pickup window for a ready, payment-eligible order.';
comment on function public.redeem_order(text) is
  'Redeems one exact SB2_ plus 48-hex, unexpired token for a ready, payment-eligible order owned by the merchant.';

commit;
