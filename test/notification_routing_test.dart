import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_nav.dart';
import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/mappers.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/screens/consumer/consumer_shell.dart';
import 'package:savebite/screens/consumer/orders_screen.dart';
import 'package:savebite/screens/merchant/incoming_orders_screen.dart';
import 'package:savebite/screens/merchant/merchant_shell.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;
import 'package:savebite/services/notification_route.dart';
import 'package:savebite/theme/app_theme.dart';
import 'package:savebite/widgets/common.dart';

AppNotification _remoteNotification({
  required String id,
  required String title,
  required String dedupeKey,
  Map<String, dynamic> data = const {},
}) => notificationFromMap({
  'id': id,
  'entity_type': 'order',
  'title': title,
  'body': 'Uji route notifikasi',
  'type': 'payment',
  'group_label': 'Hari ini',
  'read': false,
  'dedupe_key': dedupeKey,
  'data': data,
  'created_at': DateTime.now().toIso8601String(),
});

class _RealtimeNotificationBackend extends FakeBackend {
  final notificationController =
      StreamController<List<AppNotification>>.broadcast();
  int incomingOrdersCalls = 0;

  @override
  Future<StoreProfile?> myStore() async => const StoreProfile(
    id: 'store-route-test',
    name: 'Toko Route Test',
    category: 'Bakery',
    address: 'Depok',
    openTime: '08.00',
    closeTime: '20.00',
  );

  @override
  Stream<List<AppNotification>> watchNotifications() =>
      notificationController.stream;

