import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Handle bar abu di atas bottom sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 5,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.handle,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Header berwarna yang menembus area status bar (mis. beranda hijau).
class ColoredHeader extends StatelessWidget {
  final Color background;
  final Widget child;
  final double bottomPadding;
  final double horizontalPadding;

  const ColoredHeader({
    super.key,
    required this.background,
    required this.child,
    this.bottomPadding = 16,
    this.horizontalPadding = 20,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      color: background,
      padding: EdgeInsets.fromLTRB(
          horizontalPadding, top + 14, horizontalPadding, bottomPadding),
      child: child,
    );
  }
}

/// Header putih sederhana dengan tombol kembali + judul (Bricolage 19).
class SimpleHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Color background;
  final bool showBack;
  final double titleSize;

  const SimpleHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.background = AppColors.white,
    this.showBack = true,
    this.titleSize = 19,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: background,
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, 14),
      child: Row(
        children: [
          if (showBack) ...[
            GestureDetector(
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 18, color: AppColors.ink),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Text(title,
                style: AppText.display(titleSize, weight: 700, letterSpacing: -0.3)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Label kecil di atas field form.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text, style: AppText.ui(12.5, weight: 700, color: AppColors.body)),
    );
  }
}

/// Field input bergaya SaveBite (border, r14, padding 14).
class AppTextField extends StatelessWidget {
  final String? initialValue;
  final String? hintText;
  final int maxLines;
  final Color borderColor;
  final Widget? trailing;
  final TextInputType? keyboardType;

  const AppTextField({
    super.key,
    this.initialValue,
    this.hintText,
    this.maxLines = 1,
    this.borderColor = AppColors.inputBorder,
    this.trailing,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: initialValue,
              maxLines: maxLines,
              keyboardType: keyboardType,
              style: AppText.ui(14.5, color: AppColors.ink),
              cursorColor: AppColors.greenBright,
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: AppText.ui(14.5, color: AppColors.mutedAlt),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Stepper jumlah: − nilai +
class QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final Color plusColor;
  final String? suffix;

  const QtyStepper({
    super.key,
    required this.value,
    this.onMinus,
    this.onPlus,
    this.plusColor = AppColors.green,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circle('−', false, onMinus),
        const SizedBox(width: 16),
        Text(suffix == null ? '$value' : '$value $suffix',
            style: AppText.ui(16, weight: 700)),
        const SizedBox(width: 16),
        _circle('+', true, onPlus),
      ],
    );
  }

  Widget _circle(String sign, bool filled, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? plusColor : Colors.transparent,
          border: filled ? null : Border.all(color: AppColors.inputBorder, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(sign,
            style: AppText.ui(18,
                color: filled ? AppColors.white : AppColors.muted)),
      ),
    );
  }
}

/// Baris menu (ikon + label + chevron) untuk profil.
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool last;

  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.body),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label, style: AppText.ui(14.5, color: AppColors.ink))),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.chevron),
          ],
        ),
      ),
    );
  }
}

/// Kartu statistik kecil.
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color background;
  final Color valueColor;
  final Color labelColor;
  final Border? border;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    required this.background,
    required this.valueColor,
    required this.labelColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.display(18, weight: 800, color: valueColor)),
          const SizedBox(height: 2),
          Text(label, style: AppText.ui(11.5, color: labelColor)),
        ],
      ),
    );
  }
}

/// Judul bagian (Bricolage) dengan aksi opsional di kanan.
class SectionHeading extends StatelessWidget {
  final String title;
  final Widget? leadingIcon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color actionColor;
  final double fontSize;

  const SectionHeading({
    super.key,
    required this.title,
    this.leadingIcon,
    this.actionLabel,
    this.onAction,
    this.actionColor = AppColors.greenBright,
    this.fontSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: AppText.display(fontSize, weight: 700)),
        if (leadingIcon != null) ...[const SizedBox(width: 7), leadingIcon!],
        const Spacer(),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Text(actionLabel!,
                style: AppText.ui(13, weight: 700, color: actionColor)),
          ),
      ],
    );
  }
}

/// Tab switch garis bawah (Aktif / Riwayat).
class TabSwitch extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onTap;
  final Color activeColor;
  final Color underlineColor;
  final Map<int, Widget>? badges;

  const TabSwitch({
    super.key,
    required this.tabs,
    required this.index,
    required this.onTap,
    this.activeColor = AppColors.green,
    this.underlineColor = AppColors.green,
    this.badges,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < tabs.length; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Container(
                padding: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i == index ? underlineColor : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tabs[i],
                        style: AppText.ui(14.5,
                            weight: i == index ? 700 : 600,
                            color: i == index ? activeColor : AppColors.navInactive)),
                    if (badges != null && badges![i] != null) ...[
                      const SizedBox(width: 7),
                      badges![i]!,
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Progress bar tipis (mis. "5 dari 8 terjual").
class ProgressBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final Color background;
  final double height;

  const ProgressBar({
    super.key,
    required this.fraction,
    this.color = AppColors.greenBright,
    this.background = AppColors.border,
    this.height = 7,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: background,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0, 1),
          child: Container(color: color),
        ),
      ),
    );
  }
}

/// Banner info hijau (mis. dampak toko).
class InfoBanner extends StatelessWidget {
  final Widget child;
  final IconData icon;
  final Color background;
  final Color iconColor;

  const InfoBanner({
    super.key,
    required this.child,
    this.icon = Icons.eco_outlined,
    this.background = AppColors.greenSoftBg,
    this.iconColor = AppColors.greenAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Kartu putih dengan border standar.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color borderColor;
  final double borderWidth;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = AppRadius.cardSm,
    this.borderColor = AppColors.border,
    this.borderWidth = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card);
  }
}

/// State kosong generik: lingkaran ikon + judul + body + aksi opsional.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondaryAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                  color: AppColors.emptyCircle, shape: BoxShape.circle),
              child: Icon(icon, size: 48, color: AppColors.emptyIcon),
            ),
            const SizedBox(height: 22),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.display(22, weight: 800)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.ui(14, color: AppColors.body, height: 1.55)),
            if (action != null) ...[const SizedBox(height: 24), action!],
            if (secondaryAction != null) ...[
              const SizedBox(height: 12),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}
