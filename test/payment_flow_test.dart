import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_state.dart';
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
      // URL sengaja null agar widget test tidak membuka aplikasi browser.
      paymentRedirectUrl: null,
    );
  }

  @override
  Future<OrderRecord> refreshPayment(OrderRecord order) async {
    statusCalls++;
    return order.copyWith(paymentState: PaymentState.paid);
  }
}

class _CommitThenLoseWidgetResponseBackend extends FakeBackend {
  final keys = <String>[];
  bool _lostFirstResponse = false;

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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appState.resetSession();
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
          method: 'Midtrans',
          idempotencyKey: 'checkout-test-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(backend.createCalls, 1);
    expect(find.byType(VoucherScreen), findsNothing);
    expect(find.text('Selesaikan pembayaran'), findsOneWidget);

    await tester.tap(find.text('Cek status pembayaran'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(backend.statusCalls, 1);
    expect(find.byType(VoucherScreen), findsOneWidget);
  });

  testWidgets('retry UI memakai kembali key setelah respons checkout hilang', (
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
          method: 'Midtrans',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PaymentFailedScreen), findsOneWidget);
    final committedCount = (await backend.activeOrders()).length;
    await tester.tap(find.text('Coba lagi'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(backend.keys, hasLength(2));
    expect(backend.keys[1], backend.keys[0]);
    expect(await backend.activeOrders(), hasLength(committedCount));
    expect(find.byType(VoucherScreen), findsOneWidget);
  });

  test('order hasil restore menyerahkan validasi stok ke server', () async {
    final backend = _RemoteQuantityProbeBackend();
    app_backend.backend = backend;
    final restoredBag = SampleData.bagRoti.copyWith(
      quantityLeft: 0,
      soldOut: true,
    );

    await appState.placeOrder(restoredBag, 1, 'Midtrans');

    expect(backend.reachedServer, isTrue);
  });
}
