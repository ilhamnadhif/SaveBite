import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B10 Profil Toko. Pola: LAYAR PENUH (Scaffold sendiri), bisa scroll.
class StoreProfileScreen extends StatefulWidget {
  final Merchant merchant;
  const StoreProfileScreen({super.key, required this.merchant});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  List<Bag> _bags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBags();
  }

  Future<void> _loadBags() async {
    final bags = await appState.bagsByMerchant(widget.merchant.id);
    if (!mounted) return;
    setState(() {
      _bags = bags;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [_cover(context, topInset), _headerInfo(), _body(context)],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, double topInset) {
    return SizedBox(
      height: 170,
      child: Stack(
        children: [
          Positioned.fill(child: FoodImage(widget.merchant.coverImage)),
          Positioned(
            top: topInset + 6,
            left: 18,
            child: CircleIconButton(
              onTap: () => Navigator.of(context).maybePop(),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 16,
                color: AppColors.ink,
              ),
            ),
          ),
          Positioned(
            top: topInset + 6,
            right: 18,
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final fav = appState.isFavorite(widget.merchant.id);
                return CircleIconButton(
                  semanticLabel: 'Favorit',
                  onTap: () async {
                    final added = await appState.toggleFavorite(
                      widget.merchant.id,
                    );
                    if (context.mounted) {
                      AppFeedback.snack(
                        context,
                        added
                            ? 'Ditambahkan ke favorit'
                            : 'Dihapus dari favorit',
                      );
                    }
                  },
                  child: Icon(
                    fav ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: AppColors.terracotta,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerInfo() {
    final merchant = widget.merchant;
    return Transform.translate(
      offset: const Offset(0, -34),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StoreAvatar(
              initial: merchant.initial,
              color: merchant.avatarColor,
              size: 72,
              radius: 20,
              border: 4,
              borderColor: AppColors.cream,
            ),
            const SizedBox(height: 12),
            Text(
              merchant.name,
              style: AppText.display(22, weight: 800, color: AppColors.ink),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '★ ${merchant.rating.toStringAsFixed(1)}',
                  style: AppText.ui(13, weight: 700, color: AppColors.amber),
                ),
                Text(
                  '(${merchant.reviewCount} ulasan)',
                  style: AppText.ui(13, color: AppColors.body),
                ),
                Text('·', style: AppText.ui(13, color: AppColors.body)),
                Text(
                  merchant.category,
                  style: AppText.ui(13, color: AppColors.body),
                ),
                Text('·', style: AppText.ui(13, color: AppColors.body)),
                Text(
                  merchant.distance,
                  style: AppText.ui(13, color: AppColors.body),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.greenBright,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${merchant.address} · Buka ${merchant.hours}',
                    style: AppText.ui(13, color: AppColors.body),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -34),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoBanner(
              icon: Icons.home_outlined,
              child: RichText(
                text: TextSpan(
                  style: AppText.ui(
                    13,
                    weight: 600,
                    color: AppColors.greenAccent,
                  ),
                  children: [
                    const TextSpan(text: 'Toko ini sudah menyelamatkan '),
                    TextSpan(
                      text: '${widget.merchant.bagsSaved} bag',
                      style: AppText.ui(
                        13,
                        weight: 700,
                        color: AppColors.greenAccent,
                      ),
                    ),
                    const TextSpan(text: ' makanan.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeading(title: 'Surprise Bag tersedia'),
            const SizedBox(height: 12),
            _bagsSection(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _bagsSection(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_bags.isEmpty) {
      return Text(
        'Belum ada bag tersedia',
        style: AppText.ui(13, color: AppColors.body),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < _bags.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _bagCard(context, _bags[i]),
        ],
      ],
    );
  }

  Widget _bagCard(BuildContext context, Bag bag) {
    return GestureDetector(
      onTap: () => AppNav.toDetail(context, bag),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 104, child: FoodImage(bag.image)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        bag.title,
                        style: AppText.ui(
                          14,
                          weight: 700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Ambil ${bag.pickupWindow} · sisa ${bag.quantityLeft}',
                        style: AppText.ui(12, color: AppColors.body),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            formatRupiah(bag.originalPrice),
                            style: AppText.ui(
                              12,
                              color: AppColors.strikethrough,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AppColors.strikethrough,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            formatRupiah(bag.salePrice),
                            style: AppText.display(
                              17,
                              weight: 800,
                              color: AppColors.greenBright,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