  @override
  Future<List<IncomingOrder>> incomingOrders() {
    incomingOrdersCalls++;
    return super.incomingOrders();
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
    appState.resetSession();
    app_backend.useFakeBackend();
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  test('route order membedakan status aktif dan terminal', () {
    for (final status in [
      'redeemed',
      'refunded',
      'cancelled',
      'expired',
      'failed',
      'payment-review',
    ]) {
      final target = parseConsumerOrderNotificationRoute(
        'order:order-42:$status',
      );
      expect(target?.orderId, 'order-42');
      expect(target?.preferredTab, ConsumerOrdersTab.history);
    }

    for (final status in ['paid', 'ready', 'pending']) {
      expect(
        parseConsumerOrderNotificationRoute(
          'order:order-42:$status',
        )?.preferredTab,
        ConsumerOrdersTab.active,
      );
    }

    expect(
      parseConsumerOrderNotificationRoute('order:order-42')?.preferredTab,
      isNull,
    );
    expect(parseConsumerOrderNotificationRoute('order::refunded'), isNull);
    expect(
      parseConsumerOrderNotificationRoute('merchant-order:order-42:new'),
      isNull,
    );
  });

  test('route merchant dan matcher realtime mengenali new/payment-review', () {
    final active = parseMerchantOrderNotificationRoute(
      'merchant-order:order-42:new',
    );
    expect(active?.orderId, 'order-42');
    expect(active?.preferredTab, MerchantOrdersTab.active);

    final review = parseMerchantOrderNotificationRoute(
      'merchant-order:order-42:payment-review',
    );
    expect(review?.orderId, 'order-42');
    expect(review?.preferredTab, MerchantOrdersTab.closed);

    expect(isMerchantOrdersNotificationRoute('merchant_orders'), isTrue);
    expect(
      isMerchantOrdersNotificationRoute('merchant-order:order-42:new'),
      isTrue,
    );
    expect(
      isMerchantOrdersNotificationRoute(
        'merchant-order:order-42:payment-review',
      ),
      isTrue,
    );
    expect(isMerchantOrdersNotificationRoute('merchant-order::new'), isFalse);
    expect(isMerchantOrdersNotificationRoute('order:order-42:paid'), isFalse);
  });

  test('mapper hanya mengambil route pesanan yang di-whitelist', () {
    expect(
      _remoteNotification(
        id: 'refund',
        title: 'Pembayaran dikembalikan',
        dedupeKey: 'order:order-4:refunded',
      ).route,
      'order:order-4:refunded',
    );
    expect(
      _remoteNotification(
        id: 'merchant-new',
        title: 'Pesanan baru sudah dibayar',
        dedupeKey: 'merchant-order:order-5:new',
      ).route,
      'merchant-order:order-5:new',
    );
    expect(
      _remoteNotification(
        id: 'merchant-review',
        title: 'Saldo pesanan ditahan',
        dedupeKey: 'merchant-order:order-7:payment-review',
      ).route,
      'merchant-order:order-7:payment-review',
    );

    final fromData = notificationFromMap({
      'id': 'data-route',
      'title': 'Pembayaran dikembalikan',
      'data': {'route': 'order:order-8:refunded'},
      'dedupe_key': 'arbitrary:must-not-open',
    });
    expect(fromData.route, 'order:order-8:refunded');

    final unsafe = notificationFromMap({
      'id': 'unsafe',
      'title': 'Tidak dikenal',
      'dedupe_key': 'merchant_balance:arbitrary-command',
    });
    expect(unsafe.route, isNull);
  });

  testWidgets('notifikasi terminal membuka Riwayat dan memprioritaskan order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => AppNav.openNotification(
                  context,
                  _remoteNotification(
                    id: 'notification-terminal',
                    title: 'Pembayaran dikembalikan',
                    dedupeKey: 'order:order-4:refunded',
                  ),
                ),
                child: const Text('Buka notifikasi'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka notifikasi'));
    await tester.pumpAndSettle();

    final shell = tester.widget<ConsumerShell>(find.byType(ConsumerShell));
    expect(shell.initialIndex, 2);
    expect(shell.initialOrdersTab, ConsumerOrdersTab.history);
    expect(shell.referencedOrderId, 'order-4');

    final tabs = tester.widget<TabSwitch>(find.byType(TabSwitch));
    expect(tabs.index, ConsumerOrdersTab.history.index);
    expect(find.byKey(const ValueKey('history-order-order-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('active-order-order-1')), findsNothing);

    final targetTop = tester.getTopLeft(
      find.byKey(const ValueKey('history-order-order-4')),
    );
    final formerFirstTop = tester.getTopLeft(
      find.byKey(const ValueKey('history-order-order-2')),
    );
    expect(targetTop.dy, lessThan(formerFirstTop.dy));
  });

  testWidgets(
    'data terbaru mengalahkan suffix notifikasi aktif yang sudah basi',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: const Scaffold(
            body: OrdersScreen(
              initialTab: ConsumerOrdersTab.active,
              referencedOrderId: 'order-4',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final tabs = tester.widget<TabSwitch>(find.byType(TabSwitch));
      expect(tabs.index, ConsumerOrdersTab.history.index);
      expect(
        find.byKey(const ValueKey('history-order-order-4')),
        findsOneWidget,
      );
      expect(find.text('Belum ada pesanan aktif'), findsNothing);
    },
  );

  testWidgets(
    'notifikasi remote merchant new membuka order aktif yang dirujuk',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => AppNav.openNotification(
                    context,
                    _remoteNotification(
                      id: 'notification-merchant-new',
                      title: 'Pesanan baru sudah dibayar',
                      dedupeKey: 'merchant-order:order-5:new',
                    ),
                  ),
                  child: const Text('Buka merchant new'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka merchant new'));
      await tester.pumpAndSettle();

      final shell = tester.widget<MerchantShell>(find.byType(MerchantShell));
      expect(shell.initialIndex, 2);
      expect(shell.initialOrdersTab, MerchantOrdersTab.active);
      expect(shell.referencedOrderId, 'order-5');
      expect(
        find.byKey(const ValueKey('merchant-active-order-order-5')),
        findsOneWidget,
      );
    },
  );

  testWidgets('notifikasi remote merchant payment-review membuka tab Ditutup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => AppNav.openNotification(
                  context,
                  _remoteNotification(
                    id: 'notification-merchant-review',
                    title: 'Saldo pesanan ditahan',
                    dedupeKey: 'merchant-order:order-review:payment-review',
                  ),
                ),
                child: const Text('Buka payment review'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka payment review'));
    await tester.pumpAndSettle();

    final shell = tester.widget<MerchantShell>(find.byType(MerchantShell));
    expect(shell.initialIndex, 2);
    expect(shell.initialOrdersTab, MerchantOrdersTab.closed);
    expect(shell.referencedOrderId, 'order-review');

    final tabs = tester.widget<TabSwitch>(
      find.descendant(
        of: find.byType(IncomingOrdersScreen),
        matching: find.byType(TabSwitch),
      ),
    );
    expect(tabs.index, MerchantOrdersTab.closed.index);
    expect(find.text('Belum ada pesanan ditutup'), findsOneWidget);
  });

  test('realtime merchant-order memuat ulang data merchant', () async {
    final backend = _RealtimeNotificationBackend();
    app_backend.backend = backend;
    final state = AppState();
    await state.bootstrap();
    expect(state.merchantSetupDone, isTrue);
    expect(backend.incomingOrdersCalls, 0);

    backend.notificationController.add([
      _remoteNotification(
        id: 'realtime-new',
        title: 'Pesanan baru sudah dibayar',
        dedupeKey: 'merchant-order:order-5:new',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(backend.incomingOrdersCalls, 1);

    backend.notificationController.add([
      _remoteNotification(
        id: 'realtime-new',
        title: 'Pesanan baru sudah dibayar',
        dedupeKey: 'merchant-order:order-5:new',
      ),
      _remoteNotification(
        id: 'realtime-review',
        title: 'Saldo pesanan ditahan',
        dedupeKey: 'merchant-order:order-7:payment-review',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(backend.incomingOrdersCalls, 2);

    await state.clearSessionState(notify: false);
    await backend.notificationController.close();
  });
}
