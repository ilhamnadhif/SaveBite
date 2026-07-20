import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_nav.dart';
import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/backend.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/data/sample_data.dart';
import 'package:savebite/screens/consumer/checkout_screen.dart';
import 'package:savebite/screens/consumer/processing_screen.dart';
import 'package:savebite/screens/consumer/store_profile_screen.dart';
import 'package:savebite/screens/consumer/voucher_screen.dart';
import 'package:savebite/screens/onboarding/fork_screen.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;
import 'package:savebite/theme/app_theme.dart';

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

class _FlakyMerchantBagsBackend extends FakeBackend {
  int calls = 0;

  @override
  Future<List<Bag>> bagsByMerchant(String merchantId) async {
    calls++;
    if (calls == 1) {
      throw const BackendException(
        'merchant_bags_unavailable',
        'Bag toko sedang tidak dapat dimuat.',
      );
    }
    return super.bagsByMerchant(merchantId);
  }
}

class _UnrelatedRoute extends StatelessWidget {
  const _UnrelatedRoute();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('start-processing'),
          onPressed: () => AppNav.toProcessing(
            context,
            bag: SampleData.bagRoti,
            qty: 1,
            method: 'GoPay',
          ),
          child: const Text('Rute perantara'),
        ),
      ),
    );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appState.resetSession();
    AppNav.resetAuthRoutingForTest();
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1200, 2700);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    app_backend.useFakeBackend();
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'Back dari voucher tidak kembali ke checkout yang sudah membuat order',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open-checkout'),
                  onPressed: () =>
                      AppNav.toCheckout(context, SampleData.bagRoti),
                  child: const Text('Buka checkout'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-checkout')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsOneWidget);

      await tester.tap(find.textContaining('Lanjutkan ·'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ProcessingScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(VoucherScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Buka checkout'), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(appState.activeOrders, hasLength(1));
    },
  );

  testWidgets('pembersihan checkout tidak menghapus rute yang tidak terkait', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-checkout'),
                onPressed: () => AppNav.toCheckout(context, SampleData.bagRoti),
                child: const Text('Buka checkout'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-checkout')));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const _UnrelatedRoute()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start-processing')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(VoucherScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(_UnrelatedRoute), findsOneWidget);
    expect(find.text('Rute perantara'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Buka checkout'), findsOneWidget);
    expect(find.byType(CheckoutScreen), findsNothing);
  });

  testWidgets('logout dan event signedOut hanya mengganti root satu kali', (
    tester,
  ) async {
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  unawaited(AppNav.logout(context));
                  unawaited(AppNav.handleSignedOut(context));
                },
                child: const Text('Keluar'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(find.byType(ForkScreen), findsOneWidget);
    expect(observer.pushCount, 2);
  });

  testWidgets('profil toko menampilkan error lokal dan dapat mencoba lagi', (
    tester,
  ) async {
    final backend = _FlakyMerchantBagsBackend();
    app_backend.backend = backend;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const StoreProfileScreen(merchant: SampleData.rotiNyaman),
      ),
    );
    await tester.pump();

    expect(find.text('Bag toko sedang tidak dapat dimuat.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Coba lagi'));
    await tester.pump();
    await tester.pump();

    expect(backend.calls, 2);
    expect(find.text(SampleData.bagRoti.title), findsOneWidget);
    expect(find.text('Bag toko sedang tidak dapat dimuat.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
