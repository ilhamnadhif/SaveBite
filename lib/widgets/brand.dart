import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Logo SaveBite: kotak membulat dengan titik amber + daun hijau.
/// Proporsi mengikuti desain (skala terhadap [size]).
class AppLogo extends StatelessWidget {
  final double size;
  final Color background;
  final Color dotColor;
  final Color leafColor;

  const AppLogo({
    super.key,
    this.size = 40,
    this.background = AppColors.green,
    this.dotColor = AppColors.amber,
    this.leafColor = AppColors.greenBright,
  });

  @override
  Widget build(BuildContext context) {
    final r = size * 0.3;
    final dot = size * 0.31;
    final leaf = size * 0.38;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(r),
            ),
          ),
          Positioned(
            top: size * 0.2,
            right: size * 0.19,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: size * 0.21,
            left: size * 0.2,
            child: Container(
              width: leaf,
              height: leaf,
              decoration: BoxDecoration(
                color: leafColor,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(r),
                  bottomLeft: Radius.circular(r),
                ),
              ),
            ),
          ),
        ],
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
          style: AppText.display(textSize, weight: 800, color: textColor,
              letterSpacing: -0.5),
        ),
      ],
    );
  }
}
