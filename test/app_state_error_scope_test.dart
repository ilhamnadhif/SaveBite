import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/backend.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;

class _OrdersFailureBackend extends FakeBackend {
  @override
  Future<List<OrderRecord>> activeOrders() {
    throw const BackendException(
      'orders_unavailable',
      'Pesanan sedang tidak dapat dimuat.',
    );
  }
}

class _FavoritesFailureBackend extends FakeBackend {
  @override
  Future<Set<String>> favoriteMerchantIds() {
    throw const BackendException(
      'favorites_unavailable',
      'Favorit sedang tidak dapat dimuat.',
    );
  }
}

class _LocationReloadFailureBackend extends FakeBackend {
  var _nearbyCalls = 0;

  @override
  Future<List<Bag>> nearbyBags({
    double? latitude,
    double? longitude,
    BagFilter filter = const BagFilter(),
  }) async {
    _nearbyCalls++;
    if (_nearbyCalls > 1) {
      throw const BackendException(
        'nearby_unavailable',
        'Bag di area ini belum dapat dimuat.',
      );
    }
    return super.nearbyBags(
      latitude: latitude,
      longitude: longitude,
      filter: filter,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appState.resetSession();
  });

  tearDown(app_backend.useFakeBackend);

  test('error loader pesanan tidak bocor ke loader tab lain', () async {
    app_backend.backend = _OrdersFailureBackend();

    await Future.wait([
      appState.loadConsumerHome(),
      appState.loadOrders(),
      appState.loadNotifications(),
      appState.loadBalance(),
    ]);

    expect(appState.ordersError, 'Pesanan sedang tidak dapat dimuat.');
    expect(appState.consumerError, isNull);
    expect(appState.notificationsError, isNull);
    expect(appState.balanceError, isNull);
    expect(appState.errorMessage, isNull);

    await appState.loadConsumerHome();
    expect(appState.ordersError, 'Pesanan sedang tidak dapat dimuat.');
  });

  test('gagal memuat favorit tidak menyembunyikan bag di beranda', () async {
    app_backend.backend = _FavoritesFailureBackend();

    await appState.loadConsumerHome();

    expect(appState.nearbyBags, isNotEmpty);
    expect(appState.consumerError, isNull);
  });

  test('bag area lama dibersihkan saat area baru gagal dimuat', () async {
    app_backend.backend = _LocationReloadFailureBackend();

    await appState.setLocationWithCoordinates(
      'Area pertama',
      -6.3725,
      106.8323,
    );
    expect(appState.nearbyBags, isNotEmpty);

    await appState.setLocationWithCoordinates('Area kedua', -6.2607, 106.8134);

    expect(appState.location, 'Area kedua');
    expect(appState.nearbyBags, isEmpty);
    expect(appState.consumerError, 'Bag di area ini belum dapat dimuat.');
  });
}
