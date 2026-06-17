import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B9 Profil — profil konsumen + beralih ke mode merchant.
/// Pola: KONTEN TAB — Column(header + Expanded scroll), tanpa Scaffold.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: Column(
      children: [
        ColoredHeader(
          background: AppColors.green,
          bottomPadding: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListenableBuilder(
                listenable: appState,
                builder: (context, _) => Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: AppColors.amber,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(appState.userInitials,
                          style: AppText.display(22, color: AppColors.green)),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appState.userName,
                            style: AppText.display(19,
                                weight: 700, color: AppColors.cream)),
                        Text(appState.userEmail,
                            style: AppText.ui(13, color: AppColors.greenMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: StatTile(
                      value: '23',
                      label: 'Bag diselamatkan',
                      background: AppColors.greenDark,
                      valueColor: AppColors.amber,
                      labelColor: AppColors.greenMuted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: StatTile(
                      value: 'Rp612rb',
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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              children: [
                _menuCard(context),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () async {
                    final ok = await AppDialog.confirm(
                      context,
                      title: 'Keluar?',
                      message: 'Kamu perlu masuk lagi untuk melanjutkan.',
                      confirmLabel: 'Keluar',
                      destructive: true,
                    );
                    if (ok && context.mounted) AppNav.logout(context);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: Text('Keluar',
                          style: AppText.ui(14,
                              weight: 700, color: AppColors.danger)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _menuCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
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
            onTap: () => AppNav.toNotifications(context),
          ),
          MenuRow(
            icon: Icons.help_outline,
            label: 'Bantuan',
            last: true,
            onTap: () => AppNav.toHelp(context),
          ),
        ],
      ),
    );
  }
}
