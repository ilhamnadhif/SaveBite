# SaveBite × Supabase — Setup dan Operasi

Dokumen ini menyiapkan backend online SaveBite. Run/build normal membaca
konfigurasi public Supabase dari `assets/config/supabase.env`. Demo offline hanya
aktif bila diminta eksplisit dengan `SAVEBITE_DEMO=true`; konfigurasi online yang
hilang atau tidak valid akan menampilkan layar error, bukan berpindah diam-diam
ke data contoh.

Pembayaran menggunakan Midtrans Snap. Order dimulai sebagai reservation
`pending`; hanya webhook atau Get Status yang diverifikasi oleh server yang dapat
mengubahnya menjadi `paid`. Deep link dan parameter callback di aplikasi hanya
memicu refresh, bukan menjadi bukti pembayaran.

## 1. Prasyarat

- satu project Supabase;
- Supabase CLI yang sudah login dan mempunyai akses deploy ke project tersebut;
- akun Midtrans sandbox atau production beserta **Server Key**;
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
11. `supabase/migrations/0011_backend_integrity.sql`
12. `supabase/migrations/0012_midtrans_payments.sql`
13. `supabase/migrations/0013_rls_performance.sql`
14. `supabase/migrations/0014_security_advisor_hardening.sql`

Migration kedua bergantung pada skema pertama. Ia menambahkan lifecycle order,
snapshot nilai transaksi, RPC idempoten, token pickup hash-only, review per
order, ledger append-only, bank/payout, account deletion, view aman, policy RLS,
publication Realtime, dan pembatasan Storage.
Migration ketiga menambahkan publisher notifikasi bag terjadwal, vault nomor
rekening terenkripsi dengan audit akses, serta penghapusan akun dua fase yang
aman untuk diulang.
Migration berikutnya menambahkan pembatalan order/review merchant, TTL token
pickup, konfigurasi biaya publik yang aman, input isi perkiraan bag, serta guard
fail-closed yang dibutuhkan oleh alur transaksi.
Migration kesembilan memastikan order `preparing` ikut kedaluwarsa, menutup
kolom owner merchant dari query katalog, menyediakan RPC owner-only untuk profil
toko, dan mewajibkan actor+reason pada setiap akses plaintext rekening.
Migration kesepuluh mengizinkan sesi operator resmi Supabase CLI menjalankan
seed tanpa mengendurkan guard mutasi untuk role aplikasi.
Migration kesebelas memperketat invariant backend dan integritas mutasi yang
dipakai aplikasi. Migration kedua belas menggantikan kontrak checkout simulasi
dengan reservation pembayaran Midtrans, tabel attempt dan state-machine,
webhook/Get Status terverifikasi, serta expiry reservation yang idempoten.
Migration ketiga belas mengoptimalkan evaluation helper Auth pada policy RLS
tanpa mengubah izin. Migration keempat belas mengunci `search_path` dan mencabut
akses RPC langsung ke fungsi yang hanya boleh dipanggil oleh trigger.
Pembayaran masuk aktif setelah fungsi dan credential dikonfigurasi, tetapi rail
payout keluar tetap dinonaktifkan.

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

Isi konfigurasi public klien yang dibundle di
`assets/config/supabase.env`:

```dotenv
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-publishable-or-anon-key
```

Project URL dan publishable/anon key memang public untuk aplikasi mobile dan
tetap dibatasi RLS. Jangan pernah memasukkan `service_role`, `sb_secret_`, atau
Midtrans Server Key ke asset, source Flutter, log, maupun binary aplikasi.

Run normal tidak membutuhkan dart-define:

```bash
flutter pub get
flutter run
```

File root `.env` tetap dapat dipakai sebagai override build opsional. Jika salah
satu define Supabase diberikan, keduanya harus lengkap dan akan menang atas
asset:

```bash
cp .env.example .env
flutter run --dart-define-from-file=.env
```

Untuk demo offline deterministik, gunakan flag yang eksplisit:

```bash
flutter run --dart-define=SAVEBITE_DEMO=true
```

Tanpa konfigurasi valid dan tanpa flag tersebut, aplikasi menampilkan error
konfigurasi. `FakeBackend` tidak pernah dipilih otomatis pada build normal.

## 5. Integrasi Midtrans

Kode database, Edge Function, deep link, dan UI pembayaran sudah tersedia.
Aktivasi sandbox hanya membutuhkan Midtrans Server Key pada server serta deploy
empat fungsi; aplikasi mobile tidak membutuhkan Midtrans Client Key maupun
Server Key.

Buat file secret lokal dari template yang tidak memuat credential asli:

```bash
cp supabase/midtrans.env.example supabase/.env.midtrans.local
```

Isi Server Key. Environment bersifat opsional dan default-nya `sandbox`:

```dotenv
MIDTRANS_SERVER_KEY=your-midtrans-server-key
MIDTRANS_ENVIRONMENT=sandbox
```

File nyata `supabase/.env.midtrans.local` tercakup `.gitignore`. Hubungkan CLI,
kirim secret, lalu deploy keempat fungsi dari root repository:

```bash
supabase login
supabase link --project-ref <project-ref>
supabase secrets set --env-file supabase/.env.midtrans.local
supabase functions deploy midtrans-create
supabase functions deploy midtrans-status
supabase functions deploy midtrans-webhook
supabase functions deploy midtrans-return
```

Pada staging yang fungsi-fungsinya sudah terpasang, cukup jalankan
`supabase secrets set MIDTRANS_SERVER_KEY='...'`; perubahan secret tersedia
langsung tanpa deploy ulang. Sandbox adalah default.

`SUPABASE_URL`, publishable/anon key, dan service-role/secret key disediakan oleh
host Supabase untuk Edge Functions. Jangan menyalinnya ke aplikasi mobile atau
ke template Midtrans. Untuk production, gunakan Server Key production dan ubah
`MIDTRANS_ENVIRONMENT=production`, lalu kirim ulang secret sebelum deploy/retest.

URL notifikasi adalah:

```text
https://<project-ref>.supabase.co/functions/v1/midtrans-webhook
```

`midtrans-create` menurunkan URL tersebut dari `SUPABASE_URL` dan mengirimkannya
sebagai header `X-Override-Notification` pada setiap transaksi Snap. Karena itu
tidak ada URL webhook yang perlu ditanam di mobile; URL yang sama boleh dipasang
di dashboard Midtrans sebagai fallback operasional.

Keempat fungsi sengaja memakai `verify_jwt = false` di `supabase/config.toml` agar
gateway Supabase tidak menolak token dari project yang memakai signing key
asimetris. Ini tidak membuat create/status anonim: kedua handler tetap
mewajibkan bearer token dan memvalidasi user dengan `auth.getUser()`. Endpoint
webhook memang tidak membawa JWT pengguna; handler memverifikasi signature
SHA-512 Midtrans dan selalu mengambil Get Status otoritatif sebelum memutasi
order. `midtrans-return` hanya mengembalikan redirect HTTPS-ke-deep-link; endpoint
ini tidak membaca atau mengubah status pembayaran.

Callback selesai/error sudah didaftarkan pada Android dan iOS sebagai:

```text
com.savebite://payment-callback/
```

Callback hanya membangunkan aplikasi dan memicu sinkronisasi status. Uji sandbox
minimal untuk status pending, settlement/capture, deny/failure, cancel, expiry,
refund, serta callback ketika aplikasi aktif, background, dan sebelumnya
ditutup. Jangan beralih ke production sebelum hasil webhook, Get Status, stok,
dan ledger sudah direkonsiliasi.

## 6. Izin perangkat dan peta

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

## 7. Cron order dan bag terjadwal

