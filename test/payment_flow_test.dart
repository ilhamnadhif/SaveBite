import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/config/env.dart';
import 'package:savebite/data/backend/backend.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/data/sample_data.dart';
import 'package:savebite/screens/consumer/processing_screen.dart';
import 'package:savebite/screens/consumer/payment_failed_screen.dart';
import 'package:savebite/screens/consumer/voucher_screen.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;
import 'package:savebite/theme/app_theme.dart';

class _VerifiedPaymentBackend extends FakeBackend {
  static const qrUrl =
      'https://api.sandbox.midtrans.com/v2/qris/0d8178e1-c6c7-4ab4-81a6-893be9d924ab/qr-code';

  int createCalls = 0;
  int statusCalls = 0;

  @override
  bool get isRemote => true;

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    createCalls++;
    return OrderRecord(
      id: 'order-midtrans-1',
      bag: bag,
      code: 'SB-MIDTRANS',
      dateLabel: 'Hari ini',
      amount: bag.salePrice * qty + 1000,
      status: OrderStatus.pending,
      quantity: qty,
      paymentMethod: method,
      subtotalAmount: bag.salePrice * qty,
      serviceFee: 1000,
      paymentState: PaymentState.pending,
      paymentQrUrl: qrUrl,
      paymentExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<OrderRecord> refreshPayment(OrderRecord order) async {
    statusCalls++;
    return order.copyWith(paymentState: PaymentState.paid);
  }
}

class _VerifiedSnapBackend extends FakeBackend {
  static const redirectUrl =
      'https://app.sandbox.midtrans.com/snap/v2/vtweb/redirectId_987654321';
  static const snapToken = 'sandboxToken_123456789';

  int statusCalls = 0;

  @override
  bool get isRemote => true;

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async => OrderRecord(
    id: 'order-snap-1',
    bag: bag,
    code: 'SB-SNAP',
    dateLabel: 'Hari ini',
    amount: bag.salePrice * qty + 1000,
    status: OrderStatus.pending,
    quantity: qty,
    paymentMethod: method,
    subtotalAmount: bag.salePrice * qty,
    serviceFee: 1000,
    paymentState: PaymentState.pending,
    paymentSnapToken: snapToken,
    paymentRedirectUrl: redirectUrl,
    paymentExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
  );

  @override
  Future<OrderRecord> refreshPayment(OrderRecord order) async {
    statusCalls++;
    return order.copyWith(paymentState: PaymentState.paid);
  }
}

class _CommitThenLoseWidgetResponseBackend extends FakeBackend {
  final keys = <String>[];
  bool _lostFirstResponse = false;
  String? committedOrderId;

  @override
  bool get isRemote => true;

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    final order = await super.placeOrder(
      bag,
      qty,
      method,
      idempotencyKey: idempotencyKey,
    );
    committedOrderId = order.id;
    if (!_lostFirstResponse) {
      _lostFirstResponse = true;
      throw const BackendException(
        'response_lost',
        'Respons checkout terputus setelah order tersimpan.',
      );
    }
    return order;
  }
}

class _RemoteQuantityProbeBackend extends FakeBackend {
  bool reachedServer = false;

  @override
  bool get isRemote => true;

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    reachedServer = true;
    return OrderRecord(
      id: 'server-validated-order',
      bag: bag,
      code: 'SB-SERVER',
      dateLabel: 'Hari ini',
      amount: bag.salePrice * qty + 1000,
      status: OrderStatus.pending,
      quantity: qty,
      paymentMethod: method,
      paymentState: PaymentState.pending,
    );
  }
}

class _RetryQrisBackend extends FakeBackend {
  int createCalls = 0;
  final keys = <String>[];

  @override
  bool get isRemote => true;

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    createCalls++;
    keys.add(idempotencyKey);
    return OrderRecord(
      id: 'retry-qris-order',
      bag: bag,
      code: 'SB-RETRYQR',
      dateLabel: 'Hari ini',
      amount: bag.salePrice * qty + 1000,
      status: OrderStatus.pending,
      quantity: qty,
      paymentMethod: method,
      paymentState: PaymentState.pending,
      paymentQrUrl: createCalls > 1 ? _VerifiedPaymentBackend.qrUrl : null,
      paymentExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<OrderRecord> refreshPayment(OrderRecord order) async => order;
}

class _SandboxSimulatorBackend extends FakeBackend {
  static const simulatorUrl =
      'https://api.sandbox.midtrans.com/v2/qris/0d8178e1-c6c7-4ab4-81a6-893be9d924ab/qr-code';

  int statusCalls = 0;

  @override
  bool get isRemote => true;

