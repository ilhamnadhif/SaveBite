import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/mappers.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;

class _MixedCompletedOrdersBackend extends FakeBackend {
  @override
  Future<List<IncomingOrder>> incomingOrders() async => [
    const IncomingOrder(
      id: 'redeemed-order',
      customer: 'Redeemed',
      initial: 'R',
      time: 'Hari ini',
      bags: 1,
      code: 'SB-REDEEMED',
      status: IncomingOrderStatus.redeemed,
    ),
    const IncomingOrder(
      id: 'cancelled-order',
      customer: 'Cancelled',
      initial: 'C',
      time: 'Hari ini',
      bags: 2,
      code: 'SB-CANCELLED',
      status: IncomingOrderStatus.cancelled,
    ),
    incomingOrderFromMap({
      'id': 'refunded-order',
      'consumer_name': 'Refunded',
      'status': 'refunded',
      'quantity': 3,
    }),
  ];
}

void main() {
  test('statistik bag hanya menghitung order redeemed', () async {
    app_backend.backend = _MixedCompletedOrdersBackend();
    addTearDown(app_backend.useFakeBackend);
    final state = AppState();

    await state.loadMerchantData();

    expect(state.completedOrders, hasLength(3));
    expect(state.redeemedBagCount, 1);
  });
}
