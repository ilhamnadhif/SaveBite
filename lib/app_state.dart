import 'package:flutter/foundation.dart';
import 'data/models.dart';
import 'data/backend/backend.dart';
import 'services/app_backend.dart';

enum AppMode { consumer, merchant }

/// State global SaveBite: cache reaktif di atas [backend] (Fake atau Supabase).
/// Layar membaca getter cache (sinkron) lewat [ListenableBuilder]; data dimuat
/// async lewat loadX() dan diubah lewat mutator async.
class AppState extends ChangeNotifier {
  AppMode mode = AppMode.consumer;

  String location = 'Margonda, Depok';
  bool get hasNearbyBags => location == 'Margonda, Depok';
  static const cities = ['Margonda, Depok', 'Cibinong, Bogor', 'Kemang, Jakarta'];

  bool merchantSetupDone = false;
  bool locationPrimed = false;

  /// Peran yang dipilih di Fork sebelum login (untuk routing pasca-OAuth).
  /// null = tak memilih (pakai [lastMode]); true = jual; false = beli.
  bool? pendingMerchantIntent;

  /// Ekosistem terakhir (dari profil); untuk mengarahkan pengguna lama.
  String lastMode = 'consumer';

  static const paymentMethods = ['GoPay', 'OVO', 'Virtual Account BCA'];
  static const bankAccounts = ['BCA · ••6789', 'Mandiri · ••1234', 'BNI · ••4521'];
  String defaultPaymentMethod = 'GoPay';
  String selectedBank = 'BCA · ••6789';

  // ── Profil konsumen ──
  String userName = 'Ilham Hidayat';
  String userEmail = 'ilham@gmail.com';
  String userPhone = '0812-3456-7890';
  String? userAvatarUrl;
  String get userInitials {
    final parts = userName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  // ── Profil toko ──
  String storeName = 'Roti Nyaman Bakery';
  String storeCategory = 'Bakery';
  String storeAddress = 'Jl. Margonda Raya No. 88, Depok';
  String openTime = '08.00';
  String closeTime = '21.00';
  String storeDescription = '';
  String? storeLogoUrl;

  // ── Cache ──
  List<Bag> _nearby = [];
  Set<String> _favIds = {};
  List<FavoriteStore> _favStores = [];
  List<OrderRecord> _active = [];
  List<OrderRecord> _history = [];
  List<AppNotification> _notifs = [];
  List<MerchantBag> _bags = [];
  List<IncomingOrder> _incoming = [];
  List<TxRecord> _tx = [];
  int balance = 0;
  int bagsSoldToday = 0;
  int incomeToday = 0;

  // ── Getter sinkron untuk layar ──
  List<Bag> get nearbyBags => _nearby;
  List<OrderRecord> get activeOrders => _active;
  List<OrderRecord> get orderHistory => _history;
  List<FavoriteStore> get favoriteStores => _favStores;
  bool isFavorite(String id) => _favIds.contains(id);
  List<AppNotification> get notifications => _notifs;
  int get unreadCount => _notifs.where((n) => n.unread).length;
  List<MerchantBag> get activeBags =>
      _bags.where((b) => b.active).toList(growable: false);
  List<MerchantBag> get inactiveBags =>
      _bags.where((b) => !b.active).toList(growable: false);
  int get activeBagCount => activeBags.length;
  List<IncomingOrder> get pendingOrders =>
      _incoming.where((o) => !o.redeemed).toList(growable: false);
  List<IncomingOrder> get completedOrders =>
      _incoming.where((o) => o.redeemed).toList(growable: false);
  int get pendingOrderCount => pendingOrders.length;
  List<TxRecord> get transactions => _tx;

  // ── One-off (tak di-cache) ──
  Future<List<Bag>> search(String q) => backend.searchBags(q);
  Future<List<Bag>> bagsByMerchant(String id) => backend.bagsByMerchant(id);

  // ── Loads ──
  Future<void> bootstrap() async {
    await loadProfile();
    await loadStore();
  }

  Future<void> loadProfile() async {
    final p = await backend.currentProfile();
    if (p != null) {
      userName = p.name;
      userEmail = p.email;
      userPhone = p.phone;
      userAvatarUrl = p.avatarUrl;
      lastMode = p.lastMode;
    }
    notifyListeners();
  }

  Future<void> loadConsumerHome() async {
    _nearby = await backend.nearbyBags();
    _favIds = await backend.favoriteMerchantIds();
    notifyListeners();
  }

  Future<void> loadOrders() async {
    _active = await backend.activeOrders();
    _history = await backend.orderHistory();
    notifyListeners();
  }

  Future<void> loadFavorites() async {
    _favIds = await backend.favoriteMerchantIds();
    _favStores = await backend.favoriteStores();
    notifyListeners();
  }

  Future<void> loadNotifications() async {
    _notifs = await backend.notifications();
    notifyListeners();
  }

  Future<void> loadStore() async {
    final s = await backend.myStore();
    merchantSetupDone = s != null;
    if (s != null) {
      storeName = s.name;
      storeCategory = s.category;
      storeAddress = s.address;
      openTime = s.openTime;
      closeTime = s.closeTime;
      storeDescription = s.description;
      storeLogoUrl = s.logoUrl;
    }
    notifyListeners();
  }

  Future<void> loadMerchantData() async {
    _bags = await backend.myBags();
    _incoming = await backend.incomingOrders();
    final st = await backend.merchantStats();
    bagsSoldToday = st.bagsSoldToday;
    incomeToday = st.incomeToday;
    notifyListeners();
  }

  Future<void> loadBalance() async {
    balance = await backend.balance();
    _tx = await backend.transactions();
    notifyListeners();
  }

  // ── Mutator ──
  Future<bool> toggleFavorite(String merchantId) async {
    final added = await backend.toggleFavorite(merchantId);
    if (added) {
      _favIds.add(merchantId);
    } else {
      _favIds.remove(merchantId);
    }
    notifyListeners();
    _favStores = await backend.favoriteStores();
    notifyListeners();
    return added;
  }

  Future<OrderRecord> placeOrder(Bag bag, int qty, String method) async {
    final order = await backend.placeOrder(bag, qty, method);
    _active.insert(0, order);
    notifyListeners();
    return order;
  }

  Future<void> submitReview(
          OrderRecord order, int rating, List<String> tags, String comment) =>
      backend.submitReview(order, rating, tags, comment);

  Future<void> addBag({
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    String? imageUrl,
  }) async {
    await backend.addBag(
        title: title,
        salePrice: salePrice,
        pickupWindow: pickupWindow,
        total: total,
        imageUrl: imageUrl);
    _bags = await backend.myBags();
    notifyListeners();
  }

  Future<void> updateBag(
    MerchantBag bag, {
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    String? imageUrl,
  }) async {
    await backend.updateBag(bag,
        title: title,
        salePrice: salePrice,
        pickupWindow: pickupWindow,
        total: total,
        imageUrl: imageUrl);
    _bags = await backend.myBags();
    notifyListeners();
  }

  Future<void> toggleBagActive(MerchantBag bag) async {
    await backend.setBagActive(bag, !bag.active);
    _bags = await backend.myBags();
    notifyListeners();
  }

  Future<void> duplicateBag(MerchantBag bag) async {
    await backend.duplicateBag(bag);
    _bags = await backend.myBags();
    notifyListeners();
  }

  Future<IncomingOrder?> redeemOrder(String code) async {
    final order = await backend.redeemOrder(code);
    _incoming = await backend.incomingOrders();
    final st = await backend.merchantStats();
    bagsSoldToday = st.bagsSoldToday;
    incomeToday = st.incomeToday;
    notifyListeners();
    return order;
  }

  Future<void> withdraw(int amount) async {
    await backend.withdraw(amount, selectedBank);
    balance = await backend.balance();
    _tx = await backend.transactions();
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    await backend.markAllNotificationsRead();
    _notifs = await backend.notifications();
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? email, String? phone, String? avatarUrl}) async {
    await backend.updateProfile(
        name: name, email: email, phone: phone, avatarUrl: avatarUrl);
    if (name != null && name.trim().isNotEmpty) userName = name.trim();
    if (email != null && email.trim().isNotEmpty) userEmail = email.trim();
    if (phone != null && phone.trim().isNotEmpty) userPhone = phone.trim();
    if (avatarUrl != null) userAvatarUrl = avatarUrl;
    notifyListeners();
  }

