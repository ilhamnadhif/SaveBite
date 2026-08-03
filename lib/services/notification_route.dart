enum ConsumerOrdersTab { active, history }

enum MerchantOrdersTab { active, closed }

class ConsumerOrderNotificationTarget {
  const ConsumerOrderNotificationTarget({
    required this.orderId,
    this.preferredTab,
  });

  final String orderId;
  final ConsumerOrdersTab? preferredTab;
}

class MerchantOrderNotificationTarget {
  const MerchantOrderNotificationTarget({
    required this.orderId,
    this.preferredTab,
  });

  final String orderId;
  final MerchantOrdersTab? preferredTab;
}

const _terminalOrderRouteStatuses = <String>{
  'cancelled',
  'canceled',
  'complete',
  'completed',
  'disputed',
  'done',
  'expired',
  'failed',
  'payment-review',
  'redeemed',
  'refunded',
  'reviewed',
};

const _activeOrderRouteStatuses = <String>{
  'awaiting-payment',
  'new',
  'paid',
  'pending',
  'processing',
  'ready',
};

const _staticNotificationRoutes = <String>{
  'consumer_home',
  'home',
  'merchant_balance',
  'merchant_orders',
  'merchant_reviews',
  'orders',
};

final _notificationOrderIdPattern = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');

/// Membaca route notifikasi `order:<id>:<status>` tanpa menganggap status
/// route sebagai kebenaran akhir. Layar pesanan tetap mencocokkan ID ini
/// dengan data terbaru karena order dapat berubah setelah notifikasi dibuat.
ConsumerOrderNotificationTarget? parseConsumerOrderNotificationRoute(
  String? value,
) {
  final route = value?.trim() ?? '';
  final parts = route.split(':');
  if ((parts.length != 2 && parts.length != 3) ||
      parts.first.trim().toLowerCase() != 'order') {
    return null;
  }
  final orderId = parts[1].trim();
  if (orderId.isEmpty) return null;

  final status = parts.length > 2 ? parts[2].trim().toLowerCase() : '';
  final preferredTab = _terminalOrderRouteStatuses.contains(status)
      ? ConsumerOrdersTab.history
      : _activeOrderRouteStatuses.contains(status)
      ? ConsumerOrdersTab.active
      : null;
  return ConsumerOrderNotificationTarget(
    orderId: orderId,
    preferredTab: preferredTab,
  );
}

/// Membaca route notifikasi merchant `merchant-order:<id>:<status>`.
/// Suffix hanya menjadi petunjuk tab awal; layar tetap mencocokkan ID dengan
/// data order terbaru setelah refresh.
MerchantOrderNotificationTarget? parseMerchantOrderNotificationRoute(
  String? value,
) {
  final route = value?.trim() ?? '';
  final parts = route.split(':');
  if ((parts.length != 2 && parts.length != 3) ||
      parts.first.trim().toLowerCase() != 'merchant-order') {
    return null;
  }
  final orderId = parts[1].trim();
  if (orderId.isEmpty) return null;

  final status = parts.length > 2 ? parts[2].trim().toLowerCase() : '';
  final preferredTab = _terminalOrderRouteStatuses.contains(status)
      ? MerchantOrdersTab.closed
      : _activeOrderRouteStatuses.contains(status)
      ? MerchantOrdersTab.active
      : null;
  return MerchantOrderNotificationTarget(
    orderId: orderId,
    preferredTab: preferredTab,
  );
}

/// Dipakai bersama oleh navigasi dan listener realtime agar route lama dan
/// route merchant ber-ID selalu memicu pemuatan ulang data merchant.
bool isMerchantOrdersNotificationRoute(String? value) {
  final route = value?.trim() ?? '';
  return route.toLowerCase() == 'merchant_orders' ||
      parseMerchantOrderNotificationRoute(route) != null;
}

/// Mengizinkan hanya tujuan navigasi yang dikenal. Khusus nilai dari
/// `dedupe_key`, gunakan [dynamicOrderOnly] agar key arbitrer tidak pernah
/// berubah menjadi route aplikasi.
String? whitelistedNotificationRoute(
  String? value, {
  bool dynamicOrderOnly = false,
}) {
  final route = value?.trim() ?? '';
  if (route.isEmpty) return null;
  final normalized = route.toLowerCase();
  if (!dynamicOrderOnly && _staticNotificationRoutes.contains(normalized)) {
    return normalized;
  }

  final consumerTarget = parseConsumerOrderNotificationRoute(route);
  if (consumerTarget != null &&
      _notificationOrderIdPattern.hasMatch(consumerTarget.orderId)) {
    final parts = route.split(':');
    if (parts.length == 2 ||
        _activeOrderRouteStatuses.contains(parts[2].trim().toLowerCase()) ||
        _terminalOrderRouteStatuses.contains(parts[2].trim().toLowerCase())) {
      return route;
    }
  }

  final merchantTarget = parseMerchantOrderNotificationRoute(route);
  if (merchantTarget != null &&
      _notificationOrderIdPattern.hasMatch(merchantTarget.orderId)) {
    final parts = route.split(':');
    if (parts.length == 2 ||
        _activeOrderRouteStatuses.contains(parts[2].trim().toLowerCase()) ||
        _terminalOrderRouteStatuses.contains(parts[2].trim().toLowerCase())) {
      return route;
    }
  }
  return null;
}
