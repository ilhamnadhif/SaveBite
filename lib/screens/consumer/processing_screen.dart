import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';
import 'payment_failed_screen.dart';

/// Menyimpan pesanan dalam mode simulasi pembayaran. Kunci idempotensi dibuat
/// satu kali per instance dan dipertahankan saat retry agar respons yang hilang
/// tidak menghasilkan pesanan ganda.
class ProcessingScreen extends StatefulWidget {
  final Bag bag;
  final int qty;
  final String method;
  final String? idempotencyKey;

  /// Dipertahankan hanya agar pemanggil lama tetap source-compatible. Nilainya
  /// sengaja diabaikan; tidak ada lagi metode yang dibuat gagal secara palsu.
  @Deprecated('Kegagalan simulasi buatan sudah dihapus')
  final bool willFail;

  const ProcessingScreen({
    super.key,
    required this.bag,
    required this.qty,
    required this.method,
    this.idempotencyKey,
    this.willFail = false,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  late final String _idempotencyKey =
      widget.idempotencyKey ??
      'order-${DateTime.now().microsecondsSinceEpoch}-${widget.bag.id}';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _process());
  }

  Future<void> _process() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      // Sedikit jeda hanya untuk memberi waktu UI menjelaskan bahwa ini mode
      // simulasi; tidak ada koneksi palsu ke penyedia pembayaran.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final order = await appState.placeOrder(
        widget.bag,
        widget.qty,
        widget.method,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      AppNav.toVoucher(context, order, replace: true);
    } on BackendException catch (error) {
      if (!mounted) return;
      _showFailure(error.message);
    } catch (_) {
      if (!mounted) return;
      _showFailure(
        'Pesanan belum dapat dikonfirmasi. Periksa koneksi lalu coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFailure(String message) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PaymentFailedScreen(
          bag: widget.bag,
          method: widget.method,
          qty: widget.qty,
          idempotencyKey: _idempotencyKey,
          message: message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: StatusBarStyle.light(
        child: Scaffold(
          backgroundColor: AppColors.green,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.16),
                      radius: .62,
                      colors: [
                        AppColors.greenBright.withValues(alpha: .3),
                        AppColors.greenBright.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _loader(),
                      const SizedBox(height: 28),
                      Text(
                        'Menyimpan pesanan…',
                        textAlign: TextAlign.center,
                        style: AppText.display(22, color: AppColors.cream),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Mode simulasi ${widget.method}. Tidak ada dana nyata '
                        'yang dipindahkan.',
                        textAlign: TextAlign.center,
                        style: AppText.ui(
                          14,
                          color: AppColors.greenMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 32,
                right: 32,
                bottom: 32 + MediaQuery.of(context).padding.bottom,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.science_outlined,
                      size: 15,
                      color: AppColors.greenMutedDeep,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Payment gateway belum diaktifkan',
                        textAlign: TextAlign.center,
                        style: AppText.ui(
                          12.5,
                          color: AppColors.greenMutedDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loader() {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.greenDark, width: 5),
            ),
          ),
          const SizedBox(
            width: 84,
            height: 84,
            child: CircularProgressIndicator(
              strokeWidth: 5,
              color: AppColors.amber,
              backgroundColor: Colors.transparent,
            ),
          ),
          const Icon(
            Icons.shopping_bag_outlined,
            size: 30,
            color: AppColors.greenMuted,
          ),
        ],
      ),
    );
  }
}
