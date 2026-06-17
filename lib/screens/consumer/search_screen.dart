import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// Layar pencarian: cari toko atau makanan dari Surprise Bag terdekat.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  List<Bag> _results = const [];
  bool _loading = false;
  int _searchSeq = 0;

  static const _popular = ['Roti', 'Kopi', 'Donat', 'Pastry', 'Bakery'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    setState(() => _query = value);
    _runSearch(value);
  }

  Future<void> _runSearch(String value) async {
    final q = value.trim();
    final seq = ++_searchSeq;
    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    setState(() => _loading = true);
    final found = await appState.search(q);
    // Guard terhadap hasil basi: hanya pakai jika ini pencarian terbaru.
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _loading = false;
      _results = found;
    });
  }

  void _pickPopular(String term) {
    _controller.text = term;
    _controller.selection =
        TextSelection.collapsed(offset: term.length);
    _setQuery(term);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            _header(),
            Expanded(
              child: hasQuery ? _resultsView() : _emptyQueryView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: AppColors.ink),
            ),
          ),
          Expanded(child: _searchField()),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _setQuery,
              textInputAction: TextInputAction.search,
              style: AppText.ui(14.5, color: AppColors.ink),
              cursorColor: AppColors.greenBright,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cari toko atau makanan…',
                hintStyle: AppText.ui(14.5, color: AppColors.mutedAlt),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                _setQuery('');
              },
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.close, size: 19, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyQueryView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pencarian populer',
              style: AppText.ui(12.5, weight: 700, color: AppColors.body)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final term in _popular)
                SelectChip(label: term, onTap: () => _pickPopular(term)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultsView() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.greenBright,
          ),
        ),
      );
    }
    final results = _results;
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Tak ada hasil',
        message: 'Coba kata kunci lain.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _resultCard(results[i]),
    );
  }

  Widget _resultCard(Bag bag) {
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => AppNav.toDetail(context, bag),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.cardSm)),
            child: FoodImage(
              bag.image,
              width: 86,
              height: 86,
              saturation: bag.soldOut ? 0.2 : 1,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    bag.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(15, weight: 700, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    bag.merchant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.ui(12.5, color: AppColors.body),
                  ),
                  const SizedBox(height: 7),
                  if (bag.soldOut) ...[
                    StatusBadge.neutral('Habis'),
                    const SizedBox(height: 7),
                  ],
                  PriceTag(
                    salePrice: bag.salePrice,
                    originalPrice: bag.originalPrice,
                    saleSize: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
