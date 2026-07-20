import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/services/serial_task_queue.dart';

void main() {
  test('event yang datang saat task aktif tetap diproses berurutan', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final handled = <int>[];
    final queue = SerialTaskQueue<int>(
      handler: (event) async {
        if (event == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        handled.add(event);
      },
    );

    queue.add(1);
    await firstStarted.future;
    queue.add(2);
    releaseFirst.complete();
    await queue.idle;

    expect(handled, [1, 2]);
  });

  test('error satu task tidak membuang task berikutnya', () async {
    final handled = <int>[];
    final errors = <Object>[];
    final queue = SerialTaskQueue<int>(
      handler: (event) {
        if (event == 1) throw StateError('gagal');
        handled.add(event);
      },
      onError: (error, _) => errors.add(error),
    );

    queue.add(1);
    queue.add(2);
    await queue.idle;

    expect(errors, hasLength(1));
    expect(handled, [2]);
  });
}
