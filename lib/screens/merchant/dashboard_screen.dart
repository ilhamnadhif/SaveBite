import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';
import 'merchant_shell.dart';

/// Dashboard merchant dengan statistik dan order aktual dari backend.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final isOpen = _storeIsOpen();
          return Column(
            children: [
              ColoredHeader(
                background: AppColors.brown,
                bottomPadding: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Halo,',
                                style: AppText.ui(
                                  13,
                                  color: AppColors.merchantMuted,
                                ),
                              ),
                              Text(
                                appState.storeName.isEmpty
                                    ? 'Toko Anda'
                                    : appState.storeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.display(
                                  20,
                                  weight: 700,
                                  color: AppColors.cream,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        StatusBadge(
                          text: isOpen ? '● Buka' : '● Tutup',
                          background: isOpen
                              ? AppColors.greenBright
                              : AppColors.scanMuted,
                          foreground: AppColors.white,
                          weight: 800,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Jam toko ${appState.openTime}–${appState.closeTime}',
                      style: AppText.ui(11.5, color: AppColors.merchantMuted),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _statTile(
                            '${appState.bagsSoldToday}',
                            'Bag hari ini',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            formatRupiah(appState.incomeToday),
                            'Pendapatan',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statTile(
                            '${appState.activeBagCount}',
                            'Bag aktif',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: AppColors.cream,
                  child: RefreshIndicator(
                    color: AppColors.terracotta,
                    onRefresh: appState.loadMerchantData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                      children: [
                        if (appState.errorMessage != null) ...[
                          _errorCard(appState.errorMessage!),
                          const SizedBox(height: 14),
                        ],
                        if (appState.isLoadingMerchant &&
                            appState.activeBags.isEmpty &&
                            appState.pendingOrders.isEmpty) ...[
                          const LinearProgressIndicator(
                            color: AppColors.terracotta,
                            backgroundColor: AppColors.terracottaSoftBg,
                          ),
                          const SizedBox(height: 14),
                        ],
                        PrimaryButton.merchant(
                          label: 'Buat Surprise Bag',
                          height: 56,
                          icon: const Icon(
                            Icons.add,
                            color: AppColors.white,
                            size: 20,
                          ),
                          onTap: () => AppNav.toCreateBag(context),
                        ),
                        const SizedBox(height: 20),
                        SectionHeading(
                          title: 'Bag aktif (${appState.activeBagCount})',
                          actionLabel: 'Kelola',
                          actionColor: AppColors.terracotta,
                          onAction: () =>
                              MerchantShellScope.of(context)?.selectTab(1),
                        ),
                        const SizedBox(height: 11),
                        _activeBags(context),
                        const SizedBox(height: 20),
                        SectionHeading(
                          title: 'Pesanan aktif',
                          actionLabel: appState.pendingOrders.isEmpty
                              ? null
                              : 'Lihat semua',
                          actionColor: AppColors.terracotta,
                          onAction: () =>
                              MerchantShellScope.of(context)?.selectTab(2),
                        ),
                        const SizedBox(height: 11),
                        _latestOrders(context),
                        const SizedBox(height: 20),
                        _impactCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Container(
      constraints: const BoxConstraints(minHeight: 77),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brownCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.display(20, weight: 800, color: AppColors.white),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            style: AppText.ui(10.5, color: AppColors.merchantMuted),
          ),
        ],
      ),
    );
  }

  Widget _activeBags(BuildContext context) {
    final bags = appState.activeBags;
    if (bags.isEmpty) {
      return EmptyState(
        icon: Icons.shopping_bag_outlined,
        title: 'Belum ada bag aktif',
        message: 'Buat Surprise Bag untuk mulai berjualan.',
        action: SizedBox(
          width: 210,
          child: PrimaryButton.merchant(
            label: 'Buat bag pertama',
            height: 46,
            fontSize: 14,
            onTap: () => AppNav.toCreateBag(context),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < bags.take(3).length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _activeBagCard(context, bags[i]),
        ],
      ],
    );
  }

  Widget _activeBagCard(BuildContext context, MerchantBag bag) {
    final stock = bag.quantityLeft < 0 ? 0 : bag.quantityLeft;
    return AppCard(
      radius: 18,
      onTap: () => AppNav.toEditBag(context, bag),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: FoodImage(bag.image, width: 56, height: 56),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        bag.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui(
                          14,
                          weight: 700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge.available('$stock tersisa'),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatRupiah(bag.salePrice)} · ${bag.pickupWindow}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.ui(12, color: AppColors.body),
                ),
                const SizedBox(height: 8),
                ProgressBar(
                  fraction: bag.total == 0
                      ? 0
                      : (bag.sold / bag.total).clamp(0, 1).toDouble(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _latestOrders(BuildContext context) {
    final orders = appState.pendingOrders;
    if (orders.isEmpty) {
      return AppCard(
        radius: 16,
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Belum ada pesanan aktif.',
                style: AppText.ui(12.5, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < orders.take(3).length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _orderCard(context, orders[i]),
        ],
      ],
    );
  }

  Widget _orderCard(BuildContext context, IncomingOrder order) {
    return AppCard(
      radius: 14,
      onTap: () => AppNav.toOrderDetail(context, order),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.greenSoftBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              order.initial,
              style: AppText.ui(13, weight: 800, color: AppColors.greenAccent),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.customer} · ${order.bags} bag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.ui(13.5, weight: 700, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  order.bagTitle.isEmpty ? 'Surprise Bag' : order.bagTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.ui(12, color: AppColors.body),
                ),
                const SizedBox(height: 2),
                Text(
                  order.time,
                  style: AppText.ui(11.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _orderStatus(order.status),
        ],
      ),
    );
  }

  Widget _orderStatus(IncomingOrderStatus status) {
    return switch (status) {
      IncomingOrderStatus.pending => StatusBadge.waiting('Menunggu bayar'),
      IncomingOrderStatus.paid => StatusBadge(
        text: 'Baru',
        background: AppColors.terracottaSoftBg,
        foreground: AppColors.brown,
      ),
      IncomingOrderStatus.preparing => StatusBadge(
        text: 'Disiapkan',
        background: AppColors.terracottaSoftBg,
        foreground: AppColors.brown,
      ),
      IncomingOrderStatus.ready => StatusBadge.available('Siap'),
      IncomingOrderStatus.redeemed => StatusBadge.done('Selesai'),
      IncomingOrderStatus.cancelled => StatusBadge.expired('Batal'),
      IncomingOrderStatus.expired => StatusBadge.expired('Kedaluwarsa'),
    };
  }

  Widget _impactCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenSoftBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.greenBright.withAlpha(45)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.greenBright,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.eco_outlined, color: AppColors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${appState.foodSavedKg.toStringAsFixed(1)} kg makanan terselamatkan',
                  style: AppText.ui(
                    13.5,
                    weight: 800,
                    color: AppColors.greenAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Dihitung dari pesanan yang sudah selesai.',
                  style: AppText.ui(11.5, color: AppColors.body),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.dangerTintBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: AppText.ui(12.5, color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: appState.loadMerchantData,
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }

  bool _storeIsOpen() {
    int? toMinutes(String value) {
      final parts = value.trim().split(RegExp(r'[:.]'));
      if (parts.length != 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null || hour > 23 || minute > 59) {
        return null;
      }
      return hour * 60 + minute;
    }

    final open = toMinutes(appState.openTime);
    final close = toMinutes(appState.closeTime);
    if (open == null || close == null) return false;
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    if (open == close) return true;
    if (open < close) return current >= open && current < close;
    return current >= open || current < close;
  }
}
