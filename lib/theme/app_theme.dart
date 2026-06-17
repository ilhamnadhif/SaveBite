import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.green,
        primary: AppColors.green,
        secondary: AppColors.terracotta,
        surface: AppColors.cream,
        brightness: Brightness.light,
      ),
      fontFamily: 'Jakarta',
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
        fontFamily: 'Jakarta',
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.greenBright,
        selectionHandleColor: AppColors.greenBright,
      ),
      iconTheme: const IconThemeData(color: AppColors.body),
      dividerColor: AppColors.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
        contentTextStyle: AppText.ui(13.5, weight: 600, color: AppColors.cream),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.greenBright,
      ),
    );
  }
}

/// Skala spasi standar (kelipatan 4).
class AppSpacing {
  AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

/// Radius standar yang dipakai berulang.
class AppRadius {
  AppRadius._();
  static const card = 22.0;
  static const cardSm = 18.0;
  static const button = 16.0;
  static const input = 14.0;
  static const pill = 20.0;
  static const sheet = 28.0;
}

/// Helper bayangan kartu hero (box-shadow:0 12px 28px -18px rgba(40,30,12,0.5)).
const List<BoxShadow> kHeroCardShadow = [
  BoxShadow(
    color: Color(0x80281E0C),
    blurRadius: 28,
    offset: Offset(0, 12),
    spreadRadius: -18,
  ),
];

const List<BoxShadow> kSheetShadow = [
  BoxShadow(color: Color(0x26000000), blurRadius: 30, offset: Offset(0, 8)),
];
