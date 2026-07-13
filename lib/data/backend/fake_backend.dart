import 'dart:async';
import 'dart:math' as math;

import '../business_config.dart';
import '../models.dart';
import '../sample_data.dart';
import 'backend.dart';

/// Backend in-memory berbasis [SampleData]. Dipakai saat kredensial Supabase
/// tidak ada (offline/demo) dan untuk test. Semua perubahan bertahan selama sesi.
class FakeBackend implements Backend {
  @override
  bool get isRemote => false;

  @override
  Future<BusinessConfig> businessConfig() async => const BusinessConfig();

  int _seq = 100;
  int _codeSeq = 1000;
  String _id(String p) => '$p${_seq++}';
  String _code() =>
      'SB-${(_codeSeq++).toRadixString(36).toUpperCase().padLeft(5, '0')}';
  String _token() =>
      'savebite-pickup:${_id('token-')}:${DateTime.now().microsecondsSinceEpoch}';

  final Map<String, OrderRecord> _ordersByIdempotencyKey = {};
  final Map<String, int> _remainingStock = {};
  final Map<String, String> _pickupTokens = {};
  final StreamController<void> _notificationChanges =
      StreamController<void>.broadcast();
  final StreamController<void> _incomingChanges =
      StreamController<void>.broadcast();
  final StreamController<void> _transactionChanges =
      StreamController<void>.broadcast();

  @override
  void clearSessionCache() {
    _ordersByIdempotencyKey.clear();
    _pickupTokens.clear();
    _bankByIdempotencyKey.clear();
    _payoutByIdempotencyKey.clear();
  }

  // Profil & toko (mutable)
  Profile _profile = const Profile(
    id: 'me',
    name: 'Ilham Hidayat',
    email: 'ilham@gmail.com',
    phone: '0812-3456-7890',
  );
  // Mulai null → merchant baru lewat Setup Toko dulu (sesuai PRD F-G4).
  StoreProfile? _store;

  final Set<String> _favorites = {'m1', 'm2', 'm8'};
  late final List<MerchantBag> _bags = [
    ...SampleData.merchantActiveBags,
    ...SampleData.merchantInactiveBags,
  ];
  late final List<OrderRecord> _active = [...SampleData.activeOrders];
  late final List<OrderRecord> _history = [...SampleData.orderHistory];
  late final List<IncomingOrder> _incoming = [...SampleData.incomingOrders];
  final List<MerchantReview> _merchantReviews = [
    MerchantReview(
      id: 'review-merchant-1',
      orderId: 'order-review-1',
      orderReference: 'SB-8F4K2P',
      customerName: 'Nadia Putri',
      rating: 5,
      tags: const ['Masih fresh', 'Porsi banyak'],
      comment: 'Rotinya masih lembut dan isi bag-nya beragam. Terima kasih!',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    MerchantReview(
      id: 'review-merchant-2',
      orderId: 'order-review-2',
      orderReference: 'SB-1Q7M9C',
      customerName: 'Dimas Arya',
      rating: 4,
      tags: const ['Sesuai deskripsi', 'Pelayanan ramah'],
      comment: 'Pengambilan cepat dan makanannya masih enak.',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];
  late final List<AppNotification> _notifs = [...SampleData.notifications];
  late final List<TxRecord> _tx = [...SampleData.transactions];
  int _balance = SampleData.merchantBalance;
  int _soldToday = 8;
  int _incomeToday = 120000;

  final List<BankAccount> _bankAccounts = [
    const BankAccount(
      id: 'bank-1',
      bankCode: 'BCA',
      bankName: 'BCA',
      accountNumberMasked: '•••• 6789',
      accountHolder: 'ILHAM HIDAYAT',
      verified: true,
      isDefault: true,
    ),
  ];
  final List<PayoutRequest> _payouts = [];
  final Map<String, BankAccount> _bankByIdempotencyKey = {};
  final Map<String, PayoutRequest> _payoutByIdempotencyKey = {};

  String _lastMode = 'consumer';

  @override
  Future<Profile?> currentProfile() async => Profile(
    id: _profile.id,
    name: _profile.name,
    email: _profile.email,
    phone: _profile.phone,
    avatarUrl: _profile.avatarUrl,
    lastMode: _lastMode,
  );

  @override
  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
  }) async {
    _profile = Profile(
      id: _profile.id,
      name: (name?.trim().isNotEmpty ?? false) ? name!.trim() : _profile.name,
      email: (email?.trim().isNotEmpty ?? false)
          ? email!.trim()
          : _profile.email,
      phone: (phone?.trim().isNotEmpty ?? false)
          ? phone!.trim()
          : _profile.phone,
      avatarUrl: avatarUrl ?? _profile.avatarUrl,
      lastMode: _profile.lastMode,
    );
  }

