import 'dart:async';

import 'package:flutter/material.dart';

import '../../sb.dart';
import 'balance_screen.dart';
import 'dashboard_screen.dart';
import 'incoming_orders_screen.dart';
import 'manage_bags_screen.dart';
import 'merchant_profile_screen.dart';

/// Akses untuk berpindah tab dari dalam konten tab merchant.
class MerchantShellScope extends InheritedWidget {
  final void Function(int index) selectTab;

  const MerchantShellScope({
    super.key,
    required this.selectTab,
    required super.child,
  });

  static MerchantShellScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MerchantShellScope>();

  @override
  bool updateShouldNotify(MerchantShellScope oldWidget) => false;
}

/// Cangkang merchant. Data awal dimuat paralel, sedangkan perubahan order,
/// transaksi, dan notifikasi diterima melalui subscription AppState.
class MerchantShell extends StatefulWidget {
  final int initialIndex;

  const MerchantShell({super.key, this.initialIndex = 0});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex.clamp(0, 4);
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
      appState.loadStore(),
      appState.loadMerchantData(),
      appState.loadMerchantReviews(),
      appState.loadBalance(),
      appState.loadNotifications(),
    ]);
  }

  void _select(int index) {
    if (index < 0 || index > 4) return;
    if (_index != index) setState(() => _index = index);
    switch (index) {
      case 0:
      case 1:
      case 2:
        unawaited(appState.loadMerchantData());
        break;
      case 3:
        unawaited(appState.loadBalance());
        break;
      case 4:
        unawaited(appState.loadStore());
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
        body: MerchantShellScope(
          selectTab: _select,
          child: IndexedStack(
            index: _index,
            sizing: StackFit.expand,
            children: const [
              DashboardScreen(),
              ManageBagsScreen(),
              IncomingOrdersScreen(),
              BalanceScreen(),
              MerchantProfileScreen(),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          items: AppBottomNav.merchantItems,
          currentIndex: _index,
          onTap: _select,
          activeColor: AppColors.brown,
        ),
      ),
    );
  }
}
