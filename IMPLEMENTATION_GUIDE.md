# SaveBite — Panduan Implementasi Flutter

Dokumen ini menjelaskan arsitektur dan invariant yang dipakai implementasi
SaveBite saat ini. Untuk setup environment, migration, OAuth, cron, dan signing,
lihat `SUPABASE_SETUP.md`. Referensi visual awal tetap berada di
`.design/desain-aplikasi-savebite/project/SaveBite.dc.html`, sedangkan source
Dart adalah sumber kebenaran untuk perilaku aplikasi.

## Aturan umum

- Pertahankan copy Bahasa Indonesia, design token, dan pola komponen yang sudah
  ada. Gunakan widget foundation sebelum membuat variasi baru.
- Layar mengambil/mengubah data melalui `appState`; jangan mengakses Supabase
  langsung dari widget.
- Semua perpindahan layar lintas fitur masuk melalui `AppNav` agar reset stack,
  intent peran, dan logout konsisten.
- Render gambar dengan `FoodImage`; komponen ini menangani asset lokal, URL
  Storage, cache, loading, dan fallback.
- Ikon memakai Material Icons, bukan emoji.
- Semua aksi async wajib mempunyai busy state, feedback error yang dapat dibaca,
  dan guard agar submit ganda tidak menghasilkan mutasi berulang.
- Status lunas hanya boleh berasal dari state pembayaran server yang sudah
  direkonsiliasi ke Midtrans. Deep link client hanya memicu refresh status.

## Warna (lib/theme/app_colors.dart) — `AppColors.*`
cream `#FBF7EF`, green `#0F3D2C`, greenDark `#16442F`, greenBright `#27A36A`,
greenAccent `#1E8456`, greenSoftBg `#E8F3EC`, greenSoftBorder `#C9E3D2`,
greenMuted `#9FC9B2`, brown `#8A3A14`, brownCard `#9C4720`, terracotta `#E2592B`,
terracottaSoftBg `#FBEFDD`, terracottaSoftBorder `#F0DDB9`, amber `#EFA63C`,
goldOnDark `#EFC07A`, ink `#16231C`, body `#5C685F`, body2 `#4F6157`,
muted `#8A958C`, navInactive `#A0A89F`, strikethrough `#A39B89`,
border `#F0EADB`, borderAlt `#ECE4D3`, divider `#F4EEE0`, inputBorder `#E3D9C5`,
chipBorder `#E7DDC8`, handle `#D7CFBE`, neutralChip `#F1ECE0`, white,
danger `#C24420`, dangerBg `#FBE4DB`, dangerSoftBg `#FBE8E2`,
scanBg `#101512`, scanCard `#1B221D`, scanMuted `#9FB3A6`,
mapBg `#E6E9E0`, mapGrid `#DCE2D6`, mapRoad `#CFD8C6`,
gopay `#00AA13`, ovo `#4C2A86`, bca `#005BAA`, userDot `#2D7BE5`,
amberAvatar `#F2A33C`, merchantMuted `#F0C9A8`, saveBg `#FBE9DF`, saveText `#C2410C`.

## Teks — `AppText.*`
- `AppText.display(size, {weight=800, color, height, letterSpacing=-0.5})` → Bricolage (judul).
- `AppText.ui(size, {weight=500, color, height, letterSpacing, decoration, decorationColor})` → Plus Jakarta Sans (UI/body).
- weight valid: 400/500/600/700/800.

## Komponen foundation (baca file untuk detail; ringkasannya:)
`lib/widgets/brand.dart`: `AppLogo(size, {background, dotColor, leafColor})`,
`AppLogoWordmark({logoSize, textSize, textColor})`.

`lib/widgets/buttons.dart`:
`PrimaryButton(label, {onTap, background, foreground, height=54, fontSize=16, icon})`,
`PrimaryButton.merchant(label, {onTap, icon})` (terakota),
`GhostButton(label, {onTap, color})`, `CircleIconButton(child, {onTap, size=38, background})`,
`BackChevron({onTap, color})`.

`lib/widgets/chips.dart`:
`SelectChip(label, {selected, onTap, selectedColor=green, padding, fontSize})`,
`StatusBadge(text, {background, foreground, fontSize=11, weight=800, padding})` +
factory `StatusBadge.available/waiting/done/expired/neutral/save(text)`,
`OverlayBadge(text, {dark=false, lightForeground})` (badge di atas foto).

