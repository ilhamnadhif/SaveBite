import 'package:flutter/material.dart';
import '../../sb.dart';

/// Edit Toko (mode ubah). Pola: LAYAR PENUH (Scaffold sendiri) dengan bar bawah.
class EditStoreScreen extends StatefulWidget {
  const EditStoreScreen({super.key});

  @override
  State<EditStoreScreen> createState() => _EditStoreScreenState();
}

class _EditStoreScreenState extends State<EditStoreScreen> {
  static const _categories = ['Bakery', 'Kafe', 'Resto'];

  late final TextEditingController nameC =
      TextEditingController(text: appState.storeName);
  late final TextEditingController addrC =
      TextEditingController(text: appState.storeAddress);
  late final TextEditingController openC =
      TextEditingController(text: appState.openTime);
  late final TextEditingController closeC =
      TextEditingController(text: appState.closeTime);
  late final TextEditingController descC =
      TextEditingController(text: appState.storeDescription);

  late String _selectedCategory = _categories.contains(appState.storeCategory)
      ? appState.storeCategory
      : _categories.first;

  String? _logoUrl = appState.storeLogoUrl;

  @override
  void dispose() {
    nameC.dispose();
    addrC.dispose();
    openC.dispose();
    closeC.dispose();
    descC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Edit Toko'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  _logoRow(),
                  const SizedBox(height: 20),
                  const FieldLabel('Nama toko'),
                  _field(nameC),
                  const SizedBox(height: 16),
                  const FieldLabel('Kategori'),
                  Row(
                    children: [
                      for (int i = 0; i < _categories.length; i++) ...[
                        SelectChip(
                          label: _categories[i],
                          selected: _selectedCategory == _categories[i],
                          onTap: () => setState(
                              () => _selectedCategory = _categories[i]),
                        ),
                        if (i != _categories.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Alamat'),
                  _field(addrC),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Jam buka'),
                            _field(openC),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Jam tutup'),
                            _field(closeC),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Deskripsi'),
                  _field(descC, maxLines: 3),
                ],
              ),
            ),
            _bottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
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

  Future<void> _changePhoto() async {
    final url = await appState.uploadImage(BackendBucket.logo);
    if (url == null || !mounted) return;
    setState(() => _logoUrl = url);
  }

  Widget _logoRow() {
    return Row(
      children: [
        GestureDetector(
          onTap: _changePhoto,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 68,
            height: 68,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                tileMode: TileMode.repeated,
                colors: [
                  Color(0xFFEFE7D6),
                  Color(0xFFEFE7D6),
                  Color(0xFFE7DDC8),
                  Color(0xFFE7DDC8),
                ],
                stops: [0.0, 0.5, 0.5, 1.0],
              ),
            ),
            alignment: Alignment.center,
            child: (_logoUrl != null && _logoUrl!.isNotEmpty)
                ? FoodImage(_logoUrl!, width: 68, height: 68)
                : const Icon(Icons.photo_camera_outlined,
                    size: 22, color: AppColors.captionWarm),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logo / foto toko',
                style: AppText.ui(14, weight: 700, color: AppColors.ink)),
            const SizedBox(height: 2),
            Text('PNG atau JPG, maks 2MB',
                style: AppText.ui(12.5, color: AppColors.muted)),
          ],
        ),
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
      child: PrimaryButton.merchant(
        label: 'Simpan perubahan',
        onTap: () async {
          await appState.updateStore(
            name: nameC.text,
            category: _selectedCategory,
            address: addrC.text,
            open: openC.text,
            close: closeC.text,
            description: descC.text,
            logoUrl: _logoUrl,
          );
          if (!context.mounted) return;
          AppFeedback.snack(context, 'Profil toko diperbarui');
          Navigator.maybePop(context);
        },
      ),
    );
  }
}
