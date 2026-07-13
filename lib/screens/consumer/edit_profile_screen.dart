import 'package:flutter/material.dart';

import '../../data/backend/backend.dart';
import '../../sb.dart';

/// Edit profil konsumen dengan validasi, state unggah, dan penanganan error.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController = TextEditingController(
    text: appState.userName,
  );
  late final TextEditingController _emailController = TextEditingController(
    text: appState.userEmail,
  );
  late final TextEditingController _phoneController = TextEditingController(
    text: appState.userPhone,
  );
  String? _avatarUrl = appState.userAvatarUrl;
  bool _uploading = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Nama wajib diisi';
    if (name.length < 2) return 'Nama minimal 2 karakter';
    if (name.length > 80) return 'Nama maksimal 80 karakter';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email wajib diisi';
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    if (!valid) return 'Format email tidak valid';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) {
      return 'Nomor telepon harus 8–15 digit';
    }
    return null;
  }

  Future<void> _changePhoto() async {
    if (_uploading || _saving) return;
    setState(() => _uploading = true);
    try {
      final url = await appState.uploadImage(BackendBucket.avatar);
      if (url != null && mounted) setState(() => _avatarUrl = url);
    } on BackendException catch (error) {
      if (!mounted) return;
      AppFeedback.snack(context, error.message, icon: Icons.error_outline);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Foto gagal diunggah. Periksa koneksi lalu coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _uploading) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      AppFeedback.snack(
        context,
        'Periksa kembali data profil.',
        icon: Icons.error_outline,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final requestedEmail = _emailController.text.trim().toLowerCase();
      final emailChanged = requestedEmail != appState.userEmail.toLowerCase();
      await appState.updateProfile(
        name: _nameController.text.trim(),
        email: requestedEmail,
        phone: _phoneController.text.trim(),
        avatarUrl: _avatarUrl,
      );
      if (!mounted) return;
      AppFeedback.snack(
        context,
        emailChanged && appState.userEmail.toLowerCase() != requestedEmail
            ? 'Profil disimpan. Konfirmasi alamat email baru melalui tautan yang dikirim.'
            : 'Profil disimpan',
      );
      Navigator.of(context).pop(true);
    } on BackendException catch (error) {
      if (!mounted) return;
      AppFeedback.snack(context, error.message, icon: Icons.error_outline);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Profil gagal disimpan. Periksa koneksi lalu coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Edit Profil'),
            Expanded(
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                    children: [
                      Center(
                        child: Semantics(
                          button: true,
                          label: 'Ubah foto profil',
                          child: InkResponse(
                            onTap: _uploading || _saving ? null : _changePhoto,
                            radius: 50,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _avatar(),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: AppColors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.cream,
                                        width: 2.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: _uploading
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.cream,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.photo_camera_outlined,
                                            size: 15,
                                            color: AppColors.cream,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _uploading || _saving
                              ? null
                              : _changePhoto,
                          child: Text(
                            _uploading ? 'Mengunggah…' : 'Ubah foto',
                            style: AppText.ui(
                              13.5,
                              weight: 700,
                              color: AppColors.greenAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const FieldLabel('Nama'),
                      _field(
                        _nameController,
                        validator: _validateName,
                        capitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 18),
                      const FieldLabel('Email'),
                      _field(
                        _emailController,
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 18),
                      const FieldLabel('No. HP (opsional)'),
                      _field(
                        _phoneController,
                        validator: _validatePhone,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.cream,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: EdgeInsets.fromLTRB(
                24,
                14,
                24,
                14 + MediaQuery.of(context).padding.bottom,
              ),
              child: PrimaryButton(
                label: _saving ? 'Menyimpan…' : 'Simpan perubahan',
                onTap: _saving || _uploading ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    final url = _avatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _initialAvatar(),
        ),
      );
    }
    return _initialAvatar();
  }

  Widget _initialAvatar() {
    return Container(
      width: 84,
      height: 84,
      decoration: const BoxDecoration(
        color: AppColors.amberAvatar,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        appState.userInitials,
        style: AppText.display(30, color: AppColors.green),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    Iterable<String>? autofillHints,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_saving,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: AppText.ui(14.5, color: AppColors.ink),
      cursorColor: AppColors.greenBright,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(
            color: AppColors.inputBorder,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(
            color: AppColors.greenBright,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
    );
  }
}
