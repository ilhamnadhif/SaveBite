import 'package:flutter/material.dart';
import '../../sb.dart';

/// Layar konfirmasi setelah penarikan dana merchant diproses.
class WithdrawSuccessScreen extends StatelessWidget {
  final int amount;
  final String bank;

  const WithdrawSuccessScreen({
    super.key,
    required this.amount,
    required this.bank,
  });

  @override
  Widget build(BuildContext context) {
    const fee = 2500;
    final received = amount - fee;

    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: AppColors.green,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: const BoxDecoration(
                          color: AppColors.greenBright,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 44, color: AppColors.white),
                      ),
                      const SizedBox(height: 24),
                      Text('Penarikan diproses',
                          style: AppText.display(24, color: AppColors.cream)),
                      const SizedBox(height: 10),
                      Text(
                        'Dana akan masuk dalam 1–2 hari kerja.',
                        textAlign: TextAlign.center,
                        style: AppText.ui(14, color: AppColors.greenMuted),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            _row('Jumlah', formatRupiah(amount)),
                            const SizedBox(height: 12),
                            _row('Biaya admin', 'Rp2.500'),
                            const SizedBox(height: 14),
                            const Divider(height: 1, color: AppColors.divider),
                            const SizedBox(height: 14),
                            _row(
                              'Diterima',
                              formatRupiah(received),
                              valueStyle: AppText.ui(15,
                                  weight: 700, color: AppColors.greenAccent),
                            ),
                            const SizedBox(height: 12),
                            _row('Ke rekening', bank),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                PrimaryButton(
                  label: 'Selesai',
                  background: AppColors.amber,
                  foreground: AppColors.green,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {TextStyle? valueStyle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.ui(14, color: AppColors.body)),
        Text(value,
            style: valueStyle ??
                AppText.ui(14, weight: 600, color: AppColors.ink)),
      ],
    );
  }
}
