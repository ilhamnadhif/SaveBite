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
  final String midtransClientKey;
  final String midtransEnvironment;

  const SupabaseClientConfig({
    required this.url,
    required this.publishableKey,
    this.midtransClientKey = '',
    this.midtransEnvironment = '',
  });

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
      midtransClientKey: values['MIDTRANS_CLIENT_KEY'] ?? '',
      midtransEnvironment: values['MIDTRANS_ENVIRONMENT'] ?? '',
    );
  }
}

/// Konfigurasi lingkungan SaveBite.
///
/// Urutan sumber:
/// 1. `--dart-define` (bila salah satu konfigurasi client diberikan, seluruh
///    konfigurasi Supabase dan Midtrans wajib berasal dari define agar profile
///    sandbox/production tidak pernah tercampur dengan asset);
/// 2. asset `assets/config/client.env` untuk run/build biasa.
class Env {
  Env._();

  static const _defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const _definePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const _defineAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _defineMidtransClientKey = String.fromEnvironment(
    'MIDTRANS_CLIENT_KEY',
  );
  static const _defineMidtransEnvironment = String.fromEnvironment(
    'MIDTRANS_ENVIRONMENT',
  );
  static const _defineDemo = String.fromEnvironment('SAVEBITE_DEMO');
  static const _defineE2e = bool.fromEnvironment('SAVEBITE_E2E');
  static const _defineAllowSandboxRelease = bool.fromEnvironment(
    'SAVEBITE_ALLOW_SANDBOX_RELEASE',
  );
  static const _defineWebUrl = String.fromEnvironment('SAVEBITE_WEB_URL');
  static const clientConfigAsset = 'assets/config/client.env';

  static SupabaseClientConfig _assetConfig = const SupabaseClientConfig(
    url: '',
    publishableKey: '',
  );
  static String? _assetLoadError;
  static bool _loaded = false;

  static bool get _hasAnyCompileTimeSupabaseConfig =>
      _defineUrl.isNotEmpty ||
      _definePublishableKey.isNotEmpty ||
      _defineAnonKey.isNotEmpty;

  static bool get _hasAnyCompileTimeMidtransConfig =>
      _defineMidtransClientKey.isNotEmpty ||
      _defineMidtransEnvironment.isNotEmpty;

  static bool get _hasAnyCompileTimeClientConfig =>
      _hasAnyCompileTimeSupabaseConfig || _hasAnyCompileTimeMidtransConfig;

  static SupabaseClientConfig get _compileTimeConfig => SupabaseClientConfig(
    url: _defineUrl.trim(),
    publishableKey:
        (_definePublishableKey.isNotEmpty
                ? _definePublishableKey
                : _defineAnonKey)
            .trim(),
    midtransClientKey: _defineMidtransClientKey.trim(),
    midtransEnvironment: _defineMidtransEnvironment.trim().toLowerCase(),
  );

  static SupabaseClientConfig get _activeConfig => selectClientConfigForTesting(
    hasAnyCompileTimeValue: _hasAnyCompileTimeClientConfig,
    compileTimeConfig: _compileTimeConfig,
    assetConfig: _assetConfig,
  );

  @visibleForTesting
  static SupabaseClientConfig selectClientConfigForTesting({
    required bool hasAnyCompileTimeValue,
    required SupabaseClientConfig compileTimeConfig,
    required SupabaseClientConfig assetConfig,
  }) => hasAnyCompileTimeValue ? compileTimeConfig : assetConfig;

  static String get supabaseUrl => _activeConfig.url;
  static String get supabaseAnonKey => _activeConfig.publishableKey;
  static String get supabasePublishableKey => _activeConfig.publishableKey;
  static String get midtransClientKey => _activeConfig.midtransClientKey;
  static String get midtransEnvironment => _activeConfig.midtransEnvironment;
  static bool get midtransSandbox => midtransEnvironment == 'sandbox';
  static String get midtransAppHost =>
      midtransSandbox ? 'app.sandbox.midtrans.com' : 'app.midtrans.com';

