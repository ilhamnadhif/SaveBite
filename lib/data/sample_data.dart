import '../theme/app_colors.dart';
import 'models.dart';

/// Data contoh (mock) untuk demo. Mengikuti copy & angka dari desain,
/// diperkaya jadi ~9 bag dari 8 merchant lintas kategori agar filter,
/// peta, dan pencarian terasa hidup.
class SampleData {
  SampleData._();

  static const img1 = 'assets/images/food1.jpg';
  static const img2 = 'assets/images/food2.jpg';
  static const img3 = 'assets/images/food3.jpg';
  static const img4 = 'assets/images/food4.jpg';
  static const img5 = 'assets/images/food5.jpg';
  static const img6 = 'assets/images/food6.jpg';
  static const img7 = 'assets/images/food7.jpg';
  static const img8 = 'assets/images/food8.jpg';
  static const img9 = 'assets/images/food9.jpg';
  static const img10 = 'assets/images/food10.jpg';

  // ───────────── Merchant ─────────────
  static const rotiNyaman = Merchant(
    id: 'm1',
    name: 'Roti Nyaman Bakery',
    initial: 'R',
    avatarColor: AppColors.amberAvatar,
    category: 'Bakery',
    rating: 4.8,
    reviewCount: 212,
    distance: '0,4 km',
    address: 'Jl. Margonda Raya No. 88, Depok',
    hours: '08.00–21.00',
    coverImage: img2,
    bagsSaved: 184,
    latitude: -6.3718,
    longitude: 106.8318,
  );

  static const kopiSenja = Merchant(
    id: 'm2',
    name: 'Kopi Senja',
    initial: 'K',
    avatarColor: AppColors.greenBright,
    category: 'Kafe',
    rating: 4.6,
    reviewCount: 98,
    distance: '0,9 km',
    address: 'Jl. Kemang Raya No. 12, Depok',
    hours: '10.00–22.00',
    coverImage: img8,
    bagsSaved: 76,
    latitude: -6.3762,
    longitude: 106.8392,
  );

  static const donatManis = Merchant(
    id: 'm3',
    name: 'Donat Manis Margonda',
    initial: 'D',
    avatarColor: AppColors.terracotta,
    category: 'Bakery',
    rating: 4.7,
    reviewCount: 64,
    distance: '1,2 km',
    address: 'Jl. Akses UI No. 5, Depok',
    hours: '08.00–20.00',
    coverImage: img7,
    bagsSaved: 41,
    latitude: -6.3654,
    longitude: 106.8408,
  );

  static const tokoSehat = Merchant(
    id: 'm4',
    name: 'Toko Sehat Depok',
    initial: 'T',
    avatarColor: AppColors.greenAccent,
    category: 'Sehat',
    rating: 4.5,
    reviewCount: 33,
    distance: '1,8 km',
    address: 'Jl. Juanda No. 21, Depok',
    hours: '09.00–21.00',
    coverImage: img3,
    bagsSaved: 22,
    latitude: -6.3825,
    longitude: 106.8251,
  );

  static const warungIbu = Merchant(
    id: 'm5',
    name: 'Warung Nasi Ibu',
    initial: 'W',
    avatarColor: AppColors.brown,
    category: 'Resto',
    rating: 4.4,
    reviewCount: 120,
    distance: '1,1 km',
    address: 'Jl. Nusantara No. 3, Depok',
    hours: '07.00–21.00',
    coverImage: img6,
    bagsSaved: 95,
    latitude: -6.3686,
    longitude: 106.8234,
  );

  static const sayurMart = Merchant(
    id: 'm6',
    name: 'Sayur Segar Mart',
    initial: 'S',
    avatarColor: AppColors.bca,
    category: 'Supermarket',
    rating: 4.3,
    reviewCount: 45,
    distance: '2,0 km',
    address: 'Jl. Tole Iskandar No. 17, Depok',
    hours: '08.00–22.00',
    coverImage: img10,
    bagsSaved: 58,
    latitude: -6.3898,
    longitude: 106.8441,
  );

