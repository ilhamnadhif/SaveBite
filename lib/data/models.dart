import 'package:flutter/material.dart';

/// Format angka jadi rupiah, mis. 15000 -> "Rp15.000".
String formatRupiah(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return 'Rp$buf';
}

/// Normalisasi daftar perkiraan isi bag: spasi dibersihkan dan duplikat
/// (tanpa membedakan kapital) dihapus sambil mempertahankan urutan pertama.
List<String> normalizeBagContents(Iterable<String> values) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final item = value.trim();
    if (item.isEmpty || !seen.add(item.toLowerCase())) continue;
    normalized.add(item);
  }
  return normalized;
}

/// Merchant boleh memisahkan isi dengan koma, titik koma, atau baris baru.
List<String> parseBagContents(String text) =>
    normalizeBagContents(text.split(RegExp(r'[,;\r\n]+')));

/// Pesan validasi domain yang dipakai form dan backend demo.
String? bagContentsValidationError(Iterable<String> values) {
  final normalized = normalizeBagContents(values);
  if (normalized.length > 20) return 'Maksimal 20 item';
  if (normalized.any((item) => item.length > 80)) {
    return 'Setiap item maksimal 80 karakter';
  }
  return null;
}

class Merchant {
  final String id;
  final String name;
  final String initial;
  final Color avatarColor;
  final String category;
  final double rating;
  final int reviewCount;
  final String distance;
  final String address;
  final String hours;
  final String coverImage;
  final int bagsSaved;
  final double? latitude;
  final double? longitude;

  const Merchant({
    required this.id,
    required this.name,
    required this.initial,
    required this.avatarColor,
    required this.category,
    required this.rating,
    required this.reviewCount,
    required this.distance,
    required this.address,
    required this.hours,
    required this.coverImage,
    required this.bagsSaved,
    this.latitude,
    this.longitude,
  });

  Merchant copyWith({String? distance, double? latitude, double? longitude}) =>
      Merchant(
        id: id,
        name: name,
        initial: initial,
        avatarColor: avatarColor,
        category: category,
        rating: rating,
        reviewCount: reviewCount,
        distance: distance ?? this.distance,
        address: address,
        hours: hours,
        coverImage: coverImage,
        bagsSaved: bagsSaved,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
      );
}

class Bag {
  final String id;
  final Merchant merchant;
  final String title;
  final String description;
  final int originalPrice;
  final int salePrice;
  final int quantityLeft;
  final int quantityTotal;
  final String pickupWindow;
  final String image;
  final List<String> contents;
  final bool soldOut;
  final DateTime? availableOn;
  final DateTime? pickupStartsAt;
  final DateTime? pickupEndsAt;

  const Bag({
    required this.id,
    required this.merchant,
    required this.title,
    required this.description,
    required this.originalPrice,
    required this.salePrice,
    required this.quantityLeft,
    required this.quantityTotal,
    required this.pickupWindow,
    required this.image,
    this.contents = const [],
    this.soldOut = false,
    this.availableOn,
    this.pickupStartsAt,
    this.pickupEndsAt,
  });

  int get discountPercent => originalPrice <= 0
      ? 0
      : ((1 - salePrice / originalPrice) * 100).clamp(0, 100).round();
  int get savings => (originalPrice - salePrice).clamp(0, originalPrice);

  Bag copyWith({Merchant? merchant, int? quantityLeft, bool? soldOut}) => Bag(
    id: id,
    merchant: merchant ?? this.merchant,
    title: title,
    description: description,
    originalPrice: originalPrice,
    salePrice: salePrice,
    quantityLeft: quantityLeft ?? this.quantityLeft,
    quantityTotal: quantityTotal,
    pickupWindow: pickupWindow,
    image: image,
    contents: contents,
    soldOut: soldOut ?? this.soldOut,
    availableOn: availableOn,
    pickupStartsAt: pickupStartsAt,
    pickupEndsAt: pickupEndsAt,
  );
}

