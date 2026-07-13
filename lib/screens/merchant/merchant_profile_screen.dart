import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';
import 'merchant_shell.dart';

/// Profil merchant, akses operasional toko, serta perpindahan role.
class MerchantProfileScreen extends StatefulWidget {
  const MerchantProfileScreen({super.key});

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  bool _deletingAccount = false;

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => Column(
          children: [
            ColoredHeader(
              background: AppColors.brown,
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
                              appState.storeName.isEmpty
                                  ? 'Toko Anda'
                                  : appState.storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.display(
                                19,
                                weight: 700,
                                color: AppColors.cream,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Merchant · ${appState.storeCategory}',
                              style: AppText.ui(
                                13,
                                color: AppColors.merchantMuted,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${appState.openTime}–${appState.closeTime}',
                              style: AppText.ui(
                                11.5,
                                color: AppColors.merchantMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (appState.isLoadingMerchant)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.amber,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          value: '${appState.bagsSoldToday}',
                          label: 'Bag hari ini',
                          background: AppColors.brownCard,
                          valueColor: AppColors.white,
                          labelColor: AppColors.merchantMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          value: formatRupiah(appState.incomeThisMonth),
                          label: 'Bulan ini',
                          background: AppColors.brownCard,
                          valueColor: AppColors.white,
                          labelColor: AppColors.merchantMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.terracotta,
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    if (appState.errorMessage != null) ...[
                      _errorCard(appState.errorMessage!),
                      const SizedBox(height: 14),
                    ],
                    _roleSwitch(context),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          MenuRow(
                            icon: Icons.storefront_outlined,
                            label: 'Profil & jam toko',
                            onTap: () => AppNav.toEditStore(context),
                          ),
                          MenuRow(
                            icon: Icons.account_balance_outlined,
                            label: 'Rekening & penarikan',
                            onTap: () =>
                                MerchantShellScope.of(context)?.selectTab(3),
                          ),
                          MenuRow(
                            icon: Icons.notifications_none_rounded,
                            label: 'Notifikasi',
                            onTap: () => AppNav.toNotifications(context),
                          ),
                          MenuRow(
                            icon: Icons.reviews_outlined,
                            label: 'Ulasan pelanggan',
                            onTap: () => AppNav.toMerchantReviews(context),
                          ),
                          MenuRow(
                            icon: Icons.help_outline_rounded,
                            label: 'Bantuan',
                            last: true,
                            onTap: () => AppNav.toHelp(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _accountSummary(),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _logout(context),
                      icon: const Icon(Icons.logout_rounded, size: 19),
                      label: const Text('Keluar'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _deletingAccount
                          ? null
                          : () => _deleteAccount(context),
                      child: Text(
                        _deletingAccount ? 'Menghapus akun…' : 'Hapus akun',
                        style: AppText.ui(
                          13,
                          weight: 700,
                          color: AppColors.danger,
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
    final logo = appState.storeLogoUrl;
    if (logo != null && logo.isNotEmpty) {
      return ClipOval(child: FoodImage(logo, width: 58, height: 58));
    }
    return Container(
      width: 58,
      height: 58,
      decoration: const BoxDecoration(
        color: AppColors.amber,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _storeInitials,
        style: AppText.display(20, color: AppColors.brown),
      ),
    );
  }

  String get _storeInitials {
    final parts = appState.storeName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'T';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _roleSwitch(BuildContext context) {
    return Material(
      color: AppColors.greenSoftBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _switchToConsumer(context),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.greenBright.withAlpha(55)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.greenBright,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beralih ke mode pembeli',
                      style: AppText.ui(
                        13.5,
                        weight: 800,
                        color: AppColors.greenAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cari dan pesan Surprise Bag di sekitar Anda.',
                      style: AppText.ui(11.5, color: AppColors.body),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.greenAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountSummary() {
    return AppCard(
      radius: 16,
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appState.userName,
                  style: AppText.ui(13, weight: 700, color: AppColors.ink),
                ),
                if (appState.userEmail.isNotEmpty)
                  Text(
                    appState.userEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(11.5, color: AppColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
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
          TextButton(onPressed: _reload, child: const Text('Coba lagi')),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    await Future.wait([appState.loadStore(), appState.loadMerchantData()]);
  }

  void _switchToConsumer(BuildContext context) {
    appState.switchToConsumer();
    appState.rememberMode('consumer');
    if (appState.locationPrimed) {
      AppNav.toConsumerHome(context);
    } else {
      AppNav.toLocationPriming(context);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Keluar?',
      message: 'Kamu perlu masuk lagi untuk melanjutkan.',
      confirmLabel: 'Keluar',
      destructive: true,
    );
    if (ok && context.mounted) await AppNav.logout(context);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Hapus akun permanen?',
      message:
          'Profil, toko, dan akses akun akan dihapus. Riwayat transaksi '
          'yang wajib disimpan akan dianonimkan. Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Hapus permanen',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    setState(() => _deletingAccount = true);
    try {
      await AppNav.deleteAccount(context);
    } catch (error) {
      if (!context.mounted) return;
      final message = error is BackendException
          ? error.message
          : 'Akun belum dapat dihapus. Coba lagi.';
      AppFeedback.snack(context, message, icon: Icons.error_outline_rounded);
      setState(() => _deletingAccount = false);
    }
  }
}
