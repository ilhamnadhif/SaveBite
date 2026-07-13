-- SaveBite staging fixture: eight visible merchants and nine Surprise Bags.
--
-- Run only after every migration. The fixed Auth rows below are non-login
-- ownership principals: they have no auth.identities row and their generated
-- password is never exposed. Real testers still sign in through OAuth.
-- Re-running this file reconciles the fixed merchant/bag rows, so never use it
-- against production data. Every statement is self-contained because the
-- Supabase seed runner may execute adjacent statements in separate batches.

-- Remote resets can preserve Auth users while recreating the public schema.
-- Fixed IDs plus ON CONFLICT make the ownership principals safe to reconcile.
with fixture_owners (auth_user_id, email, display_name) as (
  values
    ('90000000-0000-0000-0000-000000000101'::uuid, 'fixture.roti@staging.savebite.invalid', 'Pemilik Roti Nyaman'),
    ('90000000-0000-0000-0000-000000000102'::uuid, 'fixture.kopi@staging.savebite.invalid', 'Pemilik Kopi Senja'),
    ('90000000-0000-0000-0000-000000000103'::uuid, 'fixture.donat@staging.savebite.invalid', 'Pemilik Donat Manis'),
    ('90000000-0000-0000-0000-000000000104'::uuid, 'fixture.sehat@staging.savebite.invalid', 'Pemilik Toko Sehat'),
    ('90000000-0000-0000-0000-000000000105'::uuid, 'fixture.warung@staging.savebite.invalid', 'Pemilik Warung Nasi'),
    ('90000000-0000-0000-0000-000000000106'::uuid, 'fixture.sayur@staging.savebite.invalid', 'Pemilik Sayur Segar'),
    ('90000000-0000-0000-0000-000000000107'::uuid, 'fixture.pizza@staging.savebite.invalid', 'Pemilik Pizza Sudut'),
    ('90000000-0000-0000-0000-000000000108'::uuid, 'fixture.salad@staging.savebite.invalid', 'Pemilik Salad Hijau')
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  f.auth_user_id,
  'authenticated',
  'authenticated',
  f.email,
  extensions.crypt(
    encode(extensions.gen_random_bytes(32), 'hex'),
    extensions.gen_salt('bf')
  ),
  now(),
  jsonb_build_object(
    'provider', 'email',
    'providers', jsonb_build_array(),
    'savebite_fixture', true
  ),
  jsonb_build_object(
    'full_name', f.display_name,
    'savebite_fixture', true
  ),
  now(),
  now()
from fixture_owners f
on conflict (id) do nothing;

-- Backfill profiles for every retained Auth account. This also covers OAuth
-- users created before a linked reset, whose public.profiles rows were dropped.
insert into public.profiles (id, name, email, avatar_url, last_mode)
select
  u.id,
  coalesce(
    nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
    'Pengguna'
  ),
  u.email,
  nullif(btrim(u.raw_user_meta_data ->> 'avatar_url'), ''),
  'consumer'
from auth.users u
where u.deleted_at is null
on conflict (id) do update
set email = excluded.email;

-- The insert trigger creates these profiles on a fresh database; explicitly
-- reconcile their role/name for the retained-Auth and seed-rerun cases.
with fixture_owners (auth_user_id, email, display_name) as (
  values
    ('90000000-0000-0000-0000-000000000101'::uuid, 'fixture.roti@staging.savebite.invalid', 'Pemilik Roti Nyaman'),
    ('90000000-0000-0000-0000-000000000102'::uuid, 'fixture.kopi@staging.savebite.invalid', 'Pemilik Kopi Senja'),
    ('90000000-0000-0000-0000-000000000103'::uuid, 'fixture.donat@staging.savebite.invalid', 'Pemilik Donat Manis'),
    ('90000000-0000-0000-0000-000000000104'::uuid, 'fixture.sehat@staging.savebite.invalid', 'Pemilik Toko Sehat'),
    ('90000000-0000-0000-0000-000000000105'::uuid, 'fixture.warung@staging.savebite.invalid', 'Pemilik Warung Nasi'),
    ('90000000-0000-0000-0000-000000000106'::uuid, 'fixture.sayur@staging.savebite.invalid', 'Pemilik Sayur Segar'),
    ('90000000-0000-0000-0000-000000000107'::uuid, 'fixture.pizza@staging.savebite.invalid', 'Pemilik Pizza Sudut'),
    ('90000000-0000-0000-0000-000000000108'::uuid, 'fixture.salad@staging.savebite.invalid', 'Pemilik Salad Hijau')
)
update public.profiles p
set name = f.display_name,
    email = f.email,
    last_mode = 'merchant',
    deleted_at = null
from fixture_owners f
where p.id = f.auth_user_id;

insert into public.merchants
  (id, user_id, store_name, category, distance, lat, lng, open_time,
   close_time, logo_url, status, rating, review_count, bags_saved, address,
   deleted_at)
values
  ('11111111-1111-1111-1111-111111111101', '90000000-0000-0000-0000-000000000101', 'Roti Nyaman Bakery', 'Bakery', '0,4 km', -6.3720, 106.8320, '08.00', '21.00', 'assets/images/food2.jpg', 'active', 0, 0, 0, 'Jl. Margonda Raya No. 88, Depok', null),
  ('11111111-1111-1111-1111-111111111102', '90000000-0000-0000-0000-000000000102', 'Kopi Senja', 'Kafe', '0,9 km', -6.3760, 106.8290, '10.00', '22.00', 'assets/images/food8.jpg', 'active', 0, 0, 0, 'Jl. Kemang Raya No. 12, Depok', null),
  ('11111111-1111-1111-1111-111111111103', '90000000-0000-0000-0000-000000000103', 'Donat Manis Margonda', 'Bakery', '1,2 km', -6.3680, 106.8350, '08.00', '20.00', 'assets/images/food7.jpg', 'active', 0, 0, 0, 'Jl. Akses UI No. 5, Depok', null),
  ('11111111-1111-1111-1111-111111111104', '90000000-0000-0000-0000-000000000104', 'Toko Sehat Depok', 'Sehat', '1,8 km', -6.3810, 106.8270, '09.00', '21.00', 'assets/images/food3.jpg', 'active', 0, 0, 0, 'Jl. Juanda No. 21, Depok', null),
  ('11111111-1111-1111-1111-111111111105', '90000000-0000-0000-0000-000000000105', 'Warung Nasi Ibu', 'Resto', '1,1 km', -6.3700, 106.8360, '07.00', '21.00', 'assets/images/food6.jpg', 'active', 0, 0, 0, 'Jl. Nusantara No. 3, Depok', null),
  ('11111111-1111-1111-1111-111111111106', '90000000-0000-0000-0000-000000000106', 'Sayur Segar Mart', 'Supermarket', '2,0 km', -6.3850, 106.8330, '08.00', '22.00', 'assets/images/food10.jpg', 'active', 0, 0, 0, 'Jl. Tole Iskandar No. 17, Depok', null),
  ('11111111-1111-1111-1111-111111111107', '90000000-0000-0000-0000-000000000107', 'Pizza Sudut', 'Resto', '1,5 km', -6.3740, 106.8400, '11.00', '23.00', 'assets/images/food9.jpg', 'active', 0, 0, 0, 'Jl. Siliwangi No. 9, Depok', null),
  ('11111111-1111-1111-1111-111111111108', '90000000-0000-0000-0000-000000000108', 'Salad Hijau', 'Sehat', '0,7 km', -6.3715, 106.8300, '09.00', '20.00', 'assets/images/food4.jpg', 'active', 0, 0, 0, 'Jl. Margonda Raya No. 210, Depok', null)
on conflict (id) do update
set user_id = excluded.user_id,
    store_name = excluded.store_name,
    category = excluded.category,
    distance = excluded.distance,
    lat = excluded.lat,
    lng = excluded.lng,
    open_time = excluded.open_time,
    close_time = excluded.close_time,
    logo_url = excluded.logo_url,
    status = excluded.status,
    rating = excluded.rating,
    review_count = excluded.review_count,
    bags_saved = excluded.bags_saved,
    address = excluded.address,
    deleted_at = null;

insert into public.surprise_bags
  (id, merchant_id, title, description, original_price, sale_price,
   quantity_total, quantity_left, pickup_window, image_url, contents, status,
   available_on, pickup_start_at, pickup_end_at)
values
  ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111101', 'Surprise Bag Roti & Pastry', 'Campuran roti manis, pastry, dan donat hari ini yang masih fresh.', 45000, 15000, 8, 3, '20.00–21.00', 'assets/images/food1.jpg', array['Roti manis','Croissant','Donat','Roti tawar'], 'active', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111102', 'Surprise Bag Pastry & Kopi', 'Pastry pilihan dan kopi hari ini yang belum sempat terjual.', 50000, 20000, 10, 6, '19.30–20.30', 'assets/images/food8.jpg', array['Croissant','Muffin','Kopi susu','Cookies'], 'active', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222203', '11111111-1111-1111-1111-111111111103', 'Surprise Bag Donat', 'Aneka donat manis hari ini yang masih lembut.', 40000, 16000, 6, 0, '18.00–19.00', 'assets/images/food7.jpg', array['Donat cokelat','Donat gula','Donat keju'], 'sold_out', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222204', '11111111-1111-1111-1111-111111111104', 'Surprise Bag Buah Potong', 'Aneka buah potong segar siap santap yang harus habis hari ini.', 38000, 18000, 8, 4, '17.00–18.00', 'assets/images/food3.jpg', array['Semangka','Melon','Pepaya','Nanas'], 'active', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222205', '11111111-1111-1111-1111-111111111105', 'Surprise Bag Nasi & Lauk', 'Nasi hangat plus aneka lauk rumahan sisa porsi hari ini.', 35000, 14000, 12, 5, '20.30–21.30', 'assets/images/food6.jpg', array['Nasi','Ayam','Tempe','Sayur'], 'active', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222206', '11111111-1111-1111-1111-111111111106', 'Surprise Bag Sayur & Buah', 'Paket sayur dan buah mendekati best-before, masih segar & layak.', 60000, 25000, 15, 8, '18.00–20.00', 'assets/images/food10.jpg', array['Sayur hijau','Wortel','Tomat','Buah'], 'active', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222207', '11111111-1111-1111-1111-111111111107', 'Surprise Bag Pizza Slice', 'Aneka potongan pizza akhir hari yang masih nikmat dihangatkan.', 70000, 28000, 6, 2, '21.00–22.00', 'assets/images/food9.jpg', array['Pizza keju','Pizza daging','Garlic bread'], 'active', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222208', '11111111-1111-1111-1111-111111111108', 'Surprise Bag Salad Sehat', 'Salad segar dan healthy bowl yang belum terjual sore ini.', 45000, 19000, 10, 7, '16.30–18.00', 'assets/images/food4.jpg', array['Garden salad','Healthy bowl','Smoothie'], 'active', (now() at time zone 'Asia/Jakarta')::date, null, null),
  ('22222222-2222-2222-2222-222222222209', '11111111-1111-1111-1111-111111111102', 'Surprise Bag Pastry Sore', 'Sisa pastry sore: croissant, danish, dan roti isi.', 30000, 12000, 8, 0, '17.30–18.30', 'assets/images/food5.jpg', array['Croissant','Danish','Roti isi'], 'sold_out', (now() at time zone 'Asia/Jakarta')::date, null, null)
on conflict (id) do update
set merchant_id = excluded.merchant_id,
    title = excluded.title,
    description = excluded.description,
    original_price = excluded.original_price,
    sale_price = excluded.sale_price,
    quantity_total = excluded.quantity_total,
    quantity_left = excluded.quantity_left,
    pickup_window = excluded.pickup_window,
    image_url = excluded.image_url,
    contents = excluded.contents,
    status = excluded.status,
    available_on = excluded.available_on,
    pickup_start_at = null,
    pickup_end_at = null;
