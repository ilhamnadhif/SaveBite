-- SaveBite — skema awal (tabel, RLS, trigger, RPC, view saldo, storage).
-- Jalankan di Supabase SQL Editor. Aman dijalankan ulang (idempotent sebisanya).

-- ───────────── Tabel ─────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'Pengguna',
  email text,
  avatar_url text,
  phone text default '',
  last_mode text not null default 'consumer',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.merchants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  store_name text not null,
  description text default '',
  address text default '',
  distance text default '',
  lat double precision,
  lng double precision,
  category text not null default 'Bakery',
  open_time text default '08.00',
  close_time text default '21.00',
  logo_url text,
  status text not null default 'active',
  rating numeric(2,1) default 0,
  review_count int default 0,
  bags_saved int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (user_id)
);

create table if not exists public.surprise_bags (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  title text not null,
  description text default '',
  original_price int not null,
  sale_price int not null,
  quantity_total int not null,
  quantity_left int not null,
  pickup_window text default '',
  image_url text,
  contents text[] default '{}',
  status text not null default 'active', -- active | sold_out | inactive
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  consumer_id uuid not null references auth.users(id) on delete cascade,
  consumer_name text default 'Pelanggan',
  bag_id uuid not null references public.surprise_bags(id),
  merchant_id uuid not null references public.merchants(id),
  quantity int not null default 1,
  total_amount int not null,
  pickup_code text not null unique,
  payment_method text default 'GoPay',
  status text not null default 'paid', -- pending | paid | redeemed | cancelled | expired
  created_at timestamptz default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  consumer_id uuid not null references auth.users(id) on delete cascade,
  merchant_id uuid not null references public.merchants(id),
  rating int not null check (rating between 1 and 5),
  tags text[] default '{}',
  comment text default '',
  created_at timestamptz default now()
);

create table if not exists public.favorites (
  consumer_id uuid not null references auth.users(id) on delete cascade,
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (consumer_id, merchant_id)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  title text not null,
  subtitle text default '',
  amount int not null,
  kind text not null, -- income | withdrawal
  created_at timestamptz default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text default '',
  type text default 'payment',
  group_label text default 'Hari ini',
  read boolean default false,
  created_at timestamptz default now()
);

-- ───────────── View saldo merchant ─────────────
create or replace view public.merchant_balance
with (security_invoker = true) as
select m.id as merchant_id,
       coalesce(sum(case when t.kind = 'income' then t.amount
                         when t.kind = 'withdrawal' then -t.amount
                         else 0 end), 0)::int as available
from public.merchants m
left join public.transactions t on t.merchant_id = m.id
group by m.id;

-- ───────────── Trigger: updated_at ─────────────
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists t_profiles_updated on public.profiles;
create trigger t_profiles_updated before update on public.profiles
  for each row execute function public.touch_updated_at();
drop trigger if exists t_merchants_updated on public.merchants;
create trigger t_merchants_updated before update on public.merchants
  for each row execute function public.touch_updated_at();
drop trigger if exists t_bags_updated on public.surprise_bags;
create trigger t_bags_updated before update on public.surprise_bags
  for each row execute function public.touch_updated_at();

-- ───────────── Trigger: buat profil saat user baru ─────────────
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Pengguna'),
    new.email,
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────── Trigger: rekap rating merchant ─────────────
create or replace function public.recompute_merchant_rating()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.merchants set
    rating = coalesce((select round(avg(rating)::numeric, 1) from public.reviews where merchant_id = new.merchant_id), 0),
    review_count = (select count(*) from public.reviews where merchant_id = new.merchant_id)
  where id = new.merchant_id;
  return new;
end; $$;

drop trigger if exists on_review_insert on public.reviews;
create trigger on_review_insert
  after insert on public.reviews
  for each row execute function public.recompute_merchant_rating();

-- ───────────── RPC: beli bag (ACID) ─────────────
create or replace function public.purchase_bag(p_bag_id uuid, p_qty int, p_method text)
returns public.orders language plpgsql security definer set search_path = public as $$
declare
  v_bag public.surprise_bags;
  v_order public.orders;
  v_code text;
  v_uid uuid := auth.uid();
  v_name text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_bag from public.surprise_bags where id = p_bag_id for update;
  if v_bag.id is null then raise exception 'bag not found'; end if;
  if v_bag.quantity_left < p_qty then raise exception 'insufficient stock'; end if;

  v_code := 'SB-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  select name into v_name from public.profiles where id = v_uid;

  update public.surprise_bags
    set quantity_left = quantity_left - p_qty,
        status = case when quantity_left - p_qty <= 0 then 'sold_out' else status end
  where id = p_bag_id;

  insert into public.orders
    (consumer_id, consumer_name, bag_id, merchant_id, quantity, total_amount, pickup_code, payment_method, status)
  values
    (v_uid, coalesce(v_name, 'Pelanggan'), p_bag_id, v_bag.merchant_id, p_qty, v_bag.sale_price * p_qty, v_code, p_method, 'paid')
  returning * into v_order;

  return v_order;
