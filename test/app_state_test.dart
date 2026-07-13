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
    },
  );

  test('idempotency checkout bertahan setelah AppState dibuat ulang', () async {
    final backend = _CommitThenLoseResponseBackend();
    app_backend.backend = backend;
    final firstState = AppState();
    await firstState.restoreLocalState();
    final bag = (await backend.nearbyBags()).first;

    await expectLater(
      firstState.placeOrder(bag, 1, 'Simulasi'),
      throwsA(isA<BackendException>()),
    );
    final afterCommit = await backend.activeOrders();

    final restartedState = AppState();
    await restartedState.restoreLocalState();
    final recovered = await restartedState.placeOrder(bag, 1, 'Simulasi');
    final afterRetry = await backend.activeOrders();

    expect(recovered.id, afterCommit.first.id);
    expect(afterRetry.length, afterCommit.length);
    app_backend.useFakeBackend();
  });

  test('payout fail-closed selama checkout masih simulasi', () async {
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
