-- SaveBite: short-lived, rotating pickup QR tokens.
-- Apply after 0002_security_hardening.sql.

begin;

alter table public.orders
  add column if not exists pickup_token_expires_at timestamptz;

update public.orders
set pickup_token_expires_at = least(
  expires_at,
  coalesce(pickup_token_issued_at, created_at, now()) + interval '90 seconds'
)
where pickup_token_hash is not null
  and pickup_token_expires_at is null;

alter table public.orders
  drop constraint if exists orders_pickup_token_expiry_check;
alter table public.orders
  add constraint orders_pickup_token_expiry_check check (
    pickup_token_hash is null or pickup_token_expires_at is not null
  );

create or replace function private.set_pickup_token_expiry()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
begin
  if new.pickup_token_hash is null then
    new.pickup_token_expires_at := null;
  elsif tg_op = 'INSERT'
     or new.pickup_token_hash is distinct from old.pickup_token_hash then
    new.pickup_token_expires_at := least(
      new.expires_at,
      now() + interval '90 seconds'
    );
  end if;
  return new;
end
$$;

drop trigger if exists set_pickup_token_expiry on public.orders;
create trigger set_pickup_token_expiry
before insert or update of pickup_token_hash on public.orders
for each row execute function private.set_pickup_token_expiry();

-- Recreate redeem with the additional token TTL check. The order deadline,
-- pickup window, merchant ownership, one-time ledger insert, and inventory
-- semantics remain identical to the hardened implementation.
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
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_code is null or length(p_code) < 32 then raise exception 'invalid pickup token'; end if;

  select * into v_order
  from public.orders
  where pickup_token_hash = extensions.digest(p_code, 'sha256')
  for update;
  if not found then raise exception 'order not found'; end if;

  select user_id into v_owner from public.merchants where id = v_order.merchant_id;
  if v_owner is distinct from v_uid then raise exception 'order does not belong to your merchant'; end if;
  if v_order.status = 'redeemed' then raise exception 'order was already redeemed'; end if;
  if v_order.status not in ('paid', 'ready') then raise exception 'order is not redeemable'; end if;
  if v_order.pickup_token_expires_at is null
     or v_order.pickup_token_expires_at <= now() then
    raise exception 'pickup token has expired';
  end if;
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;
  if v_order.pickup_start_at is not null and now() < v_order.pickup_start_at then
    raise exception 'pickup window has not started';
  end if;
  if v_order.pickup_end_at is not null and now() >= v_order.pickup_end_at then
    raise exception 'pickup window has ended';
  end if;

  update public.orders
  set status = 'redeemed', redeemed_at = now(), pickup_token_used_at = now()
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

revoke all on function private.set_pickup_token_expiry() from public, anon, authenticated;
revoke all on function public.redeem_order(text) from public, anon;
grant execute on function public.redeem_order(text) to authenticated;

comment on column public.orders.pickup_token_expires_at is
  'Expiry for the current hashed pickup token. Every rotation is valid for at most 90 seconds.';

commit;
