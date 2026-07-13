import 'package:flutter/material.dart';
import 'app_state.dart';
import 'data/backend/backend.dart';
import 'data/models.dart';
import 'services/auth_service.dart';

import 'screens/onboarding/onboarding_screen.dart';
import 'screens/onboarding/fork_screen.dart';
import 'screens/onboarding/login_screen.dart';
import 'screens/consumer/consumer_shell.dart';
import 'screens/consumer/detail_screen.dart';
import 'screens/consumer/filter_sheet.dart';
import 'screens/consumer/checkout_screen.dart';
import 'screens/consumer/processing_screen.dart';
import 'screens/consumer/payment_failed_screen.dart';
import 'screens/consumer/voucher_screen.dart';
import 'screens/consumer/rating_screen.dart';
import 'screens/consumer/store_profile_screen.dart';
import 'screens/consumer/notifications_screen.dart';
import 'screens/consumer/edit_profile_screen.dart';
import 'screens/consumer/search_screen.dart';
import 'screens/consumer/location_priming_screen.dart';
import 'screens/merchant/merchant_shell.dart';
import 'screens/merchant/store_setup_screen.dart';
import 'screens/merchant/create_bag_screen.dart';
import 'screens/merchant/edit_bag_screen.dart';
import 'screens/merchant/order_detail_screen.dart';
import 'screens/merchant/scan_qr_screen.dart';
import 'screens/merchant/withdraw_sheet.dart';
import 'screens/merchant/withdraw_success_screen.dart';
import 'screens/merchant/edit_store_screen.dart';
import 'screens/merchant/merchant_reviews_screen.dart';
import 'screens/shared/help_screen.dart';
import 'screens/shared/legal_screen.dart';

/// Pusat navigasi SaveBite. Semua perpindahan layar lewat sini.
class AppNav {
  AppNav._();

  static Future<T?> _push<T>(BuildContext c, Widget page) =>
      Navigator.of(c).push<T>(MaterialPageRoute(builder: (_) => page));

  static void _replace(BuildContext c, Widget page) =>
      Navigator.of(c).pushReplacement(MaterialPageRoute(builder: (_) => page));

