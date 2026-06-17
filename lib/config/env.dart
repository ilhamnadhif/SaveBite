import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Konfigurasi lingkungan. Sumber (prioritas): --dart-define, lalu file `.env`.
/// `.env` dimuat di main() via dotenv.load(). Saat test (.env tak dimuat &
/// tanpa dart-define), [isConfigured] = false → app pakai data contoh offline.
class Env {
  Env._();

  static const _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const _defineKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String _read(String key, String fromDefine) {
    if (fromDefine.isNotEmpty) return fromDefine;
    if (dotenv.isInitialized) return dotenv.maybeGet(key) ?? '';
    return '';
  }

  static String get supabaseUrl => _read('SUPABASE_URL', _defineUrl);
  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY', _defineKey);

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Deep link callback OAuth Google (didaftarkan di dashboard Supabase).
  static const authRedirect = 'com.savebite://login-callback';
}
