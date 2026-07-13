import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backend/backend.dart';
import '../../sb.dart';

/// Ulasan selalu dikaitkan ke satu pesanan yang sudah diambil. Parameter
/// merchant/date dipertahankan sementara agar pemanggil versi lama tetap dapat
/// membangun layar, tetapi pengiriman hanya aktif bila [order] tersedia.
class RatingScreen extends StatefulWidget {
  final OrderRecord? order;
  final Merchant? _legacyMerchant;
  final String? _legacyDate;

  const RatingScreen({super.key, this.order, Merchant? merchant, String? date})
    : assert(order != null || merchant != null),
      _legacyMerchant = merchant,
      _legacyDate = date;

  Merchant get merchant => order?.bag.merchant ?? _legacyMerchant!;
  String get date => order?.dateLabel ?? _legacyDate ?? '';

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  final TextEditingController _commentController = TextEditingController();
  final Set<String> _selectedTags = {};
  int _rating = 0;
  bool _submitting = false;

  static const List<String> _tags = [
    'Porsi banyak',
    'Masih fresh',
    'Pelayanan ramah',
    'Sesuai deskripsi',
    'Pickup cepat',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _toggleTag(String tag) {
    if (_submitting) return;
    setState(() {
      if (!_selectedTags.add(tag)) _selectedTags.remove(tag);
    });
  }

  Future<void> _submit() async {
    final order = widget.order;
    if (_submitting || _rating == 0 || order == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await appState.submitReview(
        order,
        _rating,
        _selectedTags.toList(growable: false),
        _commentController.text.trim(),
      );
      if (!mounted) return;
      AppFeedback.snack(context, 'Terima kasih, ulasanmu terkirim');
      Navigator.of(context).pop(true);
    } on BackendException catch (error) {
      if (!mounted) return;
      AppFeedback.snack(context, error.message, icon: Icons.error_outline);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Ulasan gagal dikirim. Periksa koneksi lalu coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final merchant = widget.merchant;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(
              title: 'Beri ulasan',
              background: AppColors.cream,
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  Column(
                    children: [
                      StoreAvatar(
                        initial: merchant.initial,
                        color: merchant.avatarColor,
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
                        '${merchant.name} · ${widget.date}',
                        textAlign: TextAlign.center,
                        style: AppText.ui(13.5, color: AppColors.body),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Semantics(
                    label: _rating == 0
                        ? 'Belum memilih rating'
                        : 'Rating $_rating dari 5',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 1; i <= 5; i++) ...[
                          Semantics(
                            button: true,
                            selected: i == _rating,
                            label: '$i dari 5 bintang',
                            child: InkResponse(
                              onTap: _submitting
                                  ? null
                                  : () => setState(() => _rating = i),
                              radius: 25,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Icon(
                                  i <= _rating
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 38,
                                  color: i <= _rating
                                      ? AppColors.amber
                                      : AppColors.handle,
                                ),
                              ),
                            ),
                          ),
                          if (i < 5) const SizedBox(width: 7),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  Text(
                    'Apa yang paling kamu suka? (opsional)',
                    style: AppText.ui(13, weight: 700, color: AppColors.body),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in _tags)
                        SelectChip(
                          label: tag,
                          selected: _selectedTags.contains(tag),
                          onTap: _submitting ? null : () => _toggleTag(tag),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          fontSize: 12.5,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ceritakan pengalamanmu (opsional)',
                    style: AppText.ui(13, weight: 700, color: AppColors.body),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: AppColors.border, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _commentController,
                      enabled: !_submitting,
                      maxLines: 4,
                      minLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [LengthLimitingTextInputFormatter(500)],
                      style: AppText.ui(14, color: AppColors.ink),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Makanan, porsi, atau proses pickup…',
                        hintStyle: AppText.ui(14, color: AppColors.mutedAlt),
                      ),
                    ),
                  ),
                  if (widget.order == null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Data pesanan belum tersedia. Buka ulasan kembali dari '
                      'Riwayat Pesanan agar ulasan dapat dikirim.',
                      style: AppText.ui(
                        12,
                        color: AppColors.danger,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.cream,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                14,
                24,
                14 + MediaQuery.of(context).padding.bottom,
              ),
              child: PrimaryButton(
                label: _submitting ? 'Mengirim…' : 'Kirim ulasan',
                onTap: _rating > 0 && widget.order != null && !_submitting
                    ? _submit
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
