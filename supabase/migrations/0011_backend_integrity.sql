-- SaveBite: transactional integrity and client/server parity follow-up.
-- Apply after 0010_cli_seed_support.sql.

begin;

-- ---------------------------------------------------------------------------
-- Public profile and catalogue input constraints
-- ---------------------------------------------------------------------------

update public.profiles
set name = case
      when length(btrim(coalesce(name, ''))) < 2 then 'Pengguna'
      else left(btrim(name), 80)
    end,
    phone = left(coalesce(phone, ''), 32),
    avatar_url = nullif(left(btrim(coalesce(avatar_url, '')), 2048), '');

alter table public.profiles alter column phone set not null;
alter table public.profiles drop constraint if exists profiles_name_length_check;
alter table public.profiles add constraint profiles_name_length_check
  check (length(btrim(name)) between 2 and 80);
alter table public.profiles drop constraint if exists profiles_phone_length_check;
alter table public.profiles add constraint profiles_phone_length_check
  check (length(phone) <= 32);
alter table public.profiles drop constraint if exists profiles_avatar_url_length_check;
alter table public.profiles add constraint profiles_avatar_url_length_check
  check (avatar_url is null or length(avatar_url) <= 2048);

-- OAuth providers may supply a one-character or blank display name. Keep the
-- auth trigger compatible with the stricter profile constraint for all future
-- sign-ups, not only rows that existed when this migration ran.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_name text := nullif(btrim(new.raw_user_meta_data ->> 'full_name'), '');
  v_avatar_url text;
begin
  if length(coalesce(v_name, '')) < 2 then
    v_name := nullif(btrim(new.raw_user_meta_data ->> 'name'), '');
  end if;
  if length(coalesce(v_name, '')) < 2 then
    v_name := 'Pengguna';
  end if;
  v_name := left(v_name, 80);
  v_avatar_url := nullif(
    left(btrim(coalesce(new.raw_user_meta_data ->> 'avatar_url', '')), 2048),
    ''
  );

  insert into public.profiles (id, name, email, avatar_url)
  values (new.id, v_name, new.email, v_avatar_url)
  on conflict (id) do nothing;
  return new;
end
$$;

revoke all on function public.handle_new_user()
  from public, anon, authenticated;

update public.merchants
set store_name = case
      when length(btrim(coalesce(store_name, ''))) < 2 then 'Toko'
      else left(btrim(store_name), 120)
    end,
    description = left(coalesce(description, ''), 2000),
    address = left(coalesce(address, ''), 500),
    distance = left(coalesce(distance, ''), 32),
    category = case
      when length(btrim(coalesce(category, ''))) < 2 then 'Lainnya'
      else left(btrim(category), 80)
    end,
    open_time = case
      when coalesce(open_time, '') ~ '^([01][0-9]|2[0-3])[.:][0-5][0-9]$'
        then open_time
      else '08.00'
    end,
    close_time = case
      when coalesce(close_time, '') ~ '^([01][0-9]|2[0-3])[.:][0-5][0-9]$'
        then close_time
      else '21.00'
    end,
    logo_url = nullif(left(btrim(coalesce(logo_url, '')), 2048), '');

-- A half coordinate pair, NaN/infinity, 0/0, or an out-of-range point must not
-- enter the public map catalogue. Legacy invalid pairs are made unknown rather
-- than silently moved to a real-world coordinate.
update public.merchants
set lat = null, lng = null
where (lat is null) <> (lng is null)
   or (
     lat is not null
     and (
       not (lat between -90 and 90)
       or not (lng between -180 and 180)
       or (lat = 0 and lng = 0)
     )
   );

alter table public.merchants alter column description set not null;
alter table public.merchants alter column address set not null;
alter table public.merchants alter column distance set not null;
alter table public.merchants alter column open_time set not null;
alter table public.merchants alter column close_time set not null;
alter table public.merchants drop constraint if exists merchants_text_fields_check;
alter table public.merchants add constraint merchants_text_fields_check check (
  length(btrim(store_name)) between 2 and 120
  and length(description) <= 2000
  and length(address) <= 500
  and length(distance) <= 32
  and length(btrim(category)) between 2 and 80
  and open_time ~ '^([01][0-9]|2[0-3])[.:][0-5][0-9]$'
  and close_time ~ '^([01][0-9]|2[0-3])[.:][0-5][0-9]$'
  and (logo_url is null or length(logo_url) <= 2048)
);
alter table public.merchants drop constraint if exists merchants_coordinates_check;
alter table public.merchants add constraint merchants_coordinates_check check (
  (lat is null and lng is null)
  or (
    lat is not null and lng is not null
    and lat between -90 and 90
    and lng between -180 and 180
    and (lat <> 0 or lng <> 0)
  )
);

