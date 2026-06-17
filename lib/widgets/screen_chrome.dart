import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Membungkus subtree dengan gaya status bar yang sesuai latar layar.
/// [StatusBarStyle.light] → ikon terang (untuk latar gelap).
/// [StatusBarStyle.dark]  → ikon gelap (untuk latar cream/putih).
class StatusBarStyle extends StatelessWidget {
  final Widget child;
  final bool light;

  const StatusBarStyle({super.key, required this.child, required this.light});

  const StatusBarStyle.light({super.key, required this.child}) : light = true;

  const StatusBarStyle.dark({super.key, required this.child}) : light = false;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: light ? Brightness.light : Brightness.dark,
        statusBarBrightness: light ? Brightness.dark : Brightness.light,
      ),
      child: child,
    );
  }
}
