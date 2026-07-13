import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' as geo;

import 'package:savebite/screens/merchant/store_location_section.dart';
import 'package:savebite/services/store_geocoding_service.dart';
import 'package:savebite/theme/app_theme.dart';

class _FakeStoreGeocoding implements StoreGeocodingService {
  _FakeStoreGeocoding({this.forwardResult, this.reverseResult});

  StoreGeoPoint? forwardResult;
  String? reverseResult;
  String? lastForwardQuery;
  StoreGeoPoint? lastReversePoint;

  @override
  Future<StoreGeoPoint?> findPoint(String address) async {
    lastForwardQuery = address;
    return forwardResult;
  }

  @override
  Future<String?> findAddress(StoreGeoPoint point) async {
    lastReversePoint = point;
    return reverseResult;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1200, 2400);
    view.devicePixelRatio = 2;
  });

  tearDown(() {
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  test('formatter placemark menghapus komponen kosong dan duplikat', () {
    const placemark = geo.Placemark(
      street: 'Jl. Margonda Raya No. 10',
      subLocality: 'Beji',
      locality: 'Depok',
      subAdministrativeArea: 'Depok',
      administrativeArea: 'Jawa Barat',
      postalCode: '16424',
      country: 'Indonesia',
    );

    expect(
      formatStorePlacemark(placemark),
      'Jl. Margonda Raya No. 10, Beji, Depok, Jawa Barat, 16424, Indonesia',
    );
    expect(isValidStoreCoordinate(-6.37, 106.83), isTrue);
    expect(isValidStoreCoordinate(0, 0), isFalse);
    expect(isValidStoreCoordinate(100, 106.83), isFalse);
  });

  testWidgets('alamat yang diketik membatalkan pin lama lalu memindahkan pin', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: 'Alamat lama, Depok, Jawa Barat',
    );
    addTearDown(controller.dispose);
    const newPoint = StoreGeoPoint(latitude: -6.3725, longitude: 106.8323);
    final geocoding = _FakeStoreGeocoding(forwardResult: newPoint);
    final pointChanges = <StoreGeoPoint?>[];
    final busyChanges = <bool>[];

    await tester.pumpWidget(
      _testApp(
        StoreLocationSection(
          addressController: controller,
          initialLatitude: -6.2,
          initialLongitude: 106.8,
          geocodingService: geocoding,
          debounceDuration: const Duration(seconds: 1),
          validator: (_) => null,
          readCurrentLocation: () async => null,
          onPointChanged: pointChanges.add,
          onBusyChanged: busyChanges.add,
        ),
      ),
    );

    const typedAddress = 'Jl. Margonda Raya No. 10, Depok';
    await tester.enterText(find.byType(TextFormField), typedAddress);
    expect(pointChanges.last, isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(geocoding.lastForwardQuery, typedAddress);
    expect(pointChanges.last?.latitude, newPoint.latitude);
    expect(pointChanges.last?.longitude, newPoint.longitude);
    expect(controller.text, typedAddress);
    expect(busyChanges, containsAllInOrder([true, false]));
    expect(
      find.text('Pin otomatis disesuaikan dengan alamat yang diketik.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('store-location-marker')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lokasi saat ini mengisi alamat dari reverse geocoding', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const currentPoint = StoreGeoPoint(latitude: -6.301, longitude: 106.812);
    const resolvedAddress =
        'Jl. Contoh No. 8, Kecamatan Contoh, Jakarta, Indonesia';
    final geocoding = _FakeStoreGeocoding(reverseResult: resolvedAddress);
    StoreGeoPoint? selectedPoint;

    await tester.pumpWidget(
      _testApp(
        StoreLocationSection(
          addressController: controller,
          initialLatitude: null,
          initialLongitude: null,
          geocodingService: geocoding,
          validator: (_) => null,
          readCurrentLocation: () async => const StoreCurrentLocation(
            point: currentPoint,
            accuracyMeters: 12,
          ),
          onPointChanged: (point) => selectedPoint = point,
          onBusyChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('store-current-location-button')));
    await tester.pump();
    await tester.pump();

    expect(geocoding.lastReversePoint?.latitude, currentPoint.latitude);
    expect(controller.text, resolvedAddress);
    expect(selectedPoint?.longitude, currentPoint.longitude);
    expect(find.text('Alamat diisi dari GPS (±12 m).'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('titik yang diketuk di peta memperbarui alamat dan koordinat', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    const resolvedAddress =
        'Jl. Pilihan Peta No. 3, Beji, Depok, Jawa Barat, Indonesia';
    final geocoding = _FakeStoreGeocoding(reverseResult: resolvedAddress);
    StoreGeoPoint? selectedPoint;

    await tester.pumpWidget(
      _testApp(
        StoreLocationSection(
          addressController: controller,
          initialLatitude: null,
          initialLongitude: null,
          geocodingService: geocoding,
          validator: (_) => null,
          readCurrentLocation: () async => null,
          onPointChanged: (point) => selectedPoint = point,
          onBusyChanged: (_) {},
        ),
      ),
    );

    await tester.pump();
    final map = find.byKey(const Key('store-location-map'));
    final mapRect = tester.getRect(map);
    await tester.tapAt(mapRect.center);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(geocoding.lastReversePoint, isNotNull);
    expect(controller.text, resolvedAddress);
    expect(selectedPoint?.latitude, geocoding.lastReversePoint?.latitude);
    expect(
      find.text('Alamat diisi dari titik yang dipilih di peta.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(Widget child) => MaterialApp(
  theme: AppTheme.theme,
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  ),
);
