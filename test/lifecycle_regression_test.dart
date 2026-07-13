import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/screens/consumer/consumer_shell.dart';
import 'package:savebite/services/app_backend.dart';
import 'package:savebite/theme/app_theme.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    useFakeBackend();
    appState.resetSession();
    final view = binding.platformDispatcher.implicitView!;
    // Lebar longgar mengisolasi regresi lifecycle dari audit responsivitas
    // komponen kartu yang diuji terpisah.
    view.physicalSize = const Size(2400, 2600);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('consumer shell tidak menotifikasi AppState saat build awal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.theme, home: const ConsumerShell()),
    );

    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
