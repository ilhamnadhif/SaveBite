import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// A1 Splash. Pola: LAYAR PENUH (Scaffold sendiri).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Pengguna lama dengan sesi aktif → langsung ke ekosistem terakhir.
    if (AuthService.isConfigured && AuthService.isSignedIn) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) await AppNav.handleSignedIn(context);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) AppNav.toOnboarding(context);
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: Scaffold(
      backgroundColor: AppColors.green,
      body: Stack(
        children: [
          // Glow radial hijau terang di area atas.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.24),
                  radius: 0.6,
                  colors: [
                    Color(0x5927A36A),
                    Color(0x0027A36A),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 88, background: AppColors.greenDark),
                const SizedBox(height: 26),
                Column(
                  children: [
                    Text(
                      'SaveBite',
                      style: AppText.display(38,
                          weight: 800,
                          color: AppColors.cream,
                          letterSpacing: -1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selamatkan makanan, hemat lebih.',
                      style: AppText.ui(15,
                          weight: 500, color: AppColors.greenMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Tiga titik indikator di dekat bawah.
          Positioned(
            left: 0,
            right: 0,
            bottom: 78,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _dot(AppColors.amber),
                const SizedBox(width: 7),
                _dot(Colors.white.withValues(alpha: 0.3)),
                const SizedBox(width: 7),
                _dot(Colors.white.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