update public.surprise_bags
set title = case
      when length(btrim(coalesce(title, ''))) < 2 then 'Surprise Bag'
      else left(btrim(title), 120)
    end,
    description = left(coalesce(description, ''), 2000),
    pickup_window = left(coalesce(pickup_window, ''), 100),
    image_url = nullif(left(btrim(coalesce(image_url, '')), 2048), '');

alter table public.surprise_bags drop constraint if exists bags_text_fields_check;
alter table public.surprise_bags
  drop constraint if exists bags_image_url_length_check;
-- Title/description/pickup-window bounds already live in bags_content_check.
alter table public.surprise_bags
  add constraint bags_image_url_length_check check (
    image_url is null or length(image_url) <= 2048
  );

-- ---------------------------------------------------------------------------
-- Atomic favourite toggle
-- ---------------------------------------------------------------------------

create or replace function public.toggle_favorite(p_merchant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_merchant_id is null then
    raise exception 'merchant not found';
  end if;

  perform private.assert_account_active(v_uid);
  perform pg_advisory_xact_lock(
    hashtextextended(v_uid::text || ':favorite:' || p_merchant_id::text, 0)
  );

  if exists (
    select 1
    from public.favorites f
    where f.consumer_id = v_uid and f.merchant_id = p_merchant_id
  ) then
    delete from public.favorites
    where consumer_id = v_uid and merchant_id = p_merchant_id;
    return false;
  end if;

  if not public.merchant_is_public(p_merchant_id) then
    raise exception 'merchant not found';
  end if;

  insert into public.favorites (consumer_id, merchant_id)
  values (v_uid, p_merchant_id);
  return true;
end
$$;

revoke all on function public.toggle_favorite(uuid)
  from public, anon, authenticated;
grant execute on function public.toggle_favorite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Pickup QR tokens exist only for ready orders
-- ---------------------------------------------------------------------------

-- Invalidate every legacy live token once. Older checkout code issued tokens
-- before readiness, so even a row that is ready now cannot prove when its
-- current capability was created. Consumers obtain a fresh short-lived token.
update public.orders
set pickup_code = null,
    pickup_token_hash = null,
    pickup_code_hint = null,
    pickup_token_issued_at = null,
    pickup_token_expires_at = null,
    pickup_token_used_at = case
      when status = 'redeemed' then pickup_token_used_at
      else null
    end
where pickup_code is not null
   or pickup_token_hash is not null
   or pickup_code_hint is not null
   or pickup_token_issued_at is not null
   or pickup_token_expires_at is not null
   or (status <> 'redeemed' and pickup_token_used_at is not null);

alter table public.orders
  drop constraint if exists orders_pickup_token_status_check;
alter table public.orders
  add constraint orders_pickup_token_status_check check (
    pickup_token_hash is null or status = 'ready'
  );

create or replace function private.enforce_pickup_token_readiness()
returns trigger
language plpgsql
set search_path = public, private, pg_catalog
as $$
begin
  -- Make every transition fail-safe. Cancellation, expiry, refund, and future
  -- lifecycle RPCs cannot accidentally retain a redeemable capability merely
  -- because they forgot to clear one token column.
  new.pickup_code := null;
  if new.status <> 'ready' then
    new.pickup_token_hash := null;
  end if;
  if new.pickup_token_hash is null then
    new.pickup_code_hint := null;
    new.pickup_token_issued_at := null;
    new.pickup_token_expires_at := null;
  end if;
  if new.status <> 'redeemed' then
    new.pickup_token_used_at := null;
  end if;
  return new;
end
$$;

drop trigger if exists enforce_pickup_token_readiness on public.orders;
create trigger enforce_pickup_token_readiness
before insert or update of status, pickup_code, pickup_token_hash,
  pickup_code_hint, pickup_token_issued_at, pickup_token_expires_at,
  pickup_token_used_at
on public.orders
for each row execute function private.enforce_pickup_token_readiness();

revoke all on function private.enforce_pickup_token_readiness()
  from public, anon, authenticated;

create or replace function public.purchase_bag(
  p_bag_id uuid,
  p_qty integer,
  p_method text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_uid uuid := auth.uid();
  v_bag public.surprise_bags;
  v_merchant public.merchants;
  v_order public.orders;
  v_existing public.orders;
  v_name text;
  v_fee integer := private.setting_int('service_fee');
  v_commission_bps integer := private.setting_int('merchant_commission_bps');
  v_subtotal integer;
  v_commission integer;
  v_expires_at timestamptz;
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  perform private.assert_account_active(v_uid);
  if p_qty is null or p_qty < 1 or p_qty > 100 then
    raise exception 'quantity must be between 1 and 100';
  end if;
  if p_method is null or length(btrim(p_method)) not between 1 and 64 then
    raise exception 'invalid payment method';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'idempotency key must contain 8-128 characters';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_uid::text || ':' || p_idempotency_key, 0)
  );

  select * into v_existing
  from public.orders
  where consumer_id = v_uid and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.bag_id <> p_bag_id
       or v_existing.quantity <> p_qty
       or v_existing.payment_method <> btrim(p_method) then
      raise exception 'idempotency key was already used with different parameters';
    end if;
    return (to_jsonb(v_existing) - 'pickup_token_hash' - 'pickup_code')
      || jsonb_build_object('order_id', v_existing.id, 'pickup_code', null);
  end if;

  select * into v_bag
  from public.surprise_bags
  where id = p_bag_id
  for update;
  if not found then raise exception 'bag not found'; end if;

  select * into v_merchant
  from public.merchants
  where id = v_bag.merchant_id;
  if not found or v_merchant.status <> 'active' or v_merchant.user_id is null then
    raise exception 'merchant is unavailable';
  end if;
  if v_bag.status <> 'active' then raise exception 'bag is not active'; end if;
  if v_bag.available_on > v_today then raise exception 'bag is not available yet'; end if;
  if v_bag.pickup_end_at is not null and v_bag.pickup_end_at <= now() then
    raise exception 'pickup window has ended';
  end if;
  if v_bag.quantity_left < p_qty then raise exception 'insufficient stock'; end if;

  v_subtotal := v_bag.sale_price * p_qty;
  v_commission := round(v_subtotal * v_commission_bps / 10000.0)::integer;
  v_expires_at := case
    when v_bag.pickup_end_at is not null then v_bag.pickup_end_at
    else now() + interval '72 hours'
  end;
  select name into v_name from public.profiles where id = v_uid;

  update public.surprise_bags
  set quantity_left = quantity_left - p_qty,
      status = case when quantity_left - p_qty = 0 then 'sold_out' else status end
  where id = p_bag_id;

  insert into public.orders (
    consumer_id, consumer_name, bag_id, merchant_id, quantity,
    subtotal, service_fee, total_amount, unit_price, original_price_snapshot,
    commission_amount, merchant_net_amount, payment_method, status,
    pickup_code,
    bag_title, bag_description, bag_image_url, pickup_window_snapshot,
    merchant_name_snapshot, merchant_category_snapshot,
    merchant_address_snapshot, merchant_logo_url_snapshot,
    merchant_rating_snapshot, merchant_review_count_snapshot,
    pickup_start_at, pickup_end_at, expires_at, paid_at, idempotency_key
  ) values (
    v_uid, coalesce(v_name, 'Pelanggan'), v_bag.id, v_bag.merchant_id, p_qty,
    v_subtotal, v_fee, v_subtotal + v_fee, v_bag.sale_price, v_bag.original_price,
    v_commission, v_subtotal - v_commission, btrim(p_method), 'paid',
    null,
    v_bag.title, v_bag.description, v_bag.image_url, v_bag.pickup_window,
    v_merchant.store_name, v_merchant.category, v_merchant.address,
    v_merchant.logo_url, v_merchant.rating, v_merchant.review_count,
    v_bag.pickup_start_at, v_bag.pickup_end_at, v_expires_at, now(),
    p_idempotency_key
  ) returning * into v_order;

  return (to_jsonb(v_order) - 'pickup_token_hash' - 'pickup_code')
    || jsonb_build_object('order_id', v_order.id, 'pickup_code', null);
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
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
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
  if v_order.expires_at <= now() then raise exception 'order has expired'; end if;

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
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_code is null or length(p_code) < 32 then raise exception 'invalid pickup token'; end if;

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
  if v_order.status <> 'ready' then raise exception 'order is not redeemable'; end if;
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