  @override
  Future<OrderRecord> refreshPayment(OrderRecord order) async {
    statusCalls++;
    return order.copyWith(simulatorQrImageUrl: simulatorUrl);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appState.resetSession();
    Env.loadAssetTextForTesting('''
SUPABASE_URL=https://mnxnwkgwiqvcgqximcvb.supabase.co
SUPABASE_ANON_KEY=sb_publishable_test
MIDTRANS_CLIENT_KEY=Mid-client-dVbTOwuCWngYwlGB
MIDTRANS_ENVIRONMENT=sandbox
''');
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1200, 2700);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    app_backend.useFakeBackend();
    Env.resetForTesting();
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('voucher hanya dibuka setelah status server menyatakan paid', (
    tester,
  ) async {
    final backend = _VerifiedPaymentBackend();
    app_backend.backend = backend;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
          idempotencyKey: 'checkout-test-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(backend.createCalls, 1);
    expect(find.byType(VoucherScreen), findsNothing);
    expect(find.text('Selesaikan pembayaran'), findsOneWidget);
    expect(find.byKey(const ValueKey('qris-image')), findsOneWidget);
    expect(find.text(_VerifiedPaymentBackend.qrUrl), findsNothing);
    expect(find.text('Salin URL QRIS lama'), findsNothing);
    expect(find.text('Muat ulang QRIS'), findsOneWidget);
    expect(find.textContaining('Selesaikan dalam sekitar'), findsOneWidget);

    await tester.tap(find.text('Muat ulang QRIS'));
    await tester.pump();
    expect(find.byKey(const ValueKey('qris-network-image-1')), findsOneWidget);

    await tester.tap(find.text('Cek status pembayaran'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(backend.statusCalls, 1);
    expect(find.byType(VoucherScreen), findsOneWidget);
  });

  testWidgets('respons checkout hilang dipulihkan dari order committed', (
    tester,
  ) async {
    final backend = _CommitThenLoseWidgetResponseBackend();
    app_backend.backend = backend;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PaymentFailedScreen), findsNothing);
    expect(backend.keys, hasLength(1));
    final committed = (await backend.activeOrders()).where(
      (order) => order.id == backend.committedOrderId,
    );
    expect(committed, hasLength(1));
    expect(find.byType(VoucherScreen), findsOneWidget);
  });

  testWidgets(
    'Snap QRIS dirender internal dan voucher menunggu status server',
    (tester) async {
      final backend = _VerifiedSnapBackend();
      app_backend.backend = backend;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: const ProcessingScreen(
            bag: SampleData.bagRoti,
            qty: 1,
            method: 'QRIS',
            idempotencyKey: 'checkout-snap-test-1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(VoucherScreen), findsNothing);
      expect(find.byKey(const ValueKey('snap-checkout-card')), findsOneWidget);
      expect(find.text('Pembayaran QRIS'), findsOneWidget);
      expect(find.text(_VerifiedSnapBackend.redirectUrl), findsNothing);
      expect(find.text('Salin URL QRIS'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -650));
      await tester.pump();
      expect(find.text('Muat ulang halaman pembayaran'), findsOneWidget);

      await tester.tap(find.text('Cek status pembayaran'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(backend.statusCalls, 1);
      expect(find.byType(VoucherScreen), findsOneWidget);
    },
  );

  testWidgets('alat simulator QRIS hanya tampil pada sandbox', (tester) async {
    const simulatorUrl =
        'https://api.sandbox.midtrans.com/v2/qris/0d8178e1-c6c7-4ab4-81a6-893be9d924ab/qr-code';
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final order = OrderRecord(
      id: 'order-sandbox-simulator',
      bag: SampleData.bagRoti,
      code: 'SB-SIMULATOR',
      dateLabel: 'Hari ini',
      amount: 16000,
      status: OrderStatus.pending,
      paymentMethod: 'QRIS',
      paymentState: PaymentState.pending,
      paymentSnapToken: _VerifiedSnapBackend.snapToken,
      paymentRedirectUrl: _VerifiedSnapBackend.redirectUrl,
      simulatorQrImageUrl: simulatorUrl,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
          existingOrder: order,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -760));
    await tester.pump();
    if (!Env.midtransSandbox) {
      expect(
        find.byKey(const ValueKey('sandbox-simulator-qris-card')),
        findsNothing,
      );
      return;
    }
    expect(
      find.byKey(const ValueKey('sandbox-simulator-qris-card')),
      findsOneWidget,
    );
    expect(find.text(simulatorUrl), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sandbox-simulator-qris-copy')));
    await tester.pump();

    expect(copiedText, simulatorUrl);
    expect(find.text('URL QRIS simulator disalin.'), findsOneWidget);
  });

  testWidgets('tombol sandbox mengambil lalu menyalin URL QRIS', (
    tester,
  ) async {
    final backend = _SandboxSimulatorBackend();
    app_backend.backend = backend;
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final order = OrderRecord(
      id: 'order-fetch-simulator-url',
      bag: SampleData.bagRoti,
      code: 'SB-FETCH-QRIS',
      dateLabel: 'Hari ini',
      amount: 16000,
      status: OrderStatus.pending,
      paymentMethod: 'QRIS',
      paymentState: PaymentState.pending,
      paymentSnapToken: _VerifiedSnapBackend.snapToken,
      paymentRedirectUrl: _VerifiedSnapBackend.redirectUrl,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
          existingOrder: order,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -760));
    await tester.pump();
    final copyButton = find.byKey(
      const ValueKey('sandbox-simulator-qris-copy'),
    );
    if (!Env.midtransSandbox) {
      expect(copyButton, findsNothing);
      return;
    }
    expect(copyButton, findsOneWidget);
    expect(find.text('Ambil & salin URL QRIS'), findsOneWidget);
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(backend.statusCalls, 1);
    expect(copiedText, _SandboxSimulatorBackend.simulatorUrl);
    expect(find.text('URL QRIS simulator disalin.'), findsOneWidget);
    expect(find.text('Salin URL'), findsOneWidget);
  });

  testWidgets('alat simulator QRIS tidak tampil pada profile production', (
    tester,
  ) async {
    Env.resetForTesting();
    Env.loadAssetTextForTesting('''
SUPABASE_URL=https://mnxnwkgwiqvcgqximcvb.supabase.co
SUPABASE_ANON_KEY=sb_publishable_test
MIDTRANS_CLIENT_KEY=Mid-client-dVbTOwuCWngYwlGB
MIDTRANS_ENVIRONMENT=production
''');
    final order = OrderRecord(
      id: 'order-production-no-simulator',
      bag: SampleData.bagRoti,
      code: 'SB-PRODUCTION',
      dateLabel: 'Hari ini',
      amount: 16000,
      status: OrderStatus.pending,
      paymentMethod: 'QRIS',
      paymentState: PaymentState.pending,
      paymentSnapToken: _VerifiedSnapBackend.snapToken,
      paymentRedirectUrl:
          'https://app.midtrans.com/snap/v2/vtweb/redirectId_987654321',
      simulatorQrImageUrl: _SandboxSimulatorBackend.simulatorUrl,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
          existingOrder: order,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('snap-checkout-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sandbox-simulator-qris-card')),
      findsNothing,
    );
    expect(find.text('Ambil & salin URL QRIS'), findsNothing);
  });

  testWidgets('QRIS native via GoPay memakai URL gambar Midtrans resmi', (
    tester,
  ) async {
    const gopayQrisUrl =
        'https://api.sandbox.midtrans.com/v2/gopay/0d8178e1-c6c7-4ab4-81a6-893be9d924ab/qr-code';
    final order = OrderRecord(
      id: 'order-gopay-qris',
      bag: SampleData.bagRoti,
      code: 'SB-GOPAYQR',
      dateLabel: 'Hari ini',
      amount: 16000,
      status: OrderStatus.pending,
      paymentMethod: 'QRIS',
      paymentState: PaymentState.pending,
      paymentQrUrl: gopayQrisUrl,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
          existingOrder: order,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('qris-image')), findsOneWidget);
    expect(find.text(gopayQrisUrl), findsNothing);
    expect(find.text('Salin URL QRIS lama'), findsNothing);
    expect(find.text('Muat ulang QRIS'), findsOneWidget);
  });

