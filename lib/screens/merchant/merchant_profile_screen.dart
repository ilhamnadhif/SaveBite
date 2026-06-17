import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// Profil Merchant — mirror dari B9 Profil (konsumen) namun palet cokelat.
/// Pola: KONTEN TAB — Column(header + Expanded scroll), tanpa Scaffold.
class MerchantProfileScreen extends StatelessWidget {
  const MerchantProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: Column(
      children: [
        ColoredHeader(
          background: AppColors.brown,
          bottomPadding: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                        color: AppColors.amber, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('RN',
                        style: AppText.display(22, color: AppColors.brown)),
                  ),
                  const SizedBox(width: 14),
                  ListenableBuilder(
                    listenable: appState,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appState.storeName,
                            style: AppText.display(19,
                                weight: 700, color: AppColors.cream)),
                        const SizedBox(height: 2),
                        Text('Merchant · ${appState.storeCategory}',
                            style:
                                AppText.ui(13, color: AppColors.merchantMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: const [
                  Expanded(
                    child: StatTile(
                      value: '184',
                      label: 'Bag terselamatkan',
                      background: AppColors.brownCard,
                      valueColor: AppColors.white,
                      labelColor: AppColors.merchantMuted,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      value: 'Rp3,2jt',
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            children: [
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
                        onTap: () => AppNav.toEditStore(context)),
                    MenuRow(
                        icon: Icons.notifications_none,
                        label: 'Notifikasi',
                        onTap: () => AppNav.toNotifications(context)),
                    MenuRow(
                        icon: Icons.help_outline,
                        label: 'Bantuan',
                        last: true,
                        onTap: () => AppNav.toHelp(context)),
                  ],
                ),
              ),
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
      ],
    ),
    );
  }

}
