import 'dart:async';

import 'package:flutter/material.dart';
import '../../sb.dart';

/// C5 Scan & Redeem QR. Pola: LAYAR PENUH (Scaffold sendiri).
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key, this.code});

  final String? code;

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _scanTimer;
  bool _scanned = false;
  IncomingOrder? _redeemed;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scanTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted && !_scanned) _doRedeem();
    });
  }

  Future<void> _doRedeem() async {
    if (_scanned) return;
    final redeemed = await appState.redeemOrder(widget.code ?? '');
    if (!mounted) return;
    setState(() {
      _scanned = true;
      _redeemed = redeemed;
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: AppColors.scanBg,
        body: Column(
          children: [
            // Header (status-bar inset + 16 ≈ 58 dari desain)
            Padding(
              padding: EdgeInsets.fromLTRB(20, topInset + 16, 20, 14),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(false),
                    child: const Icon(Icons.close,
                        size: 22, color: AppColors.white),
                  ),
                  const SizedBox(width: 14),
                  Text('Scan QR konsumen',
                      style: AppText.display(18,
                          weight: 700, color: AppColors.white)),
                ],
              ),
            ),
            // Tengah: frame scanner + instruksi
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _scannerFrame(),
                    const SizedBox(height: 26),
                    Text(
                      'Arahkan kamera ke QR di layar pembeli.',
                      textAlign: TextAlign.center,
                      style: AppText.ui(14, color: AppColors.scanMuted),
                    ),
                    if (!_scanned) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _doRedeem,
                        child: Text(
                          'Simulasikan pemindaian',
                          textAlign: TextAlign.center,
                          style: AppText.ui(13,
                              weight: 600, color: AppColors.greenBright),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Bawah: kartu sukses (setelah ter-scan) / hint
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 34 + bottomInset),
              child: _scanned
                  ? Column(
                      children: [
                        _successCard(),
                        const SizedBox(height: 14),
                        PrimaryButton.merchant(
                          label: 'Selesai',
                          onTap: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    )
                  : Text(
                      'Menunggu QR…',
                      textAlign: TextAlign.center,
                      style: AppText.ui(13, color: AppColors.scanMuted),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scannerFrame() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Latar bergaris diagonal
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: 240,
              height: 240,
              child: CustomPaint(painter: _StripePainter()),
            ),
          ),
          // Empat sudut amber
          _corner(top: -2, left: -2, topB: true, leftB: true),
          _corner(top: -2, right: -2, topB: true, rightB: true),
          _corner(bottom: -2, left: -2, bottomB: true, leftB: true),
          _corner(bottom: -2, right: -2, bottomB: true, rightB: true),
          // Garis scan animasi vertikal
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              // gerak di antara y=14 dan y=240-14 (mengikuti inset left/right:14px)
              final t = _controller.value;
              final y = 14 + t * (240 - 28);
              return Positioned(
                left: 14,
                right: 14,
                top: y,
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: AppColors.greenBright,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.greenBright,
                        blurRadius: 12,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              );
            },
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
    bool topB = false,
    bool bottomB = false,
    bool leftB = false,
    bool rightB = false,
  }) {
    const side = BorderSide(color: AppColors.amber, width: 4);
    BorderRadius radius;
    if (topB && leftB) {
      radius = const BorderRadius.only(topLeft: Radius.circular(14));
    } else if (topB && rightB) {
      radius = const BorderRadius.only(topRight: Radius.circular(14));
    } else if (bottomB && leftB) {
      radius = const BorderRadius.only(bottomLeft: Radius.circular(14));
    } else {
      radius = const BorderRadius.only(bottomRight: Radius.circular(14));
    }
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border(
            top: topB ? side : BorderSide.none,
            bottom: bottomB ? side : BorderSide.none,
            left: leftB ? side : BorderSide.none,
            right: rightB ? side : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _successCard() {
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
                    _redeemed != null
                        ? '${_redeemed!.code} berhasil di-redeem'
                        : 'QR berhasil di-redeem',
                    style: AppText.ui(14, weight: 700, color: AppColors.white)),
                const SizedBox(height: 2),
                Text(
                    _redeemed != null
                        ? '${_redeemed!.customer} · baru saja · ${_redeemed!.bags} bag'
                        : 'Order masuk saldo',
                    style: AppText.ui(12, color: AppColors.scanMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Garis diagonal 135° untuk latar frame scanner (mengikuti
/// repeating-linear-gradient(135deg, #1B221D 0–12px, #222a24 12–24px)).
class _StripePainter extends CustomPainter {
  const _StripePainter();

  static const _a = AppColors.scanCard; // #1B221D
  static const _b = Color(0xFF222A24); // #222a24

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _a);
    final paint = Paint()
      ..color = _b
      ..style = PaintingStyle.fill;
    const stripe = 12.0;
    final reach = size.width + size.height;
    // garis 135° → tegak lurus arah (1,1); offset diukur sepanjang (1,-1)/... ;
    // gambar pita berselang dengan menggeser sepanjang sumbu diagonal.
    for (double d = -reach; d < reach; d += stripe * 2) {
      final path = Path()
        ..moveTo(d, 0)
        ..lineTo(d + stripe, 0)
        ..lineTo(d + stripe + size.height, size.height)
        ..lineTo(d + size.height, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
