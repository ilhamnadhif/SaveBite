# SaveBite × Supabase — Setup dan Operasi

Dokumen ini menyiapkan backend online SaveBite. Untuk demo tanpa Supabase,
jalankan `flutter run`; aplikasi akan memilih `FakeBackend` secara otomatis.

> Payment gateway belum terhubung. RPC checkout saat ini membuat order berbayar
> sebagai kontrak sementara untuk simulasi UI. Sebelum menerima uang riil,
> status `paid` harus hanya berasal dari webhook gateway yang terverifikasi.

## 1. Prasyarat

- satu project Supabase;
- Flutter SDK yang kompatibel dengan Dart `^3.11.4`;
- Google OAuth client dan/atau konfigurasi Sign in with Apple;
- Android Studio untuk Android, serta macOS + Xcode untuk iOS;
- akses operator/server yang aman untuk tugas `service_role` seperti verifikasi
  bank, penyelesaian payout, dan expiry scheduler.

Ambil **Project URL** dan **publishable/anon key** dari dashboard Supabase. Key
ini memang ditujukan untuk klien dan tetap dibatasi RLS. `service_role` key
bersifat rahasia dan tidak boleh berada di `.env`, source code, log, atau binary
mobile.

## 2. Terapkan database

Jalankan file berikut secara utuh dan berurutan melalui SQL Editor atau alur
migration Supabase:

1. `supabase/migrations/0001_init.sql`
2. `supabase/migrations/0002_security_hardening.sql`
3. `supabase/migrations/0003_security_ops.sql`
4. `supabase/migrations/0004_orders_reviews.sql`
5. `supabase/migrations/0005_pickup_token_ttl.sql`
6. `supabase/migrations/0006_public_app_config.sql`
7. `supabase/migrations/0007_bag_contents.sql`
8. `supabase/migrations/0008_simulation_safety.sql`
9. `supabase/migrations/0009_operational_hardening.sql`
10. `supabase/migrations/0010_cli_seed_support.sql`

Migration kedua bergantung pada skema pertama. Ia menambahkan lifecycle order,
snapshot nilai transaksi, RPC idempoten, token pickup hash-only, review per
order, ledger append-only, bank/payout, account deletion, view aman, policy RLS,
publication Realtime, dan pembatasan Storage.
Migration ketiga menambahkan publisher notifikasi bag terjadwal, vault nomor
rekening terenkripsi dengan audit akses, serta penghapusan akun dua fase yang
aman untuk diulang.
Migration berikutnya menambahkan pembatalan order/review merchant, TTL token
pickup, konfigurasi biaya publik yang aman, input isi perkiraan bag, serta
fail-closed ledger/payout selama checkout masih simulasi.
Migration kesembilan memastikan order `preparing` ikut kedaluwarsa, menutup
kolom owner merchant dari query katalog, menyediakan RPC owner-only untuk profil
toko, dan mewajibkan actor+reason pada setiap akses plaintext rekening.
Migration kesepuluh mengizinkan sesi operator resmi Supabase CLI menjalankan
seed tanpa mengendurkan guard mutasi untuk role aplikasi.

`supabase/seed.sql` adalah fixture khusus local/staging dan tidak boleh dijalankan
di production. Seed membuat delapan principal Auth owner dengan ID tetap,
profile aktif, merchant yang lolos RLS, dan sembilan bag bertanggal hari Jakarta.
Principal tersebut sengaja **tidak mempunyai `auth.identities` dan tidak punya
password yang diketahui**, sehingga bukan kredensial login aplikasi. Login
tester tetap melalui OAuth; Auth user yang dipertahankan oleh linked reset akan
dibuatkan kembali profile-nya. Menjalankan ulang seed merekonsiliasi stok/status
fixture, jadi anggap operasi ini destruktif untuk data demo dengan ID tersebut.

Sesudah migrasi, periksa setidaknya:

- tabel RLS berstatus aktif;
- bucket `bag-images`, `store-logos`, dan `avatars` tersedia;
- batas unggahan bucket 2 MB dan MIME type gambar diterapkan;
- `supabase_realtime` memuat `notifications`, `orders`, `transactions`, dan
  `payout_requests`;
- view `public_merchants`, `available_bags`, `consumer_orders`,
  `merchant_orders`, `my_bank_accounts`, dan `merchant_balance` dapat dibaca
  sesuai peran.

## 3. Konfigurasi OAuth

Callback dari provider menuju Supabase adalah:

```text
https://<project-ref>.supabase.co/auth/v1/callback
```

Daftarkan URL tersebut pada Google Cloud OAuth client dan konfigurasi Apple.
Aktifkan provider yang dipakai di **Authentication → Providers** pada Supabase,
lalu tambahkan deep link aplikasi berikut ke allow-list redirect Supabase:

```text
com.savebite://login-callback
```

Deep link tersebut sudah didaftarkan pada Android dan iOS. `AuthService`
menggunakannya untuk Google maupun Apple. Pastikan package/bundle identifier
tetap `com.savebite.savebite`, atau selaraskan konfigurasi native dan provider
bila identifier diubah.

