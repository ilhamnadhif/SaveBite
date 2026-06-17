import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B4 Detail Bag. Pola: LAYAR PENUH (Scaffold sendiri).
class DetailScreen extends StatelessWidget {
  final Bag bag;
  const DetailScreen({super.key, required this.bag});

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.light(
      child: Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _imageHeader(context, topInset),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _merchantRow(context),
                      const SizedBox(height: 14),
                      Text(bag.title,
                          style: AppText.display(24, weight: 800)),
                      const SizedBox(height: 6),
                      Text(bag.description,
                          style: AppText.ui(14, color: AppColors.body, height: 1.55)),
                      const SizedBox(height: 18),
                      _infoCards(),
                      const SizedBox(height: 18),
                      Text('Mungkin ada di dalamnya',
                          style: AppText.ui(14, weight: 700)),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in bag.contents)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.neutralChip,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(c,
                                  style: AppText.ui(12.5,
                                      weight: 600, color: AppColors.body2)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _bottomBar(context),
        ],
      ),
      ),
    );
  }

  Widget _imageHeader(BuildContext context, double topInset) {
    return SizedBox(
      height: 248,
      child: Stack(
        children: [
          Positioned.fill(child: FoodImage(bag.image)),
          const BottomScrim(stop: 0.46),
          SaveRibbon(
            text: 'HEMAT ${bag.discountPercent}%',
            top: 18,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 6),
          ),
          Positioned(
            top: topInset + 6,
            left: 18,
            child: CircleIconButton(
              onTap: () => Navigator.of(context).maybePop(),
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 16, color: AppColors.ink),
            ),
          ),
          Positioned(
            top: topInset + 6,
            right: 18,
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final fav = appState.isFavorite(bag.merchant.id);
                return CircleIconButton(
                  semanticLabel: 'Favorit',
                  onTap: () async {
                    final added = await appState.toggleFavorite(bag.merchant.id);
                    if (context.mounted) {
                      AppFeedback.snack(context,
                          added ? 'Ditambahkan ke favorit' : 'Dihapus dari favorit');
                    }
                  },
                  child: Icon(fav ? Icons.favorite : Icons.favorite_border,
                      size: 18, color: AppColors.terracotta),
                );
              },
            ),
          ),
          Positioned(
            left: 18,
            bottom: 16,
            child: Row(
              children: [
                if (bag.soldOut) ...[
                  StatusBadge.neutral('Habis'),
                  const SizedBox(width: 9),
                ],
                OverlayBadge('Sisa ${bag.quantityLeft} lagi'),
                const SizedBox(width: 9),
                OverlayBadge('Isi senilai Rp${bag.originalPrice ~/ 1000}rb+',
                    dark: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _merchantRow(BuildContext context) {
    final m = bag.merchant;
    return Row(
      children: [
        StoreAvatar(initial: m.initial, color: m.avatarColor, size: 42, radius: 12),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: AppText.ui(15, weight: 700)),
              const SizedBox(height: 2),
              Text(
                  '★ ${m.rating.toStringAsFixed(1)} (${m.reviewCount}) · ${m.category} · ${m.distance}',
                  style: AppText.ui(12.5, color: AppColors.body)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => AppNav.toStoreProfile(context, m),
          child: Text('Lihat toko',
              style: AppText.ui(13, weight: 700, color: AppColors.greenBright)),
        ),
      ],
    );
  }

  Widget _infoCards() {
    return Row(
      children: [
        Expanded(
          child: _infoCard(
              'Window pickup', 'Hari ini ${bag.pickupWindow}', AppColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _infoCard(
              'Tersisa', '${bag.quantityLeft} bag lagi', AppColors.terracotta),
        ),
      ],
    );
  }

  Widget _infoCard(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.ui(11.5, weight: 600, color: AppColors.muted)),
          const SizedBox(height: 3),
          Text(value, style: AppText.ui(14, weight: 700, color: valueColor)),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatRupiah(bag.salePrice),
                      style: AppText.display(23, weight: 800, color: AppColors.green)),
                  const SizedBox(width: 7),
                  Text(formatRupiah(bag.originalPrice),
                      style: AppText.ui(12,
                          color: AppColors.strikethrough,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: AppColors.strikethrough)),
                ],
              ),
              Text('Kamu hemat ${formatRupiah(bag.savings)}',
                  style: AppText.ui(11.5, weight: 700, color: AppColors.greenAccent)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: PrimaryButton(
              label: bag.soldOut ? 'Bag habis' : 'Pesan sekarang',
              onTap: bag.soldOut ? null : () => AppNav.toCheckout(context, bag),
            ),
          ),
        ],
      ),
    );
  }
}
