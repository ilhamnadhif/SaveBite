import 'package:flutter/material.dart';
import '../../sb.dart';

/// Edit Profil konsumen. Pola: LAYAR PENUH (Scaffold sendiri) + bar bawah.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nameC =
      TextEditingController(text: appState.userName);
  late final TextEditingController emailC =
      TextEditingController(text: appState.userEmail);
  late final TextEditingController phoneC =
      TextEditingController(text: appState.userPhone);
  String? _avatarUrl = appState.userAvatarUrl;

  @override
  void dispose() {
    nameC.dispose();
    emailC.dispose();
    phoneC.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    final url = await appState.uploadImage(BackendBucket.avatar);
    if (url != null) setState(() => _avatarUrl = url);
  }

  Future<void> _save() async {
    await appState.updateProfile(
      name: nameC.text,
      email: emailC.text,
      phone: phoneC.text,
      avatarUrl: _avatarUrl,
    );
    if (!mounted) return;
    AppFeedback.snack(context, 'Profil disimpan');
    Navigator.of(context).maybePop();
  }

  Widget _field(TextEditingController controller, {TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
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

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            const SimpleHeader(title: 'Edit Profil'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                children: [
                  // Avatar + badge kamera.
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _avatarUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  _avatarUrl!,
                                  width: 84,
                                  height: 84,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Container(
                                width: 84,
                                height: 84,
                                decoration: const BoxDecoration(
                                  color: AppColors.amberAvatar,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(appState.userInitials,
                                    style: AppText.display(30,
                                        color: AppColors.green)),
                              ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.green,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppColors.cream, width: 2.5),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.photo_camera_outlined,
                                size: 14, color: AppColors.cream),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: _changePhoto,
                      behavior: HitTestBehavior.opaque,
                      child: Text('Ubah foto',
                          style: AppText.ui(13.5,
                              weight: 700, color: AppColors.greenAccent)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const FieldLabel('Nama'),
                  _field(nameC),
                  const SizedBox(height: 18),
                  const FieldLabel('Email'),
                  _field(emailC, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 18),
                  const FieldLabel('No. HP'),
                  _field(phoneC, keyboardType: TextInputType.phone),
                ],
              ),
            ),
            // Bar bawah.
            Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 14, 24, 14 + MediaQuery.of(context).padding.bottom),
              child: PrimaryButton(
                label: 'Simpan perubahan',
                onTap: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
