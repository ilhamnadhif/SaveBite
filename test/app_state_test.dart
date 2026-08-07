import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/backend.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;

class _CommitThenLoseResponseBackend extends FakeBackend {
  bool _lostFirstResponse = false;

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    final order = await super.placeOrder(
      bag,
      qty,
      method,
      idempotencyKey: idempotencyKey,
    );
    if (!_lostFirstResponse) {
      _lostFirstResponse = true;
      throw const BackendException(
        'network_lost',
        'Respons hilang setelah transaksi tersimpan.',
      );
    }
    return order;
  }
}

class _CheckoutProbeBackend extends FakeBackend {
  final keys = <String>[];
  int createCalls = 0;

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    createCalls++;
    keys.add(idempotencyKey);
    final order = await super.placeOrder(
      bag,
      qty,
      method,
      idempotencyKey: idempotencyKey,
    );
    return order.copyWith(paymentState: PaymentState.pending);
  }
}

class _PendingWithMatchingHistoryBackend extends FakeBackend {
  final keys = <String>[];
  OrderRecord? _pending;
  Bag? _bag;

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
    _bag = bag;
    return _pending ??= OrderRecord(
      id: 'pending-repeat-order',
      bag: bag,
      code: 'SB-PENDING',
      dateLabel: 'Hari ini',
      amount: bag.salePrice * qty + 1000,
      status: OrderStatus.pending,
      quantity: qty,
      paymentMethod: method,
      paymentState: PaymentState.pending,
    );
  }

  @override
  Future<List<OrderRecord>> activeOrders() async => [?_pending];

  @override
  Future<List<OrderRecord>> orderHistory() async {
    final bag = _bag;
    if (bag == null) return [];
    return [
      OrderRecord(
        id: 'older-completed-order',
        bag: bag,
        code: 'SB-OLD',
        dateLabel: 'Kemarin',
        amount: bag.salePrice + 1000,
        status: OrderStatus.done,
        quantity: 1,
        paymentMethod: 'Midtrans',
        paymentState: PaymentState.paid,
      ),
    ];
  }
}

class _AmbiguousWithMatchingHistoryBackend extends FakeBackend {
  final keys = <String>[];
  Bag? _bag;
  String? _committedKey;
  OrderRecord? _committed;
  bool _committedVisible = false;
  bool _committedResolved = false;
  int _freshOrderNumber = 0;

  @override
  bool get isRemote => true;

