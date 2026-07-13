import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';
import '../shared/legal_screen.dart';

/// Profil konsumen, pengaturan akun, perpindahan peran, dan kontrol privasi.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _switchingRole = false;
  bool _deletingAccount = false;

  int get _savedBags => appState.orderHistory
      .where((order) => order.status == OrderStatus.done)
      .fold(0, (total, order) => total + order.quantity);

  int get _totalSavings => appState.orderHistory
      .where((order) => order.status == OrderStatus.done)
      .fold(0, (total, order) => total + order.bag.savings * order.quantity);

  Future<void> _switchToMerchant() async {
    if (_switchingRole || _deletingAccount) return;
    setState(() => _switchingRole = true);
    try {
      await AppNav.switchToMerchant(context);
    } catch (_) {
      if (!mounted) return;
      appState.switchToConsumer();
      AppFeedback.snack(
        context,
        'Mode penjual gagal dibuka. Coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _switchingRole = false);
    }
  }

  Future<bool> _confirmDelete() async {
    final controller = TextEditingController();
    var matches = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Hapus akun permanen?',
            style: AppText.display(19, weight: 800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profil, favorit, dan akses akun akan dihapus. Riwayat transaksi '
                'yang wajib disimpan menurut hukum dapat dianonimkan. Tindakan '
                'ini tidak dapat dibatalkan.',
                style: AppText.ui(13.5, color: AppColors.body, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Ketik HAPUS untuk melanjutkan',
                style: AppText.ui(12.5, weight: 700, color: AppColors.body),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (value) {
                  final next = value.trim().toUpperCase() == 'HAPUS';
                  if (next != matches) {
                    setDialogState(() => matches = next);
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'HAPUS',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Batal',
                style: AppText.ui(14, weight: 700, color: AppColors.body),
              ),
            ),
            TextButton(
              onPressed: matches
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(
                'Hapus permanen',
                style: AppText.ui(14, weight: 800, color: AppColors.danger),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount || _switchingRole) return;
    if (!await _confirmDelete() || !mounted) return;
    setState(() => _deletingAccount = true);
    try {
      await AppNav.deleteAccount(context);
    } on BackendException catch (error) {
      if (!mounted) return;
      AppFeedback.snack(context, error.message, icon: Icons.error_outline);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Akun gagal dihapus. Periksa koneksi lalu coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  Future<void> _logout() async {
    if (_deletingAccount) return;
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Keluar?',
      message: 'Kamu perlu masuk lagi untuk melanjutkan.',
      confirmLabel: 'Keluar',
      destructive: true,
    );
    if (confirmed && mounted) await AppNav.logout(context);
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => Column(
          children: [
            ColoredHeader(
              background: AppColors.green,
              bottomPadding: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatar(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appState.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.display(
                                19,
                                weight: 700,
                                color: AppColors.cream,
                              ),
                            ),
                            Text(
                              appState.userEmail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.ui(
                                13,
                                color: AppColors.greenMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          value: '$_savedBags',
                          label: 'Bag diselamatkan',
                          background: AppColors.greenDark,
                          valueColor: AppColors.amber,
                          labelColor: AppColors.greenMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          value: formatRupiah(_totalSavings),
                          label: 'Total hemat',
                          background: AppColors.greenDark,
                          valueColor: AppColors.amber,
                          labelColor: AppColors.greenMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: AppColors.cream,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    _sectionLabel('Akun'),
                    _accountCard(),
                    const SizedBox(height: 18),
                    _sectionLabel('Mode aplikasi'),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: MenuRow(
                        icon: Icons.storefront_outlined,
                        label: _switchingRole
                            ? 'Membuka mode penjual…'
                            : 'Beralih ke mode penjual',
                        last: true,
                        onTap: _switchingRole ? null : _switchToMerchant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel('Informasi & legal'),
                    _informationCard(),
                    const SizedBox(height: 18),
                    _sectionLabel('Privasi akun'),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: MenuRow(
                        icon: Icons.delete_outline,
                        label: _deletingAccount
                            ? 'Menghapus akun…'
                            : 'Hapus akun permanen',
                        last: true,
                        onTap: _deletingAccount ? null : _deleteAccount,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _logout,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'Keluar',
                            style: AppText.ui(
                              14,
                              weight: 700,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    final url = appState.userAvatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 58,
          height: 58,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _initialAvatar(),
        ),
      );
    }
    return _initialAvatar();
  }

  Widget _initialAvatar() {
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(
        color: AppColors.amber,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        appState.userInitials,
        style: AppText.display(22, color: AppColors.green),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: AppText.ui(12, weight: 700, color: AppColors.muted),
      ),
    );
  }

  Widget _accountCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          MenuRow(
            icon: Icons.edit_outlined,
            label: 'Edit profil',
            onTap: () => AppNav.toEditProfile(context),
          ),
          MenuRow(
            icon: Icons.notifications_none,
            label: 'Notifikasi',
            last: true,
            onTap: () => AppNav.toNotifications(context),
          ),
        ],
      ),
    );
  }

  Widget _informationCard() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          MenuRow(
            icon: Icons.help_outline,
            label: 'Bantuan',
            onTap: () => AppNav.toHelp(context),
          ),
          MenuRow(
            icon: Icons.description_outlined,
            label: 'Syarat & Ketentuan',
            onTap: () => AppNav.toLegal(context, document: LegalDocument.terms),
          ),
          MenuRow(
            icon: Icons.privacy_tip_outlined,
            label: 'Kebijakan Privasi',
            onTap: () =>
                AppNav.toLegal(context, document: LegalDocument.privacy),
          ),
          MenuRow(
            icon: Icons.currency_exchange_outlined,
            label: 'Pembatalan & pengembalian dana',
            last: true,
            onTap: () =>
                AppNav.toLegal(context, document: LegalDocument.refundPolicy),
          ),
        ],
      ),
    );
  }
}
