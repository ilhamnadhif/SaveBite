import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/main.dart';
import 'package:savebite/app_nav.dart';
import 'package:savebite/app_state.dart';
import 'package:savebite/theme/app_theme.dart';
import 'package:savebite/data/sample_data.dart';

import 'package:savebite/screens/consumer/map_screen.dart';
import 'package:savebite/screens/consumer/orders_screen.dart';
import 'package:savebite/screens/consumer/favorites_screen.dart';
import 'package:savebite/screens/consumer/profile_screen.dart';
import 'package:savebite/screens/consumer/notifications_screen.dart';
import 'package:savebite/screens/consumer/rating_screen.dart';
import 'package:savebite/screens/consumer/store_profile_screen.dart';
import 'package:savebite/screens/consumer/payment_failed_screen.dart';
import 'package:savebite/screens/consumer/voucher_screen.dart';
import 'package:savebite/screens/consumer/filter_sheet.dart';
import 'package:savebite/screens/consumer/detail_screen.dart';
import 'package:savebite/screens/consumer/checkout_screen.dart';
import 'package:savebite/screens/consumer/edit_profile_screen.dart';
import 'package:savebite/screens/consumer/search_screen.dart';
import 'package:savebite/screens/consumer/location_priming_screen.dart';
import 'package:savebite/screens/merchant/create_bag_screen.dart';
import 'package:savebite/screens/merchant/incoming_orders_screen.dart';
import 'package:savebite/screens/merchant/balance_screen.dart';
import 'package:savebite/screens/merchant/manage_bags_screen.dart';
import 'package:savebite/screens/merchant/merchant_profile_screen.dart';
import 'package:savebite/screens/merchant/scan_qr_screen.dart';
import 'package:savebite/screens/merchant/withdraw_sheet.dart';
import 'package:savebite/screens/merchant/edit_bag_screen.dart';
import 'package:savebite/screens/merchant/order_detail_screen.dart';
import 'package:savebite/screens/merchant/edit_store_screen.dart';
import 'package:savebite/screens/merchant/withdraw_success_screen.dart';
import 'package:savebite/screens/shared/help_screen.dart';

