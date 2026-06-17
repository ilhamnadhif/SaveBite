import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B5b Pembayaran gagal. Pola: LAYAR PENUH (Scaffold sendiri).
class PaymentFailedScreen extends StatelessWidget {
  final Bag bag;
  final String method;
  const PaymentFailedScreen({super.key, required this.bag, required this.method});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: Scaffold(
      backgroundColor: AppColors.cream,
      body: Padding(
        padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top-left X
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Icon(Icons.close, size: 22, color: AppColors.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    margin: const EdgeInsets.only(bottom: 22),
                    decoration: const BoxDecoration(
                      color: AppColors.dangerBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.error_outline,
                        size: 44, color: AppColors.danger),
                  ),
                  Text('Pembayaran gagal',
                      textAlign: TextAlign.center,
                      style: AppText.display(23, weight: 800, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 290),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: AppText.ui(14, color: AppColors.body, height: 1.55),
                        children: [
                          TextSpan(
                              text:
                                  'Saldo $method-mu tidak mencukupi. Bag belum dipesan dan kamu '),
                          TextSpan(
                            text: 'tidak dikenai biaya',
                            style: AppText.ui(14,
                                weight: 700, color: AppColors.body, height: 1.55),
                          ),
                          const TextSpan(
                              text: '. Coba metode lain, ya.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _itemCard(),
                ],
              ),
            ),
            PrimaryButton(
              label: 'Coba metode lain',
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Batalkan pesanan',
              onTap: () => AppNav.toConsumerHome(context),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _itemCard() {
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
            child: FoodImage(bag.image, width: 46, height: 46),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bag.title,
                    style: AppText.ui(13.5, weight: 700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('Masih tersisa ${bag.quantityLeft} — buruan sebelum habis',
                    style: AppText.ui(12, color: AppColors.body)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