  @override
  Future<void> setLastMode(String mode) async {
    _lastMode = mode;
  }

  @override
  Future<List<Bag>> nearbyBags({
    double? latitude,
    double? longitude,
    BagFilter filter = const BagFilter(),
  }) async {
    final bags = SampleData.nearbyBags
        .map((bag) {
          final remaining = _remainingStock[bag.id] ?? bag.quantityLeft;
          var updated = bag.copyWith(
            quantityLeft: remaining,
            soldOut: remaining <= 0,
          );
          final merchantLat = bag.merchant.latitude;
          final merchantLng = bag.merchant.longitude;
          if (latitude != null &&
              longitude != null &&
              merchantLat != null &&
              merchantLng != null) {
            final distance = _distanceKm(
              latitude,
              longitude,
              merchantLat,
              merchantLng,
            );
            updated = updated.copyWith(
              merchant: updated.merchant.copyWith(
                distance: '${distance.toStringAsFixed(1)} km',
              ),
            );
          }
          return updated;
        })
        .where((bag) {
          final now = DateTime.now();
          final availableOn = bag.availableOn;
          if (availableOn != null &&
              DateTime(
                availableOn.year,
                availableOn.month,
                availableOn.day,
              ).isAfter(DateTime(now.year, now.month, now.day))) {
            return false;
          }
          if (bag.pickupEndsAt != null && !bag.pickupEndsAt!.isAfter(now)) {
            return false;
          }
          return bagMatchesFilter(bag, filter);
        })
        .toList(growable: false);
    if (latitude != null && longitude != null) {
      bags.sort((a, b) {
        final aDistance =
            double.tryParse(a.merchant.distance.split(' ').first) ??
            double.infinity;
        final bDistance =
            double.tryParse(b.merchant.distance.split(' ').first) ??
            double.infinity;
        return aDistance.compareTo(bDistance);
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
    final q = query.toLowerCase();
    final available = await nearbyBags(
      latitude: latitude,
      longitude: longitude,
      filter: filter,
    );
    return available
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
    final available = await nearbyBags();
    return available
        .where((bag) => bag.merchant.id == merchantId)
        .toList(growable: false);
  }

  @override
  Future<Set<String>> favoriteMerchantIds() async => {..._favorites};

  @override
  Future<bool> toggleFavorite(String merchantId) async {
    final added = _favorites.add(merchantId);
    if (!added) _favorites.remove(merchantId);
    return added;
  }

  @override
  Future<List<FavoriteStore>> favoriteStores() async => SampleData.favorites
      .where((f) => _favorites.contains(f.merchant.id))
      .toList();

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    final existing = _ordersByIdempotencyKey[idempotencyKey];
    if (existing != null) return existing;
    if (qty <= 0) {
      throw const BackendException('invalid_quantity', 'Jumlah bag minimal 1.');
    }
    final remaining = _remainingStock[bag.id] ?? bag.quantityLeft;
    if (remaining < qty || bag.soldOut) {
      throw const BackendException(
        'insufficient_stock',
        'Stok bag sudah berubah. Silakan pilih jumlah yang tersedia.',
      );
    }
    final subtotal = bag.salePrice * qty;
    const serviceFee = 1000;
    final now = DateTime.now();
    final code = _code();
    final token = _token();
    final order = OrderRecord(
      id: _id('order-'),
      bag: bag,
      code: code,
      dateLabel: 'Hari ini',
      amount: subtotal + serviceFee,
      status: OrderStatus.pending,
      quantity: qty,
      paymentMethod: method,
      createdAt: now,
      expiresAt: bag.pickupEndsAt ?? now.add(const Duration(hours: 4)),
      subtotalAmount: subtotal,
      serviceFee: serviceFee,
      merchantNetAmount: (subtotal * .9).round(),
      pickupToken: token,
    );
    _remainingStock[bag.id] = remaining - qty;
    _active.insert(0, order);
    _ordersByIdempotencyKey[idempotencyKey] = order;
    _incoming.insert(
      0,
      IncomingOrder(
        id: order.id,
        customer: _profile.name,
        initial: _profile.name.substring(0, 1).toUpperCase(),
        time: 'Baru saja',
        bags: qty,
        code: code,
        status: IncomingOrderStatus.paid,
        bagTitle: bag.title,
        bagImage: bag.image,
        pickupWindow: bag.pickupWindow,
        unitPrice: bag.salePrice,
        subtotalAmount: subtotal,
        serviceFee: serviceFee,
        merchantNetAmount: (subtotal * .9).round(),
        createdAt: now,
        pickupStartsAt: bag.pickupStartsAt,
        expiresAt: order.expiresAt,
      ),
    );
    _pickupTokens[token] = order.id;
    _incomingChanges.add(null);
    return order;
  }

  @override
  Future<List<OrderRecord>> activeOrders() async => [..._active];

  @override
  Future<List<OrderRecord>> orderHistory() async => [..._history];

  @override
  Future<OrderRecord> issuePickupToken(OrderRecord order) async {
    if (order.status != OrderStatus.ready) {
      throw const BackendException(
        'order_not_redeemable',
        'Pesanan ini tidak lagi dapat diambil.',
      );
    }
    final token = _token();
    final refreshed = order.copyWith(pickupToken: token);
    final index = _active.indexWhere((item) => item.id == order.id);
    if (index >= 0) _active[index] = refreshed;
    _pickupTokens.removeWhere((_, orderId) => orderId == order.id);
    _pickupTokens[token] = order.id;
    return refreshed;
  }

  @override
  Future<void> submitReview(
    OrderRecord order,
    int rating,
    List<String> tags,
    String comment,
  ) async {
    if (rating < 1 || rating > 5) {
      throw const BackendException(
        'invalid_rating',
        'Pilih rating 1 sampai 5.',
      );
    }
    final index = _history.indexWhere(
      (item) =>
          (order.id.isNotEmpty && item.id == order.id) ||
          item.code == order.code,
    );
    if (index < 0 || _history[index].status != OrderStatus.done) {
      throw const BackendException(
        'order_not_redeemed',
        'Ulasan hanya dapat dikirim setelah pesanan diambil.',
      );
    }
    if (_history[index].reviewed) {
      throw const BackendException('already_reviewed', 'Pesanan sudah diulas.');
    }
    _history[index] = _history[index].copyWith(reviewed: true, canRate: false);
    _merchantReviews.insert(
      0,
      MerchantReview(
        id: _id('review-'),
        orderId: order.id,
        orderReference: order.code,
        customerName: _profile.name,
        rating: rating,
        tags: List.unmodifiable(tags),
        comment: comment.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _notifs.insert(
      0,
      AppNotification(
        id: _id('notification-'),
        title: 'Ulasan baru',
        body: '$rating bintang untuk ${order.code}.',
        time: 'Baru saja',
        type: NotifType.rating,
        group: 'Hari ini',
        unread: true,
        route: 'merchant_reviews',
        createdAt: DateTime.now(),
      ),
    );
    _notificationChanges.add(null);
  }

  @override
  Future<List<AppNotification>> notifications() async => [..._notifs];

  @override
  Future<void> markAllNotificationsRead() async {
    for (var i = 0; i < _notifs.length; i++) {
      if (_notifs[i].unread) _notifs[i] = _notifs[i].copyWith(unread: false);
    }
    _notificationChanges.add(null);
  }

  @override
  Stream<List<AppNotification>> watchNotifications() async* {
    yield await notifications();
    await for (final _ in _notificationChanges.stream) {
      yield await notifications();
    }
  }

  @override
  Future<StoreProfile?> myStore() async => _store;

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
    _store = StoreProfile(
      id: _store?.id ?? 'store-me',
      name: name,
      category: category,
      address: address,
      openTime: open,
      closeTime: close,
      description: description,
      logoUrl: logoUrl ?? _store?.logoUrl,
      latitude: latitude ?? _store?.latitude,
      longitude: longitude ?? _store?.longitude,
    );
  }

  @override
  Future<List<MerchantBag>> myBags() async => [..._bags];

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
    if (title.trim().isEmpty ||
        salePrice <= 0 ||
        originalPrice < salePrice ||
        total <= 0) {
      throw const BackendException(
        'invalid_bag',
        'Periksa nama, harga, dan jumlah bag.',
      );
    }
    _bags.insert(
      0,
      MerchantBag(
        id: _id('mb'),
        title: title,
        salePrice: salePrice,
        pickupWindow: pickupWindow,
        sold: 0,
        total: total,
        image: imageUrl ?? SampleData.img1,
        active: true,
        description: description.trim(),
        contents: normalizeBagContents(contents),
        originalPrice: originalPrice,
        quantityLeft: total,
        availableOn: availableOn,
        pickupStartsAt: pickupStartsAt,
        pickupEndsAt: pickupEndsAt,
      ),
    );
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
    if (title.trim().isEmpty ||
        salePrice <= 0 ||
        originalPrice < salePrice ||
        total < bag.sold) {
      throw const BackendException(
        'invalid_bag',
        'Jumlah total tidak boleh di bawah jumlah terjual dan harga asli harus valid.',
      );
    }
    final i = _bags.indexWhere((b) => b.id == bag.id);
    if (i != -1) {
      _bags[i] = bag.copyWith(
        title: title,
        salePrice: salePrice,
        pickupWindow: pickupWindow,
        total: total,
        image: imageUrl,
        description: description.trim(),
        contents: normalizeBagContents(contents),
        originalPrice: originalPrice,
        quantityLeft: total - bag.sold,
        availableOn: availableOn,
        pickupStartsAt: pickupStartsAt,
        pickupEndsAt: pickupEndsAt,
      );
    }
  }

  @override
  Future<void> setBagActive(MerchantBag bag, bool active) async {
    final i = _bags.indexWhere((b) => b.id == bag.id);
    if (i != -1) {
      _bags[i] = bag.copyWith(active: active, clearStatusNote: active);
    }
  }

  @override
  Future<void> duplicateBag(MerchantBag bag) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    DateTime? moveToTomorrow(DateTime? value) => value == null
        ? null
        : DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            value.hour,
            value.minute,
            value.second,
          );
    _bags.insert(
      0,
      bag.copyWith(
        id: _id('mb'),
        sold: 0,
        quantityLeft: bag.total,
        active: true,
        clearStatusNote: true,
        availableOn: tomorrow,
        pickupStartsAt: moveToTomorrow(bag.pickupStartsAt),
        pickupEndsAt: moveToTomorrow(bag.pickupEndsAt),
      ),
    );
  }

