import 'package:flutter/material.dart';
import '../../sb.dart';
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
      context.dependOnInheritedWidgetOfExactType<ConsumerShellScope>();

  @override
  bool updateShouldNotify(ConsumerShellScope oldWidget) => false;
}

/// Cangkang ekosistem konsumen: IndexedStack + bottom nav.
class ConsumerShell extends StatefulWidget {
  final int initialIndex;
  const ConsumerShell({super.key, this.initialIndex = 0});

  @override
  State<ConsumerShell> createState() => _ConsumerShellState();
}

class _ConsumerShellState extends State<ConsumerShell> {
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    // Muat data ekosistem konsumen dari backend.
    appState.loadConsumerHome();
    appState.loadOrders();
    appState.loadFavorites();
    appState.loadNotifications();
  }

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: ConsumerShellScope(
        selectTab: _select,
        child: IndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: const [
            HomeScreen(),
            MapScreen(),
            OrdersScreen(),
            FavoritesScreen(),
            ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        items: AppBottomNav.consumerItems,
        currentIndex: _index,
        onTap: _select,
        activeColor: AppColors.green,
      ),
    );
  }
}
