import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B5a Memproses. Pola: LAYAR PENUH (Scaffold sendiri), stateful.
class ProcessingScreen extends StatefulWidget {
  final Bag bag;
  final int qty;
  final bool willFail;
  final String method;
  const ProcessingScreen({
    super.key,
    required this.bag,
    required this.qty,
    required this.willFail,
    required this.method,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;
      if (widget.willFail) {
        AppNav.toPaymentFailed(context, bag: widget.bag, method: widget.method);
      } else {
        final order =
            await appState.placeOrder(widget.bag, widget.qty, widget.method);
        if (mounted) AppNav.toVoucher(context, order, replace: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: Scaffold(
      backgroundColor: AppColors.green,
      body: Stack(
        children: [
          // Radial glow di belakang konten.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.16),
                  radius: 0.62,
                  colors: [
                    AppColors.greenBright.withValues(alpha: 0.3),
                    AppColors.greenBright.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Konten tengah.
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _loader(),
                  const SizedBox(height: 28),
                  Text(
                    'Memproses pembayaran…',
                    textAlign: TextAlign.center,
                    style: AppText.display(22, color: AppColors.cream),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Menghubungkan ke ${widget.method}. Jangan tutup halaman ini.',
                    textAlign: TextAlign.center,
                    style: AppText.ui(14,
                        color: AppColors.greenMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          // Footer aman & terenkripsi.
          Positioned(
            left: 36,
            right: 36,
            bottom: 36 + MediaQuery.of(context).padding.bottom,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline,
                    size: 14, color: AppColors.greenMutedDeep),
                const SizedBox(width: 9),
                Text('Pembayaran aman & terenkripsi',
                    style: AppText.ui(12.5, color: AppColors.greenMutedDeep)),
              ],
            ),
          ),
        ],
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
          // Cincin dasar.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.greenDark, width: 5),
            ),
          ),
          // Busur amber yang berputar.
          const SizedBox(
            width: 84,
            height: 84,
            child: CircularProgressIndicator(
              strokeWidth: 5,
              color: AppColors.amber,
              backgroundColor: Colors.transparent,
            ),
          ),
          // Ikon shopping bag di tengah.
          const Icon(Icons.shopping_bag_outlined,
              size: 30, color: AppColors.greenMuted),
        ],
      ),
    );
  }
}