  @override
  Future<List<IncomingOrder>> incomingOrders() async => [..._incoming];

  @override
  Stream<List<IncomingOrder>> watchIncomingOrders() async* {
    yield await incomingOrders();
    await for (final _ in _incomingChanges.stream) {
      yield await incomingOrders();
    }
  }

  @override
  Future<void> markOrderReady(String orderId) async {
    final index = _incoming.indexWhere((order) => order.id == orderId);
    if (index < 0) {
      throw const BackendException(
        'order_not_found',
        'Pesanan tidak ditemukan.',
      );
    }
    final order = _incoming[index];
    if (order.status != IncomingOrderStatus.paid &&
        order.status != IncomingOrderStatus.preparing) {
      throw const BackendException(
        'invalid_order_status',
        'Pesanan ini tidak dapat ditandai siap.',
      );
    }
    _incoming[index] = order.copyWith(
      status: IncomingOrderStatus.ready,
      needsAction: false,
    );
    final consumerIndex = _active.indexWhere((item) => item.id == orderId);
    if (consumerIndex >= 0) {
      _active[consumerIndex] = _active[consumerIndex].copyWith(
        status: OrderStatus.ready,
      );
    }
    _notifs.insert(
      0,
      AppNotification(
        id: _id('notification-'),
        title: 'Pesanan siap diambil',
        body: '${order.bagTitle} sudah siap.',
        time: 'Baru saja',
        type: NotifType.ready,
        group: 'Hari ini',
        unread: true,
        route: 'orders',
        createdAt: DateTime.now(),
      ),
    );
    _incomingChanges.add(null);
    _notificationChanges.add(null);
  }

