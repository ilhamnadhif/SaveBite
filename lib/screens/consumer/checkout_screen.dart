import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// B5 Checkout & Bayar. Pola: LAYAR PENUH (Scaffold sendiri), stateful.
class CheckoutScreen extends StatefulWidget {
  final Bag bag;
  const CheckoutScreen({super.key, required this.bag});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int qty = 1;
  late String selectedMethod = appState.defaultPaymentMethod;

  Bag get bag => widget.bag;
  int get subtotal => bag.salePrice * qty;
  int get total => subtotal + 1000;

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Checkout'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  _itemCard(),
                  const SizedBox(height: 16),
                  _qtyCard(),
                  const SizedBox(height: 20),
                  Text('Metode pembayaran',
                      style: AppText.ui(14, weight: 700)),
                  const SizedBox(height: 11),
                  _methodsCard(),
                  const SizedBox(height: 20),
                  _summaryCard(),
                ],
              ),
            ),
            _bottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _itemCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FoodImage(bag.image, width: 58, height: 58),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bag.title, style: AppText.ui(14, weight: 700)),
                const SizedBox(height: 2),
                Text(bag.merchant.name,
                    style: AppText.ui(12.5, color: AppColors.body)),
                const SizedBox(height: 5),
                Text('Ambil ${bag.pickupWindow} hari ini',
                    style: AppText.ui(12.5,
                        weight: 700, color: AppColors.greenBright)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Jumlah bag', style: AppText.ui(14, weight: 700)),
          QtyStepper(
            value: qty,
            onMinus: () => setState(() {
              if (qty > 1) qty--;
            }),
            onPlus: () => setState(() {
              if (qty < bag.quantityLeft) qty++;
            }),
          ),
        ],
      ),
    );
  }

  Widget _methodsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _methodRow('GoPay', AppColors.gopay, last: false),
          _methodRow('OVO', AppColors.ovo, last: false),
          _methodRow('Virtual Account BCA', AppColors.bca, last: true),
        ],
      ),
    );
  }

  Widget _methodRow(String name, Color boxColor, {required bool last}) {
    final selected = selectedMethod == name;
    return GestureDetector(
      onTap: () => setState(() => selectedMethod = name),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: boxColor,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            const SizedBox(width: 12),
            Text(name, style: AppText.ui(14, weight: 600)),
            const Spacer(),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.greenBright : AppColors.inputBorder,
                  width: selected ? 6 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _summaryRow('Subtotal', formatRupiah(subtotal)),
          const SizedBox(height: 9),
          _summaryRow('Biaya layanan', 'Rp1.000'),
          Container(
            height: 1,
            color: AppColors.border,
            margin: const EdgeInsets.fromLTRB(0, 6, 0, 11),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Total', style: AppText.ui(15, weight: 700)),
              Text(formatRupiah(total),
                  style: AppText.display(20, color: AppColors.green)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.ui(13.5, color: AppColors.body)),
        Text(value, style: AppText.ui(13.5, color: AppColors.body)),
      ],
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
      child: PrimaryButton(
        label: 'Bayar ${formatRupiah(total)}',
        onTap: () => AppNav.toProcessing(
          context,
          bag: bag,
          qty: qty,
          willFail: selectedMethod == 'OVO',
          method: selectedMethod,
        ),
      ),
    );
  }
}
