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

/// Layar kegagalan startup yang hanya menampilkan pesan aman untuk pengguna.
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
                      'Aplikasi sedang tidak tersedia',
                      textAlign: TextAlign.center,
                      style: AppText.display(
                        25,
                        weight: 800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Aplikasi sedang mengalami kendala. Silakan coba lagi '
                      'beberapa saat lagi.',
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                        14,
                        color: AppColors.body,
                        height: 1.55,
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
