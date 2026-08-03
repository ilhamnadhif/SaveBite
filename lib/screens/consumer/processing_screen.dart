import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_nav.dart';
import '../../config/env.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';
import 'payment_failed_screen.dart';
import 'snap_checkout_view.dart';
import '../../services/snap_checkout_session.dart';

/// Membuat satu reservation idempoten, membuka Snap di dalam aplikasi, lalu
/// hanya melanjutkan setelah backend memverifikasi status ke Midtrans.
class ProcessingScreen extends StatefulWidget {
  final Bag bag;
  final int qty;
  final String method;
  final String? idempotencyKey;
  final OrderRecord? existingOrder;

  /// Dipertahankan agar pemanggil lama tetap source-compatible.
  @Deprecated('Kegagalan simulasi buatan sudah dihapus')
  final bool willFail;

  const ProcessingScreen({
    super.key,
    required this.bag,
    required this.qty,
    required this.method,
    this.idempotencyKey,
    this.existingOrder,
    this.willFail = false,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with WidgetsBindingObserver {
  static const _allowedQrHosts = {
    'api.sandbox.midtrans.com',
    'api.midtrans.com',
  };

  OrderRecord? _order;
  Timer? _pollTimer;
  bool _creating = false;
  bool _checking = false;
  bool _navigated = false;
  int _snapReloadEpoch = 0;
  String? _error;

  bool get _busy => _creating || _checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _createPayment());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_order != null) {
        _startPolling();
        unawaited(_checkStatus());
      }
      return;
    }
    // Jeda pekerjaan jaringan ketika aplikasi berada di background.
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _createPayment() async {
    if (_creating || _order != null || !mounted) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final existing = widget.existingOrder;
      if (existing != null) {
        _order = existing;
        await _handleStatus(existing);
        return;
      }
      // FakeBackend tetap menyelesaikan alur deterministik untuk widget test
      // dan demo eksplisit. Backend remote selalu memakai Edge Function.
      if (!appState.usesRemoteBackend) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      final order = await appState.placeOrder(
        widget.bag,
        widget.qty,
        widget.method,
        // Bila null, AppState mengambil atau membuat key yang dipersist. Ini
        // memastikan retry setelah process death tetap menuju order yang sama.
        idempotencyKey: widget.idempotencyKey,
      );
      if (!mounted) return;
      _order = order;
      await _handleStatus(order);
    } on BackendException catch (error) {
      if (await _recoverAfterCreateFailure()) return;
      if (mounted) _showFailure(error.message, retrySameRequest: true);
    } catch (_) {
      if (await _recoverAfterCreateFailure()) return;
      if (mounted) {
        _showFailure(
          'Pembayaran belum dapat dibuat. Periksa koneksi lalu coba lagi.',
          retrySameRequest: true,
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<bool> _recoverAfterCreateFailure() async {
    if (!appState.usesRemoteBackend || !mounted) return false;
    try {
      final recovered = await appState.recoverCheckout(
        widget.bag,
        widget.qty,
        widget.method,
      );
      if (recovered == null || !mounted) return false;
      _order = recovered;
      await _handleStatus(recovered);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleStatus(OrderRecord order) async {
    if (!mounted || _navigated) return;
    setState(() {
      _order = order;
      _error = null;
    });
    if (order.paymentState.isPaid) {
      _navigated = true;
      _pollTimer?.cancel();
      AppNav.toVoucher(context, order, completeCheckout: true);
      return;
    }
    if (order.paymentState.isTerminalFailure) {
      _showFailure(_terminalMessage(order), retrySameRequest: false);
      return;
    }
    _startPolling();
  }

  void _startPolling() {
    if (!appState.usesRemoteBackend || _pollTimer?.isActive == true) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) unawaited(_checkStatus());
    });
  }

  Uri? _paymentQrUri(OrderRecord? order) {
    final rawUrl = order?.paymentQrUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !_allowedQrHosts.contains(uri.host) ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length != 4 ||
        segments[0] != 'v2' ||
        !const {'qris', 'gopay'}.contains(segments[1]) ||
        !_validQrResourceId(segments[2]) ||
        segments[3] != 'qr-code') {
      return null;
    }
    return uri;
  }

  bool _validQrResourceId(String value) => RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
  ).hasMatch(value);

