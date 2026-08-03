import 'package:flutter_test/flutter_test.dart';

import 'package:savebite/services/location_permission_support.dart';

void main() {
  test(
    'web memberi panduan izin situs dan tidak membuka pengaturan native',
    () async {
      var locationSettingsCalls = 0;
      var appSettingsCalls = 0;

      final opened = await LocationPermissionSupport.openSettings(
        locationServicesEnabled: false,
        isWeb: true,
        openLocationSettings: () async {
          locationSettingsCalls++;
          return true;
        },
        openAppSettings: () async {
          appSettingsCalls++;
          return true;
        },
      );

      expect(opened, isFalse);
      expect(locationSettingsCalls, 0);
      expect(appSettingsCalls, 0);
      expect(
        LocationPermissionSupport.permissionBlockedMessage(isWeb: true),
        contains('bilah alamat browser'),
      );
      expect(
        LocationPermissionSupport.settingsActionLabel(
          locationServicesEnabled: true,
          isWeb: true,
        ),
        'Cara mengizinkan lokasi',
      );
    },
  );

  test('mobile membuka target pengaturan yang sesuai', () async {
    var locationSettingsCalls = 0;
    var appSettingsCalls = 0;

    Future<bool> openLocationSettings() async {
      locationSettingsCalls++;
      return true;
    }

    Future<bool> openAppSettings() async {
      appSettingsCalls++;
      return true;
    }

    expect(
      await LocationPermissionSupport.openSettings(
        locationServicesEnabled: false,
        isWeb: false,
        openLocationSettings: openLocationSettings,
        openAppSettings: openAppSettings,
      ),
      isTrue,
    );
    expect(locationSettingsCalls, 1);
    expect(appSettingsCalls, 0);

    expect(
      await LocationPermissionSupport.openSettings(
        locationServicesEnabled: true,
        isWeb: false,
        openLocationSettings: openLocationSettings,
        openAppSettings: openAppSettings,
      ),
      isTrue,
    );
    expect(locationSettingsCalls, 1);
    expect(appSettingsCalls, 1);
  });
}
