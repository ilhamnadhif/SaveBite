import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../data/backend/backend.dart';
import '../../sb.dart';

/// Detail operasional pesanan. Pickup token sengaja tidak dirender di layar
/// merchant; kasir wajib memindai QR milik konsumen.
class OrderDetailScreen extends StatefulWidget {
  final IncomingOrder order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final order = _currentOrder;
        return StatusBarStyle.dark(
          child: Scaffold(
            backgroundColor: AppColors.cream,
            body: Column(
              children: [
                const SimpleHeader(title: 'Detail Pesanan'),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.terracotta,
                    onRefresh: appState.loadMerchantData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                      children: [
                        _customerCard(order),
                        const SizedBox(height: 18),
                        const SectionHeading(title: 'Item pesanan'),
                        const SizedBox(height: 11),
                        _itemCard(order),
                        const SizedBox(height: 18),
                        const SectionHeading(title: 'Jadwal pickup'),
                        const SizedBox(height: 11),
                        _pickupCard(order),
                        const SizedBox(height: 18),
                        const SectionHeading(title: 'Rincian pembayaran'),
                        const SizedBox(height: 11),
                        _paymentCard(order),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: AppColors.neutralChip,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.security_rounded,
                                size: 18,
                                color: AppColors.body,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  'Kode dan token pickup hanya ada di perangkat '
                                  'pembeli. Gunakan scanner untuk mencegah '
                                  'redeem tanpa izin.',
                                  style: AppText.ui(
                                    12,
                                    color: AppColors.body,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _bottomBar(context, order),
              ],
            ),
          ),
        );
      },
    );
  }

  IncomingOrder get _currentOrder {
    final all = [...appState.pendingOrders, ...appState.completedOrders];
    for (final candidate in all) {
      if (widget.order.id.isNotEmpty && candidate.id == widget.order.id) {
        return candidate;
      }
      if (widget.order.id.isEmpty &&
          candidate.customer == widget.order.customer &&
          candidate.time == widget.order.time &&
          candidate.bags == widget.order.bags) {
        return candidate;
      }
    }
    return widget.order;
  }

  Widget _customerCard(IncomingOrder order) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.terracottaSoftBg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              order.initial,
              style: AppText.display(17, weight: 800, color: AppColors.brown),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customer,
                  style: AppText.ui(14.5, weight: 700, color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_reference(order)} · ${order.time}',
                  style: AppText.ui(12, color: AppColors.muted),
                ),
                if (order.createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _dateTimeLabel(order.createdAt!),
                    style: AppText.ui(11.5, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusBadge(order.status),
        ],
      ),
    );
  }

  Widget _itemCard(IncomingOrder order) {
    final subtotal = _subtotal(order);
    return AppCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FoodImage(
              order.bagImage.isEmpty ? SampleData.img1 : order.bagImage,
              width: 58,
              height: 58,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.bagTitle.isEmpty ? 'Surprise Bag' : order.bagTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.ui(14, weight: 700, color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  '${order.bags} bag'
                  '${order.unitPrice > 0 ? ' × ${formatRupiah(order.unitPrice)}' : ''}',
                  style: AppText.ui(12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            subtotal > 0 ? formatRupiah(subtotal) : '—',
            style: AppText.ui(14, weight: 700, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _pickupCard(IncomingOrder order) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_outlined,
                size: 19,
                color: AppColors.terracotta,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.pickupWindow.isEmpty
                      ? 'Jadwal pickup belum tersedia'
                      : order.pickupWindow,
                  style: AppText.ui(13.5, weight: 700, color: AppColors.ink),
                ),
              ),
            ],
          ),
          if (order.expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Berlaku sampai ${_dateTimeLabel(order.expiresAt!)}',
              style: AppText.ui(12, color: AppColors.body),
            ),
          ],
          if (order.redeemedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Diambil ${_dateTimeLabel(order.redeemedAt!)}',
              style: AppText.ui(12, weight: 700, color: AppColors.greenAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentCard(IncomingOrder order) {
    final subtotal = _subtotal(order);
    final net = order.merchantNetAmount;
    final platformFee = subtotal > 0 && net > 0
        ? (subtotal - net).clamp(0, subtotal)
        : 0;
    return AppCard(
      child: Column(
        children: [
          _line('Subtotal item', subtotal > 0 ? formatRupiah(subtotal) : '—'),
          if (order.serviceFee > 0) ...[
            const SizedBox(height: 11),
            _line('Biaya layanan pembeli', formatRupiah(order.serviceFee)),
          ],
          const SizedBox(height: 11),
          _line(
            'Biaya platform merchant',
            platformFee > 0 ? '−${formatRupiah(platformFee)}' : '—',
          ),
          const SizedBox(height: 13),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 13),
          _line(
            'Masuk saldo',
            net > 0 ? formatRupiah(net) : '—',
            valueColor: AppColors.greenAccent,
            bold: true,
          ),
          if (order.status != IncomingOrderStatus.redeemed) ...[
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Saldo dicatat setelah pickup berhasil di-redeem.',
                style: AppText.ui(11.5, color: AppColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppText.ui(
              13.5,
              weight: bold ? 700 : 500,
              color: bold ? AppColors.ink : AppColors.body,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.end,
          style: AppText.ui(
            14,
            weight: bold ? 800 : 600,
            color: valueColor ?? AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, IncomingOrder order) {
    final status = order.status;
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
        18 + MediaQuery.paddingOf(context).bottom,
      ),
      child: switch (status) {
        IncomingOrderStatus.paid || IncomingOrderStatus.preparing => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton.merchant(
              label: _busy ? 'Menyimpan…' : 'Tandai siap diambil',
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: AppColors.white,
                    ),
              onTap: _busy || order.id.isEmpty ? null : () => _markReady(order),
            ),
            const SizedBox(height: 9),
            _cancelButton(order),
          ],
        ),
        IncomingOrderStatus.ready => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton.merchant(
              label: 'Scan QR untuk redeem',
              icon: const Icon(
                Icons.qr_code_scanner_rounded,
                size: 20,
                color: AppColors.white,
              ),
              onTap: _busy ? null : () => AppNav.toScanQr(context),
            ),
            const SizedBox(height: 9),
            _cancelButton(order),
          ],
        ),
        IncomingOrderStatus.redeemed => _statusMessage(
          Icons.check_circle_rounded,
          'Pesanan sudah diambil',
          AppColors.greenAccent,
        ),
        IncomingOrderStatus.pending => _statusMessage(
          Icons.schedule_rounded,
          'Menunggu pembayaran pembeli',
          AppColors.muted,
        ),
        IncomingOrderStatus.cancelled => _statusMessage(
          Icons.cancel_outlined,
          'Pesanan dibatalkan',
          AppColors.danger,
        ),
        IncomingOrderStatus.expired => _statusMessage(
          Icons.timer_off_outlined,
          'Masa pickup sudah berakhir',
          AppColors.danger,
        ),
      },
    );
  }

  Widget _statusMessage(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Text(text, style: AppText.ui(14, weight: 700, color: color)),
        ],
      ),
    );
  }

  Widget _cancelButton(IncomingOrder order) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _busy || order.id.isEmpty ? null : () => _cancelOrder(order),
        icon: const Icon(Icons.cancel_outlined, size: 19),
        label: const Text('Batalkan pesanan'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
        ),
      ),
    );
  }

  Widget _statusBadge(IncomingOrderStatus status) {
    return switch (status) {
      IncomingOrderStatus.pending => StatusBadge.waiting('Menunggu bayar'),
      IncomingOrderStatus.paid => StatusBadge(
        text: 'Baru',
        background: AppColors.terracottaSoftBg,
        foreground: AppColors.brown,
      ),
      IncomingOrderStatus.preparing => StatusBadge(
        text: 'Disiapkan',
        background: AppColors.terracottaSoftBg,
        foreground: AppColors.brown,
      ),
      IncomingOrderStatus.ready => StatusBadge.available('Siap'),
      IncomingOrderStatus.redeemed => StatusBadge.done('Selesai'),
      IncomingOrderStatus.cancelled => StatusBadge.expired('Dibatalkan'),
      IncomingOrderStatus.expired => StatusBadge.expired('Kedaluwarsa'),
    };
  }

  Future<void> _markReady(IncomingOrder order) async {
    if (_busy || order.id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await appState.markOrderReady(order.id);
      if (mounted) {
        AppFeedback.snack(
          context,
          'Pesanan ditandai siap diambil.',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        error is BackendException
            ? error.message
            : 'Status pesanan belum dapat diperbarui.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelOrder(IncomingOrder order) async {
    if (_busy || order.id.isEmpty) return;
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Batalkan pesanan?',
      message:
          'Midtrans akan membatalkan atau mengembalikan pembayaran untuk '
          '${_reference(order)}. Stok ${order.bags} bag baru dikembalikan '
          'setelah provider mengonfirmasi. Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Batalkan pesanan',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await appState.cancelMerchantOrder(order.id);
      if (mounted) {
        AppFeedback.snack(
          context,
          'Pembatalan/refund telah dikonfirmasi Midtrans untuk diproses. Stok telah '
          'dikembalikan; waktu dana masuk mengikuti metode pembayaran.',
          icon: Icons.inventory_2_outlined,
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        error is BackendException
            ? error.message
            : 'Pesanan belum dapat dibatalkan.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _subtotal(IncomingOrder order) {
    if (order.subtotalAmount > 0) return order.subtotalAmount;
    return order.unitPrice > 0 ? order.unitPrice * order.bags : 0;
  }

  String _reference(IncomingOrder order) {
    if (order.id.isEmpty) return 'Pesanan baru';
    final clean = order.id.replaceAll('-', '');
    final suffix = clean.length <= 6
        ? clean
        : clean.substring(clean.length - 6);
    return 'Order #${suffix.toUpperCase()}';
  }

  String _dateTimeLabel(DateTime value) {
    final local = value.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $hour.$minute';
  }
}
