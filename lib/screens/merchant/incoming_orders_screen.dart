import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';
import '../../services/notification_route.dart';

/// Daftar operasional order merchant. Pickup token tidak pernah ditampilkan;
/// redeem hanya dilakukan dari scanner QR.
class IncomingOrdersScreen extends StatefulWidget {
  const IncomingOrdersScreen({
    super.key,
    this.initialTab = MerchantOrdersTab.active,
    this.referencedOrderId,
  });

  final MerchantOrdersTab initialTab;
  final String? referencedOrderId;

  @override
  State<IncomingOrdersScreen> createState() => _IncomingOrdersScreenState();
}

class _IncomingOrdersScreenState extends State<IncomingOrdersScreen> {
  late int _tab;
  late bool _referenceTabResolved;
  final Set<String> _busyOrderKeys = {};

  @override
  void initState() {
    super.initState();
    final referencedTab = _tabForReferencedOrder();
    _tab = (referencedTab ?? widget.initialTab).index;
    _referenceTabResolved =
        widget.referencedOrderId?.trim().isEmpty != false ||
        referencedTab != null;
    appState.addListener(_resolveReferencedOrder);
  }

  @override
  void dispose() {
    appState.removeListener(_resolveReferencedOrder);
    super.dispose();
  }

  void _resolveReferencedOrder() {
    if (_referenceTabResolved || !mounted) return;
    final referencedTab = _tabForReferencedOrder();
    if (referencedTab == null) return;
    setState(() {
      _tab = referencedTab.index;
      _referenceTabResolved = true;
    });
  }

  MerchantOrdersTab? _tabForReferencedOrder() {
    final targetId = widget.referencedOrderId?.trim().toLowerCase();
    if (targetId == null || targetId.isEmpty) return null;
    bool matches(IncomingOrder order) => order.id.toLowerCase() == targetId;
    if (appState.completedOrders.any(matches)) return MerchantOrdersTab.closed;
    if (appState.pendingOrders.any(matches)) return MerchantOrdersTab.active;
    return null;
  }

