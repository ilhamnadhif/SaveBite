# SaveBite — Panduan Implementasi Layar (Flutter)

Dokumen kontrak untuk membangun tiap layar agar konsisten. Sumber kebenaran
desain: `.design/desain-aplikasi-savebite/project/SaveBite.dc.html`.

## Aturan umum
- Setiap file layar: `import 'package:flutter/material.dart';`, `import '../../sb.dart';`,
  dan kalau perlu navigasi `import '../../app_nav.dart';`.
- **Cocokkan warna, ukuran, radius, dan copy (Bahasa Indonesia) PERSIS** dengan HTML.
  Jangan mengarang teks baru. Angka & label harus sama.
- Pakai komponen foundation (lihat di bawah) sebelum bikin manual.
- Jangan render foto sebagai placeholder garis — pakai `FoodImage(path)` dengan
  aset nyata. Mapping foto ada di `SampleData` (`SampleData.img1`..`img8`).
- Tidak ada emoji. Ikon pakai Material Icons (mendekati ikon SVG di desain).
- Jangan jalankan perintah flutter. Hanya tulis file Dart yang diminta.

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

## Data — `SampleData.*` (lib/data/sample_data.dart)
Merchant: `rotiNyaman, kopiSenja, donatManis, tokoSehat`.
Bag: `bagRoti, bagKopi, bagDonat`. List: `nearbyBags, favorites, activeOrders,
orderHistory, notifications, merchantActiveBags, merchantInactiveBags,
incomingOrders, transactions`.
Helper: `formatRupiah(int)` → "Rp15.000". `bag.discountPercent`, `bag.savings`.

## State — `appState` (lib/app_state.dart)
`appState.mode` (AppMode.consumer/merchant), `appState.location`,
`appState.hasNearbyBags`, `appState.merchantSetupDone`,
`appState.isFavorite(id)`, `appState.toggleFavorite(id)`, `setLocation`,
`switchToMerchant`, `switchToConsumer`. Bungkus widget reaktif dengan
`ListenableBuilder(listenable: appState, builder: ...)` bila perlu.

## Navigasi — `AppNav.*` (lib/app_nav.dart) — PAKAI INI untuk berpindah layar
- `AppNav.toOnboarding(c)` / `toFork(c)` / `toLogin(c, merchant: bool)`
- `AppNav.toConsumerHome(c)` (replace) / `toMerchantHome(c)` (replace)
- `AppNav.toStoreSetup(c)`
- `AppNav.toDetail(c, Bag bag)`
- `AppNav.showFilter(c)` (bottom sheet)
- `AppNav.toCheckout(c, Bag bag)`
- `AppNav.toProcessing(c, bag: Bag, willFail: bool, method: String)`
- `AppNav.toVoucher(c, bag: Bag, code: String)` (replace processing)
- `AppNav.toPaymentFailed(c, bag: Bag, method: String)` (replace processing)
- `AppNav.toStoreProfile(c, Merchant m)`
- `AppNav.toRating(c, merchant: Merchant, date: String)`
- `AppNav.toNotifications(c)`
- `AppNav.toCreateBag(c)`
- `AppNav.toScanQr(c)`
- `AppNav.showWithdraw(c)` (bottom sheet)
- `AppNav.switchToMerchant(c)` (atur appState + ke setup/dashboard)
- `AppNav.switchToConsumer(c)` (atur appState + ke beranda)

## Pindah tab di dalam shell
- Konsumen: `ConsumerShellScope.of(context)?.selectTab(i)` — 0 Beranda,1 Peta,2 Pesanan,3 Favorit,4 Profil.
- Merchant: `MerchantShellScope.of(context)?.selectTab(i)` — 0 Dashboard,1 Bag,2 Pesanan,3 Saldo,4 Profil.

## Dua pola layar
### A. Konten tab (TANPA Scaffold/bottom nav — shell yang menyediakannya)
Kembalikan `Column` berisi header + `Expanded(child: scrollable)`. Header pakai
`ColoredHeader`/`SimpleHeader` (sudah menangani inset status bar). Contoh nyata:
`lib/screens/consumer/home_screen.dart`.
Layar konten-tab: HomeScreen, MapScreen, OrdersScreen, FavoritesScreen,
ProfileScreen, DashboardScreen, ManageBagsScreen, IncomingOrdersScreen,
BalanceScreen, MerchantProfileScreen.

### B. Layar penuh (punya Scaffold sendiri) — di-push lewat Navigator
`Scaffold(backgroundColor: AppColors.cream, body: Column(...))`. Untuk konten
yang bisa scroll + bar bawah tetap, susun `Column([header, Expanded(ListView), bottomBar])`.
Tangani inset bawah dengan `SafeArea` atau padding. Contoh nyata:
`lib/screens/consumer/detail_screen.dart`.
Layar penuh: Splash, Onboarding, Fork, Login, Detail, Checkout, Processing,
PaymentFailed, Voucher, Rating, StoreProfile, Notifications, StoreSetup,
CreateBag, ScanQr.

### C. Bottom sheet — widget isi sheet (FilterSheet, WithdrawSheet)
Kembalikan kontainer dengan `SheetHandle()` di atas. Ditampilkan via AppNav.
Contoh: `lib/screens/consumer/filter_sheet.dart`.

## Status bar padding
`ColoredHeader`/`SimpleHeader` sudah menambah `MediaQuery.padding.top`. Untuk
layar penuh berlatar penuh yang headernya manual, tambahkan sendiri
`MediaQuery.of(context).padding.top` agar konten tidak ketutup notch
(desain pakai padding-top ~58px = status bar + ~16).
