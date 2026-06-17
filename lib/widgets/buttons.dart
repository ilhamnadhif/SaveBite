import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

/// Tombol utama full-width (pill, h54, r16, weight 700) dengan umpan balik
/// tekan (scale + haptic) dan state nonaktif (onTap == null).
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final double height;
  final double fontSize;
  final Widget? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.background = AppColors.green,
    this.foreground = AppColors.cream,
    this.height = 54,
    this.fontSize = 16,
    this.icon,
  });

  /// Varian merchant (terakota).
  const PrimaryButton.merchant({
    super.key,
    required this.label,
    this.onTap,
    this.height = 54,
    this.fontSize = 16,
    this.icon,
  })  : background = AppColors.terracotta,
        foreground = AppColors.white;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: Material(
            color: widget.background,
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onHighlightChanged: enabled
                  ? (v) => setState(() => _pressed = v)
                  : null,
              onTap: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      widget.onTap!();
                    }
                  : null,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[widget.icon!, const SizedBox(width: 9)],
                    Text(widget.label,
                        style: AppText.ui(widget.fontSize,
                            weight: 700, color: widget.foreground)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol teks polos (mis. "Batalkan pesanan").
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double height;
  final double fontSize;

  const GhostButton({
    super.key,
    required this.label,
    this.onTap,
    this.color = AppColors.body,
    this.height = 50,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: TextButton(
        onPressed: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap!();
              },
        style: TextButton.styleFrom(
          foregroundColor: color,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button)),
        ),
        child: Text(label, style: AppText.ui(fontSize, weight: 700, color: color)),
      ),
    );
  }
}

/// Tombol bundar (mis. tombol kembali / favorit di atas foto).
class CircleIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final Color background;
  final String? semanticLabel;

  const CircleIconButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 38,
    this.background = const Color(0xEBFFFFFF),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: SizedBox(width: size, height: size, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Tombol kembali sederhana (chevron) untuk header.
class BackChevron extends StatelessWidget {
  final VoidCallback? onTap;
  final Color color;
  const BackChevron({super.key, this.onTap, this.color = AppColors.ink});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kembali',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          (onTap ?? () => Navigator.of(context).maybePop())();
        },
        behavior: HitTestBehavior.opaque,
        child: Icon(Icons.arrow_back_ios_new, size: 18, color: color),
      ),
    );
  }
}