end; $$;

-- ───────────── RPC: redeem order ─────────────
create or replace function public.redeem_order(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_commission int;
begin
  select * into v_order from public.orders where pickup_code = p_code for update;
  if v_order.id is null then raise exception 'order not found'; end if;
  select user_id into v_owner from public.merchants where id = v_order.merchant_id;
  if v_owner is distinct from v_uid then raise exception 'not your order'; end if;
  if v_order.status = 'redeemed' then raise exception 'already redeemed'; end if;

  update public.orders set status = 'redeemed' where id = v_order.id;
  v_commission := round(v_order.total_amount * 0.1);
  insert into public.transactions (merchant_id, title, subtitle, amount, kind)
  values (v_order.merchant_id, 'Order ' || v_order.pickup_code,
          'komisi ' || v_commission, v_order.total_amount - v_commission, 'income');
  update public.merchants set bags_saved = bags_saved + v_order.quantity
  where id = v_order.merchant_id;

  return jsonb_build_object(
    'pickup_code', v_order.pickup_code,
    'quantity', v_order.quantity,
    'customer_name', v_order.consumer_name,
    'created_at', v_order.created_at
  );
end; $$;

-- ───────────── RLS ─────────────
alter table public.profiles enable row level security;
alter table public.merchants enable row level security;
alter table public.surprise_bags enable row level security;
alter table public.orders enable row level security;
alter table public.reviews enable row level security;
alter table public.favorites enable row level security;
alter table public.transactions enable row level security;
alter table public.notifications enable row level security;

-- profiles: hanya pemilik
drop policy if exists profiles_self on public.profiles;
create policy profiles_self on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

-- merchants: baca publik; tulis pemilik
drop policy if exists merchants_read on public.merchants;
create policy merchants_read on public.merchants for select using (true);
drop policy if exists merchants_write on public.merchants;
create policy merchants_write on public.merchants
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- surprise_bags: baca bag aktif (atau milik sendiri); tulis pemilik
drop policy if exists bags_read on public.surprise_bags;
create policy bags_read on public.surprise_bags for select using (
  status = 'active'
  or merchant_id in (select id from public.merchants where user_id = auth.uid())
);
drop policy if exists bags_write on public.surprise_bags;
create policy bags_write on public.surprise_bags for all using (
  merchant_id in (select id from public.merchants where user_id = auth.uid())
) with check (
  merchant_id in (select id from public.merchants where user_id = auth.uid())
);

-- orders: konsumen miliknya + merchant pemilik bag-nya (insert/update via RPC security definer)
drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select using (
  consumer_id = auth.uid()
  or merchant_id in (select id from public.merchants where user_id = auth.uid())
);

-- reviews: baca publik; tulis konsumen sendiri
drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews for select using (true);
drop policy if exists reviews_insert on public.reviews;
create policy reviews_insert on public.reviews
  for insert with check (auth.uid() = consumer_id);

-- favorites: pemilik
drop policy if exists favorites_self on public.favorites;
create policy favorites_self on public.favorites
  for all using (auth.uid() = consumer_id) with check (auth.uid() = consumer_id);

-- transactions: baca + tulis (withdrawal) oleh pemilik merchant
drop policy if exists tx_owner on public.transactions;
create policy tx_owner on public.transactions for all using (
  merchant_id in (select id from public.merchants where user_id = auth.uid())
) with check (
  merchant_id in (select id from public.merchants where user_id = auth.uid())
);

-- notifications: pemilik
drop policy if exists notif_self on public.notifications;
create policy notif_self on public.notifications
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ───────────── Storage ─────────────
insert into storage.buckets (id, name, public) values
  ('bag-images', 'bag-images', true),
  ('store-logos', 'store-logos', true),
  ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Baca publik untuk ketiga bucket
drop policy if exists storage_public_read on storage.objects;
create policy storage_public_read on storage.objects for select using (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
);

-- Tulis: user terautentikasi ke folder miliknya (folder pertama = uid)
drop policy if exists storage_auth_write on storage.objects;
create policy storage_auth_write on storage.objects for insert to authenticated with check (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists storage_auth_update on storage.objects;
create policy storage_auth_update on storage.objects for update to authenticated using (
  bucket_id in ('bag-images', 'store-logos', 'avatars')
  and (storage.foldername(name))[1] = auth.uid()::text
);
