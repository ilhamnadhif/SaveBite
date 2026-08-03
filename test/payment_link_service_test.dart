import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/services/payment_link_service.dart';

void main() {
  test('hanya callback Midtrans SaveBite yang diterima', () {
    expect(
      PaymentLinks.isPaymentCallback(
        Uri.parse(
          'com.savebite://payment-callback/?order_id=SB-1&transaction_status=settlement',
        ),
      ),
      isTrue,
    );
    expect(
      PaymentLinks.isPaymentCallback(
        Uri.parse('com.savebite://login-callback?code=oauth'),
      ),
      isFalse,
    );
    expect(
      PaymentLinks.isPaymentCallback(
        Uri.parse('https://attacker.example/payment-callback'),
      ),
      isFalse,
    );
    expect(
      PaymentLinks.isPaymentCallback(
        Uri.parse('https://savebite.example/?savebite_payment_return=1'),
        webOrigin: Uri.parse('https://savebite.example/'),
      ),
      isTrue,
    );
    expect(
      PaymentLinks.isPaymentCallback(
        Uri.parse('https://attacker.example/?savebite_payment_return=1'),
        webOrigin: Uri.parse('https://savebite.example/'),
      ),
      isFalse,
    );
  });
}
