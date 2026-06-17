// Listener auth menavigasi lewat navigatorKey global (di luar widget tree),
// jadi pemakaian context lintas-async di sini memang disengaja & aman.
// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'config/env.dart';
import 'services/app_backend.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'app_nav.dart';
import 'screens/onboarding/splash_screen.dart';

/// Navigator global agar listener auth bisa navigasi dari luar widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env tidak ada → app jalan offline (data contoh) atau pakai --dart-define.
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    useSupabaseBackend();
  }

  runApp(const SaveBiteApp());
}

class SaveBiteApp extends StatefulWidget {
  const SaveBiteApp({super.key});

  @override
  State<SaveBiteApp> createState() => _SaveBiteAppState();
}

class _SaveBiteAppState extends State<SaveBiteApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    final stream = AuthService.onAuthStateChange;
    if (stream != null) {
      _authSub = stream.listen((data) async {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        if (data.event == AuthChangeEvent.signedIn && data.session != null) {
          await AppNav.handleSignedIn(ctx);
        } else if (data.event == AuthChangeEvent.signedOut) {
          AppNav.toForkRoot(ctx);
        }
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaveBite',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
