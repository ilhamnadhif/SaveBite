import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';

/// Voucher pickup menggunakan token berumur pendek dari backend. Kode referensi
/// pesanan tidak pernah dipakai sebagai payload QR.
class VoucherScreen extends StatefulWidget {
  final OrderRecord order;

  const VoucherScreen({super.key, required this.order});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  late OrderRecord _order = widget.order;
  Timer? _timer;
  DateTime? _tokenRefreshAt;
  bool _loadingToken = false;
  String? _tokenError;

  DateTime? get _expiresAt => _order.expiresAt ?? _order.bag.pickupEndsAt;

  bool get _pastExpiry {
    final expiresAt = _expiresAt;
    return expiresAt != null && !expiresAt.isAfter(DateTime.now());
  }

  bool get _redeemed => _order.status == OrderStatus.done;
  bool get _cancelled => _order.status == OrderStatus.cancelled;
  bool get _expired => _order.status == OrderStatus.expired || _pastExpiry;
  bool get _canShowQr =>
      _order.status == OrderStatus.ready &&
      !_redeemed &&
      !_cancelled &&
      !_expired;

  @override
  void initState() {
    super.initState();
    appState.addListener(_syncOrderFromState);
    _startClock();
    if (_canShowQr) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rotateToken());
    }
  }

  void _startClock() {
    if (_expiresAt == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final refreshAt = _tokenRefreshAt;
      if (_canShowQr &&
          _order.pickupToken != null &&
          refreshAt != null &&
          !refreshAt.isAfter(DateTime.now())) {
        unawaited(_rotateToken());
      }
      if (_pastExpiry) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    appState.removeListener(_syncOrderFromState);
    _timer?.cancel();
    super.dispose();
  }

  void _syncOrderFromState() {
    OrderRecord? latest;
    for (final order in [...appState.activeOrders, ...appState.orderHistory]) {
      if (order.id == _order.id) {
        latest = order;
        break;
      }
    }
    if (!mounted || latest == null) return;

    final becameReady = !_canShowQr && latest.status == OrderStatus.ready;
    final terminal =
        latest.status == OrderStatus.done ||
        latest.status == OrderStatus.cancelled ||
        latest.status == OrderStatus.expired;
    final synced =
        latest.status == OrderStatus.ready &&
            latest.pickupToken == null &&
            _order.pickupToken != null
        ? latest.copyWith(pickupToken: _order.pickupToken)
        : latest;

    setState(() {
      _order = terminal ? synced.copyWith(clearPickupToken: true) : synced;
      if (terminal) {
        _tokenError = null;
        _tokenRefreshAt = null;
      }
    });
    if (terminal) {
      _timer?.cancel();
    } else if (_timer == null || !_timer!.isActive) {
      _startClock();
    }
    if (becameReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rotateToken());
    }
  }

  Future<void> _rotateToken() async {
    if (_loadingToken || !_canShowQr) return;
    setState(() {
      _loadingToken = true;
      _tokenError = null;
    });
    try {
      final refreshed = await appState.issuePickupToken(_order);
      if (!mounted) return;
      setState(() {
        _order = refreshed;
        _tokenRefreshAt = DateTime.now().add(const Duration(seconds: 60));
      });
    } on BackendException catch (error) {
      if (!mounted) return;
      setState(() => _tokenError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tokenError = 'QR pickup gagal dimuat. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted) setState(() => _loadingToken = false);
    }
  }

  String get _remainingLabel {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return 'Ikuti jadwal pickup merchant';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return 'Waktu pengambilan berakhir';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    if (hours >= 24) {
      final days = remaining.inDays;
      return '$days hari ${hours.remainder(24)} jam lagi';
    }
    if (hours > 0) return '$hours jam $minutes menit lagi';
    return '$minutes menit ${seconds.toString().padLeft(2, '0')} detik lagi';
  }

  String get _deadlineLabel {
    final expiresAt = _expiresAt?.toLocal();
    if (expiresAt == null) return _order.bag.pickupWindow;
    final now = DateTime.now();
    final sameDay =
        expiresAt.year == now.year &&
        expiresAt.month == now.month &&
        expiresAt.day == now.day;
    final hour = expiresAt.hour.toString().padLeft(2, '0');
    final minute = expiresAt.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Hari ini pukul $hour.$minute';
    return '${expiresAt.day}/${expiresAt.month}/${expiresAt.year} pukul $hour.$minute';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return StatusBarStyle.light(
      child: Scaffold(
        backgroundColor: AppColors.green,
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            24,
            topInset + 16,
            24,
            32 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            _statusIcon(),
            const SizedBox(height: 14),
            Text(
              _title,
              textAlign: TextAlign.center,
              style: AppText.display(23, weight: 800, color: AppColors.cream),
            ),
            const SizedBox(height: 5),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: AppText.ui(
                13.5,
                color: AppColors.greenMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            _ticketCard(),
            const SizedBox(height: 18),
            _timePill(),
            const SizedBox(height: 18),
            GhostButton(
              label: 'Lihat pesanan saya',
              color: AppColors.greenMuted,
              onTap: () => AppNav.toOrders(context),
            ),
          ],
        ),
      ),
    );
  }

  String get _title {
    if (_redeemed) return 'Pesanan sudah diambil';
    if (_cancelled) return 'Pesanan dibatalkan';
    if (_expired) return 'Voucher kedaluwarsa';
    if (_order.status == OrderStatus.pending) return 'Pesanan sedang diproses';
    return 'Pesanan siap diambil!';
  }

  String get _subtitle {
    if (_redeemed) {
      return 'QR sudah dipindai dan tidak dapat digunakan kembali.';
    }
    if (_cancelled) return 'QR pickup dinonaktifkan untuk pesanan ini.';
    if (_expired) {
      return 'Waktu pengambilan telah berakhir dan QR dinonaktifkan.';
    }
    if (_order.status == OrderStatus.pending) {
      return 'QR akan tersedia setelah pesanan siap diambil.';
    }
    return 'Tunjukkan QR aktif ini kepada kasir saat mengambil bag.';
  }

  Widget _statusIcon() {
    final terminalProblem = _cancelled || _expired;
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: terminalProblem ? AppColors.danger : AppColors.greenBright,
          shape: BoxShape.circle,
        ),
        child: Icon(
          terminalProblem
              ? Icons.close_rounded
              : _redeemed
              ? Icons.done_all_rounded
              : Icons.check_rounded,
          size: 34,
          color: AppColors.white,
        ),
      ),
    );
  }

  Widget _ticketCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _qrContent(),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 16),
            color: AppColors.border,
          ),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: FoodImage(_order.bag.image, width: 42, height: 42),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _order.bag.merchant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(14, weight: 700, color: AppColors.ink),
                    ),
                    Text(
                      '${_order.quantity}× ${_order.bag.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.ui(12.5, color: AppColors.body),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Referensi pesanan',
                style: AppText.ui(11.5, color: AppColors.muted),
              ),
              Text(
                _order.code,
                style: AppText.ui(12, weight: 700, color: AppColors.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qrContent() {
    if (!_canShowQr) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.neutralChip,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(
              _redeemed ? Icons.qr_code_2_rounded : Icons.block_rounded,
              size: 64,
              color: AppColors.muted,
            ),
            const SizedBox(height: 10),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: AppText.ui(12.5, color: AppColors.body, height: 1.45),
            ),
          ],
        ),
      );
    }
    if (_loadingToken) {
      return const SizedBox(
        height: 216,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.greenBright),
        ),
      );
    }
    if (_tokenError != null) {
      return SizedBox(
        height: 216,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.qr_code_scanner_rounded,
              size: 54,
              color: AppColors.muted,
            ),
            const SizedBox(height: 10),
            Text(
              _tokenError!,
              textAlign: TextAlign.center,
              style: AppText.ui(12.5, color: AppColors.body, height: 1.45),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _rotateToken, child: const Text('Coba lagi')),
          ],
        ),
      );
    }
    final token = _order.pickupToken;
    if (token == null || token.isEmpty) {
      return SizedBox(
        height: 216,
        child: Center(
          child: TextButton(
            onPressed: _rotateToken,
            child: const Text('Muat QR pickup'),
          ),
        ),
      );
    }
    return Column(
      children: [
        Semantics(
          label: 'QR pickup aktif untuk pesanan ${_order.code}',
          child: QrBox(data: token, size: 190),
        ),
        const SizedBox(height: 9),
        Text(
          'Demi keamanan, QR diperbarui otomatis setiap 60 detik.',
          textAlign: TextAlign.center,
          style: AppText.ui(10.8, color: AppColors.muted, height: 1.4),
        ),
        TextButton.icon(
          onPressed: _loadingToken ? null : _rotateToken,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Perbarui QR'),
        ),
      ],
    );
  }

  Widget _timePill() {
    final warning = _expired || _cancelled;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: warning ? AppColors.dangerBg : AppColors.greenDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  warning ? Icons.event_busy_outlined : Icons.schedule,
                  size: 16,
                  color: warning ? AppColors.danger : AppColors.amber,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    warning ? _remainingLabel : 'Batas: $_deadlineLabel',
                    textAlign: TextAlign.center,
                    style: AppText.ui(
                      13,
                      weight: 700,
                      color: warning ? AppColors.danger : AppColors.goldOnDark,
                    ),
                  ),
                ),
              ],
            ),
            if (!warning && _expiresAt != null) ...[
              const SizedBox(height: 3),
              Text(
                _remainingLabel,
                style: AppText.ui(11.5, color: AppColors.greenMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