`lib/widgets/bag_cards.dart`:
`FoodImage(path, {width, height, saturation=1, fit})` (1=warna, <1 desaturasi),
`BottomScrim({stop})`, `SaveRibbon(text:'HEMAT 67%', {top, fontSize, padding})`,
`PriceTag(salePrice, originalPrice, {saleSize=23, saleColor=green})`,
`SaveLabel()`, `StoreAvatar(initial, color, {size=28, radius, border, borderColor})`,
`BagHeroCard(bag, {onTap})` (kartu beranda besar),
`BagCompactCard(bag, {onTap})` (kartu beranda kecil).

`lib/widgets/bottom_nav.dart`: `AppBottomNav` + `AppBottomNav.consumerItems` /
`.merchantItems` (dipakai oleh shell, biasanya tidak perlu di layar).

`lib/widgets/common.dart`:
`SheetHandle()`, `ColoredHeader(background, child, {bottomPadding=16, horizontalPadding=20})`
(header berwarna yang menembus status bar),
`SimpleHeader(title, {onBack, trailing, background=white, showBack=true, titleSize=19})`
(header putih + tombol kembali; menangani inset status bar sendiri),
`FieldLabel(text)`, `AppTextField({initialValue, hintText, maxLines, borderColor, trailing, keyboardType})`,
`QtyStepper(value, {onMinus, onPlus, plusColor=green, suffix})`,
`MenuRow(icon, label, {onTap, last})`,
`StatTile(value, label, {background, valueColor, labelColor, border})`,
`SectionHeading(title, {leadingIcon, actionLabel, onAction, actionColor=greenBright, fontSize=17})`,
`TabSwitch(tabs, index, onTap, {activeColor=green, underlineColor=green, badges})`,
`ProgressBar(fraction, {color=greenBright, background=border, height=7})`,
`InfoBanner(child, {icon, background=greenSoftBg, iconColor=greenAccent})`,
`AppCard(child, {padding, radius=18, borderColor=border, borderWidth=1, onTap})`.

`lib/widgets/qr_box.dart`: `QrBox(data, {size=190})`.

Radius: `AppRadius.card=22, cardSm=18, button=16, input=14, pill=20, sheet=28`.
Bayangan kartu hero: `kHeroCardShadow`. Bayangan sheet: `kSheetShadow`.

## Struktur aplikasi

```text
lib/
├── main.dart                    bootstrap environment, auth listener, app
├── app_state.dart               state + orkestrasi use case
├── app_nav.dart                 satu pintu navigasi
├── config/env.dart              public Supabase config + explicit demo flag
├── data/
│   ├── models.dart              model domain
│   ├── mappers.dart             map row Supabase ke model
│   ├── sample_data.dart         fixture FakeBackend
│   └── backend/
│       ├── backend.dart         kontrak backend
│       ├── fake_backend.dart    explicit demo/test implementation
│       └── supabase_backend.dart online implementation
├── services/                    backend, Auth, antrean, payment deep-link
├── screens/{onboarding,consumer,merchant,shared}/
├── theme/                       color, typography, Material theme
└── widgets/                     komponen UI reusable
```

`main()` membaca URL + publishable/anon key publik dari
`assets/config/supabase.env`; dart-define yang lengkap dapat mengoverride asset.
Konfigurasi hilang/salah menampilkan layar error. `FakeBackend` hanya aktif
dengan `--dart-define=SAVEBITE_DEMO=true`, sehingga error produksi tidak pernah
tersamar sebagai login demo.

## Model dan kontrak backend

Model domain berada di `lib/data/models.dart`. `Bag` dipakai katalog konsumen,
sedangkan `MerchantBag` menyertakan data pengelolaan seperti status, stok,
tanggal tersedia, serta waktu pickup. `OrderRecord` memisahkan `OrderStatus`
(fulfillment) dari `PaymentState` (awaiting/pending/paid/terminal), sedangkan
`IncomingOrder` adalah perspektif merchant. Nilai tidak dikenal, refund, dan
chargeback wajib fail-closed dan tidak boleh jatuh ke status paid.