  static const pizzaSudut = Merchant(
    id: 'm7',
    name: 'Pizza Sudut',
    initial: 'P',
    avatarColor: AppColors.ovo,
    category: 'Resto',
    rating: 4.6,
    reviewCount: 88,
    distance: '1,5 km',
    address: 'Jl. Siliwangi No. 9, Depok',
    hours: '11.00–23.00',
    coverImage: img9,
    bagsSaved: 67,
    latitude: -6.3796,
    longitude: 106.8189,
  );

  static const saladHijau = Merchant(
    id: 'm8',
    name: 'Salad Hijau',
    initial: 'H',
    avatarColor: AppColors.greenAccent,
    category: 'Sehat',
    rating: 4.7,
    reviewCount: 52,
    distance: '0,7 km',
    address: 'Jl. Margonda Raya No. 210, Depok',
    hours: '09.00–20.00',
    coverImage: img4,
    bagsSaved: 39,
    latitude: -6.3740,
    longitude: 106.8354,
  );

  static const merchants = [
    rotiNyaman,
    kopiSenja,
    donatManis,
    tokoSehat,
    warungIbu,
    sayurMart,
    pizzaSudut,
    saladHijau,
  ];

  // ───────────── Bag ─────────────
  static const bagRoti = Bag(
    id: 'b1',
    merchant: rotiNyaman,
    title: 'Surprise Bag Roti & Pastry',
    description:
        'Campuran roti manis, pastry, dan donat hari ini yang masih fresh. Isi kejutan senilai minimal Rp45.000.',
    originalPrice: 45000,
    salePrice: 15000,
    quantityLeft: 3,
    quantityTotal: 8,
    pickupWindow: '20.00–21.00',
    image: img1,
    contents: ['Roti manis', 'Croissant', 'Donat', 'Roti tawar'],
  );

  static const bagKopi = Bag(
    id: 'b2',
    merchant: kopiSenja,
    title: 'Surprise Bag Pastry & Kopi',
    description:
        'Pastry pilihan dan kopi hari ini yang belum sempat terjual. Cocok untuk teman sore.',
    originalPrice: 50000,
    salePrice: 20000,
    quantityLeft: 6,
    quantityTotal: 10,
    pickupWindow: '19.30–20.30',
    image: img8,
    contents: ['Croissant', 'Muffin', 'Kopi susu', 'Cookies'],
  );

  static const bagDonat = Bag(
    id: 'b3',
    merchant: donatManis,
    title: 'Surprise Bag Donat',
    description: 'Aneka donat manis hari ini yang masih lembut.',
    originalPrice: 40000,
    salePrice: 16000,
    quantityLeft: 0,
    quantityTotal: 6,
    pickupWindow: '18.00–19.00',
    image: img7,
    contents: ['Donat cokelat', 'Donat gula', 'Donat keju'],
    soldOut: true,
  );

  static const bagSehat = Bag(
    id: 'b4',
    merchant: tokoSehat,
    title: 'Surprise Bag Buah Potong',
    description:
        'Aneka buah potong segar siap santap yang harus habis hari ini.',
    originalPrice: 38000,
    salePrice: 18000,
    quantityLeft: 4,
    quantityTotal: 8,
    pickupWindow: '17.00–18.00',
    image: img3,
    contents: ['Semangka', 'Melon', 'Pepaya', 'Nanas'],
  );

  static const bagNasi = Bag(
    id: 'b5',
    merchant: warungIbu,
    title: 'Surprise Bag Nasi & Lauk',
    description: 'Nasi hangat plus aneka lauk rumahan sisa porsi hari ini.',
    originalPrice: 35000,
    salePrice: 14000,
    quantityLeft: 5,
    quantityTotal: 12,
    pickupWindow: '20.30–21.30',
    image: img6,
    contents: ['Nasi', 'Ayam', 'Tempe', 'Sayur'],
  );

  static const bagSayur = Bag(
    id: 'b6',
    merchant: sayurMart,
    title: 'Surprise Bag Sayur & Buah',
    description:
        'Paket sayur dan buah mendekati best-before, masih segar & layak.',
    originalPrice: 60000,
    salePrice: 25000,
    quantityLeft: 8,
    quantityTotal: 15,
    pickupWindow: '18.00–20.00',
    image: img10,
    contents: ['Sayur hijau', 'Wortel', 'Tomat', 'Buah'],
  );

