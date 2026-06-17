import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// C1 Setup Toko. Pola: LAYAR PENUH (Scaffold sendiri) dengan bar bawah.
/// Sekali saat masuk mode jual.
class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({super.key});

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  static const _categories = ['Bakery', 'Kafe', 'Resto'];

  late final TextEditingController _nameC =
      TextEditingController(text: appState.storeName);
  late final TextEditingController _addrC =
      TextEditingController(text: appState.storeAddress);
  late final TextEditingController _openC =
      TextEditingController(text: appState.openTime);
  late final TextEditingController _closeC =
      TextEditingController(text: appState.closeTime);

  late int _category = () {
    final i = _categories.indexOf(appState.storeCategory);
    return i == -1 ? 0 : i;
  }();

  String? _logoUrl = appState.storeLogoUrl;

  @override
  void dispose() {
    _nameC.dispose();
    _addrC.dispose();
    _openC.dispose();
    _closeC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            _header(topInset),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                children: [
                  _logoRow(context),
                const SizedBox(height: 20),
                  const FieldLabel('Nama toko'),
                  _controlledField(controller: _nameC),
                  const SizedBox(height: 16),
                  const FieldLabel('Kategori'),
                  Row(
                    children: [
                      for (int i = 0; i < _categories.length; i++) ...[
                        SelectChip(
                          label: _categories[i],
                          selected: _category == i,
                          onTap: () => setState(() => _category = i),
                        ),
                        if (i != _categories.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Alamat'),
                  _controlledField(controller: _addrC),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Jam buka'),
                            _controlledField(controller: _openC),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Jam tutup'),
                            _controlledField(controller: _closeC),
                          ],
                        ),
                      ),
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

  Widget _header(double topInset) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topInset + 14, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Siapkan tokomu',
              style: AppText.display(21, weight: 800, color: AppColors.ink)),
          const SizedBox(height: 3),
          Text('Langkah 1 dari 1 · agar bag tampil ke pembeli',
              style: AppText.ui(13, color: AppColors.body)),
        ],
      ),
    );
  }

  Widget _logoRow(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: _pickLogo,
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
            child: _logoUrl != null
                ? FoodImage(_logoUrl!, width: 68, height: 68)
                : const Icon(Icons.add, size: 22, color: AppColors.captionWarm),
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

  Future<void> _pickLogo() async {
    final url = await appState.uploadImage(BackendBucket.logo);
    if (!mounted || url == null) return;
    setState(() => _logoUrl = url);
    AppFeedback.snack(context, 'Foto toko diperbarui');
  }

  Widget _controlledField({required TextEditingController controller}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
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
        ],
      ),
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
        label: 'Simpan & lanjut',
        onTap: () async {
          await appState.updateStore(
            name: _nameC.text,
            category: _categories[_category],
            address: _addrC.text,
            open: _openC.text,
            close: _closeC.text,
            logoUrl: _logoUrl,
          );
          if (!context.mounted) return;
          appState.merchantSetupDone = true;
          appState.switchToMerchant();
          AppNav.toMerchantHome(context);
        },
      ),
    );
  }
}
