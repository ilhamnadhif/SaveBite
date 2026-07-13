-- SaveBite - merchant order cancellation and owner-scoped review inbox.
--
-- Payment settlement remains intentionally outside this migration. The order
-- cancellation function only operates on orders which have already reached an
-- eligible operational state.

begin;

-- `preparing` is already represented by the clients and is an eligible
-- cancellation state. Keep the database contract aligned with that lifecycle.
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in (
    'pending', 'paid', 'preparing', 'ready', 'redeemed', 'cancelled',
    'expired', 'refunded'
  ));

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
  v_stock_restored boolean := false;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_order_id is null then
    raise exception 'order not found';
  end if;

  -- The row lock serializes cancellation against ready/redeem/expiry. A retry
  -- that observes `cancelled` returns successfully without restoring stock a
  -- second time.
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
      'order_id', v_order.id,
      'stock_restored', false,
      'already_cancelled', true
    );
  end if;

  if v_order.status not in ('paid', 'preparing', 'ready') then
    raise exception 'order cannot be cancelled from status %', v_order.status;
  end if;

  update public.orders
  set status = 'cancelled',
      cancelled_at = coalesce(cancelled_at, now()),
      pickup_token_hash = null,
      pickup_code_hint = null,
      pickup_token_issued_at = null,
      updated_at = now()
  where id = v_order.id
    and status in ('paid', 'preparing', 'ready')
  returning * into v_order;

  if not found then
    raise exception 'order status changed; reload and try again';
  end if;

  update public.surprise_bags
  set quantity_left = least(quantity_total, quantity_left + v_order.quantity),
      status = case
        when status = 'sold_out'
          and least(quantity_total, quantity_left + v_order.quantity) > 0
        then 'active'
        else status
      end,
      updated_at = now()
  where id = v_order.bag_id;

  if not found then
    -- Raising rolls the order update back as well, preserving atomicity.
    raise exception 'bag not found for order';
  end if;
  v_stock_restored := true;

  return to_jsonb(v_order) || jsonb_build_object(
    'order_id', v_order.id,
    'stock_restored', v_stock_restored,
    'already_cancelled', false
  );
end
$$;

comment on function public.cancel_merchant_order(uuid) is
  'Owner-only atomic cancellation for paid/preparing/ready orders; restores reserved stock exactly once.';

revoke all on function public.cancel_merchant_order(uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_merchant_order(uuid) to authenticated;

-- This RPC runs as the caller. RLS on orders and the explicit merchant-owner
-- predicate both constrain the result to the signed-in merchant.
create or replace function public.get_my_merchant_reviews()
returns table (
  review_id uuid,
  order_id uuid,
  order_reference text,
  customer_name text,
  rating integer,
  tags text[],
  comment text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public, pg_catalog
as $$
  select
    r.id as review_id,
    r.order_id,
    o.order_reference,
    case
      when o.consumer_anonymized then 'Pelanggan'
      else coalesce(nullif(btrim(o.consumer_name), ''), 'Pelanggan')
    end as customer_name,
    r.rating,
    r.tags,
    r.comment,
    r.created_at
  from public.reviews r
  join public.orders o
    on o.id = r.order_id
   and o.merchant_id = r.merchant_id
  join public.merchants m
    on m.id = r.merchant_id
  where m.user_id = auth.uid()
  order by r.created_at desc, r.id desc
$$;

comment on function public.get_my_merchant_reviews() is
  'Returns rating, tags, comment, date, customer display name, and order reference only for the signed-in merchant owner.';

revoke all on function public.get_my_merchant_reviews()
  from public, anon, authenticated;
grant execute on function public.get_my_merchant_reviews() to authenticated;

create index if not exists reviews_merchant_created_idx
  on public.reviews (merchant_id, created_at desc);

commit;