  /// Mode demo harus diminta eksplisit. Tanpa flag ini, konfigurasi yang hilang
  /// menghasilkan layar error dan tidak pernah diam-diam memakai FakeBackend.
  static bool get demoMode => _defineDemo.trim().toLowerCase() == 'true';

  /// Mengaktifkan alat bantu pengujian E2E yang tidak boleh muncul pada build
  /// biasa. Nilainya hanya dapat diberikan saat kompilasi melalui
  /// `--dart-define=SAVEBITE_E2E=true`. Kontrol staging tetap dipaksa mati
  /// pada profile production dan pada release sandbox yang tidak diizinkan
  /// secara eksplisit.
  static bool get e2eMode =>
      _defineE2e &&
      midtransSandbox &&
      (!kReleaseMode || _defineAllowSandboxRelease);

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
    try {
      final source = await (bundle ?? rootBundle).loadString(clientConfigAsset);
      _assetConfig = SupabaseClientConfig.fromEnvText(source);
    } catch (_) {
      if (!_hasAnyCompileTimeClientConfig) {
        _assetLoadError =
            'Konfigurasi client tidak ditemukan. Isi $clientConfigAsset '
            'dengan konfigurasi Supabase dan Midtrans, lalu build ulang '
            'aplikasi.';
      }
    } finally {
      _loaded = true;
    }
  }

  static String? _configurationProblem(
    SupabaseClientConfig config, {
    bool releaseMode = kReleaseMode,
    bool e2eRequested = _defineE2e,
    bool allowSandboxRelease = _defineAllowSandboxRelease,
  }) {
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
    if (!RegExp(
      r'^Mid-client-[A-Za-z0-9_-]{8,128}$',
    ).hasMatch(config.midtransClientKey)) {
      return 'MIDTRANS_CLIENT_KEY tidak valid. Gunakan Client Key publik, '
          'bukan Server Key.';
    }
    if (!const {'sandbox', 'production'}.contains(config.midtransEnvironment)) {
      return 'MIDTRANS_ENVIRONMENT harus bernilai sandbox atau production.';
    }
    if (e2eRequested && config.midtransEnvironment != 'sandbox') {
      return 'SAVEBITE_E2E hanya boleh digunakan dengan profile sandbox.';
    }
    if (releaseMode &&
        config.midtransEnvironment == 'sandbox' &&
        !allowSandboxRelease) {
      return 'Build release sandbox memerlukan izin staging eksplisit. '
          'Gunakan SAVEBITE_ALLOW_SANDBOX_RELEASE=true hanya untuk distribusi '
          'internal, bukan production.';
    }
    return null;
  }

  @visibleForTesting
  static String? configurationProblemForTesting(
    SupabaseClientConfig config, {
    required bool releaseMode,
    required bool e2eRequested,
    required bool allowSandboxRelease,
  }) => _configurationProblem(
    config,
    releaseMode: releaseMode,
    e2eRequested: e2eRequested,
    allowSandboxRelease: allowSandboxRelease,
  );

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

  static const mobileAuthRedirect = 'com.savebite://login-callback';

  /// Origin aplikasi web yang dipakai sebagai callback OAuth dan pembayaran.
  ///
  /// Build production sebaiknya selalu memberi `SAVEBITE_WEB_URL`. Fallback ke
  /// origin halaman aktif hanya dipakai agar localhost tetap mudah diuji.
  static Uri get webBaseUri {
    final raw = _defineWebUrl.trim().isNotEmpty
        ? _defineWebUrl.trim()
        : Uri.base.origin;
    final uri = Uri.tryParse(raw);
    final isLocal =
        uri != null && (uri.host == 'localhost' || uri.host == '127.0.0.1');
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !(isLocal && uri.scheme == 'http'))) {
      throw StateError(
        'SAVEBITE_WEB_URL harus berupa origin HTTPS atau localhost HTTP.',
      );
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/',
    );
  }

  /// Callback OAuth Google/Apple yang sesuai dengan platform aktif.
  static String get authRedirect =>
      kIsWeb ? webBaseUri.toString() : mobileAuthRedirect;
}
