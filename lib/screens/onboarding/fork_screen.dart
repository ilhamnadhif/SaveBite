import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// A3 Fork peran. Pola: LAYAR PENUH (Scaffold sendiri).
class ForkScreen extends StatelessWidget {
  const ForkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 0),
                const AppLogoWordmark(logoSize: 30, textSize: 19),
                const SizedBox(height: 36),
                Text(
                  'Mau mulai dari mana?',
                  style: AppText.display(27, color: AppColors.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pilih peranmu. Tenang, bisa diganti kapan saja lewat Profil.',
                  style: AppText.ui(14, color: AppColors.body, height: 1.5),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: Column(
                    children: [
                      _roleCard(
                        background: AppColors.greenSoftBg,
                        borderColor: AppColors.greenSoftBorder,
                        iconBoxColor: AppColors.greenBright,
                        icon: Icons.shopping_bag_outlined,
                        title: 'Saya mau beli',
                        titleColor: AppColors.green,
                        desc:
                            'Temukan Surprise Bag murah dari toko di sekitarmu.',
                        descColor: AppColors.body2,
                        arrowColor: AppColors.greenBright,
                        onTap: () => AppNav.toLogin(context, merchant: false),
                      ),
                      const SizedBox(height: 16),
                      _roleCard(
                        background: AppColors.terracottaSoftBg,
                        borderColor: AppColors.terracottaSoftBorder,
                        iconBoxColor: AppColors.terracotta,
                        icon: Icons.storefront_outlined,
                        title: 'Saya mau jual',
                        titleColor: AppColors.brown,
                        desc:
                            'Ubah stok berlebih jadi cuan, kurangi makanan terbuang.',
                        descColor: AppColors.terracottaText,
                        arrowColor: AppColors.terracotta,
                        onTap: () => AppNav.toLogin(context, merchant: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    'Satu akun bisa jadi pembeli sekaligus penjual.',
                    style: AppText.ui(13, color: AppColors.captionWarm),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleCard({
    required Color background,
    required Color borderColor,
    required Color iconBoxColor,
    required IconData icon,
    required String title,
    required Color titleColor,
    required String desc,
    required Color descColor,
    required Color arrowColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBoxColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 22, color: AppColors.white),
                ),
                const SizedBox(height: 14),
                Text(title, style: AppText.display(20, color: titleColor)),
                const SizedBox(height: 5),
                Text(
                  desc,
                  style: AppText.ui(13.5, color: descColor, height: 1.5),
                ),
              ],
            ),
            Positioned(
              top: 2,
              right: 0,
              child: Icon(Icons.arrow_forward, size: 20, color: arrowColor),
            ),
          ],
        ),
      ),
    );
  }
}
