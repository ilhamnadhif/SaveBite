import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Konfigurasi client Supabase yang aman dibundel ke aplikasi.
///
/// URL project dan publishable/anon key memang merupakan nilai publik pada
/// client mobile. Service-role key dan key server lain tidak boleh dimasukkan.
@immutable
class SupabaseClientConfig {
  final String url;
  final String publishableKey;

  const SupabaseClientConfig({required this.url, required this.publishableKey});

  bool get isComplete => url.isNotEmpty && publishableKey.isNotEmpty;

  static SupabaseClientConfig fromEnvText(String source) {
    final values = <String, String>{};
    for (final originalLine in const LineSplitter().convert(source)) {
      var line = originalLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trimLeft();
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
    return SupabaseClientConfig(
      url: values['SUPABASE_URL'] ?? '',
      publishableKey:
          values['SUPABASE_PUBLISHABLE_KEY'] ??
          values['SUPABASE_ANON_KEY'] ??
          '',
    );
  }
}

/// Konfigurasi lingkungan SaveBite.
///
/// Urutan sumber:
/// 1. `--dart-define` (bila salah satu define Supabase diberikan, keduanya
///    wajib lengkap agar dua project berbeda tidak tercampur);
/// 2. asset `assets/config/supabase.env` untuk run/build biasa.
class Env {
  Env._();

  static const _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const _definePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const _defineAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _defineDemo = String.fromEnvironment('SAVEBITE_DEMO');
  static const clientConfigAsset = 'assets/config/supabase.env';

  static SupabaseClientConfig _assetConfig = const SupabaseClientConfig(
    url: '',
    publishableKey: '',
  );
  static String? _assetLoadError;
  static bool _loaded = false;

  static bool get _hasAnyCompileTimeConfig =>
      _defineUrl.isNotEmpty ||
      _definePublishableKey.isNotEmpty ||
      _defineAnonKey.isNotEmpty;

  static SupabaseClientConfig get _compileTimeConfig => SupabaseClientConfig(
    url: _defineUrl.trim(),
    publishableKey:
        (_definePublishableKey.isNotEmpty
                ? _definePublishableKey
                : _defineAnonKey)
            .trim(),
  );

  static SupabaseClientConfig get _activeConfig =>
      _hasAnyCompileTimeConfig ? _compileTimeConfig : _assetConfig;

  static String get supabaseUrl => _activeConfig.url;
  static String get supabaseAnonKey => _activeConfig.publishableKey;
  static String get supabasePublishableKey => _activeConfig.publishableKey;

  /// Mode demo harus diminta eksplisit. Tanpa flag ini, konfigurasi yang hilang
  /// menghasilkan layar error dan tidak pernah diam-diam memakai FakeBackend.
  static bool get demoMode => _defineDemo.trim().toLowerCase() == 'true';

  static bool get isConfigured =>
      _loaded && !demoMode && _configurationProblem(_activeConfig) == null;

  static String? get configurationError {
    if (demoMode) return null;
    if (!_loaded) return 'Konfigurasi aplikasi belum selesai dimuat.';
    final problem = _configurationProblem(_activeConfig);
    if (problem != null) return problem;
    return _assetLoadError;
  }

  static Future<void> load({AssetBundle? bundle}) async {
    if (_loaded) return;
    if (_hasAnyCompileTimeConfig) {
      _loaded = true;
      return;
    }
    try {
      final source = await (bundle ?? rootBundle).loadString(clientConfigAsset);
      _assetConfig = SupabaseClientConfig.fromEnvText(source);
    } catch (_) {
      _assetLoadError =
          'Konfigurasi Supabase tidak ditemukan. Isi '
          '$clientConfigAsset dengan SUPABASE_URL dan '
          'SUPABASE_PUBLISHABLE_KEY, lalu build ulang aplikasi.';
    } finally {
      _loaded = true;
    }
  }

  static String? _configurationProblem(SupabaseClientConfig config) {
    if (!config.isComplete) {
      return _assetLoadError ??
          'Konfigurasi Supabase belum lengkap. Isi SUPABASE_URL dan '
              'SUPABASE_PUBLISHABLE_KEY, lalu build ulang aplikasi.';
    }
    final uri = Uri.tryParse(config.url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.host.endsWith('.supabase.co')) {
      return 'SUPABASE_URL tidak valid. Gunakan URL HTTPS project Supabase.';
    }
    if (_looksLikeServerSecret(config.publishableKey)) {
      return 'Key server/secret tidak boleh dibundel ke aplikasi. Gunakan '
          'publishable key atau anon key Supabase.';
    }
    return null;
  }

  static bool _looksLikeServerSecret(String key) {
    final normalized = key.trim();
    if (normalized.startsWith('sb_secret_')) return true;
    final parts = normalized.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(payload);
      return json is Map && json['role']?.toString() == 'service_role';
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void loadAssetTextForTesting(String source) {
    _assetConfig = SupabaseClientConfig.fromEnvText(source);
    _assetLoadError = null;
    _loaded = true;
  }

  @visibleForTesting
  static void resetForTesting() {
    _assetConfig = const SupabaseClientConfig(url: '', publishableKey: '');
    _assetLoadError = null;
    _loaded = false;
  }

  /// Deep link callback OAuth Google/Apple (didaftarkan di Supabase dashboard).
  static const authRedirect = 'com.savebite://login-callback';
}