  Uri? _simulatorQrUri(OrderRecord? order) {
    if (!Env.e2eMode) return null;
    final rawUrl = order?.simulatorQrImageUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'api.sandbox.midtrans.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length != 4 ||
        segments[0] != 'v2' ||
        segments[1] != 'qris' ||
        !_validQrResourceId(segments[2]) ||
        segments[3] != 'qr-code') {
      return null;
    }
    return uri;
  }

  Future<void> _copyPaymentQrUrl() async {
    final uri = _paymentQrUri(_order);
    if (uri == null || !mounted) {
      if (mounted) {
        setState(() {
          _error =
              'URL QRIS belum tersedia. Tekan “Cek status pembayaran” untuk mencoba lagi.';
        });
      }
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'URL QRIS disalin.',
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'URL QRIS tidak dapat disalin. Pilih dan salin teks secara manual.';
      });
    }
  }

  Future<void> _copySimulatorQrUrl() async {
    final uri = _simulatorQrUri(_order);
    if (uri == null || !mounted) return;
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'URL QRIS simulator disalin.',
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'URL QRIS simulator tidak dapat disalin.';
      });
    }
  }

  Future<void> _retryPaymentCreation() async {
    if (_busy || _navigated || !mounted) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final refreshed = await appState.placeOrder(
        widget.bag,
        widget.qty,
        widget.method,
        // AppState mempertahankan key berdasarkan signature checkout ketika
        // pemanggil tidak memberikan key eksplisit. Retry ini karena itu tetap
        // menuju reservation/provider order yang sama.
        idempotencyKey: widget.idempotencyKey,
      );
      if (!mounted) return;
      _order = refreshed;
      await _handleStatus(refreshed);
    } on BackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Pembayaran belum dapat dibuat. Periksa koneksi lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _reloadSnapCheckout() {
    if (_busy || _navigated || !mounted) return;
    setState(() {
      _snapReloadEpoch++;
      _error = null;
    });
  }

  void _handleSnapStatusHint() {
    if (!mounted || _navigated) return;
    // Callback browser hanya sebuah hint. Tidak ada field callback yang
    // dipercaya dan voucher tetap menunggu hasil sinkronisasi server.
    unawaited(_checkStatus());
  }

  void _handleSnapError(String message) {
    if (!mounted || _navigated) return;
    setState(() => _error = message);
  }

  Future<void> _checkStatus() async {
    final order = _order;
    if (_checking || order == null || _navigated || !mounted) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final refreshed = await appState.refreshPayment(order);
      if (!mounted) return;
      await _handleStatus(refreshed);
    } on BackendException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Status pembayaran belum dapat diperiksa. Coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _terminalMessage(OrderRecord order) => switch (order.paymentState) {
    PaymentState.expired =>
      'Waktu pembayaran berakhir. Stok yang ditahan sudah dikembalikan.',
    PaymentState.cancelled => 'Pembayaran dibatalkan.',
    PaymentState.refunded =>
      'Refund telah dikonfirmasi Midtrans untuk diproses. Waktu dana masuk mengikuti metode pembayaran.',
    PaymentState.disputed =>
      'Pembayaran sedang ditinjau. Hubungi bantuan jika memerlukan informasi.',
    _ => 'Pembayaran ditolak atau tidak berhasil.',
  };

  void _showFailure(String message, {required bool retrySameRequest}) {
    if (_navigated) return;
    _navigated = true;
    _pollTimer?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PaymentFailedScreen(
          bag: widget.bag,
          method: widget.method,
          qty: widget.qty,
          // Key eksplisit lama tetap diteruskan. Bila null, AppState sudah
          // menyimpan key efektif berdasarkan signature checkout.
          idempotencyKey: retrySameRequest ? widget.idempotencyKey : null,
          message: message,
        ),
      ),
    );
  }

  String get _expiryLabel {
    final expiresAt = _order?.paymentExpiresAt?.toLocal();
    if (expiresAt == null) {
      return 'Selesaikan pembayaran sebelum sesi QRIS kedaluwarsa.';
    }
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return 'Waktu pembayaran telah berakhir.';
    final minutes = remaining.inMinutes;
    return 'Selesaikan dalam sekitar $minutes menit.';
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final waitingForPayment = order?.paymentState.isAwaitingCustomer == true;
    final snapSession = SnapCheckoutSession.tryParse(
      order?.paymentRedirectUrl,
      snapToken: order?.paymentSnapToken,
    );
    final qrUri = _paymentQrUri(order);
    final simulatorQrUri = _simulatorQrUri(order);
    return PopScope(
      canPop: !_creating,
      child: StatusBarStyle.light(
        child: Scaffold(
          backgroundColor: AppColors.green,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
              children: [
                Center(child: _statusIcon(waitingForPayment)),
                const SizedBox(height: 24),
                Text(
                  waitingForPayment
                      ? 'Selesaikan pembayaran'
                      : 'Menyiapkan pembayaran…',
                  textAlign: TextAlign.center,
                  style: AppText.display(23, color: AppColors.cream),
                ),
                const SizedBox(height: 9),
                Text(
                  waitingForPayment
                      ? _expiryLabel
                      : 'Pesanan dan total sedang diverifikasi secara aman.',
                  textAlign: TextAlign.center,
                  style: AppText.ui(
                    14,
                    color: AppColors.greenMuted,
                    height: 1.5,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppText.ui(12.5, color: AppColors.danger),
                      ),
                    ),
                  ),
                ],
                if (waitingForPayment && order != null) ...[
                  const SizedBox(height: 22),
                  if (snapSession != null)
                    _snapCard(snapSession)
                  else
                    _qrisCard(order),
                  if (simulatorQrUri != null) ...[
                    const SizedBox(height: 14),
                    _simulatorQrCard(simulatorQrUri),
                  ],
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: snapSession != null
                        ? 'Muat ulang halaman pembayaran'
                        : qrUri == null
                        ? (_creating
                              ? 'Membuat pembayaran…'
                              : 'Coba buat pembayaran lagi')
                        : 'Salin URL QRIS lama',
                    icon: Icon(
                      snapSession != null || qrUri == null
                          ? Icons.refresh_rounded
                          : Icons.copy_rounded,
                      size: 19,
                    ),
                    background: AppColors.amber,
                    foreground: AppColors.green,
                    onTap: _busy
                        ? null
                        : snapSession != null
                        ? _reloadSnapCheckout
                        : qrUri == null
                        ? _retryPaymentCreation
                        : _copyPaymentQrUrl,
                  ),
                  const SizedBox(height: 8),
                  GhostButton(
                    label: _checking ? 'Memeriksa…' : 'Cek status pembayaran',
                    color: AppColors.greenMuted,
                    onTap: _busy ? null : _checkStatus,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pembayaran hanya dianggap lunas setelah server memverifikasi status Midtrans.',
                    textAlign: TextAlign.center,
                    style: AppText.ui(
                      11.5,
                      color: AppColors.greenMutedDeep,
                      height: 1.4,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 42),
                  const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _snapCard(SnapCheckoutSession session) {
    return Semantics(
      label: 'Checkout QRIS Midtrans di dalam aplikasi',
      child: Container(
        key: const ValueKey('snap-checkout-card'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.amber, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Column(
                children: [
                  Text(
                    'Pembayaran QRIS aman',
                    style: AppText.ui(15, weight: 800, color: AppColors.green),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Pilih QRIS lalu selesaikan pembayaran di halaman Midtrans berikut.',
                    textAlign: TextAlign.center,
                    style: AppText.ui(12.5, color: AppColors.body, height: 1.4),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 560,
              child: SnapCheckoutView(
                key: ValueKey(
                  'snap-${session.environment}-${session.token}-$_snapReloadEpoch',
                ),
                session: session,
                onStatusHint: _handleSnapStatusHint,
                onError: _handleSnapError,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simulatorQrCard(Uri uri) {
    return Container(
      key: const ValueKey('sandbox-simulator-qris-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.science_outlined,
                color: AppColors.green,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alat uji QRIS Sandbox',
                  style: AppText.ui(13.5, weight: 800, color: AppColors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Salin URL gambar ini ke QRIS Simulator Midtrans.',
            style: AppText.ui(12, color: AppColors.body, height: 1.4),
          ),
          const SizedBox(height: 9),
          SelectableText(
            uri.toString(),
            key: const ValueKey('sandbox-simulator-qris-url'),
            style: AppText.ui(10.5, color: AppColors.greenBright, height: 1.35),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: const ValueKey('sandbox-simulator-qris-copy'),
              onPressed: _copySimulatorQrUrl,
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Salin URL'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrisCard(OrderRecord order) {
    final qrUri = _paymentQrUri(order);
    return Semantics(
      label: 'Kode QRIS pembayaran lama',
      child: Container(
        key: const ValueKey('qris-card'),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.amber, width: 2),
        ),
        child: qrUri == null
            ? Column(
                children: [
                  const Icon(
                    Icons.qr_code_2_rounded,
                    size: 64,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Halaman pembayaran belum tersedia. Coba buat pembayaran lagi.',
                    textAlign: TextAlign.center,
                    style: AppText.ui(13, color: AppColors.body, height: 1.45),
                  ),
                ],
              )
            : Column(
                children: [
                  Text(
                    'Pindai kode QRIS',
                    style: AppText.ui(15, weight: 800, color: AppColors.green),
                  ),
                  const SizedBox(height: 14),
                  SizedBox.square(
                    dimension: 220,
                    child: Image.network(
                      qrUri.toString(),
                      key: const ValueKey('qris-image'),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.green,
                            strokeWidth: 3,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.cream,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Gambar QRIS lama belum dapat dimuat. Salin URL di bawah untuk kebutuhan pemulihan.',
                          textAlign: TextAlign.center,
                          style: AppText.ui(
                            12.5,
                            color: AppColors.body,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'URL QRIS',
                      style: AppText.ui(
                        11.5,
                        weight: 700,
                        color: AppColors.body,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SelectableText(
                    qrUri.toString(),
                    key: const ValueKey('qris-url-text'),
                    style: AppText.ui(
                      11,
                      color: AppColors.greenBright,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _statusIcon(bool waitingForPayment) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: AppColors.greenDark,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.amber, width: 4),
      ),
      child: Icon(
        waitingForPayment ? Icons.qr_code_2_rounded : Icons.lock_clock_outlined,
        size: 38,
        color: AppColors.amber,
      ),
    );
  }
}
