# SaveBite

SaveBite adalah aplikasi Flutter untuk menjual kembali makanan surplus dalam
bentuk _Surprise Bag_. Satu aplikasi melayani dua peran: konsumen menemukan dan
memesan bag di sekitar mereka, sedangkan merchant mengelola toko, stok, pickup,
dan saldo.

Backend produksi menggunakan Supabase (Auth, Postgres, Realtime, dan Storage).
Tanpa konfigurasi Supabase, aplikasi otomatis memakai `FakeBackend` agar alur UI
dapat didemokan dan diuji secara lokal.

> **Status pembayaran:** integrasi payment gateway sengaja belum diaktifkan.
> GoPay, OVO, dan Virtual Account BCA di checkout saat ini hanya pilihan
> simulasi; tidak ada saldo atau rekening nyata yang didebit. Jangan gunakan
> build ini untuk transaksi uang riil sebelum alur webhook gateway diterapkan.

## Fitur yang tersedia

### Konsumen

- onboarding dan pilihan peran yang tersimpan di perangkat;
- login Supabase melalui Google atau Apple;
- izin lokasi, pencarian bag terdekat, filter, favorit, dan peta OpenStreetMap;
- checkout idempoten dalam mode simulasi, daftar status pesanan, dan detail
  pickup;
- QR pickup ber-token acak yang dapat diperbarui dan hanya tersedia saat order
  siap; merchant melakukan redeem lewat kamera;
- ulasan yang terikat ke order selesai, notifikasi dalam aplikasi secara
  realtime, edit profil, bantuan, dokumen legal, pergantian peran, dan hapus
  akun.

### Merchant

- setup/edit profil dan lokasi toko;
- buat, edit, duplikasi, aktif/nonaktifkan bag, jadwal tersedia/pickup, stok,
  serta unggah gambar;
- dashboard dan pesanan masuk realtime, tandai siap, detail order, scan/redeem
  QR satu kali;
- ledger saldo, rekening bank, dan permintaan payout dengan status terpantau;
- payout manual yang memakai rekening terverifikasi dan reservasi saldo
  idempoten; request uang riil dinonaktifkan server selama checkout simulasi.

### Backend dan keamanan

- Row Level Security, view aman untuk konsumen/merchant, dan RPC tervalidasi;
- pengurangan stok atomik, idempotency key untuk checkout/payout, snapshot harga
  dan informasi order, serta status kedaluwarsa;
- token pickup hanya disimpan sebagai hash, ledger merchant append-only, dan
  nomor rekening penuh hanya disimpan terenkripsi di vault schema privat dengan
  audit setiap akses plaintext;
- notifikasi/order/transaksi/payout masuk ke Supabase Realtime;
- penghapusan akun membersihkan file pengguna lalu menganonimkan catatan yang
  wajib dipertahankan untuk integritas order/akuntansi, setelah fase prepare
  berhasil memblokir order/payout dan mutasi baru.

## Menjalankan aplikasi

Prasyarat: Flutter yang mendukung Dart `^3.11.4`, Android Studio/Xcode sesuai
platform, dan project Supabase bila ingin memakai backend online.

```bash
flutter pub get
cp .env.example .env
flutter run --dart-define-from-file=.env
```

Isi `.env` dengan URL project dan publishable/anon key Supabase:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-publishable-or-anon-key
```

`.env` diabaikan Git dan **bukan** asset Flutter. Konfigurasi dibaca dari
`String.fromEnvironment`, sehingga untuk mode online perintah harus menyertakan
`--dart-define-from-file=.env` (atau dua `--dart-define` eksplisit). Jangan pernah
menaruh `service_role` key di aplikasi mobile.

Untuk menjalankan demo offline dengan data contoh:

```bash
flutter run
```

## Verifikasi perubahan

```bash
flutter analyze
flutter test
flutter test --coverage
flutter build apk --debug --dart-define-from-file=.env
```

Test tidak membutuhkan Supabase dan menggunakan backend palsu yang deterministik.
Panduan signing serta build release ada di
[SUPABASE_SETUP.md](SUPABASE_SETUP.md#8-build-release).

## Dokumentasi

- [SUPABASE_SETUP.md](SUPABASE_SETUP.md) — migrasi, OAuth, cron, operasi payout,
  konfigurasi platform, dan release checklist.
- [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) — arsitektur aplikasi,
  kontrak state/backend, pola layar, dan invariant implementasi.
- `supabase/migrations/0001_init.sql`,
  `supabase/migrations/0002_security_hardening.sql`, lalu
  seluruh migration bernomor berikutnya sampai
  `supabase/migrations/0010_cli_seed_support.sql` — skema database yang wajib
  dijalankan berurutan.

`supabase/seed.sql` hanya untuk local/staging. Ia membuat katalog yang visible
di bawah RLS melalui principal owner non-login; tester tetap masuk lewat OAuth,
bukan memakai akun/password demo.

## Batas rilis yang masih eksternal

- Payment gateway beserta webhook terverifikasi belum diimplementasikan sesuai
  prioritas proyek saat ini.
- Payout belum memakai rail/provider transfer otomatis. Primitive verifikasi,
  vault tujuan, audit akses, dan penyelesaian manual sudah tersedia untuk
  operator/worker `service_role`, tetapi request payout baru sengaja ditolak
  server sampai checkout uang riil mempunyai verifikasi payment gateway.
- Notifikasi realtime di dalam aplikasi sudah aktif. Push OS ketika aplikasi di
  background/terminated memerlukan project FCM/APNs, kredensial signing, token
  perangkat, dan worker pengirim yang belum dapat dikonfigurasi tanpa akun
  provider tersebut.
- Naskah Syarat & Ketentuan dan Kebijakan Privasi di aplikasi adalah draf produk
  dan harus direview pemilik bisnis/penasihat hukum sebelum publikasi.
