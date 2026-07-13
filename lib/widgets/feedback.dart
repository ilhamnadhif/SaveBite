import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// SnackBar bermerek SaveBite + haptic ringan. Dipakai untuk umpan balik aksi.
class AppFeedback {
  AppFeedback._();

  static void snack(BuildContext context, String message, {IconData? icon}) {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.amber, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message,
                style: AppText.ui(13.5, weight: 600, color: AppColors.cream),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog konfirmasi bermerek (mis. sebelum keluar / nonaktifkan bag).
class AppDialog {
  AppDialog._();

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Ya',
    String cancelLabel = 'Batal',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AppText.display(19, weight: 800)),
        content: Text(
          message,
          style: AppText.ui(14, color: AppColors.body, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelLabel,
              style: AppText.ui(14, weight: 700, color: AppColors.body),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: AppText.ui(
                14,
                weight: 800,
                color: destructive ? AppColors.danger : AppColors.greenAccent,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
