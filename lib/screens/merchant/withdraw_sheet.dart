import 'package:flutter/material.dart';
import '../../sb.dart';

/// C8 Tarik Dana. Pola: BOTTOM SHEET.
class WithdrawSheet extends StatefulWidget {
  const WithdrawSheet({super.key});

  @override
  State<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<WithdrawSheet> {
  int _amount = 1; // 0 Rp500rb, 1 Rp1jt, 2 Semua saldo

  static const int _fee = 2500;

  @override
  Widget build(BuildContext context) {
    final amounts = [500000, 1000000, appState.balance];
    final amount = amounts[_amount];
    final amountGrouped = formatRupiah(amount).replaceFirst('Rp', '');
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, 32 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          const Center(child: SheetHandle()),
          const SizedBox(height: 6),
          Text('Tarik dana', style: AppText.display(22, weight: 800)),
          const SizedBox(height: 20),

          // Saldo tersedia
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo tersedia',
                    style: AppText.ui(12.5, color: AppColors.greenMuted)),
                ListenableBuilder(
                  listenable: appState,
                  builder: (context, _) => Text(formatRupiah(appState.balance),
                      style: AppText.display(28, color: AppColors.cream)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Jumlah penarikan
          const FieldLabel('Jumlah penarikan'),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.greenBright, width: 1.5),
            ),
            child: Row(
              children: [
                Text('Rp',
                    style: AppText.ui(16, weight: 700, color: AppColors.muted)),
                const SizedBox(width: 6),
                Text(amountGrouped, style: AppText.display(20)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                _AmountChip(
                  label: const ['Rp500rb', 'Rp1jt', 'Semua saldo'][i],
                  selected: _amount == i,
                  onTap: () => setState(() => _amount = i),
                ),
                if (i != 2) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // Rekening tujuan
          const FieldLabel('Rekening tujuan'),
          Container(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.bca,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListenableBuilder(
                        listenable: appState,
                        builder: (context, _) => Text(appState.selectedBank,
                            style: AppText.ui(13.5,
                                weight: 700, color: AppColors.ink)),
                      ),
                      Text('a.n. Ilham Hidayat',
                          style: AppText.ui(12, color: AppColors.muted)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showBankPicker(context),
                  child: Text('Ubah',
                      style: AppText.ui(13,
                          weight: 700, color: AppColors.greenBright)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Biaya admin
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.neutralChip,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Biaya admin transfer',
                    style: AppText.ui(13, color: AppColors.body)),
                Text('Rp2.500',
                    style: AppText.ui(13, weight: 700, color: AppColors.ink)),
              ],
            ),
          ),
          const SizedBox(height: 22),

          PrimaryButton.merchant(
            label: 'Tarik ${formatRupiah(amount - _fee)}',
            onTap: () => Navigator.of(context).pop(amount),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Dana masuk 1–2 hari kerja.',
                style: AppText.ui(12, color: AppColors.captionWarm)),
          ),
          ],
        ),
      ),
    );
  }

  void _showBankPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C0F231C),
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cream,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 14, 24, 24 + MediaQuery.of(sheetContext).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 12),
            Text('Pilih rekening', style: AppText.display(20, weight: 800)),
            const SizedBox(height: 16),
            for (final bank in AppState.bankAccounts)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  appState.setBank(bank);
                  Navigator.of(sheetContext).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.bca,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(bank,
                            style: AppText.ui(13.5,
                                weight: 700, color: AppColors.ink)),
                      ),
                      if (appState.selectedBank == bank)
                        Icon(Icons.check_rounded,
                            size: 20, color: AppColors.greenBright),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chip kecil pada baris jumlah penarikan (gaya SelectChip, padding lebih kecil).
class _AmountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AmountChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.green : AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: selected
              ? null
              : Border.all(color: AppColors.chipBorder, width: 1),
        ),
        child: Text(
          label,
          style: AppText.ui(12.5,
              weight: selected ? 700 : 600,
              color: selected ? AppColors.white : AppColors.body2),
        ),
      ),
    );
  }
}
