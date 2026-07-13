/// Nilai bisnis non-rahasia yang juga dipakai RPC transaksi di database.
/// Default menjaga aplikasi tetap dapat dipakai saat konfigurasi remote gagal.
class BusinessConfig {
  final int serviceFee;
  final int merchantCommissionBps;
  final int withdrawalFee;
  final int minimumWithdrawal;
  final bool paymentsEnabled;
  final bool payoutsEnabled;

  const BusinessConfig({
    this.serviceFee = 1000,
    this.merchantCommissionBps = 1000,
    this.withdrawalFee = 2500,
    this.minimumWithdrawal = 50000,
    this.paymentsEnabled = false,
    this.payoutsEnabled = false,
  });

  factory BusinessConfig.fromMap(Map<String, dynamic> map) {
    int positive(String key, int fallback) {
      final value = (map[key] as num?)?.toInt();
      return value == null || value < 0 ? fallback : value;
    }

    return BusinessConfig(
      serviceFee: positive('service_fee', 1000),
      merchantCommissionBps: positive(
        'merchant_commission_bps',
        1000,
      ).clamp(0, 10000),
      withdrawalFee: positive('withdrawal_fee', 2500),
      minimumWithdrawal: positive('minimum_withdrawal', 50000),
      paymentsEnabled: map['payments_enabled'] == true,
      payoutsEnabled: map['payouts_enabled'] == true,
    );
  }
}
