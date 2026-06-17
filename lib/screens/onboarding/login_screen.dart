import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// A4 Login Google. Pola: LAYAR PENUH (Scaffold sendiri).
class LoginScreen extends StatelessWidget {
  final bool merchant;
  const LoginScreen({super.key, required this.merchant});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Padding(
          padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 32),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const AppLogo(size: 72),
                    const SizedBox(height: 26),
                    Text(
                      'Tinggal selangkah lagi',
                      textAlign: TextAlign.center,
                      style: AppText.display(26, weight: 800, color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        'Masuk dengan akun Google untuk mulai berbelanja Surprise Bag.',
                        textAlign: TextAlign.center,
                        style: AppText.ui(15, color: AppColors.body, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              _googleButton(context),
              const SizedBox(height: 16),
              Text(
                'Dengan masuk, kamu menyetujui Ketentuan Layanan dan Kebijakan Privasi SaveBite.',
                textAlign: TextAlign.center,
                style: AppText.ui(12, color: AppColors.captionWarm, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onLogin(BuildContext context) async {
    if (AuthService.isConfigured) {
      // Mode online: simpan peran lalu buka Google; routing oleh listener auth.
      appState.pendingMerchantIntent = merchant;
      await AuthService.signInWithGoogle();
    } else {
      // Mode offline (tanpa kredensial Supabase): pakai data contoh.
      await AppNav.completeLogin(context, merchant: merchant);
    }
  }

  Widget _googleButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _onLogin(context),
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.inputBorder, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _googleMark(),
            const SizedBox(width: 12),
            Text(
              'Lanjutkan dengan Google',
              style: AppText.ui(16, weight: 700, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _googleMark() {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFEA4335),
            Color(0xFFEA4335),
            Color(0xFFFBBC05),
            Color(0xFFFBBC05),
            Color(0xFF34A853),
            Color(0xFF34A853),
            Color(0xFF4285F4),
            Color(0xFF4285F4),
          ],
          stops: [0.0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75, 1.0],
        ),
      ),
      child: Center(
        child: Container(
          width: 11,
          height: 11,
          decoration: const BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
