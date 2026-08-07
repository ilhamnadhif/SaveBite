import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/screens/onboarding/splash_screen.dart';
import 'package:savebite/theme/app_theme.dart';
import 'package:savebite/widgets/brand.dart';

void main() {
  testWidgets('splash menampilkan artwork resmi tanpa indikator pager palsu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.theme, home: const SplashScreen()),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/savebite_brand.png',
    );
    expect(find.byType(Row), findsNothing);

    // Splash hanya visual; keputusan sesi dimiliki coordinator di root app.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('error startup tidak membocorkan detail konfigurasi', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const StartupConfigurationErrorScreen(
          message: 'Konfigurasi Supabase belum lengkap.',
        ),
      ),
    );

    expect(find.text('Aplikasi sedang tidak tersedia'), findsOneWidget);
    expect(
      find.text(
        'Aplikasi sedang mengalami kendala. Silakan coba lagi beberapa saat lagi.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('SAVEBITE_DEMO=true'), findsNothing);
    expect(find.textContaining('Konfigurasi Supabase'), findsNothing);
    expect(find.textContaining('Lanjutkan dengan Google'), findsNothing);
  });

  testWidgets('logo kecil memakai simbol tangan dan burger resmi', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLogo(size: 72))),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    final source = (image.image as ResizeImage).imageProvider;
    expect((source as AssetImage).assetName, 'assets/images/savebite_mark.png');
  });
}
