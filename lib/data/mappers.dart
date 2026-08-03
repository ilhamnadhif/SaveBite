import '../theme/app_colors.dart';
import '../services/notification_route.dart';
import 'models.dart';

/// Konversi baris Supabase (Map) → model. Hanya dipakai oleh SupabaseBackend.

const _avatarPalette = [
  AppColors.amberAvatar,
  AppColors.greenBright,
  AppColors.terracotta,
  AppColors.greenAccent,
  AppColors.brown,
  AppColors.bca,
  AppColors.ovo,
  AppColors.green,
];

String initialOf(String? name) {
  final n = (name ?? '').trim();
  return n.isEmpty ? '?' : n[0].toUpperCase();
}

String initials2(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

String _hoursOf(dynamic open, dynamic close) =>
    '${open ?? '08.00'}–${close ?? '21.00'}';

int _asInt(dynamic v) => (v is num) ? v.toInt() : (int.tryParse('$v') ?? 0);
double _asDouble(dynamic v) =>
    (v is num) ? v.toDouble() : (double.tryParse('$v') ?? 0);
String _str(dynamic v) => v == null ? '' : v.toString();
DateTime? _asDate(dynamic v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();
Map<String, dynamic>? _asMap(dynamic value) =>
    value is Map<String, dynamic> ? value : null;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

String dateLabel(dynamic ts) {
  final dt = DateTime.tryParse('$ts')?.toLocal();
  if (dt == null) return '';
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return 'Hari ini';
  }
  return '${dt.day} ${_months[dt.month - 1]}';
}

String timeLabel(dynamic ts) {
  final dt = DateTime.tryParse('$ts')?.toLocal();
  if (dt == null) return '';
  return '${dt.hour.toString().padLeft(2, '0')}.${dt.minute.toString().padLeft(2, '0')}';
}

NotifType _notifType(dynamic t) {
  switch ('$t') {
    case 'ready':
      return NotifType.ready;
    case 'newBag':
      return NotifType.newBag;
    case 'rating':
      return NotifType.rating;
    default:
      return NotifType.payment;
  }
}

Merchant merchantFromMap(Map<String, dynamic> m) {
  final id = _str(m['merchant_id'] ?? m['id']);
  final name = _str(m['store_name'] ?? m['merchant_name']);
  final logo = _str(m['logo_url'] ?? m['merchant_logo_url']);
  final lat = m['lat'] ?? m['merchant_lat'];
  final lng = m['lng'] ?? m['merchant_lng'];
  return Merchant(
    id: id,
    name: name.isEmpty ? 'Toko' : name,
    initial: initialOf(name),
    avatarColor: _avatarPalette[id.hashCode.abs() % _avatarPalette.length],
    category: _str(m['category'] ?? m['merchant_category']),
    rating: _asDouble(m['rating'] ?? m['merchant_rating']),
    reviewCount: _asInt(m['review_count'] ?? m['merchant_review_count']),
    distance: _str(m['distance'] ?? m['merchant_distance']),
    address: _str(m['address'] ?? m['merchant_address']),
    hours: _hoursOf(
      m['open_time'] ?? m['merchant_open_time'],
      m['close_time'] ?? m['merchant_close_time'],
    ),
    coverImage: logo.isNotEmpty ? logo : 'assets/images/food1.jpg',
    bagsSaved: _asInt(m['bags_saved'] ?? m['merchant_bags_saved']),
    latitude: lat == null ? null : _asDouble(lat),
    longitude: lng == null ? null : _asDouble(lng),
  );
}

Bag bagFromMap(Map<String, dynamic> m, {Merchant? merchant}) {
  final nestedMerchant = _asMap(m['merchants']) ?? _asMap(m['merchant']);
  final mer = merchant ?? merchantFromMap(nestedMerchant ?? m);
  final qLeft = _asInt(m['quantity_left']);
  final img = _str(m['image_url']);
  final salePrice = _asInt(m['sale_price'] ?? m['unit_price']);
  final originalPrice = _asInt(m['original_price']);
  return Bag(
    id: _str(m['bag_id'] ?? m['id']),
    merchant: mer,
    title: _str(m['title'] ?? m['bag_title']),
    description: _str(m['description'] ?? m['bag_description']),
    originalPrice: originalPrice > 0
        ? originalPrice
        : _asInt(m['original_price_snapshot'] ?? (salePrice * 3)),
    salePrice: salePrice,
    quantityLeft: qLeft,
    quantityTotal: _asInt(m['quantity_total'] ?? m['quantity']),
    pickupWindow: _str(m['pickup_window'] ?? m['pickup_window_snapshot']),
    image: img.isNotEmpty
        ? img
        : (_str(m['bag_image_url']).isNotEmpty
              ? _str(m['bag_image_url'])
              : 'assets/images/food1.jpg'),
    contents: ((m['contents'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    soldOut: _str(m['status']) == 'sold_out' || qLeft <= 0,
    availableOn: _asDate(m['available_on']),
    pickupStartsAt: _asDate(m['pickup_start_at']),
    pickupEndsAt: _asDate(m['pickup_end_at']),
  );
}

MerchantBag merchantBagFromMap(Map<String, dynamic> m) {
  final total = _asInt(m['quantity_total']);
  final left = _asInt(m['quantity_left']);
  final img = _str(m['image_url']);
  final status = _str(m['status']);
  return MerchantBag(
    id: _str(m['id']),
    title: _str(m['title']),
    salePrice: _asInt(m['sale_price']),
    pickupWindow: _str(m['pickup_window']).isEmpty
        ? '—'
        : _str(m['pickup_window']),
    sold: total - left,
    total: total,
    image: img.isNotEmpty ? img : 'assets/images/food1.jpg',
    active: status == 'active',
    statusNote: status == 'sold_out' ? 'Habis terjual' : null,
    description: _str(m['description']),
    contents: ((m['contents'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList(growable: false),
    originalPrice: _asInt(m['original_price']),
    quantityLeft: left,
    availableOn: _asDate(m['available_on']),
    pickupStartsAt: _asDate(m['pickup_start_at']),
    pickupEndsAt: _asDate(m['pickup_end_at']),
  );
}

OrderRecord orderRecordFromMap(Map<String, dynamic> m) {
  final nestedBag = _asMap(m['surprise_bags']) ?? _asMap(m['bag']);
  final bag = bagFromMap(nestedBag ?? m);
  final st = _str(m['status']);
  final status = switch (st) {
    'pending' => OrderStatus.pending,
    'paid' => OrderStatus.pending,
    'preparing' => OrderStatus.pending,
    'ready' => OrderStatus.ready,
    'redeemed' => OrderStatus.done,
    'cancelled' || 'refunded' => OrderStatus.cancelled,
    'expired' => OrderStatus.expired,
    _ => OrderStatus.pending,
  };
  final rawPaymentStatus = _str(m['payment_status']).toLowerCase();
  final rawFraudStatus = _str(m['fraud_status']).toLowerCase();
  final paymentState = switch (rawPaymentStatus) {
    'creating' || 'checkout_created' || 'new' => PaymentState.awaitingPayment,
    'pending' => PaymentState.pending,
    'capture' => switch (rawFraudStatus) {
      'accept' => PaymentState.paid,
      'deny' => PaymentState.failed,
      _ => PaymentState.pending,
    },
    'settlement' || 'paid' => PaymentState.paid,
    'deny' || 'failure' || 'failed' => PaymentState.failed,
    'cancel' || 'cancelled' => PaymentState.cancelled,
    'expire' || 'expired' => PaymentState.expired,
    'refund' || 'refunded' => PaymentState.refunded,
    'partial_refund' ||
    'chargeback' ||
    'partial_chargeback' ||
    'disputed' => PaymentState.disputed,
    // Legacy order tanpa payment_status boleh memakai timestamp pembayaran.
    // Status provider yang tidak dikenal selalu fail-closed dan tidak pernah
    // dianggap lunas hanya karena status fulfillment berubah.
    _ =>
      rawPaymentStatus.isEmpty &&
              (m['payment_verified_at'] != null || m['paid_at'] != null)
          ? PaymentState.paid
          : PaymentState.awaitingPayment,
  };
  final subtotal = _asInt(m['subtotal'] ?? m['subtotal_amount']);
  final fee = _asInt(m['service_fee']);
  final amount = _asInt(m['total_amount']);
  return OrderRecord(
    id: _str(m['order_id'] ?? m['id']),
    bag: bag,
    code: _str(m['order_reference']).isNotEmpty
        ? _str(m['order_reference'])
        : 'SB-${_str(m['order_id'] ?? m['id']).replaceAll('-', '').toUpperCase().padRight(8, '0').substring(0, 8)}',
    dateLabel: dateLabel(m['created_at']),
    amount: amount,
    status: status,
    reviewed: m['reviewed'] == true || m['review_id'] != null,
    quantity: _asInt(m['quantity']) == 0 ? 1 : _asInt(m['quantity']),
    paymentMethod: _str(m['payment_method']).isEmpty
        ? 'QRIS'
        : _str(m['payment_method']),
    canRate:
        status == OrderStatus.done &&
        m['reviewed'] != true &&
        m['review_id'] == null,
    createdAt: _asDate(m['created_at']),
    pickupStartsAt: _asDate(m['pickup_start_at']),
    expiresAt: _asDate(m['expires_at'] ?? m['pickup_end_at']),
    redeemedAt: _asDate(m['redeemed_at']),
    subtotalAmount: subtotal > 0 ? subtotal : amount - fee,
    serviceFee: fee,
    merchantNetAmount: _asInt(m['merchant_net_amount']),
    pickupToken: _str(m['pickup_token']).isEmpty
        ? null
        : _str(m['pickup_token']),
    paymentState: paymentState,
    paymentQrUrl: _str(m['payment_qr_url']).isEmpty
        ? null
        : _str(m['payment_qr_url']),
    paymentSnapToken: _str(m['payment_snap_token']).isEmpty
        ? null
        : _str(m['payment_snap_token']),
    simulatorQrImageUrl: _str(m['simulator_qr_image_url']).isEmpty
        ? null
        : _str(m['simulator_qr_image_url']),
    paymentRedirectUrl: _str(m['payment_redirect_url']).isEmpty
        ? null
        : _str(m['payment_redirect_url']),
    paymentExpiresAt: _asDate(m['payment_expires_at']),
    providerPaymentType: _str(m['payment_type']).isEmpty
        ? null
        : _str(m['payment_type']),
    providerOrderId: _str(m['midtrans_order_id']).isEmpty
        ? null
        : _str(m['midtrans_order_id']),
  );
}

IncomingOrder incomingOrderFromMap(Map<String, dynamic> m) {
  final profile = m['profiles'] as Map<String, dynamic>?;
  final raw = _str(m['consumer_name']).isNotEmpty
      ? _str(m['consumer_name'])
      : _str(profile?['name']);
  final name = raw.isEmpty ? 'Pelanggan' : raw;
  final status = switch (_str(m['status'])) {
    'pending' => IncomingOrderStatus.pending,
    'paid' => IncomingOrderStatus.paid,
    'preparing' => IncomingOrderStatus.preparing,
    'ready' => IncomingOrderStatus.ready,
    'redeemed' => IncomingOrderStatus.redeemed,
    'cancelled' || 'refunded' => IncomingOrderStatus.cancelled,
    'expired' => IncomingOrderStatus.expired,
    // Nilai baru/tidak dikenal tidak boleh menjadi order berbayar yang dapat
    // diproses merchant. View server tetap menyaring pending-payment.
    _ => IncomingOrderStatus.pending,
  };
  final image = _str(m['bag_image_url'] ?? m['image_url']);
  return IncomingOrder(
    id: _str(m['order_id'] ?? m['id']),
    customer: name,
    initial: initials2(name),
    time: timeLabel(m['created_at']),
    bags: _asInt(m['quantity']) == 0 ? 1 : _asInt(m['quantity']),
    code: _str(m['order_reference']).isNotEmpty
        ? _str(m['order_reference'])
        : 'SB-${_str(m['order_id'] ?? m['id']).replaceAll('-', '').toUpperCase().padRight(8, '0').substring(0, 8)}',
    needsAction:
        status == IncomingOrderStatus.paid ||
        status == IncomingOrderStatus.preparing,
    redeemed: status == IncomingOrderStatus.redeemed,
    status: status,
    bagTitle: _str(m['bag_title'] ?? m['title']),
    bagImage: image.isEmpty ? 'assets/images/food1.jpg' : image,
    pickupWindow: _str(m['pickup_window'] ?? m['pickup_window_snapshot']),
    unitPrice: _asInt(m['unit_price'] ?? m['sale_price']),
    subtotalAmount: _asInt(m['subtotal'] ?? m['subtotal_amount']),
    serviceFee: _asInt(m['service_fee']),
    merchantNetAmount: _asInt(m['merchant_net_amount']),
    createdAt: _asDate(m['created_at']),
    pickupStartsAt: _asDate(m['pickup_start_at']),
    expiresAt: _asDate(m['expires_at'] ?? m['pickup_end_at']),
    redeemedAt: _asDate(m['redeemed_at']),
  );
}

MerchantReview merchantReviewFromMap(Map<String, dynamic> m) {
  final name = _str(m['customer_name'] ?? m['consumer_name']);
  return MerchantReview(
    id: _str(m['review_id'] ?? m['id']),
    orderId: _str(m['order_id']),
    orderReference: _str(m['order_reference']).isEmpty
        ? 'Pesanan'
        : _str(m['order_reference']),
    customerName: name.isEmpty ? 'Pelanggan' : name,
    rating: _asInt(m['rating']).clamp(1, 5),
    tags: ((m['tags'] as List?) ?? const [])
        .map((tag) => tag.toString())
        .where((tag) => tag.trim().isNotEmpty)
        .toList(growable: false),
    comment: _str(m['comment']),
    createdAt: _asDate(m['created_at']),
  );
}

AppNotification notificationFromMap(Map<String, dynamic> m) {
  final data = _asMap(m['data']);
  var route =
      whitelistedNotificationRoute(_str(m['route'])) ??
      whitelistedNotificationRoute(_str(data?['route'])) ??
      whitelistedNotificationRoute(
        _str(m['dedupe_key']),
        dynamicOrderOnly: true,
      ) ??
      '';
  if (route.isEmpty) {
    route = switch (_str(m['entity_type'])) {
      'order' =>
        _str(m['title']).toLowerCase().contains('pesanan baru')
            ? 'merchant_orders'
            : 'orders',
      'review' => 'merchant_reviews',
      'payout' || 'bank_account' => 'merchant_balance',
      'bag' => 'consumer_home',
      _ => '',
    };
  }
  return AppNotification(
    id: _str(m['id']),
    title: _str(m['title']),
    body: _str(m['body']),
    time: timeLabel(m['created_at']),
    type: _notifType(m['type']),
    group: _str(m['group_label']).isEmpty ? 'Hari ini' : _str(m['group_label']),
    unread: m['read'] != true,
    route: route.isEmpty ? null : route,
    createdAt: _asDate(m['created_at']),
  );
}

TxRecord txFromMap(Map<String, dynamic> m) {
  final kind = switch (_str(m['kind'])) {
    'withdrawal' => TxKind.withdrawal,
    'withdrawal_reversal' => TxKind.reversal,
    _ => TxKind.income,
  };
  return TxRecord(
    id: _str(m['id']),
    title: _str(m['title']),
    subtitle: _str(m['subtitle']),
    amount: _asInt(m['amount']),
    kind: kind,
    createdAt: _asDate(m['created_at']),
    status: _str(m['status']).isEmpty ? 'completed' : _str(m['status']),
  );
}

Profile profileFromMap(Map<String, dynamic> m) => Profile(
  id: _str(m['id']),
  name: _str(m['name']).isEmpty ? 'Pengguna' : _str(m['name']),
  email: _str(m['email']),
  phone: _str(m['phone']),
  avatarUrl: _str(m['avatar_url']).isEmpty ? null : _str(m['avatar_url']),
  lastMode: _str(m['last_mode']).isEmpty ? 'consumer' : _str(m['last_mode']),
);

StoreProfile storeFromMap(Map<String, dynamic> m) => StoreProfile(
  id: _str(m['id']),
  name: _str(m['store_name']),
  category: _str(m['category']).isEmpty ? 'Bakery' : _str(m['category']),
  address: _str(m['address']),
  openTime: _str(m['open_time']).isEmpty ? '08.00' : _str(m['open_time']),
  closeTime: _str(m['close_time']).isEmpty ? '21.00' : _str(m['close_time']),
  description: _str(m['description']),
  logoUrl: _str(m['logo_url']).isEmpty ? null : _str(m['logo_url']),
  latitude: m['lat'] == null ? null : _asDouble(m['lat']),
  longitude: m['lng'] == null ? null : _asDouble(m['lng']),
);

BankAccount bankAccountFromMap(Map<String, dynamic> m) {
  final code = _str(m['bank_code']).toUpperCase();
  final rawName = _str(m['bank_name']).trim();
  final last4 = _str(m['account_number_last4']);
  final masked = _str(m['account_number_masked']);
  final status = switch (_str(m['status'])) {
    'verified' => BankAccountStatus.verified,
    'rejected' => BankAccountStatus.rejected,
    'disabled' => BankAccountStatus.disabled,
    _ when m['verified'] == true => BankAccountStatus.verified,
    _ => BankAccountStatus.pending,
  };
  return BankAccount(
    id: _str(m['id'] ?? m['bank_account_id']),
    bankCode: code,
    bankName: _bankDisplayName(code, rawName),
    accountNumberMasked: masked.isNotEmpty
        ? masked
        : (last4.isEmpty ? '••••' : '•••• $last4'),
    accountHolder: _str(m['account_holder']),
    status: status,
    isDefault: m['is_default'] == true,
  );
}

String _bankDisplayName(String code, String rawName) {
  if (rawName.isNotEmpty && rawName.toUpperCase() != code) return rawName;
  return switch (code) {
    'BCA' => 'BCA',
    'MANDIRI' => 'Bank Mandiri',
    'BNI' => 'BNI',
    'BRI' => 'BRI',
    'BSI' => 'Bank Syariah Indonesia',
    'PERMATA' => 'Bank Permata',
    'CIMB' => 'CIMB Niaga',
    _ => rawName.isEmpty ? code : rawName,
  };
}

PayoutRequest payoutRequestFromMap(
  Map<String, dynamic> m, {
  BankAccount? bankAccount,
}) {
  final nested = _asMap(m['bank_accounts']) ?? _asMap(m['bank_account']);
  final account =
      bankAccount ??
      bankAccountFromMap(
        nested ??
            <String, dynamic>{
              'id': m['bank_account_id'],
              'bank_code': m['bank_code'],
              'bank_name': m['bank_name'],
              'account_number_last4': m['account_number_last4'],
              'account_holder': m['account_holder'],
              'status': 'verified',
            },
      );
  final status = switch (_str(m['status'])) {
    'processing' => PayoutStatus.processing,
    'paid' => PayoutStatus.paid,
    'failed' => PayoutStatus.failed,
    'cancelled' => PayoutStatus.cancelled,
    _ => PayoutStatus.pending,
  };
  final gross = _asInt(m['gross_amount'] ?? m['amount']);
  final fee = _asInt(m['fee_amount']);
  return PayoutRequest(
    id: _str(m['id'] ?? m['payout_request_id']),
    grossAmount: gross,
    feeAmount: fee,
    netAmount: _asInt(m['net_amount']) > 0
        ? _asInt(m['net_amount'])
        : gross - fee,
    status: status,
    bankAccount: account,
    createdAt: _asDate(m['created_at'] ?? m['requested_at']),
  );
}