`lib/data/backend/backend.dart` adalah batas I/O. Fitur baru harus ditambahkan
ke interface, lalu diimplementasikan pada **keduanya**:

- `FakeBackend` untuk demo dan test deterministik;
- `SupabaseBackend` untuk Auth user aktif, view/RPC aman, Storage, dan Realtime.

Kelompok use case yang tersedia:

- profil, mode terakhir, dan hapus akun;
- nearby/search/filter, toko, favorit;
- checkout idempoten, refresh status Midtrans, daftar order, token pickup,
  review;
- notifikasi dan stream realtime;
- profil toko, CRUD/duplikasi/aktivasi bag beserta jadwal;
- order merchant, mark ready, redeem token, statistik;
- ledger saldo/transaksi, rekening, dan payout manual;
- upload gambar menurut bucket.

Jangan membuat fallback dari error Supabase ke data contoh di tengah sesi.
Mode backend dipilih sekali saat startup agar kegagalan produksi tidak tersamar
sebagai data demo.

## State — `appState`

`AppState` adalah `ChangeNotifier` tunggal yang menyimpan snapshot UI dan
mengorkestrasi backend. Widget reaktif memakai:

```dart
ListenableBuilder(
  listenable: appState,
  builder: (context, _) => /* baca getter appState */,
)
```

State lokal berikut dipersist melalui `SharedPreferences`: onboarding selesai,
location priming, lokasi/koordinat terakhir, metode pembayaran default, dan
intent login merchant. Onboarding adalah preference tingkat perangkat. State
lokasi, koordinat, metode pembayaran, dan intent merchant hanya dipakai dalam
konteks sesi terkait serta dibersihkan saat sign-out agar tidak bocor ke akun
berikutnya. Mode terakhir disimpan pada profil backend. Filter aktif hanya
berlaku selama proses aplikasi. Data akun, order, saldo, rekening, serta
notifikasi selalu dimuat ulang dari backend per sesi.

Operasi penting:

- `restoreLocalState()` dipanggil sebelum `runApp`;
- `bootstrap()` memuat profil dan data peran setelah auth;
- `determineLocation()` menangani service/permission GPS dan memperbarui katalog;
- `setBagFilter()` dan `search()` meneruskan filter serta koordinat aktif;
- `placeOrder()`, `refreshPayment()`, `withdraw()`, dan backend RPC memakai
  idempotency/lifecycle yang sesuai;
- `loadConsumerHome()`, `loadOrders()`, `loadMerchantData()`, dan
  `loadBalance()` menyegarkan snapshot terkait;
- `clearSessionState()` membatalkan subscription, menaikkan session epoch, dan
  menghapus data akun lama agar tidak bocor ke login berikutnya;
- `deleteAccount()` memanggil alur cleanup/anonymization backend.

Gunakan `appState.errorMessage`, loading flags, dan try/catch pada aksi lokal.
Jangan mempertahankan `BuildContext` melewati `await` tanpa memeriksa `mounted`.

## Auth dan routing

`AuthService` menangani Google/Apple OAuth dengan callback
`com.savebite://login-callback`. Sesi Supabase yang tersimpan dipulihkan dan
token kedaluwarsa direfresh sebelum bootstrap. Listener auth global
mendeduplikasi event startup, membersihkan state saat `signedOut`, dan
menampilkan retry bila startup gagal. Login lokal hanya ada pada build demo.

Startup menampilkan satu branded Flutter splash. Native Android/iOS launch
screen hanya menjadi transisi hitam tanpa artwork. Tiga indikator pager hanya
milik onboarding carousel saat pertama instalasi, bukan bagian dari splash.

Semua navigasi lintas fitur memakai `AppNav`. Signature yang sering dipakai:

- onboarding/account: `toOnboarding`, `toFork`, `toLogin`, `logout`,
  `deleteAccount`, `switchToMerchant`, `switchToConsumer`;
- root: `toConsumerHome`, `toMerchantHome`, `toStoreSetup`,
  `toLocationPriming`, `toOrders`;
