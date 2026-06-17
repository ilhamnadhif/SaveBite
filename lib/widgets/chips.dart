import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Chip pilihan (kategori / filter). Terpilih = solid, tidak = outline putih.
class SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color selectedColor;
  final EdgeInsets padding;
  final double fontSize;

  const SelectChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.selectedColor = AppColors.green,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? selectedColor : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? null
              : Border.all(color: AppColors.chipBorder, width: 1),
        ),
        child: Text(
          label,
          style: AppText.ui(
            fontSize,
            weight: selected ? 700 : 600,
            color: selected ? AppColors.white : AppColors.body2,
          ),
        ),
      ),
    );
  }
}

/// Badge status kecil dengan background + warna teks bebas.
class StatusBadge extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  final double fontSize;
  final int weight;
  final EdgeInsets padding;

  const StatusBadge({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.fontSize = 11,
    this.weight = 800,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  // Preset umum.
  factory StatusBadge.available(String text) => StatusBadge(
        text: text,
        background: AppColors.greenSoftBg,
        foreground: AppColors.greenAccent,
        weight: 700,
      );

  factory StatusBadge.waiting(String text) => StatusBadge(
        text: text,
        background: AppColors.terracottaSoftBg,
        foreground: AppColors.brown,
      );

  factory StatusBadge.done(String text) => StatusBadge(
        text: text,
        background: AppColors.neutralChip2,
        foreground: AppColors.body,
        weight: 700,
      );

  factory StatusBadge.expired(String text) => StatusBadge(
        text: text,
        background: AppColors.dangerSoftBg,
        foreground: AppColors.danger,
        weight: 700,
      );

  factory StatusBadge.neutral(String text) => StatusBadge(
        text: text,
        background: AppColors.neutralChip,
        foreground: AppColors.muted,
        weight: 700,
      );

  factory StatusBadge.save(String text) => StatusBadge(
        text: text,
        background: AppColors.saveBg,
        foreground: AppColors.saveText,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: AppText.ui(fontSize, weight: weight, color: foreground)),
    );
  }
}

/// Badge di atas foto: "Sisa 3 lagi" (putih) & "Ambil 20.00–21.00" (hijau).
class OverlayBadge extends StatelessWidget {
  final String text;
  final bool dark; // true = bg hijau gelap + teks emas
  final Color lightForeground;

  const OverlayBadge(
    this.text, {
    super.key,
    this.dark = false,
    this.lightForeground = AppColors.saveText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: dark ? const Color(0xDB0F3D2C) : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppText.ui(11,
            weight: dark ? 700 : 800,
            color: dark ? AppColors.goldOnDark : lightForeground),
      ),
    );
  }
}