  List<IncomingOrder> _prioritizeReferenced(List<IncomingOrder> orders) {
    final targetId = widget.referencedOrderId?.trim().toLowerCase();
    if (targetId == null || targetId.isEmpty) return orders;
    final index = orders.indexWhere(
      (order) => order.id.toLowerCase() == targetId,
    );
    if (index <= 0) return orders;
    return <IncomingOrder>[
      orders[index],
      ...orders.take(index),
      ...orders.skip(index + 1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return StatusBarStyle.dark(
      child: Column(
        children: [
          ListenableBuilder(
            listenable: appState,
            builder: (context, _) => Container(
              padding: EdgeInsets.fromLTRB(20, top + 16, 20, 12),
              decoration: const BoxDecoration(
                color: AppColors.white,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pesanan masuk',
                          style: AppText.display(
                            24,
                            weight: 800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (appState.isLoadingMerchant)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Ulasan pelanggan',
                        onPressed: () => AppNav.toMerchantReviews(context),
                        icon: const Icon(Icons.reviews_outlined),
                        color: AppColors.brown,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TabSwitch(
                    tabs: const ['Aktif', 'Ditutup'],
                    index: _tab,
                    onTap: (index) => setState(() {
                      _tab = index;
                      _referenceTabResolved = true;
                    }),
                    activeColor: AppColors.brown,
                    underlineColor: AppColors.terracotta,
                    badges: {
                      if (appState.pendingOrderCount > 0)
                        0: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.terracotta,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${appState.pendingOrderCount}',
                            style: AppText.ui(
                              10,
                              weight: 700,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final orders = _prioritizeReferenced(
                  _tab == MerchantOrdersTab.active.index
                      ? appState.pendingOrders
                      : appState.completedOrders,
                );
                if (appState.isLoadingMerchant && orders.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return RefreshIndicator(
                  color: AppColors.terracotta,
                  onRefresh: appState.loadMerchantData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      if (appState.merchantError != null) ...[
                        _errorCard(appState.merchantError!),
                        const SizedBox(height: 14),
                      ],
                      if (orders.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 64),
                          child: EmptyState(
                            icon: _tab == 0
                                ? Icons.inbox_outlined
                                : Icons.check_circle_outline_rounded,
                            title: _tab == 0
                                ? 'Tidak ada pesanan aktif'
                                : 'Belum ada pesanan ditutup',
                            message: _tab == 0
                                ? 'Pesanan baru akan muncul otomatis di sini.'
                                : 'Pesanan selesai, dibatalkan, atau kedaluwarsa akan muncul di sini.',
                          ),
                        )
                      else
                        for (int i = 0; i < orders.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _orderCard(context, orders[i]),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderCard(BuildContext context, IncomingOrder order) {
    final key = _orderKey(order);
    final busy = _busyOrderKeys.contains(key);
    final actionable =
        order.status == IncomingOrderStatus.paid ||
        order.status == IncomingOrderStatus.preparing;
    final ready = order.status == IncomingOrderStatus.ready;
    final terminal =
        order.status == IncomingOrderStatus.redeemed ||
        order.status == IncomingOrderStatus.cancelled ||
        order.status == IncomingOrderStatus.expired;
    final reference = _orderReference(order);

    return AppCard(
      key: ValueKey(
        'merchant-${_tab == MerchantOrdersTab.active.index ? 'active' : 'closed'}-order-${order.id}',
      ),
      padding: EdgeInsets.zero,
      radius: 18,
      borderColor: ready ? AppColors.greenBright : AppColors.border,
      borderWidth: ready ? 1.4 : 1,
      onTap: () => AppNav.toOrderDetail(context, order),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: terminal
                        ? AppColors.greenSoftBg
                        : AppColors.terracottaSoftBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    order.initial,
                    style: AppText.ui(
                      14,
                      weight: 800,
                      color: terminal ? AppColors.greenAccent : AppColors.brown,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui(
                          14.5,
                          weight: 700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$reference · ${order.time}',
                        style: AppText.ui(11.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusBadge(order.status),
              ],
            ),
            const SizedBox(height: 13),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.bagTitle.isEmpty ? 'Surprise Bag' : order.bagTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(13.5, weight: 700, color: AppColors.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.bags} bag'
                    '${order.pickupWindow.isEmpty ? '' : ' · ambil ${order.pickupWindow}'}',
                    style: AppText.ui(12, color: AppColors.body),
                  ),
                ],
              ),
            ),
            if (!terminal) ...[
              const SizedBox(height: 12),
              if (actionable)
                Column(
                  children: [
                    PrimaryButton.merchant(
                      label: busy ? 'Menyimpan…' : 'Tandai siap diambil',
                      height: 46,
                      fontSize: 14,
                      icon: busy
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : const Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                              color: AppColors.white,
                            ),
                      onTap: busy || order.id.isEmpty
                          ? null
                          : () => _markReady(order),
                    ),
                    const SizedBox(height: 8),
                    _cancelButton(order, busy),
                  ],
                )
              else if (ready)
                Column(
                  children: [
                    PrimaryButton(
                      label: 'Scan QR untuk redeem',
                      height: 46,
                      fontSize: 14,
                      background: AppColors.green,
                      foreground: AppColors.white,
                      icon: const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 18,
                        color: AppColors.white,
                      ),
                      onTap: busy ? null : () => AppNav.toScanQr(context),
                    ),
                    const SizedBox(height: 8),
                    _cancelButton(order, busy),
                  ],
                )
              else
                Text(
                  'Pesanan belum dibayar dan belum perlu disiapkan.',
                  style: AppText.ui(12, color: AppColors.muted),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(IncomingOrderStatus status) {
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
      IncomingOrderStatus.cancelled => StatusBadge.expired('Dibatalkan'),
      IncomingOrderStatus.expired => StatusBadge.expired('Kedaluwarsa'),
    };
  }

  Widget _cancelButton(IncomingOrder order, bool busy) {
    return SizedBox(
      width: double.infinity,
      height: 43,
      child: OutlinedButton.icon(
        onPressed: busy || order.id.isEmpty ? null : () => _cancelOrder(order),
        icon: const Icon(Icons.cancel_outlined, size: 18),
        label: const Text('Batalkan pesanan'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
        ),
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

  Future<void> _markReady(IncomingOrder order) async {
    final key = _orderKey(order);
    if (_busyOrderKeys.contains(key) || order.id.isEmpty) return;
    setState(() => _busyOrderKeys.add(key));
    try {
      await appState.markOrderReady(order.id);
      if (mounted) {
        AppFeedback.snack(
          context,
          'Pesanan ditandai siap diambil.',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = error is BackendException
          ? error.message
          : 'Status pesanan belum dapat diperbarui.';
      AppFeedback.snack(context, message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busyOrderKeys.remove(key));
    }
  }

  Future<void> _cancelOrder(IncomingOrder order) async {
    final key = _orderKey(order);
    if (_busyOrderKeys.contains(key) || order.id.isEmpty) return;
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Batalkan pesanan?',
      message:
          'Midtrans akan membatalkan atau mengembalikan pembayaran untuk '
          '${_orderReference(order)}. Stok ${order.bags} bag baru dikembalikan '
          'setelah provider mengonfirmasi. Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Batalkan pesanan',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyOrderKeys.add(key));
    try {
      await appState.cancelMerchantOrder(order.id);
      if (mounted) {
        AppFeedback.snack(
          context,
          'Pembatalan/refund telah dikonfirmasi Midtrans untuk diproses. Stok telah '
          'dikembalikan; waktu dana masuk mengikuti metode pembayaran.',
          icon: Icons.inventory_2_outlined,
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        error is BackendException
            ? error.message
            : 'Pesanan belum dapat dibatalkan.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _busyOrderKeys.remove(key));
    }
  }

  String _orderKey(IncomingOrder order) => order.id.isNotEmpty
      ? order.id
      : '${order.customer}|${order.time}|${order.bags}';

  String _orderReference(IncomingOrder order) {
    if (order.id.isEmpty) return 'Pesanan baru';
    final clean = order.id.replaceAll('-', '');
    final suffix = clean.length <= 6
        ? clean
        : clean.substring(clean.length - 6);
    return 'Order #${suffix.toUpperCase()}';
  }
}