- konsumen: `toDetail`, `toSearch`, `showFilter`, `toCheckout`,
  `toProcessing(bag:, qty:, method:)`, `toResumePayment(OrderRecord)`,
  `toVoucher(OrderRecord)`,
  `toRating(order:)`, `toNotifications`, `toEditProfile`, `toHelp`, dan
  `toLegal`;
- merchant: `toCreateBag`, `toEditBag`, `toOrderDetail`, `toEditStore`,
  `toScanQr`, `showWithdraw`, dan `toWithdrawSuccess`.

QR scanner tidak menerima `code` dari layar merchant. Token hanya boleh berasal
dari kamera yang benar-benar membaca QR milik konsumen.

Pindah tab di dalam shell:

- konsumen: `ConsumerShellScope.of(context)?.selectTab(i)` — Beranda, Peta,
  Pesanan, Favorit, Profil;
- merchant: `MerchantShellScope.of(context)?.selectTab(i)` — Dashboard, Bag,
  Pesanan, Saldo, Profil.

## Alur bisnis dan invariant

### Discovery dan lokasi

Koordinat pengguna digunakan untuk menghitung jarak, mengurutkan bag, dan
menentukan area peta. Pengguna boleh menolak GPS; UI harus menjelaskan dampaknya
dan menyediakan retry/Settings. Filter saat ini mencakup kategori, radius,
rentang harga, dan rentang waktu pickup. Peta memakai OpenStreetMap dengan
atribusi yang dapat dibuka.

### Checkout dan order

1. Validasi quantity dan stok di UI untuk feedback cepat.
2. RPC server menghitung harga/snapshot dan menahan stok secara atomik selama
   jendela bayar yang terpisah dari jendela pickup.
3. Edge Function membuat Snap memakai Server Key yang hanya berada di secret,
   lalu aplikasi membuka redirect HTTPS Midtrans di browser sistem.
4. Retry ambigu memakai idempotency key yang sama. Pembayaran tertunda dapat
   dilanjutkan setelah restart aplikasi tanpa membuat order baru.
5. Webhook diverifikasi dan hasilnya direkonsiliasi lewat Get Status. Hanya
   `settlement` atau `capture` dengan fraud `accept` yang menjadi paid.
6. Deep link `com.savebite://payment-callback/` dan query result tidak menjadi
   bukti lunas; keduanya hanya memicu refresh server.
7. Satu Snap order dapat memuat beberapa percobaan channel pembayaran. Status
   awal `deny`/`failure` dari satu percobaan hanya diagnostik dan effective state
   tetap `pending`; jangan melepas stok karena pengguna masih dapat mencoba
   channel lain pada Snap order yang sama.
8. Provider `cancel`/`expire` atau deadline pembayaran lokal bersifat terminal
   dan melepas reservation tepat satu kali. Status negatif setelah pembayaran
   terverifikasi tidak boleh menulis ulang histori paid secara diam-diam;
   refund, partial refund, dan chargeback masuk alur terminal/manual-review.
9. Merchant menandai order siap sebelum konsumen dapat meminta token pickup.
10. Token pickup acak boleh dirotasi, disimpan server sebagai hash, terikat
   order/window, dan hanya dapat diredeem satu kali.
11. Review hanya dapat dikirim pemilik order selesai, satu review per order.

### Merchant dan inventory

Form toko/bag memvalidasi input, schedule, harga, stok, dan gambar sebelum
submit. Status `active`, `sold_out`, dan `inactive` harus konsisten dengan
inventory. Mutasi yang bisa balapan menggunakan RPC database; jangan mengganti
pengurangan stok, mark-ready, atau redeem dengan update langsung dari klien.

### Saldo dan payout

Saldo berasal dari ledger transaksi tepercaya, bukan angka lokal. Redeem order
mencatat pendapatan bersih satu kali. Payout hanya dapat diajukan ke rekening
`verified`, minimum Rp50.000, biaya Rp2.500, dan dana langsung direservasi.
Transfer masih diproses manual; hanya worker/operator `service_role` yang boleh
memverifikasi rekening atau menyelesaikan payout. Rail payout tetap
dinonaktifkan sampai transfer keluar dan prosedur refund/chargeback operasional
tersedia; aktivasi pembayaran Midtrans inbound tidak otomatis mengaktifkannya.

### Privasi dan sesi

