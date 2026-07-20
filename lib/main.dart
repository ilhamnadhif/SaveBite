// Listener auth menavigasi lewat navigatorKey global (di luar widget tree),
// jadi pemakaian context lintas-async di sini memang disengaja & aman.
// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'services/app_backend.dart';
import 'services/auth_service.dart';
import 'services/payment_link_service.dart';
import 'services/serial_task_queue.dart';
import 'theme/app_theme.dart';
import 'app_nav.dart';
import 'app_state.dart';
import 'screens/onboarding/splash_screen.dart';

/// Navigator global agar listener auth bisa navigasi dari luar widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  await Env.load();
  String? startupConfigurationError = Env.configurationError;
  if (Env.demoMode) {
    // FakeBackend hanya boleh aktif pada build demo yang meminta mode ini.
    useFakeBackend();
  } else if (startupConfigurationError == null) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabasePublishableKey,
      );
      useSupabaseBackend();
    } catch (error) {
      if (kDebugMode) debugPrint('Supabase initialization failed: $error');
      startupConfigurationError =
          'Koneksi akun tidak dapat disiapkan. Periksa konfigurasi Supabase '
          'client lalu buka ulang aplikasi.';
    }
  }

  await appState.restoreLocalState();

  runApp(SaveBiteApp(startupConfigurationError: startupConfigurationError));
}

class SaveBiteApp extends StatefulWidget {
  final String? startupConfigurationError;

  const SaveBiteApp({super.key, this.startupConfigurationError});

  @override
  State<SaveBiteApp> createState() => _SaveBiteAppState();
}

class _SaveBiteAppState extends State<SaveBiteApp> {
  static const _minimumSplashDuration = Duration(milliseconds: 900);

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<Uri>? _paymentLinkSub;
  late final SerialTaskQueue<AuthState> _authEvents;
  late final Future<void> _minimumSplash;
  Future<void>? _startupRouting;
  Future<void>? _paymentCallbackFlow;
  bool _startupRouted = false;
  Uri? _lastPaymentCallback;
  DateTime? _lastPaymentCallbackAt;

  @override
  void initState() {
    super.initState();
    _authEvents = SerialTaskQueue<AuthState>(
      handler: _routeAuthEvent,
      onError: (error, _) => appState.reportError(error),
    );
    _minimumSplash = Future<void>.delayed(_minimumSplashDuration);
    if (widget.startupConfigurationError != null) return;

    final stream = AuthService.onAuthStateChange;
    if (stream != null) {
      _authSub = stream.listen(
        _authEvents.add,
        onError: (Object error) {
          appState.reportError(error);
        },
      );
    }
    if (!kIsWeb && AuthService.isConfigured) {
      // Supabase juga mendengarkan stream singleton yang sama untuk OAuth.
      // Listener ini memfilter ketat callback pembayaran saja. Initial link
      // tetap dibaca eksplisit karena listener OAuth dapat lebih dahulu
      // menerima event ketika aplikasi dibuka dari kondisi terminated.
      final appLinks = AppLinks();
      _paymentLinkSub = appLinks.uriLinkStream.listen(
        _queuePaymentCallback,
        onError: (Object error) => appState.reportError(error),
      );
      unawaited(
        appLinks.getInitialLink().then((uri) {
          if (uri != null) {
            _queuePaymentCallback(uri, arrivedDuringStartup: true);
          }
        }, onError: (Object error) => appState.reportError(error)),
      );
    }
    // Fallback ini juga menangani build demo dan kondisi ketika event terakhir
    // sudah berubah menjadi tokenRefreshed sebelum listener widget terpasang.
    unawaited(_routeStartup());
  }

  @override
  void dispose() {
    _authEvents.close();
    _authSub?.cancel();
    _paymentLinkSub?.cancel();
    super.dispose();
  }

  void _queuePaymentCallback(Uri uri, {bool? arrivedDuringStartup}) {
    if (!PaymentLinks.isPaymentCallback(uri)) return;
    final now = DateTime.now();
    if (_lastPaymentCallback == uri &&
        _lastPaymentCallbackAt != null &&
        now.difference(_lastPaymentCallbackAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastPaymentCallback = uri;
    _lastPaymentCallbackAt = now;
    final shouldNavigateAfterStartup = arrivedDuringStartup ?? !_startupRouted;
    _paymentCallbackFlow = (_paymentCallbackFlow ?? Future<void>.value())
        .then(
          (_) => _handlePaymentCallback(
            arrivedDuringStartup: shouldNavigateAfterStartup,
          ),
        )
        .catchError((Object error) {
          appState.reportError(error);
        });
  }

  Future<void> _handlePaymentCallback({
    required bool arrivedDuringStartup,
  }) async {
    // Query/deep-link hanya membangunkan aplikasi. Status pembayaran selalu
    // diambil ulang oleh Edge Function dari Get Status API Midtrans.
    await _routeStartup();
    if (!mounted || AuthService.currentSession == null) return;
    await appState.loadOrders();
    if (!mounted || !arrivedDuringStartup) return;
    final ctx = await _navigatorContext();
    if (ctx == null) return;
    appState.switchToConsumer();
    appState.rememberMode('consumer');
    AppNav.toOrders(ctx);
  }

  Future<void> _routeAuthEvent(AuthState data) async {
    if (!mounted || widget.startupConfigurationError != null) return;
    final event = data.event;
    if (!_startupRouted &&
        (event == AuthChangeEvent.initialSession ||
            event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.signedOut ||
            event == AuthChangeEvent.tokenRefreshed)) {
      await _routeStartup();
      return;
    }

    final ctx = await _navigatorContext();
    if (ctx == null) return;
    if (event == AuthChangeEvent.signedIn && data.session != null) {
      await AppNav.handleSignedIn(ctx);
    } else if (event == AuthChangeEvent.signedOut) {
      await AppNav.handleSignedOut(ctx);
    }
  }

  Future<void> _routeStartup() => _startupRouting ??= _performStartupRoute();

  Future<void> _performStartupRoute() async {
    await _minimumSplash;
    if (!mounted) return;
    final ctx = await _navigatorContext();
    if (ctx == null) return;
    if (AuthService.isConfigured && AuthService.currentSession != null) {
      await AppNav.handleSignedIn(ctx);
    } else {
      AppNav.routeLoggedOutAtStartup(ctx);
    }
    _startupRouted = true;
  }

  Future<BuildContext?> _navigatorContext() async {
    var ctx = navigatorKey.currentContext;
    if (ctx != null) return ctx;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    return navigatorKey.currentContext;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaveBite',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.theme,
      home: widget.startupConfigurationError == null
          ? const SplashScreen()
          : StartupConfigurationErrorScreen(
              message: widget.startupConfigurationError!,
            ),
    );
  }
}
