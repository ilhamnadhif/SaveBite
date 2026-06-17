import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B7 Pesanan. Pola: KONTEN TAB — Column(header + Expanded scroll), tanpa Scaffold.
/// Tab internal: Aktif / Riwayat.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) => Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children:
                    _tab == 0 ? _aktifChildren(context) : _riwayatChildren(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 12, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pesanan',
              style: AppText.display(24, weight: 800, color: AppColors.ink)),
          const SizedBox(height: 14),
          TabSwitch(
            tabs: const ['Aktif', 'Riwayat'],
            index: _tab,
            onTap: (i) => setState(() => _tab = i),
          ),
        ],
      ),
    );
  }

  List<Widget> _aktifChildren(BuildContext context) {
    final active = appState.activeOrders;
    return [
      if (active.isEmpty)
        const EmptyState(
          icon: Icons.shopping_bag_outlined,
          title: 'Belum ada pesanan aktif',
          message: 'Pesanan yang sedang berjalan akan muncul di sini.',
        )
      else
        for (final o in active) _activeCard(context, o),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
        child: Text('RIWAYAT',
            style: AppText.ui(12.5,
                weight: 700, color: AppColors.muted, letterSpacing: 0.5)),
      ),
      ..._historyCards(context),
    ];
  }

  List<Widget> _riwayatChildren(BuildContext context) {
    return _historyCards(context);
  }

  Widget _activeCard(BuildContext context, OrderRecord o) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.greenSoftBorder, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              StoreAvatar(
                initial: o.bag.merchant.initial,
                color: o.bag.merchant.avatarColor,
                size: 40,
                radius: 11,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.bag.merchant.name,
                        style: AppText.ui(14, weight: 700, color: AppColors.ink)),
                    const SizedBox(height: 1),
                    Text('${o.code} · ${o.quantity} bag',
                        style: AppText.ui(12, color: AppColors.body)),
                  ],
                ),
              ),
              StatusBadge.available('Siap diambil'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Lihat QR pickup',
              height: 44,
              fontSize: 14,
              onTap: () => AppNav.toVoucher(context, o),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _historyCards(BuildContext context) {
    final history = appState.orderHistory;
    return [
      for (final o in history) _historyCard(context, o),
    ];
  }

  Widget _historyCard(BuildContext context, OrderRecord o) {
    final expired = o.status == OrderStatus.expired;
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
              o.bag.image,
              width: 46,
              height: 46,
              saturation: expired ? 0.6 : 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.bag.merchant.name,
                    style: AppText.ui(14, weight: 700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('${o.dateLabel} · ${formatRupiah(o.amount)}',
                    style: AppText.ui(12, color: AppColors.body)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _trailing(context, o),
        ],
      ),
    );
    if (expired) {
      card = Opacity(opacity: 0.75, child: card);
    }
    return card;
  }

  Widget _trailing(BuildContext context, OrderRecord o) {
    if (o.status == OrderStatus.expired) {
      return StatusBadge.expired('Hangus');
    }
    // Selesai (done)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        StatusBadge.done('Selesai'),
        const SizedBox(height: 6),
        if (o.canRate)
          GestureDetector(
            onTap: () => AppNav.toRating(context,
                merchant: o.bag.merchant, date: o.dateLabel),
            child: Text('★ Beri rating',
                style: AppText.ui(12, weight: 700, color: AppColors.amber)),
          )
        else if (o.reviewed)
          Text('★ 5 · diulas',
              style: AppText.ui(12, weight: 600, color: AppColors.muted)),
      ],
    );
  }
}