  testWidgets('QRIS menolak host di luar endpoint resmi Midtrans', (
    tester,
  ) async {
    const untrustedUrl =
        'https://attacker.example/v2/qris/order-unsafe/qr-code';
    final order = OrderRecord(
      id: 'order-untrusted-qris',
      bag: SampleData.bagRoti,
      code: 'SB-UNTRUSTED',
      dateLabel: 'Hari ini',
      amount: 16000,
      status: OrderStatus.pending,
      paymentMethod: 'QRIS',
      paymentState: PaymentState.pending,
      paymentQrUrl: untrustedUrl,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
          existingOrder: order,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('qris-image')), findsNothing);
    expect(find.text(untrustedUrl), findsNothing);
    expect(
      find.textContaining('Halaman pembayaran belum tersedia'),
      findsOneWidget,
    );
    expect(find.text('Salin URL QRIS'), findsNothing);
    expect(find.text('Coba buat pembayaran lagi'), findsOneWidget);
  });

  testWidgets('QRIS yang belum tersimpan dapat dibuat ulang secara idempoten', (
    tester,
  ) async {
    final backend = _RetryQrisBackend();
    app_backend.backend = backend;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const ProcessingScreen(
          bag: SampleData.bagRoti,
          qty: 1,
          method: 'QRIS',
          idempotencyKey: 'retry-qris-same-key',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(backend.createCalls, 1);
    expect(find.text('Coba buat pembayaran lagi'), findsOneWidget);
    expect(find.byKey(const ValueKey('qris-image')), findsNothing);

    await tester.tap(find.text('Coba buat pembayaran lagi'));
    await tester.pump();
    await tester.pump();

    expect(backend.createCalls, 2);
    expect(backend.keys, everyElement('retry-qris-same-key'));
    expect(find.byKey(const ValueKey('qris-image')), findsOneWidget);
    expect(find.text('Salin URL QRIS lama'), findsNothing);
    expect(find.text('Muat ulang QRIS'), findsOneWidget);
  });

  test('order hasil restore menyerahkan validasi stok ke server', () async {
    final backend = _RemoteQuantityProbeBackend();
    app_backend.backend = backend;
    final restoredBag = SampleData.bagRoti.copyWith(
      quantityLeft: 0,
      soldOut: true,
    );

    await appState.placeOrder(restoredBag, 1, 'QRIS');

    expect(backend.reachedServer, isTrue);
  });
}
