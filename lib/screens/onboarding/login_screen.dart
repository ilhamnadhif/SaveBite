import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../config/env.dart';
import '../../sb.dart';
import '../shared/legal_screen.dart';

/// Login OAuth. Peran dipersistenkan sebelum browser provider dibuka agar
/// redirect/deep-link tidak kehilangan tujuan pengguna.
class LoginScreen extends StatefulWidget {
  final bool merchant;

  const LoginScreen({super.key, required this.merchant});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _login(Future<bool> Function() provider) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await appState.setPendingMerchantIntent(widget.merchant);
      if (AuthService.isConfigured) {
        final opened = await provider();
        if (!opened && mounted) {
          setState(
            () => _error = 'Halaman login tidak dapat dibuka. Coba lagi.',
          );
        }
      } else {
        if (!mounted) return;
        await AppNav.completeLogin(context, merchant: widget.merchant);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Login gagal dimulai. Periksa koneksi lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showTestAccountLogin() async {
    if (!Env.e2eMode || _busy) return;

    final credentials = await showModalBottomSheet<_TestAccountCredentials>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _TestAccountLoginSheet(),
    );
    if (!mounted || credentials == null) return;
    await _login(
      () => AuthService.signInWithPassword(
        credentials.email,
        credentials.password,
      ),
    );
  }

  bool get _showApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, topInset + 16, 24, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Kembali',
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AppLogo(size: 72),
                      const SizedBox(height: 26),
                      Text(
                        'Tinggal selangkah lagi',
                        textAlign: TextAlign.center,
                        style: AppText.display(
                          26,
                          weight: 800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          widget.merchant
                              ? 'Masuk untuk menyiapkan toko dan menyelamatkan stok makananmu.'
                              : 'Masuk untuk menemukan dan memesan Surprise Bag di sekitarmu.',
                          textAlign: TextAlign.center,
                          style: AppText.ui(
                            15,
                            color: AppColors.body,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppText.ui(12.5, color: AppColors.danger),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _providerButton(
                  label: 'Lanjutkan dengan Google',
                  icon: _googleMark(),
                  onPressed: () => _login(AuthService.signInWithGoogle),
                ),
                if (_showApple) ...[
                  const SizedBox(height: 10),
                  _providerButton(
                    label: 'Lanjutkan dengan Apple',
                    icon: const Icon(
                      Icons.apple,
                      size: 25,
                      color: AppColors.ink,
                    ),
                    onPressed: () => _login(AuthService.signInWithApple),
                  ),
                ],
                if (Env.e2eMode) ...[
                  const SizedBox(height: 10),
                  _providerButton(
                    label: 'Masuk dengan akun pengujian',
                    icon: const Icon(
                      Icons.science_outlined,
                      size: 24,
                      color: AppColors.greenBright,
                    ),
                    onPressed: _showTestAccountLogin,
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Dengan masuk, kamu menyetujui ',
                      style: AppText.ui(11.5, color: AppColors.captionWarm),
                    ),
                    _legalLink('Ketentuan Layanan', LegalDocument.terms),
                    Text(
                      ' dan ',
                      style: AppText.ui(11.5, color: AppColors.captionWarm),
                    ),
                    _legalLink('Kebijakan Privasi', LegalDocument.privacy),
                    Text(
                      '.',
                      style: AppText.ui(11.5, color: AppColors.captionWarm),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _providerButton({
    required String label,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : onPressed,
        icon: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : icon,
        label: Text(label, style: AppText.ui(15.5, weight: 700)),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _legalLink(String label, LegalDocument document) {
    return InkWell(
      onTap: () => AppNav.toLegal(context, document: document),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          style: AppText.ui(11.5, weight: 700, color: AppColors.greenBright),
        ),
      ),
    );
  }

  Widget _googleMark() {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFEA4335),
            Color(0xFFFBBC05),
            Color(0xFF34A853),
            Color(0xFF4285F4),
            Color(0xFFEA4335),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _TestAccountCredentials {
  final String email;
  final String password;

  const _TestAccountCredentials(this.email, this.password);
}

class _TestAccountLoginSheet extends StatefulWidget {
  const _TestAccountLoginSheet();

  @override
  State<_TestAccountLoginSheet> createState() => _TestAccountLoginSheetState();
}

class _TestAccountLoginSheetState extends State<_TestAccountLoginSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.clear();
    _passwordController.clear();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _TestAccountCredentials(
        _emailController.text.trim(),
        _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.science_outlined,
                    color: AppColors.greenBright,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Masuk dengan akun pengujian',
                      style: AppText.ui(18, weight: 800, color: AppColors.ink),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Khusus pengujian E2E. Credential diisi saat pengujian dan '
                'tidak ditanam di source atau konfigurasi SaveBite.',
                style: AppText.ui(13, color: AppColors.body, height: 1.45),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('e2e-email-field'),
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[],
                decoration: const InputDecoration(
                  labelText: 'Email akun uji',
                  hintText: 'contoh@pengujian.local',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty || !email.contains('@')) {
                    return 'Masukkan email akun uji yang valid.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('e2e-password-field'),
                controller: _passwordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[],
                decoration: const InputDecoration(
                  labelText: 'Kata sandi akun uji',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Masukkan kata sandi akun uji.'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('e2e-submit-button'),
                onPressed: _submit,
                icon: const Icon(Icons.login),
                label: const Text('Masuk untuk pengujian'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
