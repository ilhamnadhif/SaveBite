/// Kontrak deep link pembayaran. Parameter dari URL hanya dipakai untuk
/// membuka layar pesanan; status transaksi selalu disinkronkan dari backend.
class PaymentLinks {
  PaymentLinks._();

  static const scheme = 'com.savebite';
  static const host = 'payment-callback';
  static const callbackUrl = '$scheme://$host/';

  static bool isPaymentCallback(Uri uri) =>
      uri.scheme.toLowerCase() == scheme && uri.host.toLowerCase() == host;
}
