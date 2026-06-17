import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_colors.dart';

/// QR code asli (qr_flutter) dengan warna brand.
class QrBox extends StatelessWidget {
  final String data;
  final double size;
  const QrBox({super.key, required this.data, this.size = 190});

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: AppColors.ink,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.circle,
        color: AppColors.ink,
      ),
    );
  }
}