- Cache store Supabase harus dipisahkan berdasarkan UID.
- Logout/auth change wajib membatalkan stream dan membersihkan snapshot sesi.
- Raw token QR, hash token, idempotency key internal, nomor rekening penuh,
  provider recipient ID, dan key `service_role` tidak boleh muncul di view atau
  log klien. Nomor rekening penuh hanya boleh didekripsi oleh RPC `service_role`
  yang mewajibkan alasan dan menulis audit privat.
- Delete account memanggil fase prepare lebih dahulu, kemudian menghapus objek
  Storage pengguna, lalu menjalankan RPC final untuk menganonimkan record
  historis yang harus dipertahankan. Mutasi lain diblokir selama marker delete
  masih aktif agar retry tidak meninggalkan akun parsial.

## Pola layar

### A. Konten tab

Konten tab tidak membuat bottom navigation sendiri karena disediakan shell.
Biasanya mengembalikan `Column` dengan header dan `Expanded` scrollable. Contoh:
`HomeScreen`, `MapScreen`, `OrdersScreen`, `DashboardScreen`,
`IncomingOrdersScreen`, dan `BalanceScreen`.

### B. Layar penuh

Layar yang di-push mempunyai `Scaffold` sendiri. Untuk action bar bawah tetap,
gunakan `Column([header, Expanded(scrollable), SafeArea(bottomBar)])`. Contoh:
detail, search, checkout, voucher, rating, edit profil/toko, form bag, detail
order, scanner, bantuan, dan legal.

### C. Bottom sheet

`FilterSheet` dan `WithdrawSheet` dikembalikan melalui `showModalBottomSheet`
dari `AppNav`. Perhitungkan keyboard dengan `MediaQuery.viewInsets.bottom`,
gunakan `SheetHandle`, dan kembalikan nilai hanya setelah mutasi berhasil.

`ColoredHeader` dan `SimpleHeader` sudah menangani inset status bar. Untuk layar
manual, tambahkan safe-area sendiri. Uji layout minimal pada lebar 320/360/400,
text scale besar, keyboard terbuka, dan perangkat bernotch.

## Loading, error, dan realtime

- Gunakan loading/empty/error/success state yang berbeda; jangan menyamarkan
  kegagalan jaringan sebagai list kosong.
- Submit button dinonaktifkan saat request berjalan.
- Error backend dipetakan menjadi copy yang dapat ditindaklanjuti tanpa
  menampilkan detail internal SQL/Auth.
- Notification, incoming order, dan transaction stream menyegarkan snapshot
  terkait. Perubahan payout juga menghasilkan notifikasi, tetapi daftar payout
  dimuat melalui `loadBalance`; tetap sediakan pull/manual refresh sebagai jalur
  recovery.
- Hindari subscription ganda. Semua subscription dimiliki `AppState` dan
  dibatalkan saat sesi berubah.

## Asset, Storage, dan gambar

Fixture offline menggunakan `assets/images/`. Upload online masuk ke folder
`<auth.uid()>/...` pada bucket `avatars`, `store-logos`, atau `bag-images`.
Klien dan bucket membatasi gambar ke JPEG/PNG/WebP/HEIC/HEIF dan maksimal 2 MB.
Jangan menyimpan path file lokal permanen atau mengizinkan user memilih nama
object Storage milik pengguna lain.

## Quality gate perubahan

Setelah perubahan implementasi:

```bash
dart format lib test
flutter analyze
flutter test
flutter test --coverage
flutter build apk --debug
```

Tambahkan test FakeBackend/AppState untuk invariant bisnis dan widget test untuk
copy/status utama. Perubahan SQL harus diuji pada project Supabase disposable
dengan sedikitnya dua user per peran untuk memverifikasi isolasi RLS.

## Batas yang disengaja

- Payout provider otomatis ditunda; verifikasi dan transfer memakai operasi
  manual tepercaya.
- In-app realtime tersedia, tetapi background/terminated OS push memerlukan
  kredensial FCM/APNs dan worker eksternal.
- Naskah legal adalah draf produk dan memerlukan review hukum sebelum rilis.

Jangan menghilangkan disclosure tersebut dari UI atau dokumentasi sampai
integrasi eksternal masing-masing selesai dan telah diuji end-to-end.
