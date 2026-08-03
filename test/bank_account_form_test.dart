import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/screens/merchant/withdraw_sheet.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;
import 'package:savebite/theme/app_theme.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    app_backend.useFakeBackend();
    appState.resetSession();
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1200, 2400);
    view.devicePixelRatio = 2;
  });

  tearDown(() {
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('form rekening memberi error field yang dapat ditindaklanjuti', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Buka form rekening'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('bank-account-number-field')),
      '12345',
    );
    await tester.enterText(
      find.byKey(const ValueKey('bank-account-holder-field')),
      'A',
    );
    await tester.ensureVisible(find.text('Simpan rekening'));
    await tester.tap(find.text('Simpan rekening'));
    await tester.pump();

    expect(find.text('Masukkan 6–20 digit nomor rekening.'), findsOneWidget);
    expect(
      find.text('Nama pemilik harus berisi 2–100 karakter.'),
      findsOneWidget,
    );
  });

  testWidgets('data BCA sepuluh digit berhasil melewati alur form', (
    tester,
  ) async {
    app_backend.backend = _FixedBankListBackend();
    await appState.loadBalance();
    BankAccount? saved;
    await tester.pumpWidget(_host(onSaved: (account) => saved = account));
    await tester.tap(find.text('Buka form rekening'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('bank-account-number-field')),
      '1234567890',
    );
    await tester.enterText(
      find.byKey(const ValueKey('bank-account-holder-field')),
      'TEST USER',
    );
    await tester.ensureVisible(find.text('Simpan rekening'));
    await tester.tap(find.text('Simpan rekening'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved?.bankCode, 'BCA');
    expect(saved?.accountNumberMasked, '•••• 7890');
    expect(
      find.byKey(const ValueKey('bank-account-number-field')),
      findsNothing,
    );
  });
}

class _FixedBankListBackend extends FakeBackend {
  @override
  Future<List<BankAccount>> bankAccounts() async =>
      List<BankAccount>.unmodifiable(await super.bankAccounts());
}

Widget _host({ValueChanged<BankAccount>? onSaved}) {
  return MaterialApp(
    theme: AppTheme.theme,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final account = await showAddBankAccountSheet(context);
              if (account != null) onSaved?.call(account);
            },
            child: const Text('Buka form rekening'),
          ),
        ),
      ),
    ),
  );
}
