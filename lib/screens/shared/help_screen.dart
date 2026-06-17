import 'package:flutter/material.dart';
import '../../sb.dart';

/// Bantuan / FAQ. Pola: LAYAR PENUH (Scaffold sendiri).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    _Faq(
      'Apa itu Surprise Bag?',
      'Paket kejutan berisi makanan layak yang belum terjual hari itu, '
          'dijual diskon 50–70%.',
    ),
    _Faq(
      'Bagaimana cara ambil pesanan?',
      'Datang ke toko pada jam pickup, tunjukkan QR di menu Pesanan, '
          'lalu kasir scan.',
    ),
    _Faq(
      'Metode pembayaran apa saja?',
      'GoPay, OVO, dan Virtual Account BCA.',
    ),
    _Faq(
      'Bagaimana kalau saya tidak jadi ambil?',
      'Pembayaran bersifat prepaid; jika tidak diambil dalam window, '
          'dana hangus.',
    ),
    _Faq(
      'Bisakah satu akun jadi penjual?',
      'Bisa — keluar lalu masuk lagi dan pilih “Saya mau jual”.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Bantuan'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('Pertanyaan umum',
                        style: AppText.ui(12.5,
                            weight: 700, color: AppColors.body)),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.cardSm),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius:
                            BorderRadius.circular(AppRadius.cardSm),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                        ),
                        child: ExpansionTileTheme(
                          data: const ExpansionTileThemeData(
                            iconColor: AppColors.greenBright,
                            collapsedIconColor: AppColors.greenBright,
                            backgroundColor: AppColors.white,
                            collapsedBackgroundColor: AppColors.white,
                            tilePadding:
                                EdgeInsets.symmetric(horizontal: 16),
                            childrenPadding:
                                EdgeInsets.fromLTRB(16, 0, 16, 14),
                            expandedAlignment: Alignment.centerLeft,
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < _faqs.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                      height: 1, color: AppColors.divider),
                                _FaqTile(faq: _faqs[i]),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('Hubungi kami',
                        style: AppText.ui(12.5,
                            weight: 700, color: AppColors.body)),
                  ),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        MenuRow(
                          icon: Icons.mail_outline,
                          label: 'Email: halo@savebite.id',
                          onTap: () => AppFeedback.snack(
                              context, 'Membuka email ke halo@savebite.id'),
                        ),
                        MenuRow(
                          icon: Icons.chat_bubble_outline,
                          label: 'WhatsApp: 0812-0000-0000',
                          last: true,
                          onTap: () => AppFeedback.snack(
                              context, 'Membuka WhatsApp 0812-0000-0000'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(faq.question,
          style: AppText.ui(14.5, weight: 700, color: AppColors.ink)),
      children: [
        Text(faq.answer,
            style: AppText.ui(13.5, color: AppColors.body, height: 1.55)),
      ],
    );
  }
}
