import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';

/// Daftar ulasan yang hanya dapat dibaca oleh pemilik merchant terkait.
class MerchantReviewsScreen extends StatefulWidget {
  /// Saat dibuka dari notifikasi dengan stack baru, tombol kembali diarahkan
  /// ke beranda merchant alih-alih mencoba menutup route root.
  final bool rootEntry;

  const MerchantReviewsScreen({super.key, this.rootEntry = false});

  @override
  State<MerchantReviewsScreen> createState() => _MerchantReviewsScreenState();
}

class _MerchantReviewsScreenState extends State<MerchantReviewsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(appState.loadMerchantReviews());
    });
  }

  void _back() {
    if (widget.rootEntry) {
      AppNav.toMerchantHome(context);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.rootEntry,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.rootEntry) _back();
      },
      child: StatusBarStyle.dark(
        child: Scaffold(
          backgroundColor: AppColors.cream,
          body: ListenableBuilder(
            listenable: appState,
            builder: (context, _) {
              final reviews = appState.merchantReviews;
              return Column(
                children: [
                  SimpleHeader(
                    title: 'Ulasan pelanggan',
                    titleSize: 22,
                    onBack: _back,
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.terracotta,
                      onRefresh: appState.loadMerchantReviews,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                        children: [
                          if (reviews.isNotEmpty) ...[
                            _summary(reviews),
                            const SizedBox(height: 18),
                          ],
                          if (appState.errorMessage != null) ...[
                            _errorCard(appState.errorMessage!),
                            const SizedBox(height: 14),
                          ],
                          if (appState.isLoadingMerchantReviews &&
                              reviews.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 96),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.terracotta,
                                ),
                              ),
                            )
                          else if (reviews.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 72),
                              child: EmptyState(
                                icon: Icons.reviews_outlined,
                                title: 'Belum ada ulasan',
                                message:
                                    'Rating, tag, dan komentar pelanggan akan muncul setelah pesanan selesai.',
                              ),
                            )
                          else
                            for (
                              var index = 0;
                              index < reviews.length;
                              index++
                            ) ...[
                              if (index > 0) const SizedBox(height: 12),
                              _reviewCard(reviews[index]),
                            ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _summary(List<MerchantReview> reviews) {
    final average =
        reviews.fold<int>(0, (sum, item) => sum + item.rating) / reviews.length;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.ratingBg,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: AppColors.amber,
              size: 31,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  average.toStringAsFixed(1),
                  style: AppText.display(24, weight: 800, color: AppColors.ink),
                ),
                Text(
                  '${reviews.length} ulasan terbaru',
                  style: AppText.ui(12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (appState.isLoadingMerchantReviews)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _reviewCard(MerchantReview review) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.greenSoftBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  review.customerInitial,
                  style: AppText.ui(
                    13,
                    weight: 800,
                    color: AppColors.greenAccent,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(14, weight: 700, color: AppColors.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${review.orderReference} · ${_dateLabel(review.createdAt)}',
                      style: AppText.ui(11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _rating(review.rating),
            ],
          ),
          if (review.tags.isNotEmpty) ...[
            const SizedBox(height: 13),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: review.tags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.terracottaSoftBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tag,
                        style: AppText.ui(
                          11,
                          weight: 650,
                          color: AppColors.brown,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            review.comment.trim().isEmpty
                ? 'Tidak ada komentar tertulis.'
                : review.comment,
            style: AppText.ui(
              13,
              color: review.comment.trim().isEmpty
                  ? AppColors.muted
                  : AppColors.body,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rating(int rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.ratingBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.amber, size: 16),
          const SizedBox(width: 3),
          Text(
            '$rating',
            style: AppText.ui(12, weight: 800, color: AppColors.brown),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.dangerTintBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: AppText.ui(12.5, color: AppColors.danger),
            ),
          ),
          TextButton(
            onPressed: appState.loadMerchantReviews,
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Tanggal tidak tersedia';
    final local = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