enum OrderStatus { pending, ready, done, cancelled, expired }

class OrderRecord {
  final String id;
  final Bag bag;
  final String code;
  final String dateLabel;
  final int amount;
  final OrderStatus status;
  final bool reviewed;
  final bool canRate;
  final int quantity;
  final String paymentMethod;
  final DateTime? createdAt;
  final DateTime? pickupStartsAt;
  final DateTime? expiresAt;
  final DateTime? redeemedAt;
  final int subtotalAmount;
  final int serviceFee;
  final int merchantNetAmount;
  final String? pickupToken;

  const OrderRecord({
    this.id = '',
    required this.bag,
    required this.code,
    required this.dateLabel,
    required this.amount,
    required this.status,
    this.reviewed = false,
    this.canRate = false,
    this.quantity = 1,
    this.paymentMethod = 'GoPay',
    this.createdAt,
    this.pickupStartsAt,
    this.expiresAt,
    this.redeemedAt,
    this.subtotalAmount = 0,
    this.serviceFee = 0,
    this.merchantNetAmount = 0,
    this.pickupToken,
  });

  OrderRecord copyWith({
    OrderStatus? status,
    bool? reviewed,
    bool? canRate,
    String? pickupToken,
    bool clearPickupToken = false,
  }) => OrderRecord(
    id: id,
    bag: bag,
    code: code,
    dateLabel: dateLabel,
    amount: amount,
    status: status ?? this.status,
    reviewed: reviewed ?? this.reviewed,
    canRate: canRate ?? this.canRate,
    quantity: quantity,
    paymentMethod: paymentMethod,
    createdAt: createdAt,
    pickupStartsAt: pickupStartsAt,
    expiresAt: expiresAt,
    redeemedAt: redeemedAt,
    subtotalAmount: subtotalAmount,
    serviceFee: serviceFee,
    merchantNetAmount: merchantNetAmount,
    pickupToken: clearPickupToken ? null : (pickupToken ?? this.pickupToken),
  );
}

enum NotifType { ready, newBag, rating, payment }

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String time;
  final NotifType type;
  final bool unread;
  final String group;
  final String? route;
  final DateTime? createdAt;

  const AppNotification({
    this.id = '',
    required this.title,
    required this.body,
    required this.time,
    required this.type,
    required this.group,
    this.unread = false,
    this.route,
    this.createdAt,
  });

  AppNotification copyWith({bool? unread}) => AppNotification(
    id: id,
    title: title,
    body: body,
    time: time,
    type: type,
    group: group,
    unread: unread ?? this.unread,
    route: route,
    createdAt: createdAt,
  );
}

class FavoriteStore {
  final Merchant merchant;
  final String availability; // "3 bag tersedia" / "Habis hari ini"
  final bool soldOut;

  const FavoriteStore({
    required this.merchant,
    required this.availability,
    this.soldOut = false,
  });
}

enum TxKind { income, withdrawal, reversal }

class TxRecord {
  final String id;
  final String title;
  final String subtitle;
  final int amount; // positif = masuk, akan ditampilkan sesuai kind
  final TxKind kind;
  final DateTime? createdAt;
  final String status;

  const TxRecord({
    this.id = '',
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
    this.createdAt,
    this.status = 'completed',
  });
}

/// Bag milik merchant (untuk Kelola Bag & Dashboard).
class MerchantBag {
  final String id;
  final String title;
  final int salePrice;
  final String pickupWindow;
  final int sold;
  final int total;
  final String image;
  final bool active;
  final String? statusNote; // mis. "Habis terjual kemarin"
  final String description;
  final List<String> contents;
  final int originalPrice;
  final int quantityLeft;
  final DateTime? availableOn;
  final DateTime? pickupStartsAt;
  final DateTime? pickupEndsAt;

