import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:savebite/app_nav.dart';
import 'package:savebite/app_state.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/screens/consumer/location_priming_screen.dart';
import 'package:savebite/screens/onboarding/fork_screen.dart';
import 'package:savebite/screens/onboarding/onboarding_screen.dart';
import 'package:savebite/services/app_backend.dart' as app_backend;
import 'package:savebite/theme/app_theme.dart';

class _GatedBootstrapBackend extends FakeBackend {
  final Completer<void> releaseProfile = Completer<void>();
  int currentProfileCalls = 0;

  @override
  Future<Profile?> currentProfile() async {
    currentProfileCalls++;
    await releaseProfile.future;
    return super.currentProfile();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appState.resetSession();
    AppNav.resetAuthRoutingForTest();
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1200, 2700);
    view.devicePixelRatio = 3;
  });

  tearDown(() {
    app_backend.useFakeBackend();
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'initialSession dan signedIn bersamaan hanya bootstrap satu kali',
    (tester) async {
      final backend = _GatedBootstrapBackend();
      app_backend.backend = backend;
      late BuildContext rootContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Builder(
            builder: (context) {
              rootContext = context;
              return const Scaffold(body: Text('Splash'));
            },
          ),
        ),
      );

      final initialSessionRoute = AppNav.handleSignedIn(rootContext);
      final signedInRoute = AppNav.handleSignedIn(rootContext);
      backend.releaseProfile.complete();
      await Future.wait([initialSessionRoute, signedInRoute]);
      await tester.pumpAndSettle();

      expect(backend.currentProfileCalls, 1);
      expect(find.byType(LocationPrimingScreen), findsOneWidget);
    },
  );

  testWidgets('logout membatalkan navigasi bootstrap yang masih berjalan', (
    tester,
  ) async {
    final backend = _GatedBootstrapBackend();
    app_backend.backend = backend;
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) {
            rootContext = context;
            return const Scaffold(body: Text('Splash'));
          },
        ),
      ),
    );

    final signingIn = AppNav.handleSignedIn(rootContext);
    expect(backend.currentProfileCalls, 1);

    final loggingOut = AppNav.logout(rootContext);
    await tester.pumpAndSettle();
    await loggingOut;
    await tester.pumpAndSettle();
    expect(find.byType(ForkScreen), findsOneWidget);

    backend.releaseProfile.complete();
    await signingIn;
    await tester.pumpAndSettle();

    expect(find.byType(ForkScreen), findsOneWidget);
    expect(find.byType(LocationPrimingScreen), findsNothing);
  });

  testWidgets('cold-start tanpa sesi menghormati status onboarding', (
    tester,
  ) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (context) {
            rootContext = context;
            return const Scaffold(body: Text('Splash'));
          },
        ),
      ),
    );

    AppNav.routeLoggedOutAtStartup(rootContext);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    AppNav.resetAuthRoutingForTest();
    appState.onboardingSeen = true;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    AppNav.routeLoggedOutAtStartup(navigator.context);
    await tester.pumpAndSettle();
    expect(find.byType(ForkScreen), findsOneWidget);
  });
}
