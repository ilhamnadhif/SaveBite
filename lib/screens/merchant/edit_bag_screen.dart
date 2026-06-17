import 'package:flutter/material.dart';
import '../../sb.dart';

/// Edit Surprise Bag. Pola: LAYAR PENUH (Scaffold sendiri) + bar bawah.
class EditBagScreen extends StatefulWidget {
  const EditBagScreen({super.key, required this.bag});

  final MerchantBag bag;

  @override
  State<EditBagScreen> createState() => _EditBagScreenState();
}

class _EditBagScreenState extends State<EditBagScreen> {
  late int _qty = widget.bag.total;

  late String? _imageUrl =
      widget.bag.image.startsWith('http') ? widget.bag.image : null;

  late final List<String> _window = _splitWindow(widget.bag.pickupWindow);

  late final TextEditingController _titleController =
      TextEditingController(text: widget.bag.title);
  late final TextEditingController _priceController =
      TextEditingController(text: formatRupiah(widget.bag.salePrice));
  late final TextEditingController _windowStartController =
      TextEditingController(text: _window[0]);
  late final TextEditingController _windowEndController =
      TextEditingController(text: _window[1]);

  static List<String> _splitWindow(String raw) {
    final parts = raw.split('–');
    final start = parts.isNotEmpty ? parts[0].trim() : '';
    final end = parts.length > 1 ? parts[1].trim() : '';
    return [
      start.isEmpty ? '20.00' : start,
      end.isEmpty ? '21.00' : end,
    ];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _windowStartController.dispose();
    _windowEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Edit Surprise Bag'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  const FieldLabel('Foto bag'),
                  _coverPicker(),
                  const SizedBox(height: 16),
                  const FieldLabel('Judul bag'),
                  _controlledField(controller: _titleController),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        QtyStepper(
                          value: _qty,
                          suffix: 'bag',
                          plusColor: AppColors.terracotta,
                          onMinus: () {
                            if (_qty > 1) setState(() => _qty--);
                          },
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
                              controller: _windowStartController)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _controlledField(
                              controller: _windowEndController)),
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

  Future<void> _changeCover() async {
    final url = await appState.uploadImage(BackendBucket.bag);
    if (url == null || !mounted) return;
    setState(() => _imageUrl = url);
  }

  Widget _coverPicker() {
    final hasImage = _imageUrl != null && _imageUrl!.isNotEmpty;
    return GestureDetector(
      onTap: _changeCover,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 140,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.tanPlaceholder,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(color: AppColors.inputBorder, width: 1.5),
        ),
        alignment: Alignment.center,
        child: hasImage
            ? FoodImage(_imageUrl!, width: double.infinity, height: 140)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.photo_camera_outlined,
                      size: 24, color: AppColors.captionWarm),
                  const SizedBox(height: 6),
                  Text('Tambah foto',
                      style: AppText.ui(13, weight: 600, color: AppColors.muted)),
                ],
              ),
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
        label: 'Simpan perubahan',
        onTap: () async {
          final titleText = _titleController.text.trim();
          final digits =
              _priceController.text.replaceAll(RegExp(r'[^0-9]'), '');
          final parsedPrice =
              digits.isEmpty ? widget.bag.salePrice : int.parse(digits);
          final w1 = _windowStartController.text.trim();
          final w2 = _windowEndController.text.trim();
          await appState.updateBag(
            widget.bag,
            title: titleText,
            salePrice: parsedPrice,
            pickupWindow: '$w1–$w2',
            total: _qty,
            imageUrl: _imageUrl,
          );
          if (!context.mounted) return;
          AppFeedback.snack(context, 'Perubahan disimpan');
          Navigator.of(context).maybePop();
        },
      ),
    );
  }
}
