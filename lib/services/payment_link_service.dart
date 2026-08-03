/// Kontrak deep link pembayaran. Parameter dari URL hanya dipakai untuk
/// membuka layar pesanan; status transaksi selalu disinkronkan dari backend.
class PaymentLinks {
  PaymentLinks._();

  static const scheme = 'com.savebite';
  static const host = 'payment-callback';
  static const callbackUrl = '$scheme://$host/';
  static const webMarker = 'savebite_payment_return';

  static bool isPaymentCallback(Uri uri, {Uri? webOrigin}) {
    final mobile =
        uri.scheme.toLowerCase() == scheme && uri.host.toLowerCase() == host;
    if (mobile) return true;
    if (webOrigin == null || uri.queryParameters[webMarker] != '1') {
      return false;
    }
    return _sameOrigin(uri, webOrigin);
  }

  static bool _sameOrigin(Uri left, Uri right) =>
      left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      left.port == right.port;
}
