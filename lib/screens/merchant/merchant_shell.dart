import 'package:flutter/material.dart';
import '../../sb.dart';
import 'dashboard_screen.dart';
import 'manage_bags_screen.dart';
import 'incoming_orders_screen.dart';
import 'balance_screen.dart';
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
      context.dependOnInheritedWidgetOfExactType<MerchantShellScope>();

  @override
  bool updateShouldNotify(MerchantShellScope oldWidget) => false;
}

/// Cangkang ekosistem merchant: IndexedStack + bottom nav (palet terakota).
class MerchantShell extends StatefulWidget {
  final int initialIndex;
  const MerchantShell({super.key, this.initialIndex = 0});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    // Muat data ekosistem merchant dari backend.
    appState.loadStore();
    appState.loadMerchantData();
    appState.loadBalance();
    appState.loadNotifications();
  }

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}
