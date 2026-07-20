import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/data/backend/fake_backend.dart';

void main() {
  test(
    'semua watcher FakeBackend dapat dibatalkan setelah snapshot pertama',
    () async {
      final backend = FakeBackend();

      Future<void> receivesThenCancels<T>(Stream<T> stream) async {
        final firstValue = Completer<void>();
        final subscription = stream.listen((_) {
          if (!firstValue.isCompleted) firstValue.complete();
        });
        await firstValue.future;
        await subscription.cancel().timeout(const Duration(seconds: 1));
      }

      await receivesThenCancels(backend.watchNotifications());
      await receivesThenCancels(backend.watchIncomingOrders());
      await receivesThenCancels(backend.watchTransactions());
    },
  );
}
