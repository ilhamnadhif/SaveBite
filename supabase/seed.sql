-- SaveBite — data contoh: 8 toko + 9 Surprise Bag (foto pakai aset bundel app).
-- Jalankan SETELAH 0001_init.sql. Toko seed tidak punya user_id (milik "platform").

insert into public.merchants
  (id, user_id, store_name, category, distance, lat, lng, open_time, close_time, logo_url, status, rating, review_count, bags_saved, address)
values
  ('11111111-1111-1111-1111-111111111101', null, 'Roti Nyaman Bakery', 'Bakery', '0,4 km', -6.3720, 106.8320, '08.00', '21.00', 'assets/images/food2.jpg', 'active', 4.8, 212, 184, 'Jl. Margonda Raya No. 88, Depok'),
  ('11111111-1111-1111-1111-111111111102', null, 'Kopi Senja', 'Kafe', '0,9 km', -6.3760, 106.8290, '10.00', '22.00', 'assets/images/food8.jpg', 'active', 4.6, 98, 76, 'Jl. Kemang Raya No. 12, Depok'),
  ('11111111-1111-1111-1111-111111111103', null, 'Donat Manis Margonda', 'Bakery', '1,2 km', -6.3680, 106.8350, '08.00', '20.00', 'assets/images/food7.jpg', 'active', 4.7, 64, 41, 'Jl. Akses UI No. 5, Depok'),
  ('11111111-1111-1111-1111-111111111104', null, 'Toko Sehat Depok', 'Sehat', '1,8 km', -6.3810, 106.8270, '09.00', '21.00', 'assets/images/food3.jpg', 'active', 4.5, 33, 22, 'Jl. Juanda No. 21, Depok'),
  ('11111111-1111-1111-1111-111111111105', null, 'Warung Nasi Ibu', 'Resto', '1,1 km', -6.3700, 106.8360, '07.00', '21.00', 'assets/images/food6.jpg', 'active', 4.4, 120, 95, 'Jl. Nusantara No. 3, Depok'),
  ('11111111-1111-1111-1111-111111111106', null, 'Sayur Segar Mart', 'Supermarket', '2,0 km', -6.3850, 106.8330, '08.00', '22.00', 'assets/images/food10.jpg', 'active', 4.3, 45, 58, 'Jl. Tole Iskandar No. 17, Depok'),
  ('11111111-1111-1111-1111-111111111107', null, 'Pizza Sudut', 'Resto', '1,5 km', -6.3740, 106.8400, '11.00', '23.00', 'assets/images/food9.jpg', 'active', 4.6, 88, 67, 'Jl. Siliwangi No. 9, Depok'),
  ('11111111-1111-1111-1111-111111111108', null, 'Salad Hijau', 'Sehat', '0,7 km', -6.3715, 106.8300, '09.00', '20.00', 'assets/images/food4.jpg', 'active', 4.7, 52, 39, 'Jl. Margonda Raya No. 210, Depok')
on conflict (id) do nothing;

insert into public.surprise_bags
  (id, merchant_id, title, description, original_price, sale_price, quantity_total, quantity_left, pickup_window, image_url, contents, status)
values
  ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111101', 'Surprise Bag Roti & Pastry', 'Campuran roti manis, pastry, dan donat hari ini yang masih fresh.', 45000, 15000, 8, 3, '20.00–21.00', 'assets/images/food1.jpg', array['Roti manis','Croissant','Donat','Roti tawar'], 'active'),
  ('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111102', 'Surprise Bag Pastry & Kopi', 'Pastry pilihan dan kopi hari ini yang belum sempat terjual.', 50000, 20000, 10, 6, '19.30–20.30', 'assets/images/food8.jpg', array['Croissant','Muffin','Kopi susu','Cookies'], 'active'),
  ('22222222-2222-2222-2222-222222222203', '11111111-1111-1111-1111-111111111103', 'Surprise Bag Donat', 'Aneka donat manis hari ini yang masih lembut.', 40000, 16000, 6, 0, '18.00–19.00', 'assets/images/food7.jpg', array['Donat cokelat','Donat gula','Donat keju'], 'sold_out'),
  ('22222222-2222-2222-2222-222222222204', '11111111-1111-1111-1111-111111111104', 'Surprise Bag Buah Potong', 'Aneka buah potong segar siap santap yang harus habis hari ini.', 38000, 18000, 8, 4, '17.00–18.00', 'assets/images/food3.jpg', array['Semangka','Melon','Pepaya','Nanas'], 'active'),
  ('22222222-2222-2222-2222-222222222205', '11111111-1111-1111-1111-111111111105', 'Surprise Bag Nasi & Lauk', 'Nasi hangat plus aneka lauk rumahan sisa porsi hari ini.', 35000, 14000, 12, 5, '20.30–21.30', 'assets/images/food6.jpg', array['Nasi','Ayam','Tempe','Sayur'], 'active'),
  ('22222222-2222-2222-2222-222222222206', '11111111-1111-1111-1111-111111111106', 'Surprise Bag Sayur & Buah', 'Paket sayur dan buah mendekati best-before, masih segar & layak.', 60000, 25000, 15, 8, '18.00–20.00', 'assets/images/food10.jpg', array['Sayur hijau','Wortel','Tomat','Buah'], 'active'),
  ('22222222-2222-2222-2222-222222222207', '11111111-1111-1111-1111-111111111107', 'Surprise Bag Pizza Slice', 'Aneka potongan pizza akhir hari yang masih nikmat dihangatkan.', 70000, 28000, 6, 2, '21.00–22.00', 'assets/images/food9.jpg', array['Pizza keju','Pizza daging','Garlic bread'], 'active'),
  ('22222222-2222-2222-2222-222222222208', '11111111-1111-1111-1111-111111111108', 'Surprise Bag Salad Sehat', 'Salad segar dan healthy bowl yang belum terjual sore ini.', 45000, 19000, 10, 7, '16.30–18.00', 'assets/images/food4.jpg', array['Garden salad','Healthy bowl','Smoothie'], 'active'),
  ('22222222-2222-2222-2222-222222222209', '11111111-1111-1111-1111-111111111102', 'Surprise Bag Pastry Sore', 'Sisa pastry sore: croissant, danish, dan roti isi.', 30000, 12000, 8, 0, '17.30–18.30', 'assets/images/food5.jpg', array['Croissant','Danish','Roti isi'], 'sold_out')
on conflict (id) do nothing;