  OrderRecord _pendingOrder(
    Bag bag,
    int qty,
    String method, {
    required String id,
  }) => OrderRecord(
    id: id,
    bag: bag,
    code: 'SB-${id.toUpperCase()}',
    dateLabel: 'Hari ini',
    amount: bag.salePrice * qty + 1000,
    status: OrderStatus.pending,
    quantity: qty,
    paymentMethod: method,
    paymentState: PaymentState.pending,
  );

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    _bag = bag;
    if (_committedKey == null) {
      _committedKey = idempotencyKey;
      _committed = _pendingOrder(bag, qty, method, id: 'ambiguous-order');
      throw const BackendException(
        'response_lost',
        'Respons hilang sementara server masih menyelesaikan order.',
      );
    }
    if (idempotencyKey == _committedKey) {
      _committedVisible = true;
      return _committed!;
    }
    _freshOrderNumber++;
    return _pendingOrder(
      bag,
      qty,
      method,
      id: 'fresh-order-$_freshOrderNumber',
    );
  }

  void resolveCommittedOrder() {
    _committedResolved = true;
    _committedVisible = false;
    _committed = _committed!.copyWith(
      status: OrderStatus.done,
      paymentState: PaymentState.paid,
    );
  }

  @override
  Future<List<OrderRecord>> activeOrders() async => [
    if (_committedVisible && !_committedResolved) _committed!,
  ];

  @override
  Future<List<OrderRecord>> orderHistory() async {
    final bag = _bag;
    if (bag == null) return [];
    return [
      OrderRecord(
        id: 'unrelated-old-order',
        bag: bag,
        code: 'SB-UNRELATED',
        dateLabel: 'Minggu lalu',
        amount: bag.salePrice + 1000,
        status: OrderStatus.done,
        quantity: 1,
        paymentMethod: 'Midtrans',
        paymentState: PaymentState.paid,
      ),
      if (_committedResolved) _committed!,
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appState.resetSession();
  });

  test('lokasi FakeBackend berhasil tanpa memanggil platform GPS', () async {
    final success = await appState.determineLocation();

    expect(success, isTrue);
    expect(appState.locationPrimed, isTrue);
    expect(appState.hasLocationPermission, isTrue);
    expect(appState.location, 'Margonda, Depok');
    expect(appState.userLatitude, closeTo(-6.3725, .0001));
    expect(appState.userLongitude, closeTo(106.8323, .0001));
    expect(appState.nearbyBags, isNotEmpty);
    expect(appState.errorMessage, isNull);
  });

  test('area pencarian tidak menimpa posisi fisik perangkat', () async {
    final state = AppState();
    await state.restoreLocalState();
    await state.setLocationWithCoordinates(
      'Sekitar saya',
      -6.201,
      106.817,
      reload: false,
      fromDevice: true,
      accuracyMeters: 18,
    );

    await state.setLocationWithCoordinates(
      'Area peta',
      -6.3725,
      106.8323,
      reload: false,
    );

    expect(state.userLocationIsFromDevice, isFalse);
    expect(state.userLatitude, closeTo(-6.3725, .0001));
    expect(state.userLongitude, closeTo(106.8323, .0001));
    expect(state.deviceLatitude, closeTo(-6.201, .0001));
    expect(state.deviceLongitude, closeTo(106.817, .0001));
    expect(state.userLocationAccuracyMeters, 18);

    final restored = AppState();
    await restored.restoreLocalState();
    expect(restored.location, 'Area peta');
    expect(restored.userLatitude, closeTo(-6.3725, .0001));
    expect(restored.deviceLatitude, closeTo(-6.201, .0001));
    expect(restored.deviceLongitude, closeTo(106.817, .0001));
    expect(restored.userLocationAccuracyMeters, 18);
  });

  test('profil toko menolak koordinat peta yang tidak valid', () async {
    await expectLater(
      appState.updateStore(latitude: 0, longitude: 0),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'invalid_store_location',
        ),
      ),
    );
  });

  test(
    'clearSessionState menghapus seluruh cache dan identitas sesi',
    () async {
      await Future.wait([
        appState.loadConsumerHome(),
        appState.loadOrders(),
        appState.loadFavorites(),
        appState.loadNotifications(),
        appState.loadMerchantData(),
        appState.loadMerchantReviews(),
        appState.loadBalance(),
      ]);
      await appState.updateProfile(name: 'Akun Lama');
      await appState.updateStore(
        name: 'Toko Lama',
        category: 'Bakery',
        address: 'Alamat lama',
        open: '08.00',
        close: '20.00',
      );
      await appState.setLocationWithCoordinates(
        'Lokasi Akun Lama',
        -6.2,
        106.8,
        fromDevice: true,
        accuracyMeters: 12,
      );
      await appState.markLocationPrimed();
      appState.setDefaultPaymentMethod('OVO');
      appState.switchToMerchant();

      expect(appState.nearbyBags, isNotEmpty);
      expect(appState.activeOrders, isNotEmpty);
      expect(appState.favoriteStores, isNotEmpty);
      expect(appState.notifications, isNotEmpty);
      expect(appState.activeBags, isNotEmpty);
      expect(appState.pendingOrders, isNotEmpty);
      expect(appState.merchantReviews, isNotEmpty);
      expect(appState.transactions, isNotEmpty);
      expect(appState.bankAccountRecords, isNotEmpty);
      expect(appState.merchantSetupDone, isTrue);

      await appState.clearSessionState();

      expect(appState.mode, AppMode.consumer);
      expect(appState.userName, 'Pengguna');
      expect(appState.userEmail, isEmpty);
      expect(appState.userPhone, isEmpty);
      expect(appState.storeName, isEmpty);
      expect(appState.merchantSetupDone, isFalse);
      expect(appState.nearbyBags, isEmpty);
      expect(appState.activeOrders, isEmpty);
      expect(appState.orderHistory, isEmpty);
      expect(appState.favoriteStores, isEmpty);
      expect(appState.notifications, isEmpty);
      expect(appState.activeBags, isEmpty);
      expect(appState.inactiveBags, isEmpty);
      expect(appState.pendingOrders, isEmpty);
      expect(appState.completedOrders, isEmpty);
      expect(appState.merchantReviews, isEmpty);
      expect(appState.transactions, isEmpty);
      expect(appState.bankAccountRecords, isEmpty);
      expect(appState.payoutRequests, isEmpty);
      expect(appState.balance, 0);
      expect(appState.pendingMerchantIntent, isNull);
      expect(appState.locationPrimed, isFalse);
      expect(appState.location, 'Lokasi belum dipilih');
      expect(appState.userLatitude, isNull);
      expect(appState.userLongitude, isNull);
      expect(appState.deviceLatitude, isNull);
      expect(appState.deviceLongitude, isNull);
      expect(appState.defaultPaymentMethod, 'QRIS');

      final restoredForNextAccount = AppState();
      await restoredForNextAccount.restoreLocalState();
      expect(restoredForNextAccount.locationPrimed, isFalse);
      expect(restoredForNextAccount.userLatitude, isNull);
      expect(restoredForNextAccount.deviceLatitude, isNull);
      expect(restoredForNextAccount.defaultPaymentMethod, 'QRIS');
    },
  );

  test('idempotency checkout bertahan setelah AppState dibuat ulang', () async {
    final backend = _CommitThenLoseResponseBackend();
    app_backend.backend = backend;
    final firstState = AppState();
    await firstState.restoreLocalState();
    final bag = (await backend.nearbyBags()).first;

    await expectLater(
      firstState.placeOrder(bag, 1, 'Midtrans'),
      throwsA(isA<BackendException>()),
    );
    final afterCommit = await backend.activeOrders();

    final restartedState = AppState();
    await restartedState.restoreLocalState();
    final recovered = await restartedState.placeOrder(bag, 1, 'Midtrans');
    final afterRetry = await backend.activeOrders();

    expect(recovered.id, afterCommit.first.id);
    expect(afterRetry.length, afterCommit.length);
    app_backend.useFakeBackend();
  });

  test(
    'checkout tetap memanggil backend ketika persistence lokal gagal',
    () async {
      final backend = _CheckoutProbeBackend();
      app_backend.backend = backend;
      final state = AppState(
        idempotencyPersistenceOverride: () async {
          throw StateError('local storage unavailable');
        },
      );
      final bag = (await backend.nearbyBags()).first;

      final first = await state.placeOrder(bag, 1, 'Midtrans');
      final retry = await state.placeOrder(bag, 1, 'Midtrans');

      expect(backend.createCalls, 2);
      expect(backend.keys, hasLength(2));
      expect(backend.keys[1], backend.keys[0]);
      expect(retry.id, first.id);
      app_backend.useFakeBackend();
    },
  );

  test(
    'checkout dapat memperbarui cache hasil loadOrders yang fixed-length',
    () async {
      final backend = _CheckoutProbeBackend();
      app_backend.backend = backend;
      final state = AppState();
      final bag = (await backend.nearbyBags()).first;

      await state.loadOrders();
      final order = await state.placeOrder(bag, 1, 'Midtrans');

      expect(backend.createCalls, 1);
      expect(state.activeOrders.any((item) => item.id == order.id), isTrue);
      app_backend.useFakeBackend();
    },
  );

  test(
    'riwayat dengan signature sama tidak menghapus key order yang masih pending',
    () async {
      final backend = _PendingWithMatchingHistoryBackend();
      app_backend.backend = backend;
      final firstState = AppState();
      await firstState.restoreLocalState();
      final bag = (await backend.nearbyBags()).first;

      await firstState.placeOrder(bag, 1, 'Midtrans');
      await firstState.loadOrders();

      final restartedState = AppState();
      await restartedState.restoreLocalState();
      await restartedState.placeOrder(bag, 1, 'Midtrans');

      expect(backend.keys, hasLength(2));
      expect(backend.keys[1], backend.keys[0]);
      app_backend.useFakeBackend();
    },
  );

  test(
    'respons ambigu tidak dikaitkan ke riwayat lama dan exact order membersihkan key',
    () async {
      final backend = _AmbiguousWithMatchingHistoryBackend();
      app_backend.backend = backend;
      final firstState = AppState();
      await firstState.restoreLocalState();
      final bag = (await backend.nearbyBags()).first;

      await expectLater(
        firstState.placeOrder(bag, 1, 'Midtrans'),
        throwsA(isA<BackendException>()),
      );
      await firstState.loadOrders();

      final retryState = AppState();
      await retryState.restoreLocalState();
      final recovered = await retryState.placeOrder(bag, 1, 'Midtrans');

      expect(recovered.id, 'ambiguous-order');
      expect(backend.keys, hasLength(2));
      expect(backend.keys[1], backend.keys[0]);

      backend.resolveCommittedOrder();
      await retryState.loadOrders();

      final nextCheckoutState = AppState();
      await nextCheckoutState.restoreLocalState();
      await nextCheckoutState.placeOrder(bag, 1, 'Midtrans');

      expect(backend.keys, hasLength(3));
      expect(backend.keys[2], isNot(backend.keys[1]));
      app_backend.useFakeBackend();
    },
  );

  test('payout fail-closed ketika operator belum mengaktifkannya', () async {
    await appState.loadBalance();

    await expectLater(
      appState.withdraw(50000),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'payout_disabled',
        ),
      ),
    );
  });
}
