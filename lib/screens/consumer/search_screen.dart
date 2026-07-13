import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';

/// Pencarian toko dan Surprise Bag dengan debounce serta stale-result guard.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _popular = ['Roti', 'Kopi', 'Donat', 'Pastry', 'Bakery'];

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  List<Bag> _results = const [];
  bool _loading = false;
  String? _error;
  int _searchSequence = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value;
      _error = null;
      if (value.trim().isEmpty) {
        _results = const [];
        _loading = false;
      }
    });
    if (value.trim().isEmpty) {
      _searchSequence++;
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(value),
    );
  }

  Future<void> _submit(String value) async {
    _debounce?.cancel();
    await _runSearch(value);
  }

  Future<void> _runSearch(String value) async {
    final query = value.trim();
    final sequence = ++_searchSequence;
    if (query.isEmpty) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final found = await appState.search(query);
      if (!mounted || sequence != _searchSequence) return;
      setState(() {
        _loading = false;
        _results = found.where((bag) => !bag.soldOut).toList(growable: false);
      });
    } catch (_) {
      if (!mounted || sequence != _searchSequence) return;
      setState(() {
        _loading = false;
        _results = const [];
        _error = 'Pencarian gagal dimuat. Periksa koneksimu lalu coba lagi.';
      });
    }
  }

  void _pickPopular(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    setState(() => _query = term);
    _submit(term);
  }

  Future<void> _showFilter() async {
    final filter = await AppNav.showFilter(context);
    if (!mounted || filter == null) return;
    await appState.setBagFilter(filter);
    if (!mounted) return;
    setState(() {});
    if (_query.trim().isNotEmpty) await _submit(_query);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focusNode.unfocus,
          child: Column(
            children: [
              _header(),
              Expanded(child: hasQuery ? _resultsView() : _emptyQueryView()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      color: AppColors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, top + 10, 12, 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Kembali',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: AppColors.ink,
              ),
            ),
            Expanded(child: _searchField()),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Filter pencarian',
              onPressed: _showFilter,
              icon: Badge(
                isLabelVisible: !appState.currentFilter.isEmpty,
                backgroundColor: AppColors.terracotta,
                child: const Icon(Icons.tune, color: AppColors.green),
              ),
            ),
          ],
        ),
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
              focusNode: _focusNode,
              autofocus: true,
              onChanged: _setQuery,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              autocorrect: false,
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
            IconButton(
              tooltip: 'Hapus pencarian',
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
              onPressed: () {
                _controller.clear();
                _setQuery('');
                _focusNode.requestFocus();
              },
              icon: const Icon(Icons.close, size: 19, color: AppColors.muted),
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
          Text(
            'Pencarian populer',
            style: AppText.ui(12.5, weight: 700, color: AppColors.body),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final term in _popular)
                SelectChip(label: term, onTap: () => _pickPopular(term)),
            ],
          ),
          if (!appState.currentFilter.isEmpty) ...[
            const SizedBox(height: 28),
            InfoBanner(
              icon: Icons.filter_alt_outlined,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter discovery juga berlaku pada hasil pencarian.',
                      style: AppText.ui(12.5, color: AppColors.body),
                    ),
                  ),
                  TextButton(onPressed: _showFilter, child: const Text('Ubah')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultsView() {
    if (_loading) {
      return Semantics(
        liveRegion: true,
        label: 'Mencari $_query',
        child: const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.greenBright,
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Pencarian gagal',
        message: _error!,
        action: SizedBox(
          width: 210,
          child: PrimaryButton(
            label: 'Coba lagi',
            height: 50,
            onTap: () => _submit(_query),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Tak ada hasil',
        message: !appState.currentFilter.isEmpty
            ? 'Tak ada hasil untuk “${_query.trim()}” dengan filter saat ini.'
            : 'Tak ada toko atau bag yang cocok dengan “${_query.trim()}”.',
        action: !appState.currentFilter.isEmpty
            ? SizedBox(
                width: 210,
                child: PrimaryButton(
                  label: 'Ubah filter',
                  height: 50,
                  onTap: _showFilter,
                ),
              )
            : null,
      );
    }
    return Semantics(
      liveRegion: true,
      label: '${_results.length} hasil ditemukan',
      child: ListView.separated(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        itemCount: _results.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          if (index == 0) {
            return Text(
              '${_results.length} hasil untuk “${_query.trim()}”',
              style: AppText.ui(12.5, weight: 700, color: AppColors.body),
            );
          }
          return _resultCard(_results[index - 1]);
        },
      ),
    );
  }

  Widget _resultCard(Bag bag) {
    return Semantics(
      button: true,
      label:
          '${bag.title}, ${bag.merchant.name}, ${formatRupiah(bag.salePrice)}',
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () => AppNav.toDetail(context, bag),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.cardSm),
              ),
              child: FoodImage(bag.image, width: 86, height: 94),
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
                      style: AppText.display(
                        15,
                        weight: 700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${bag.merchant.name} · ${bag.merchant.distance}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(12.5, color: AppColors.body),
                    ),
                    const SizedBox(height: 7),
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
      ),
    );
  }
}
