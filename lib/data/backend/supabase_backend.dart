import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';
import '../business_config.dart';
import '../mappers.dart';
import '../models.dart';
import 'backend.dart';

/// Backend Supabase: Postgres (tabel + RPC), Storage, dengan RLS.
class SupabaseBackend implements Backend {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  String _requireUid() =>
      _uid ??
      (throw const BackendException(
        'not_authenticated',
        'Sesi berakhir. Silakan masuk kembali.',
      ));

  Future<String> _requireStoreId() async =>
      await _storeId() ??
      (throw const BackendException(
        'merchant_not_found',
        'Profil toko belum tersedia. Lengkapi toko terlebih dahulu.',
      ));

  @override
  bool get isRemote => true;

  @override
  Future<BusinessConfig> businessConfig() async {
    try {
      final row = _rpcMap(await _sb.rpc('get_public_app_config'));
      return BusinessConfig.fromMap(row);
    } catch (_) {
      return const BusinessConfig();
    }
  }

  String? _storeIdCache;
  String? _cacheUid;

  @override
  void clearSessionCache() {
    _storeIdCache = null;
    _cacheUid = null;
  }

  Future<String?> _storeId() async {
    final uid = _uid;
    if (uid == null) return null;
    if (_cacheUid == uid && _storeIdCache != null) return _storeIdCache;
    if (_cacheUid != uid) clearSessionCache();
    final response = await _sb.rpc('get_my_merchant');
    final row = response == null ? null : _rpcMap(response);
    _cacheUid = uid;
    return _storeIdCache = row?['id']?.toString();
  }

