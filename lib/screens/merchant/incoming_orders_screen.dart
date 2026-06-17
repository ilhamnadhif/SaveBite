import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// C4 Pesanan Masuk. Pola: KONTEN TAB — Column(header + Expanded scroll).
class IncomingOrdersScreen extends StatefulWidget {
  const IncomingOrdersScreen({super.key});

  @override
  State<IncomingOrdersScreen> createState() => _IncomingOrdersScreenState();
}

class _IncomingOrdersScreenState extends State<IncomingOrdersScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
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
                  Text('Pesanan masuk',
                      style:
                          AppText.display(24, weight: 800, color: AppColors.ink)),
                  const SizedBox(height: 14),
                  TabSwitch(
                    tabs: const ['Perlu disiapkan', 'Selesai'],
                    index: _tab,
                    onTap: (i) => setState(() => _tab = i),
                    activeColor: AppColors.brown,
                    underlineColor: AppColors.terracotta,
                    badges: {
                      0: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.terracotta,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${appState.pendingOrderCount}',
                            style: AppText.ui(10,
                                weight: 700, color: AppColors.white)),
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
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: _tab == 0 ? _toPrepare() : _completed(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab "Perlu disiapkan" ────────────────────────────────────────────────
  List<Widget> _toPrepare() {
    final orders = appState.pendingOrders;
    if (orders.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.inbox_outlined,
          title: 'Tidak ada pesanan',
          message: 'Pesanan masuk akan muncul di sini.',
        ),
      ];
    }
    final widgets = <Widget>[];
    for (var i = 0; i < orders.length; i++) {
      final order = orders[i];
      final terracotta = i.isEven;
      if (i > 0) widgets.add(const SizedBox(height: 14));
      if (i == 0) {
        widgets.add(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => AppNav.toOrderDetail(context, order),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: AppColors.terracottaSoftBorder, width: 1.5),
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  _customerRow(
                    initials: order.initial,
                    boxBg: AppColors.terracottaSoftBg,
                    boxFg: AppColors.brown,
                    name: order.customer,
                    meta: 'Pesan ${order.time} · ${order.bags} bag',
                  ),
                  const SizedBox(height: 11),
                  // Kode pickup
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Kode pickup',
                            style: AppText.ui(13, color: AppColors.body)),
                        Text(order.code,
                            style: AppText.display(16,
                                weight: 800,
                                color: AppColors.ink,
                                letterSpacing: 2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: 'Scan QR untuk redeem',
                      height: 46,
                      fontSize: 14,
                      background: AppColors.green,
                      foreground: AppColors.white,
                      icon: const Icon(Icons.qr_code_scanner,
                          size: 18, color: AppColors.white),
                      onTap: () async => AppNav.toScanQr(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => AppNav.toOrderDetail(context, order),
            child: AppCard(
              padding: const EdgeInsets.all(15),
              radius: 18,
              borderColor: AppColors.border,
              child: _customerRow(
                initials: order.initial,
                boxBg: terracotta
                    ? AppColors.terracottaSoftBg
                    : AppColors.greenSoftBg,
                boxFg: terracotta ? AppColors.brown : AppColors.greenAccent,
                name: order.customer,
                meta: 'Pesan ${order.time} · ${order.bags} bag',
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  // ── Tab "Selesai" ─────────────────────────────────────────────────────────
  List<Widget> _completed() {
    final orders = appState.completedOrders;
    if (orders.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.check_circle_outline,
          title: 'Belum ada yang selesai',
          message: 'Pesanan yang sudah diambil akan muncul di sini.',
        ),
      ];
    }
    final widgets = <Widget>[];
    for (var i = 0; i < orders.length; i++) {
      final order = orders[i];
      final terracotta = i.isEven;
      if (i > 0) widgets.add(const SizedBox(height: 14));
      widgets.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => AppNav.toOrderDetail(context, order),
          child: AppCard(
            padding: const EdgeInsets.all(15),
            radius: 18,
            borderColor: AppColors.border,
            child: _customerRow(
              initials: order.initial,
              boxBg: terracotta
                  ? AppColors.terracottaSoftBg
                  : AppColors.greenSoftBg,
              boxFg: terracotta ? AppColors.brown : AppColors.greenAccent,
              name: '${order.customer} · ${order.bags} bag',
              meta: 'Diambil ${order.time}',
              done: true,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _customerRow({
    required String initials,
    required Color boxBg,
    required Color boxFg,
    required String name,
    required String meta,
    bool done = false,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: boxBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(initials,
              style: AppText.ui(14, weight: 800, color: boxFg)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: AppText.ui(14.5, weight: 700, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(meta, style: AppText.ui(12, color: AppColors.body)),
            ],
          ),
        ),
        done
            ? StatusBadge.done('Selesai')
            : StatusBadge(
                text: 'Menunggu',
                background: AppColors.terracottaSoftBg,
                foreground: AppColors.brown,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
      ],
    );
  }
}
