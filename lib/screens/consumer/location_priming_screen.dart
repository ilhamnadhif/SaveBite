import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app_nav.dart';
import '../../sb.dart';
import 'location_picker_sheet.dart';

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
      if (located && appState.locationPrimed && appState.hasValidUserLocation) {
        // Permission may already be granted while the persisted priming flag
        // is being restored. Do not make the user press the permission button
        // again; continue directly to the consumer home.
        AppNav.toConsumerHome(context);
        return;
      }
      setState(() {
        _permission = permission;
        _message = located ? null : _messageForLocationStatus(permission);
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _message = _messageForLocationStatus(
          _permission ?? LocationPermission.denied,
        ),
      );
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
      var permission = _permission ?? LocationPermission.denied;
      try {
        permission = await Geolocator.checkPermission();
      } catch (_) {
        // Jika plugin lokasi sendiri tidak dapat membaca status, pengguna
        // tetap harus dapat memakai area manual.
      }
      if (!mounted) return;
      setState(() {
        _permission = permission;
        _message = _messageForLocationStatus(permission);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _locationProblemMessage(LocationPermission permission) {
    if (appState.usesBrowserPermissionSettings) {
      return 'Lokasi browser belum tersedia. Kamu tetap dapat memilih area '
          'secara manual untuk melanjutkan.';
    }
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

  String _messageForLocationStatus(LocationPermission permission) {
    if (!appState.locationServicesEnabled || !appState.hasLocationPermission) {
      return _locationProblemMessage(permission);
    }
    return appState.errorMessage ??
        'Lokasi belum berhasil ditemukan. Coba lagi.';
  }

  Future<void> _openSettings() async {
    if (appState.usesBrowserPermissionSettings) {
      setState(() {
        _message = appState.browserLocationPermissionGuidance;
      });
      return;
    }
    await appState.openRelevantLocationSettings();
  }

  Future<void> _chooseManualArea() async {
    if (_busy) return;
    final selected = await ConsumerLocationPicker.show(context);
    if (!mounted || !selected) return;
    await appState.markLocationPrimed();
    if (!mounted) return;
    AppNav.toConsumerHome(context);
  }

  bool get _showSettings =>
      !appState.usesBrowserPermissionSettings &&
      (!appState.locationServicesEnabled ||
          _permission == LocationPermission.deniedForever);

  @override
  Widget build(BuildContext context) {
    final isPermissionIssue =
        !appState.locationServicesEnabled || !appState.hasLocationPermission;
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
                                    color: isPermissionIssue
                                        ? AppColors.greenSoftBg
                                        : AppColors.dangerBg,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 20,
                                        color: isPermissionIssue
                                            ? AppColors.greenAccent
                                            : AppColors.danger,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _message!,
                                          style: AppText.ui(
                                            13,
                                            color: isPermissionIssue
                                                ? AppColors.greenAccent
                                                : AppColors.danger,
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
                    label: appState.locationSettingsActionLabel,
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
                  label: 'Pilih area manual',
                  onTap: _busy ? null : _chooseManualArea,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
