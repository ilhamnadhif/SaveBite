import 'package:flutter_test/flutter_test.dart';
import 'package:savebite/data/business_config.dart';

void main() {
  test('BusinessConfig membaca nilai server yang valid', () {
    final config = BusinessConfig.fromMap({
      'service_fee': 1500,
      'merchant_commission_bps': 1250,
      'withdrawal_fee': 3000,
      'minimum_withdrawal': 75000,
      'payments_enabled': true,
      'payouts_enabled': true,
    });

    expect(config.serviceFee, 1500);
    expect(config.merchantCommissionBps, 1250);
    expect(config.withdrawalFee, 3000);
    expect(config.minimumWithdrawal, 75000);
    expect(config.paymentsEnabled, isTrue);
    expect(config.payoutsEnabled, isTrue);
  });

  test('BusinessConfig menolak nilai negatif dan membatasi komisi', () {
    final config = BusinessConfig.fromMap({
      'service_fee': -1,
      'merchant_commission_bps': 25000,
      'withdrawal_fee': -10,
      'minimum_withdrawal': -50,
    });

    expect(config.serviceFee, 1000);
    expect(config.merchantCommissionBps, 10000);
    expect(config.withdrawalFee, 2500);
    expect(config.minimumWithdrawal, 50000);
    expect(config.paymentsEnabled, isFalse);
    expect(config.payoutsEnabled, isFalse);
  });
}
