import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';
import 'processing_screen.dart';

/// Pesanan gagal dikonfirmasi. Retry membawa kunci idempotensi yang sama untuk
/// mencegah duplikasi jika server sebenarnya sudah menerima percobaan pertama.
class PaymentFailedScreen extends StatefulWidget {
  final Bag bag;
  final String method;
  final int qty;
  final String? idempotencyKey;
  final String? message;

  const PaymentFailedScreen({
    super.key,
    required this.bag,
    required this.method,
    this.qty = 1,
    this.idempotencyKey,
    this.message,
  });

  @override
  State<PaymentFailedScreen> createState() => _PaymentFailedScreenState();
}

class _PaymentFailedScreenState extends State<PaymentFailedScreen> {
  bool _navigating = false;

  void _retry() {
    if (_navigating) return;
    setState(() => _navigating = true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProcessingScreen(
          bag: widget.bag,
          qty: widget.qty,
          method: widget.method,
          idempotencyKey: widget.idempotencyKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Padding(
          padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Kembali ke checkout',
                    onPressed: _navigating
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.close,
                      size: 22,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height * .58,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          margin: const EdgeInsets.only(bottom: 22),
                          decoration: const BoxDecoration(
                            color: AppColors.dangerBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline,
                            size: 44,
                            color: AppColors.danger,
                          ),
                        ),
                        Text(
                          'Pesanan belum berhasil',
                          textAlign: TextAlign.center,
                          style: AppText.display(
                            23,
                            weight: 800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 310),
                          child: Text(
                            widget.message ??
                                'Pesanan belum dapat dikonfirmasi. Periksa '
                                    'koneksi lalu coba lagi.',
                            textAlign: TextAlign.center,
                            style: AppText.ui(
                              14,
                              color: AppColors.body,
                              height: 1.55,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Mode simulasi tidak mendebit saldo atau rekening nyata.',
                          textAlign: TextAlign.center,
                          style: AppText.ui(
                            11.8,
                            weight: 650,
                            color: AppColors.muted,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _itemCard(),
                      ],
                    ),
                  ),
                ),
              ),
              PrimaryButton(
                label: _navigating ? 'Mencoba lagi…' : 'Coba lagi',
                onTap: _navigating ? null : _retry,
              ),
              const SizedBox(height: 8),
              GhostButton(
                label: 'Pilih metode lain',
                onTap: _navigating
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
              TextButton(
                onPressed: _navigating
                    ? null
                    : () => AppNav.toConsumerHome(context),
                child: Text(
                  'Kembali ke beranda',
                  style: AppText.ui(12.5, weight: 700, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemCard() {
    final subtotal = widget.bag.salePrice * widget.qty;
    final serviceFee = appState.businessConfig.serviceFee;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: FoodImage(widget.bag.image, width: 46, height: 46),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.bag.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.ui(13.5, weight: 700, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.qty} bag · ${widget.method}',
                  style: AppText.ui(12, color: AppColors.body),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatRupiah(subtotal + serviceFee),
            style: AppText.ui(12.5, weight: 700, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
