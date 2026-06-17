import '../theme/app_colors.dart';
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
double _asDouble(dynamic v) => (v is num) ? v.toDouble() : (double.tryParse('$v') ?? 0);
String _str(dynamic v) => v == null ? '' : v.toString();

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
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
  final id = _str(m['id']);
  final logo = _str(m['logo_url']);
  return Merchant(
    id: id,
    name: _str(m['store_name']),
    initial: initialOf(m['store_name']),
    avatarColor: _avatarPalette[id.hashCode.abs() % _avatarPalette.length],
    category: _str(m['category']),
    rating: _asDouble(m['rating']),
    reviewCount: _asInt(m['review_count']),
    distance: _str(m['distance']),
    address: _str(m['address']),
    hours: _hoursOf(m['open_time'], m['close_time']),
    coverImage: logo.isNotEmpty ? logo : 'assets/images/food1.jpg',
    bagsSaved: _asInt(m['bags_saved']),
  );
}

Bag bagFromMap(Map<String, dynamic> m, {Merchant? merchant}) {
  final mer = merchant ??
      merchantFromMap((m['merchants'] ?? m['merchant']) as Map<String, dynamic>);
  final qLeft = _asInt(m['quantity_left']);
  final img = _str(m['image_url']);
  return Bag(
    id: _str(m['id']),
    merchant: mer,
    title: _str(m['title']),
    description: _str(m['description']),
    originalPrice: _asInt(m['original_price']),
    salePrice: _asInt(m['sale_price']),
    quantityLeft: qLeft,
    quantityTotal: _asInt(m['quantity_total']),
    pickupWindow: _str(m['pickup_window']),
    image: img.isNotEmpty ? img : 'assets/images/food1.jpg',
    contents: ((m['contents'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    soldOut: _str(m['status']) == 'sold_out' || qLeft <= 0,
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
    pickupWindow: _str(m['pickup_window']).isEmpty ? '—' : _str(m['pickup_window']),
    sold: total - left,
    total: total,
    image: img.isNotEmpty ? img : 'assets/images/food1.jpg',
    active: status == 'active',
    statusNote: status == 'sold_out' ? 'Habis terjual' : null,
  );
}

OrderRecord orderRecordFromMap(Map<String, dynamic> m) {
  final bag = bagFromMap(m['surprise_bags'] as Map<String, dynamic>);
  final st = _str(m['status']);
  final status = st == 'redeemed'
      ? OrderStatus.done
      : (st == 'expired' || st == 'cancelled')
          ? OrderStatus.expired
          : OrderStatus.ready;
  return OrderRecord(
    bag: bag,
    code: _str(m['pickup_code']),
    dateLabel: dateLabel(m['created_at']),
    amount: _asInt(m['total_amount']),
    status: status,
    quantity: _asInt(m['quantity']) == 0 ? 1 : _asInt(m['quantity']),
    paymentMethod: _str(m['payment_method']).isEmpty ? 'GoPay' : _str(m['payment_method']),
    canRate: status == OrderStatus.done,
  );
}

IncomingOrder incomingOrderFromMap(Map<String, dynamic> m) {
  final profile = m['profiles'] as Map<String, dynamic>?;
  final raw = _str(m['consumer_name']).isNotEmpty
      ? _str(m['consumer_name'])
      : _str(profile?['name']);
  final name = raw.isEmpty ? 'Pelanggan' : raw;
  return IncomingOrder(
    customer: name,
    initial: initials2(name),
    time: timeLabel(m['created_at']),
    bags: _asInt(m['quantity']) == 0 ? 1 : _asInt(m['quantity']),
    code: _str(m['pickup_code']),
    redeemed: _str(m['status']) == 'redeemed',
  );
}

AppNotification notificationFromMap(Map<String, dynamic> m) => AppNotification(
      title: _str(m['title']),
      body: _str(m['body']),
      time: timeLabel(m['created_at']),
      type: _notifType(m['type']),
      group: _str(m['group_label']).isEmpty ? 'Hari ini' : _str(m['group_label']),
      unread: m['read'] != true,
    );

TxRecord txFromMap(Map<String, dynamic> m) => TxRecord(
      title: _str(m['title']),
      subtitle: _str(m['subtitle']),
      amount: _asInt(m['amount']),
      kind: _str(m['kind']) == 'withdrawal' ? TxKind.withdrawal : TxKind.income,
    );

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
    );