  // ── Profil ──
  @override
  Future<Profile?> currentProfile() async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;
    final row = await _sb
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (row != null) return profileFromMap(row);
    // fallback dari metadata auth bila baris profil belum sempat dibuat trigger
    return Profile(
      id: user.id,
      name:
          (user.userMetadata?['full_name'] ??
                  user.userMetadata?['name'] ??
                  'Pengguna')
              .toString(),
      email: user.email ?? '',
      avatarUrl: user.userMetadata?['avatar_url']?.toString(),
    );
  }

  @override
  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
  }) async {
    final uid = _requireUid();
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (email != null && email.trim() != _sb.auth.currentUser?.email) {
      await _guard(
        () => _sb.auth.updateUser(
          UserAttributes(email: email.trim()),
          emailRedirectTo: Env.authRedirect,
        ),
      );
    }
    if (phone != null) data['phone'] = phone;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (data.isEmpty) return;
    await _sb.from('profiles').update(data).eq('id', uid);
  }

  @override
  Future<void> setLastMode(String mode) async {
    final uid = _requireUid();
    await _sb.from('profiles').update({'last_mode': mode}).eq('id', uid);
  }

  // ── Browse ──
  @override
  Future<List<Bag>> nearbyBags({
    double? latitude,
    double? longitude,
    BagFilter filter = const BagFilter(),
  }) async {
    final now = DateTime.now();
    final availableDate = _jakartaDateText();
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('available_bags')
          .select()
          .eq('status', 'active')
          .gt('quantity_left', 0)
          .or('available_on.is.null,available_on.lte.$availableDate')
          .or(
            'pickup_end_at.is.null,pickup_end_at.gt.${now.toUtc().toIso8601String()}',
          )
          .order('created_at', ascending: false)
          .range(from, to),
    );
    final bags = rows
        .map(bagFromMap)
        .map((bag) {
          final lat = bag.merchant.latitude;
          final lng = bag.merchant.longitude;
          if (latitude == null ||
              longitude == null ||
              lat == null ||
              lng == null) {
            return bag;
          }
          final km = _distanceKm(latitude, longitude, lat, lng);
          return bag.copyWith(
            merchant: bag.merchant.copyWith(
              distance: '${km.toStringAsFixed(1)} km',
            ),
          );
        })
        .where((bag) => bagMatchesFilter(bag, filter))
        .toList(growable: false);
    if (latitude != null && longitude != null) {
      bags.sort((a, b) {
        final ad =
            double.tryParse(a.merchant.distance.split(' ').first) ??
            double.infinity;
        final bd =
            double.tryParse(b.merchant.distance.split(' ').first) ??
            double.infinity;
        return ad.compareTo(bd);
      });
    }
    return bags;
  }

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    double radians(double value) => value * math.pi / 180;
    final dLat = radians(lat2 - lat1);
    final dLng = radians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  Future<List<Bag>> searchBags(
    String query, {
    double? latitude,
    double? longitude,
    BagFilter filter = const BagFilter(),
  }) async {
    final all = await nearbyBags(
      latitude: latitude,
      longitude: longitude,
      filter: filter,
    );
    final q = query.toLowerCase();
    return all
        .where(
          (b) =>
              b.title.toLowerCase().contains(q) ||
              b.merchant.name.toLowerCase().contains(q) ||
              b.merchant.category.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Future<List<Bag>> bagsByMerchant(String merchantId) async {
    final now = DateTime.now();
    final availableDate = _jakartaDateText();
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('available_bags')
          .select()
          .eq('merchant_id', merchantId)
          .eq('status', 'active')
          .gt('quantity_left', 0)
          .or('available_on.is.null,available_on.lte.$availableDate')
          .or(
            'pickup_end_at.is.null,pickup_end_at.gt.${now.toUtc().toIso8601String()}',
          )
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(bagFromMap).toList();
  }

  // ── Favorit ──
  @override
  Future<Set<String>> favoriteMerchantIds() async {
    final uid = _uid;
    if (uid == null) return {};
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('favorites')
          .select('merchant_id')
          .eq('consumer_id', uid)
          .range(from, to),
    );
    return rows.map((e) => e['merchant_id'].toString()).toSet();
  }

  @override
  Future<bool> toggleFavorite(String merchantId) async {
    final uid = _requireUid();
    final existing = await _sb
        .from('favorites')
        .select()
        .eq('consumer_id', uid)
        .eq('merchant_id', merchantId)
        .maybeSingle();
    if (existing == null) {
      await _sb.from('favorites').insert({
        'consumer_id': uid,
        'merchant_id': merchantId,
      });
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
    final merchants = await _sb
        .from('public_merchants')
        .select()
        .inFilter('id', ids.toList());
    final now = DateTime.now();
    final availableDate = _jakartaDateText();
    final counts = await _sb
        .from('surprise_bags')
        .select('merchant_id')
        .eq('status', 'active')
        .gt('quantity_left', 0)
        .or('available_on.is.null,available_on.lte.$availableDate')
        .or(
          'pickup_end_at.is.null,pickup_end_at.gt.${now.toUtc().toIso8601String()}',
        )
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
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    if (qty <= 0) {
      throw const BackendException('invalid_quantity', 'Jumlah bag minimal 1.');
    }
    return _guard(() async {
      final res = await _sb.rpc(
        'purchase_bag',
        params: {
          'p_bag_id': bag.id,
          'p_qty': qty,
          'p_method': method,
          'p_idempotency_key': idempotencyKey,
        },
      );
      final row = _rpcMap(res);
      final subtotal =
          (row['subtotal'] as num?)?.toInt() ?? bag.salePrice * qty;
      final fee = (row['service_fee'] as num?)?.toInt() ?? 1000;
      final token = (row['pickup_code'] ?? '').toString();
      final reference = (row['order_reference'] ?? '').toString();
      final status = switch ((row['status'] ?? 'pending').toString()) {
        'pending' || 'paid' => OrderStatus.pending,
        'ready' => OrderStatus.ready,
        'redeemed' => OrderStatus.done,
        'cancelled' || 'refunded' => OrderStatus.cancelled,
        'expired' => OrderStatus.expired,
        _ => OrderStatus.pending,
      };
      return OrderRecord(
        id: (row['order_id'] ?? row['id'] ?? '').toString(),
        bag: bag,
        code: reference.isEmpty
            ? 'SB-${bag.id.substring(0, math.min(8, bag.id.length)).toUpperCase()}'
            : reference,
        dateLabel: dateLabel(row['created_at']).isEmpty
            ? 'Hari ini'
            : dateLabel(row['created_at']),
        amount: (row['total_amount'] as num?)?.toInt() ?? subtotal + fee,
        status: status,
        quantity: (row['quantity'] as num?)?.toInt() ?? qty,
        paymentMethod: method,
        createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal(),
        pickupStartsAt: DateTime.tryParse(
          '${row['pickup_start_at']}',
        )?.toLocal(),
        expiresAt: DateTime.tryParse('${row['expires_at']}')?.toLocal(),
        subtotalAmount: subtotal,
        serviceFee: fee,
        merchantNetAmount:
            (row['merchant_net_amount'] as num?)?.toInt() ??
            (subtotal * .9).round(),
        pickupToken: status == OrderStatus.ready && token.isNotEmpty
            ? token
            : null,
      );
    });
  }

  @override
  Future<List<OrderRecord>> activeOrders() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('consumer_orders')
          .select()
          .eq('consumer_id', uid)
          .inFilter('status', ['pending', 'paid', 'preparing', 'ready'])
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(orderRecordFromMap).toList();
  }

  @override
  Future<List<OrderRecord>> orderHistory() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('consumer_orders')
          .select()
          .eq('consumer_id', uid)
          .inFilter('status', ['redeemed', 'expired', 'cancelled'])
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(orderRecordFromMap).toList();
  }

  @override
  Future<OrderRecord> issuePickupToken(OrderRecord order) async {
    if (order.id.isEmpty) {
      throw const BackendException(
        'order_not_found',
        'Pesanan tidak ditemukan.',
      );
    }
    return _guard(() async {
      final row = _rpcMap(
        await _sb.rpc('issue_pickup_token', params: {'p_order_id': order.id}),
      );
      final token = (row['pickup_code'] ?? '').toString();
      if (token.isEmpty) {
        throw const BackendException(
          'pickup_token_unavailable',
          'QR pickup belum dapat dibuat. Coba lagi.',
        );
      }
      return order.copyWith(pickupToken: token);
    });
  }

  @override
  Future<void> submitReview(
    OrderRecord order,
    int rating,
    List<String> tags,
    String comment,
  ) async {
    _requireUid();
    if (order.id.isEmpty) {
      throw const BackendException(
        'order_not_found',
        'Pesanan tidak ditemukan.',
      );
    }
    await _guard(() async {
      await _sb.rpc(
        'submit_review',
        params: {
          'p_order_id': order.id,
          'p_rating': rating,
          'p_tags': tags,
          'p_comment': comment.trim(),
        },
      );
    });
  }

  // ── Notifikasi ──
  @override
  Future<List<AppNotification>> notifications() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(notificationFromMap).toList();
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final uid = _requireUid();
    await _sb.from('notifications').update({'read': true}).eq('user_id', uid);
  }

  @override
  Stream<List<AppNotification>> watchNotifications() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <AppNotification>[]);
    return _sb
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(notificationFromMap).toList(growable: false));
  }

  // ── Toko ──
  @override
  Future<StoreProfile?> myStore() async {
    if (_uid == null) return null;
    final response = await _sb.rpc('get_my_merchant');
    final row = response == null ? null : _rpcMap(response);
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
    double? latitude,
    double? longitude,
  }) async {
    final uid = _requireUid();
    final data = <String, dynamic>{
      'store_name': name,
      'category': category,
      'address': address,
      'open_time': open,
      'close_time': close,
      'description': description,
      'logo_url': ?logoUrl,
      'lat': ?latitude,
      'lng': ?longitude,
    };
    final existingId = await _storeId();
    if (existingId == null) {
      await _sb.from('merchants').insert({...data, 'user_id': uid});
    } else {
      await _sb.from('merchants').update(data).eq('id', existingId);
    }
    clearSessionCache();
  }

  // ── Bag merchant ──
  @override
  Future<List<MerchantBag>> myBags() async {
    final sid = await _storeId();
    if (sid == null) return [];
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('surprise_bags')
          .select()
          .eq('merchant_id', sid)
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(merchantBagFromMap).toList();
  }

  @override
  Future<void> addBag({
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    required String description,
    required List<String> contents,
    required int originalPrice,
    String? imageUrl,
    DateTime? availableOn,
    DateTime? pickupStartsAt,
    DateTime? pickupEndsAt,
  }) async {
    final contentsError = bagContentsValidationError(contents);
    if (contentsError != null) {
      throw BackendException('invalid_bag_contents', contentsError);
    }
    final sid = await _requireStoreId();
    await _sb.from('surprise_bags').insert({
      'merchant_id': sid,
      'title': title,
      'description': description.trim(),
      'contents': normalizeBagContents(contents),
      'original_price': originalPrice,
      'sale_price': salePrice,
      'quantity_total': total,
      'quantity_left': total,
      'pickup_window': pickupWindow,
      'available_on': availableOn == null
          ? null
          : '${availableOn.year.toString().padLeft(4, '0')}-${availableOn.month.toString().padLeft(2, '0')}-${availableOn.day.toString().padLeft(2, '0')}',
      'pickup_start_at': pickupStartsAt?.toUtc().toIso8601String(),
      'pickup_end_at': pickupEndsAt?.toUtc().toIso8601String(),
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
    required String description,
    required List<String> contents,
    required int originalPrice,
    String? imageUrl,
    DateTime? availableOn,
    DateTime? pickupStartsAt,
    DateTime? pickupEndsAt,
  }) async {
    final contentsError = bagContentsValidationError(contents);
    if (contentsError != null) {
      throw BackendException('invalid_bag_contents', contentsError);
    }
    if (total < bag.sold) {
      throw const BackendException(
        'invalid_quantity',
        'Jumlah total tidak boleh lebih kecil dari jumlah yang sudah terjual.',
      );
    }
    final jakartaNow = DateTime.now().toUtc().add(const Duration(hours: 7));
    final effectiveDate =
        availableOn ??
        bag.availableOn ??
        DateTime(jakartaNow.year, jakartaNow.month, jakartaNow.day);
    final effectiveStart = pickupStartsAt ?? bag.pickupStartsAt;
    final effectiveEnd = pickupEndsAt ?? bag.pickupEndsAt;
    await _guard(() async {
      await _sb.rpc(
        'update_surprise_bag',
        params: {
          'p_bag_id': bag.id,
          'p_title': title,
          'p_description': description.trim(),
          'p_original_price': originalPrice,
          'p_sale_price': salePrice,
          'p_quantity_total': total,
          'p_pickup_window': pickupWindow,
          'p_image_url':
              imageUrl ?? (bag.image.startsWith('http') ? bag.image : null),
          'p_available_on': _dateText(effectiveDate),
          'p_pickup_start_at': effectiveStart?.toUtc().toIso8601String(),
          'p_pickup_end_at': effectiveEnd?.toUtc().toIso8601String(),
          'p_contents': normalizeBagContents(contents),
        },
      );
    });
  }

  @override
  Future<void> setBagActive(MerchantBag bag, bool active) async {
    await _guard(() async {
      await _sb.rpc(
        'set_bag_active',
        params: {'p_bag_id': bag.id, 'p_active': active},
      );
    });
  }

  @override
  Future<void> duplicateBag(MerchantBag bag) async {
    final sid = await _requireStoreId();
    final jakartaNow = DateTime.now().toUtc().add(const Duration(hours: 7));
    final tomorrow = DateTime.utc(
      jakartaNow.year,
      jakartaNow.month,
      jakartaNow.day + 1,
    );
    DateTime? moveToTomorrow(DateTime? value) {
      if (value == null) return null;
      final jakartaValue = value.toUtc().add(const Duration(hours: 7));
      return DateTime.utc(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        jakartaValue.hour,
        jakartaValue.minute,
        jakartaValue.second,
      ).subtract(const Duration(hours: 7));
    }

    await _sb.from('surprise_bags').insert({
      'merchant_id': sid,
      'title': bag.title,
      'description': bag.description,
      'contents': bag.contents,
      'original_price': bag.originalPrice,
      'sale_price': bag.salePrice,
      'quantity_total': bag.total,
      'quantity_left': bag.total,
      'pickup_window': bag.pickupWindow,
      'available_on': _dateText(tomorrow),
      'pickup_start_at': moveToTomorrow(bag.pickupStartsAt)?.toIso8601String(),
      'pickup_end_at': moveToTomorrow(bag.pickupEndsAt)?.toIso8601String(),
      'image_url': bag.image.startsWith('http') ? bag.image : null,
      'status': 'active',
    });
  }

  // ── Order masuk + statistik ──
  @override
  Future<List<IncomingOrder>> incomingOrders() async {
    final sid = await _storeId();
    if (sid == null) return [];
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('merchant_orders')
          .select()
          .eq('merchant_id', sid)
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(incomingOrderFromMap).toList();
  }

  @override
  Stream<List<IncomingOrder>> watchIncomingOrders() async* {
    final sid = await _storeId();
    if (sid == null) {
      yield const <IncomingOrder>[];
      return;
    }
    yield await incomingOrders();
    yield* _sb
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('merchant_id', sid)
        .asyncMap((_) => incomingOrders());
  }

  @override
  Future<void> markOrderReady(String orderId) async {
    if (orderId.isEmpty) {
      throw const BackendException(
        'order_not_found',
        'Pesanan tidak ditemukan.',
      );
    }
    await _guard(() async {
      await _sb.rpc('mark_order_ready', params: {'p_order_id': orderId});
    });
  }

  @override
  Future<IncomingOrder> cancelMerchantOrder(String orderId) async {
    if (orderId.isEmpty) {
      throw const BackendException(
        'order_not_found',
        'Pesanan tidak ditemukan.',
      );
    }
    return _guard(() async {
      final row = _rpcMap(
        await _sb.rpc('cancel_merchant_order', params: {'p_order_id': orderId}),
      );
      return incomingOrderFromMap(row);
    });
  }

  @override
  Future<IncomingOrder?> redeemOrder(String code) async {
    if (code.trim().isEmpty) {
      throw const BackendException(
        'invalid_pickup_code',
        'QR pickup tidak valid.',
      );
    }
    return _guard(() async {
      final res = await _sb.rpc(
        'redeem_order',
        params: {'p_code': code.trim()},
      );
      if (res == null || (res is List && res.isEmpty)) return null;
      final row = _rpcMap(res);
      final name = (row['customer_name'] ?? 'Pelanggan').toString();
      return IncomingOrder(
        id: (row['order_id'] ?? '').toString(),
        customer: name,
        initial: initials2(name),
        time: timeLabel(row['created_at']),
        bags: (row['quantity'] as num?)?.toInt() ?? 1,
        code: (row['pickup_code'] ?? '').toString(),
        needsAction: false,
        redeemed: true,
        status: IncomingOrderStatus.redeemed,
        bagTitle: (row['bag_title'] ?? '').toString(),
        redeemedAt: DateTime.tryParse('${row['redeemed_at']}')?.toLocal(),
      );
    });
  }

  @override
  Future<List<MerchantReview>> merchantReviews() async {
    if (_uid == null) return const [];
    return _guard(() async {
      final rows = await _sb.rpc('get_my_merchant_reviews');
      if (rows == null) return const <MerchantReview>[];
      if (rows is! List) {
        throw const BackendException(
          'invalid_response',
          'Respons server tidak valid.',
        );
      }
      return rows
          .map(
            (row) =>
                merchantReviewFromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<MerchantStats> merchantStats() async {
    final sid = await _storeId();
    if (sid == null) return const MerchantStats();
    final bags = await _pagedRows(
      (from, to) => _sb
          .from('surprise_bags')
          .select('id')
          .eq('merchant_id', sid)
          .eq('status', 'active')
          .range(from, to),
    );
    final jakartaNow = DateTime.now().toUtc().add(const Duration(hours: 7));
    final today = DateTime.utc(
      jakartaNow.year,
      jakartaNow.month,
      jakartaNow.day,
    ).subtract(const Duration(hours: 7)).toIso8601String();
    final month = DateTime.utc(
      jakartaNow.year,
      jakartaNow.month,
    ).subtract(const Duration(hours: 7)).toIso8601String();
    final redeemed = await _pagedRows(
      (from, to) => _sb
          .from('orders')
          .select('quantity, merchant_net_amount, total_amount, redeemed_at')
          .eq('merchant_id', sid)
          .eq('status', 'redeemed')
          .gte('redeemed_at', month)
          .order('redeemed_at', ascending: false)
          .range(from, to),
    );
    final pending = await _pagedRows(
      (from, to) => _sb
          .from('orders')
          .select('id')
          .eq('merchant_id', sid)
          .inFilter('status', ['paid', 'preparing', 'ready'])
          .range(from, to),
    );
    var sold = 0, income = 0, monthlyIncome = 0;
    for (final o in redeemed) {
      final value =
          (o['merchant_net_amount'] as num?)?.toInt() ??
          ((((o['total_amount'] as num?)?.toInt() ?? 0) * .9).round());
      monthlyIncome += value;
      final redeemedAt = DateTime.tryParse('${o['redeemed_at']}')?.toUtc();
      if (redeemedAt != null && !redeemedAt.isBefore(DateTime.parse(today))) {
        sold += (o['quantity'] as num?)?.toInt() ?? 0;
        income += value;
      }
    }
    return MerchantStats(
      bagsSoldToday: sold,
      incomeToday: income,
      activeBagCount: bags.length,
      pendingOrderCount: pending.length,
      incomeThisMonth: monthlyIncome,
      foodSavedKg: sold * .5,
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
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('transactions')
          .select()
          .eq('merchant_id', sid)
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(txFromMap).toList();
  }

  @override
  Stream<List<TxRecord>> watchTransactions() async* {
    final sid = await _storeId();
    if (sid == null) {
      yield const <TxRecord>[];
      return;
    }
    yield await transactions();
    yield* _sb
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('merchant_id', sid)
        .asyncMap((_) => transactions());
  }

  @override
  Future<List<BankAccount>> bankAccounts() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('my_bank_accounts')
          .select()
          .order('is_default', ascending: false)
          .order('created_at', ascending: false)
          .range(from, to),
    );
    return rows.map(bankAccountFromMap).toList(growable: false);
  }

  @override
  Future<void> setDefaultBankAccount(String bankAccountId) async {
    if (_uid == null) {
      throw const BackendException(
        'not_authenticated',
        'Sesi berakhir. Silakan masuk kembali.',
      );
    }
    await _guard(
      () => _sb.rpc(
        'set_default_bank_account',
        params: {'p_bank_account_id': bankAccountId},
      ),
    );
  }

  @override
  Future<BankAccount> saveBankAccount({
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required String idempotencyKey,
  }) async {
    return _guard(() async {
      final row = _rpcMap(
        await _sb.rpc(
          'register_bank_account',
          params: {
            'p_bank_code': bankCode,
            'p_account_holder': accountHolder.trim(),
            'p_account_number': accountNumber.replaceAll(RegExp(r'\s'), ''),
            'p_idempotency_key': idempotencyKey,
          },
        ),
      );
      final mapped = <String, dynamic>{...row};
      mapped['bank_name'] ??= bankName;
      return bankAccountFromMap(mapped);
    });
  }

  @override
  Future<List<PayoutRequest>> payoutRequests() async {
    final sid = await _storeId();
    if (sid == null) return [];
    final rows = await _pagedRows(
      (from, to) => _sb
          .from('payout_requests')
          .select(
            '*, bank_accounts(id, bank_code, account_holder, account_number_last4, status, is_default)',
          )
          .eq('merchant_id', sid)
          .order('requested_at', ascending: false)
          .range(from, to),
    );
    return rows.map(payoutRequestFromMap).toList(growable: false);
  }

  @override
  Future<PayoutRequest> requestPayout({
    required int amount,
    required String bankAccountId,
    required String idempotencyKey,
  }) async {
    return _guard(() async {
      final row = _rpcMap(
        await _sb.rpc(
          'request_withdrawal',
          params: {
            'p_bank_account_id': bankAccountId,
            'p_amount': amount,
            'p_idempotency_key': idempotencyKey,
          },
        ),
      );
      final accounts = await bankAccounts();
      BankAccount? account;
      for (final item in accounts) {
        if (item.id == bankAccountId) {
          account = item;
          break;
        }
      }
      return payoutRequestFromMap(row, bankAccount: account);
    });
  }

  @override
  Future<void> deleteAccount() async {
    final uid = _requireUid();
    // Phase one mengunci akun dan memeriksa order/payout aktif sebelum ada
    // objek Storage yang dihapus. Marker ini idempotent sehingga retry aman.
    await _guard(() => _sb.rpc('prepare_delete_my_account'));
    for (final bucket in const ['bag-images', 'store-logos', 'avatars']) {
      await _deleteStorageFolder(bucket, uid);
    }
    await _guard(() async {
      await _sb.rpc('delete_my_account');
    });
    clearSessionCache();
  }

  Future<void> _deleteStorageFolder(String bucket, String uid) async {
    while (true) {
      final objects = await _guard(
        () => _sb.storage
            .from(bucket)
            .list(
              path: uid,
              searchOptions: const SearchOptions(limit: 100, offset: 0),
            ),
      );
      if (objects.isEmpty) return;
      await _guard(
        () => _sb.storage
            .from(bucket)
            .remove(objects.map((object) => '$uid/${object.name}').toList()),
      );
      if (objects.length < 100) return;
    }
  }

  // ── Storage ──
  @override
  Future<String?> uploadImage(BackendBucket bucket) async {
    final uid = _requireUid();
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      throw const BackendException(
        'image_too_large',
        'Ukuran gambar maksimal 2 MB.',
      );
    }
    final bucketName = switch (bucket) {
      BackendBucket.bag => 'bag-images',
      BackendBucket.logo => 'store-logos',
      BackendBucket.avatar => 'avatars',
    };
    final rawExt = picked.name.contains('.')
        ? picked.name.split('.').last.toLowerCase()
        : 'jpg';
    const allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
    final ext = allowedExtensions.contains(rawExt) ? rawExt : 'jpg';
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _guard(
      () => _sb.storage
          .from(bucketName)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: false, contentType: mime),
          ),
    );
    return _sb.storage.from(bucketName).getPublicUrl(path);
  }

  String _dateText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _jakartaDateText() =>
      _dateText(DateTime.now().toUtc().add(const Duration(hours: 7)));

  Future<List<Map<String, dynamic>>> _pagedRows(
    Future<dynamic> Function(int from, int to) fetch, {
    int pageSize = 500,
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += pageSize) {
      final value = await fetch(from, from + pageSize - 1);
      if (value is! List) {
        throw const BackendException(
          'invalid_response',
          'Respons server tidak valid.',
        );
      }
      final page = value
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return rows;
  }

  Map<String, dynamic> _rpcMap(dynamic value) {
    final row = value is List ? (value.isEmpty ? null : value.first) : value;
    if (row is Map<String, dynamic>) return row;
    if (row is Map) return Map<String, dynamic>.from(row);
    throw const BackendException(
      'invalid_response',
      'Respons server tidak valid.',
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on BackendException {
      rethrow;
    } on PostgrestException catch (error) {
      final raw = '${error.message} ${error.details ?? ''}'.toLowerCase();
      if (raw.contains('insufficient stock')) {
        throw const BackendException(
          'insufficient_stock',
          'Stok bag sudah berubah. Silakan cek kembali.',
        );
      }
      if (raw.contains('not authenticated')) {
        throw const BackendException(
          'not_authenticated',
          'Sesi berakhir. Silakan masuk kembali.',
        );
      }
      if (raw.contains('merchant cannot purchase')) {
        throw const BackendException(
          'self_purchase_forbidden',
          'Merchant tidak dapat membeli bag dari tokonya sendiri.',
        );
      }
      if (raw.contains('payouts are disabled')) {
        throw const BackendException(
          'payout_disabled',
          'Penarikan dinonaktifkan selama pembayaran konsumen masih simulasi.',
        );
      }
      if (raw.contains('idempotency')) {
        throw const BackendException(
          'idempotency_conflict',
          'Permintaan yang sama sudah diproses dengan data berbeda.',
        );
      }
      if (raw.contains('pickup token has expired')) {
        throw const BackendException(
          'pickup_token_expired',
          'QR sudah diperbarui. Minta pembeli menampilkan QR terbaru.',
        );
      }
      if (raw.contains('expired')) {
        throw const BackendException(
          'expired',
          'Masa berlaku pesanan sudah berakhir.',
        );
      }
      if (raw.contains('already redeemed')) {
        throw const BackendException(
          'already_redeemed',
          'Pesanan sudah pernah diambil.',
        );
      }
      if (raw.contains('cannot be cancelled') ||
          raw.contains('order status changed')) {
        throw const BackendException(
          'invalid_order_status',
          'Status pesanan sudah berubah dan tidak dapat dibatalkan.',
        );
      }
      if (raw.contains('does not belong to your merchant')) {
        throw const BackendException(
          'order_not_found',
          'Pesanan tidak ditemukan.',
        );
      }
      if (raw.contains('not verified')) {
        throw const BackendException(
          'bank_not_verified',
          'Rekening masih menunggu verifikasi manual.',
        );
      }
      if (raw.contains('insufficient balance')) {
        throw const BackendException(
          'insufficient_balance',
          'Saldo tidak mencukupi.',
        );
      }
      if (raw.contains('account cannot be deleted') && raw.contains('payout')) {
        throw const BackendException(
          'payout_in_progress',
          'Akun belum dapat dihapus karena penarikan dana masih diproses.',
        );
      }
      if (raw.contains('account cannot be deleted') && raw.contains('order')) {
        throw const BackendException(
          'active_order_exists',
          'Akun belum dapat dihapus karena masih ada pesanan aktif.',
        );
      }
      throw const BackendException(
        'server_error',
        'Layanan sedang bermasalah. Silakan coba lagi.',
      );
    } on AuthException {
      throw const BackendException(
        'authentication_required',
        'Sesi berakhir. Silakan masuk kembali.',
      );
    } on StorageException {
      throw const BackendException(
        'upload_failed',
        'Gambar gagal diunggah. Periksa koneksi dan coba lagi.',
      );
    }
  }
}
