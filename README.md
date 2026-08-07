# SaveBite

SaveBite adalah aplikasi Flutter untuk menjual kembali makanan surplus dalam
bentuk _Surprise Bag_. Satu aplikasi melayani dua peran: konsumen menemukan dan
memesan bag di sekitar mereka, sedangkan merchant mengelola toko, stok, pickup,
dan saldo.

Backend aplikasi menggunakan Supabase (Auth, Postgres, Realtime, Storage, dan
Edge Functions). Pembayaran menggunakan Midtrans Snap yang dikunci ke
`other_qris`; halaman checkout tampil di WebView/overlay internal aplikasi tanpa
membuka browser eksternal. Pembuatan transaksi, sinkronisasi Get Status,
verifikasi webhook, dan perubahan status lunas semuanya berjalan di server.
Aplikasi tidak pernah menyimpan Midtrans Server Key atau mempercayai callback
dan tampilan checkout sebagai bukti pembayaran.

## Fitur yang tersedia

### Konsumen

- onboarding dan pilihan peran yang tersimpan di perangkat;
- login Supabase melalui Google atau Apple;
- izin lokasi, pencarian bag terdekat, filter, favorit, dan peta OpenStreetMap;
- checkout Snap QRIS yang idempoten di WebView/overlay internal, pemulihan
  pembayaran tertunda setelah aplikasi ditutup, rekonsiliasi server, daftar
  status pesanan, dan detail pickup;
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
  idempoten; rail transfer otomatis tetap dipisahkan dari Midtrans payment.

### Backend dan keamanan

- Row Level Security, view aman untuk konsumen/merchant, dan RPC tervalidasi;
- pengurangan stok atomik, idempotency key untuk checkout/payout, snapshot harga
  dan informasi order, serta status kedaluwarsa;
- reservation pembayaran 15 menit, Midtrans status state-machine yang
  fail-closed, signature webhook SHA-512, dan rekonsiliasi Get Status;
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
flutter run
```

Run/build biasa membaca konfigurasi public client dari
`assets/config/client.env`. Isi file tersebut dengan konfigurasi public
Supabase serta Midtrans:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-publishable-or-anon-key
MIDTRANS_CLIENT_KEY=your-public-midtrans-client-key
MIDTRANS_ENVIRONMENT=sandbox
```

Keempat nilai tersebut memang public untuk client. Client Key diperlukan build
web untuk membuka Snap.js overlay; Android/iOS memakai redirect URL langsung di
WebView dan tidak membutuhkan Client Key untuk memuat checkout. Jangan pernah
menaruh `service_role`, `sb_secret_`, Midtrans Server Key, atau secret backend
lain di asset. File `.env` lokal tetap dapat dipakai sebagai override saat build
melalui `--dart-define-from-file=.env`. Bila satu nilai konfigurasi client
diberikan melalui define, seluruh profil compile-time wajib memuat keempat nilai
Supabase dan Midtrans agar credential sandbox/production tidak tercampur dengan
asset.

Build release sandbox hanya untuk staging/internal dan harus diizinkan
eksplisit. Tombol salin URL gambar QRIS dan alat bantu uji lainnya hanya
tampil pada artifact internal dengan mode E2E aktif; UI sandbox biasa dan
production tetap bersih:

```bash
flutter build appbundle --release \
  --dart-define=SAVEBITE_ALLOW_SANDBOX_RELEASE=true
# Tambahkan --dart-define=SAVEBITE_E2E=true hanya pada artifact tester internal.
```

Build production wajib memberikan satu profil public client yang lengkap dan
atomik; jangan gunakan `SAVEBITE_ALLOW_SANDBOX_RELEASE` atau `SAVEBITE_E2E`:

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://your-production-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-production-publishable-key \
  --dart-define=MIDTRANS_CLIENT_KEY=your-production-midtrans-client-key \
  --dart-define=MIDTRANS_ENVIRONMENT=production
