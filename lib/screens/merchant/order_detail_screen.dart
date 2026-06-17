import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// Detail pesanan masuk. Pola: LAYAR PENUH (Scaffold sendiri) dengan bar bawah.
class OrderDetailScreen extends StatelessWidget {
  final IncomingOrder order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final subtotal = 15000 * order.bags;
    final komisi = (subtotal * 0.1).round();
    final masukSaldo = (subtotal * 0.9).round();

    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Detail Pesanan'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  _customerCard(),
                  const SizedBox(height: 20),
                  const SectionHeading(title: 'Item pesanan'),
                  const SizedBox(height: 12),
                  _itemRow(subtotal),
                  const SizedBox(height: 18),
                  _pickupCodeBox(),
                  const SizedBox(height: 18),
                  const SectionHeading(title: 'Rincian'),
                  const SizedBox(height: 12),
                  _detailCard(subtotal, komisi, masukSaldo),
                ],
              ),
            ),
            _bottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _customerCard() {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.terracottaSoftBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(order.initial,
                style: AppText.display(17, weight: 800, color: AppColors.brown)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.customer,
                    style: AppText.ui(14.5, weight: 700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('Pesan ${order.time}',
                    style: AppText.ui(12.5, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          order.redeemed
              ? StatusBadge.done('Selesai')
              : StatusBadge.waiting('Menunggu'),
        ],
      ),
    );
  }

  Widget _itemRow(int subtotal) {
    return AppCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: const FoodImage(SampleData.img1, width: 54, height: 54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Surprise Bag Roti & Pastry',
                    style: AppText.ui(14, weight: 700, color: AppColors.ink)),
                const SizedBox(height: 3),
                Text('${order.bags} bag',
                    style: AppText.ui(12.5, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(formatRupiah(subtotal),
              style: AppText.ui(14, weight: 700, color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _pickupCodeBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kode pickup',
              style: AppText.ui(12.5, weight: 600, color: AppColors.body)),
          const SizedBox(height: 6),
          Text(order.code,
              style: AppText.display(16, weight: 800, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _detailCard(int subtotal, int komisi, int masukSaldo) {
    return AppCard(
      child: Column(
        children: [
          _line('Subtotal', formatRupiah(subtotal)),
          const SizedBox(height: 11),
          _line('Komisi platform', '-${formatRupiah(komisi)}'),
          const SizedBox(height: 13),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 13),
          _line(
            'Masuk saldo',
            formatRupiah(masukSaldo),
            valueColor: AppColors.greenAccent,
            bold: true,
          ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 13),
          Row(
            children: [
              const Icon(Icons.schedule_outlined,
                  size: 18, color: AppColors.body),
              const SizedBox(width: 8),
              Text('Ambil 20.00–21.00',
                  style: AppText.ui(13.5, weight: 600, color: AppColors.body)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: AppText.ui(13.5,
                  weight: bold ? 700 : 500,
                  color: bold ? AppColors.ink : AppColors.body)),
        ),
        Text(value,
            style: AppText.ui(14,
                weight: bold ? 800 : 600,
                color: valueColor ?? AppColors.ink)),
      ],
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 30 + MediaQuery.of(context).padding.bottom),
      child: order.redeemed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Pesanan sudah diambil',
                    style: AppText.ui(14, weight: 600, color: AppColors.muted)),
              ),
            )
          : PrimaryButton.merchant(
              label: 'Scan QR untuk redeem',
              icon: const Icon(Icons.qr_code_scanner,
                  size: 20, color: AppColors.white),
              onTap: () async {
                await AppNav.toScanQr(context, code: order.code);
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
    );
  }
}
