import 'package:flutter_test/flutter_test.dart';
import 'package:savebite/data/backend/backend.dart';
import 'package:savebite/data/backend/supabase_backend.dart';
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

  test('nama bank kode-only memakai label yang ramah pengguna', () {
    final bsi = bankAccountFromMap({
      'id': 'bank-bsi',
      'bank_code': 'BSI',
      'bank_name': 'BSI',
      'account_number_last4': '1234',
      'account_holder': 'TEST USER',
      'status': 'pending',
    });
    final explicitName = bankAccountFromMap({
      'id': 'bank-custom',
      'bank_code': 'BCA',
      'bank_name': 'Bank Central Asia',
      'account_number_last4': '5678',
      'account_holder': 'TEST USER',
      'status': 'pending',
    });

    expect(bsi.bankName, 'Bank Syariah Indonesia');
    expect(bsi.label, 'Bank Syariah Indonesia · •••• 1234');
    expect(explicitName.bankName, 'Bank Central Asia');
  });

  test('payload RPC rekening dinormalisasi sesuai kontrak server', () {
    final params = SupabaseBackend.buildBankAccountRpcParams(
      bankCode: ' bca ',
      accountNumber: '1234-5678 90',
      accountHolder: '  TEST USER  ',
      idempotencyKey: ' bank-request-1 ',
    );

    expect(params, {
      'p_bank_code': 'BCA',
      'p_account_holder': 'TEST USER',
      'p_account_number': '1234567890',
      'p_idempotency_key': 'bank-request-1',
    });
  });

  test('payload RPC rekening menolak data invalid sebelum request', () {
    expect(
      () => SupabaseBackend.buildBankAccountRpcParams(
        bankCode: 'BCA',
        accountNumber: '12345',
        accountHolder: 'TEST USER',
        idempotencyKey: 'bank-request-2',
      ),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          'invalid_bank_account_number',
        ),
      ),
    );
  });

  test('respons RPC object dan single-row list dipetakan identik', () {
    const row = <String, dynamic>{
      'id': 'bank-remote',
      'bank_code': 'BCA',
      'bank_name': 'Bank Central Asia',
      'account_number_last4': '7890',
      'account_holder': 'TEST USER',
      'status': 'pending',
      'is_default': true,
    };

    for (final response in <dynamic>[
      row,
      const [row],
    ]) {
      final decoded = SupabaseBackend.decodeRpcRow(response);
      final account = bankAccountFromMap(decoded);
      expect(account.id, 'bank-remote');
      expect(account.accountNumberMasked, '•••• 7890');
      expect(account.status, BankAccountStatus.pending);
      expect(account.isDefault, isTrue);
    }
  });

  test('error RPC rekening tidak jatuh ke pesan server generik', () {
    final invalidNumber = SupabaseBackend.bankAccountExceptionFromMessage(
      'invalid account number',
    );
    final unavailable = SupabaseBackend.bankAccountExceptionFromMessage(
      'bank security configuration is unavailable',
    );

    expect(invalidNumber?.code, 'invalid_bank_account_number');
    expect(invalidNumber?.message, contains('6–20 digit'));
    expect(unavailable?.code, 'bank_registration_unavailable');
    expect(unavailable?.message, isNot(contains('security configuration')));
    expect(
      SupabaseBackend.bankAccountExceptionFromMessage('insufficient stock'),
      isNull,
    );
  });

  test('hanya kegagalan ambigu pendaftaran rekening yang aman diulang', () {
    expect(
      SupabaseBackend.shouldRetryBankAccountRegistration(
        const BackendException('invalid_response', 'Respons terputus.'),
      ),
      isTrue,
    );
    expect(
      SupabaseBackend.shouldRetryBankAccountRegistration(
        StateError('network response closed'),
      ),
      isTrue,
    );
    expect(
      SupabaseBackend.shouldRetryBankAccountRegistration(
        const BackendException(
          'invalid_bank_account_number',
          'Nomor rekening invalid.',
        ),
      ),
      isFalse,
    );
    expect(
      SupabaseBackend.shouldRetryBankAccountRegistration(
        const BackendException('not_authenticated', 'Sesi berakhir.'),
      ),
      isFalse,
    );
  });
}
