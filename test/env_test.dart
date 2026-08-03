import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/config/env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Env.resetForTesting);

  test(
    'asset client Supabase tersedia untuk flutter run/build biasa',
    () async {
      Env.resetForTesting();
      await Env.load();

      expect(Env.isConfigured, isTrue);
      expect(Env.configurationError, isNull);
      expect(Uri.parse(Env.supabaseUrl).host, endsWith('.supabase.co'));
      expect(Env.supabasePublishableKey, isNotEmpty);
      expect(Env.midtransClientKey, startsWith('Mid-client-'));
      expect(Env.midtransEnvironment, 'sandbox');
      expect(Env.midtransAppHost, 'app.sandbox.midtrans.com');
    },
  );

  test('parser menerima publishable key dan format dotenv umum', () {
    const source = '''
# public mobile client configuration
export SUPABASE_URL="https://example.supabase.co"
SUPABASE_PUBLISHABLE_KEY='sb_publishable_example'
MIDTRANS_CLIENT_KEY=Mid-client-publicExample123
MIDTRANS_ENVIRONMENT=sandbox
''';

    final config = SupabaseClientConfig.fromEnvText(source);

    expect(config.url, 'https://example.supabase.co');
    expect(config.publishableKey, 'sb_publishable_example');
    expect(config.midtransClientKey, 'Mid-client-publicExample123');
    expect(config.midtransEnvironment, 'sandbox');
  });

  test('compile-time profile dipilih secara atomik tanpa fallback asset', () {
    const asset = SupabaseClientConfig(
      url: 'https://sandbox.supabase.co',
      publishableKey: 'sb_publishable_sandbox',
      midtransClientKey: 'Mid-client-sandboxPublic123',
      midtransEnvironment: 'sandbox',
    );
    const partialCompile = SupabaseClientConfig(
      url: 'https://production.supabase.co',
      publishableKey: 'sb_publishable_production',
    );

    final selected = Env.selectClientConfigForTesting(
      hasAnyCompileTimeValue: true,
      compileTimeConfig: partialCompile,
      assetConfig: asset,
    );

    expect(selected.url, partialCompile.url);
    expect(selected.midtransClientKey, isEmpty);
    expect(
      Env.configurationProblemForTesting(
        selected,
        releaseMode: false,
        e2eRequested: false,
        allowSandboxRelease: false,
      ),
      contains('MIDTRANS_CLIENT_KEY'),
    );
  });

  test('release sandbox dan alat E2E gagal tertutup lintas profile', () {
    const sandbox = SupabaseClientConfig(
      url: 'https://sandbox.supabase.co',
      publishableKey: 'sb_publishable_sandbox',
      midtransClientKey: 'Mid-client-sandboxPublic123',
      midtransEnvironment: 'sandbox',
    );
    const production = SupabaseClientConfig(
      url: 'https://production.supabase.co',
      publishableKey: 'sb_publishable_production',
      midtransClientKey: 'Mid-client-productionPublic123',
      midtransEnvironment: 'production',
    );

    expect(
      Env.configurationProblemForTesting(
        sandbox,
        releaseMode: true,
        e2eRequested: false,
        allowSandboxRelease: false,
      ),
      contains('izin staging eksplisit'),
    );
    expect(
      Env.configurationProblemForTesting(
        sandbox,
        releaseMode: true,
        e2eRequested: true,
        allowSandboxRelease: true,
      ),
      isNull,
    );
    expect(
      Env.configurationProblemForTesting(
        production,
        releaseMode: true,
        e2eRequested: true,
        allowSandboxRelease: false,
      ),
      contains('hanya boleh digunakan dengan profile sandbox'),
    );
    expect(
      Env.configurationProblemForTesting(
        production,
        releaseMode: true,
        e2eRequested: false,
        allowSandboxRelease: false,
      ),
      isNull,
    );
  });

  test('konfigurasi tidak lengkap gagal tertutup, bukan mode demo', () {
    Env.loadAssetTextForTesting('SUPABASE_URL=https://example.supabase.co\n');

    expect(Env.isConfigured, isFalse);
    expect(Env.configurationError, contains('belum lengkap'));
  });

  test('service-role JWT ditolak dari konfigurasi client', () {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final serviceRoleJwt =
        '${part({'alg': 'HS256'})}.${part({'role': 'service_role'})}.signature';
    Env.loadAssetTextForTesting('''
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=$serviceRoleJwt
''');

    expect(Env.isConfigured, isFalse);
    expect(Env.configurationError, contains('tidak boleh'));
  });

  test('Midtrans Server Key ditolak dari asset client', () {
    Env.loadAssetTextForTesting('''
SUPABASE_URL=https://example.supabase.co
SUPABASE_ANON_KEY=sb_publishable_example
MIDTRANS_CLIENT_KEY=Mid-server-secretExample123
MIDTRANS_ENVIRONMENT=sandbox
''');

    expect(Env.isConfigured, isFalse);
    expect(Env.configurationError, contains('Client Key publik'));
  });
}
