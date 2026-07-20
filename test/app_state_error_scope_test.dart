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
}