  static void _root(BuildContext c, Widget page) => Navigator.of(
    c,
  ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), (r) => false);

  // ── Onboarding & akun ──
  static void toOnboarding(BuildContext c) =>
      _replace(c, const OnboardingScreen());
  static void toFork(BuildContext c) => _push(c, const ForkScreen());
  static void toForkRoot(BuildContext c) => _root(c, const ForkScreen());
  static void toLogin(BuildContext c, {required bool merchant}) =>
      _push(c, LoginScreen(merchant: merchant));

  /// Dipanggil dari LoginScreen untuk mode offline (Supabase tak dikonfigurasi):
  /// langsung bootstrap data (fake) lalu arahkan. Saat online, routing dipicu
  /// oleh listener auth (lihat main.dart) -> [handleSignedIn].
  static Future<void> completeLogin(
    BuildContext c, {
    required bool merchant,
  }) async {
    await appState.setPendingMerchantIntent(merchant);
    if (!c.mounted) return;
    await handleSignedIn(c);
  }

  /// Sesudah sesi aktif: muat profil/toko lalu arahkan ke ekosistem yang tepat.
  static Future<void> handleSignedIn(BuildContext c) async {
    try {
      await appState.bootstrap();
      if (!c.mounted) return;
      routeAfterLogin(c);
    } catch (_) {
      if (!c.mounted) return;
      _root(
        c,
        _StartupErrorScreen(
          message:
              appState.errorMessage ??
              'Data akun belum dapat dimuat. Periksa koneksi lalu coba lagi.',
        ),
      );
    }
  }

  static void routeAfterLogin(BuildContext c) {
    // Pilihan eksplisit dari Fork (true/false) menang; jika null pakai lastMode.
    final wantMerchant =
        appState.consumePendingMerchantIntent() ??
        (appState.lastMode == 'merchant');
    if (wantMerchant) {
      appState.switchToMerchant();
      appState.rememberMode('merchant');
      if (appState.merchantSetupDone) {
        toMerchantHome(c);
      } else {
        _root(c, const StoreSetupScreen());
      }
    } else {
      appState.switchToConsumer();
      appState.rememberMode('consumer');
      if (!appState.locationPrimed) {
        _root(c, const LocationPrimingScreen());
      } else {
        toConsumerHome(c);
      }
    }
  }

  static Future<void> logout(BuildContext c) async {
    await AuthService.signOut();
    await appState.clearSessionState();
    if (c.mounted) _root(c, const ForkScreen());
  }

  static Future<void> switchToMerchant(BuildContext c) async {
    appState.switchToMerchant();
    appState.rememberMode('merchant');
    appState.clearError();
    await appState.loadStore();
    final error = appState.errorMessage;
    if (error != null) {
      appState.switchToConsumer();
      appState.rememberMode('consumer');
      throw BackendException('store_load_failed', error);
    }
    if (!c.mounted) return;
    appState.merchantSetupDone
        ? toMerchantHome(c)
        : _root(c, const StoreSetupScreen());
  }

  static void switchToConsumer(BuildContext c) {
    appState.switchToConsumer();
    appState.rememberMode('consumer');
    appState.locationPrimed
        ? toConsumerHome(c)
        : _root(c, const LocationPrimingScreen());
  }

  static Future<void> deleteAccount(BuildContext c) async {
    await appState.deleteAccount();
    try {
      // Akun server sudah terhapus. Kegagalan membersihkan sesi lokal tidak
      // boleh dilaporkan sebagai kegagalan penghapusan data.
      await AuthService.signOut();
    } catch (_) {}
    if (c.mounted) _root(c, const ForkScreen());
  }

  // ── Root ekosistem ──
  static void toConsumerHome(BuildContext c) => _root(c, const ConsumerShell());
  static void toMerchantHome(BuildContext c) => _root(c, const MerchantShell());
  static void toMerchantOrders(BuildContext c) =>
      _root(c, const MerchantShell(initialIndex: 2));
  static void toMerchantBalance(BuildContext c) =>
      _root(c, const MerchantShell(initialIndex: 3));
  static void toStoreSetup(BuildContext c) =>
      _push(c, const StoreSetupScreen());
  static void toLocationPriming(BuildContext c) =>
      _root(c, const LocationPrimingScreen());
  static void toOrders(BuildContext c) =>
      _root(c, const ConsumerShell(initialIndex: 2));

  // ── Konsumen ──
  static void toDetail(BuildContext c, Bag bag) =>
      _push(c, DetailScreen(bag: bag));

  static void toSearch(BuildContext c) => _push(c, const SearchScreen());

  /// Buka filter; mengembalikan set kategori terpilih (atau null bila batal).
  static Future<BagFilter?> showFilter(BuildContext c) =>
      showModalBottomSheet<BagFilter>(
        context: c,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x8C0F231C),
        builder: (_) => const FilterSheet(),
      );

  static void toCheckout(BuildContext c, Bag bag) =>
      _push(c, CheckoutScreen(bag: bag));

  static void toProcessing(
    BuildContext c, {
    required Bag bag,
    required int qty,
    required String method,
  }) => _push(c, ProcessingScreen(bag: bag, qty: qty, method: method));

  static void toVoucher(
    BuildContext c,
    OrderRecord order, {
    bool replace = false,
  }) {
    final page = VoucherScreen(order: order);
    replace ? _replace(c, page) : _push(c, page);
  }

  static void toPaymentFailed(
    BuildContext c, {
    required Bag bag,
    required String method,
  }) => _replace(c, PaymentFailedScreen(bag: bag, method: method));

  static void toStoreProfile(BuildContext c, Merchant m) =>
      _push(c, StoreProfileScreen(merchant: m));

  static void toRating(BuildContext c, {required OrderRecord order}) =>
      _push(c, RatingScreen(order: order));

  static void toNotifications(BuildContext c) =>
      _push(c, const NotificationsScreen());

  static void toEditProfile(BuildContext c) =>
      _push(c, const EditProfileScreen());
  static void toHelp(BuildContext c) => _push(c, const HelpScreen());
  static void toLegal(BuildContext c, {required LegalDocument document}) =>
      _push(c, LegalScreen(document: document));

  static void openNotification(BuildContext c, AppNotification notification) {
    final route = (notification.route ?? '').toLowerCase();
    if (route == 'merchant_orders') {
      appState.switchToMerchant();
      appState.rememberMode('merchant');
      toMerchantOrders(c);
    } else if (route == 'merchant_balance') {
      appState.switchToMerchant();
      appState.rememberMode('merchant');
      toMerchantBalance(c);
    } else if (route == 'merchant_reviews') {
      appState.switchToMerchant();
      appState.rememberMode('merchant');
      toMerchantReviews(c, root: true);
    } else if (route == 'orders' || route.startsWith('order:')) {
      appState.switchToConsumer();
      appState.rememberMode('consumer');
      toOrders(c);
    } else if (route == 'consumer_home' || route == 'home') {
      appState.switchToConsumer();
      appState.rememberMode('consumer');
      toConsumerHome(c);
    }
  }

  // ── Merchant ──
  static void toCreateBag(BuildContext c) => _push(c, const CreateBagScreen());
  static void toEditBag(BuildContext c, MerchantBag bag) =>
      _push(c, EditBagScreen(bag: bag));
  static void toOrderDetail(BuildContext c, IncomingOrder order) =>
      _push(c, OrderDetailScreen(order: order));
  static void toEditStore(BuildContext c) => _push(c, const EditStoreScreen());
  static void toMerchantReviews(BuildContext c, {bool root = false}) {
    final page = MerchantReviewsScreen(rootEntry: root);
    root ? _root(c, page) : _push(c, page);
  }

  /// Buka scanner QR pickup. Token selalu berasal dari hasil kamera dan tidak
  /// pernah dipasok dari kode/hint yang terlihat di layar merchant.
  static Future<bool?> toScanQr(BuildContext c) =>
      _push<bool>(c, const ScanQrScreen());

  /// Buka sheet tarik dana; mengembalikan jumlah yang ditarik (atau null).
  static Future<int?> showWithdraw(BuildContext c) => showModalBottomSheet<int>(
    context: c,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C0F231C),
    builder: (_) => const WithdrawSheet(),
  );

  static void toWithdrawSuccess(
    BuildContext c, {
    required PayoutRequest request,
  }) => _push(c, WithdrawSuccessScreen(request: request));
}

class _StartupErrorScreen extends StatefulWidget {
  final String message;

  const _StartupErrorScreen({required this.message});

  @override
  State<_StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<_StartupErrorScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await AppNav.handleSignedIn(context);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF1),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 58,
                  color: Color(0xFF1B5E43),
                ),
                const SizedBox(height: 20),
                Text(
                  'SaveBite belum dapat dibuka',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _retry,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_busy ? 'Mencoba lagi…' : 'Coba lagi'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => AppNav.logout(context),
                  child: const Text('Keluar dari akun'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
