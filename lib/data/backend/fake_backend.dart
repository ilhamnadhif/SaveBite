import '../models.dart';
import '../sample_data.dart';
import 'backend.dart';

/// Backend in-memory berbasis [SampleData]. Dipakai saat kredensial Supabase
/// tidak ada (offline/demo) dan untuk test. Semua perubahan bertahan selama sesi.
class FakeBackend implements Backend {
  @override
  bool get isRemote => false;

  int _seq = 100;
  int _codeSeq = 1000;
  String _id(String p) => '$p${_seq++}';
  String _code() =>
      'SB-${(_codeSeq++).toRadixString(36).toUpperCase().padLeft(5, '0')}';

  // Profil & toko (mutable)
  Profile _profile = const Profile(
      id: 'me', name: 'Ilham Hidayat', email: 'ilham@gmail.com', phone: '0812-3456-7890');
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
  late final List<AppNotification> _notifs = [...SampleData.notifications];
  late final List<TxRecord> _tx = [...SampleData.transactions];
  int _balance = SampleData.merchantBalance;
  int _soldToday = 8;
  int _incomeToday = 120000;

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
  Future<void> updateProfile({String? name, String? email, String? phone, String? avatarUrl}) async {
    _profile = Profile(
      id: _profile.id,
      name: (name?.trim().isNotEmpty ?? false) ? name!.trim() : _profile.name,
      email: (email?.trim().isNotEmpty ?? false) ? email!.trim() : _profile.email,
      phone: (phone?.trim().isNotEmpty ?? false) ? phone!.trim() : _profile.phone,
      avatarUrl: avatarUrl ?? _profile.avatarUrl,
      lastMode: _profile.lastMode,
    );
  }

  @override
  Future<void> setLastMode(String mode) async {
    _lastMode = mode;
  }

  @override
  Future<List<Bag>> nearbyBags() async => SampleData.nearbyBags;

  @override
  Future<List<Bag>> searchBags(String query) async {
    final q = query.toLowerCase();
    return SampleData.allBags
        .where((b) =>
            b.title.toLowerCase().contains(q) ||
            b.merchant.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Bag>> bagsByMerchant(String merchantId) async =>
      SampleData.allBags.where((b) => b.merchant.id == merchantId).toList();

  @override
  Future<Set<String>> favoriteMerchantIds() async => {..._favorites};

  @override
  Future<bool> toggleFavorite(String merchantId) async {
    final added = _favorites.add(merchantId);
    if (!added) _favorites.remove(merchantId);
    return added;
  }

  @override
  Future<List<FavoriteStore>> favoriteStores() async =>
      SampleData.favorites.where((f) => _favorites.contains(f.merchant.id)).toList();

  @override
  Future<OrderRecord> placeOrder(Bag bag, int qty, String method) async {
    final order = OrderRecord(
      bag: bag,
      code: _code(),
      dateLabel: 'Hari ini',
      amount: bag.salePrice * qty,
      status: OrderStatus.ready,
      quantity: qty,
      paymentMethod: method,
    );
    _active.insert(0, order);
    return order;
  }

  @override
  Future<List<OrderRecord>> activeOrders() async => [..._active];

  @override
  Future<List<OrderRecord>> orderHistory() async => [..._history];

  @override
  Future<void> submitReview(
      OrderRecord order, int rating, List<String> tags, String comment) async {}

  @override
  Future<List<AppNotification>> notifications() async => [..._notifs];

  @override
  Future<void> markAllNotificationsRead() async {
    for (var i = 0; i < _notifs.length; i++) {
      if (_notifs[i].unread) _notifs[i] = _notifs[i].copyWith(unread: false);
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
    String? imageUrl,
  }) async {
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
    String? imageUrl,
  }) async {
    final i = _bags.indexWhere((b) => b.id == bag.id);
    if (i != -1) {
      _bags[i] = bag.copyWith(
        title: title,
        salePrice: salePrice,
        pickupWindow: pickupWindow,
        total: total,
        image: imageUrl,
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
    _bags.insert(
      0,
      bag.copyWith(id: _id('mb'), sold: 0, active: true, clearStatusNote: true),
    );
  }

  @override
  Future<List<IncomingOrder>> incomingOrders() async => [..._incoming];

  @override
  Future<IncomingOrder?> redeemOrder(String code) async {
    final i = _incoming.indexWhere((o) => o.code == code && !o.redeemed);
    final idx = i != -1 ? i : _incoming.indexWhere((o) => !o.redeemed);
    if (idx == -1) return null;
    final redeemed = _incoming[idx].copyWith(redeemed: true);
    _incoming[idx] = redeemed;
    _soldToday += redeemed.bags;
    _incomeToday += redeemed.bags * 15000;
    return redeemed;
  }

  @override
  Future<MerchantStats> merchantStats() async => MerchantStats(
        bagsSoldToday: _soldToday,
        incomeToday: _incomeToday,
        activeBagCount: _bags.where((b) => b.active).length,
      );

  @override
  Future<int> balance() async => _balance;

  @override
  Future<List<TxRecord>> transactions() async => [..._tx];

  @override
  Future<void> withdraw(int amount, String bank) async {
    _balance -= amount;
    _tx.insert(
      0,
      TxRecord(
        title: 'Penarikan ke ${bank.split(' · ').first}',
        subtitle: 'Hari ini · diproses',
        amount: amount,
        kind: TxKind.withdrawal,
      ),
    );
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
