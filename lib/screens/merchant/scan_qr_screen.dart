import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../config/env.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';

/// Scanner pickup merchant. [code] dipertahankan agar route lama kompatibel,
/// tetapi sengaja tidak pernah digunakan untuk redeem: token wajib berasal
/// dari QR yang benar-benar dibaca kamera.
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key, this.code});

  final String? code;

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  late final MobileScannerController _scannerController =
      MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
        facing: CameraFacing.back,
        autoZoom: true,
      );

  bool _busy = false;
  IncomingOrder? _redeemed;
  String? _message;
  String? _lastRejectedValue;

  bool get _completed => _redeemed != null;

  @override
  void dispose() {
    unawaited(_scannerController.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: AppColors.scanBg,
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(14, topInset + 8, 14, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Tutup scanner',
                    onPressed: () => Navigator.of(context).pop(_completed),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Scan QR konsumen',
                      style: AppText.display(
                        18,
                        weight: 700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _scannerController,
                    builder: (context, state, _) {
                      if (state.torchState == TorchState.unavailable ||
                          _completed) {
                        return const SizedBox(width: 48);
                      }
                      final on = state.torchState == TorchState.on;
                      return IconButton(
                        tooltip: on ? 'Matikan senter' : 'Nyalakan senter',
                        onPressed: _busy
                            ? null
                            : () => _scannerController.toggleTorch(),
                        icon: Icon(
                          on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: on ? AppColors.amber : AppColors.white,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(
                  children: [
                    if (_completed)
                      _completedIllustration()
                    else
                      _scannerFrame(),
                    const SizedBox(height: 24),
                    Text(
                      _completed
                          ? 'Pickup berhasil dikonfirmasi'
                          : _busy
                          ? 'Memverifikasi pesanan…'
                          : 'Arahkan kamera ke QR di layar pembeli.',
                      textAlign: TextAlign.center,
                      style: AppText.ui(
                        14,
                        weight: _completed ? 700 : 500,
                        color: _completed
                            ? AppColors.white
                            : AppColors.scanMuted,
                      ),
                    ),
                    if (Env.e2eMode && !_completed && !_busy) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        key: const ValueKey('e2e-scanned-token-button'),
                        onPressed: _showE2eScannedTokenInput,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.amber,
                        ),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Masukkan hasil scan staging'),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      _messageCard(_message!),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + bottomInset),
              child: _completed
                  ? Column(
                      children: [
                        _successCard(_redeemed!),
                        const SizedBox(height: 14),
                        PrimaryButton.merchant(
                          label: 'Selesai',
                          onTap: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: AppColors.scanMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Token pickup divalidasi aman oleh server.',
                            textAlign: TextAlign.center,
                            style: AppText.ui(12, color: AppColors.scanMuted),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scannerFrame() {
    return Semantics(
      label: 'Area kamera untuk memindai QR pickup konsumen',
      child: SizedBox(
        width: 280,
        height: 280,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: MobileScanner(
                controller: _scannerController,
                fit: BoxFit.cover,
                tapToFocus: true,
                onDetect: _onDetect,
                onDetectError: (error, _) {
                  if (!mounted || _busy) return;
                  setState(() {
                    _message =
                        'QR belum dapat dibaca. Coba arahkan ulang kamera.';
                  });
                },
                placeholderBuilder: (_) => const ColoredBox(
                  color: AppColors.scanCard,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.greenBright,
                    ),
                  ),
                ),
                errorBuilder: (context, error) => _cameraError(error),
              ),
            ),
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.scanCardBorder),
                ),
              ),
            ),
            _corner(top: -1, left: -1, topBorder: true, leftBorder: true),
            _corner(top: -1, right: -1, topBorder: true, rightBorder: true),
            _corner(bottom: -1, left: -1, bottomBorder: true, leftBorder: true),
            _corner(
              bottom: -1,
              right: -1,
              bottomBorder: true,
              rightBorder: true,
            ),
            if (_busy)
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: ColoredBox(
                  color: const Color(0x99101B16),
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.amber),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cameraError(MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: AppColors.scanCard,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              denied
                  ? Icons.no_photography_outlined
                  : Icons.camera_alt_outlined,
              size: 42,
              color: AppColors.scanMuted,
            ),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Izin kamera diperlukan untuk scan QR.'
                  : 'Kamera belum dapat digunakan.',
              textAlign: TextAlign.center,
              style: AppText.ui(13, color: AppColors.white, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: denied
                  ? kIsWeb
                        ? _showWebCameraPermissionHelp
                        : appState.openAppSettings
                  : () => _restartScanner(clearMessage: true),
              style: TextButton.styleFrom(foregroundColor: AppColors.amber),
              child: Text(
                denied
                    ? kIsWeb
                          ? 'Cara mengizinkan'
                          : 'Buka pengaturan'
                    : 'Coba lagi',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWebCameraPermissionHelp() {
    setState(() {
      _message =
          'Izinkan kamera dari ikon izin di bilah alamat browser, lalu muat '
          'ulang halaman dan buka scanner kembali.';
    });
  }

  Widget _completedIllustration() {
    return Container(
      width: 150,
      height: 150,
      decoration: const BoxDecoration(
        color: AppColors.greenBright,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, size: 78, color: AppColors.white),
    );
  }

  Widget _messageCard(String message) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.danger.withAlpha(28),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.danger.withAlpha(100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: AppText.ui(12.5, color: AppColors.white, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successCard(IncomingOrder order) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.scanCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.scanCardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.greenBright,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 22, color: AppColors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pesanan berhasil di-redeem',
                  style: AppText.ui(14, weight: 700, color: AppColors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.customer} · ${order.bags} bag'
                  '${order.bagTitle.isEmpty ? '' : ' · ${order.bagTitle}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.ui(12, color: AppColors.scanMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner({
    double? top,
    double? bottom,
    double? left,
    double? right,
    bool topBorder = false,
    bool bottomBorder = false,
    bool leftBorder = false,
    bool rightBorder = false,
  }) {
    const side = BorderSide(color: AppColors.amber, width: 4);
    final radius = BorderRadius.only(
      topLeft: topBorder && leftBorder
          ? const Radius.circular(18)
          : Radius.zero,
      topRight: topBorder && rightBorder
          ? const Radius.circular(18)
          : Radius.zero,
      bottomLeft: bottomBorder && leftBorder
          ? const Radius.circular(18)
          : Radius.zero,
      bottomRight: bottomBorder && rightBorder
          ? const Radius.circular(18)
          : Radius.zero,
    );
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border(
              top: topBorder ? side : BorderSide.none,
              bottom: bottomBorder ? side : BorderSide.none,
              left: leftBorder ? side : BorderSide.none,
              right: rightBorder ? side : BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy || _completed) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      final token = _extractPickupToken(raw);
      if (token == null) {
        if (_lastRejectedValue == raw) return;
        _lastRejectedValue = raw;
        setState(() {
          _message = 'QR ini bukan voucher pickup SaveBite yang valid.';
        });
        return;
      }
      unawaited(_redeem(token));
      return;
    }
  }

  Future<void> _showE2eScannedTokenInput() async {
    if (!Env.e2eMode || _busy || _completed) return;
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hasil scan QR staging'),
        content: TextField(
          key: const ValueKey('e2e-scanned-token-field'),
          controller: controller,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Token hasil decode QR'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const ValueKey('e2e-scanned-token-submit'),
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Verifikasi'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || raw == null || raw.isEmpty) return;
    final token = _extractPickupToken(raw);
    if (token == null) {
      setState(() {
        _message = 'QR ini bukan voucher pickup SaveBite yang valid.';
      });
      return;
    }
    await _redeem(token);
  }

  String? _extractPickupToken(String raw) {
    if (raw.length < 6 || raw.length > 512 || raw.contains(RegExp(r'\s'))) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      final queryToken = uri.queryParameters['token'];
      if (queryToken != null &&
          queryToken.length >= 6 &&
          queryToken.length <= 512) {
        return queryToken;
      }
      if (uri.scheme.toLowerCase() == 'savebite' &&
          uri.pathSegments.isNotEmpty) {
        final candidate = uri.pathSegments.last;
        if (candidate.length >= 6) return candidate;
      }
      return null;
    }
    return raw;
  }

  Future<void> _redeem(String token) async {
    if (_busy || _completed) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      try {
        await _scannerController.stop();
      } catch (_) {
        // Redeem server tetap aman saat kamera sudah berhenti/tidak tersedia.
      }
      final order = await appState.redeemOrder(token);
      if (!mounted) return;
      if (order == null) {
        setState(() {
          _busy = false;
          _message =
              'Voucher tidak ditemukan, sudah dipakai, atau bukan milik toko ini.';
        });
        await _restartScanner();
        return;
      }
      setState(() {
        _busy = false;
        _redeemed = order;
        _message = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error is BackendException
            ? error.message
            : 'Voucher belum dapat diverifikasi. Coba lagi.';
      });
      await _restartScanner();
    }
  }

  Future<void> _restartScanner({bool clearMessage = false}) async {
    if (!mounted || _completed) return;
    if (clearMessage) setState(() => _message = null);
    _lastRejectedValue = null;
    try {
      await _scannerController.start();
    } catch (_) {
      // MobileScanner menampilkan error kamera melalui errorBuilder.
    }
  }
}
