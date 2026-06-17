import 'package:flutter/material.dart';
import '../../sb.dart';

/// C3 Buat Surprise Bag. Pola: LAYAR PENUH (Scaffold sendiri) + bar bawah.
class CreateBagScreen extends StatefulWidget {
  const CreateBagScreen({super.key});

  @override
  State<CreateBagScreen> createState() => _CreateBagScreenState();
}

class _CreateBagScreenState extends State<CreateBagScreen> {
  final TextEditingController _titleController =
      TextEditingController(text: 'Surprise Bag Roti & Pastry');
  final TextEditingController _priceController =
      TextEditingController(text: 'Rp15.000');
  final TextEditingController _pickupStartController =
      TextEditingController(text: '20.00');
  final TextEditingController _pickupEndController =
      TextEditingController(text: '21.00');
  int _qty = 8;
  String? _imageUrl;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _pickupStartController.dispose();
    _pickupEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Buat Surprise Bag'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  const FieldLabel('Foto bag'),
                  _coverPicker(),
                  const SizedBox(height: 16),
                  const FieldLabel('Judul bag'),
                  _titleField(),
                  const SizedBox(height: 16),
                  const FieldLabel('Deskripsi isi'),
                  const AppTextField(
                    maxLines: 3,
                    initialValue:
                        'Campuran roti manis, pastry, dan donat hari ini yang masih fresh.',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            FieldLabel('Harga asli'),
                            AppTextField(initialValue: 'Rp45.000'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Harga jual'),
                            _controlledField(
                              controller: _priceController,
                              borderColor: AppColors.greenBright,
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.greenSoftBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('-67%',
                                    style: AppText.ui(11,
                                        weight: 800,
                                        color: AppColors.greenAccent)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Jumlah tersedia'),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border:
                          Border.all(color: AppColors.inputBorder, width: 1.5),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        QtyStepper(
                          value: _qty,
                          suffix: 'bag',
                          plusColor: AppColors.terracotta,
                          onMinus: _qty > 1
                              ? () => setState(() => _qty--)
                              : null,
                          onPlus: () => setState(() => _qty++),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Window pickup'),
                  Row(
                    children: [
                      Expanded(
                          child: _controlledField(
                              controller: _pickupStartController)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _controlledField(
                              controller: _pickupEndController)),
                    ],
                  ),
                ],
              ),
            ),
            _bottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _coverPicker() {
    return GestureDetector(
      onTap: () async {
        final url = await appState.uploadImage(BackendBucket.bag);
        if (url != null) setState(() => _imageUrl = url);
      },
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.inputBorder, width: 1.5),
          ),
          alignment: Alignment.center,
          child: _imageUrl != null
              ? FoodImage(_imageUrl!, width: double.infinity, height: 160)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: AppColors.greenSoftBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_a_photo_outlined,
                          size: 22, color: AppColors.greenAccent),
                    ),
                    const SizedBox(height: 10),
                    Text('Tambah foto',
                        style: AppText.ui(13.5,
                            weight: 700, color: AppColors.body)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _titleField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: TextFormField(
        controller: _titleController,
        style: AppText.ui(14.5, color: AppColors.ink),
        cursorColor: AppColors.greenBright,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _controlledField({
    required TextEditingController controller,
    Color borderColor = AppColors.inputBorder,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              style: AppText.ui(14.5, color: AppColors.ink),
              cursorColor: AppColors.greenBright,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 30 + MediaQuery.of(context).padding.bottom),
      child: PrimaryButton.merchant(
        label: 'Publikasikan bag',
        onTap: () async {
          final title = _titleController.text.trim();
          final digits = _priceController.text.replaceAll(RegExp(r'\D'), '');
          final price = digits.isEmpty ? 15000 : int.parse(digits);
          final w1 = _pickupStartController.text.trim();
          final w2 = _pickupEndController.text.trim();
          await appState.addBag(
            title: title.isEmpty ? 'Surprise Bag' : title,
            salePrice: price,
            pickupWindow: '$w1–$w2',
            total: _qty,
            imageUrl: _imageUrl,
          );
          if (!context.mounted) return;
          AppFeedback.snack(context, 'Bag dipublikasikan');
          Navigator.of(context).maybePop();
        },
      ),
    );
  }
}
