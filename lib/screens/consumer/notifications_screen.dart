import 'package:flutter/material.dart';
import '../../sb.dart';

/// B12 Notifikasi. Pola: LAYAR PENUH (Scaffold sendiri).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: ListenableBuilder(
          listenable: appState,
          builder: (context, _) {
            final notifs = appState.notifications;
            // Kelompokkan berdasarkan .group dengan mempertahankan urutan kemunculan.
            final groups = <String, List<AppNotification>>{};
            for (final n in notifs) {
              groups.putIfAbsent(n.group, () => []).add(n);
            }

            return Column(
              children: [
                SimpleHeader(
                  title: 'Notifikasi',
                  showBack: false,
                  titleSize: 24,
                  trailing: GestureDetector(
                    onTap: () {
                      appState.markAllNotificationsRead();
                      AppFeedback.snack(context, 'Semua ditandai dibaca');
                    },
                    child: Text(
                      'Tandai dibaca',
                      style: AppText.ui(13,
                          weight: 700, color: AppColors.greenBright),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: AppText.ui(12,
                                weight: 700,
                                color: AppColors.muted,
                                letterSpacing: 0.5),
                          ),
                        ),
                        for (final n in entry.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _notifCard(n),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _notifCard(AppNotification n) {
    final card = Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: n.unread ? AppColors.greenSoftBg : AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: n.unread ? AppColors.greenSoftBorder : AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBox(n.type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title,
                    style: AppText.ui(13.5, weight: 700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(n.body,
                    style: AppText.ui(12.5,
                        color: AppColors.body, height: 1.45)),
                const SizedBox(height: 5),
                Text(n.time,
                    style: AppText.ui(11.5, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );

    // Kartu yang sudah dibaca tampil sedikit redup.
    return n.unread ? card : Opacity(opacity: 0.85, child: card);
  }

  Widget _iconBox(NotifType type) {
    late final Color background;
    late final IconData icon;
    late final Color iconColor;
    switch (type) {
      case NotifType.ready:
        background = AppColors.greenBright;
        icon = Icons.check;
        iconColor = AppColors.white;
        break;
      case NotifType.newBag:
        background = AppColors.terracottaSoftBg;
        icon = Icons.shopping_bag_outlined;
        iconColor = AppColors.terracotta;
        break;
      case NotifType.rating:
        background = AppColors.ratingBg;
        icon = Icons.star;
        iconColor = AppColors.amber;
        break;
      case NotifType.payment:
        background = AppColors.greenSoftBg;
        icon = Icons.check_circle_outline;
        iconColor = AppColors.greenAccent;
        break;
    }
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
