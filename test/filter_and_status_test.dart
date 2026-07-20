import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/mappers.dart';
import 'package:savebite/data/models.dart';

void main() {
  group('BagFilter', () {
    test('copyWith mempertahankan dan dapat membersihkan setiap kriteria', () {
      const initial = BagFilter(
        categories: {'Bakery'},
        maxDistanceKm: 2,
        minPrice: 10000,
        maxPrice: 25000,
        pickupAfter: TimeOfDay(hour: 17, minute: 0),
        pickupBefore: TimeOfDay(hour: 21, minute: 0),
      );

      expect(initial.isEmpty, isFalse);
      final cleared = initial.copyWith(
        categories: const {},
        clearMaxDistance: true,
        clearMinPrice: true,
        clearMaxPrice: true,
        clearPickupAfter: true,
        clearPickupBefore: true,
      );

      expect(cleared.isEmpty, isTrue);
      expect(cleared.categories, isEmpty);
      expect(cleared.maxDistanceKm, isNull);
      expect(cleared.minPrice, isNull);
      expect(cleared.maxPrice, isNull);
      expect(cleared.pickupAfter, isNull);
      expect(cleared.pickupBefore, isNull);
    });

    test(
      'FakeBackend menerapkan kategori, harga, dan jarak bersama-sama',
      () async {
        final backend = FakeBackend();
        const filter = BagFilter(
          categories: {'Kafe'},
          maxDistanceKm: 1,
          minPrice: 15000,
          maxPrice: 21000,
        );

        final results = await backend.nearbyBags(
          latitude: -6.3725,
          longitude: 106.8323,
          filter: filter,
        );

        expect(results, hasLength(1));
        expect(results.single.merchant.category, 'Kafe');
        expect(results.single.salePrice, inInclusiveRange(15000, 21000));
      },
    );

    test(
      'aturan pickup memakai irisan window dan menolak data tak diketahui',
      () {
        final merchant = Merchant(
          id: 'm-filter',
          name: 'Toko Filter',
          initial: 'TF',
          avatarColor: Colors.green,
          category: 'Bakery',
          rating: 4.5,
          reviewCount: 1,
          distance: '1.2 km',
          address: 'Depok',
          hours: '08.00–21.00',
          coverImage: '',
          bagsSaved: 1,
        );
        Bag bag(String window) => Bag(
          id: 'bag-$window',
          merchant: merchant,
          title: 'Bag',
          description: 'Isi',
          originalPrice: 30000,
          salePrice: 10000,
          quantityLeft: 1,
          quantityTotal: 1,
          pickupWindow: window,
          image: '',
        );
        const filter = BagFilter(
          pickupAfter: TimeOfDay(hour: 18, minute: 0),
          pickupBefore: TimeOfDay(hour: 20, minute: 0),
        );

        expect(bagMatchesFilter(bag('17.30–18.30'), filter), isTrue);
        expect(bagMatchesFilter(bag('20.30–21.00'), filter), isFalse);
        expect(bagMatchesFilter(bag('jadwal menyusul'), filter), isFalse);
      },
    );
  });

  test('status cancelled dipetakan terpisah dari expired dan redeemed', () {
    Map<String, dynamic> row(String status) => {
      'id': 'order-$status',
      'status': status,
      'order_reference': 'SB-$status',
      'quantity': 1,
      'subtotal_amount': 15000,
      'service_fee': 1000,
      'total_amount': 16000,
      'surprise_bags': {
        'id': 'bag-1',
        'title': 'Surprise Bag',
        'sale_price': 15000,
        'original_price': 45000,
        'quantity_left': 1,
        'quantity_total': 2,
        'pickup_window': '20.00–21.00',
        'merchants': {
          'id': 'merchant-1',
          'store_name': 'Toko Uji',
          'category': 'Bakery',
        },
      },
    };

    final cancelled = orderRecordFromMap(row('cancelled'));
    final expired = orderRecordFromMap(row('expired'));
    final redeemed = orderRecordFromMap(row('redeemed'));

    expect(cancelled.status, OrderStatus.cancelled);
    expect(expired.status, OrderStatus.expired);
    expect(redeemed.status, OrderStatus.done);
    expect(cancelled.status, isNot(expired.status));
    expect(cancelled.status, isNot(redeemed.status));
    expect(cancelled.canRate, isFalse);
  });

  test('status pembayaran Midtrans tidak pernah jatuh ke siap/paid', () {
    Map<String, dynamic> row(String paymentStatus) => {
      'id': 'order-$paymentStatus',
      'status': paymentStatus == 'settlement' ? 'paid' : 'pending',
      'payment_status': paymentStatus,
      'order_reference': 'SB-${paymentStatus.toUpperCase()}',
      'quantity': 1,
      'subtotal': 15000,
      'service_fee': 1000,
      'total_amount': 16000,
      'bag_id': 'bag-1',
      'bag_title': 'Surprise Bag',
      'unit_price': 15000,
      'original_price_snapshot': 45000,
      'merchant_id': 'merchant-1',
      'merchant_name': 'Toko Uji',
    };

    expect(
      orderRecordFromMap(row('pending')).paymentState,
      PaymentState.pending,
    );
    expect(
      orderRecordFromMap(row('settlement')).paymentState,
      PaymentState.paid,
    );
    final captureChallenge = row('capture')..['fraud_status'] = 'challenge';
    final captureAccepted = row('capture')..['fraud_status'] = 'accept';
    expect(
      orderRecordFromMap(captureChallenge).paymentState,
      PaymentState.pending,
    );
    expect(orderRecordFromMap(captureAccepted).paymentState, PaymentState.paid);
    expect(orderRecordFromMap(row('deny')).paymentState, PaymentState.failed);
    expect(
      orderRecordFromMap(row('refund')).paymentState,
      PaymentState.refunded,
    );
    expect(
      orderRecordFromMap(row('chargeback')).paymentState,
      PaymentState.disputed,
    );
    expect(
      orderRecordFromMap(row('partial_refund')).paymentState,
      PaymentState.disputed,
    );
    expect(orderRecordFromMap(row('refund')).status, OrderStatus.pending);
    expect(orderRecordFromMap(row('chargeback')).paymentState.isPaid, isFalse);

    final unknownProviderState = row('future_provider_status')
      ..['status'] = 'ready'
      ..['paid_at'] = '2026-07-19T08:00:00Z';
    expect(
      orderRecordFromMap(unknownProviderState).paymentState,
      PaymentState.awaitingPayment,
    );

    final verifiedLegacy = row('')
      ..['status'] = 'paid'
      ..['paid_at'] = '2026-07-19T08:00:00Z';
    expect(orderRecordFromMap(verifiedLegacy).paymentState, PaymentState.paid);
  });

  test('status merchant yang tidak dikenal tidak dianggap sudah dibayar', () {
    final unknown = incomingOrderFromMap({
      'id': 'order-unknown',
      'status': 'future_status',
      'consumer_name': 'Nadia',
      'quantity': 1,
    });

    expect(unknown.status, IncomingOrderStatus.pending);
    expect(unknown.needsAction, isFalse);
  });

  test('notifikasi diarahkan ke ekosistem pemilik yang tepat', () {
    AppNotification notification(String entity, String title) =>
        notificationFromMap({
          'id': '$entity-$title',
          'entity_type': entity,
          'title': title,
          'body': 'Uji',
          'type': 'order',
          'group_label': 'Hari ini',
          'read': false,
          'created_at': DateTime.now().toIso8601String(),
        });

    expect(notification('order', 'Pesanan baru').route, 'merchant_orders');
    expect(notification('order', 'Pesanan siap').route, 'orders');
    expect(notification('review', 'Ulasan baru').route, 'merchant_reviews');
    expect(
      notification('payout', 'Penarikan diproses').route,
      'merchant_balance',
    );
    expect(
      notification('bank_account', 'Rekening terverifikasi').route,
      'merchant_balance',
    );
    expect(notification('bag', 'Surprise Bag baru').route, 'consumer_home');
  });

  test('ulasan merchant memetakan identitas aman dan rincian pesanan', () {
    final review = merchantReviewFromMap({
      'review_id': 'review-1',
      'order_id': 'order-1',
      'order_reference': 'SB-ABC12345',
      'customer_name': 'Nadia Putri',
      'rating': 5,
      'tags': ['Masih fresh', 'Porsi banyak'],
      'comment': 'Bag sesuai deskripsi.',
      'created_at': '2026-07-13T08:00:00Z',
    });

    expect(review.id, 'review-1');
    expect(review.orderId, 'order-1');
    expect(review.orderReference, 'SB-ABC12345');
    expect(review.customerName, 'Nadia Putri');
    expect(review.customerInitial, 'NP');
    expect(review.rating, 5);
    expect(review.tags, hasLength(2));
    expect(review.comment, 'Bag sesuai deskripsi.');
    expect(review.createdAt, isNotNull);
  });

  test('bag merchant memetakan perkiraan isi dari database', () {
    final bag = merchantBagFromMap({
      'id': 'bag-merchant-1',
      'title': 'Surprise Bag Roti',
      'sale_price': 15000,
      'original_price': 45000,
      'quantity_total': 5,
      'quantity_left': 3,
      'pickup_window': '20.00–21.00',
      'status': 'active',
      'contents': ['Roti manis', 'Croissant'],
    });

    expect(bag.contents, ['Roti manis', 'Croissant']);
    expect(bag.copyWith().contents, bag.contents);
  });
}
