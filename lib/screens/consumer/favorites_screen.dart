import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B11 Favorit. Pola: KONTEN TAB — Column(header + Expanded scroll), tanpa Scaffold.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final favorites = appState.favoriteStores;
          return Column(
            children: [
              _header(),
              Expanded(
                child: favorites.isEmpty
                    ? const EmptyState(
                        icon: Icons.favorite_border,
                        title: 'Belum ada favorit',
                        message:
                            'Simpan toko favoritmu agar mudah ditemukan dan dapat info bag baru.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        children: [
                          for (final f in favorites) ...[
                            _favoriteCard(context, f),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    return ColoredHeader(
      background: AppColors.white,
      bottomPadding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Favorit', style: AppText.display(24, weight: 800, color: AppColors.ink)),
          const SizedBox(height: 3),
          Text('Kami kabari kalau ada bag baru dari toko ini.',
              style: AppText.ui(13, color: AppColors.body)),
        ],
      ),
    );
  }

  Widget _favoriteCard(BuildContext context, FavoriteStore f) {
    final m = f.merchant;
    return GestureDetector(
      onTap: () => AppNav.toStoreProfile(context, m),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 96,
                  child: FoodImage(m.coverImage),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(m.name,
                                style: AppText.ui(14, weight: 700, color: AppColors.ink)),
                            const SizedBox(height: 3),
                            Text('★ ${m.rating.toStringAsFixed(1)} · ${m.distance}',
                                style: AppText.ui(12, color: AppColors.body)),
                            const SizedBox(height: 8),
                            f.soldOut
                                ? StatusBadge.neutral(f.availability)
                                : StatusBadge.available(f.availability),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: () async {
                            final id = f.merchant.id;
                            await appState.toggleFavorite(id);
                            if (context.mounted) {
                              AppFeedback.snack(context, 'Dihapus dari favorit');
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: const Icon(Icons.favorite,
                              size: 20, color: AppColors.terracotta),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