`public.expire_orders(limit)` melepaskan reservation pembayaran yang melewati
`payment_expires_at`, lalu mengakhiri order `paid`/`preparing`/`ready` yang
melewati jendela pickup. `public.publish_due_bag_notifications(limit)`
menerbitkan notifikasi terdeduplikasi untuk follower ketika bag terjadwal
memasuki tanggal tersedia di zona Jakarta. Keduanya hanya boleh dipanggil oleh
konteks tepercaya, bukan klien `anon`/`authenticated`.

Migration `0012` mengaktifkan `pg_cron` dan memasang ulang job
`savebite-expire-orders` secara idempoten setiap lima menit. Jangan membuat job
expiry kedua. Verifikasi otomatisasi setelah migration:

```sql
select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'savebite-expire-orders';
```

Publisher notifikasi bag tetap perlu dijadwalkan satu kali. Bila job dengan nama
ini belum ada, jalankan:

```sql
select cron.schedule(
  'savebite-publish-due-bags',
  '*/5 * * * *',
  'select public.publish_due_bag_notifications(1000)'
);
```

Pantau `cron.job_run_details` dan buat alert bila job berulang kali gagal.
Worker eksternal juga boleh memanggil RPC dengan `service_role`, tetapi key
tersebut harus tetap berada di server/secret manager.

## 8. Rekening dan payout manual

Payout di aplikasi adalah workflow manual, bukan bukti transfer selesai:

> Migration `0012` mengaktifkan pembayaran masuk Midtrans yang terverifikasi,
> tetapi tetap menetapkan `payouts_enabled = 0`. Request payout baru akan ditolak
> fail-closed sampai rail transfer keluar serta prosedur refund/chargeback
> operasional tersedia. Langkah di bawah adalah runbook yang sudah disiapkan
> untuk diaktifkan setelah batas eksternal tersebut diselesaikan.

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

## 9. Build release

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
flutter build appbundle --release
```

### iOS

Salin template Team ID (file nyata diabaikan Git):

```bash
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig
```

Ganti `DEVELOPMENT_TEAM`, pilih certificate/provisioning profile yang benar di
Xcode, aktifkan capability Sign in with Apple bila provider digunakan, lalu:

```bash
flutter build ipa --release
```

Sebelum upload store, naikkan `version`/build number di `pubspec.yaml`, tes
artifact release pada perangkat, dan verifikasi OAuth callback, kamera, lokasi,
galeri, serta account deletion.

## 10. Quality gate

```bash
flutter analyze
flutter test
flutter test --coverage
flutter build apk --debug
```

Untuk validasi backend, gunakan sedikitnya dua akun konsumen dan dua akun
merchant agar isolasi RLS dapat diuji. Coba checkout paralel pada stok terakhir,
retry dengan idempotency key yang sama, rotasi dan penggunaan ulang QR,
redeem di luar waktu pickup, review order orang lain, baca order lintas merchant,
payout melebihi saldo, serta hapus akun saat payout masih berjalan.

## 11. Setup eksternal sebelum produksi

- **Midtrans:** implementasi kode sudah lengkap. Pengelola tinggal memasukkan
  Server Key server-side, memilih environment, deploy keempat Edge Function, dan
  menyelesaikan uji sandbox end-to-end sebelum memakai credential production.
- **Supabase Auth:** aplikasi hanya mengekspos login OAuth. Bila email/password
  diaktifkan di kemudian hari, aktifkan Leaked Password Protection pada Auth
  Attack Protection dan ulangi Security Advisor.
- **OS push:** notifikasi realtime saat aplikasi terbuka sudah bekerja melalui
  Supabase. Background/terminated push memerlukan project FCM, APNs key,
  capability iOS, registrasi token perangkat, dan worker/Edge Function pengirim.
- **Legal:** teks Syarat & Ketentuan serta Kebijakan Privasi dalam aplikasi masih
  draf; minta review hukum dan isi identitas badan usaha, kontak, retensi data,
  kebijakan refund, serta yurisdiksi final.
- **Operasional:** pasang monitoring job cron, error reporting, backup/PITR,
  rotasi secret, alert payout, dan prosedur rekonsiliasi sebelum go-live.
