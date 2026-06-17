import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

class NavItem {
  final IconData outlined;
  final IconData filled;
  final String label;
  const NavItem(this.outlined, this.filled, this.label);
}

/// Bottom navigation generik (dipakai konsumen & merchant).
class AppBottomNav extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color activeColor;

  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.activeColor = AppColors.green,
  });

  static const consumerItems = [
    NavItem(Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    NavItem(Icons.map_outlined, Icons.map_rounded, 'Peta'),
    NavItem(Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'Pesanan'),
    NavItem(Icons.favorite_border_rounded, Icons.favorite_rounded, 'Favorit'),
    NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  static const merchantItems = [
    NavItem(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Dashboard'),
    NavItem(Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, 'Bag'),
    NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Pesanan'),
    NavItem(Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet_rounded, 'Saldo'),
    NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(8, 10, 8, 12 + bottomInset),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < items.length; i++)
            _NavButton(
              item: items[i],
              active: i == currentIndex,
              activeColor: activeColor,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavItem item;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : AppColors.navInactive;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? item.filled : item.outlined, size: 23, color: color),
          const SizedBox(height: 3),
          Text(item.label,
              style: AppText.ui(10.5, weight: active ? 700 : 600, color: color)),
        ],
      ),
    );
  }
}
