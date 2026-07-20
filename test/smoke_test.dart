import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/data/sample_data.dart';
import 'package:savebite/screens/consumer/checkout_screen.dart';
import 'package:savebite/screens/consumer/profile_screen.dart';
import 'package:savebite/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.theme,
  home: Scaffold(body: child),
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appState.resetSession();
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1200, 2600);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('checkout menjelaskan Midtrans dan menampilkan total', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: CheckoutScreen(bag: SampleData.bagRoti),
      ),
    );
    await tester.pump();

    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Midtrans Snap'), findsOneWidget);
    expect(find.textContaining('Mode demo eksplisit'), findsOneWidget);
    expect(find.text('Biaya layanan'), findsOneWidget);
    expect(find.text('Lanjutkan · Rp16.000'), findsOneWidget);
    expect(find.textContaining('Bayar'), findsNothing);
  });

  testWidgets('profil konsumen menyediakan perpindahan mode', (tester) async {
    await tester.pumpWidget(_host(const ProfileScreen()));
    await tester.pump();

    expect(find.text('Mode aplikasi'), findsOneWidget);
    expect(find.text('Beralih ke mode penjual'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
  });
}
