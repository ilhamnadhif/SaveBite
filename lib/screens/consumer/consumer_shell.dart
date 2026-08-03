import 'dart:async';

import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../services/notification_route.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'orders_screen.dart';
import 'favorites_screen.dart';
import 'profile_screen.dart';

/// Akses untuk berpindah tab dari dalam konten tab konsumen.
class ConsumerShellScope extends InheritedWidget {
  final void Function(int index) selectTab;
  const ConsumerShellScope({
    super.key,
    required this.selectTab,
    required super.child,
  });

  static ConsumerShellScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ConsumerShellScope>();

  @override
  bool updateShouldNotify(ConsumerShellScope oldWidget) => false;
}

/// Cangkang ekosistem konsumen: IndexedStack + bottom nav.
class ConsumerShell extends StatefulWidget {
  final int initialIndex;
  final ConsumerOrdersTab initialOrdersTab;
  final String? referencedOrderId;

  const ConsumerShell({
    super.key,
    this.initialIndex = 0,
    this.initialOrdersTab = ConsumerOrdersTab.active,
    this.referencedOrderId,
  });

  @override
  State<ConsumerShell> createState() => _ConsumerShellState();
}

class _ConsumerShellState extends State<ConsumerShell>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reloadAll());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastRefresh;
    if (last == null || DateTime.now().difference(last).inSeconds >= 30) {
      unawaited(_reloadAll());
    }
  }

  Future<void> _reloadAll() async {
    _lastRefresh = DateTime.now();
    await Future.wait([
      appState.loadConsumerHome(),
      appState.loadOrders(),
      appState.loadFavorites(),
      appState.loadNotifications(),
    ]);
  }

  void _select(int i) {
    if (i < 0 || i > 4) return;
    if (_index != i) setState(() => _index = i);
    switch (i) {
      case 0:
      case 1:
        unawaited(appState.loadConsumerHome());
        break;
      case 2:
        unawaited(appState.loadOrders());
        break;
      case 3:
        unawaited(appState.loadFavorites());
        break;
      case 4:
        unawaited(appState.loadProfile());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) _select(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: ConsumerShellScope(
          selectTab: _select,
          child: IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: [
              const HomeScreen(),
              const MapScreen(),
              OrdersScreen(
                initialTab: widget.initialOrdersTab,
                referencedOrderId: widget.referencedOrderId,
              ),
              const FavoritesScreen(),
              const ProfileScreen(),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          items: AppBottomNav.consumerItems,
          currentIndex: _index,
          onTap: _select,
          activeColor: AppColors.green,
        ),
      ),
    );
  }
}
