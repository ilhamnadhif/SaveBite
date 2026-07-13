import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backend/backend.dart';
import '../../sb.dart';

/// Membuka formulir rekening baru. Rekening baru selalu menunggu verifikasi
/// manual sebelum dapat digunakan untuk penarikan.
Future<BankAccount?> showAddBankAccountSheet(BuildContext context) {
  return showModalBottomSheet<BankAccount>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C0F231C),
    builder: (_) => const _AddBankAccountSheet(),
  );
}

/// C8 Tarik Dana. Penarikan hanya membuat permintaan payout berstatus pending;
/// transfer eksternal diproses manual sampai provider payout tersedia.
class WithdrawSheet extends StatefulWidget {
  const WithdrawSheet({super.key});

  @override
  State<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<WithdrawSheet> {
  int _amountIndex = 2;

  int get _fee => appState.businessConfig.withdrawalFee;
  int get _minimum => appState.businessConfig.minimumWithdrawal;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final choices = <({String label, int amount})>[
          (label: 'Rp500rb', amount: 500000),
          (label: 'Rp1jt', amount: 1000000),
          (label: 'Semua saldo', amount: appState.balance),
        ];
        final amount = choices[_amountIndex].amount;
        final account = appState.selectedBankAccount;
        final validAmount = amount >= _minimum && amount <= appState.balance;
        final canSubmit = validAmount && account?.verified == true;

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            14,
            24,
            24 +
                MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: SheetHandle()),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ajukan penarikan',
                        style: AppText.display(22, weight: 800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _balanceCard(),
                const SizedBox(height: 20),
                const FieldLabel('Jumlah penarikan'),
                _amountField(amount),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < choices.length; i++)
                      _AmountChip(
                        label: choices[i].label,
                        selected: _amountIndex == i,
                        enabled:
                            choices[i].amount >= _minimum &&
                            choices[i].amount <= appState.balance,
                        onTap: () => setState(() => _amountIndex = i),
                      ),
                  ],
                ),
                if (!validAmount) ...[
                  const SizedBox(height: 8),
                  Text(
                    appState.balance < _minimum
                        ? 'Saldo minimum untuk penarikan adalah ${formatRupiah(_minimum)}.'
                        : 'Pilihan jumlah melebihi saldo tersedia.',
                    style: AppText.ui(12, color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: FieldLabel('Rekening tujuan')),
                    TextButton.icon(
                      onPressed: () => _addBank(context),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Tambah'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.greenBright,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                _bankCard(context, account),
                const SizedBox(height: 16),
                _feeSummary(amount),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppColors.neutralChip,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.body,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Permintaan akan berstatus menunggu dan ditinjau '
                          'manual. Transfer otomatis belum tersedia.',
                          style: AppText.ui(
                            12,
                            color: AppColors.body,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                PrimaryButton.merchant(
                  label: canSubmit
                      ? 'Ajukan ${formatRupiah(amount)}'
                      : account == null
                      ? 'Tambahkan rekening dahulu'
                      : account.verified
                      ? 'Jumlah belum memenuhi syarat'
                      : 'Rekening belum terverifikasi',
                  onTap: canSubmit
                      ? () => Navigator.of(context).pop(amount)
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _balanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saldo tersedia',
            style: AppText.ui(12.5, color: AppColors.greenMuted),
          ),
          Text(
            formatRupiah(appState.balance),
            style: AppText.display(28, color: AppColors.cream),
          ),
        ],
      ),
    );
  }

  Widget _amountField(int amount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.greenBright, width: 1.5),
      ),
      child: Text(formatRupiah(amount), style: AppText.display(20)),
    );
  }

  Widget _bankCard(BuildContext context, BankAccount? account) {
    if (account == null) {
      return AppCard(
        radius: 14,
        child: Column(
          children: [
            const Icon(
              Icons.account_balance_outlined,
              color: AppColors.muted,
              size: 30,
            ),
            const SizedBox(height: 8),
            Text(
              'Belum ada rekening',
              style: AppText.ui(13.5, weight: 700, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Tambahkan rekening atas nama pemilik toko.',
              textAlign: TextAlign.center,
              style: AppText.ui(12, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showBankPicker(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _bankIcon(account.bankCode),
              const SizedBox(width: 12),
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
                      style: AppText.ui(12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 5),
                    _verificationBadge(account),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feeSummary(int amount) {
    final net = amount > _fee ? amount - _fee : 0;
    return AppCard(
      radius: 14,
      child: Column(
        children: [
          _summaryLine('Jumlah diajukan', formatRupiah(amount)),
          const SizedBox(height: 10),
          _summaryLine('Biaya admin', '−${formatRupiah(_fee)}'),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          _summaryLine('Estimasi diterima', formatRupiah(net), bold: true),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppText.ui(
              13,
              weight: bold ? 700 : 500,
              color: bold ? AppColors.ink : AppColors.body,
            ),
          ),
        ),
        Text(
          value,
          style: AppText.ui(
            13.5,
            weight: bold ? 800 : 600,
            color: bold ? AppColors.greenAccent : AppColors.ink,
          ),
        ),
      ],
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

  Future<void> _showBankPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C0F231C),
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          14,
          24,
          24 + MediaQuery.of(sheetContext).padding.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 12),
              Text('Pilih rekening', style: AppText.display(20, weight: 800)),
              const SizedBox(height: 12),
              for (final bank in appState.bankAccountRecords)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      try {
                        await appState.setBankAccount(bank);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      } on BackendException catch (error) {
                        if (sheetContext.mounted) {
                          AppFeedback.snack(
                            sheetContext,
                            error.message,
                            icon: Icons.error_outline_rounded,
                          );
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          _bankIcon(bank.bankCode),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bank.label,
                                  style: AppText.ui(
                                    13.5,
                                    weight: 700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _verificationBadge(bank),
                              ],
                            ),
                          ),
                          if (appState.selectedBank == bank.label)
                            const Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: AppColors.greenBright,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  await _addBank(context);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah rekening lain'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.greenBright,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bankIcon(String code) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bca,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        code.length > 4 ? code.substring(0, 4) : code,
        style: AppText.ui(9.5, weight: 800, color: AppColors.white),
      ),
    );
  }

  Widget _verificationBadge(BankAccount account) {
    final (label, icon, color) = switch (account.status) {
      BankAccountStatus.verified => (
        'Terverifikasi',
        Icons.verified_rounded,
        AppColors.greenAccent,
      ),
      BankAccountStatus.rejected => (
        'Ditolak',
        Icons.error_outline_rounded,
        AppColors.danger,
      ),
      BankAccountStatus.disabled => (
        'Dinonaktifkan',
        Icons.block_rounded,
        AppColors.muted,
      ),
      BankAccountStatus.pending => (
        'Menunggu verifikasi',
        Icons.schedule_rounded,
        AppColors.terracotta,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: AppText.ui(10.5, weight: 700, color: color)),
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _AmountChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: enabled ? (_) => onTap() : null,
        selectedColor: AppColors.green,
        backgroundColor: AppColors.white,
        side: BorderSide(
          color: selected ? AppColors.green : AppColors.chipBorder,
        ),
        labelStyle: AppText.ui(
          12.5,
          weight: selected ? 700 : 600,
          color: selected ? AppColors.white : AppColors.body2,
        ),
        showCheckmark: false,
      ),
    );
  }
}

class _AddBankAccountSheet extends StatefulWidget {
  const _AddBankAccountSheet();

  @override
  State<_AddBankAccountSheet> createState() => _AddBankAccountSheetState();
}

class _AddBankAccountSheetState extends State<_AddBankAccountSheet> {
  static const _banks = <String, String>{
    'BCA': 'BCA',
    'MANDIRI': 'Bank Mandiri',
    'BNI': 'BNI',
    'BRI': 'BRI',
    'BSI': 'Bank Syariah Indonesia',
    'PERMATA': 'Bank Permata',
    'CIMB': 'CIMB Niaga',
  };

  final _formKey = GlobalKey<FormState>();
  final _accountNumber = TextEditingController();
  final _accountHolder = TextEditingController();
  String _bankCode = _banks.keys.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _accountNumber.dispose();
    _accountHolder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        24 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tambah rekening',
                      style: AppText.display(21, weight: 800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const FieldLabel('Bank'),
              DropdownButtonFormField<String>(
                initialValue: _bankCode,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: [
                  for (final entry in _banks.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _bankCode = value!),
              ),
              const SizedBox(height: 16),
              const FieldLabel('Nomor rekening'),
              TextFormField(
                controller: _accountNumber,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.creditCardNumber],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  hintText: 'Contoh: 1234567890',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
                validator: (value) {
                  final digits = value?.trim() ?? '';
                  if (digits.length < 8 || digits.length > 20) {
                    return 'Masukkan 8–20 digit nomor rekening.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const FieldLabel('Nama pemilik rekening'),
              TextFormField(
                controller: _accountHolder,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  hintText: 'Sesuai nama pada rekening',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) {
                  if ((value?.trim().length ?? 0) < 3) {
                    return 'Nama pemilik minimal 3 karakter.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppText.ui(12.5, color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.neutralChip,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  'Rekening baru tidak langsung aktif. Tim SaveBite perlu '
                  'memverifikasi kepemilikan rekening secara manual.',
                  style: AppText.ui(12, color: AppColors.body, height: 1.4),
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton.merchant(
                label: _busy ? 'Menyimpan…' : 'Simpan rekening',
                onTap: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await appState.saveBankAccount(
        bankCode: _bankCode,
        bankName: _banks[_bankCode]!,
        accountNumber: _accountNumber.text.trim(),
        accountHolder: _accountHolder.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(account);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is BackendException
            ? error.message
            : 'Rekening belum dapat disimpan. Coba lagi.';
        _busy = false;
      });
    }
  }
}