Future<void> _loadFonts() async {
  for (final entry in {
    'Bricolage': 'assets/fonts/BricolageGrotesque.ttf',
    'Jakarta': 'assets/fonts/PlusJakartaSans.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.theme, home: Scaffold(body: child));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  setUp(() async {
    appState.resetSession();
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1200, 2600); // ~400x866 @3x (phone)
    view.devicePixelRatio = 3.0;
    // Backend kini async (FakeBackend); muat cache dulu agar getter terisi.
    await appState.loadConsumerHome();
    await appState.loadOrders();
    await appState.loadFavorites();
    await appState.loadNotifications();
    await appState.loadStore();
    await appState.loadMerchantData();
    await appState.loadBalance();
  });
  tearDown(() {
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('Alur pembeli: splash → priming → … → voucher QR', (tester) async {
    await tester.pumpWidget(const SaveBiteApp());
    expect(find.text('SaveBite'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Lewati'), findsOneWidget);

    await tester.tap(find.text('Lewati'));
    await tester.pumpAndSettle();
    expect(find.text('Mau mulai dari mana?'), findsOneWidget);

    await tester.tap(find.text('Saya mau beli'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan dengan Google'));
    await tester.pumpAndSettle();

    // Priming lokasi (sekali) sebelum beranda.
    expect(find.text('Aktifkan lokasi'), findsOneWidget);
    await tester.tap(find.text('Izinkan akses lokasi'));
    await tester.pumpAndSettle();
    expect(find.text('Segera tutup'), findsOneWidget);

    await tester.tap(find.text('Surprise Bag Roti & Pastry').first);
    await tester.pumpAndSettle();
    // Sampai Detail. Lanjutan checkout → bayar → voucher diuji di test
    // 'Pembelian muncul…' (stack dangkal agar tap tombol andal).
    expect(find.text('Pesan sekarang'), findsOneWidget);
    expect(find.textContaining('Lihat toko'), findsOneWidget);
  });

  testWidgets('Alur merchant: fork jual → setup → dashboard → tab', (tester) async {
    await tester.pumpWidget(const SaveBiteApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lewati'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saya mau jual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan dengan Google'));
    await tester.pumpAndSettle();
    expect(find.text('Siapkan tokomu'), findsOneWidget);

    await tester.tap(find.text('Simpan & lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Buat Surprise Bag'), findsWidgets);

    await tester.tap(find.text('Saldo'));
    await tester.pumpAndSettle();
    expect(find.text('Saldo tersedia'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Beralih ke Mode Konsumen'), findsNothing);
    expect(find.text('Keluar'), findsOneWidget);
  });

  testWidgets('Pilih beli setelah sesi merchant tetap masuk konsumen',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.theme, navigatorKey: key, home: const Scaffold()));
    // Sesi pertama: pilih jual → masuk merchant (Setup Toko).
    await AppNav.completeLogin(key.currentContext!, merchant: true);
    await tester.pumpAndSettle();
    expect(find.text('Siapkan tokomu'), findsOneWidget);
    // lastMode kini 'merchant'. Sekarang pilih beli → HARUS masuk konsumen,
    // bukan merchant (pilihan Fork menang atas lastMode).
    await AppNav.completeLogin(key.currentContext!, merchant: false);
    await tester.pumpAndSettle();
    expect(find.text('Aktifkan lokasi'), findsOneWidget);
  });

  testWidgets('Tak ada tombol switch role di profil konsumen', (tester) async {
    await tester.pumpWidget(_host(const ProfileScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Beralih ke Mode Merchant'), findsNothing);
    expect(find.text('Keluar'), findsOneWidget);
  });

  testWidgets('Heart di Detail menoggle favorit', (tester) async {
    await tester.pumpWidget(_host(DetailScreen(bag: SampleData.bagRoti)));
    await tester.pumpAndSettle();
    final before = appState.isFavorite('m1'); // true secara default
    await tester.tap(
        find.byIcon(before ? Icons.favorite : Icons.favorite_border));
    await tester.pump();
    expect(appState.isFavorite('m1'), !before);
  });

  testWidgets('Kelola Bag: duplikat menambah bag aktif', (tester) async {
    await tester.pumpWidget(_host(const ManageBagsScreen()));
    await tester.pumpAndSettle();
    final before = appState.activeBags.length;
    await tester.tap(find.text('Duplikat besok').first);
    await tester.pump();
    expect(appState.activeBags.length, before + 1);
  });

  testWidgets('Buat Bag: publikasi menambah bag', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme, home: const CreateBagScreen()));
    await tester.pumpAndSettle();
    final before = appState.activeBags.length;
    await tester.tap(find.text('Publikasikan bag'));
    await tester.pumpAndSettle();
    expect(appState.activeBags.length, before + 1);
  });

  testWidgets('Tarik dana mengurangi saldo + layar berhasil', (tester) async {
    final before = appState.balance;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme, home: const Scaffold(body: BalanceScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarik dana'));
    await tester.pumpAndSettle();
    expect(find.text('Semua saldo'), findsOneWidget);
    await tester.tap(find.textContaining('Tarik Rp'));
    await tester.pumpAndSettle();
    expect(find.text('Penarikan diproses'), findsOneWidget);
    expect(appState.balance, lessThan(before));
  });

  testWidgets('Pembelian muncul di Pesanan Aktif (bag & kode benar)',
      (tester) async {
    final before = appState.activeOrders.length;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme, home: CheckoutScreen(bag: SampleData.bagKopi)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Bayar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    // Order tercipta dengan bag & kode yang benar…
    expect(appState.activeOrders.length, before + 1);
    expect(appState.activeOrders.first.bag.id, 'b2');
    expect(appState.activeOrders.first.code == 'SB-7K2Q9', isFalse);
    // …dan voucher sukses ditampilkan.
    expect(find.text('Pembayaran berhasil!'), findsOneWidget);
    // Lepas (Voucher punya Timer.periodic).
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump();
  });

  testWidgets('Scan QR by code redeem order yang dipilih', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme, home: const ScanQrScreen(code: 'SB-3M8X1')));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(appState.completedOrders.any((o) => o.code == 'SB-3M8X1'), isTrue);
    expect(appState.pendingOrders.any((o) => o.code == 'SB-7K2Q9'), isTrue);
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump();
  });

  testWidgets('Filter menampilkan jumlah hasil nyata', (tester) async {
    await tester.pumpWidget(_host(const SingleChildScrollView(child: FilterSheet())));
    await tester.pumpAndSettle();
    expect(find.textContaining('hasil'), findsOneWidget);
  });

  testWidgets('Profil merchant tak punya tujuan menu ganda', (tester) async {
    await tester.pumpWidget(_host(const MerchantProfileScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Jam operasional'), findsNothing);
    expect(find.text('Profil & jam toko'), findsOneWidget);
  });

  testWidgets('Edit profil menyimpan nama', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.theme, home: const EditProfileScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Budi Coba');
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pumpAndSettle();
    expect(appState.userName, 'Budi Coba');
  });

  testWidgets('Scan QR redeem memindah order ke Selesai', (tester) async {
    final before = appState.completedOrders.length;
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.theme, home: const ScanQrScreen()));
    await tester.pump(const Duration(seconds: 3)); // auto-simulate
    await tester.pump();
    expect(appState.completedOrders.length, before + 1);
    expect(find.text('Selesai'), findsWidgets);
    // Lepas untuk men-dispose AnimationController.
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump();
  });

  testWidgets('Notifikasi: tandai dibaca menghapus unread', (tester) async {
    expect(appState.unreadCount, greaterThan(0));
    await tester.pumpWidget(_host(const NotificationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tandai dibaca'));
    await tester.pumpAndSettle();
    expect(appState.unreadCount, 0);
  });

  testWidgets('Semua layar lama ter-build tanpa error', (tester) async {
    final screens = <String, Widget>{
      'Map': const MapScreen(),
      'Orders': const OrdersScreen(),
      'Favorites': const FavoritesScreen(),
      'Profile': const ProfileScreen(),
      'Notifications': const NotificationsScreen(),
      'Rating': RatingScreen(merchant: SampleData.kopiSenja, date: '14 Jun'),
      'StoreProfile': StoreProfileScreen(merchant: SampleData.rotiNyaman),
      'PaymentFailed':
          PaymentFailedScreen(bag: SampleData.bagRoti, method: 'OVO'),
      'Voucher': VoucherScreen(order: SampleData.activeOrders.first),
      'FilterSheet': const SingleChildScrollView(child: FilterSheet()),
      'WithdrawSheet': const SingleChildScrollView(child: WithdrawSheet()),
      'CreateBag': const CreateBagScreen(),
      'IncomingOrders': const IncomingOrdersScreen(),
      'Balance': const BalanceScreen(),
      'ManageBags': const ManageBagsScreen(),
      'MerchantProfile': const MerchantProfileScreen(),
    };
    for (final entry in screens.entries) {
      await tester.pumpWidget(_host(entry.value));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'Gagal build: ${entry.key}');
    }
    // Voucher punya Timer.periodic — lepas agar tidak menggantung.
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump();
  });

  testWidgets('Semua layar baru ter-build tanpa error', (tester) async {
    final screens = <String, Widget>{
      'EditProfile': const EditProfileScreen(),
      'Search': const SearchScreen(),
      'LocationPriming': const LocationPrimingScreen(),
      'Help': const HelpScreen(),
      'EditStore': const EditStoreScreen(),
      'WithdrawSuccess':
          const WithdrawSuccessScreen(amount: 1000000, bank: 'BCA · •6789'),
      'EditBag': EditBagScreen(bag: SampleData.merchantActiveBags.first),
      'OrderDetail': OrderDetailScreen(order: SampleData.incomingOrders.first),
    };
    for (final entry in screens.entries) {
      await tester.pumpWidget(_host(entry.value));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'Gagal build: ${entry.key}');
    }
  });
}
