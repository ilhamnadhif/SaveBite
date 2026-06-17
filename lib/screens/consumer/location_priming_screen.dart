import 'package:flutter/material.dart';
import '../../sb.dart';
import '../../app_nav.dart';

/// Layar pemicu izin lokasi — mengajak konsumen mengaktifkan lokasi
/// agar bisa menemukan Surprise Bag terdekat.
class LocationPrimingScreen extends StatelessWidget {
  const LocationPrimingScreen({super.key});

  void _allow(BuildContext context) {
    appState.locationPrimed = true;
    AppFeedback.snack(context, 'Lokasi diaktifkan');
    AppNav.toConsumerHome(context);
  }

  void _later(BuildContext context) {
    appState.locationPrimed = true;
    AppNav.toConsumerHome(context);
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle.dark(
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: AppColors.greenSoftBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.greenBright,
                            size: 56,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Aktifkan lokasi',
                          textAlign: TextAlign.center,
                          style: AppText.display(26),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            'Izinkan SaveBite mengakses lokasimu untuk '
                            'menemukan Surprise Bag terdekat dan jam pickup '
                            'yang pas.',
                            textAlign: TextAlign.center,
                            style: AppText.ui(15,
                                color: AppColors.body, height: 1.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PrimaryButton(
                  label: 'Izinkan akses lokasi',
                  onTap: () => _allow(context),
                ),
                const SizedBox(height: 6),
                GhostButton(
                  label: 'Nanti saja',
                  onTap: () => _later(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
