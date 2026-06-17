import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Helper tipografi SaveBite.
/// - [display] / judul: Bricolage Grotesque (variable: opsz, wght)
/// - [ui] / body: Plus Jakarta Sans (variable: wght)
///
/// Karena font yang dibundel adalah variable font, kita pakai [FontVariation]
/// agar berat (weight) dirender presisi di semua versi Flutter, bukan hanya
/// mengandalkan [fontWeight].
class AppText {
  AppText._();

  static const String _display = 'Bricolage';
  static const String _ui = 'Jakarta';

  static FontWeight _w(int weight) {
    switch (weight) {
      case 400:
        return FontWeight.w400;
      case 500:
        return FontWeight.w500;
      case 600:
        return FontWeight.w600;
      case 700:
        return FontWeight.w700;
      case 800:
        return FontWeight.w800;
      default:
        return FontWeight.w400;
    }
  }

  /// Judul / headline — Bricolage Grotesque.
  static TextStyle display(
    double size, {
    int weight = 800,
    Color color = AppColors.ink,
    double? height,
    double letterSpacing = -0.5,
  }) {
    final opsz = size.clamp(12.0, 96.0);
    return TextStyle(
      fontFamily: _display,
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontWeight: _w(weight),
      fontVariations: [
        FontVariation('wght', weight.toDouble()),
        FontVariation('opsz', opsz),
      ],
    );
  }

  /// UI / body — Plus Jakarta Sans.
  static TextStyle ui(
    double size, {
    int weight = 500,
    Color color = AppColors.ink,
    double? height,
    double letterSpacing = 0,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return TextStyle(
      fontFamily: _ui,
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
      decorationColor: decorationColor,
      fontWeight: _w(weight),
      fontVariations: [FontVariation('wght', weight.toDouble())],
    );
  }
}
