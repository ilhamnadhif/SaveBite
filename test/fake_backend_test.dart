import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/data/backend/backend.dart';
import 'package:savebite/data/backend/fake_backend.dart';
import 'package:savebite/data/models.dart';
import 'package:savebite/data/sample_data.dart';

Matcher _backendError(String code) =>
    isA<BackendException>().having((error) => error.code, 'code', code);

void main() {
  group('FakeBackend checkout', () {
    late FakeBackend backend;

    setUp(() => backend = FakeBackend());

    test(
      'idempotency tidak menduplikasi order atau mengurangi stok dua kali',
      () async {
        final before = await backend.activeOrders();

        final first = await backend.placeOrder(
          SampleData.bagRoti,
          2,
          'GoPay',
          idempotencyKey: 'checkout-same-request',
        );
        final retry = await backend.placeOrder(
          SampleData.bagRoti,
          2,
          'GoPay',
          idempotencyKey: 'checkout-same-request',
        );

        expect(retry.id, first.id);
        final orders = await backend.activeOrders();
        expect(orders.length, before.length + 1);
        expect(orders.where((order) => order.id == first.id), hasLength(1));

        final refreshedBag = (await backend.nearbyBags()).singleWhere(
          (bag) => bag.id == SampleData.bagRoti.id,
        );
        expect(refreshedBag.quantityLeft, 1);
      },
    );

    test('jumlah nol, negatif, melebihi stok, dan sold out ditolak', () async {
      for (final quantity in [0, -1, SampleData.bagRoti.quantityLeft + 1]) {
        await expectLater(
          backend.placeOrder(
            SampleData.bagRoti,
            quantity,
            'GoPay',
            idempotencyKey: 'invalid-$quantity',
          ),
          throwsA(
            quantity <= 0
                ? _backendError('invalid_quantity')
                : _backendError('insufficient_stock'),
          ),
        );
      }

      await expectLater(
        backend.placeOrder(
          SampleData.bagDonat,
          1,
          'GoPay',
          idempotencyKey: 'sold-out',
        ),
        throwsA(_backendError('insufficient_stock')),
      );
    });

    test(
      'subtotal, biaya layanan, dan total memakai satu sumber hitung',
      () async {
        final order = await backend.placeOrder(
          SampleData.bagKopi,
          2,
          'OVO',
          idempotencyKey: 'fee-calculation',
        );

        expect(order.quantity, 2);
        expect(order.subtotalAmount, SampleData.bagKopi.salePrice * 2);
        expect(order.serviceFee, 1000);
        expect(order.amount, order.subtotalAmount + order.serviceFee);
        expect(order.paymentMethod, 'OVO');
      },
    );
  });

  group('pickup token', () {
    test(
      'referensi publik tidak dapat redeem; token hanya berlaku sekali',
      () async {
        final backend = FakeBackend();
        final placed = await backend.placeOrder(
          SampleData.bagKopi,
          1,
          'GoPay',
          idempotencyKey: 'pickup-order',
        );
        await backend.markOrderReady(placed.id);
        final ready = (await backend.activeOrders()).singleWhere(
          (order) => order.id == placed.id,
        );
        final issued = await backend.issuePickupToken(ready);

        expect(await backend.redeemOrder(issued.code), isNull);
        expect(issued.pickupToken, isNotNull);

        final redeemed = await backend.redeemOrder(issued.pickupToken!);
        expect(redeemed, isNotNull);
        expect(redeemed!.status, IncomingOrderStatus.redeemed);
        expect(await backend.redeemOrder(issued.pickupToken!), isNull);
      },
    );
  });

  group('pembatalan merchant', () {
    test(
      'mengembalikan stok tepat sekali dan memindahkan order konsumen',
      () async {
        final backend = FakeBackend();
        final placed = await backend.placeOrder(
          SampleData.bagRoti,
          2,
          'GoPay',
          idempotencyKey: 'cancel-order-once',
        );
        await backend.markOrderReady(placed.id);

        expect(
          (await backend.nearbyBags())
              .singleWhere((bag) => bag.id == SampleData.bagRoti.id)
              .quantityLeft,
          1,
        );

        final cancelled = await backend.cancelMerchantOrder(placed.id);
        expect(cancelled.status, IncomingOrderStatus.cancelled);
        expect(
          (await backend.orderHistory())
              .singleWhere((order) => order.id == placed.id)
              .status,
          OrderStatus.cancelled,
        );
        expect(
          (await backend.activeOrders()).where(
            (order) => order.id == placed.id,
          ),
          isEmpty,
        );
        expect(
          (await backend.nearbyBags())
              .singleWhere((bag) => bag.id == SampleData.bagRoti.id)
              .quantityLeft,
          SampleData.bagRoti.quantityLeft,
        );

        final retry = await backend.cancelMerchantOrder(placed.id);
        expect(retry.status, IncomingOrderStatus.cancelled);
        expect(
          (await backend.nearbyBags())
              .singleWhere((bag) => bag.id == SampleData.bagRoti.id)
              .quantityLeft,
          SampleData.bagRoti.quantityLeft,
        );
      },
    );

    test('order redeemed tidak dapat dibatalkan', () async {
      final backend = FakeBackend();
      final placed = await backend.placeOrder(
        SampleData.bagKopi,
        1,
        'GoPay',
        idempotencyKey: 'cancel-after-redeem',
      );
      await backend.markOrderReady(placed.id);
      final ready = (await backend.activeOrders()).singleWhere(
        (order) => order.id == placed.id,
      );
      final tokenized = await backend.issuePickupToken(ready);
      await backend.redeemOrder(tokenized.pickupToken!);

      await expectLater(
        backend.cancelMerchantOrder(placed.id),
        throwsA(_backendError('invalid_order_status')),
      );
    });
  });

  group('ulasan terikat pesanan', () {
    test(
      'hanya order redeemed milik pengguna dan belum diulas yang diterima',
      () async {
        final backend = FakeBackend();
        final reviewsBefore = await backend.merchantReviews();
        final history = await backend.orderHistory();
        final redeemed = history.singleWhere(
          (order) => order.status == OrderStatus.done && !order.reviewed,
        );
        final active = (await backend.activeOrders()).first;
        final unknown = OrderRecord(
          id: 'order-not-owned',
          bag: SampleData.bagRoti,
          code: 'SB-NOT-OWNED',
          dateLabel: 'Hari ini',
          amount: 16000,
          status: OrderStatus.done,
        );

        await expectLater(
          backend.submitReview(active, 5, const [], ''),
          throwsA(_backendError('order_not_redeemed')),
        );
        await expectLater(
          backend.submitReview(unknown, 5, const [], ''),
          throwsA(_backendError('order_not_redeemed')),
        );

        await backend.submitReview(redeemed, 5, const [
          'Masih fresh',
        ], 'Bag sesuai deskripsi.');
        final reviewsAfter = await backend.merchantReviews();
        expect(reviewsAfter, hasLength(reviewsBefore.length + 1));
        expect(reviewsAfter.first.orderReference, redeemed.code);
        expect(reviewsAfter.first.rating, 5);
        expect(reviewsAfter.first.tags, contains('Masih fresh'));
        expect(reviewsAfter.first.comment, 'Bag sesuai deskripsi.');
        await expectLater(
          backend.submitReview(redeemed, 4, const [], ''),
          throwsA(_backendError('already_reviewed')),
        );
      },
    );
  });

  group('payout manual aman', () {
    test(
      'memvalidasi minimum, saldo, rekening terverifikasi, dan idempotency',
      () async {
        final backend = FakeBackend();
        final startingBalance = await backend.balance();
        final verified = (await backend.bankAccounts()).singleWhere(
          (account) => account.verified,
        );

        await expectLater(
          backend.requestPayout(
            amount: 49999,
            bankAccountId: verified.id,
            idempotencyKey: 'below-minimum',
          ),
          throwsA(_backendError('minimum_payout')),
        );
        await expectLater(
          backend.requestPayout(
            amount: startingBalance + 1,
            bankAccountId: verified.id,
            idempotencyKey: 'above-balance',
          ),
          throwsA(_backendError('insufficient_balance')),
        );

        final unverified = await backend.saveBankAccount(
          bankCode: 'BNI',
          bankName: 'BNI',
          accountNumber: '1234567890',
          accountHolder: 'Ilham Hidayat',
          idempotencyKey: 'new-bank',
        );
        expect(unverified.verified, isFalse);
        await expectLater(
          backend.requestPayout(
            amount: 50000,
            bankAccountId: unverified.id,
            idempotencyKey: 'unverified-bank',
          ),
          throwsA(_backendError('bank_not_verified')),
        );

        final first = await backend.requestPayout(
          amount: 100000,
          bankAccountId: verified.id,
          idempotencyKey: 'same-payout',
        );
        final retry = await backend.requestPayout(
          amount: 100000,
          bankAccountId: verified.id,
          idempotencyKey: 'same-payout',
        );

        expect(retry.id, first.id);
        expect(first.status, PayoutStatus.pending);
        expect(first.feeAmount, 2500);
        expect(first.netAmount, first.grossAmount - first.feeAmount);
        expect(await backend.balance(), startingBalance - 100000);
        expect(await backend.payoutRequests(), hasLength(1));
      },
    );
  });

  test('duplikat bag memindahkan tanggal dan window pickup ke besok', () async {
    final backend = FakeBackend();
    final now = DateTime.now();
    final available = DateTime(now.year, now.month, now.day);
    final startsAt = DateTime(now.year, now.month, now.day, 19, 30);
    final endsAt = DateTime(now.year, now.month, now.day, 21);
    await backend.addBag(
      title: 'Bag untuk diduplikat',
      salePrice: 15000,
      pickupWindow: '19.30–21.00',
      total: 4,
      description: 'Stok uji',
      contents: const ['Croissant', 'Danish'],
      originalPrice: 45000,
      availableOn: available,
      pickupStartsAt: startsAt,
      pickupEndsAt: endsAt,
    );
    final source = (await backend.myBags()).first;

    await backend.duplicateBag(source);
    final duplicate = (await backend.myBags()).first;
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    expect(duplicate.id, isNot(source.id));
    expect(duplicate.availableOn?.year, tomorrow.year);
    expect(duplicate.availableOn?.month, tomorrow.month);
    expect(duplicate.availableOn?.day, tomorrow.day);
    expect(duplicate.pickupStartsAt?.hour, startsAt.hour);
    expect(duplicate.pickupStartsAt?.minute, startsAt.minute);
    expect(duplicate.pickupEndsAt?.hour, endsAt.hour);
    expect(duplicate.sold, 0);
    expect(duplicate.quantityLeft, source.total);
    expect(duplicate.active, isTrue);
    expect(duplicate.contents, source.contents);
  });

  group('perkiraan isi bag', () {
    test('parser menerima koma/baris baru dan menghapus duplikat', () {
      final parsed = parseBagContents(
        ' Roti manis, Croissant\nroti MANIS; Donat ',
      );

      expect(parsed, ['Roti manis', 'Croissant', 'Donat']);
      expect(bagContentsValidationError(parsed), isNull);
      expect(
        bagContentsValidationError(
          List.generate(21, (index) => 'Item ${index + 1}'),
        ),
        'Maksimal 20 item',
      );
      expect(
        bagContentsValidationError([List.filled(81, 'x').join()]),
        'Setiap item maksimal 80 karakter',
      );
    });

    test('create dan edit menyimpan daftar isi yang dinormalisasi', () async {
      final backend = FakeBackend();
      await backend.addBag(
        title: 'Bag Isi Uji',
        salePrice: 15000,
        pickupWindow: '19.00–20.00',
        total: 3,
        description: 'Deskripsi isi untuk pengujian.',
        contents: const [' Roti ', 'roti', 'Donat'],
        originalPrice: 45000,
      );
      final created = (await backend.myBags()).first;
      expect(created.contents, ['Roti', 'Donat']);

      await backend.updateBag(
        created,
        title: created.title,
        salePrice: created.salePrice,
        pickupWindow: created.pickupWindow,
        total: created.total,
        description: created.description,
        contents: const ['Croissant', 'Kopi susu'],
        originalPrice: created.originalPrice,
      );
      final updated = (await backend.myBags()).first;
      expect(updated.contents, ['Croissant', 'Kopi susu']);
    });

    test(
      'backend demo menolak lebih dari 20 item atau item terlalu panjang',
      () async {
        final backend = FakeBackend();

        Future<void> add(List<String> contents) => backend.addBag(
          title: 'Bag Isi Invalid',
          salePrice: 15000,
          pickupWindow: '19.00–20.00',
          total: 3,
          description: 'Deskripsi isi untuk pengujian.',
          contents: contents,
          originalPrice: 45000,
        );

        await expectLater(
          add(List.generate(21, (index) => 'Item ${index + 1}')),
          throwsA(_backendError('invalid_bag_contents')),
        );
        await expectLater(
          add([List.filled(81, 'x').join()]),
          throwsA(_backendError('invalid_bag_contents')),
        );
      },
    );
  });

  test('hapus akun membersihkan seluruh data milik sesi demo', () async {
    final backend = FakeBackend();
    await backend.upsertStore(
      name: 'Toko Uji',
      category: 'Bakery',
      address: 'Jl. Pengujian No. 1',
      open: '08.00',
      close: '20.00',
    );

    await backend.deleteAccount();

    expect(await backend.myStore(), isNull);
    expect(await backend.myBags(), isEmpty);
    expect(await backend.activeOrders(), isEmpty);
    expect(await backend.orderHistory(), isEmpty);
    expect(await backend.incomingOrders(), isEmpty);
    expect(await backend.transactions(), isEmpty);
    expect(await backend.bankAccounts(), isEmpty);
    expect(await backend.balance(), 0);
    expect((await backend.currentProfile())?.name, 'Pengguna');
  });
}