revoke all on function public.purchase_bag(uuid,integer,text,text)
  from public, anon, authenticated;
grant execute on function public.purchase_bag(uuid,integer,text,text)
  to authenticated;
revoke all on function public.issue_pickup_token(uuid)
  from public, anon, authenticated;
grant execute on function public.issue_pickup_token(uuid) to authenticated;
revoke all on function public.redeem_order(text)
  from public, anon, authenticated;
grant execute on function public.redeem_order(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Cancellation/expiry restore reservations without republishing elapsed bags
-- ---------------------------------------------------------------------------

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
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_order_id is null then raise exception 'order not found'; end if;

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
      pickup_token_expires_at = null,
      pickup_token_used_at = null,
      updated_at = now()
  where id = v_order.id
    and status in ('paid', 'preparing', 'ready')
  returning * into v_order;
  if not found then
    raise exception 'order status changed; reload and try again';
  end if;

  update public.surprise_bags b
  set quantity_left = least(
        b.quantity_total,
        b.quantity_left + v_order.quantity
      ),
      status = case
        when b.status = 'inactive' then 'inactive'
        when b.available_on < (now() at time zone 'Asia/Jakarta')::date
          then 'inactive'
        when b.pickup_end_at is not null and b.pickup_end_at <= now()
          then 'inactive'
        when least(b.quantity_total, b.quantity_left + v_order.quantity) = 0
          then 'sold_out'
        else 'active'
      end,
      updated_at = now()
  where b.id = v_order.bag_id;
  if not found then
    raise exception 'bag not found for order';
  end if;

  return to_jsonb(v_order) || jsonb_build_object(
    'order_id', v_order.id,
    'stock_restored', true,
    'already_cancelled', false
  );
end
$$;

revoke all on function public.cancel_merchant_order(uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_merchant_order(uuid) to authenticated;

create or replace function public.expire_orders(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_count integer;
begin
  if session_user::text not in ('postgres', 'supabase_admin', 'service_role')
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'limit must be between 1 and 5000';
  end if;

  with candidates as materialized (
    select id
    from public.orders
    where status in ('paid', 'preparing', 'ready')
      and expires_at <= now()
    order by expires_at
    for update skip locked
    limit p_limit
  ), expired as (
    update public.orders o
    set status = 'expired',
        expired_at = coalesce(o.expired_at, now()),
        pickup_token_hash = null,
        pickup_code_hint = null,
        pickup_token_issued_at = null,
        pickup_token_expires_at = null
    from candidates c
    where o.id = c.id
      and o.status in ('paid', 'preparing', 'ready')
    returning o.bag_id, o.quantity
  ), restored as (
    select bag_id, sum(quantity)::integer as quantity
    from expired
    group by bag_id
  ), updated_bags as (
    update public.surprise_bags b
    set quantity_left = least(b.quantity_total, b.quantity_left + r.quantity),
        status = case
          when b.status = 'inactive' then 'inactive'
          when b.available_on < (now() at time zone 'Asia/Jakarta')::date
            then 'inactive'
          when b.pickup_end_at is not null and b.pickup_end_at <= now()
            then 'inactive'
          when least(b.quantity_total, b.quantity_left + r.quantity) = 0
            then 'sold_out'
          else 'active'
        end
    from restored r
    where b.id = r.bag_id
    returning b.id
  )
  select (select count(*) from expired)::integer
  into v_count
  from (select count(*) from updated_bags) applied;

  return coalesce(v_count, 0);
end
$$;

revoke all on function public.expire_orders(integer)
  from public, anon, authenticated;
grant execute on function public.expire_orders(integer) to service_role;

comment on function public.toggle_favorite(uuid) is
  'Atomically toggles the signed-in consumer favorite under an advisory lock.';
comment on function public.issue_pickup_token(uuid) is
  'Issues a rotating pickup token only after the consumer order is ready.';
comment on function public.redeem_order(text) is
  'Redeems one unexpired rotating token for a ready order owned by the merchant.';
comment on function public.cancel_merchant_order(uuid) is
  'Cancels an eligible merchant order once, restores its reservation, and never republishes an elapsed bag.';
comment on function public.expire_orders(integer) is
  'Expires due orders, restores their inventory reservation, and keeps elapsed bags inactive.';

commit;
