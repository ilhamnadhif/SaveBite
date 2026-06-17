import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// C6 Saldo & Penarikan. Pola: KONTEN TAB — Column(header + Expanded scroll).
class BalanceScreen extends StatelessWidget {
  const BalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  _balanceCard(context),
                  const SizedBox(height: 18),
                  _statRow(),
                  const SizedBox(height: 20),
                  Text(
                    'RIWAYAT TRANSAKSI',
                    style: AppText.ui(12.5,
                        weight: 700,
                        color: AppColors.muted,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  _transactionList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 14, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Text('Saldo', style: AppText.display(24, weight: 800)),
    );
  }

  Widget _balanceCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        color: AppColors.green,
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x40279A6A),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saldo tersedia',
                      style: AppText.ui(13, color: AppColors.greenMuted)),
                  const SizedBox(height: 4),
                  Text(formatRupiah(appState.balance),
                      style: AppText.display(36,
                          weight: 800, color: AppColors.cream)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        final amt = await AppNav.showWithdraw(context);
                        if (amt != null && context.mounted) {
                          appState.withdraw(amt);
                          AppNav.toWithdrawSuccess(context,
                              amount: amt, bank: appState.selectedBank);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: AppColors.green,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text('Tarik dana',
                          style: AppText.ui(15,
                              weight: 800, color: AppColors.green)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'Pendapatan bulan ini',
            'Rp3,2jt',
            AppColors.ink,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'Bag terselamatkan',
            '184',
            AppColors.greenBright,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.ui(11.5, weight: 600, color: AppColors.muted)),
          const SizedBox(height: 3),
          Text(value, style: AppText.display(18, weight: 800, color: valueColor)),
        ],
      ),
    );
  }

  Widget _transactionList() {
    final txs = appState.transactions;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            for (int i = 0; i < txs.length; i++)
              _txRow(txs[i], last: i == txs.length - 1),
          ],
        ),
      ),
    );
  }

  Widget _txRow(TxRecord t, {required bool last}) {
    final income = t.kind == TxKind.income;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: income ? AppColors.greenSoftBg : AppColors.dangerTintBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              income ? Icons.south : Icons.north,
              size: 18,
              color: income ? AppColors.greenAccent : AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title,
                    style: AppText.ui(13.5, weight: 700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(t.subtitle,
                    style: AppText.ui(12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            income
                ? '+${formatRupiah(t.amount)}'
                : '−${formatRupiah(t.amount)}',
            style: AppText.ui(14,
                weight: 800,
                color: income ? AppColors.greenAccent : AppColors.ink),
          ),
        ],
      ),
    );
  }
}
