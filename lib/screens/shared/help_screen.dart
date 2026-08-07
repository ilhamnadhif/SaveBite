import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
      'SaveBite memakai QRIS. Setelah checkout, pindai kode QR yang tampil '
          'langsung di aplikasi dengan aplikasi pembayaran yang mendukung QRIS.',
    ),
    _Faq(
      'Bagaimana kalau saya tidak jadi ambil?',
      'Buka Kebijakan Pembatalan & Pengembalian Dana di Profil. Pembayaran yang '
          'belum selesai akan kedaluwarsa otomatis; pesanan yang sudah dibayar '
          'mengikuti proses pembatalan dan refund yang tercantum di sana.',
    ),
    _Faq(
      'Bisakah satu akun jadi penjual?',
      'Bisa. Pilih “Beralih ke mode penjual” dari Profil. Jika belum memiliki '
          'toko, kamu akan diminta melengkapi data toko terlebih dahulu.',
    ),
  ];

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'halo@savebite.id',
      queryParameters: {
        'subject': 'Bantuan aplikasi SaveBite',
        'body': 'Halo tim SaveBite,\n\nNomor pesanan (jika ada):\nKendala:\n',
      },
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        AppFeedback.snack(
          context,
          'Aplikasi email tidak tersedia. Kirim ke halo@savebite.id.',
          icon: Icons.info_outline,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      AppFeedback.snack(
        context,
        'Tidak dapat membuka email. Kirim ke halo@savebite.id.',
        icon: Icons.error_outline,
      );
    }
  }

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
                    child: Text(
                      'Pertanyaan umum',
                      style: AppText.ui(
                        12.5,
                        weight: 700,
                        color: AppColors.body,
                      ),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.cardSm),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppRadius.cardSm),
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
                            tilePadding: EdgeInsets.symmetric(horizontal: 16),
                            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                            expandedAlignment: Alignment.centerLeft,
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < _faqs.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                    height: 1,
                                    color: AppColors.divider,
                                  ),
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
                    child: Text(
                      'Hubungi kami',
                      style: AppText.ui(
                        12.5,
                        weight: 700,
                        color: AppColors.body,
                      ),
                    ),
                  ),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        MenuRow(
                          icon: Icons.mail_outline,
                          label: 'Kirim email ke dukungan',
                          last: true,
                          onTap: () => _openEmail(context),
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
      title: Text(
        faq.question,
        style: AppText.ui(14.5, weight: 700, color: AppColors.ink),
      ),
      children: [
        Text(
          faq.answer,
          style: AppText.ui(13.5, color: AppColors.body, height: 1.55),
        ),
      ],
    );
  }
}
