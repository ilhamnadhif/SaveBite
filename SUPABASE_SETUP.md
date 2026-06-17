# SaveBite × Supabase — Panduan Setup

Backend SaveBite memakai **Supabase** (Auth Google, Postgres, Storage). Midtrans
menyusul. App tetap **bisa jalan offline** memakai data contoh bila kredensial
Supabase tidak diisi (mode FakeBackend) — berguna untuk demo cepat.

## 1. Buat project Supabase
1. Masuk ke https://supabase.com → **New project**. Catat **Project URL** dan
   **anon/public key** (Settings → API). anon key aman dipakai di klien.

## 2. Jalankan SQL
Di **SQL Editor** Supabase, jalankan berurutan:
1. `supabase/migrations/0001_init.sql` — tabel, RLS, trigger, RPC (`purchase_bag`,
   `redeem_order`), view `merchant_balance`, dan bucket Storage + policy.
2. `supabase/seed.sql` — 8 toko + 9 Surprise Bag contoh (foto pakai aset bundel app).

> Storage bucket (`bag-images`, `store-logos`, `avatars`) dibuat otomatis oleh
> script #1 beserta policy (baca publik, tulis ke folder milik user).

## 3. Aktifkan Google Auth
1. **Authentication → Providers → Google** → enable.
2. Buat OAuth Client di Google Cloud Console, tempel **Client ID + Secret** ke
   provider Google di Supabase (ikuti petunjuk di halaman provider).
3. **Authentication → URL Configuration → Redirect URLs**: tambahkan
   `com.savebite://login-callback`.
   - Deep link sudah dikonfigurasi di app: `AndroidManifest.xml` (intent-filter
     scheme `com.savebite` host `login-callback`) dan `ios/Runner/Info.plist`
     (`CFBundleURLSchemes` = `com.savebite`).

## 4. Kredensial via `.env`
Buat file `.env` di root project (lihat `.env.example`):
```
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=sb_publishable_xxx
```
`.env` di-load otomatis saat app start (dideklarasikan sebagai asset di pubspec,
dan masuk `.gitignore`). Lalu cukup:
```bash
flutter run
```
Alternatif (override / CI): `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
Tanpa `.env` maupun dart-define, app jalan **offline** (data contoh, login langsung tanpa Google).

## 5. Uji alur
- Login Google → profil dibuat otomatis (trigger `handle_new_user`).
- Browse konsumen menampilkan 9 bag seed → beli (RPC `purchase_bag`, stok turun
  atomik) → pesanan muncul di **Pesanan**.
- Mode merchant (keluar → pilih "jual" → login) pertama kali → **Setup Toko**
  (membuat baris `merchants` milikmu) → Dashboard.
- Buat/Edit bag dengan **upload foto** (ke bucket `bag-images`).
- Redeem QR (RPC `redeem_order`) → order pindah ke "Selesai", saldo + transaksi
  bertambah (view `merchant_balance`).

## Catatan
- **RLS aktif** di semua tabel: konsumen hanya melihat datanya sendiri + bag aktif
  publik; merchant hanya mengelola toko/bag/order miliknya. Penulisan order
  (beli & redeem) lewat RPC `security definer` agar atomik & aman.
- **Toko seed** tidak punya `user_id` (milik "platform") sehingga muncul di browse
  semua konsumen; toko milikmu dibuat saat Setup Toko.
- **Foto seed** memakai path aset bundel (`assets/images/foodN.jpg`); foto baru
  yang diupload memakai URL Storage. `FoodImage` menangani keduanya otomatis.
- Ganti **password/secret** jangan di-commit; hanya URL + anon key (publik) yang
  dipakai klien via `--dart-define`.