```

Untuk menjalankan demo offline dengan data contoh:

```bash
flutter run --dart-define=SAVEBITE_DEMO=true
```

Tanpa konfigurasi Supabase dan tanpa flag demo eksplisit, aplikasi menampilkan
error konfigurasi dan tidak akan menyamar sebagai login online yang berhasil.

Untuk mengaktifkan pembayaran, terapkan seluruh migration sampai `0021`, simpan
`MIDTRANS_SERVER_KEY` dan `MIDTRANS_ENVIRONMENT` sebagai Supabase Edge Function
secret, lalu deploy lima Edge Function Midtrans. Environment server wajib
bernilai persis `sandbox` atau `production`; nilai hilang, alias, dan flag lama
`MIDTRANS_IS_PRODUCTION` yang berkonflik akan ditolak. URL webhook dan callback
selesai diterapkan otomatis per transaksi. Snap hanya mengaktifkan
`other_qris`, sehingga metode lain tidak dapat dipilih dari checkout. Project
yang sudah memakai QRIS Core wajib masuk maintenance dan mencapai **nol
checkout aktif yang belum lunas** sebelum menerapkan `0021`; jangan melakukan
rollout saat trafik checkout masih terbuka. Langkah preflight dan urutan rollout
ada di [SUPABASE_SETUP.md](SUPABASE_SETUP.md#rollout-snap-webview-dari-qris-core).

## Verifikasi perubahan

```bash
flutter analyze
flutter test
flutter test --coverage
flutter build apk --debug
```

Test tidak membutuhkan Supabase dan menggunakan backend palsu yang deterministik.
Panduan signing serta build release ada di
[SUPABASE_SETUP.md](SUPABASE_SETUP.md#9-build-release).

## Dokumentasi

- [SUPABASE_SETUP.md](SUPABASE_SETUP.md) — migrasi, OAuth, cron, operasi payout,
  konfigurasi platform, dan release checklist.
- [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) — arsitektur aplikasi,
  kontrak state/backend, pola layar, dan invariant implementasi.
- `supabase/migrations/0001_init.sql`,
  `supabase/migrations/0002_security_hardening.sql`, lalu
  seluruh migration bernomor berikutnya sampai
  `supabase/migrations/0021_snap_webview_checkout.sql` — skema database yang wajib
  dijalankan berurutan.

`supabase/seed.sql` hanya untuk local/staging. Ia membuat katalog yang visible
di bawah RLS melalui principal owner non-login; tester tetap masuk lewat OAuth,
bukan memakai akun/password demo.

## Batas rilis yang masih eksternal

- Midtrans Server Key tetap harus dimasukkan oleh pengelola sebagai secret
  server-side; source code dan aplikasi tidak boleh memuatnya. Client Key adalah
  publishable key dan dibundel ke build web untuk Snap.js overlay. Android/iOS
  memakai direct redirect WebView dan tidak menggunakannya untuk memuat Snap.
  URL notifikasi diturunkan dari project Supabase dan dikirim otomatis pada
  setiap transaksi; dashboard Midtrans dapat memakai URL yang sama sebagai
  fallback.
- Payout belum memakai rail/provider transfer otomatis. Primitive verifikasi,
  vault tujuan, audit akses, dan penyelesaian manual sudah tersedia untuk
  operator/worker `service_role`; request payout baru tetap dinonaktifkan sampai
  rail payout dan prosedur refund/chargeback operasional disiapkan.
- Notifikasi realtime di dalam aplikasi sudah aktif. Push OS ketika aplikasi di
  background/terminated memerlukan project FCM/APNs, kredensial signing, token
  perangkat, dan worker pengirim yang belum dapat dikonfigurasi tanpa akun
  provider tersebut.
- Naskah Syarat & Ketentuan dan Kebijakan Privasi di aplikasi adalah draf produk
  dan harus direview pemilik bisnis/penasihat hukum sebelum publikasi.
