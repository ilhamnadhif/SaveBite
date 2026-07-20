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
    },
  );

  test('parser menerima publishable key dan format dotenv umum', () {
    const source = '''
# public mobile client configuration
export SUPABASE_URL="https://example.supabase.co"
SUPABASE_PUBLISHABLE_KEY='sb_publishable_example'
''';

    final config = SupabaseClientConfig.fromEnvText(source);

    expect(config.url, 'https://example.supabase.co');
    expect(config.publishableKey, 'sb_publishable_example');
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
}
