import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../mappers.dart';
import '../models.dart';
import 'backend.dart';

/// Backend Supabase: Postgres (tabel + RPC), Storage, dengan RLS.
class SupabaseBackend implements Backend {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  @override
  bool get isRemote => true;

  String? _storeIdCache;
  Future<String?> _storeId() async {
    if (_storeIdCache != null) return _storeIdCache;
    final uid = _uid;
    if (uid == null) return null;
    final row = await _sb
        .from('merchants')
        .select('id')
        .eq('user_id', uid)
        .maybeSingle();
    return _storeIdCache = row?['id']?.toString();
  }

  // ── Profil ──
  @override
  Future<Profile?> currentProfile() async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;
    final row =
        await _sb.from('profiles').select().eq('id', user.id).maybeSingle();
    if (row != null) return profileFromMap(row);
    // fallback dari metadata auth bila baris profil belum sempat dibuat trigger
    return Profile(
      id: user.id,
      name: (user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'Pengguna')
          .toString(),
      email: user.email ?? '',
      avatarUrl: user.userMetadata?['avatar_url']?.toString(),
    );
  }

  @override
  Future<void> updateProfile(
      {String? name, String? email, String? phone, String? avatarUrl}) async {
    final uid = _uid;
    if (uid == null) return;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (email != null) data['email'] = email;
    if (phone != null) data['phone'] = phone;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (data.isEmpty) return;
    await _sb.from('profiles').update(data).eq('id', uid);
  }

  @override
  Future<void> setLastMode(String mode) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('profiles').update({'last_mode': mode}).eq('id', uid);
  }

  // ── Browse ──
  @override
  Future<List<Bag>> nearbyBags() async {
    final rows = await _sb
        .from('surprise_bags')
        .select('*, merchants(*)')
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (rows as List).map((e) => bagFromMap(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Bag>> searchBags(String query) async {
    final all = await nearbyBags();
    final q = query.toLowerCase();
    return all
        .where((b) =>
            b.title.toLowerCase().contains(q) ||
            b.merchant.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Bag>> bagsByMerchant(String merchantId) async {
    final rows = await _sb
        .from('surprise_bags')
        .select('*, merchants(*)')
        .eq('merchant_id', merchantId)
        .eq('status', 'active');
    return (rows as List).map((e) => bagFromMap(e as Map<String, dynamic>)).toList();
  }

  // ── Favorit ──
  @override
  Future<Set<String>> favoriteMerchantIds() async {
    final uid = _uid;
    if (uid == null) return {};
    final rows =
        await _sb.from('favorites').select('merchant_id').eq('consumer_id', uid);
    return (rows as List).map((e) => e['merchant_id'].toString()).toSet();
  }

  @override
  Future<bool> toggleFavorite(String merchantId) async {
    final uid = _uid;
    if (uid == null) return false;
    final existing = await _sb
        .from('favorites')
        .select()
        .eq('consumer_id', uid)
        .eq('merchant_id', merchantId)
        .maybeSingle();
    if (existing == null) {
      await _sb.from('favorites').insert({'consumer_id': uid, 'merchant_id': merchantId});
      return true;
    } else {
      await _sb
          .from('favorites')
          .delete()
          .eq('consumer_id', uid)
          .eq('merchant_id', merchantId);
      return false;
    }
  }

  @override
  Future<List<FavoriteStore>> favoriteStores() async {
    final ids = await favoriteMerchantIds();
    if (ids.isEmpty) return [];
    final merchants = await _sb.from('merchants').select().inFilter('id', ids.toList());
    final counts = await _sb
        .from('surprise_bags')
        .select('merchant_id')
        .eq('status', 'active')
        .inFilter('merchant_id', ids.toList());
    final byMerchant = <String, int>{};
    for (final c in (counts as List)) {
      final mid = c['merchant_id'].toString();
      byMerchant[mid] = (byMerchant[mid] ?? 0) + 1;
    }
    return (merchants as List).map((e) {
      final m = merchantFromMap(e as Map<String, dynamic>);
      final n = byMerchant[m.id] ?? 0;
      return FavoriteStore(
        merchant: m,
        availability: n > 0 ? '$n bag tersedia' : 'Habis hari ini',
        soldOut: n == 0,
      );
    }).toList();
  }

  // ── Pesanan konsumen ──
  @override
  Future<OrderRecord> placeOrder(Bag bag, int qty, String method) async {
    final res = await _sb.rpc('purchase_bag', params: {
      'p_bag_id': bag.id,
      'p_qty': qty,
      'p_method': method,
    });
    final row = (res is List ? res.first : res) as Map<String, dynamic>;
    return OrderRecord(
      bag: bag,
      code: (row['pickup_code'] ?? '').toString(),
      dateLabel: 'Hari ini',
      amount: (row['total_amount'] as num?)?.toInt() ?? bag.salePrice * qty,
      status: OrderStatus.ready,
      quantity: qty,
      paymentMethod: method,
    );
  }

  @override
  Future<List<OrderRecord>> activeOrders() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _sb
        .from('orders')
        .select('*, surprise_bags(*, merchants(*))')
        .eq('consumer_id', uid)
        .eq('status', 'paid')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => orderRecordFromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<OrderRecord>> orderHistory() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _sb
        .from('orders')
        .select('*, surprise_bags(*, merchants(*))')
        .eq('consumer_id', uid)
        .inFilter('status', ['redeemed', 'expired', 'cancelled'])
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => orderRecordFromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> submitReview(
      OrderRecord order, int rating, List<String> tags, String comment) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('reviews').insert({
      'consumer_id': uid,
      'merchant_id': order.bag.merchant.id,
      'rating': rating,
      'tags': tags,
      'comment': comment,
    });
  }

  // ── Notifikasi ──
  @override
  Future<List<AppNotification>> notifications() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _sb
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => notificationFromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('notifications').update({'read': true}).eq('user_id', uid);
  }

  // ── Toko ──
  @override
  Future<StoreProfile?> myStore() async {
    final uid = _uid;
    if (uid == null) return null;
    final row =
        await _sb.from('merchants').select().eq('user_id', uid).maybeSingle();
    return row == null ? null : storeFromMap(row);
  }

  @override
  Future<void> upsertStore({
    required String name,
    required String category,
    required String address,
    required String open,
    required String close,
    String description = '',
    String? logoUrl,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final data = {
      'user_id': uid,
      'store_name': name,
      'category': category,
      'address': address,
      'open_time': open,
      'close_time': close,
      'description': description,
      'logo_url': ?logoUrl,
      'status': 'active',
    };
    await _sb.from('merchants').upsert(data, onConflict: 'user_id');
    _storeIdCache = null;
  }

  // ── Bag merchant ──
  @override
  Future<List<MerchantBag>> myBags() async {
    final sid = await _storeId();
    if (sid == null) return [];
    final rows = await _sb
        .from('surprise_bags')
        .select()
        .eq('merchant_id', sid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => merchantBagFromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> addBag({
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    String? imageUrl,
  }) async {
    final sid = await _storeId();
    if (sid == null) return;
    await _sb.from('surprise_bags').insert({
      'merchant_id': sid,
      'title': title,
      'description': '',
      'original_price': salePrice * 3,
      'sale_price': salePrice,
      'quantity_total': total,
      'quantity_left': total,
      'pickup_window': pickupWindow,
      'image_url': imageUrl,
      'status': 'active',
    });
  }

  @override
  Future<void> updateBag(
    MerchantBag bag, {
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    String? imageUrl,
  }) async {
    await _sb.from('surprise_bags').update({
      'title': title,
      'sale_price': salePrice,
      'pickup_window': pickupWindow,
      'quantity_total': total,
      'image_url': ?imageUrl,
    }).eq('id', bag.id);
  }

  @override
  Future<void> setBagActive(MerchantBag bag, bool active) async {
    await _sb
        .from('surprise_bags')
        .update({'status': active ? 'active' : 'inactive'}).eq('id', bag.id);
  }

  @override
  Future<void> duplicateBag(MerchantBag bag) async {
    final sid = await _storeId();
    if (sid == null) return;
    await _sb.from('surprise_bags').insert({
      'merchant_id': sid,
      'title': bag.title,
      'description': '',
      'original_price': bag.salePrice * 3,
      'sale_price': bag.salePrice,
      'quantity_total': bag.total,
      'quantity_left': bag.total,
      'pickup_window': bag.pickupWindow,
      'image_url': bag.image.startsWith('http') ? bag.image : null,
      'status': 'active',
    });
  }

  // ── Order masuk + statistik ──
  @override
  Future<List<IncomingOrder>> incomingOrders() async {
    final sid = await _storeId();
    if (sid == null) return [];
    final rows = await _sb
        .from('orders')
        .select()
        .eq('merchant_id', sid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => incomingOrderFromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<IncomingOrder?> redeemOrder(String code) async {
    final res = await _sb.rpc('redeem_order', params: {'p_code': code});
    if (res == null) return null;
    final row = (res is List ? (res.isEmpty ? null : res.first) : res)
        as Map<String, dynamic>?;
    if (row == null) return null;
    final name = (row['customer_name'] ?? 'Pelanggan').toString();
    return IncomingOrder(
      customer: name,
      initial: initials2(name),
      time: timeLabel(row['created_at']),
      bags: (row['quantity'] as num?)?.toInt() ?? 1,
      code: code,
      redeemed: true,
    );
  }

  @override
  Future<MerchantStats> merchantStats() async {
    final sid = await _storeId();
    if (sid == null) return const MerchantStats();
    final bags = await _sb
        .from('surprise_bags')
        .select('id')
        .eq('merchant_id', sid)
        .eq('status', 'active');
    final redeemed = await _sb
        .from('orders')
        .select('quantity, total_amount')
        .eq('merchant_id', sid)
        .eq('status', 'redeemed');
    var sold = 0, income = 0;
    for (final o in (redeemed as List)) {
      sold += (o['quantity'] as num?)?.toInt() ?? 0;
      income += ((o['total_amount'] as num?)?.toInt() ?? 0);
    }
    return MerchantStats(
      bagsSoldToday: sold,
      incomeToday: income,
      activeBagCount: (bags as List).length,
    );
  }

  // ── Saldo ──
  @override
  Future<int> balance() async {
    final sid = await _storeId();
    if (sid == null) return 0;
    final row = await _sb
        .from('merchant_balance')
        .select('available')
        .eq('merchant_id', sid)
        .maybeSingle();
    return (row?['available'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<TxRecord>> transactions() async {
    final sid = await _storeId();
    if (sid == null) return [];
    final rows = await _sb
        .from('transactions')
        .select()
        .eq('merchant_id', sid)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => txFromMap(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<void> withdraw(int amount, String bank) async {
    final sid = await _storeId();
    if (sid == null) return;
    await _sb.from('transactions').insert({
      'merchant_id': sid,
      'title': 'Penarikan ke ${bank.split(' · ').first}',
      'subtitle': 'Diproses',
      'amount': amount,
      'kind': 'withdrawal',
    });
  }

  // ── Storage ──
  @override
  Future<String?> uploadImage(BackendBucket bucket) async {
    final uid = _uid;
    if (uid == null) return null;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final bucketName = switch (bucket) {
      BackendBucket.bag => 'bag-images',
      BackendBucket.logo => 'store-logos',
      BackendBucket.avatar => 'avatars',
    };
    final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _sb.storage.from(bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
        );
    return _sb.storage.from(bucketName).getPublicUrl(path);
  }
}
