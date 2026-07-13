import 'package:flutter/material.dart';

import '../../sb.dart';
import '../../services/store_geocoding_service.dart';
import 'merchant_form_fields.dart';
import 'store_location_section.dart';

/// Edit Toko (mode ubah). Pola: LAYAR PENUH (Scaffold sendiri) dengan bar bawah.
class EditStoreScreen extends StatefulWidget {
  const EditStoreScreen({super.key});

  @override
  State<EditStoreScreen> createState() => _EditStoreScreenState();
}

class _EditStoreScreenState extends State<EditStoreScreen> {
  static const _defaultCategories = [
    'Bakery',
    'Kafe',
    'Resto',
    'Sehat',
    'Supermarket',
    'Lainnya',
  ];

  final _formKey = GlobalKey<FormState>();

  late final List<String> _categories =
      appState.storeCategory.trim().isNotEmpty &&
          !_defaultCategories.contains(appState.storeCategory)
      ? [..._defaultCategories, appState.storeCategory]
      : _defaultCategories;

  late final TextEditingController _nameC = TextEditingController(
    text: appState.storeName,
  );
  late final TextEditingController _addrC = TextEditingController(
    text: appState.storeAddress,
  );
  late final TextEditingController _openC = TextEditingController(
    text: appState.openTime,
  );
  late final TextEditingController _closeC = TextEditingController(
    text: appState.closeTime,
  );
  late final TextEditingController _descC = TextEditingController(
    text: appState.storeDescription,
  );

  late String _selectedCategory = _categories.contains(appState.storeCategory)
      ? appState.storeCategory
      : _categories.first;
  String? _logoUrl = appState.storeLogoUrl;
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
    _descC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              const SimpleHeader(title: 'Edit Toko'),
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
                        for (final category in _categories)
                          SelectChip(
                            label: category,
                            selected: _selectedCategory == category,
                            onTap: _isSaving
                                ? null
                                : () => setState(
                                    () => _selectedCategory = category,
                                  ),
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
                    const SizedBox(height: 16),
                    const FieldLabel('Deskripsi'),
                    MerchantFormField(
                      controller: _descC,
                      hintText: 'Ceritakan tentang toko dan produkmu',
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      validator: (value) {
                        if ((value?.trim().length ?? 0) > 500) {
                          return 'Maksimal 500 karakter';
                        }
                        return null;
                      },
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

  Future<void> _changePhoto() async {
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

  Widget _logoRow() {
    final hasLogo = _logoUrl != null && _logoUrl!.isNotEmpty;
    return Row(
      children: [
        Semantics(
          button: true,
          label: hasLogo ? 'Ganti foto toko' : 'Tambah foto toko',
          child: GestureDetector(
            onTap: _isSaving || _isUploading ? null : _changePhoto,
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
        'Sinkronkan alamat dengan pin peta sebelum menyimpan.',
        icon: Icons.location_off_outlined,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await appState.updateStore(
        name: _nameC.text.trim(),
        category: _selectedCategory,
        address: _addrC.text.trim(),
        open: _openC.text.trim(),
        close: _closeC.text.trim(),
        description: _descC.text.trim(),
        logoUrl: _logoUrl,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      AppFeedback.snack(context, 'Profil toko diperbarui');
      Navigator.maybePop(context);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Profil toko gagal disimpan. Coba lagi.',
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
        label: _isSaving ? 'Menyimpan...' : 'Simpan perubahan',
        onTap: _isSaving || _isUploading || _isLocating ? null : _save,
      ),
    );
  }
}
