import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';
import 'chips.dart';

/// Foto makanan dengan placeholder tan + cover fit + opsi desaturasi.
class FoodImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final double saturation; // 1 = penuh, 0 = grayscale
  final BoxFit fit;

  const FoodImage(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.saturation = 1,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final isNetwork = path.startsWith('http');
    Widget img = isNetwork
        ? Image.network(
            path,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          )
        : Image.asset(
            path,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          );
    if (saturation < 1) {
      img = ColorFiltered(
        colorFilter: _saturationFilter(saturation),
        child: img,
      );
    }
    return Container(
      width: width,
      height: height,
      color: AppColors.tanPlaceholder,
      child: img,
    );
  }

  static ColorFilter _saturationFilter(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    double m(double base, bool diag) =>
        (1 - s) * base + (diag ? s : 0);
    return ColorFilter.matrix(<double>[
      m(r, true), m(g, false), m(b, false), 0, 0,
      m(r, false), m(g, true), m(b, false), 0, 0,
      m(r, false), m(g, false), m(b, true), 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }
}

/// Gradient gelap dari bawah ke atas di atas foto (untuk badge terbaca).
class BottomScrim extends StatelessWidget {
  final double stop;
  const BottomScrim({super.key, this.stop = 0.52});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: const [Color(0x80140C04), Color(0x00140C04)],
            stops: [0, stop],
          ),
        ),
      ),
    );
  }
}

/// Pita diagonal "HEMAT 67%" di pojok kanan atas foto.
class SaveRibbon extends StatelessWidget {
  final String text;
  final double top;
  final double fontSize;
  final EdgeInsets padding;

  const SaveRibbon({
    super.key,
    required this.text,
    this.top = 15,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 40, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: -36,
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          padding: padding,
          decoration: const BoxDecoration(
            color: AppColors.terracotta,
            boxShadow: [
              BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
          child: Text(
            text,
            style: AppText.ui(fontSize,
                weight: 800, color: AppColors.white, letterSpacing: 0.6),
          ),
        ),
      ),
    );
  }
}

/// Harga jual (Bricolage 800) + harga asli dicoret.
class PriceTag extends StatelessWidget {
  final int salePrice;
  final int originalPrice;
  final double saleSize;
  final Color saleColor;

  const PriceTag({
    super.key,
    required this.salePrice,
    required this.originalPrice,
    this.saleSize = 23,
    this.saleColor = AppColors.green,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatRupiah(salePrice),
            style: AppText.display(saleSize, weight: 800, color: saleColor, height: 1)),
        const SizedBox(width: 9),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            formatRupiah(originalPrice),
            style: AppText.ui(13,
                color: AppColors.strikethrough,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.strikethrough),
          ),
        ),
      ],
    );
  }
}

/// Label "Selamatkan" (ikon eco hijau + teks).
class SaveLabel extends StatelessWidget {
  const SaveLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.eco_outlined, size: 15, color: AppColors.greenAccent),
        const SizedBox(width: 5),
        Text('Selamatkan',
            style: AppText.ui(12, weight: 700, color: AppColors.greenAccent)),
      ],
    );
  }
}

/// Avatar toko (kotak membulat dengan inisial).
class StoreAvatar extends StatelessWidget {
  final String initial;
  final Color color;
  final double size;
  final double? radius;
  final double border;
  final Color borderColor;

  const StoreAvatar({
    super.key,
    required this.initial,
    required this.color,
    this.size = 28,
    this.radius,
    this.border = 0,
    this.borderColor = AppColors.cream,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius ?? size * 0.32),
        border: border > 0 ? Border.all(color: borderColor, width: border) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppText.display(size * 0.46, weight: 800, color: AppColors.white),
      ),
    );
  }
}

/// Kartu hero beranda (foto besar + pita hemat + badge).
class BagHeroCard extends StatelessWidget {
  final Bag bag;
  final VoidCallback? onTap;
  const BagHeroCard({super.key, required this.bag, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.borderAlt),
          boxShadow: kHeroCardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 174,
              child: Stack(
                children: [
                  Positioned.fill(child: FoodImage(bag.image)),
                  const BottomScrim(),
                  SaveRibbon(text: 'HEMAT ${bag.discountPercent}%'),
                  Positioned(
                    left: 11,
                    right: 11,
                    bottom: 11,
                    child: Row(
                      children: [
                        OverlayBadge('Sisa ${bag.quantityLeft} lagi'),
                        const Spacer(),
                        OverlayBadge('Ambil ${bag.pickupWindow}', dark: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StoreAvatar(
                          initial: bag.merchant.initial,
                          color: bag.merchant.avatarColor),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(bag.merchant.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.ui(14, weight: 700)),
                      ),
                      const SizedBox(width: 8),
                      Text('★ ${_r(bag.merchant.rating)} · ${bag.merchant.distance}',
                          style: AppText.ui(12, weight: 600, color: AppColors.body)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(bag.title,
                      style: AppText.display(17, weight: 700, letterSpacing: -0.3)),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PriceTag(
                          salePrice: bag.salePrice,
                          originalPrice: bag.originalPrice),
                      const Spacer(),
                      const SaveLabel(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu beranda kompak (foto lebih kecil + badge "Hemat X%").
class BagCompactCard extends StatelessWidget {
  final Bag bag;
  final VoidCallback? onTap;
  const BagCompactCard({super.key, required this.bag, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.borderAlt),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 124,
              child: Stack(
                children: [
                  Positioned.fill(child: FoodImage(bag.image)),
                  const BottomScrim(),
                  Positioned(
                    left: 11,
                    right: 11,
                    bottom: 11,
                    child: Row(
                      children: [
                        OverlayBadge('Sisa ${bag.quantityLeft} lagi',
                            lightForeground: AppColors.greenAccent),
                        const Spacer(),
                        OverlayBadge('Ambil ${bag.pickupWindow}', dark: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StoreAvatar(
                          initial: bag.merchant.initial,
                          color: bag.merchant.avatarColor),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(bag.merchant.name,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.ui(14, weight: 700)),
                      ),
                      const SizedBox(width: 8),
                      Text('★ ${_r(bag.merchant.rating)} · ${bag.merchant.distance}',
                          style: AppText.ui(12, weight: 600, color: AppColors.body)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(bag.title,
                      style: AppText.display(16, weight: 700, letterSpacing: -0.3)),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      PriceTag(
                          salePrice: bag.salePrice,
                          originalPrice: bag.originalPrice,
                          saleSize: 21),
                      const Spacer(),
                      StatusBadge.save('Hemat ${bag.discountPercent}%'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _r(double v) => v.toStringAsFixed(1);
