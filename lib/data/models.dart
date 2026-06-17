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
  });
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
  });

  int get discountPercent =>
      ((1 - salePrice / originalPrice) * 100).round();
  int get savings => originalPrice - salePrice;
}

enum OrderStatus { ready, done, expired }

class OrderRecord {
  final Bag bag;
  final String code;
  final String dateLabel;
  final int amount;
  final OrderStatus status;
  final bool reviewed;
  final bool canRate;
  final int quantity;
  final String paymentMethod;

  const OrderRecord({
    required this.bag,
    required this.code,
    required this.dateLabel,
    required this.amount,
    required this.status,
    this.reviewed = false,
    this.canRate = false,
    this.quantity = 1,
    this.paymentMethod = 'GoPay',
  });

  OrderRecord copyWith({OrderStatus? status, bool? reviewed, bool? canRate}) =>
      OrderRecord(
        bag: bag,
        code: code,
        dateLabel: dateLabel,
        amount: amount,
        status: status ?? this.status,
        reviewed: reviewed ?? this.reviewed,
        canRate: canRate ?? this.canRate,
        quantity: quantity,
        paymentMethod: paymentMethod,
      );
}

enum NotifType { ready, newBag, rating, payment }

class AppNotification {
  final String title;
  final String body;
  final String time;
  final NotifType type;
  final bool unread;
  final String group;

  const AppNotification({
    required this.title,
    required this.body,
    required this.time,
    required this.type,
    required this.group,
    this.unread = false,
  });

  AppNotification copyWith({bool? unread}) => AppNotification(
        title: title,
        body: body,
        time: time,
        type: type,
        group: group,
        unread: unread ?? this.unread,
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

enum TxKind { income, withdrawal }

class TxRecord {
  final String title;
  final String subtitle;
  final int amount; // positif = masuk, akan ditampilkan sesuai kind
  final TxKind kind;

  const TxRecord({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
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
  });

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
    );
  }
}

class IncomingOrder {
  final String customer;
  final String initial;
  final String time;
  final int bags;
  final String code;
  final bool needsAction; // perlu disiapkan
  final bool redeemed;

  const IncomingOrder({
    required this.customer,
    required this.initial,
    required this.time,
    required this.bags,
    required this.code,
    this.needsAction = true,
    this.redeemed = false,
  });

  IncomingOrder copyWith({bool? redeemed}) => IncomingOrder(
        customer: customer,
        initial: initial,
        time: time,
        bags: bags,
        code: code,
        needsAction: needsAction,
        redeemed: redeemed ?? this.redeemed,
      );
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

  const StoreProfile({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.openTime,
    required this.closeTime,
    this.description = '',
    this.logoUrl,
  });
}

/// Ringkasan statistik dashboard merchant.
class MerchantStats {
  final int bagsSoldToday;
  final int incomeToday;
  final int activeBagCount;

  const MerchantStats({
    this.bagsSoldToday = 0,
    this.incomeToday = 0,
    this.activeBagCount = 0,
  });
}