  @override
  Future<IncomingOrder> cancelMerchantOrder(String orderId) async {
    final index = _incoming.indexWhere((order) => order.id == orderId);
    if (index < 0) {
      throw const BackendException(
        'order_not_found',
        'Pesanan tidak ditemukan.',
      );
    }
    final source = _incoming[index];
    if (source.status == IncomingOrderStatus.cancelled) return source;
    if (source.status != IncomingOrderStatus.paid &&
        source.status != IncomingOrderStatus.preparing &&
        source.status != IncomingOrderStatus.ready) {
      throw const BackendException(
        'invalid_order_status',
        'Pesanan ini tidak dapat dibatalkan.',
      );
    }

    final cancelled = source.copyWith(
      status: IncomingOrderStatus.cancelled,
      needsAction: false,
    );
    _incoming[index] = cancelled;

    final consumerIndex = _active.indexWhere((order) => order.id == orderId);
    if (consumerIndex >= 0) {
      final consumerOrder = _active.removeAt(consumerIndex);
      final bag = consumerOrder.bag;
      final current = _remainingStock[bag.id] ?? bag.quantityLeft;
      _remainingStock[bag.id] = math.min(
        bag.quantityTotal,
        current + consumerOrder.quantity,
      );
      final historyOrder = consumerOrder.copyWith(
        status: OrderStatus.cancelled,
        canRate: false,
        clearPickupToken: true,
      );
      _history.insert(0, historyOrder);
      for (final entry in _ordersByIdempotencyKey.entries.toList()) {
        if (entry.value.id == orderId) {
          _ordersByIdempotencyKey[entry.key] = historyOrder;
        }
      }
    }

    final bagIndex = _bags.indexWhere((bag) => bag.title == source.bagTitle);
    if (bagIndex >= 0) {
      final bag = _bags[bagIndex];
      final restored = math.min(bag.total, bag.quantityLeft + source.bags);
      _bags[bagIndex] = bag.copyWith(
        sold: bag.total - restored,
        quantityLeft: restored,
        active: bag.active || bag.quantityLeft == 0,
        clearStatusNote: true,
      );
    }

    _pickupTokens.removeWhere((_, mappedOrderId) => mappedOrderId == orderId);
    _notifs.insert(
      0,
      AppNotification(
        id: _id('notification-'),
        title: 'Pesanan dibatalkan',
        body: '${source.bagTitle} telah dibatalkan oleh merchant.',
        time: 'Baru saja',
        type: NotifType.payment,
        group: 'Hari ini',
        unread: true,
        route: 'orders',
        createdAt: DateTime.now(),
      ),
    );
    _incomingChanges.add(null);
    _notificationChanges.add(null);
    return cancelled;
  }

