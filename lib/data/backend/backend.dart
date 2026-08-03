import 'dart:typed_data';

import '../business_config.dart';
import '../models.dart';

enum BackendBucket { bag, logo, avatar }

/// Error domain yang aman ditampilkan ke pengguna. Implementasi backend harus
/// membungkus detail teknis/SQL menjadi pesan yang bisa ditindaklanjuti.
class BackendException implements Exception {
  final String code;
  final String message;

  const BackendException(this.code, this.message);

  @override
  String toString() => message;
}

/// Kontrak akses data SaveBite. Dua implementasi:
/// - [FakeBackend] (data contoh in-memory, untuk demo eksplisit/test)
/// - [SupabaseBackend] (Postgres + Storage + Auth)
abstract class Backend {
  bool get isRemote;

  /// Bersihkan seluruh cache yang terkait user saat sesi berubah/logout.
  void clearSessionCache();

  /// Biaya/limit non-rahasia yang juga dipakai fungsi transaksi database.
  Future<BusinessConfig> businessConfig();

  // ── Profil konsumen ──
  Future<Profile?> currentProfile();
  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
  });
  Future<void> setLastMode(String mode);

  // ── Browse konsumen ──
  Future<List<Bag>> nearbyBags({
    double? latitude,
    double? longitude,
    BagFilter filter = const BagFilter(),
  });
  Future<List<Bag>> searchBags(
    String query, {
    double? latitude,
    double? longitude,
    BagFilter filter = const BagFilter(),
  });
  Future<List<Bag>> bagsByMerchant(String merchantId);

  // ── Favorit ──
  Future<Set<String>> favoriteMerchantIds();
  Future<bool> toggleFavorite(String merchantId);
  Future<List<FavoriteStore>> favoriteStores();

  // ── Pesanan konsumen ──
  Future<OrderRecord> placeOrder(
    Bag bag,
    int qty,
    String method, {
    required String idempotencyKey,
  });

  /// Meminta backend menyinkronkan status pembayaran dari provider. Client
  /// tidak pernah dipercaya untuk menandai order sebagai lunas.
  Future<OrderRecord> refreshPayment(OrderRecord order);
  Future<List<OrderRecord>> activeOrders();
  Future<List<OrderRecord>> orderHistory();
  Future<OrderRecord> issuePickupToken(OrderRecord order);
  Future<void> submitReview(
    OrderRecord order,
    int rating,
    List<String> tags,
    String comment,
  );

  // ── Notifikasi ──
  Future<List<AppNotification>> notifications();
  Future<void> markAllNotificationsRead();
  Stream<List<AppNotification>> watchNotifications();

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
    double? latitude,
    double? longitude,
  });

  // ── Bag merchant ──
  Future<List<MerchantBag>> myBags();
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
  });
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
  });
  Future<void> setBagActive(MerchantBag bag, bool active);
  Future<void> duplicateBag(MerchantBag bag);

  // ── Order masuk + statistik ──
  Future<List<IncomingOrder>> incomingOrders();
  Stream<List<IncomingOrder>> watchIncomingOrders();
  Future<void> markOrderReady(String orderId);
  Future<IncomingOrder> cancelMerchantOrder(String orderId);
  Future<IncomingOrder?> redeemOrder(String pickupToken);
  Future<List<MerchantReview>> merchantReviews();
  Future<MerchantStats> merchantStats();

  // ── Saldo ──
  Future<int> balance();
  Future<List<TxRecord>> transactions();
  Stream<List<TxRecord>> watchTransactions();
  Future<List<BankAccount>> bankAccounts();
  Future<void> setDefaultBankAccount(String bankAccountId);
  Future<BankAccount> saveBankAccount({
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    required String idempotencyKey,
  });
  Future<List<PayoutRequest>> payoutRequests();
  Future<PayoutRequest> requestPayout({
    required int amount,
    required String bankAccountId,
    required String idempotencyKey,
  });

  // ── Privasi akun ──
  Future<void> deleteAccount();

  // ── Storage ──
  /// Pilih gambar dari galeri/kamera lalu unggah; kembalikan URL publik
  /// (atau null bila dibatalkan).
  Future<String?> uploadImage(BackendBucket bucket);

  /// Unggah byte gambar yang sudah dipilih oleh caller. Jalur ini memakai
  /// validasi ukuran, ekstensi, MIME, ownership, dan bucket yang sama dengan
  /// [uploadImage].
  Future<String?> uploadImageBytes(
    BackendBucket bucket,
    Uint8List bytes, {
    required String filename,
  });
}
