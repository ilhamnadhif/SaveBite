import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';

import '../../services/snap_checkout_session.dart';

@JS('SaveBiteSnap.pay')
external JSPromise<JSAny?> _snapPay(
  JSString token,
  JSString clientKey,
  JSString environment,
  JSString sessionId,
  JSFunction onResult,
);

@JS('SaveBiteSnap.hide')
external void _snapHide(JSString sessionId);

/// Flutter web menggunakan popup in-page resmi Snap.js. Isi callback provider
/// dibuang di bridge; Flutter hanya menerima sinyal untuk sinkronisasi server.
class SnapCheckoutView extends StatefulWidget {
  final SnapCheckoutSession session;
  final VoidCallback onStatusHint;
  final ValueChanged<String> onError;

  const SnapCheckoutView({
    super.key,
    required this.session,
    required this.onStatusHint,
    required this.onError,
  });

  @override
  State<SnapCheckoutView> createState() => _SnapCheckoutViewState();
}

class _SnapCheckoutViewState extends State<SnapCheckoutView> {
  late String _sessionId;
  late JSFunction _resultHandler;
  bool _opening = true;

  @override
  void initState() {
    super.initState();
    _configureSession();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void didUpdateWidget(covariant SnapCheckoutView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.session.clientKey != widget.session.clientKey) {
      _snapHide(_sessionId.toJS);
      _configureSession();
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    }
  }

  void _configureSession() {
    _sessionId =
        '${widget.session.environment}:${widget.session.token}:${identityHashCode(this)}';
    _resultHandler = ((JSString _) {
      if (!mounted) return;
      setState(() => _opening = false);
      widget.onStatusHint();
    }).toJS;
  }

  void _open() {
    if (!mounted) return;
    setState(() => _opening = true);
    try {
      unawaited(
        _snapPay(
          widget.session.token.toJS,
          widget.session.clientKey.toJS,
          widget.session.environment.toJS,
          _sessionId.toJS,
          _resultHandler,
        ).toDart.catchError((Object _) {
          if (mounted) {
            setState(() => _opening = false);
            widget.onError(
              'Halaman pembayaran belum dapat dibuka. Muat ulang untuk mencoba lagi.',
            );
          }
          return null;
        }),
      );
    } catch (_) {
      setState(() => _opening = false);
      widget.onError(
        'Komponen pembayaran belum siap. Muat ulang untuk mencoba lagi.',
      );
    }
  }

  @override
  void dispose() {
    _snapHide(_sessionId.toJS);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('snap-checkout-view'),
    color: Colors.white,
    child: Center(
      child: _opening
          ? const CircularProgressIndicator()
          : const SizedBox.shrink(),
    ),
  );
}