  Future<void> updateStore({
    String? name,
    String? category,
    String? address,
    String? open,
    String? close,
    String? description,
    String? logoUrl,
  }) async {
    await backend.upsertStore(
      name: name ?? storeName,
      category: category ?? storeCategory,
      address: address ?? storeAddress,
      open: open ?? openTime,
      close: close ?? closeTime,
      description: description ?? storeDescription,
      logoUrl: logoUrl ?? storeLogoUrl,
    );
    merchantSetupDone = true;
    if (name != null && name.trim().isNotEmpty) storeName = name.trim();
    if (category != null) storeCategory = category;
    if (address != null && address.trim().isNotEmpty) storeAddress = address.trim();
    if (open != null) openTime = open;
    if (close != null) closeTime = close;
    if (description != null) storeDescription = description;
    if (logoUrl != null) storeLogoUrl = logoUrl;
    notifyListeners();
  }

  /// Upload gambar lewat backend (galeri → storage), kembalikan URL/path.
  Future<String?> uploadImage(BackendBucket bucket) => backend.uploadImage(bucket);

  void setDefaultPaymentMethod(String m) {
    defaultPaymentMethod = m;
    notifyListeners();
  }

  void setBank(String b) {
    selectedBank = b;
    notifyListeners();
  }

  void setLocation(String value) {
    location = value;
    notifyListeners();
  }

  void rememberMode(String m) {
    lastMode = m;
    backend.setLastMode(m);
  }

  void switchToMerchant() {
    mode = AppMode.merchant;
    notifyListeners();
  }

  void switchToConsumer() {
    mode = AppMode.consumer;
    notifyListeners();
  }

  /// Reset untuk test: backend baru (fake) + bersihkan cache.
  @visibleForTesting
  void resetSession() {
    useFakeBackend();
    mode = AppMode.consumer;
    location = 'Margonda, Depok';
    merchantSetupDone = false;
    locationPrimed = false;
    defaultPaymentMethod = 'GoPay';
    selectedBank = 'BCA · ••6789';
    userName = 'Ilham Hidayat';
    userEmail = 'ilham@gmail.com';
    userPhone = '0812-3456-7890';
    userAvatarUrl = null;
    storeName = 'Roti Nyaman Bakery';
    storeCategory = 'Bakery';
    storeAddress = 'Jl. Margonda Raya No. 88, Depok';
    openTime = '08.00';
    closeTime = '21.00';
    storeDescription = '';
    storeLogoUrl = null;
    _nearby = [];
    _favIds = {};
    _favStores = [];
    _active = [];
    _history = [];
    _notifs = [];
    _bags = [];
    _incoming = [];
    _tx = [];
    balance = 0;
    bagsSoldToday = 0;
    incomeToday = 0;
    notifyListeners();
  }
}

final appState = AppState();
