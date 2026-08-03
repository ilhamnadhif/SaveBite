import '../config/env.dart';
import 'payment_link_service.dart';

/// Nilai checkout Snap yang telah lolos validasi client-side.
///
/// Validasi ini bukan sumber kebenaran status pembayaran. Ia hanya memastikan
/// aplikasi tidak memuat URL atau script di luar endpoint Midtrans yang sudah
/// ditentukan. Status lunas selalu berasal dari backend.
class SnapCheckoutSession {
  static final RegExp _clientKeyPattern = RegExp(
    r'^Mid-client-[A-Za-z0-9_-]{8,128}$',
  );
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{8,512}$');

  final Uri redirectUri;
  final String token;
  final String clientKey;
  final String environment;
  final Uri supabaseOrigin;

  const SnapCheckoutSession._({
    required this.redirectUri,
    required this.token,
    required this.clientKey,
    required this.environment,
    required this.supabaseOrigin,
  });

  static SnapCheckoutSession? tryParse(
    String? rawRedirectUrl, {
    String? snapToken,
    String? clientKey,
    String? environment,
    String? supabaseUrl,
  }) {
    final raw = rawRedirectUrl?.trim();
    final effectiveToken = snapToken?.trim() ?? '';
    final effectiveKey = (clientKey ?? Env.midtransClientKey).trim();
    final effectiveEnvironment = (environment ?? Env.midtransEnvironment)
        .trim()
        .toLowerCase();
    final effectiveSupabaseUrl = (supabaseUrl ?? Env.supabaseUrl).trim();
    if (raw == null ||
        raw.isEmpty ||
        !_tokenPattern.hasMatch(effectiveToken) ||
        !_clientKeyPattern.hasMatch(effectiveKey) ||
        !const {'sandbox', 'production'}.contains(effectiveEnvironment)) {
      return null;
    }

    final redirect = Uri.tryParse(raw);
    final supabase = Uri.tryParse(effectiveSupabaseUrl);
    if (redirect == null ||
        supabase == null ||
        !_isSafeHttpsUri(redirect) ||
        !_isSafeHttpsUri(supabase) ||
        !supabase.host.endsWith('.supabase.co')) {
      return null;
    }

    final expectedHost = effectiveEnvironment == 'sandbox'
        ? 'app.sandbox.midtrans.com'
        : 'app.midtrans.com';
    if (redirect.host != expectedHost ||
        redirect.hasQuery ||
        redirect.hasFragment) {
      return null;
    }

    final segments = redirect.pathSegments;
    final isV2 =
        segments.length == 4 &&
        segments[0] == 'snap' &&
        segments[1] == 'v2' &&
        segments[2] == 'vtweb';
    final isV3 =
        segments.length == 4 &&
        segments[0] == 'snap' &&
        segments[1] == 'v3' &&
        segments[2] == 'redirection';
    final isV4 =
        segments.length == 4 &&
        segments[0] == 'snap' &&
        segments[1] == 'v4' &&
        segments[2] == 'redirection';
    // The redirect resource ID and Snap.js token are independent values in
    // Midtrans' response. Validate both, but never assume they are equal.
    if ((!isV2 && !isV3 && !isV4) || !_tokenPattern.hasMatch(segments[3])) {
      return null;
    }

    return SnapCheckoutSession._(
      redirectUri: redirect,
      token: effectiveToken,
      clientKey: effectiveKey,
      environment: effectiveEnvironment,
      supabaseOrigin: Uri(
        scheme: supabase.scheme,
        host: supabase.host,
        port: supabase.hasPort ? supabase.port : null,
      ),
    );
  }

  /// Hanya initial Snap document dan bridge return Supabase yang boleh menjadi
  /// navigasi frame utama WebView. Resource halaman tetap dimuat oleh WebView.
  bool allowsMainFrameNavigation(Uri uri) {
    if (uri == redirectUri) return true;
    return _isSafeHttpsUri(uri) &&
        uri.scheme == supabaseOrigin.scheme &&
        uri.host == supabaseOrigin.host &&
        uri.port == supabaseOrigin.port &&
        uri.path == '/functions/v1/midtrans-return' &&
        !uri.hasFragment;
  }

  bool isAppCallback(Uri uri) => PaymentLinks.isPaymentCallback(uri);

  static bool _isSafeHttpsUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;
}
