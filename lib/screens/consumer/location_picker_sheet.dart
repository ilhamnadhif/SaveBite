import 'package:flutter/material.dart';

import '../../sb.dart';

/// Pemilih area bersama untuk beranda dan onboarding lokasi.
///
/// Pemilihan area manual tidak bergantung pada izin GPS. Ini penting ketika
/// browser atau perangkat menolak izin lokasi, agar discovery tetap dapat
/// digunakan tanpa membuat pengguna terhenti di layar izin.
abstract final class ConsumerLocationPicker {
  static const _presets = <_LocationPreset>[
    _LocationPreset('Margonda, Depok', -6.3721, 106.8325),
    _LocationPreset('Cibinong, Bogor', -6.4840, 106.8424),
    _LocationPreset('Kemang, Jakarta', -6.2607, 106.8133),
  ];

  /// Mengembalikan `true` setelah lokasi berhasil diterapkan dan bag dimuat.
  static Future<bool> show(BuildContext context) async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x8C0F231C),
      builder: (sheetContext) {
        var busy = false;
        String? localError;
        var offerPermissionHelp = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> useCurrentLocation() async {
              if (busy) return;
              setSheetState(() {
                busy = true;
                localError = null;
                offerPermissionHelp = false;
              });
              try {
                final located = await appState.determineLocation();
                if (!located) {
                  offerPermissionHelp =
                      !appState.locationServicesEnabled ||
                      !appState.hasLocationPermission;
                  localError =
                      appState.errorMessage ??
                      'Lokasi terbaru belum berhasil ditemukan.';
                } else if (!appState.locationServicesEnabled) {
                  offerPermissionHelp = true;
                  localError = 'Layanan lokasi perangkat belum aktif.';
                } else if (!appState.hasLocationPermission) {
                  offerPermissionHelp = true;
                  localError = appState.usesBrowserPermissionSettings
                      ? appState.browserLocationPermissionGuidance
                      : appState.locationPermissionDeniedForever
                      ? 'Izin lokasi diblokir. Buka pengaturan aplikasi untuk '
                            'mengaktifkannya.'
                      : 'Izin lokasi belum diberikan.';
                } else if (!appState.hasValidUserLocation) {
                  localError =
                      appState.errorMessage ??
                      'Lokasi belum berhasil ditemukan. Coba lagi.';
                } else if (appState.consumerError != null) {
                  localError = appState.consumerError;
                } else {
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop(true);
                  return;
                }
              } catch (_) {
                offerPermissionHelp =
                    !appState.locationServicesEnabled ||
                    !appState.hasLocationPermission;
                localError =
                    appState.errorMessage ??
                    'Lokasi gagal diperbarui. Periksa izin dan koneksimu.';
              }
              if (!sheetContext.mounted) return;
              setSheetState(() => busy = false);
            }

            Future<void> selectPreset(_LocationPreset preset) async {
              if (busy) return;
              setSheetState(() {
                busy = true;
                localError = null;
                offerPermissionHelp = false;
              });
              try {
                await appState.setLocationWithCoordinates(
                  preset.label,
                  preset.latitude,
                  preset.longitude,
                );
                if (!sheetContext.mounted) return;
                if (appState.consumerError != null) {
                  setSheetState(() {
                    busy = false;
                    localError = appState.consumerError;
                  });
                  return;
                }
                Navigator.of(sheetContext).pop(true);
              } catch (_) {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  busy = false;
                  localError =
                      appState.consumerError ??
                      'Area gagal dimuat. Periksa koneksimu lalu coba lagi.';
                });
              }
            }

            Future<void> openSettings() async {
              if (appState.usesBrowserPermissionSettings) {
                setSheetState(() {
                  localError = appState.browserLocationPermissionGuidance;
                });
                return;
              }
              final opened = await appState.openRelevantLocationSettings();
              if (!opened && sheetContext.mounted) {
                setSheetState(() {
                  localError =
                      'Pengaturan tidak dapat dibuka otomatis. Buka '
                      'pengaturan perangkat dan izinkan lokasi untuk SaveBite.';
                });
              }
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.sheet),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(child: SheetHandle()),
                      Text(
                        'Pilih area',
                        style: AppText.display(22, weight: 800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Gunakan posisi saat ini atau pilih area secara manual.',
                        style: AppText.ui(13.5, color: AppColors.body),
                      ),
                      const SizedBox(height: 18),
                      AppCard(
                        padding: EdgeInsets.zero,
                        onTap: busy ? null : useCurrentLocation,
                        child: ListTile(
                          leading: busy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.greenBright,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location,
                                  color: AppColors.greenBright,
                                ),
                          title: Text(
                            busy ? 'Mencari lokasimu…' : 'Lokasi saat ini',
                            style: AppText.ui(14.5, weight: 700),
                          ),
                          subtitle: Text(
                            'Menggunakan GPS perangkat',
                            style: AppText.ui(12, color: AppColors.body),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppColors.chevron,
                          ),
                        ),
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 10),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.dangerBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  localError!,
                                  style: AppText.ui(
                                    12.5,
                                    color: AppColors.danger,
                                    height: 1.4,
                                  ),
                                ),
                                if (offerPermissionHelp &&
                                    !appState
                                        .usesBrowserPermissionSettings) ...[
                                  const SizedBox(height: 4),
                                  TextButton(
                                    onPressed: openSettings,
                                    child: Text(
                                      appState.locationSettingsActionLabel,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Text(
                        'Area pilihan',
                        style: AppText.ui(
                          13,
                          weight: 700,
                          color: AppColors.body,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < _presets.length; i++)
                              ListTile(
                                enabled: !busy,
                                onTap: busy
                                    ? null
                                    : () => selectPreset(_presets[i]),
                                leading: const Icon(
                                  Icons.location_on_outlined,
                                  color: AppColors.body,
                                ),
                                title: Text(
                                  _presets[i].label,
                                  style: AppText.ui(14, weight: 600),
                                ),
                                trailing: appState.location == _presets[i].label
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: AppColors.greenBright,
                                      )
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    return selected ?? false;
  }
}

class _LocationPreset {
  final String label;
  final double latitude;
  final double longitude;

  const _LocationPreset(this.label, this.latitude, this.longitude);
}
