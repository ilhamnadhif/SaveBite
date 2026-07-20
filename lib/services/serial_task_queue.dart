import 'dart:async';

/// Menjalankan event asynchronous satu per satu sesuai urutan kedatangan.
///
/// Error sebuah event dilaporkan melalui [onError], lalu antrean dilanjutkan
/// agar event penting sesudahnya (misalnya `signedOut`) tidak ikut hilang.
class SerialTaskQueue<T> {
  final FutureOr<void> Function(T event) _handler;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  SerialTaskQueue({
    required FutureOr<void> Function(T event) handler,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _handler = handler,
       _onError = onError;

  void add(T event) {
    if (_closed) return;
    _tail = _tail
        .then((_) async {
          if (_closed) return;
          await _handler(event);
        })
        .catchError((Object error, StackTrace stackTrace) {
          _onError?.call(error, stackTrace);
        });
  }

  /// Future yang selesai setelah seluruh event yang saat ini sudah masuk
  /// selesai ditangani. Dipakai terutama oleh regression test.
  Future<void> get idle => _tail;

  void close() => _closed = true;
}