  const MerchantBag({
    required this.id,
    required this.title,
    required this.salePrice,
    required this.pickupWindow,
    required this.sold,
    required this.total,
    required this.image,
    required this.active,
    this.statusNote,
    this.description = '',
    this.contents = const [],
    this.originalPrice = 0,
    int? quantityLeft,
    this.availableOn,
    this.pickupStartsAt,
    this.pickupEndsAt,
  }) : quantityLeft = quantityLeft ?? (total - sold);

  MerchantBag copyWith({
    String? id,
    String? title,
    int? salePrice,
    String? pickupWindow,
    int? sold,
    int? total,
    String? image,
    bool? active,
    String? statusNote,
    bool clearStatusNote = false,
    String? description,
    List<String>? contents,
    int? originalPrice,
    int? quantityLeft,
    DateTime? availableOn,
    DateTime? pickupStartsAt,
    DateTime? pickupEndsAt,
  }) {
    return MerchantBag(
      id: id ?? this.id,
      title: title ?? this.title,
      salePrice: salePrice ?? this.salePrice,
      pickupWindow: pickupWindow ?? this.pickupWindow,
      sold: sold ?? this.sold,
      total: total ?? this.total,
      image: image ?? this.image,
      active: active ?? this.active,
      statusNote: clearStatusNote ? null : (statusNote ?? this.statusNote),
      description: description ?? this.description,
      contents: contents ?? this.contents,
      originalPrice: originalPrice ?? this.originalPrice,
      quantityLeft: quantityLeft ?? this.quantityLeft,
      availableOn: availableOn ?? this.availableOn,
      pickupStartsAt: pickupStartsAt ?? this.pickupStartsAt,
      pickupEndsAt: pickupEndsAt ?? this.pickupEndsAt,
    );
  }
}

enum IncomingOrderStatus {
  pending,
  paid,
  preparing,
  ready,
  redeemed,
  cancelled,
  expired,
}

class IncomingOrder {
  final String id;
  final String customer;
  final String initial;
  final String time;
  final int bags;
  final String code;
  final bool needsAction; // perlu disiapkan
  final bool redeemed;
  final IncomingOrderStatus status;
  final String bagTitle;
  final String bagImage;
  final String pickupWindow;
  final int unitPrice;
  final int subtotalAmount;
  final int serviceFee;
  final int merchantNetAmount;
  final DateTime? createdAt;
  final DateTime? pickupStartsAt;
  final DateTime? expiresAt;
  final DateTime? redeemedAt;

  const IncomingOrder({
    this.id = '',
    required this.customer,
    required this.initial,
    required this.time,
    required this.bags,
    required this.code,
    this.needsAction = true,
    this.redeemed = false,
    IncomingOrderStatus? status,
    this.bagTitle = '',
    this.bagImage = '',
    this.pickupWindow = '',
    this.unitPrice = 0,
    this.subtotalAmount = 0,
    this.serviceFee = 0,
    this.merchantNetAmount = 0,
    this.createdAt,
    this.pickupStartsAt,
    this.expiresAt,
    this.redeemedAt,
  }) : status =
           status ??
           (redeemed ? IncomingOrderStatus.redeemed : IncomingOrderStatus.paid);

  IncomingOrder copyWith({
    bool? redeemed,
    IncomingOrderStatus? status,
    bool? needsAction,
    DateTime? redeemedAt,
  }) => IncomingOrder(
    id: id,
    customer: customer,
    initial: initial,
    time: time,
    bags: bags,
    code: code,
    needsAction: needsAction ?? this.needsAction,
    redeemed: redeemed ?? this.redeemed,
    status: (redeemed ?? this.redeemed)
        ? IncomingOrderStatus.redeemed
        : (status ?? this.status),
    bagTitle: bagTitle,
    bagImage: bagImage,
    pickupWindow: pickupWindow,
    unitPrice: unitPrice,
    subtotalAmount: subtotalAmount,
    serviceFee: serviceFee,
    merchantNetAmount: merchantNetAmount,
    createdAt: createdAt,
    pickupStartsAt: pickupStartsAt,
    expiresAt: expiresAt,
    redeemedAt: redeemedAt ?? this.redeemedAt,
  );
}

