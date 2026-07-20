import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/backend.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;

class _ControlledBackend extends FakeBackend {
  final profileRequests = <Completer<Profile?>>[];
  final activeOrderRequests = <Completer<List<OrderRecord>>>[];
  final orderHistoryRequests = <Completer<List<OrderRecord>>>[];

  @override
  Future<Profile?> currentProfile() {
    final request = Completer<Profile?>();
    profileRequests.add(request);
    return request.future;
  }

  @override
  Future<List<OrderRecord>> activeOrders() {
    final request = Completer<List<OrderRecord>>();
    activeOrderRequests.add(request);
    return request.future;
  }

  @override
  Future<List<OrderRecord>> orderHistory() {
    final request = Completer<List<OrderRecord>>();
    orderHistoryRequests.add(request);
    return request.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;
  late _ControlledBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _ControlledBackend();
    app_backend.backend = backend;
    state = AppState();
  });

  tearDown(app_backend.useFakeBackend);

  test('hasil loadProfile lama tidak menimpa request terbaru', () async {
    final first = state.loadProfile();
    final second = state.loadProfile();

    backend.profileRequests[1].complete(
      const Profile(id: 'new', name: 'Profil Baru', email: 'new@example.com'),
    );
    await second;
    expect(state.userName, 'Profil Baru');

    backend.profileRequests[0].complete(
      const Profile(id: 'old', name: 'Profil Lama', email: 'old@example.com'),
    );
    await first;

    expect(state.userName, 'Profil Baru');
    expect(state.userEmail, 'new@example.com');
  });

  test(
    'loadOrders lama tidak mengubah data atau loading request baru',
    () async {
      final sampleOrders = await FakeBackend().activeOrders();
      expect(sampleOrders, isNotEmpty);

      final first = state.loadOrders();
      final second = state.loadOrders();

      backend.activeOrderRequests[0].complete(const []);
      backend.orderHistoryRequests[0].complete(const []);
      await first;

      expect(state.isLoadingOrders, isTrue);
      expect(state.activeOrders, isEmpty);

      backend.activeOrderRequests[1].complete(sampleOrders);
      backend.orderHistoryRequests[1].complete(const []);
      await second;

      expect(state.isLoadingOrders, isFalse);
      expect(state.activeOrders, sampleOrders);
    },
  );

  test(
    'error request loadOrders lama diabaikan setelah request baru sukses',
    () async {
      final first = state.loadOrders();
      final second = state.loadOrders();

      backend.activeOrderRequests[1].complete(const []);
      backend.orderHistoryRequests[1].complete(const []);
      await second;

      backend.activeOrderRequests[0].completeError(
        const BackendException('stale', 'Error request lama.'),
      );
      backend.orderHistoryRequests[0].complete(const []);
      await first;

      expect(state.ordersError, isNull);
      expect(state.isLoadingOrders, isFalse);
    },
  );

  test('reset sesi membatalkan loader dan langsung mereset loading', () async {
    final pending = state.loadOrders();
    expect(state.isLoadingOrders, isTrue);

    state.resetSession();
    expect(state.isLoadingOrders, isFalse);

    backend.activeOrderRequests.single.complete(const []);
    backend.orderHistoryRequests.single.complete(const []);
    await pending;

    expect(state.isLoadingOrders, isFalse);
    expect(state.activeOrders, isEmpty);
  });
}
