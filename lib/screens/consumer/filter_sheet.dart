import 'package:flutter/material.dart';
import '../../sb.dart';

/// B2 Pencarian & Filter. Pola: BOTTOM SHEET.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  final Set<String> _categories = {'Bakery', 'Resto'};
  static const _allCategories = ['Bakery', 'Kafe', 'Resto', 'Supermarket', 'Sehat'];
  double _distance = 2; // km (0..5)
  int _price = 1; // <15rb, 15–30rb, >30rb
  int _time = 0; // Sore, Malam

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, 32 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: SheetHandle()),
          Row(
            children: [
              Text('Filter', style: AppText.display(22, weight: 800)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() {
                  _categories.clear();
                  _distance = 2;
                  _price = 1;
                  _time = 0;
                }),
                child: Text('Reset',
                    style: AppText.ui(14, weight: 700, color: AppColors.greenBright)),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _label('Kategori'),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final c in _allCategories)
                SelectChip(
                  label: c,
                  selected: _categories.contains(c),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  onTap: () => setState(() {
                    _categories.contains(c)
                        ? _categories.remove(c)
                        : _categories.add(c);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Jarak maksimal', style: AppText.ui(14, weight: 700)),
              const Spacer(),
              Text('${_distance.toStringAsFixed(0)} km',
                  style: AppText.ui(14, weight: 700, color: AppColors.greenBright)),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: AppColors.greenBright,
              inactiveTrackColor: AppColors.chipBorder,
              thumbColor: AppColors.white,
              overlayColor: const Color(0x2227A36A),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: _distance,
              min: 0,
              max: 5,
              onChanged: (v) => setState(() => _distance = v),
            ),
          ),
          const SizedBox(height: 14),
          _label('Rentang harga'),
          Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                SelectChip(
                  label: const ['< 15rb', '15–30rb', '> 30rb'][i],
                  selected: _price == i,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  onTap: () => setState(() => _price = i),
                ),
                if (i != 2) const SizedBox(width: 9),
              ],
            ],
          ),
          const SizedBox(height: 24),
          _label('Jam pickup'),
          Row(
            children: [
              for (int i = 0; i < 2; i++) ...[
                SelectChip(
                  label: const ['Sore', 'Malam'][i],
                  selected: _time == i,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  onTap: () => setState(() => _time = i),
                ),
                if (i != 1) const SizedBox(width: 9),
              ],
            ],
          ),
          const SizedBox(height: 28),
          ListenableBuilder(
            listenable: appState,
            builder: (context, _) {
              final count = appState.nearbyBags
                  .where((b) =>
                      _categories.isEmpty ||
                      _categories.contains(b.merchant.category))
                  .length;
              return PrimaryButton(
                  label: 'Terapkan · $count hasil',
                  onTap: () => Navigator.of(context).pop(_categories));
            },
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Text(text, style: AppText.ui(14, weight: 700)),
      );
}