/// Ulasan yang dapat dibaca merchant pemilik pesanan. Data ini berasal dari
/// RPC terproteksi dan tidak memuat identitas kontak konsumen.
class MerchantReview {
  final String id;
  final String orderId;
  final String orderReference;
  final String customerName;
  final int rating;
  final List<String> tags;
  final String comment;
  final DateTime? createdAt;

  const MerchantReview({
    required this.id,
    required this.orderId,
    required this.orderReference,
    required this.customerName,
    required this.rating,
    this.tags = const [],
    this.comment = '',
    this.createdAt,
  });

  String get customerInitial {
    final parts = customerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }
}

class BagFilter {
  final Set<String> categories;
  final double? maxDistanceKm;
  final int? minPrice;
  final int? maxPrice;
  final TimeOfDay? pickupAfter;
  final TimeOfDay? pickupBefore;

  const BagFilter({
    this.categories = const {},
    this.maxDistanceKm,
    this.minPrice,
    this.maxPrice,
    this.pickupAfter,
    this.pickupBefore,
  });

  bool get isEmpty =>
      categories.isEmpty &&
      maxDistanceKm == null &&
      minPrice == null &&
      maxPrice == null &&
      pickupAfter == null &&
      pickupBefore == null;

  BagFilter copyWith({
    Set<String>? categories,
    double? maxDistanceKm,
    bool clearMaxDistance = false,
    int? minPrice,
    bool clearMinPrice = false,
    int? maxPrice,
    bool clearMaxPrice = false,
    TimeOfDay? pickupAfter,
    bool clearPickupAfter = false,
    TimeOfDay? pickupBefore,
    bool clearPickupBefore = false,
  }) {
    return BagFilter(
      categories: categories ?? this.categories,
      maxDistanceKm: clearMaxDistance
          ? null
          : (maxDistanceKm ?? this.maxDistanceKm),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      pickupAfter: clearPickupAfter ? null : (pickupAfter ?? this.pickupAfter),
      pickupBefore: clearPickupBefore
          ? null
          : (pickupBefore ?? this.pickupBefore),
    );
  }
}

/// Satu aturan filter dipakai oleh preview, fake backend, dan Supabase agar
/// jumlah hasil tidak berubah setelah tombol Terapkan ditekan.
bool bagMatchesFilter(Bag bag, BagFilter filter) {
  if (bag.soldOut || bag.quantityLeft <= 0) return false;
  if (filter.categories.isNotEmpty &&
      !filter.categories.any(
        (category) =>
            category.toLowerCase() == bag.merchant.category.toLowerCase(),
      )) {
    return false;
  }
  if (filter.minPrice != null && bag.salePrice < filter.minPrice!) return false;
  if (filter.maxPrice != null && bag.salePrice > filter.maxPrice!) return false;

  if (filter.maxDistanceKm != null) {
    final match = RegExp(
      r'([0-9]+(?:[,.][0-9]+)?)',
    ).firstMatch(bag.merchant.distance);
    final distance = double.tryParse(
      (match?.group(1) ?? '').replaceAll(',', '.'),
    );
    if (distance == null || distance > filter.maxDistanceKm!) return false;
  }

  if (filter.pickupAfter != null || filter.pickupBefore != null) {
    final window = _bagPickupMinutes(bag);
    if (window == null) return false;
    final after = filter.pickupAfter;
    final before = filter.pickupBefore;
    // Sebuah bag cocok bila jadwal pickup-nya beririsan dengan rentang filter.
    if (after != null && window.$2 < after.hour * 60 + after.minute) {
      return false;
    }
    if (before != null && window.$1 > before.hour * 60 + before.minute) {
      return false;
    }
  }
  return true;
}

