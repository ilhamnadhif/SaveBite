import 'package:flutter/material.dart';
import '../../sb.dart';

/// A1 Splash. Pola: LAYAR PENUH (Scaffold sendiri).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Semantics(
                  image: true,
                  label: 'SaveBite, Every Bite Matters',
                  child: Image.asset(
                    'assets/images/savebite_brand.png',
                    width: double.infinity,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Build salah konfigurasi tidak boleh terlihat seperti login demo yang
/// berhasil. Layar ini sengaja menjelaskan langkah perbaikan tanpa pernah
/// menampilkan key atau nilai credential.
class StartupConfigurationErrorScreen extends StatelessWidget {
  final String message;

  const StartupConfigurationErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 84),
                    const SizedBox(height: 24),
                    Text(
                      'Konfigurasi aplikasi belum lengkap',
                      textAlign: TextAlign.center,
                      style: AppText.display(
                        25,
                        weight: 800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                        14,
                        color: AppColors.body,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Text(
                        'Untuk build normal, isi assets/config/client.env. '
                        'Mode data contoh hanya aktif dengan '
                        'SAVEBITE_DEMO=true.',
                        textAlign: TextAlign.center,
                        style: AppText.ui(
                          12.5,
                          weight: 600,
                          color: AppColors.body,
                          height: 1.5,
                        ),
                      ),
                    ),
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
