import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';
import 'withdraw_sheet.dart';

/// Saldo merchant, ledger transaksi, rekening, dan permintaan payout manual.
class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  bool _withdrawing = false;

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                if (appState.isLoadingBalance &&
                    appState.transactions.isEmpty &&
                    appState.bankAccountRecords.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return RefreshIndicator(
                  color: AppColors.terracotta,
                  onRefresh: appState.loadBalance,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                    children: [
                      if (appState.balanceError != null) ...[
                        _errorCard(context, appState.balanceError!),
                        const SizedBox(height: 14),
                      ],
                      _balanceCard(context),
                      const SizedBox(height: 16),
                      _statRow(),
                      const SizedBox(height: 20),
                      _sectionTitle(
                        'REKENING PENARIKAN',
                        action: 'Tambah',
                        onAction: () => _addBank(context),
                      ),
                      const SizedBox(height: 10),
                      _bankAccountsCard(context),
                      if (appState.payoutRequests.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _sectionTitle('PERMINTAAN PENARIKAN'),
                        const SizedBox(height: 10),
                        _payoutList(),
                      ],
                      const SizedBox(height: 20),
                      _sectionTitle('RIWAYAT TRANSAKSI'),
                      const SizedBox(height: 10),
                      _transactionList(),
                    ],
                  ),
                );
              },
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
        20,
        MediaQuery.of(context).padding.top + 14,
        20,
        14,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Saldo', style: AppText.display(24, weight: 800)),
          ),
          if (appState.isLoadingBalance)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _balanceCard(BuildContext context) {
    final verifiedAccount = appState.selectedBankAccount?.verified == true;
    final payoutEnabled = appState.businessConfig.payoutsEnabled;
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
                  Text(
                    'Saldo tersedia',
                    style: AppText.ui(13, color: AppColors.greenMuted),
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    label: 'Saldo tersedia ${formatRupiah(appState.balance)}',
                    child: Text(
                      formatRupiah(appState.balance),
                      style: AppText.display(
                        36,
                        weight: 800,
                        color: AppColors.cream,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Payout otomatis belum aktif. Permintaan diproses manual.',
                    style: AppText.ui(
                      11.5,
                      color: AppColors.greenMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _withdrawing || !payoutEnabled
                          ? null
                          : () => _startWithdrawal(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: AppColors.green,
                        disabledBackgroundColor: AppColors.amber.withAlpha(150),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _withdrawing
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.green,
                              ),
                            )
                          : const Icon(
                              Icons.account_balance_outlined,
                              size: 19,
                            ),
                      label: Text(
                        _withdrawing
                            ? 'Mengajukan…'
                            : !payoutEnabled
                            ? 'Payout belum diaktifkan'
                            : verifiedAccount
                            ? 'Tarik dana'
                            : 'Atur rekening penarikan',
                        style: AppText.ui(
                          14.5,
                          weight: 800,
                          color: AppColors.green,
                        ),
                      ),
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
    final completedBags = appState.redeemedBagCount;
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'Pendapatan bulan ini',
            formatRupiah(appState.incomeThisMonth),
            AppColors.ink,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'Bag selesai diambil',
            '$completedBags',
            AppColors.greenBright,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color valueColor) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            style: AppText.ui(11.5, weight: 600, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.display(18, weight: 800, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? action, VoidCallback? onAction}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppText.ui(
              12.5,
              weight: 700,
              color: AppColors.muted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.greenBright,
            ),
            child: Text(action),
          ),
      ],
    );
  }

  Widget _bankAccountsCard(BuildContext context) {
    final accounts = appState.bankAccountRecords;
    if (accounts.isEmpty) {
      return AppCard(
        radius: 18,
        child: Column(
          children: [
            const Icon(
              Icons.account_balance_outlined,
              size: 32,
              color: AppColors.muted,
            ),
            const SizedBox(height: 9),
            Text(
              'Belum ada rekening',
              style: AppText.ui(14, weight: 700, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Tambahkan rekening atas nama pemilik toko untuk mengajukan payout.',
              textAlign: TextAlign.center,
              style: AppText.ui(12.5, color: AppColors.body, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _addBank(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah rekening'),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < accounts.length; i++)
            _bankRow(accounts[i], last: i == accounts.length - 1),
        ],
      ),
    );
  }

  Widget _bankRow(BankAccount account, {required bool last}) {
    final selected = appState.selectedBankAccount?.id == account.id;
    final (statusLabel, statusIcon, statusColor) = switch (account.status) {
      BankAccountStatus.verified => (
        'Terverifikasi',
        Icons.verified_rounded,
        AppColors.greenAccent,
      ),
      BankAccountStatus.rejected => (
        'Ditolak — periksa kembali data',
        Icons.error_outline_rounded,
        AppColors.danger,
      ),
      BankAccountStatus.disabled => (
        'Dinonaktifkan',
        Icons.block_rounded,
        AppColors.muted,
      ),
      BankAccountStatus.pending => (
        'Menunggu verifikasi manual',
        Icons.schedule_rounded,
        AppColors.terracotta,
      ),
    };
    return Material(
      color: selected ? AppColors.greenSoftBg : AppColors.white,
      child: InkWell(
        onTap: () => _selectBankAccount(account),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.bca,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  account.bankCode.length > 4
                      ? account.bankCode.substring(0, 4)
                      : account.bankCode,
                  style: AppText.ui(9.5, weight: 800, color: AppColors.white),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.label,
                      style: AppText.ui(
                        13.5,
                        weight: 700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.accountHolder,
                      style: AppText.ui(11.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: AppText.ui(
                            10.5,
                            weight: 700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.greenBright,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectBankAccount(BankAccount account) async {
    try {
      await appState.setBankAccount(account);
    } on BackendException catch (error) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        error.message,
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Widget _payoutList() {
    final payouts = appState.payoutRequests;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < payouts.length; i++)
            _payoutRow(payouts[i], last: i == payouts.length - 1),
        ],
      ),
    );
  }

  Widget _payoutRow(PayoutRequest payout, {required bool last}) {
    final (label, color, icon) = switch (payout.status) {
      PayoutStatus.pending => (
        'Menunggu proses manual',
        AppColors.terracotta,
        Icons.schedule_rounded,
      ),
      PayoutStatus.processing => (
        'Sedang diproses',
        AppColors.greenBright,
        Icons.sync_rounded,
      ),
      PayoutStatus.paid => (
        'Sudah ditransfer',
        AppColors.greenBright,
        Icons.check_circle_rounded,
      ),
      PayoutStatus.failed => (
        'Gagal',
        AppColors.danger,
        Icons.error_outline_rounded,
      ),
      PayoutStatus.cancelled => (
        'Dibatalkan',
        AppColors.muted,
        Icons.cancel_outlined,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatRupiah(payout.grossAmount),
                  style: AppText.ui(13.5, weight: 800, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${payout.bankAccount.label} · diterima ${formatRupiah(payout.netAmount)}',
                  style: AppText.ui(11.5, color: AppColors.body),
                ),
                const SizedBox(height: 4),
                Text(label, style: AppText.ui(11, weight: 700, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transactionList() {
    final txs = appState.transactions;
    if (txs.isEmpty) {
      return AppCard(
        radius: 18,
        child: Column(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.muted,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'Belum ada transaksi',
              style: AppText.ui(14, weight: 700, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Pendapatan order dan payout akan tercatat di sini.',
              textAlign: TextAlign.center,
              style: AppText.ui(12.5, color: AppColors.body),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < txs.length; i++)
            _txRow(txs[i], last: i == txs.length - 1),
        ],
      ),
    );
  }

  Widget _txRow(TxRecord transaction, {required bool last}) {
    final income = transaction.kind == TxKind.income;
    final reversal = transaction.kind == TxKind.reversal;
    final incoming = income || reversal;
    final pending = transaction.status == 'pending';
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: reversal
                  ? AppColors.ratingBg
                  : income
                  ? AppColors.greenSoftBg
                  : AppColors.dangerTintBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              reversal
                  ? Icons.undo_rounded
                  : income
                  ? Icons.south_rounded
                  : Icons.north_rounded,
              size: 18,
              color: reversal
                  ? AppColors.terracotta
                  : income
                  ? AppColors.greenAccent
                  : AppColors.danger,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title.trim().isEmpty
                      ? reversal
                            ? 'Pengembalian saldo payout'
                            : income
                            ? 'Pendapatan order'
                            : 'Penarikan saldo'
                      : transaction.title,
                  style: AppText.ui(13.5, weight: 700, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  transaction.subtitle,
                  style: AppText.ui(11.5, color: AppColors.muted),
                ),
                if (pending) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Menunggu proses manual',
                    style: AppText.ui(
                      10.5,
                      weight: 700,
                      color: AppColors.terracotta,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            incoming
                ? '+${formatRupiah(transaction.amount)}'
                : '−${formatRupiah(transaction.amount)}',
            style: AppText.ui(
              13.5,
              weight: 800,
              color: reversal
                  ? AppColors.terracotta
                  : income
                  ? AppColors.greenAccent
                  : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.dangerTintBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: AppText.ui(12.5, color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: appState.loadBalance,
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }

  Future<void> _addBank(BuildContext context) async {
    final account = await showAddBankAccountSheet(context);
    if (account != null && context.mounted) {
      AppFeedback.snack(
        context,
        'Rekening ditambahkan dan menunggu verifikasi manual.',
        icon: Icons.schedule_rounded,
      );
    }
  }

  Future<void> _startWithdrawal(BuildContext context) async {
    if (appState.selectedBankAccount == null) {
      await _addBank(context);
      return;
    }
    if (appState.selectedBankAccount?.verified != true) {
      AppFeedback.snack(
        context,
        'Pilih rekening yang sudah terverifikasi untuk menarik saldo.',
        icon: Icons.verified_user_outlined,
      );
      return;
    }

    final amount = await AppNav.showWithdraw(context);
    if (amount == null || !context.mounted) return;
    setState(() => _withdrawing = true);
    try {
      final request = await appState.withdraw(amount);
      if (!context.mounted) return;
      AppNav.toWithdrawSuccess(context, request: request);
    } catch (error) {
      if (!context.mounted) return;
      final message = error is BackendException
          ? error.message
          : 'Permintaan penarikan belum dapat dibuat. Coba lagi.';
      AppFeedback.snack(context, message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }
}