  @override
  Future<IncomingOrder?> redeemOrder(String code) async {
    if (code.trim().isEmpty) {
      throw const BackendException(
        'invalid_pickup_code',
        'QR pickup tidak valid.',
      );
    }
    final orderId = _pickupTokens[code];
    if (orderId == null) return null;
    final idx = _incoming.indexWhere((o) => o.id == orderId && !o.redeemed);
    if (idx == -1) return null;
    final source = _incoming[idx];
    if (source.expiresAt != null &&
        source.expiresAt!.isBefore(DateTime.now())) {
      throw const BackendException(
        'order_expired',
        'Masa pickup pesanan sudah berakhir.',
      );
    }
    if (source.pickupStartsAt != null &&
        source.pickupStartsAt!.isAfter(DateTime.now())) {
      throw const BackendException(
        'pickup_not_started',
        'Waktu pickup pesanan belum dimulai.',
      );
    }
    if (source.status == IncomingOrderStatus.cancelled ||
        source.status == IncomingOrderStatus.expired ||
        (source.status != IncomingOrderStatus.paid &&
            source.status != IncomingOrderStatus.ready)) {
      throw const BackendException(
        'invalid_order_status',
        'Pesanan dibatalkan atau sudah kedaluwarsa.',
      );
    }
    final redeemed = source.copyWith(
      redeemed: true,
      status: IncomingOrderStatus.redeemed,
      needsAction: false,
      redeemedAt: DateTime.now(),
    );
    _incoming[idx] = redeemed;
    _pickupTokens.remove(code);
    _soldToday += redeemed.bags;
    _incomeToday += redeemed.merchantNetAmount;
    _balance += redeemed.merchantNetAmount;
    _tx.insert(
      0,
      TxRecord(
        id: _id('tx-'),
        title: 'Order ${redeemed.code}',
        subtitle: 'Hari ini · selesai',
        amount: redeemed.merchantNetAmount,
        kind: TxKind.income,
        createdAt: DateTime.now(),
      ),
    );
    _incomingChanges.add(null);
    _transactionChanges.add(null);
    return redeemed;
  }

  @override
  Future<List<MerchantReview>> merchantReviews() async => [..._merchantReviews];

  @override
  Future<MerchantStats> merchantStats() async => MerchantStats(
    bagsSoldToday: _soldToday,
    incomeToday: _incomeToday,
    activeBagCount: _bags.where((b) => b.active).length,
    pendingOrderCount: _incoming.where((o) => !o.redeemed).length,
    incomeThisMonth: _incomeToday,
    foodSavedKg: _soldToday * .5,
  );

  @override
  Future<int> balance() async => _balance;

  @override
  Future<List<TxRecord>> transactions() async => [..._tx];