(int, int)? _bagPickupMinutes(Bag bag) {
  final starts = bag.pickupStartsAt;
  final ends = bag.pickupEndsAt;
  if (starts != null && ends != null) {
    return (starts.hour * 60 + starts.minute, ends.hour * 60 + ends.minute);
  }
  final match = RegExp(
    r'(\d{1,2})[.:](\d{2})\s*[-–—]\s*(\d{1,2})[.:](\d{2})',
  ).firstMatch(bag.pickupWindow);
  if (match == null) return null;
  final startHour = int.tryParse(match.group(1)!);
  final startMinute = int.tryParse(match.group(2)!);
  final endHour = int.tryParse(match.group(3)!);
  final endMinute = int.tryParse(match.group(4)!);
  if (startHour == null ||
      startMinute == null ||
      endHour == null ||
      endMinute == null ||
      startHour > 23 ||
      endHour > 23 ||
      startMinute > 59 ||
      endMinute > 59) {
    return null;
  }
  return (startHour * 60 + startMinute, endHour * 60 + endMinute);
}

enum BankAccountStatus { pending, verified, rejected, disabled }

class BankAccount {
  final String id;
  final String bankCode;
  final String bankName;
  final String accountNumberMasked;
  final String accountHolder;
  final BankAccountStatus status;
  final bool isDefault;

  const BankAccount({
    required this.id,
    required this.bankCode,
    required this.bankName,
    required this.accountNumberMasked,
    required this.accountHolder,
    bool verified = false,
    BankAccountStatus? status,
    this.isDefault = false,
  }) : status =
           status ??
           (verified ? BankAccountStatus.verified : BankAccountStatus.pending);

  String get label => '$bankName · $accountNumberMasked';
  bool get verified => status == BankAccountStatus.verified;

  BankAccount copyWith({bool? isDefault, BankAccountStatus? status}) =>
      BankAccount(
        id: id,
        bankCode: bankCode,
        bankName: bankName,
        accountNumberMasked: accountNumberMasked,
        accountHolder: accountHolder,
        status: status ?? this.status,
        isDefault: isDefault ?? this.isDefault,
      );
}

enum PayoutStatus { pending, processing, paid, failed, cancelled }

class PayoutRequest {
  final String id;
  final int grossAmount;
  final int feeAmount;
  final int netAmount;
  final PayoutStatus status;
  final BankAccount bankAccount;
  final DateTime? createdAt;

  const PayoutRequest({
    required this.id,
    required this.grossAmount,
    required this.feeAmount,
    required this.netAmount,
    required this.status,
    required this.bankAccount,
    this.createdAt,
  });
}

/// Profil pengguna (konsumen) — dari tabel `profiles`.
class Profile {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String? avatarUrl;
  final String lastMode; // 'consumer' | 'merchant'

  const Profile({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.avatarUrl,
    this.lastMode = 'consumer',
  });
}

/// Profil toko merchant — dari tabel `merchants` (milik user).
class StoreProfile {
  final String id;
  final String name;
  final String category;
  final String address;
  final String openTime;
  final String closeTime;
  final String description;
  final String? logoUrl;
  final double? latitude;
  final double? longitude;

  const StoreProfile({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.openTime,
    required this.closeTime,
    this.description = '',
    this.logoUrl,
    this.latitude,
    this.longitude,
  });
}

/// Ringkasan statistik dashboard merchant.
class MerchantStats {
  final int bagsSoldToday;
  final int incomeToday;
  final int activeBagCount;
  final int pendingOrderCount;
  final int incomeThisMonth;
  final double foodSavedKg;

  const MerchantStats({
    this.bagsSoldToday = 0,
    this.incomeToday = 0,
    this.activeBagCount = 0,
    this.pendingOrderCount = 0,
    this.incomeThisMonth = 0,
    this.foodSavedKg = 0,
  });
}
