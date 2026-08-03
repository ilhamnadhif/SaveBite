import 'package:flutter/material.dart';

import '../../services/snap_checkout_session.dart';

class SnapCheckoutView extends StatelessWidget {
  final SnapCheckoutSession session;
  final VoidCallback onStatusHint;
  final ValueChanged<String> onError;

  const SnapCheckoutView({
    super.key,
    required this.session,
    required this.onStatusHint,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) => const Center(
    key: ValueKey('snap-checkout-unavailable'),
    child: Text('Checkout Midtrans tidak tersedia di platform ini.'),
  );
}
