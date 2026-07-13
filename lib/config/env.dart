/// Konfigurasi lingkungan dari `--dart-define` atau
/// `--dart-define-from-file=.env`. Nilai tidak dibundel sebagai Flutter asset.
class Env {
  Env._();

  static const _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const _defineKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseUrl => _defineUrl;
  static String get supabaseAnonKey => _defineKey;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Deep link callback OAuth Google (didaftarkan di dashboard Supabase).
  static const authRedirect = 'com.savebite://login-callback';
}
