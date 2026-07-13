import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app_nav.dart';
import '../../sb.dart';

/// Menjelaskan manfaat lokasi sebelum dialog izin sistem ditampilkan.
class LocationPrimingScreen extends StatefulWidget {
  const LocationPrimingScreen({super.key});

  @override
  State<LocationPrimingScreen> createState() => _LocationPrimingScreenState();
}

class _LocationPrimingScreenState extends State<LocationPrimingScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _message;
  LocationPermission? _permission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshStatus());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final located = await appState.determineLocation(
        requestPermission: false,
      );
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _permission = permission;
        _message = located ? null : appState.errorMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = appState.errorMessage);
    }
  }

  Future<void> _allow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final located = await appState.determineLocation();
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      _permission = permission;

      if (located &&
          appState.locationServicesEnabled &&
          appState.hasLocationPermission &&
          appState.hasValidUserLocation) {
        await appState.markLocationPrimed();
        if (!mounted) return;
        AppNav.toConsumerHome(context);
        return;
      }

      setState(() => _message = _locationProblemMessage(permission));
    } catch (_) {
      if (!mounted) return;
      final permission = await Geolocator.checkPermission();
      if (!mounted) return;
      setState(() {
        _permission = permission;
        _message = appState.errorMessage ?? _locationProblemMessage(permission);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _locationProblemMessage(LocationPermission permission) {
    if (!appState.locationServicesEnabled) {
      return 'Layanan lokasi perangkat sedang nonaktif. Aktifkan lokasi, lalu '
          'coba lagi.';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Akses lokasi diblokir. Buka pengaturan aplikasi untuk '
          'mengizinkan lokasi.';
    }
    return 'SaveBite belum mendapat izin lokasi. Kamu tetap dapat memilih '
        'area secara manual dari beranda.';
  }

  Future<void> _openSettings() async {
    if (!appState.locationServicesEnabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _later() async {
    if (_busy) return;
    await appState.markLocationPrimed();
    if (!mounted) return;
    AppNav.toConsumerHome(context);
  }

  bool get _showSettings =>
      !appState.locationServicesEnabled ||
      _permission == LocationPermission.deniedForever;

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
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.sizeOf(context).height * 0.56,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              image: true,
                              label: 'Ilustrasi penanda lokasi',
                              child: Container(
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
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Aktifkan lokasi',
                              textAlign: TextAlign.center,
                              style: AppText.display(26),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 330),
                              child: Text(
                                'Lokasi dipakai saat aplikasi aktif untuk '
                                'mengurutkan Surprise Bag berdasarkan jarak. '
                                'SaveBite tidak melacak perjalananmu.',
                                textAlign: TextAlign.center,
                                style: AppText.ui(
                                  15,
                                  color: AppColors.body,
                                  height: 1.55,
                                ),
                              ),
                            ),
                            if (_message != null) ...[
                              const SizedBox(height: 22),
                              Semantics(
                                liveRegion: true,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerBg,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        size: 20,
                                        color: AppColors.danger,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _message!,
                                          style: AppText.ui(
                                            13,
                                            color: AppColors.danger,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showSettings && _message != null) ...[
                  GhostButton(
                    label: !appState.locationServicesEnabled
                        ? 'Buka pengaturan lokasi'
                        : 'Buka pengaturan aplikasi',
                    color: AppColors.greenBright,
                    onTap: _busy ? null : _openSettings,
                  ),
                  const SizedBox(height: 6),
                ],
                PrimaryButton(
                  label: _busy ? 'Mencari lokasimu…' : 'Izinkan akses lokasi',
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.cream,
                          ),
                        )
                      : const Icon(
                          Icons.my_location,
                          size: 19,
                          color: AppColors.cream,
                        ),
                  onTap: _busy ? null : _allow,
                ),
                const SizedBox(height: 6),
                GhostButton(
                  label: 'Pilih area nanti',
                  onTap: _busy ? null : _later,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
