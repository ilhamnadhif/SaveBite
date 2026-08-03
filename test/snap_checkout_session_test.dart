import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/services/snap_checkout_session.dart';

void main() {
  const clientKey = 'Mid-client-publicExample123';
  const supabaseUrl = 'https://project-ref.supabase.co';

  test('menerima URL Snap sandbox v2 dan mengekstrak token', () {
    final session = SnapCheckoutSession.tryParse(
      'https://app.sandbox.midtrans.com/snap/v2/vtweb/redirect_987654321',
      snapToken: 'token_123456789',
      clientKey: clientKey,
      environment: 'sandbox',
      supabaseUrl: supabaseUrl,
    );

    expect(session, isNotNull);
    expect(session!.token, 'token_123456789');
    expect(session.redirectUri.pathSegments.last, 'redirect_987654321');
    expect(session.environment, 'sandbox');
  });

  test('menolak token Snap hilang atau tidak valid', () {
    const url =
        'https://app.sandbox.midtrans.com/snap/v3/redirection/redirect_123456';
    expect(
      SnapCheckoutSession.tryParse(
        url,
        clientKey: clientKey,
        environment: 'sandbox',
        supabaseUrl: supabaseUrl,
      ),
      isNull,
    );
    expect(
      SnapCheckoutSession.tryParse(
        url,
        snapToken: 'token.with.dots',
        clientKey: clientKey,
        environment: 'sandbox',
        supabaseUrl: supabaseUrl,
      ),
      isNull,
    );
  });

  test(
    'menerima URL Snap production v3 hanya untuk environment production',
    () {
      final production = SnapCheckoutSession.tryParse(
        'https://app.midtrans.com/snap/v3/redirection/redirect_123456',
        snapToken: 'prodToken_123456',
        clientKey: clientKey,
        environment: 'production',
        supabaseUrl: supabaseUrl,
      );
      final mismatched = SnapCheckoutSession.tryParse(
        'https://app.midtrans.com/snap/v3/redirection/redirect_123456',
        snapToken: 'prodToken_123456',
        clientKey: clientKey,
        environment: 'sandbox',
        supabaseUrl: supabaseUrl,
      );

      expect(production, isNotNull);
      expect(mismatched, isNull);
    },
  );

  test('menerima URL redirection Snap v4 yang dipakai sandbox terbaru', () {
    final session = SnapCheckoutSession.tryParse(
      'https://app.sandbox.midtrans.com/snap/v4/redirection/redirect_123456',
      snapToken: 'token_independent_987654',
      clientKey: clientKey,
      environment: 'sandbox',
      supabaseUrl: supabaseUrl,
    );

    expect(session, isNotNull);
    expect(session!.token, 'token_independent_987654');
  });

  test('menolak host, credential, query, path, dan Client Key tidak tepercaya', () {
    SnapCheckoutSession? parse(String url, {String key = clientKey}) =>
        SnapCheckoutSession.tryParse(
          url,
          snapToken: 'token_123456789',
          clientKey: key,
          environment: 'sandbox',
          supabaseUrl: supabaseUrl,
        );

    expect(
      parse(
        'https://app.sandbox.midtrans.com.attacker.test/snap/v2/vtweb/token_123456789',
      ),
      isNull,
    );
    expect(
      parse(
        'https://user@app.sandbox.midtrans.com/snap/v2/vtweb/token_123456789',
      ),
      isNull,
    );
    expect(
      parse(
        'https://app.sandbox.midtrans.com/snap/v2/vtweb/token_123456789?next=evil',
      ),
      isNull,
    );
    expect(
      parse('https://app.sandbox.midtrans.com/snap/v1/vtweb/token_123456789'),
      isNull,
    );
    expect(
      parse(
        'https://app.sandbox.midtrans.com/snap/v2/vtweb/token_123456789',
        key: 'Mid-server-secretValue123',
      ),
      isNull,
    );
  });

  test('WebView hanya mengizinkan dokumen Snap dan return function exact', () {
    final session = SnapCheckoutSession.tryParse(
      'https://app.sandbox.midtrans.com/snap/v2/vtweb/redirect_987654321',
      snapToken: 'token_123456789',
      clientKey: clientKey,
      environment: 'sandbox',
      supabaseUrl: supabaseUrl,
    )!;

    expect(session.allowsMainFrameNavigation(session.redirectUri), isTrue);
    expect(
      session.allowsMainFrameNavigation(
        Uri.parse(
          'https://project-ref.supabase.co/functions/v1/midtrans-return?order_id=ignored',
        ),
      ),
      isTrue,
    );
    expect(
      session.allowsMainFrameNavigation(
        Uri.parse('https://project-ref.supabase.co/functions/v1/other'),
      ),
      isFalse,
    );
    expect(
      session.allowsMainFrameNavigation(
        Uri.parse('https://app.sandbox.midtrans.com/snap/v2/other'),
      ),
      isFalse,
    );
    expect(
      session.isAppCallback(
        Uri.parse('com.savebite://payment-callback/?ignored=1'),
      ),
      isTrue,
    );
  });
}
