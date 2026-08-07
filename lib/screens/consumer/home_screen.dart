import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';
import 'consumer_shell.dart';
import 'location_picker_sheet.dart';

/// Beranda discovery konsumen berbasis lokasi dan filter aktif.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _refresh() => appState.loadConsumerHome();

  Future<void> _showFilters() async {
    final filter = await AppNav.showFilter(context);
    if (!mounted || filter == null) return;
    await appState.setBagFilter(filter);
  }

  Future<void> _selectCategory(String category) async {
    final categories = category == 'Semua' ? <String>{} : {category};
    await appState.setBagFilter(
      appState.currentFilter.copyWith(categories: categories),
    );
  }

  Future<void> _showLocationPicker() async {
    await ConsumerLocationPicker.show(context);
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
                        const SizedBox(width: 8),
                        _bellButton(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _searchBar(),
                  ],
                ),
              ),
              Expanded(child: _content()),
            ],
          );
        },
      ),
    );
  }

  Widget _locationPicker() {
    return Semantics(
      button: true,
      label: 'Lokasi kamu, ${appState.location}. Ketuk untuk mengubah.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _showLocationPicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lokasi kamu',
                  style: AppText.ui(
                    12,
                    weight: 600,
                    color: AppColors.greenMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        appState.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui(
                          16,
                          weight: 700,
                          color: AppColors.cream,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: AppColors.cream,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bellButton() {
    return Semantics(
      button: true,
      label: appState.unreadCount > 0
          ? '${appState.unreadCount} notifikasi belum dibaca'
          : 'Notifikasi',
      child: Material(
        color: AppColors.greenDark,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => AppNav.toNotifications(context),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              children: [
                const Center(
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: 21,
                    color: AppColors.amber,
                  ),
                ),
                if (appState.unreadCount > 0)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.terracotta,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.greenDark,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    final filterCount = _activeFilterCount(appState.currentFilter);
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => AppNav.toSearch(context),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(Icons.search, size: 19, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cari toko atau makanan…',
                  style: AppText.ui(14.5, color: AppColors.mutedAlt),
                ),
              ),
              Semantics(
                button: true,
                label: filterCount == 0
                    ? 'Buka filter'
                    : 'Buka filter, $filterCount filter aktif',
                child: IconButton(
                  tooltip: 'Filter',
                  onPressed: _showFilters,
                  icon: Badge(
                    isLabelVisible: filterCount > 0,
                    label: Text('$filterCount'),
                    backgroundColor: AppColors.terracotta,
                    child: const Icon(
                      Icons.tune,
                      size: 19,
                      color: AppColors.green,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final hasData = appState.nearbyBags.any((bag) => !bag.soldOut);
    if (!appState.hasValidUserLocation) {
      return _locationRequiredState();
    }
    if (appState.isLoadingConsumer && !hasData) {
      return const _LoadingState();
    }
    if (appState.consumerError != null && !hasData) {
      return _ErrorState(
        message: appState.consumerError!,
        onRetry: _refresh,
        onChangeLocation: _showLocationPicker,
      );
    }
    if (!hasData) {
      return _emptyState();
    }
    return _bagList();
  }

  Widget _locationRequiredState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        EmptyState(
          icon: Icons.location_searching_rounded,
          title: 'Pilih area untuk melihat Surprise Bag',
          message:
              'Atur lokasi agar SaveBite dapat menampilkan bag yang tersedia di sekitarmu.',
          action: SizedBox(
            width: 240,
            child: PrimaryButton(
              label: 'Pilih area',
              height: 50,
              onTap: _showLocationPicker,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _bagList() {
    final bags = appState.nearbyBags.where((bag) => !bag.soldOut).toList()
      ..sort((a, b) {
        final aEnd = a.pickupEndsAt;
        final bEnd = b.pickupEndsAt;
        if (aEnd == null && bEnd == null) return 0;
        if (aEnd == null) return 1;
        if (bEnd == null) return -1;
        return aEnd.compareTo(bEnd);
      });

    return RefreshIndicator(
      color: AppColors.greenBright,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          if (appState.consumerError != null) ...[
            _InlineError(message: appState.consumerError!, onRetry: _refresh),
            const SizedBox(height: 14),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < SampleData.categories.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final category = SampleData.categories[i];
                      final selected = category == 'Semua'
                          ? appState.currentFilter.categories.isEmpty
                          : appState.currentFilter.categories.contains(
                              category,
                            );
                      return SelectChip(
                        label: category,
                        selected: selected,
                        onTap: () => _selectCategory(category),
                      );
                    },
                  ),
                  if (i != SampleData.categories.length - 1)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionHeading(
            title: 'Segera tutup',
            leadingIcon: const Icon(
              Icons.local_fire_department,
              size: 16,
              color: AppColors.terracotta,
            ),
            actionLabel: 'Lihat peta',
            onAction: () => ConsumerShellScope.of(context)?.selectTab(1),
            fontSize: 18,
          ),
          const SizedBox(height: 12),
          BagHeroCard(
            bag: bags.first,
            onTap: () => AppNav.toDetail(context, bags.first),
          ),
          for (final bag in bags.skip(1)) ...[
            const SizedBox(height: 14),
            BagCompactCard(
              bag: bag,
              onTap: () => AppNav.toDetail(context, bag),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    final hasFilter = !appState.currentFilter.isEmpty;
    return RefreshIndicator(
      color: AppColors.greenBright,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          EmptyState(
            icon: hasFilter
                ? Icons.filter_alt_off_outlined
                : Icons.remove_shopping_cart_outlined,
            title: hasFilter
                ? 'Tak ada bag yang cocok'
                : 'Belum ada bag di sini',
            message: hasFilter
                ? 'Ubah atau reset filter untuk melihat lebih banyak pilihan.'
                : 'Toko di area ini belum merilis Surprise Bag. Coba lagi '
                      'nanti atau pilih area lain.',
            action: SizedBox(
              width: 240,
              child: PrimaryButton(
                label: hasFilter ? 'Atur ulang filter' : 'Ubah area',
                height: 50,
                onTap: hasFilter
                    ? () async {
                        await appState.setBagFilter(const BagFilter());
                      }
                    : _showLocationPicker,
              ),
            ),
            secondaryAction: TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Muat ulang'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  int _activeFilterCount(BagFilter filter) {
    var count = 0;
    if (filter.categories.isNotEmpty) count++;
    if (filter.maxDistanceKm != null) count++;
    if (filter.minPrice != null || filter.maxPrice != null) count++;
    if (filter.pickupAfter != null || filter.pickupBefore != null) count++;
    return count;
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Memuat Surprise Bag di sekitar',
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.greenBright),
            SizedBox(height: 14),
            Text('Mencari bag di sekitarmu…'),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChangeLocation;

  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.onChangeLocation,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Bag belum dapat dimuat',
      message: message,
      action: SizedBox(
        width: 220,
        child: PrimaryButton(label: 'Coba lagi', onTap: onRetry, height: 50),
      ),
      secondaryAction: TextButton(
        onPressed: onChangeLocation,
        child: const Text('Ubah area'),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.danger, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.ui(12.5, color: AppColors.danger),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Ulangi')),
          ],
        ),
      ),
    );
  }
}
