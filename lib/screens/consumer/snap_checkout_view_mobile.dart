import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/snap_checkout_session.dart';

/// WebView internal khusus satu sesi Snap. Tidak pernah meluncurkan browser
/// atau aplikasi eksternal dan tidak menyuntik JavaScript ke halaman Midtrans.
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
  WebViewController? _controller;
  bool _loading = true;
  bool _platformUnavailable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await WebViewCookieManager().clearCookies();
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame == true && mounted) {
                widget.onError(
                  'Halaman pembayaran belum dapat dimuat. Periksa koneksi lalu muat ulang.',
                );
              }
            },
            onNavigationRequest: _handleNavigation,
          ),
        );
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.loadRequest(widget.session.redirectUri);
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      // Flutter widget tests tidak memiliki native WebView implementation.
      // Pada perangkat yang didukung, plugin selalu terdaftar sebelum runApp.
      setState(() {
        _platformUnavailable = true;
        _loading = false;
      });
    }
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (widget.session.isAppCallback(uri)) {
      widget.onStatusHint();
      return NavigationDecision.prevent;
    }
    // Subframe navigation uses the same allowlist. Image/script/XHR resources
    // are not navigation requests and tetap dapat dimuat normal oleh WebView.
    return widget.session.allowsMainFrameNavigation(uri)
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    if (_platformUnavailable) {
      return const Center(
        key: ValueKey('snap-webview-unavailable'),
        child: Icon(Icons.web_asset_off_rounded, size: 42),
      );
    }
    final controller = _controller;
    return Stack(
      key: const ValueKey('snap-checkout-view'),
      fit: StackFit.expand,
      children: [
        if (controller != null) WebViewWidget(controller: controller),
        if (_loading || controller == null)
          const ColoredBox(
            color: Colors.white,
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
