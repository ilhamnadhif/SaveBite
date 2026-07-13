import 'package:flutter/material.dart';

import '../../sb.dart';

/// Konfirmasi bahwa request payout sudah tercatat. Ini bukan konfirmasi bahwa
/// dana sudah ditransfer oleh bank/provider eksternal.
class WithdrawSuccessScreen extends StatelessWidget {
  final PayoutRequest request;

  const WithdrawSuccessScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: AppColors.green,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            MediaQuery.sizeOf(context).height -
                            MediaQuery.paddingOf(context).vertical -
                            150,
                      ),
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
                            child: const Icon(
                              Icons.schedule_rounded,
                              size: 42,
                              color: AppColors.white,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Penarikan diproses',
                            textAlign: TextAlign.center,
                            style: AppText.display(24, color: AppColors.cream),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Permintaan sudah tercatat dan menunggu '
                            'pemeriksaan manual.',
                            textAlign: TextAlign.center,
                            style: AppText.ui(
                              14,
                              color: AppColors.greenMuted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              children: [
                                _row(
                                  'Status',
                                  'Menunggu proses manual',
                                  valueStyle: AppText.ui(
                                    13.5,
                                    weight: 700,
                                    color: AppColors.terracotta,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _row(
                                  'Jumlah diajukan',
                                  formatRupiah(request.grossAmount),
                                ),
                                const SizedBox(height: 12),
                                _row(
                                  'Biaya admin',
                                  formatRupiah(request.feeAmount),
                                ),
                                const SizedBox(height: 14),
                                const Divider(
                                  height: 1,
                                  color: AppColors.divider,
                                ),
                                const SizedBox(height: 14),
                                _row(
                                  'Estimasi diterima',
                                  formatRupiah(request.netAmount),
                                  valueStyle: AppText.ui(
                                    15,
                                    weight: 700,
                                    color: AppColors.greenAccent,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _row('Ke rekening', request.bankAccount.label),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Saldo sudah ditahan untuk mencegah penarikan '
                            'ganda. Status akan diperbarui setelah transfer '
                            'manual diselesaikan.',
                            textAlign: TextAlign.center,
                            style: AppText.ui(
                              11.5,
                              color: AppColors.greenMuted,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: AppText.ui(13.5, color: AppColors.body)),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style:
                valueStyle ??
                AppText.ui(13.5, weight: 600, color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}