  static const bagPizza = Bag(
    id: 'b7',
    merchant: pizzaSudut,
    title: 'Surprise Bag Pizza Slice',
    description:
        'Aneka potongan pizza akhir hari yang masih nikmat dihangatkan.',
    originalPrice: 70000,
    salePrice: 28000,
    quantityLeft: 2,
    quantityTotal: 6,
    pickupWindow: '21.00–22.00',
    image: img9,
    contents: ['Pizza keju', 'Pizza daging', 'Garlic bread'],
  );

  static const bagSalad = Bag(
    id: 'b8',
    merchant: saladHijau,
    title: 'Surprise Bag Salad Sehat',
    description: 'Salad segar dan healthy bowl yang belum terjual sore ini.',
    originalPrice: 45000,
    salePrice: 19000,
    quantityLeft: 7,
    quantityTotal: 10,
    pickupWindow: '16.30–18.00',
    image: img4,
    contents: ['Garden salad', 'Healthy bowl', 'Smoothie'],
  );

  static const bagPastrySore = Bag(
    id: 'b9',
    merchant: kopiSenja,
    title: 'Surprise Bag Pastry Sore',
    description: 'Sisa pastry sore: croissant, danish, dan roti isi.',
    originalPrice: 30000,
    salePrice: 12000,
    quantityLeft: 0,
    quantityTotal: 8,
    pickupWindow: '17.30–18.30',
    image: img5,
    contents: ['Croissant', 'Danish', 'Roti isi'],
    soldOut: true,
  );

  /// Semua bag (tersedia lebih dulu, lalu yang habis).
  static const allBags = [
    bagRoti,
    bagKopi,
    bagSalad,
    bagSehat,
    bagNasi,
    bagSayur,
    bagPizza,
    bagDonat,
    bagPastrySore,
  ];

  static List<Bag> get nearbyBags =>
      allBags.where((b) => !b.soldOut).toList(growable: false);

  static const categories = [
    'Semua',
    'Bakery',
    'Kafe',
    'Resto',
    'Supermarket',
    'Sehat',
  ];

  static List<FavoriteStore> get favorites => const [
    FavoriteStore(merchant: rotiNyaman, availability: '3 bag tersedia'),
    FavoriteStore(merchant: kopiSenja, availability: '6 bag tersedia'),
    FavoriteStore(merchant: saladHijau, availability: '7 bag tersedia'),
    FavoriteStore(
      merchant: donatManis,
      availability: 'Habis hari ini',
      soldOut: true,
    ),
  ];

  static List<OrderRecord> get activeOrders => const [
    OrderRecord(
      id: 'order-1',
      bag: bagRoti,
      code: 'SB-7K2Q9',
      dateLabel: 'Hari ini',
      amount: 16000,
      status: OrderStatus.ready,
      quantity: 1,
      subtotalAmount: 15000,
      serviceFee: 1000,
      merchantNetAmount: 13500,
    ),
  ];

  static List<OrderRecord> get orderHistory => const [
    OrderRecord(
      id: 'order-2',
      bag: bagKopi,
      code: 'SB-5P1A8',
      dateLabel: '14 Jun',
      amount: 21000,
      status: OrderStatus.done,
      canRate: true,
      subtotalAmount: 20000,
      serviceFee: 1000,
      merchantNetAmount: 18000,
    ),
    OrderRecord(
      id: 'order-3',
      bag: bagRoti,
      code: 'SB-2H7C4',
      dateLabel: '11 Jun',
      amount: 16000,
      status: OrderStatus.done,
      reviewed: true,
      subtotalAmount: 15000,
      serviceFee: 1000,
      merchantNetAmount: 13500,
    ),
    OrderRecord(
      id: 'order-4',
      bag: bagSehat,
      code: 'SB-9X3D2',
      dateLabel: '8 Jun',
      amount: 22000,
      status: OrderStatus.expired,
      subtotalAmount: 22000,
      serviceFee: 0,
    ),
  ];

