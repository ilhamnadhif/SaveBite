import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef LocationSettingsOpener = Future<bool> Function();

/// Satu pintu untuk UX izin lokasi lintas platform.
///
/// Browser tidak menyediakan API untuk membuka halaman izin situs secara
/// programatis. Karena itu Flutter Web selalu menampilkan petunjuk, sedangkan
/// Android/iOS boleh meneruskan pengguna ke pengaturan sistem.
abstract final class LocationPermissionSupport {
  static const browserGuidance =
      'Izinkan lokasi untuk situs SaveBite melalui ikon izin di bilah alamat '
      'browser, lalu muat ulang halaman dan coba lagi.';

  static bool get usesBrowserSettings => kIsWeb;

  static String settingsActionLabel({
    required bool locationServicesEnabled,
    bool isWeb = kIsWeb,
  }) {
    if (isWeb) return 'Cara mengizinkan lokasi';
    return locationServicesEnabled
        ? 'Buka pengaturan aplikasi'
        : 'Buka pengaturan lokasi';
  }

  static String permissionBlockedMessage({bool isWeb = kIsWeb}) => isWeb
      ? browserGuidance
      : 'Izin lokasi diblokir. Aktifkan lewat pengaturan aplikasi.';

  static String locationServicesDisabledMessage({bool isWeb = kIsWeb}) =>
      isWeb ? browserGuidance : 'Layanan lokasi perangkat belum aktif.';

  /// Mengembalikan `false` di web tanpa memanggil plugin platform apa pun.
  static Future<bool> openSettings({
    required bool locationServicesEnabled,
    bool isWeb = kIsWeb,
    LocationSettingsOpener? openLocationSettings,
    LocationSettingsOpener? openAppSettings,
  }) async {
    if (isWeb) return false;
    if (locationServicesEnabled) {
      return (openAppSettings ?? Geolocator.openAppSettings)();
    }
    return (openLocationSettings ?? Geolocator.openLocationSettings)();
  }
}
