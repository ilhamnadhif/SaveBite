import 'package:flutter/material.dart';

import '../../sb.dart';

/// Filter discovery yang menghasilkan satu objek [BagFilter] terstruktur.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  static const _allCategories = [
    'Bakery',
    'Kafe',
    'Resto',
    'Supermarket',
    'Sehat',
  ];
  static const _priceLabels = [
    'Semua harga',
    '< Rp15rb',
    'Rp15–30rb',
    '> Rp30rb',
  ];
  static const _pickupLabels = ['Kapan saja', 'Pagi', 'Siang', 'Sore', 'Malam'];

  late Set<String> _categories;
  late bool _limitDistance;
  late double _distance;
  late int _price;
  late int _pickup;

  @override
  void initState() {
    super.initState();
    final filter = appState.currentFilter;
    _categories = {...filter.categories};
    _limitDistance = filter.maxDistanceKm != null;
    _distance = (filter.maxDistanceKm ?? 5).clamp(0.5, 20);
    _price = _priceIndex(filter);
    _pickup = _pickupIndex(filter);
  }

  int _priceIndex(BagFilter filter) {
    if (filter.minPrice == null && filter.maxPrice == null) return 0;
    if (filter.minPrice == null && (filter.maxPrice ?? 0) < 15000) return 1;
    if ((filter.minPrice ?? 0) >= 15000 &&
        (filter.maxPrice ?? 30000) <= 30000) {
      return 2;
    }
    if ((filter.minPrice ?? 0) > 30000 && filter.maxPrice == null) return 3;
    return 0;
  }

  int _pickupIndex(BagFilter filter) {
    final start = filter.pickupAfter;
    if (start == null && filter.pickupBefore == null) return 0;
    final minutes = start == null ? -1 : start.hour * 60 + start.minute;
    if (minutes < 12 * 60) return 1;
    if (minutes < 17 * 60) return 2;
    if (minutes < 19 * 60) return 3;
    return 4;
  }

  BagFilter get _filter {
    int? minPrice;
    int? maxPrice;
    switch (_price) {
      case 1:
        maxPrice = 14999;
        break;
      case 2:
        minPrice = 15000;
        maxPrice = 30000;
        break;
      case 3:
        minPrice = 30001;
        break;
      default:
        break;
    }

    TimeOfDay? pickupAfter;
    TimeOfDay? pickupBefore;
    switch (_pickup) {
      case 1:
        pickupAfter = const TimeOfDay(hour: 5, minute: 0);
        pickupBefore = const TimeOfDay(hour: 11, minute: 59);
        break;
      case 2:
        pickupAfter = const TimeOfDay(hour: 12, minute: 0);
        pickupBefore = const TimeOfDay(hour: 16, minute: 59);
        break;
      case 3:
        pickupAfter = const TimeOfDay(hour: 17, minute: 0);
        pickupBefore = const TimeOfDay(hour: 18, minute: 59);
        break;
      case 4:
        pickupAfter = const TimeOfDay(hour: 19, minute: 0);
        pickupBefore = const TimeOfDay(hour: 23, minute: 59);
        break;
      default:
        break;
    }

    return BagFilter(
      categories: {..._categories},
      maxDistanceKm: _limitDistance ? _distance : null,
      minPrice: minPrice,
      maxPrice: maxPrice,
      pickupAfter: pickupAfter,
      pickupBefore: pickupBefore,
    );
  }

  void _reset() {
    setState(() {
      _categories.clear();
      _limitDistance = false;
      _distance = 5;
      _price = 0;
      _pickup = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: height * 0.9),
        decoration: const BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: SheetHandle()),
                    Row(
                      children: [
                        Text('Filter', style: AppText.display(22, weight: 800)),
                        const Spacer(),
                        TextButton(
                          onPressed: _reset,
                          child: Text(
                            'Reset',
                            style: AppText.ui(
                              14,
                              weight: 700,
                              color: AppColors.greenBright,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _label('Kategori'),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        for (final category in _allCategories)
                          SelectChip(
                            label: category,
                            selected: _categories.contains(category),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 9,
                            ),
                            onTap: () => setState(() {
                              if (!_categories.add(category)) {
                                _categories.remove(category);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _limitDistance,
                      activeTrackColor: AppColors.greenBright,
                      title: Text(
                        'Batasi jarak',
                        style: AppText.ui(14, weight: 700),
                      ),
                      subtitle: Text(
                        'Hanya tampilkan toko dalam radius pilihan',
                        style: AppText.ui(12, color: AppColors.body),
                      ),
                      onChanged: (value) =>
                          setState(() => _limitDistance = value),
                    ),
                    if (_limitDistance) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'Jarak maksimal',
                            style: AppText.ui(13, weight: 600),
                          ),
                          const Spacer(),
                          Text(
                            _distance < 1
                                ? '${(_distance * 1000).round()} m'
                                : '${_distance.toStringAsFixed(_distance % 1 == 0 ? 0 : 1)} km',
                            style: AppText.ui(
                              14,
                              weight: 700,
                              color: AppColors.greenBright,
                            ),
                          ),
                        ],
                      ),
                      Semantics(
                        label: 'Jarak maksimal dalam kilometer',
                        value: _distance.toStringAsFixed(1),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            activeTrackColor: AppColors.greenBright,
                            inactiveTrackColor: AppColors.chipBorder,
                            thumbColor: AppColors.white,
                            overlayColor: const Color(0x2227A36A),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 9,
                            ),
                          ),
                          child: Slider(
                            value: _distance,
                            min: 0.5,
                            max: 20,
                            divisions: 39,
                            label: '${_distance.toStringAsFixed(1)} km',
                            onChanged: (value) =>
                                setState(() => _distance = value),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _label('Rentang harga'),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        for (var i = 0; i < _priceLabels.length; i++)
                          SelectChip(
                            label: _priceLabels[i],
                            selected: _price == i,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            onTap: () => setState(() => _price = i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _label('Jam pickup dimulai'),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        for (var i = 0; i < _pickupLabels.length; i++)
                          SelectChip(
                            label: _pickupLabels[i],
                            selected: _pickup == i,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            onTap: () => setState(() => _pickup = i),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: const BoxDecoration(
                color: AppColors.cream,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: ListenableBuilder(
                listenable: appState,
                builder: (context, _) {
                  final count = appState.allNearbyBags
                      .where((bag) => bagMatchesFilter(bag, _filter))
                      .length;
                  return PrimaryButton(
                    label: 'Terapkan · $count hasil',
                    onTap: () => Navigator.of(context).pop(_filter),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Text(text, style: AppText.ui(14, weight: 700)),
  );
}
