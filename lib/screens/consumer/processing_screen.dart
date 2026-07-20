import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';
import 'payment_failed_screen.dart';

/// Membuat satu reservation idempoten, membuka halaman Snap di browser sistem,
/// lalu hanya melanjutkan setelah backend memverifikasi status ke Midtrans.
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
  OrderRecord? _order;
  Timer? _pollTimer;
  bool _creating = false;
  bool _opening = false;
  bool _checking = false;
  bool _navigated = false;
  String? _error;

  bool get _busy => _creating || _opening || _checking;

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
    // Jangan polling ketika browser/payment app sedang berada di depan.
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
        await _handleStatus(existing, openWhenPending: true);
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
      await _handleStatus(order, openWhenPending: true);
    } on BackendException catch (error) {
      if (mounted) _showFailure(error.message, retrySameRequest: true);
    } catch (_) {
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

  Future<void> _handleStatus(
    OrderRecord order, {
    bool openWhenPending = false,
  }) async {
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
    if (openWhenPending) await _openPayment();
  }

  void _startPolling() {
    if (!appState.usesRemoteBackend || _pollTimer?.isActive == true) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) unawaited(_checkStatus());
    });
  }

  Future<void> _openPayment() async {
    final order = _order;
    if (_opening || order == null || !mounted) return;
    final rawUrl = order.paymentRedirectUrl;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'midtrans.com' || uri.host.endsWith('.midtrans.com'))) {
      setState(() {
        _error =
            'Tautan pembayaran belum tersedia. Tekan “Cek status” untuk mencoba lagi.';
      });
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() {
          _error = 'Browser pembayaran tidak dapat dibuka. Coba lagi.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Browser pembayaran tidak dapat dibuka. Coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
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
    PaymentState.refunded => 'Pembayaran telah dikembalikan.',
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
    if (expiresAt == null) return 'Selesaikan pembayaran di halaman Midtrans.';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return 'Waktu pembayaran telah berakhir.';
    final minutes = remaining.inMinutes;
    return 'Selesaikan dalam sekitar $minutes menit.';
  }

  @override
  Widget build(BuildContext context) {
    final waitingForPayment = _order?.paymentState.isAwaitingCustomer == true;
    return PopScope(
      canPop: !_creating,
      child: StatusBarStyle.light(
        child: Scaffold(
          backgroundColor: AppColors.green,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                children: [
                  const Spacer(),
                  _statusIcon(waitingForPayment),
                  const SizedBox(height: 28),
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
                  const Spacer(),
                  if (waitingForPayment) ...[
                    PrimaryButton(
                      label: _opening
                          ? 'Membuka Midtrans…'
                          : 'Buka halaman pembayaran',
                      onTap: _busy ? null : _openPayment,
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: _checking ? 'Memeriksa…' : 'Cek status pembayaran',
                      color: AppColors.greenMuted,
                      onTap: _busy ? null : _checkStatus,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Status hanya dikonfirmasi dari server Midtrans, bukan dari tautan kembali.',
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                        11.5,
                        color: AppColors.greenMutedDeep,
                        height: 1.4,
                      ),
                    ),
                  ] else
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.amber,
                      ),
                    ),
                ],
              ),
            ),
          ),
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
        waitingForPayment
            ? Icons.open_in_browser_rounded
            : Icons.lock_clock_outlined,
        size: 38,
        color: AppColors.amber,
      ),
    );
  }
}
