import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../business_config.dart';
import '../models.dart';
import '../sample_data.dart';
import 'backend.dart';

/// Backend in-memory berbasis [SampleData]. Dipakai hanya untuk demo eksplisit
/// dan test deterministik; credential production yang hilang tidak jatuh ke
/// backend ini. Semua perubahan bertahan selama sesi.
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
  final Map<String, String> _orderSignaturesByIdempotencyKey = {};
  final Map<String, int> _remainingStock = {};
  final Map<String, String> _pickupTokens = {};
  final Map<String, DateTime> _pickupTokenExpiries = {};
  final Set<String> _locallyPublishedBagIds = {};
  final StreamController<void> _notificationChanges =
      StreamController<void>.broadcast();
  final StreamController<void> _incomingChanges =
      StreamController<void>.broadcast();
  final StreamController<void> _transactionChanges =
      StreamController<void>.broadcast();

  /// `async*` yang berhenti pada yield pertama dapat membuat `cancel()`
  /// menunggu event berikutnya di fake-async test. Controller ini meneruskan
  /// cancellation langsung ke broadcast source sehingga logout/reset selalu
  /// selesai dan tidak meninggalkan listener sesi lama.
  Stream<List<T>> _watchSnapshots<T>(
    List<T> Function() snapshot,
    Stream<void> changes,
  ) {
    StreamSubscription<void>? changesSubscription;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>(
      onListen: () {
        controller.add(snapshot());
        changesSubscription = changes.listen(
          (_) => controller.add(snapshot()),
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => changesSubscription?.pause(),
      onResume: () => changesSubscription?.resume(),
      onCancel: () => changesSubscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  void clearSessionCache() {
    _ordersByIdempotencyKey.clear();
    _orderSignaturesByIdempotencyKey.clear();
    _pickupTokens.clear();
    _pickupTokenExpiries.clear();
    for (var i = 0; i < _active.length; i++) {
      if (_active[i].pickupToken != null) {
        _active[i] = _active[i].copyWith(clearPickupToken: true);
      }
    }
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
    final bags = [...SampleData.nearbyBags, ..._locallyPublishedBags()]
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

  List<Bag> _locallyPublishedBags() {
    final merchant = _localMerchant();
    if (merchant == null || _locallyPublishedBagIds.isEmpty) return const [];

    return _bags
        .where(
          (bag) =>
              _locallyPublishedBagIds.contains(bag.id) &&
              bag.active &&
              bag.quantityLeft > 0,
        )
        .map(
          (bag) => Bag(
            id: bag.id,
            merchant: merchant,
            title: bag.title,
            description: bag.description,
            originalPrice: math.max(bag.originalPrice, bag.salePrice),
            salePrice: bag.salePrice,
            quantityLeft: bag.quantityLeft,
            quantityTotal: bag.total,
            pickupWindow: bag.pickupWindow,
            image: bag.image,
            contents: bag.contents,
            availableOn: bag.availableOn,
            pickupStartsAt: bag.pickupStartsAt,
            pickupEndsAt: bag.pickupEndsAt,
          ),
        )
        .toList(growable: false);
  }

  Merchant? _localMerchant() {
    final store = _store;
    if (store == null) return null;
    final storeName = store.name.trim();
    return Merchant(
      id: store.id,
      name: storeName,
      initial: storeName.isEmpty
          ? 'T'
          : storeName.substring(0, 1).toUpperCase(),
      avatarColor: SampleData.rotiNyaman.avatarColor,
      category: store.category,
      rating: 0,
      reviewCount: 0,
      distance: 'Lokasi toko',
      address: store.address,
      hours: '${store.openTime}–${store.closeTime}',
      coverImage: store.logoUrl ?? SampleData.img1,
      bagsSaved: 0,
      latitude: store.latitude,
      longitude: store.longitude,
    );
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
    if (_favorites.remove(merchantId)) return false;

    final merchantExists = SampleData.merchants.any(
      (merchant) => merchant.id == merchantId,
    );
    if (!merchantExists && _store?.id != merchantId) {
      throw const BackendException(
        'merchant_not_found',
        'Toko tidak ditemukan atau sudah tidak aktif.',
      );
    }
    _favorites.add(merchantId);
    return true;
  }

  @override
  Future<List<FavoriteStore>> favoriteStores() async {
    final availableBags = await nearbyBags();
    final merchants = <String, Merchant>{
      for (final merchant in SampleData.merchants) merchant.id: merchant,
      for (final bag in availableBags) bag.merchant.id: bag.merchant,
    };
    final localMerchant = _localMerchant();
    if (localMerchant != null) {
      merchants[localMerchant.id] = localMerchant;
    }
    final quantities = <String, int>{};
    for (final bag in availableBags) {
      quantities[bag.merchant.id] =
          (quantities[bag.merchant.id] ?? 0) + bag.quantityLeft;
    }

    return _favorites
        .map((merchantId) {
          final merchant = merchants[merchantId];
          if (merchant == null) return null;
          final quantity = quantities[merchantId] ?? 0;
          return FavoriteStore(
            merchant: merchant,
            availability: quantity > 0
                ? '$quantity bag tersedia'
                : 'Habis hari ini',
            soldOut: quantity == 0,
          );
        })
        .whereType<FavoriteStore>()
        .toList(growable: false);
  }

  @override
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  }) async {
    final normalizedMethod = method.trim();
    if (qty < 1 || qty > 100) {
      throw const BackendException(
        'invalid_quantity',
        'Jumlah bag harus antara 1 dan 100.',
      );
    }
    if (normalizedMethod.isEmpty || normalizedMethod.length > 64) {
      throw const BackendException(
        'invalid_payment_method',
        'Metode pembayaran tidak valid.',
      );
    }
    if (idempotencyKey.length < 8 || idempotencyKey.length > 128) {
      throw const BackendException(
        'invalid_idempotency_key',
        'Identitas permintaan checkout tidak valid.',
      );
    }

    final signature = '${bag.id}|$qty|$normalizedMethod';
    final existing = _ordersByIdempotencyKey[idempotencyKey];
    if (existing != null) {
      if (_orderSignaturesByIdempotencyKey[idempotencyKey] != signature) {
        throw const BackendException(
          'idempotency_conflict',
          'Permintaan yang sama sudah diproses dengan data berbeda.',
        );
      }
      return existing;
    }
    if (_store?.id == bag.merchant.id) {
      throw const BackendException(
        'self_purchase_forbidden',
        'Merchant tidak dapat membeli bag dari tokonya sendiri.',
      );
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
    final order = OrderRecord(
      id: _id('order-'),
      bag: bag,
      code: code,
      dateLabel: 'Hari ini',
      amount: subtotal + serviceFee,
      status: OrderStatus.pending,
      quantity: qty,
      paymentMethod: normalizedMethod,
      createdAt: now,
      expiresAt: bag.pickupEndsAt ?? now.add(const Duration(hours: 4)),
      subtotalAmount: subtotal,
      serviceFee: serviceFee,
      merchantNetAmount: (subtotal * .9).round(),
    );
    _remainingStock[bag.id] = remaining - qty;
    _active.insert(0, order);
    _ordersByIdempotencyKey[idempotencyKey] = order;
    _orderSignaturesByIdempotencyKey[idempotencyKey] = signature;
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
    _incomingChanges.add(null);
    return order;
  }

  @override
  Future<OrderRecord> refreshPayment(OrderRecord order) async {
    for (final candidate in [..._active, ..._history]) {
      if (candidate.id == order.id) return candidate;
    }
    throw const BackendException('order_not_found', 'Pesanan tidak ditemukan.');
  }

  @override
  Future<List<OrderRecord>> activeOrders() async => [..._active];

  @override
  Future<List<OrderRecord>> orderHistory() async => [..._history];

  @override
  Future<OrderRecord> issuePickupToken(OrderRecord order) async {
    final index = _active.indexWhere((item) => item.id == order.id);
    if (index < 0) {
      throw const BackendException(
        'order_not_found',
        'Pesanan tidak ditemukan.',
      );
    }
    final current = _active[index];
    if (current.status != OrderStatus.ready) {
      throw const BackendException(
        'order_not_redeemable',
        'QR baru tersedia setelah merchant menandai pesanan siap.',
      );
    }
    final now = DateTime.now();
    if (current.expiresAt != null && !current.expiresAt!.isAfter(now)) {
      throw const BackendException(
        'order_expired',
        'Masa pickup pesanan sudah berakhir.',
      );
    }
    final token = _token();
    final refreshed = current.copyWith(pickupToken: token);
    _active[index] = refreshed;
    _removePickupTokensForOrder(order.id);
    _pickupTokens[token] = order.id;
    final tokenDeadline = now.add(const Duration(seconds: 90));
    _pickupTokenExpiries[token] =
        current.expiresAt != null && current.expiresAt!.isBefore(tokenDeadline)
        ? current.expiresAt!
        : tokenDeadline;
    _cacheOrderRecord(refreshed);
    return refreshed;
  }

  void _cacheOrderRecord(OrderRecord record) {
    final safeRecord = record.copyWith(clearPickupToken: true);
    for (final entry in _ordersByIdempotencyKey.entries.toList()) {
      if (entry.value.id == record.id) {
        _ordersByIdempotencyKey[entry.key] = safeRecord;
      }
    }
  }

  void _removePickupTokensForOrder(String orderId) {
    final tokens = _pickupTokens.entries
        .where((entry) => entry.value == orderId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final token in tokens) {
      _pickupTokens.remove(token);
      _pickupTokenExpiries.remove(token);
    }
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
  Stream<List<AppNotification>> watchNotifications() =>
      _watchSnapshots(() => [..._notifs], _notificationChanges.stream);

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
    final id = _id('mb');
    _bags.insert(
      0,
      MerchantBag(
        id: id,
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
    _locallyPublishedBagIds.add(id);
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
    final id = _id('mb');
    _bags.insert(
      0,
      bag.copyWith(
        id: id,
        sold: 0,
        quantityLeft: bag.total,
        active: true,
        clearStatusNote: true,
        availableOn: tomorrow,
        pickupStartsAt: moveToTomorrow(bag.pickupStartsAt),
        pickupEndsAt: moveToTomorrow(bag.pickupEndsAt),
      ),
    );
    _locallyPublishedBagIds.add(id);
  }

  @override
  Future<List<IncomingOrder>> incomingOrders() async => [..._incoming];

  @override
  Stream<List<IncomingOrder>> watchIncomingOrders() =>
      _watchSnapshots(() => [..._incoming], _incomingChanges.stream);

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
      final readyOrder = _active[consumerIndex].copyWith(
        status: OrderStatus.ready,
      );
      _active[consumerIndex] = readyOrder;
      _cacheOrderRecord(readyOrder);
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
      _cacheOrderRecord(historyOrder);
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

    _removePickupTokensForOrder(orderId);
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
    final token = code.trim();
    final orderId = _pickupTokens[token];
    if (orderId == null) return null;
    final tokenExpiry = _pickupTokenExpiries[token];
    if (tokenExpiry == null || !tokenExpiry.isAfter(DateTime.now())) {
      _pickupTokens.remove(token);
      _pickupTokenExpiries.remove(token);
      throw const BackendException(
        'pickup_token_expired',
        'QR sudah diperbarui. Minta pembeli menampilkan QR terbaru.',
      );
    }
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
    if (source.status != IncomingOrderStatus.ready) {
      throw const BackendException(
        'invalid_order_status',
        'Pesanan belum siap atau sudah tidak dapat diambil.',
      );
    }
    final redeemed = source.copyWith(
      redeemed: true,
      status: IncomingOrderStatus.redeemed,
      needsAction: false,
      redeemedAt: DateTime.now(),
    );
    _incoming[idx] = redeemed;
    _removePickupTokensForOrder(orderId);
    final consumerIndex = _active.indexWhere((order) => order.id == orderId);
    if (consumerIndex >= 0) {
      final consumerOrder = _active
          .removeAt(consumerIndex)
          .copyWith(
            status: OrderStatus.done,
            canRate: true,
            clearPickupToken: true,
          );
      _history.insert(0, consumerOrder);
      _cacheOrderRecord(consumerOrder);
    }
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
  Stream<List<TxRecord>> watchTransactions() =>
      _watchSnapshots(() => [..._tx], _transactionChanges.stream);

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
        'Rekening masih dalam verifikasi.',
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
        subtitle: 'Hari ini · menunggu diproses',
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
    _locallyPublishedBagIds.clear();
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

  @override
  Future<String?> uploadImageBytes(
    BackendBucket bucket,
    Uint8List bytes, {
    required String filename,
  }) => uploadImage(bucket);
}
