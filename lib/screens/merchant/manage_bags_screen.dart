import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// C7 Kelola Bag — Edit · nonaktif · duplikat.
/// Pola: KONTEN TAB — Column(header + Expanded scroll) + bar bawah, tanpa Scaffold.
class ManageBagsScreen extends StatefulWidget {
  const ManageBagsScreen({super.key});

  @override
  State<ManageBagsScreen> createState() => _ManageBagsScreenState();
}

class _ManageBagsScreenState extends State<ManageBagsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final bags =
                    _tab == 0 ? appState.activeBags : appState.inactiveBags;
                if (bags.isEmpty) {
                  return _tab == 0
                      ? const EmptyState(
                          icon: Icons.shopping_bag_outlined,
                          title: 'Belum ada bag aktif',
                          message: 'Buat Surprise Bag untuk mulai berjualan.',
                        )
                      : const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Tidak ada bag nonaktif',
                          message:
                              'Bag yang kamu nonaktifkan akan muncul di sini.',
                        );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  itemCount: bags.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _tab == 0
                      ? _activeCard(bags[i])
                      : _inactiveCard(bags[i]),
                );
              },
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _header() {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bag saya', style: AppText.display(24, weight: 800)),
          const SizedBox(height: 14),
          TabSwitch(
            tabs: const ['Aktif', 'Nonaktif'],
            index: _tab,
            onTap: (i) => setState(() => _tab = i),
            activeColor: AppColors.brown,
            underlineColor: AppColors.terracotta,
          ),
        ],
      ),
    );
  }

  // ───────────── Aktif ─────────────

  Widget _activeCard(MerchantBag bag) {
    final fraction = bag.total == 0 ? 0.0 : bag.sold / bag.total;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: FoodImage(bag.image, width: 64, height: 64),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(bag.title,
                                style: AppText.ui(14,
                                    weight: 700, color: AppColors.ink)),
                          ),
                          const SizedBox(width: 8),
                          _togglePill(bag),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                          '${formatRupiah(bag.salePrice)} · ambil ${bag.pickupWindow}',
                          style: AppText.ui(12, color: AppColors.body)),
                      const SizedBox(height: 8),
                      ProgressBar(fraction: fraction, height: 6),
                      const SizedBox(height: 5),
                      Text('${bag.sold} dari ${bag.total} terjual',
                          style: AppText.ui(11.5, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _actionsRow(
            left: _actionCell('Edit',
                color: AppColors.body,
                onTap: () => AppNav.toEditBag(context, bag)),
            right: _actionCell('Duplikat besok',
                color: AppColors.terracotta,
                withCopyIcon: true,
                onTap: () => _duplicate(bag)),
          ),
        ],
      ),
    );
  }

  // ───────────── Nonaktif ─────────────

  Widget _inactiveCard(MerchantBag bag) {
    return Opacity(
      opacity: 0.92,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child:
                        FoodImage(bag.image, width: 64, height: 64, saturation: 0.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(bag.title,
                                  style: AppText.ui(14,
                                      weight: 700, color: AppColors.ink)),
                            ),
                            const SizedBox(width: 8),
                            _togglePill(bag),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text('${formatRupiah(bag.salePrice)} · nonaktif',
                            style: AppText.ui(12, color: AppColors.body)),
                        if (bag.statusNote != null) ...[
                          const SizedBox(height: 6),
                          StatusBadge.neutral(bag.statusNote!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _actionsRow(
              left: _actionCell('Aktifkan',
                  color: AppColors.body, onTap: () => _activate(bag)),
              right: _actionCell('Duplikat besok',
                  color: AppColors.terracotta,
                  withCopyIcon: true,
                  onTap: () => _duplicate(bag)),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────── Aksi ─────────────

  Future<void> _onTogglePill(MerchantBag bag) async {
    if (bag.active) {
      final ok = await AppDialog.confirm(
        context,
        title: 'Nonaktifkan bag?',
        message: 'Bag tidak akan tampil ke pembeli.',
        confirmLabel: 'Nonaktifkan',
        destructive: true,
      );
      if (ok && mounted) {
        appState.toggleBagActive(bag);
        AppFeedback.snack(context, 'Bag dinonaktifkan');
      }
    } else {
      _activate(bag);
    }
  }

  void _activate(MerchantBag bag) {
    appState.toggleBagActive(bag);
    AppFeedback.snack(context, 'Bag diaktifkan');
  }

  void _duplicate(MerchantBag bag) {
    appState.duplicateBag(bag);
    AppFeedback.snack(context, 'Diduplikat untuk besok');
  }

  // ───────────── Bagian bersama ─────────────

  Widget _togglePill(MerchantBag bag) {
    final on = bag.active;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onTogglePill(bag),
      child: Container(
        width: 40,
        height: 23,
        decoration: BoxDecoration(
          color: on ? AppColors.greenBright : AppColors.handle,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 2.5,
              left: on ? null : 2.5,
              right: on ? 2.5 : null,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow({required Widget left, required Widget right}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  border:
                      Border(right: BorderSide(color: AppColors.divider)),
                ),
                child: left,
              ),
            ),
            Expanded(child: right),
          ],
        ),
      ),
    );
  }

  Widget _actionCell(String label,
      {required Color color,
      required VoidCallback onTap,
      bool withCopyIcon = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (withCopyIcon) ...[
              Icon(Icons.copy_outlined, size: 15, color: color),
              const SizedBox(width: 6),
            ],
            Text(label, style: AppText.ui(13, weight: 700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: PrimaryButton.merchant(
        label: 'Buat Surprise Bag',
        icon: const Icon(Icons.add, color: AppColors.white, size: 20),
        onTap: () => AppNav.toCreateBag(context),
      ),
    );
  }
}
