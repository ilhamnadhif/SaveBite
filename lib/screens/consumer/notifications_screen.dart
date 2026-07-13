import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_nav.dart';
import '../../sb.dart';

/// Pusat notifikasi in-app. Realtime dikelola AppState; layar ini menangani
/// initial load, retry, empty state, dan tujuan saat kartu diketuk.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = false;
  bool _markingRead = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loading = appState.notifications.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    try {
      appState.clearError();
      await appState.loadNotifications();
      if (!mounted) return;
      setState(() => _error = appState.errorMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Notifikasi gagal dimuat. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingRead || appState.unreadCount == 0) return;
    setState(() => _markingRead = true);
    try {
      await appState.markAllNotificationsRead();
      if (!mounted) return;
      AppFeedback.snack(context, 'Semua notifikasi ditandai dibaca');
    } catch (_) {
      if (!mounted) return;
      AppFeedback.snack(
        context,
        'Status notifikasi gagal diperbarui. Coba lagi.',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _markingRead = false);
    }
  }

  void _openNotification(AppNotification notification) {
    AppNav.openNotification(context, notification);
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final notifications = appState.notifications;
            final groups = <String, List<AppNotification>>{};
            for (final notification in notifications) {
              groups
                  .putIfAbsent(notification.group, () => [])
                  .add(notification);
            }

            return Column(
              children: [
                SimpleHeader(
                  title: 'Notifikasi',
                  titleSize: 24,
                  trailing: appState.unreadCount == 0
                      ? null
                      : TextButton(
                          onPressed: _markingRead ? null : _markAllRead,
                          child: Text(
                            _markingRead ? 'Memproses…' : 'Tandai dibaca',
                            style: AppText.ui(
                              12.5,
                              weight: 700,
                              color: AppColors.greenBright,
                            ),
                          ),
                        ),
                ),
                Expanded(child: _body(groups, notifications.isEmpty)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(Map<String, List<AppNotification>> groups, bool isEmpty) {
    if (_loading && isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.greenBright),
      );
    }
    return RefreshIndicator(
      color: AppColors.greenBright,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null) ...[
            _NotificationError(message: _error!, onRetry: _load),
            const SizedBox(height: 14),
          ],
          if (isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 84),
              child: EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Belum ada notifikasi',
                message:
                    'Kabar pesanan dan Surprise Bag terbaru akan muncul di sini.',
              ),
            )
          else
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                child: Text(
                  entry.key.toUpperCase(),
                  style: AppText.ui(
                    12,
                    weight: 700,
                    color: AppColors.muted,
                    letterSpacing: .5,
                  ),
                ),
              ),
              for (final notification in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _notificationCard(notification),
                ),
            ],
        ],
      ),
    );
  }

  Widget _notificationCard(AppNotification notification) {
    final card = Material(
      color: notification.unread ? AppColors.greenSoftBg : AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openNotification(notification),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: notification.unread
                  ? AppColors.greenSoftBorder
                  : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBox(notification.type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: AppText.ui(
                        13.5,
                        weight: 700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: AppText.ui(
                        12.5,
                        color: AppColors.body,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.time,
                      style: AppText.ui(11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (notification.unread) ...[
                const SizedBox(width: 8),
                Semantics(
                  label: 'Belum dibaca',
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.greenBright,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return notification.unread ? card : Opacity(opacity: .88, child: card);
  }

  Widget _iconBox(NotifType type) {
    final (background, icon, iconColor) = switch (type) {
      NotifType.ready => (
        AppColors.greenBright,
        Icons.check_rounded,
        AppColors.white,
      ),
      NotifType.newBag => (
        AppColors.terracottaSoftBg,
        Icons.shopping_bag_outlined,
        AppColors.terracotta,
      ),
      NotifType.rating => (
        AppColors.ratingBg,
        Icons.star_rounded,
        AppColors.amber,
      ),
      NotifType.payment => (
        AppColors.greenSoftBg,
        Icons.check_circle_outline,
        AppColors.greenAccent,
      ),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: iconColor),
    );
  }
}

class _NotificationError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _NotificationError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppText.ui(12.5, color: AppColors.body, height: 1.4),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