  @override
  Stream<List<TxRecord>> watchTransactions() async* {
    yield await transactions();
    await for (final _ in _transactionChanges.stream) {
      yield await transactions();
    }
  }

  @override
  Future<List<BankAccount>> bankAccounts() async => [..._bankAccounts];

  @override
  Future<void> setDefaultBankAccount(String bankAccountId) async {
    final index = _bankAccounts.indexWhere(
      (account) => account.id == bankAccountId,
    );
    if (index < 0) {
      throw const BackendException(
        'bank_account_not_found',
        'Rekening tidak ditemukan.',
      );
    }
    for (var i = 0; i < _bankAccounts.length; i++) {
      _bankAccounts[i] = _bankAccounts[i].copyWith(isDefault: i == index);
    }
  }

  @override
  Future<BankAccount> saveBankAccount({
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required String idempotencyKey,
  }) async {
    final existing = _bankByIdempotencyKey[idempotencyKey];
    if (existing != null) return existing;
    final digits = accountNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || accountHolder.trim().length < 3) {
      throw const BackendException(
        'invalid_bank_account',
        'Nomor rekening atau nama pemilik belum valid.',
      );
    }
    final account = BankAccount(
      id: _id('bank-'),
      bankCode: bankCode,
      bankName: bankName,
      accountNumberMasked: '•••• ${digits.substring(digits.length - 4)}',
      accountHolder: accountHolder.trim().toUpperCase(),
      isDefault: _bankAccounts.isEmpty,
    );
    _bankAccounts.add(account);
    _bankByIdempotencyKey[idempotencyKey] = account;
    return account;
  }

  @override
  Future<List<PayoutRequest>> payoutRequests() async => [..._payouts];

  @override
  Future<PayoutRequest> requestPayout({
    required int amount,
    required String bankAccountId,
    required String idempotencyKey,
  }) async {
    final existing = _payoutByIdempotencyKey[idempotencyKey];
    if (existing != null) return existing;
    if (amount < 50000) {
      throw const BackendException(
        'minimum_payout',
        'Minimum penarikan adalah Rp50.000.',
      );
    }
    if (amount > _balance) {
      throw const BackendException(
        'insufficient_balance',
        'Saldo tidak mencukupi.',
      );
    }
    final bank = _bankAccounts
        .where((item) => item.id == bankAccountId)
        .firstOrNull;
    if (bank == null) {
      throw const BackendException(
        'bank_not_found',
        'Rekening tidak ditemukan.',
      );
    }
    if (!bank.verified) {
      throw const BackendException(
        'bank_not_verified',
        'Rekening masih menunggu verifikasi manual.',
      );
    }
    const fee = 2500;
    final request = PayoutRequest(
      id: _id('payout-'),
      grossAmount: amount,
      feeAmount: fee,
      netAmount: amount - fee,
      status: PayoutStatus.pending,
      bankAccount: bank,
      createdAt: DateTime.now(),
    );
    _balance -= amount;
    _payouts.insert(0, request);
    _payoutByIdempotencyKey[idempotencyKey] = request;
    _tx.insert(
      0,
      TxRecord(
        id: _id('tx-'),
        title: 'Penarikan ke ${bank.bankName}',
        subtitle: 'Hari ini · menunggu proses manual',
        amount: amount,
        kind: TxKind.withdrawal,
        createdAt: DateTime.now(),
        status: 'pending',
      ),
    );
    _transactionChanges.add(null);
    return request;
  }

  @override
  Future<void> deleteAccount() async {
    clearSessionCache();
    _profile = const Profile(id: 'me', name: 'Pengguna', email: '');
    _store = null;
    _lastMode = 'consumer';
    _favorites.clear();
    _bags.clear();
    _active.clear();
    _history.clear();
    _incoming.clear();
    _merchantReviews.clear();
    _notifs.clear();
    _tx.clear();
    _bankAccounts.clear();
    _payouts.clear();
    _remainingStock.clear();
    _balance = 0;
    _soldToday = 0;
    _incomeToday = 0;
    _notificationChanges.add(null);
    _incomingChanges.add(null);
    _transactionChanges.add(null);
  }

  @override
  Future<String?> uploadImage(BackendBucket bucket) async {
    // Offline: kembalikan foto contoh berbeda agar perubahan "terlihat".
    const samples = [
      SampleData.img6,
      SampleData.img9,
      SampleData.img4,
      SampleData.img10,
    ];
    return samples[_seq++ % samples.length];
  }
}
