import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B1 Beranda + B13 Empty state (cabang berdasarkan lokasi).
/// Pola: KONTEN TAB — Column(header + Expanded scroll), tanpa Scaffold.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _category = 'Semua';

  @override
  void initState() {
    super.initState();
    appState.loadConsumerHome();
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.light(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          return Column(
            children: [
              ColoredHeader(
                background: AppColors.green,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _locationPicker()),
                        _bellButton(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _searchBar(),
                  ],
                ),
              ),
              Expanded(
                child: !appState.hasNearbyBags
                    ? _emptyState()
                    : appState.nearbyBags.isEmpty
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.greenBright))
                        : _bagList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _locationPicker() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => appState.setLocation(
          appState.hasNearbyBags ? 'Cibinong, Bogor' : 'Margonda, Depok'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lokasi kamu',
              style: AppText.ui(12, weight: 600, color: AppColors.greenMuted)),
          Row(
            children: [
              const Icon(Icons.location_on, size: 15, color: AppColors.amber),
              const SizedBox(width: 5),
              Text(appState.location,
                  style: AppText.ui(16, weight: 700, color: AppColors.cream)),
              const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.cream),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bellButton() {
    return GestureDetector(
      onTap: () => AppNav.toNotifications(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
                color: AppColors.greenDark, shape: BoxShape.circle),
            child: const Icon(Icons.notifications_none_rounded,
                size: 20, color: AppColors.amber),
          ),
          if (appState.unreadCount > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: AppColors.terracotta,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.greenDark, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return GestureDetector(
      onTap: () => AppNav.toSearch(context),
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(left: 14, right: 6),
        decoration: BoxDecoration(
            color: AppColors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Cari toko atau makanan…',
                  style: AppText.ui(14.5, color: AppColors.mutedAlt)),
            ),
            GestureDetector(
              onTap: () async {
                final cats = await AppNav.showFilter(context);
                if (cats != null) {
                  setState(() => _category =
                      cats.isNotEmpty ? cats.first : 'Semua');
                }
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.tune, size: 18, color: AppColors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bagList() {
    final filtered = _category == 'Semua'
        ? appState.nearbyBags
        : appState.nearbyBags
            .where((b) => b.merchant.category == _category)
            .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < SampleData.categories.length; i++) ...[
                SelectChip(
                  label: SampleData.categories[i],
                  selected: _category == SampleData.categories[i],
                  onTap: () =>
                      setState(() => _category = SampleData.categories[i]),
                ),
                if (i != SampleData.categories.length - 1)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.search_off,
            title: 'Tak ada bag',
            message: 'Coba kategori lain.',
          )
        else ...[
          SectionHeading(
            title: 'Segera tutup',
            leadingIcon: const Icon(Icons.local_fire_department,
                size: 16, color: AppColors.terracotta),
            actionLabel: 'Lihat semua',
            fontSize: 18,
          ),
          const SizedBox(height: 12),
          BagHeroCard(
              bag: filtered.first,
              onTap: () => AppNav.toDetail(context, filtered.first)),
          for (final bag in filtered.skip(1)) ...[
            const SizedBox(height: 14),
            BagCompactCard(
                bag: bag, onTap: () => AppNav.toDetail(context, bag)),
          ],
        ],
      ],
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                  color: AppColors.emptyCircle, shape: BoxShape.circle),
              child: const Icon(Icons.remove_shopping_cart_outlined,
                  size: 48, color: AppColors.emptyIcon),
            ),
            const SizedBox(height: 22),
            Text('Belum ada bag di sini',
                textAlign: TextAlign.center,
                style: AppText.display(22, weight: 800)),
            const SizedBox(height: 8),
            Text(
              'Toko di sekitarmu belum merilis Surprise Bag hari ini. Coba ubah lokasi atau aktifkan notifikasi biar tak ketinggalan.',
              textAlign: TextAlign.center,
              style: AppText.ui(14, color: AppColors.body, height: 1.55),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 240,
              child: PrimaryButton(
                  label: 'Beri tahu saat ada bag',
                  height: 50,
                  onTap: () => AppFeedback.snack(
                      context, 'Kami akan kabari saat ada bag baru')),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => appState.setLocation('Margonda, Depok'),
              child: Text('Ubah lokasi',
                  style: AppText.ui(14, weight: 700, color: AppColors.greenBright)),
            ),
          ],
        ),
      ),
    );
  }
}