  static List<AppNotification> get notifications => const [
    AppNotification(
      id: 'notification-1',
      title: 'Pesananmu siap diambil',
      body: 'Roti Nyaman Bakery menunggu sampai 21.00. Tunjukkan QR-mu.',
      time: '5 menit lalu',
      type: NotifType.ready,
      group: 'Hari ini',
      unread: true,
      route: 'orders',
    ),
    AppNotification(
      id: 'notification-2',
      title: 'Bag baru di dekatmu',
      body: 'Kopi Senja baru rilis 6 Surprise Bag, mulai Rp20.000.',
      time: '1 jam lalu',
      type: NotifType.newBag,
      group: 'Hari ini',
    ),
    AppNotification(
      id: 'notification-3',
      title: 'Sudah ambil bag-nya? Beri rating',
      body: 'Bantu pembeli lain dengan ulasanmu untuk Kopi Senja.',
      time: 'Kemarin · 20.40',
      type: NotifType.rating,
      group: 'Kemarin',
      route: 'orders',
    ),
    AppNotification(
      id: 'notification-4',
      title: 'Pembayaran berhasil',
      body: 'Order SB-7K2Q9 · Rp16.000 lunas.',
      time: 'Kemarin · 18.42',
      type: NotifType.payment,
      group: 'Kemarin',
    ),
  ];

  // ───────────── Merchant ─────────────
  static List<MerchantBag> get merchantActiveBags => const [
    MerchantBag(
      id: 'mb1',
      title: 'Surprise Bag Roti & Pastry',
      salePrice: 15000,
      pickupWindow: '20.00–21.00',
      sold: 5,
      total: 8,
      image: img1,
      active: true,
      contents: ['Roti manis', 'Croissant', 'Donat', 'Roti tawar'],
    ),
    MerchantBag(
      id: 'mb3',
      title: 'Surprise Bag Donat',
      salePrice: 16000,
      pickupWindow: '18.00–19.00',
      sold: 2,
      total: 6,
      image: img7,
      active: true,
      contents: ['Donat cokelat', 'Donat gula', 'Donat keju'],
    ),
  ];

  static List<MerchantBag> get merchantInactiveBags => const [
    MerchantBag(
      id: 'mb2',
      title: 'Surprise Bag Pastry Sore',
      salePrice: 18000,
      pickupWindow: '—',
      sold: 8,
      total: 8,
      image: img5,
      active: false,
      statusNote: 'Habis terjual kemarin',
      contents: ['Croissant', 'Danish', 'Roti isi'],
    ),
  ];

  static List<IncomingOrder> get incomingOrders => const [
    IncomingOrder(
      id: 'order-1',
      customer: 'Rani Anggraini',
      initial: 'RA',
      time: '18.42',
      bags: 1,
      code: 'SB-7K2Q9',
      status: IncomingOrderStatus.ready,
      needsAction: false,
      bagTitle: 'Surprise Bag Roti & Pastry',
      bagImage: img1,
      pickupWindow: '20.00–21.00',
      unitPrice: 15000,
      subtotalAmount: 15000,
      serviceFee: 1000,
      merchantNetAmount: 13500,
    ),
    IncomingOrder(
      id: 'order-5',
      customer: 'Budi Santoso',
      initial: 'BS',
      time: '18.20',
      bags: 2,
      code: 'SB-3M8X1',
      status: IncomingOrderStatus.paid,
      bagTitle: 'Surprise Bag Roti & Pastry',
      bagImage: img1,
      pickupWindow: '20.00–21.00',
      unitPrice: 15000,
      subtotalAmount: 30000,
      serviceFee: 1000,
      merchantNetAmount: 27000,
    ),
  ];

  static const merchantBalance = 1245000;

  static List<TxRecord> get transactions => const [
    TxRecord(
      id: 'tx-1',
      title: 'Order SB-7K2Q9',
      subtitle: '17 Jun · komisi Rp1.500',
      amount: 13500,
      kind: TxKind.income,
    ),
    TxRecord(
      id: 'tx-2',
      title: 'Order SB-3M8X1',
      subtitle: '17 Jun · komisi Rp2.000',
      amount: 18000,
      kind: TxKind.income,
    ),
    TxRecord(
      id: 'tx-3',
      title: 'Penarikan ke BCA',
      subtitle: '15 Jun · ••6789',
      amount: 1500000,
      kind: TxKind.withdrawal,
    ),
  ];
}
