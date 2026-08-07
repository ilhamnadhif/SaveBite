import 'package:flutter/material.dart';

import '../../sb.dart';

/// Dokumen hukum yang dapat dibuka dari profil dan pusat bantuan.
enum LegalDocument { terms, privacy, refundPolicy }

class LegalScreen extends StatelessWidget {
  final LegalDocument document;

  const LegalScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final content = _contentFor(document);
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            SimpleHeader(title: content.title),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  28 + MediaQuery.of(context).padding.bottom,
                ),
                children: [
                  Text(
                    'Terakhir diperbarui: 7 Agustus 2026',
                    style: AppText.ui(12.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    content.introduction,
                    style: AppText.ui(14, color: AppColors.body, height: 1.65),
                  ),
                  const SizedBox(height: 20),
                  for (final section in content.sections) ...[
                    Text(
                      section.title,
                      style: AppText.display(
                        17,
                        weight: 750,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      section.body,
                      style: AppText.ui(
                        13.5,
                        color: AppColors.body,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

_LegalContent _contentFor(LegalDocument document) {
  return switch (document) {
    LegalDocument.terms => const _LegalContent(
      title: 'Syarat & Ketentuan',
      introduction:
          'Ketentuan ini menjelaskan aturan dasar penggunaan SaveBite sebagai '
          'platform yang mempertemukan konsumen dan merchant makanan surplus.',
      sections: [
        _LegalSection(
          '1. Akun dan kelayakan',
          'Pengguna bertanggung jawab atas keakuratan data akun, keamanan '
              'akses, dan seluruh aktivitas yang dilakukan melalui akunnya. Akun '
              'tidak boleh digunakan untuk penipuan, penyalahgunaan promo, atau '
              'aktivitas yang melanggar hukum.',
        ),
        _LegalSection(
          '2. Surprise Bag',
          'Isi Surprise Bag dapat bervariasi karena bergantung pada makanan '
              'surplus yang tersedia. Merchant tetap bertanggung jawab atas '
              'kualitas, keamanan pangan, informasi alergen, serta kesesuaian '
              'produk pada saat penyerahan.',
        ),
        _LegalSection(
          '3. Pesanan dan pengambilan',
          'Konsumen wajib datang pada jendela pengambilan yang tercantum dan '
              'menunjukkan token QR aktif. Token bersifat pribadi dan tidak boleh '
              'dibagikan. Pesanan dianggap selesai setelah merchant memindai dan '
              'mengonfirmasi pengambilan.',
        ),
        _LegalSection(
          '4. Pembayaran',
          'Pembayaran diproses melalui Midtrans. SaveBite tidak menyimpan '
              'credential pembayaran pengguna dan hanya menganggap transaksi '
              'berhasil setelah statusnya diverifikasi oleh server penyedia. '
              'Ketersediaan metode dan waktu penyelesaian dapat berbeda menurut '
              'channel pembayaran yang dipilih.',
        ),
        _LegalSection(
          '5. Pembatasan dan penghentian',
          'SaveBite dapat membatasi akses yang terindikasi melanggar aturan '
              'atau membahayakan pengguna lain, dengan tetap mengikuti hukum yang '
              'berlaku dan mekanisme keberatan yang tersedia.',
        ),
      ],
    ),
    LegalDocument.privacy => const _LegalContent(
      title: 'Kebijakan Privasi',
      introduction:
          'Kebijakan ini merangkum cara SaveBite memproses data untuk menjalankan '
          'akun, pesanan, lokasi, notifikasi, dan dukungan pengguna.',
      sections: [
        _LegalSection(
          '1. Data yang diproses',
          'SaveBite dapat memproses identitas akun, email, nomor telepon, foto '
              'profil, lokasi perangkat saat diizinkan, detail pesanan, ulasan, '
              'data toko merchant, serta catatan keamanan dan operasional.',
        ),
        _LegalSection(
          '2. Tujuan pemrosesan',
          'Data digunakan untuk autentikasi, menampilkan bag terdekat, '
              'memproses dan memvalidasi pesanan, mencegah penyalahgunaan, '
              'mengirim notifikasi layanan, menangani dukungan, dan meningkatkan '
              'keandalan aplikasi.',
        ),
        _LegalSection(
          '3. Berbagi dan penyimpanan',
          'Data hanya boleh dibagikan kepada penyedia infrastruktur dan mitra '
              'yang diperlukan untuk layanan, berdasarkan perjanjian perlindungan '
              'data. Data disimpan selama diperlukan untuk menyediakan layanan, '
              'memenuhi kewajiban hukum, dan menyelesaikan sengketa.',
        ),
        _LegalSection(
          '4. Pilihan pengguna',
          'Pengguna dapat menolak izin lokasi dan memasukkan area secara '
              'manual. Pengguna juga dapat memperbarui profil, mengatur notifikasi '
              'di perangkat, serta meminta penghapusan akun dari menu Profil.',
        ),
        _LegalSection(
          '5. Keamanan data',
          'SaveBite menerapkan pembatasan akses dan kontrol keamanan yang '
              'wajar untuk melindungi data pengguna.',
        ),
      ],
    ),
    LegalDocument.refundPolicy => const _LegalContent(
      title: 'Pembatalan & Pengembalian Dana',
      introduction:
          'Kebijakan ini menjelaskan skenario pembatalan dan pengembalian dana untuk '
          'pembayaran yang diproses melalui Midtrans.',
      sections: [
        _LegalSection(
          '1. Pembatalan oleh merchant',
          'Jika merchant tidak dapat menyediakan pesanan, status pesanan harus '
              'diubah melalui proses pembatalan server. Pembayaran yang sudah '
              'berhasil tidak boleh dibatalkan hanya dari perangkat merchant; '
              'pengembalian diproses ke metode asal sesuai status dan SLA Midtrans.',
        ),
        _LegalSection(
          '2. Stok atau transaksi gagal',
          'Pesanan yang gagal dibuat karena stok berubah tidak boleh dikenai '
              'biaya. Reservation pembayaran yang gagal atau kedaluwarsa '
              'dikembalikan tepat satu kali. Kunci idempotensi mencegah pesanan '
              'ganda ketika pengguna mencoba kembali.',
        ),
        _LegalSection(
          '3. Tidak datang saat pickup',
          'Pesanan yang tidak diambil pada jendela pengambilan mengikuti ketentuan '
              'yang tercantum pada detail pesanan.',
        ),
        _LegalSection(
          '4. Pengajuan masalah',
          'Pengguna harus dapat mengirim nomor pesanan, uraian masalah, dan '
              'bukti pendukung melalui kanal bantuan SaveBite.',
        ),
      ],
    ),
  };
}

class _LegalContent {
  final String title;
  final String introduction;
  final List<_LegalSection> sections;

  const _LegalContent({
    required this.title,
    required this.introduction,
    required this.sections,
  });
}

class _LegalSection {
  final String title;
  final String body;

  const _LegalSection(this.title, this.body);
}
