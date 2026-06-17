import '../models.dart';

enum BackendBucket { bag, logo, avatar }

/// Kontrak akses data SaveBite. Dua implementasi:
/// - [FakeBackend] (data contoh in-memory, untuk offline/test)
/// - [SupabaseBackend] (Postgres + Storage + Auth)
abstract class Backend {
  bool get isRemote;

  // ── Profil konsumen ──
  Future<Profile?> currentProfile();
  Future<void> updateProfile({String? name, String? email, String? phone, String? avatarUrl});
  Future<void> setLastMode(String mode);

  // ── Browse konsumen ──
  Future<List<Bag>> nearbyBags();
  Future<List<Bag>> searchBags(String query);
  Future<List<Bag>> bagsByMerchant(String merchantId);

  // ── Favorit ──
  Future<Set<String>> favoriteMerchantIds();
  Future<bool> toggleFavorite(String merchantId);
  Future<List<FavoriteStore>> favoriteStores();

  // ── Pesanan konsumen ──
  Future<OrderRecord> placeOrder(Bag bag, int qty, String method);
  Future<List<OrderRecord>> activeOrders();
  Future<List<OrderRecord>> orderHistory();
  Future<void> submitReview(
      OrderRecord order, int rating, List<String> tags, String comment);

  // ── Notifikasi ──
  Future<List<AppNotification>> notifications();
  Future<void> markAllNotificationsRead();

  // ── Toko (merchant) ──
  Future<StoreProfile?> myStore();
  Future<void> upsertStore({
    required String name,
    required String category,
    required String address,
    required String open,
    required String close,
    String description,
    String? logoUrl,
  });

  // ── Bag merchant ──
  Future<List<MerchantBag>> myBags();
  Future<void> addBag({
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    String? imageUrl,
  });
  Future<void> updateBag(
    MerchantBag bag, {
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    String? imageUrl,
  });
  Future<void> setBagActive(MerchantBag bag, bool active);
  Future<void> duplicateBag(MerchantBag bag);

  // ── Order masuk + statistik ──
  Future<List<IncomingOrder>> incomingOrders();
  Future<IncomingOrder?> redeemOrder(String code);
  Future<MerchantStats> merchantStats();

  // ── Saldo ──
  Future<int> balance();
  Future<List<TxRecord>> transactions();
  Future<void> withdraw(int amount, String bank);

  // ── Storage ──
  /// Pilih gambar dari galeri/kamera lalu unggah; kembalikan URL publik
  /// (atau null bila dibatalkan).
  Future<String?> uploadImage(BackendBucket bucket);
}
