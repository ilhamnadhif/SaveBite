import 'package:flutter_test/flutter_test.dart';
import 'package:savebite/data/mappers.dart';
import 'package:savebite/data/models.dart';

void main() {
  test('withdrawal_reversal tetap dibedakan dari pendapatan order', () {
    final record = txFromMap({
      'id': 'tx-reversal',
      'kind': 'withdrawal_reversal',
      'title': 'Saldo payout dikembalikan',
      'subtitle': 'Rekening tujuan ditolak',
      'amount': 100000,
    });

    expect(record.kind, TxKind.reversal);
    expect(record.title, 'Saldo payout dikembalikan');
    expect(record.amount, 100000);
  });

  test('status rekening rejected dan disabled tidak dianggap pending', () {
    final rejected = bankAccountFromMap({
      'id': 'bank-r',
      'bank_code': 'BCA',
      'account_number_last4': '1234',
      'account_holder': 'TEST USER',
      'status': 'rejected',
    });
    final disabled = bankAccountFromMap({
      'id': 'bank-d',
      'bank_code': 'BNI',
      'account_number_last4': '5678',
      'account_holder': 'TEST USER',
      'status': 'disabled',
    });

    expect(rejected.status, BankAccountStatus.rejected);
    expect(disabled.status, BankAccountStatus.disabled);
    expect(rejected.verified, isFalse);
    expect(disabled.verified, isFalse);
  });
}
