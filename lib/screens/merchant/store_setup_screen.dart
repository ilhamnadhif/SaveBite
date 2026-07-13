import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';
import '../../services/store_geocoding_service.dart';
import 'merchant_form_fields.dart';
import 'store_location_section.dart';

/// C1 Setup Toko. Pola: LAYAR PENUH (Scaffold sendiri) dengan bar bawah.
/// Sekali saat masuk mode jual.
class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({super.key});

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  static const _defaultCategories = [
    'Bakery',
    'Kafe',
    'Resto',
    'Sehat',
    'Supermarket',
    'Lainnya',
  ];

  final _formKey = GlobalKey<FormState>();

  late final bool _hasExistingStore = appState.merchantSetupDone;
  late final List<String> _categories =
      _hasExistingStore &&
          appState.storeCategory.trim().isNotEmpty &&
          !_defaultCategories.contains(appState.storeCategory)
      ? [..._defaultCategories, appState.storeCategory]
      : _defaultCategories;
  late final TextEditingController _nameC = TextEditingController(
    text: _hasExistingStore ? appState.storeName : '',
  );
  late final TextEditingController _addrC = TextEditingController(
    text: _hasExistingStore ? appState.storeAddress : '',
  );
  late final TextEditingController _openC = TextEditingController(
    text: _hasExistingStore ? appState.openTime : '08.00',
  );
  late final TextEditingController _closeC = TextEditingController(
    text: _hasExistingStore ? appState.closeTime : '21.00',
  );

  late int _category = () {
    if (!_hasExistingStore) return 0;
    final index = _categories.indexOf(appState.storeCategory);
    return index == -1 ? 0 : index;
  }();

  late String? _logoUrl = _hasExistingStore ? appState.storeLogoUrl : null;
  bool _isSaving = false;
  bool _isUploading = false;
  bool _isLocating = false;
  late double? _latitude = appState.storeLatitude;
  late double? _longitude = appState.storeLongitude;

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
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              _header(topInset),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  children: [
                    _logoRow(),
                    const SizedBox(height: 20),
                    const FieldLabel('Nama toko'),
                    MerchantFormField(
                      controller: _nameC,
                      hintText: 'Contoh: Dapur Bu Sari',
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: _validateStoreName,
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Kategori'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < _categories.length; i++)
                          SelectChip(
                            label: _categories[i],
                            selected: _category == i,
                            onTap: _isSaving
                                ? null
                                : () => setState(() => _category = i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    StoreLocationSection(
                      addressController: _addrC,
                      initialLatitude: _latitude,
                      initialLongitude: _longitude,
                      enabled: !_isSaving && !_isUploading,
                      validator: _validateAddress,
                      readCurrentLocation: _readCurrentStoreLocation,
                      onBusyChanged: (busy) {
                        if (mounted && _isLocating != busy) {
                          setState(() => _isLocating = busy);
                        }
                      },
                      onPointChanged: (point) {
                        if (!mounted) return;
                        setState(() {
                          _latitude = point?.latitude;
                          _longitude = point?.longitude;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('Jam buka'),
                              _timeField(
                                controller: _openC,
                                fallback: const TimeOfDay(hour: 8, minute: 0),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('Jam tutup'),
                              _timeField(
                                controller: _closeC,
                                fallback: const TimeOfDay(hour: 21, minute: 0),
                                validator: _validateClosingTime,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _bottomBar(),
            ],
          ),
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
          Text(
            'Siapkan tokomu',
            style: AppText.display(21, weight: 800, color: AppColors.ink),
          ),
          const SizedBox(height: 3),
          Text(
            'Langkah 1 dari 1 · agar bag tampil ke pembeli',
            style: AppText.ui(13, color: AppColors.body),
          ),
        ],
      ),
    );
  }

  Widget _logoRow() {
    final hasLogo = _logoUrl != null && _logoUrl!.isNotEmpty;
    return Row(
      children: [
        Semantics(
          button: true,
          label: hasLogo ? 'Ganti foto toko' : 'Tambah foto toko',
          child: GestureDetector(
            onTap: _isSaving || _isUploading ? null : _pickLogo,
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
              child: _isUploading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.terracotta,
                      ),
                    )
                  : hasLogo
                  ? FoodImage(_logoUrl!, width: 68, height: 68)
                  : const Icon(
                      Icons.add_a_photo_outlined,
                      size: 22,
                      color: AppColors.captionWarm,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Logo / foto toko',
                style: AppText.ui(14, weight: 700, color: AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'PNG atau JPG, maks 2MB',
                style: AppText.ui(12.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timeField({
    required TextEditingController controller,
    required TimeOfDay fallback,
    String? Function(String?)? validator,
  }) {
    return MerchantFormField(
      controller: controller,
      readOnly: true,
      keyboardType: TextInputType.datetime,
      validator: validator ?? _validateTime,
      onTap: _isSaving
          ? null
          : () => _pickTime(controller: controller, fallback: fallback),
      trailing: const Icon(
        Icons.schedule_outlined,
        size: 18,
        color: AppColors.muted,
      ),
    );
  }

  Future<void> _pickTime({
    required TextEditingController controller,
    required TimeOfDay fallback,
  }) async {
    FocusScope.of(context).unfocus();
    final selected = await showTimePicker(
      context: context,
      initialTime: merchantTimeFromText(controller.text, fallback: fallback),
      helpText: 'Pilih waktu operasional',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (!mounted || selected == null) return;
    controller.text = formatMerchantTime(selected);
    _formKey.currentState?.validate();
  }

  Future<void> _pickLogo() async {
    if (_isSaving || _isUploading) return;
    setState(() => _isUploading = true);
    try {
      final url = await appState.uploadImage(BackendBucket.logo);
      if (!mounted || url == null) return;
      setState(() => _logoUrl = url);
      AppFeedback.snack(context, 'Foto toko diperbarui');
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Foto toko gagal diunggah. Coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<StoreCurrentLocation?> _readCurrentStoreLocation() async {
    final position = await appState.determineStoreLocation();
    if (position == null) {
      throw StoreLocationInputException(
        appState.errorMessage ?? 'Lokasi toko belum berhasil dibaca.',
      );
    }
    final point = StoreGeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (!point.isValid) {
      throw const StoreLocationInputException(
        'Perangkat memberikan koordinat yang tidak valid.',
      );
    }
    return StoreCurrentLocation(
      point: point,
      accuracyMeters: position.accuracy,
    );
  }

  String? _validateStoreName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Nama toko wajib diisi';
    if (text.length < 3) return 'Minimal 3 karakter';
    if (text.length > 80) return 'Maksimal 80 karakter';
    return null;
  }

  String? _validateAddress(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Alamat wajib diisi';
    if (text.length < 8) return 'Masukkan alamat lebih lengkap';
    if (text.length > 240) return 'Maksimal 240 karakter';
    return null;
  }

  String? _validateTime(String? value) {
    if (parseMerchantTimeMinutes(value ?? '') == null) {
      return 'Waktu tidak valid';
    }
    return null;
  }

  String? _validateClosingTime(String? value) {
    final error = _validateTime(value);
    if (error != null) return error;
    final open = parseMerchantTimeMinutes(_openC.text);
    final close = parseMerchantTimeMinutes(value!);
    if (open != null && open == close) return 'Harus berbeda';
    return null;
  }

  Future<void> _save() async {
    if (_isSaving || _isUploading || _isLocating) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppFeedback.snack(
        context,
        'Periksa kembali data toko.',
        icon: Icons.error_outline,
      );
      return;
    }
    final hasStoreLocation = isValidStoreCoordinate(_latitude, _longitude);
    if (!hasStoreLocation) {
      AppFeedback.snack(
        context,
        'Sinkronkan alamat dengan pin peta sebelum melanjutkan.',
        icon: Icons.location_off_outlined,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await appState.updateStore(
        name: _nameC.text.trim(),
        category: _categories[_category],
        address: _addrC.text.trim(),
        open: _openC.text.trim(),
        close: _closeC.text.trim(),
        logoUrl: _logoUrl,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      appState.switchToMerchant();
      AppNav.toMerchantHome(context);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Toko gagal disimpan. Periksa koneksi lalu coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _bottomBar() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        30 + MediaQuery.of(context).padding.bottom,
      ),
      child: PrimaryButton.merchant(
        label: _isSaving ? 'Menyimpan...' : 'Simpan & lanjut',
        onTap: _isSaving || _isUploading || _isLocating ? null : _save,
      ),
    );
  }
}
