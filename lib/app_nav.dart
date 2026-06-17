import 'package:flutter/material.dart';
import 'app_state.dart';
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
import 'screens/shared/help_screen.dart';

/// Pusat navigasi SaveBite. Semua perpindahan layar lewat sini.
class AppNav {
  AppNav._();

  static Future<T?> _push<T>(BuildContext c, Widget page) =>
      Navigator.of(c).push<T>(MaterialPageRoute(builder: (_) => page));

  static void _replace(BuildContext c, Widget page) =>
      Navigator.of(c).pushReplacement(MaterialPageRoute(builder: (_) => page));

  static void _root(BuildContext c, Widget page) => Navigator.of(c)
      .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => page), (r) => false);

  // ── Onboarding & akun ──
  static void toOnboarding(BuildContext c) => _replace(c, const OnboardingScreen());
  static void toFork(BuildContext c) => _push(c, const ForkScreen());
  static void toForkRoot(BuildContext c) => _root(c, const ForkScreen());
  static void toLogin(BuildContext c, {required bool merchant}) =>
      _push(c, LoginScreen(merchant: merchant));

  /// Dipanggil dari LoginScreen untuk mode offline (Supabase tak dikonfigurasi):
  /// langsung bootstrap data (fake) lalu arahkan. Saat online, routing dipicu
  /// oleh listener auth (lihat main.dart) -> [handleSignedIn].
  static Future<void> completeLogin(BuildContext c, {required bool merchant}) async {
    appState.pendingMerchantIntent = merchant;
    await handleSignedIn(c);
  }

  /// Sesudah sesi aktif: muat profil/toko lalu arahkan ke ekosistem yang tepat.
  static Future<void> handleSignedIn(BuildContext c) async {
    await appState.bootstrap();
    if (!c.mounted) return;
    routeAfterLogin(c);
  }

  static void routeAfterLogin(BuildContext c) {
    // Pilihan eksplisit dari Fork (true/false) menang; jika null pakai lastMode.
    final wantMerchant =
        appState.pendingMerchantIntent ?? (appState.lastMode == 'merchant');
    appState.pendingMerchantIntent = null;
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
    appState.switchToConsumer();
    if (c.mounted) _root(c, const ForkScreen());
  }

  // ── Root ekosistem ──
  static void toConsumerHome(BuildContext c) => _root(c, const ConsumerShell());
  static void toMerchantHome(BuildContext c) => _root(c, const MerchantShell());
  static void toStoreSetup(BuildContext c) => _push(c, const StoreSetupScreen());
  static void toLocationPriming(BuildContext c) =>
      _root(c, const LocationPrimingScreen());
  static void toOrders(BuildContext c) =>
      _root(c, const ConsumerShell(initialIndex: 2));

  // ── Konsumen ──
  static void toDetail(BuildContext c, Bag bag) =>
      _push(c, DetailScreen(bag: bag));

  static void toSearch(BuildContext c) => _push(c, const SearchScreen());

  /// Buka filter; mengembalikan set kategori terpilih (atau null bila batal).
  static Future<Set<String>?> showFilter(BuildContext c) =>
      showModalBottomSheet<Set<String>>(
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
    required bool willFail,
    required String method,
  }) =>
      _push(c,
          ProcessingScreen(bag: bag, qty: qty, willFail: willFail, method: method));

  static void toVoucher(BuildContext c, OrderRecord order,
      {bool replace = false}) {
    final page = VoucherScreen(order: order);
    replace ? _replace(c, page) : _push(c, page);
  }

  static void toPaymentFailed(
    BuildContext c, {
    required Bag bag,
    required String method,
  }) =>
      _replace(c, PaymentFailedScreen(bag: bag, method: method));

  static void toStoreProfile(BuildContext c, Merchant m) =>
      _push(c, StoreProfileScreen(merchant: m));

  static void toRating(BuildContext c,
          {required Merchant merchant, required String date}) =>
      _push(c, RatingScreen(merchant: merchant, date: date));

  static void toNotifications(BuildContext c) =>
      _push(c, const NotificationsScreen());

  static void toEditProfile(BuildContext c) =>
      _push(c, const EditProfileScreen());
  static void toHelp(BuildContext c) => _push(c, const HelpScreen());

  // ── Merchant ──
  static void toCreateBag(BuildContext c) => _push(c, const CreateBagScreen());
  static void toEditBag(BuildContext c, MerchantBag bag) =>
      _push(c, EditBagScreen(bag: bag));
  static void toOrderDetail(BuildContext c, IncomingOrder order) =>
      _push(c, OrderDetailScreen(order: order));
  static void toEditStore(BuildContext c) => _push(c, const EditStoreScreen());

  /// Buka scanner; opsional [code] order yang akan di-redeem. Mengembalikan
  /// true jika order berhasil di-redeem.
  static Future<bool?> toScanQr(BuildContext c, {String? code}) =>
      _push<bool>(c, ScanQrScreen(code: code));

  /// Buka sheet tarik dana; mengembalikan jumlah yang ditarik (atau null).
  static Future<int?> showWithdraw(BuildContext c) => showModalBottomSheet<int>(
        context: c,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: const Color(0x8C0F231C),
        builder: (_) => const WithdrawSheet(),
      );

  static void toWithdrawSuccess(BuildContext c,
          {required int amount, required String bank}) =>
      _push(c, WithdrawSuccessScreen(amount: amount, bank: bank));
}
