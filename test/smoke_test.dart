import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/data/sample_data.dart';
import 'package:savebite/screens/consumer/checkout_screen.dart';
import 'package:savebite/screens/consumer/profile_screen.dart';
import 'package:savebite/theme/app_theme.dart';
import 'package:savebite/widgets/common.dart';

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

  testWidgets('checkout menampilkan QRIS sebagai satu-satunya metode', (
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
    expect(find.text('QRIS'), findsOneWidget);
    expect(
      find.text('Pindai dengan aplikasi pembayaran yang mendukung QRIS'),
      findsOneWidget,
    );
    expect(find.textContaining('virtual account'), findsNothing);
    expect(find.textContaining('Mode demo eksplisit'), findsOneWidget);
    expect(find.text('Biaya layanan'), findsOneWidget);
    expect(find.text('Lanjutkan · Rp16.000'), findsOneWidget);
    expect(find.textContaining('Bayar'), findsNothing);
  });

  testWidgets('checkout membatasi jumlah sesuai batas backend', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: CheckoutScreen(
          bag: SampleData.bagRoti.copyWith(quantityLeft: 150),
        ),
      ),
    );
    await tester.pump();

    for (var quantity = 1; quantity < 100; quantity++) {
      final stepper = tester.widget<QtyStepper>(find.byType(QtyStepper));
      expect(stepper.onPlus, isNotNull);
      stepper.onPlus!();
      await tester.pump();
    }

    final capped = tester.widget<QtyStepper>(find.byType(QtyStepper));
    expect(capped.value, 100);
    expect(capped.onPlus, isNull);
  });

  testWidgets('profil konsumen menyediakan perpindahan mode', (tester) async {
    await tester.pumpWidget(_host(const ProfileScreen()));
    await tester.pump();

    expect(find.text('Mode aplikasi'), findsOneWidget);
    expect(find.text('Beralih ke mode penjual'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
  });
}