Untuk Apple, lengkapi Team ID, Service ID, Key ID, dan private key pada provider
Supabase sesuai akun Apple Developer. Untuk Google, lengkapi Client ID dan
Client Secret. Uji callback pada perangkat nyata untuk kedua provider yang
diaktifkan.

## 4. Konfigurasi runtime

Salin template lokal:

```bash
cp .env.example .env
```

Isi hanya konfigurasi klien:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-publishable-or-anon-key
```

Jalankan:

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

`.env` sudah masuk `.gitignore`, tidak tercantum sebagai asset di `pubspec.yaml`,
dan tidak dibaca oleh `flutter_dotenv`. Nilainya masuk sebagai compile-time
define; file `.env` itu sendiri tidak dibundle. Untuk CI, sediakan file sementara
dari secret store atau gunakan:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-publishable-or-anon-key
```

Tanpa kedua nilai tersebut aplikasi sengaja berjalan offline dengan
`FakeBackend`.

## 5. Izin perangkat dan peta

Android sudah mendeklarasikan Internet, kamera, coarse location, dan fine
location. iOS sudah mempunyai usage description untuk kamera, lokasi saat app
digunakan, dan galeri. Kamera/GPS tidak ditandai sebagai hardware wajib sehingga
pengguna tetap dapat menjelajah saat fitur tersebut tidak tersedia.

Aplikasi meminta izin saat fitur digunakan, menangani `denied` dan
`deniedForever`, serta menyediakan jalan ke Settings. Peta memakai tile
OpenStreetMap dan menampilkan atribusi. Untuk trafik produksi berskala besar,
gunakan tile provider yang SLA dan kebijakan penggunaannya sesuai kebutuhan;
jangan membebani public tile server.

Uji pada perangkat nyata:

- izin lokasi pertama kali, ditolak, ditolak permanen, GPS mati, dan lokasi
  berhasil;
- buka atribusi peta;
- izin kamera ditolak/diberikan dan scan QR pickup;
- pemilihan gambar dari galeri serta penolakan file di atas 2 MB.

## 6. Cron order dan bag terjadwal

`public.expire_orders(limit)` dan
`public.publish_due_bag_notifications(limit)` harus dipanggil periodik oleh
konteks tepercaya. Fungsi pertama mengubah order `paid`/`preparing`/`ready` yang
melewati `expires_at` menjadi `expired`. Fungsi kedua menerbitkan notifikasi terdeduplikasi
untuk follower ketika bag terjadwal memasuki tanggal tersedia di zona Jakarta.
Keduanya tidak dapat dieksekusi oleh klien `anon`/`authenticated`.

Rekomendasi: aktifkan **Supabase Cron** dan buat job setiap lima menit dengan
perintah:

```sql
select public.expire_orders(500);
select public.publish_due_bag_notifications(1000);
```

Jika menggunakan SQL `pg_cron`, aktifkan extension dari dashboard lalu jadwalkan
ekuivalennya:

```sql
select cron.schedule(
  'savebite-expire-orders',
  '*/5 * * * *',
  'select public.expire_orders(500)'
);

select cron.schedule(
  'savebite-publish-due-bags',
  '*/5 * * * *',
  'select public.publish_due_bag_notifications(1000)'
);
```

Pantau hasil job dan alert bila berulang kali gagal. Worker eksternal juga boleh
memanggil RPC dengan `service_role`, tetapi key tersebut harus tetap berada di
server/secret manager.

## 7. Rekening dan payout manual

Payout di aplikasi adalah workflow manual, bukan bukti transfer selesai:

> Migration `0008` menetapkan `payouts_enabled = 0` selama checkout belum
> diverifikasi payment gateway. Karena payment gateway memang ditunda, request
> payout baru akan ditolak fail-closed dan pendapatan simulasi tidak masuk saldo
> yang dapat ditarik. Langkah di bawah adalah runbook operasional yang sudah
> disiapkan untuk data non-simulasi ketika fitur uang riil kelak diaktifkan.

1. merchant mendaftarkan rekening; skema publik hanya menyimpan hash ber-pepper
   yang mencakup kode bank, empat digit terakhir, dan metadata aman. Nomor penuh
   dienkripsi AES-256 di schema `private`;
2. operator/worker mengambil tujuan verifikasi melalui RPC `service_role`
   `get_bank_account_verification_data`. Hanya rekening `pending` yang dapat
   dibuka; setiap dekripsi wajib menyertakan ID actor stabil dan alasan, lalu
   otomatis dicatat beserta context JWT/database ke audit privat;
3. operator/worker memverifikasi kepemilikan di luar aplikasi;
4. konteks `service_role` memanggil `verify_bank_account` dengan status
   `verified` atau `rejected`;
5. merchant dapat meminta penarikan dari rekening terverifikasi. Minimum saat
   ini Rp50.000 dan biaya admin Rp2.500;
6. saldo langsung direservasi melalui ledger agar permintaan paralel tidak
   menarik saldo yang sama;
