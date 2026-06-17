import 'dart:async';
import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B6 Voucher & QR. Pola: LAYAR PENUH (Scaffold sendiri).
class VoucherScreen extends StatefulWidget {
  final OrderRecord order;
  const VoucherScreen({super.key, required this.order});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  Timer? _timer;
  int _remaining = 72 * 60; // 1j 12m dalam detik

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) _remaining--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _remainingLabel {
    final hours = _remaining ~/ 3600;
    final minutes = (_remaining % 3600) ~/ 60;
    final seconds = _remaining % 60;
    if (_remaining < 3600) {
      return '${minutes}m ${seconds}d';
    }
    return '${hours}j ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: AppColors.green,
        body: ListView(
          padding: EdgeInsets.fromLTRB(
              24, topInset + 16, 24, 32 + MediaQuery.of(context).padding.bottom),
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: const BoxDecoration(
                  color: AppColors.greenBright,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 34, color: AppColors.white),
              ),
            ),
            Center(
              child: Text('Pembayaran berhasil!',
                  style:
                      AppText.display(23, weight: 800, color: AppColors.cream)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('Tunjukkan QR ini ke kasir saat ambil bag.',
                  textAlign: TextAlign.center,
                  style: AppText.ui(13.5, color: AppColors.greenMuted)),
            ),
            const SizedBox(height: 24),
            _ticketCard(),
            const SizedBox(height: 18),
            _timerPill(),
            const SizedBox(height: 18),
            GhostButton(
              label: 'Lihat pesanan saya',
              color: AppColors.greenMuted,
              onTap: () => AppNav.toOrders(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticketCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Center(child: QrBox(data: widget.order.code, size: 190)),
          const SizedBox(height: 16),
          Text('Kode pickup',
              style: AppText.ui(12, weight: 600, color: AppColors.muted)),
          Text(widget.order.code,
              style: AppText.display(26,
                  weight: 800, color: AppColors.ink, letterSpacing: 4)),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 16),
            color: AppColors.border,
          ),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: FoodImage(widget.order.bag.image, width: 38, height: 38),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.order.bag.merchant.name,
                        style:
                            AppText.ui(14, weight: 700, color: AppColors.ink)),
                    Text('${widget.order.quantity}× ${widget.order.bag.title}',
                        style: AppText.ui(12.5, color: AppColors.body)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timerPill() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.greenDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 16, color: AppColors.amber),
            const SizedBox(width: 8),
            Text('Ambil sebelum 21.00 — sisa $_remainingLabel',
                style: AppText.ui(13.5,
                    weight: 700, color: AppColors.goldOnDark)),
          ],
        ),
      ),
    );
  }
}
