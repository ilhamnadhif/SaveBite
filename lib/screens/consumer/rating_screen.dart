import 'package:flutter/material.dart';
import '../../sb.dart';

/// B8 Rating & Ulasan. Pola: LAYAR PENUH (Scaffold sendiri).
class RatingScreen extends StatefulWidget {
  final Merchant merchant;
  final String date;
  const RatingScreen({super.key, required this.merchant, required this.date});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int rating = 0;
  final Set<String> selectedTags = {};

  static const List<String> _tags = [
    'Porsi banyak',
    'Masih fresh',
    'Pelayanan ramah',
  ];

  void _toggleTag(String tag) {
    setState(() {
      if (selectedTags.contains(tag)) {
        selectedTags.remove(tag);
      } else {
        selectedTags.add(tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.merchant;
    return StatusBarStyle.dark(
      child: Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const SimpleHeader(title: 'Beri ulasan', background: AppColors.cream),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              children: [
                // Blok tengah.
                Column(
                  children: [
                    StoreAvatar(
                      initial: m.initial,
                      color: m.avatarColor,
                      size: 64,
                      radius: 18,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Bagaimana Surprise Bag-nya?',
                      textAlign: TextAlign.center,
                      style: AppText.display(18, weight: 700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${m.name} · ${widget.date}',
                      textAlign: TextAlign.center,
                      style: AppText.ui(13.5, color: AppColors.body),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                // Bintang.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 1; i <= 5; i++) ...[
                      GestureDetector(
                        onTap: () => setState(() => rating = i),
                        behavior: HitTestBehavior.opaque,
                        child: Icon(
                          i <= rating ? Icons.star : Icons.star_border,
                          size: 38,
                          color: i <= rating
                              ? AppColors.amber
                              : AppColors.handle,
                        ),
                      ),
                      if (i < 5) const SizedBox(width: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                // Chip tag.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in _tags)
                      SelectChip(
                        label: tag,
                        selected: selectedTags.contains(tag),
                        onTap: () => _toggleTag(tag),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 8),
                        fontSize: 12.5,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                // Kotak ulasan.
                const AppTextField(
                  maxLines: 4,
                  borderColor: AppColors.border,
                ),
              ],
            ),
          ),
          // Bar bawah.
          Padding(
            padding: EdgeInsets.fromLTRB(
                24, 14, 24, 14 + MediaQuery.of(context).padding.bottom),
            child: PrimaryButton(
              label: 'Kirim ulasan',
              onTap: rating > 0
                  ? () {
                      AppFeedback.snack(
                          context, 'Terima kasih, ulasanmu terkirim');
                      Navigator.of(context).maybePop();
                    }
                  : null,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
