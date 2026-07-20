import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Simbol SaveBite resmi yang diturunkan dari artwork aplikasi.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Semantics(
      image: true,
      label: 'Logo SaveBite',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/images/savebite_mark.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
        ),
      ),
    );
  }
}

/// Logo + wordmark "SaveBite" berdampingan.
class AppLogoWordmark extends StatelessWidget {
  final double logoSize;
  final double textSize;
  final Color textColor;

  const AppLogoWordmark({
    super.key,
    this.logoSize = 30,
    this.textSize = 19,
    this.textColor = AppColors.green,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        SizedBox(width: logoSize * 0.3),
        Text(
          'SaveBite',
          style: AppText.display(
            textSize,
            weight: 800,
            color: textColor,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