7. operator mengambil tujuan payout aktif melalui `get_payout_destination`
   dengan alasan audit, melakukan transfer manual, lalu worker memanggil
   `resolve_payout_request` ke `processing`, kemudian `paid`; gunakan `failed`
   atau `cancelled` bila gagal agar reversal ledger dibuat otomatis.

Contoh berikut hanya dijalankan dari SQL Editor/worker tepercaya, bukan klien:

```sql
select public.get_bank_account_verification_data(
  '<bank-account-uuid>',
  'worker-verification-01',
  'Verifikasi rekening tiket OPS-1234'
);

select public.verify_bank_account(
  '<bank-account-uuid>',
  'verified',
  '<provider-recipient-id>'
);

select public.get_payout_destination(
  '<payout-request-uuid>',
  'worker-payout-01',
  'Transfer manual tiket OPS-5678'
);

select public.resolve_payout_request(
  '<payout-request-uuid>',
  'processing',
  '<operator-or-provider-reference>',
  null
);

select public.resolve_payout_request(
  '<payout-request-uuid>',
  'paid',
  '<operator-or-provider-reference>',
  null
);
```

Jangan menandai `paid` sebelum transfer benar-benar terkonfirmasi. Jangan log,
cache, atau teruskan field `account_number` di luar worker tepercaya. Nilai actor
harus berasal dari identitas worker/operator yang stabil; label ini meningkatkan
traceability tetapi shared `service_role` saja tidak memberi nonrepudiation, jadi
letakkan RPC di balik worker dengan autentikasi operator terpisah. Audit akses
`service_role`, gunakan idempotency key dari aplikasi, dan rekonsiliasi ledger
dengan rekening operasional. Rekening yang dibuat sebelum migration `0003`
harus didaftarkan ulang sekali agar ciphertext vault tersedia.

### Penghapusan akun dua fase

Klien terlebih dahulu memanggil `prepare_delete_my_account()`. RPC ini mengunci
akun, menolak proses bila payout masih `requested`/`processing` atau order
konsumen/merchant masih aktif, lalu memasang marker yang menghentikan mutasi baru.
Setelah marker berhasil, klien menghapus objek pada folder Storage UID miliknya
dan memanggil `delete_my_account()` untuk anonymization final. Bila cleanup
Storage atau jaringan gagal, ulangi rangkaian yang sama; kedua RPC idempoten
terhadap fase persiapannya dan mutasi normal tetap diblokir sampai finalisasi
berhasil. RPC final juga memeriksa ketiga bucket dan menolak penghapusan Auth
selama masih ada objek dengan prefix UID, sehingga file publik tidak menjadi
orphan tanpa pemilik.

## 8. Build release

### Android

Buat upload keystore di tempat aman, lalu salin template:

```bash
cp android/key.properties.example android/key.properties
```

Isi `storeFile`, `storePassword`, `keyAlias`, dan `keyPassword` sesuai keystore.
`android/key.properties` dan file keystore sudah diabaikan Git. Build release
sengaja gagal bila konfigurasi signing ini tidak tersedia sehingga artifact
distribusi tidak pernah diam-diam memakai debug key.

```bash
flutter build appbundle --release --dart-define-from-file=.env
```

### iOS

Salin template Team ID (file nyata diabaikan Git):

```bash
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig
```

Ganti `DEVELOPMENT_TEAM`, pilih certificate/provisioning profile yang benar di
Xcode, aktifkan capability Sign in with Apple bila provider digunakan, lalu:

```bash
flutter build ipa --release --dart-define-from-file=.env
```

Sebelum upload store, naikkan `version`/build number di `pubspec.yaml`, tes
artifact release pada perangkat, dan verifikasi OAuth callback, kamera, lokasi,
galeri, serta account deletion.

## 9. Quality gate

```bash
flutter analyze
flutter test
flutter test --coverage
flutter build apk --debug --dart-define-from-file=.env
```

Untuk validasi backend, gunakan sedikitnya dua akun konsumen dan dua akun
merchant agar isolasi RLS dapat diuji. Coba checkout paralel pada stok terakhir,
retry dengan idempotency key yang sama, rotasi dan penggunaan ulang QR,
redeem di luar waktu pickup, review order orang lain, baca order lintas merchant,
payout melebihi saldo, serta hapus akun saat payout masih berjalan.

## 10. Setup eksternal sebelum produksi

- **Payment gateway:** pilih provider, buat status `pending`, endpoint webhook
  bertanda tangan, rekonsiliasi, refund/cancel/expiry, dan hanya ubah ke `paid`
  setelah callback server terverifikasi.
- **OS push:** notifikasi realtime saat aplikasi terbuka sudah bekerja melalui
  Supabase. Background/terminated push memerlukan project FCM, APNs key,
  capability iOS, registrasi token perangkat, dan worker/Edge Function pengirim.
- **Legal:** teks Syarat & Ketentuan serta Kebijakan Privasi dalam aplikasi masih
  draf; minta review hukum dan isi identitas badan usaha, kontak, retensi data,
  kebijakan refund, serta yurisdiksi final.
- **Operasional:** pasang monitoring job cron, error reporting, backup/PITR,
  rotasi secret, alert payout, dan prosedur rekonsiliasi sebelum go-live.
