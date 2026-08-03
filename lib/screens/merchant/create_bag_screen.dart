import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/env.dart';
import '../../sb.dart';
import 'merchant_form_fields.dart';

/// C3 Buat Surprise Bag. Pola: LAYAR PENUH (Scaffold sendiri) + bar bawah.
class CreateBagScreen extends StatefulWidget {
  const CreateBagScreen({super.key});

  @override
  State<CreateBagScreen> createState() => _CreateBagScreenState();
}

class _CreateBagScreenState extends State<CreateBagScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contentsController = TextEditingController();
  final _originalPriceController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _pickupStartController = TextEditingController(text: '20.00');
  final _pickupEndController = TextEditingController(text: '21.00');
  DateTime _availableOn = merchantDateOnly(DateTime.now());
  late final _dateController = TextEditingController(
    text: formatMerchantDate(_availableOn),
  );

  int _qty = 1;
  String? _imageUrl;
  bool _isSaving = false;
  bool _isUploading = false;

  int? get _discountPercent {
    final original = parseMerchantPrice(_originalPriceController.text);
    final sale = parseMerchantPrice(_salePriceController.text);
    if (original == null || sale == null || original <= sale || sale <= 0) {
      return null;
    }
    return ((original - sale) * 100 / original).round();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _contentsController.dispose();
    _originalPriceController.dispose();
    _salePriceController.dispose();
    _pickupStartController.dispose();
    _pickupEndController.dispose();
    _dateController.dispose();
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
              const SimpleHeader(title: 'Buat Surprise Bag'),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  children: [
                    const FieldLabel('Foto bag'),
                    _coverPicker(),
                    if (Env.e2eMode) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        key: const ValueKey('e2e-bag-photo-button'),
                        onPressed: _isSaving || _isUploading
                            ? null
                            : _useBundledTestCover,
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Gunakan foto staging'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const FieldLabel('Judul bag'),
                    MerchantFormField(
                      controller: _titleController,
                      hintText: 'Contoh: Surprise Bag Roti & Pastry',
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: _validateTitle,
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Deskripsi isi'),
                    MerchantFormField(
                      controller: _descriptionController,
                      hintText: 'Jelaskan perkiraan isi dan kondisi produk',
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      validator: _validateDescription,
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Perkiraan isi (opsional)'),
                    MerchantFormField(
                      controller: _contentsController,
                      hintText: 'Contoh: Roti manis, Croissant, Donat',
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      validator: _validateContents,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${parseBagContents(_contentsController.text).length}/20 item · pisahkan dengan koma atau baris baru',
                      style: AppText.ui(11.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('Harga asli'),
                              _priceField(
                                controller: _originalPriceController,
                                validator: _validateOriginalPrice,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('Harga jual'),
                              _priceField(
                                controller: _salePriceController,
                                validator: _validateSalePrice,
                                highlight: true,
                                trailing: _discountBadge(),
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
                        border: Border.all(
                          color: AppColors.inputBorder,
                          width: 1.5,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: QtyStepper(
                        value: _qty,
                        suffix: 'bag',
                        plusColor: AppColors.terracotta,
                        onMinus: _isSaving || _qty <= 1
                            ? null
                            : () => setState(() => _qty--),
                        onPlus: _isSaving || _qty >= 999
                            ? null
                            : () => setState(() => _qty++),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Tanggal tersedia'),
                    MerchantFormField(
                      controller: _dateController,
                      readOnly: true,
                      validator: _validateDate,
                      onTap: _isSaving ? null : _pickDate,
                      trailing: const Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Window pickup'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _timeField(
                            controller: _pickupStartController,
                            fallback: const TimeOfDay(hour: 20, minute: 0),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _timeField(
                            controller: _pickupEndController,
                            fallback: const TimeOfDay(hour: 21, minute: 0),
                            validator: _validatePickupEnd,
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

  Widget _coverPicker() {
    final hasImage = _imageUrl != null && _imageUrl!.isNotEmpty;
    return Semantics(
      button: true,
      label: hasImage ? 'Ganti foto bag' : 'Tambah foto bag',
      child: GestureDetector(
        onTap: _isSaving || _isUploading ? null : _changeCover,
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
            child: _isUploading
                ? const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.terracotta,
                  )
                : hasImage
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
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          size: 22,
                          color: AppColors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tambah foto',
                        style: AppText.ui(
                          13.5,
                          weight: 700,
                          color: AppColors.body,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _priceField({
    required TextEditingController controller,
    required String? Function(String?) validator,
    Widget? trailing,
    bool highlight = false,
  }) {
    return MerchantFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: const [RupiahInputFormatter()],
      prefixText: 'Rp ',
      validator: validator,
      borderColor: highlight ? AppColors.greenBright : AppColors.inputBorder,
      trailing: trailing,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget? _discountBadge() {
    final discount = _discountPercent;
    if (discount == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.greenSoftBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '-$discount%',
        style: AppText.ui(11, weight: 800, color: AppColors.greenAccent),
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

  Future<void> _changeCover() async {
    if (_isSaving || _isUploading) return;
    setState(() => _isUploading = true);
    try {
      final url = await appState.uploadImage(BackendBucket.bag);
      if (!mounted || url == null) return;
      setState(() => _imageUrl = url);
      AppFeedback.snack(context, 'Foto bag diperbarui');
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Foto bag gagal diunggah. Coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _useBundledTestCover() async {
    if (!Env.e2eMode || _isSaving || _isUploading) return;
    setState(() => _isUploading = true);
    try {
      final data = await rootBundle.load('assets/images/food4.jpg');
      final url = await appState.uploadImageBytes(
        BackendBucket.bag,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        filename: 'savebite-e2e-food.jpg',
      );
      if (!mounted || url == null) return;
      setState(() => _imageUrl = url);
      AppFeedback.snack(context, 'Foto staging berhasil diunggah');
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Foto staging gagal diunggah. Coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final today = merchantDateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _availableOn.isBefore(today) ? today : _availableOn,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Pilih tanggal bag tersedia',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (!mounted || selected == null) return;
    setState(() {
      _availableOn = merchantDateOnly(selected);
      _dateController.text = formatMerchantDate(_availableOn);
    });
    _formKey.currentState?.validate();
  }

  Future<void> _pickTime({
    required TextEditingController controller,
    required TimeOfDay fallback,
  }) async {
    FocusScope.of(context).unfocus();
    final selected = await showTimePicker(
      context: context,
      initialTime: merchantTimeFromText(controller.text, fallback: fallback),
      helpText: 'Pilih waktu pickup',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (!mounted || selected == null) return;
    controller.text = formatMerchantTime(selected);
    _formKey.currentState?.validate();
  }

  String? _validateTitle(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Judul bag wajib diisi';
    if (text.length < 3) return 'Minimal 3 karakter';
    if (text.length > 80) return 'Maksimal 80 karakter';
    return null;
  }

  String? _validateDescription(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Deskripsi wajib diisi';
    if (text.length < 10) return 'Minimal 10 karakter';
    if (text.length > 500) return 'Maksimal 500 karakter';
    return null;
  }

  String? _validateContents(String? value) =>
      bagContentsValidationError(parseBagContents(value ?? ''));

  String? _validateOriginalPrice(String? value) {
    final original = parseMerchantPrice(value ?? '');
    if (original == null) return 'Wajib diisi';
    if (original < 1000) return 'Minimal Rp1.000';
    final sale = parseMerchantPrice(_salePriceController.text);
    if (sale != null && original <= sale) return 'Harus di atas harga jual';
    return null;
  }

  String? _validateSalePrice(String? value) {
    final sale = parseMerchantPrice(value ?? '');
    if (sale == null) return 'Wajib diisi';
    if (sale < 1000) return 'Minimal Rp1.000';
    final original = parseMerchantPrice(_originalPriceController.text);
    if (original != null && sale >= original) return 'Harus lebih rendah';
    return null;
  }

  String? _validateDate(String? value) {
    final today = merchantDateOnly(DateTime.now());
    if (_availableOn.isBefore(today)) return 'Tanggal sudah lewat';
    return null;
  }

  String? _validateTime(String? value) {
    if (parseMerchantTimeMinutes(value ?? '') == null) {
      return 'Waktu tidak valid';
    }
    return null;
  }

  String? _validatePickupEnd(String? value) {
    final error = _validateTime(value);
    if (error != null) return error;
    final start = parseMerchantTimeMinutes(_pickupStartController.text);
    final end = parseMerchantTimeMinutes(value!);
    if (start != null && end! <= start) return 'Harus setelah mulai';
    final now = DateTime.now();
    final pickupEnd = merchantDateTime(_availableOn, value);
    if (!pickupEnd.isAfter(now)) return 'Waktu sudah lewat';
    return null;
  }

  Future<void> _publish() async {
    if (_isSaving || _isUploading) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppFeedback.snack(
        context,
        'Periksa kembali data bag.',
        icon: Icons.error_outline,
      );
      return;
    }
    if (_imageUrl == null || _imageUrl!.isEmpty) {
      AppFeedback.snack(
        context,
        'Tambahkan foto bag sebelum dipublikasikan.',
        icon: Icons.add_a_photo_outlined,
      );
      return;
    }

    final originalPrice = parseMerchantPrice(_originalPriceController.text)!;
    final salePrice = parseMerchantPrice(_salePriceController.text)!;
    final pickupStartsAt = merchantDateTime(
      _availableOn,
      _pickupStartController.text,
    );
    final pickupEndsAt = merchantDateTime(
      _availableOn,
      _pickupEndController.text,
    );

    setState(() => _isSaving = true);
    try {
      await appState.addBag(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        contents: parseBagContents(_contentsController.text),
        originalPrice: originalPrice,
        salePrice: salePrice,
        pickupWindow:
            '${_pickupStartController.text}–${_pickupEndController.text}',
        pickupStartsAt: pickupStartsAt,
        pickupEndsAt: pickupEndsAt,
        availableOn: _availableOn,
        total: _qty,
        imageUrl: _imageUrl,
      );
      if (!mounted) return;
      AppFeedback.snack(context, 'Bag dipublikasikan');
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Bag gagal dipublikasikan. Coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _bottomBar() {
    return Container(
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
        label: _isSaving ? 'Mempublikasikan...' : 'Publikasikan bag',
        onTap: _isSaving || _isUploading ? null : _publish,
      ),
    );
  }
}
