import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';
import 'merchant_shell.dart';

/// C2 Dashboard merchant.
/// Pola: KONTEN TAB — Column(header + Expanded scroll), tanpa Scaffold.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => Column(
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
                          Text('Halo,',
                              style: AppText.ui(13,
                                  color: AppColors.merchantMuted)),
                          Text(appState.storeName,
                              style: AppText.display(20,
                                  weight: 700, color: AppColors.cream)),
                        ],
                      ),
                    ),
                    StatusBadge(
                      text: '● Buka',
                      background: AppColors.greenBright,
                      foreground: AppColors.white,
                      weight: 800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                        child: _statTile(
                            '${appState.bagsSoldToday}', 'Bag terjual')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _statTile(
                            formatRupiah(appState.incomeToday), 'Pendapatan')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _statTile(
                            '${appState.activeBagCount}', 'Bag aktif')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: AppColors.cream,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  PrimaryButton.merchant(
                    label: 'Buat Surprise Bag',
                    height: 56,
                    icon:
                        const Icon(Icons.add, color: AppColors.white, size: 20),
                    onTap: () => AppNav.toCreateBag(context),
                  ),
                  const SizedBox(height: 20),
                  SectionHeading(
                    title: 'Bag aktif',
                    actionLabel: 'Kelola',
                    actionColor: AppColors.terracotta,
                    onAction: () =>
                        MerchantShellScope.of(context)?.selectTab(1),
                  ),
                  const SizedBox(height: 11),
                  _activeBagCard(),
                  const SizedBox(height: 18),
                  const SectionHeading(title: 'Order terbaru'),
                  const SizedBox(height: 11),
                  _orderCard(context),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.brownCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: AppText.display(22, weight: 800, color: AppColors.white)),
          const SizedBox(height: 2),
          Text(label,
              style: AppText.ui(11.5, color: AppColors.merchantMuted)),
        ],
      ),
    );
  }

  Widget _activeBagCard() {
    if (appState.activeBags.isEmpty) {
      return const EmptyState(
        icon: Icons.shopping_bag_outlined,
        title: 'Belum ada bag aktif',
        message: 'Buat Surprise Bag untuk mulai berjualan.',
      );
    }
    final bag = appState.activeBags.first;
    return AppCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(bag.title,
                    style: AppText.ui(14, weight: 700, color: AppColors.ink)),
              ),
              const SizedBox(width: 10),
              StatusBadge.available('Aktif'),
            ],
          ),
          const SizedBox(height: 6),
          Text('Ambil ${bag.pickupWindow} · ${formatRupiah(bag.salePrice)}',
              style: AppText.ui(12.5, color: AppColors.body)),
          const SizedBox(height: 11),
          ProgressBar(fraction: bag.total == 0 ? 0 : bag.sold / bag.total),
          const SizedBox(height: 6),
          Text('${bag.sold} dari ${bag.total} terjual',
              style: AppText.ui(11.5, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _orderCard(BuildContext context) {
    if (appState.pendingOrders.isEmpty) {
      return Text('Belum ada order',
          style: AppText.ui(12.5, color: AppColors.muted));
    }
    final order = appState.pendingOrders.first;
    return AppCard(
      radius: 14,
      onTap: () => AppNav.toOrderDetail(context, order),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.greenSoftBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(order.initial,
                style: AppText.ui(13,
                    weight: 800, color: AppColors.greenAccent)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${order.customer} · ${order.bags} bag',
                    style:
                        AppText.ui(13.5, weight: 700, color: AppColors.ink)),
                Text('${order.code} · belum diambil',
                    style: AppText.ui(12, color: AppColors.body)),
              ],
            ),
          ),
          const SizedBox(width: 11),
          StatusBadge.waiting('Menunggu'),
        ],
      ),
    );
  }
}
