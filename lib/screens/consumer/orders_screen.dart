import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';

/// Daftar pesanan konsumen dengan pemisahan status aktif dan riwayat.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  int _tab = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loading = appState.activeOrders.isEmpty && appState.orderHistory.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (mounted &&
        !_loading &&
        appState.activeOrders.isEmpty &&
        appState.orderHistory.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      await appState.loadOrders();
      if (!mounted) return;
      setState(() => _error = appState.ordersError);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pesanan gagal dimuat. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasExpired(OrderRecord order) {
    if (order.paymentState == PaymentState.expired) return true;
    final expiresAt = order.paymentState.isAwaitingCustomer
        ? order.paymentExpiresAt
        : order.expiresAt;
    return expiresAt != null && !expiresAt.isAfter(DateTime.now());
  }

  List<OrderRecord> get _activeOrders => appState.activeOrders
      .where(
        (order) =>
            (order.status == OrderStatus.pending ||
                order.status == OrderStatus.ready) &&
            !order.paymentState.isTerminalFailure &&
            !_hasExpired(order),
      )
      .toList(growable: false);

  List<OrderRecord> get _historyOrders {
    final result = <OrderRecord>[...appState.orderHistory];
    final ids = result
        .map((order) => order.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final order in appState.activeOrders.where(
      (order) => _hasExpired(order) || order.paymentState.isTerminalFailure,
    )) {
      if (order.id.isEmpty || ids.add(order.id)) result.add(order);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => Column(
          children: [
            _header(context),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 12,
        20,
        12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pesanan',
            style: AppText.display(24, weight: 800, color: AppColors.ink),
          ),
          const SizedBox(height: 14),
          TabSwitch(
            tabs: const ['Aktif', 'Riwayat'],
            index: _tab,
            onTap: (index) => setState(() => _tab = index),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading &&
        appState.activeOrders.isEmpty &&
        appState.orderHistory.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.greenBright),
      );
    }

    final orders = _tab == 0 ? _activeOrders : _historyOrders;
    return RefreshIndicator(
      color: AppColors.greenBright,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!, onRetry: _refresh),
            const SizedBox(height: 14),
          ],
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 72),
              child: EmptyState(
                icon: _tab == 0
                    ? Icons.shopping_bag_outlined
                    : Icons.receipt_long_outlined,
                title: _tab == 0
                    ? 'Belum ada pesanan aktif'
                    : 'Belum ada riwayat pesanan',
                message: _tab == 0
                    ? 'Pesanan yang sedang berjalan akan muncul di sini.'
                    : 'Pesanan selesai, dibatalkan, atau kedaluwarsa akan muncul di sini.',
              ),
            )
          else if (_tab == 0)
            for (final order in orders) _activeCard(context, order)
          else
            for (final order in orders) _historyCard(context, order),
        ],
      ),
    );
  }

  Widget _activeCard(BuildContext context, OrderRecord order) {
    final ready = order.status == OrderStatus.ready;
    final awaitingPayment = order.paymentState.isAwaitingCustomer;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.greenSoftBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StoreAvatar(
                initial: order.bag.merchant.initial,
                color: order.bag.merchant.avatarColor,
                size: 40,
                radius: 11,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.bag.merchant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(14, weight: 700, color: AppColors.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${order.quantity}× ${order.bag.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(12, color: AppColors.body),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ready
                  ? StatusBadge.available('Siap diambil')
                  : awaitingPayment
                  ? StatusBadge.waiting('Menunggu bayar')
                  : StatusBadge.waiting('Diproses'),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              const Icon(
                Icons.confirmation_number_outlined,
                size: 15,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                'Pesanan ${order.code}',
                style: AppText.ui(11.5, color: AppColors.muted),
              ),
              const Spacer(),
              Text(
                formatRupiah(order.amount),
                style: AppText.ui(12, weight: 700, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ready)
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Tampilkan QR pickup',
                height: 44,
                fontSize: 14,
                onTap: () => AppNav.toVoucher(context, order),
              ),
            )
          else if (awaitingPayment)
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Lanjutkan pembayaran',
                height: 44,
                fontSize: 14,
                onTap: () => AppNav.toResumePayment(context, order),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.neutralChip,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Pembayaran sudah diterima. QR tersedia setelah pesanan siap.',
                textAlign: TextAlign.center,
                style: AppText.ui(12, color: AppColors.body),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyCard(BuildContext context, OrderRecord order) {
    final expired = order.status == OrderStatus.expired || _hasExpired(order);
    final cancelled = order.status == OrderStatus.cancelled;
    Widget card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FoodImage(
              order.bag.image,
              width: 46,
              height: 46,
              saturation: expired || cancelled ? 0.5 : 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.bag.merchant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.ui(14, weight: 700, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.dateLabel} · ${formatRupiah(order.amount)}',
                  style: AppText.ui(12, color: AppColors.body),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _historyTrailing(context, order, expired: expired),
        ],
      ),
    );
    if (expired || cancelled) card = Opacity(opacity: 0.76, child: card);
    return card;
  }

  Widget _historyTrailing(
    BuildContext context,
    OrderRecord order, {
    required bool expired,
  }) {
    if (order.paymentState == PaymentState.refunded) {
      return StatusBadge.expired('Dikembalikan');
    }
    if (order.paymentState == PaymentState.disputed) {
      return StatusBadge.expired('Ditinjau');
    }
    if (order.paymentState == PaymentState.failed) {
      return StatusBadge.expired('Gagal bayar');
    }
    if (order.paymentState == PaymentState.cancelled) {
      return StatusBadge.expired('Dibatalkan');
    }
    if (order.paymentState == PaymentState.expired) {
      return StatusBadge.expired('Kedaluwarsa');
    }
    if (order.status == OrderStatus.cancelled) {
      return StatusBadge.expired('Dibatalkan');
    }
    if (expired) return StatusBadge.expired('Kedaluwarsa');
    if (order.status == OrderStatus.pending ||
        order.status == OrderStatus.ready) {
      return StatusBadge.waiting('Diproses');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        StatusBadge.done('Selesai'),
        const SizedBox(height: 6),
        if (order.canRate)
          InkWell(
            onTap: () => AppNav.toRating(context, order: order),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Text(
                '★ Beri rating',
                style: AppText.ui(12, weight: 700, color: AppColors.amber),
              ),
            ),
          )
        else if (order.reviewed)
          Text(
            'Sudah diulas',
            style: AppText.ui(12, weight: 600, color: AppColors.muted),
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppText.ui(12.5, color: AppColors.body, height: 1.4),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Coba lagi',
              style: AppText.ui(12.5, weight: 700, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
