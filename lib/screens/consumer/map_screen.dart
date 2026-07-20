import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../../app_nav.dart';
import '../../sb.dart';

/// Peta discovery berbasis OpenStreetMap dan koordinat merchant tersimpan.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _fallbackCenter = LatLng(-6.3721, 106.8325);
  static const _distance = Distance();
  static final _osmCopyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  final MapController _mapController = MapController();
  String? _selectedBagId;
  bool _selectionDismissed = false;
  bool _mapReady = false;
  bool _didInitialFit = false;
  bool _mapMovedByUser = false;
  bool _locationBusy = false;
  bool _areaBusy = false;
  LatLng? _lastSyncedCenter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshDeviceLocationWithoutPrompt();
    });
  }

  List<Bag> get _mappedBags => appState.nearbyBags
      .where(
        (bag) =>
            !bag.soldOut &&
            _validCoordinates(bag.merchant.latitude, bag.merchant.longitude),
      )
      .toList(growable: false);

  bool _validCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (latitude != 0 || longitude != 0);

  bool get _hasDeviceLocation =>
      appState.hasLocationPermission && appState.hasValidDeviceLocation;

  LatLng get _userCenter {
    final latitude = appState.userLatitude;
    final longitude = appState.userLongitude;
    return _validCoordinates(latitude, longitude)
        ? LatLng(latitude!, longitude!)
        : _fallbackCenter;
  }

  LatLng get _deviceCenter =>
      LatLng(appState.deviceLatitude!, appState.deviceLongitude!);

  Bag? _selectedBag(List<Bag> bags) {
    if (bags.isEmpty || _selectionDismissed) return null;
    final selectedId = _selectedBagId;
    if (selectedId == null) return null;
    for (final bag in bags) {
      if (bag.id == selectedId) return bag;
    }
    return null;
  }

  void _scheduleInitialFit(List<Bag> bags) {
    if (!_mapReady || appState.isLoadingConsumer) return;
    final hasDiscoveryCenter = _validCoordinates(
      appState.userLatitude,
      appState.userLongitude,
    );
    final discoveryCenter = hasDiscoveryCenter ? _userCenter : null;
    final centerChanged =
        discoveryCenter != null &&
        (_lastSyncedCenter == null ||
            _distance(_lastSyncedCenter!, discoveryCenter) > 2);
    if (_didInitialFit && !centerChanged) return;
    _didInitialFit = true;
    if (discoveryCenter != null) _lastSyncedCenter = discoveryCenter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      if (discoveryCenter != null) {
        // Lokasi yang dipilih adalah pusat discovery. Jangan memaksa semua
        // fixture toko yang jauh masuk satu frame karena itu membuat posisi
        // perangkat terlihat bergeser/tidak akurat.
        _mapController.move(discoveryCenter, 15);
        return;
      }
      final points = <LatLng>[
        for (final bag in bags)
          LatLng(bag.merchant.latitude!, bag.merchant.longitude!),
      ];
      if (points.isEmpty) {
        _mapController.move(_fallbackCenter, 14);
      } else if (points.length == 1) {
        _mapController.move(points.first, 15);
      } else {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.fromLTRB(54, 130, 54, 220),
            maxZoom: 15.5,
          ),
        );
      }
    });
  }

  Future<void> _showFilters() async {
    final filter = await AppNav.showFilter(context);
    if (!mounted || filter == null) return;
    await appState.setBagFilter(filter);
    if (!mounted) return;
    setState(() {
      _selectedBagId = null;
      _selectionDismissed = false;
      _mapMovedByUser = false;
    });
  }

  Future<void> _recenter() async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      final located = await appState.determineLocation();
      if (!mounted) return;
      if (located &&
          _validCoordinates(appState.userLatitude, appState.userLongitude)) {
        _mapController.move(_userCenter, 15.5);
        setState(() => _mapMovedByUser = false);
        final accuracy = appState.userLocationAccuracyMeters;
        if (appState.userLocationAccuracyReduced) {
          AppFeedback.snack(
            context,
            'Perangkat memberi lokasi perkiraan. Aktifkan lokasi presisi di '
            'pengaturan agar titik lebih akurat.',
          );
        } else if (accuracy != null && accuracy > 100) {
          AppFeedback.snack(
            context,
            'Sinyal GPS masih lemah (akurasi sekitar '
            '±${accuracy.round()} m). Coba lagi di area terbuka.',
          );
        }
      } else {
        final message = !appState.locationServicesEnabled
            ? 'Aktifkan layanan lokasi perangkat lalu coba lagi.'
            : appState.locationPermissionDeniedForever
            ? 'Izin lokasi diblokir. Aktifkan melalui pengaturan aplikasi.'
            : appState.errorMessage ??
                  'Lokasi terbaru belum berhasil ditemukan.';
        AppFeedback.snack(context, message);
      }
    } catch (_) {
      if (mounted) {
        AppFeedback.snack(
          context,
          appState.errorMessage ?? 'Lokasi belum berhasil ditemukan.',
        );
      }
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _refreshDeviceLocationWithoutPrompt() async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      final located = await appState.determineLocation(
        requestPermission: false,
      );
      if (!mounted || !located) return;
      _lastSyncedCenter = null;
      _mapMovedByUser = false;
    } catch (_) {
      // Refresh pasif tidak mengganggu browsing; tombol lokasi tetap dapat
      // dipakai untuk meminta izin atau mencoba lagi secara eksplisit.
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  Future<void> _searchThisArea() async {
    if (_areaBusy || !_mapReady) return;
    setState(() => _areaBusy = true);
    try {
      final center = _mapController.camera.center;
      _lastSyncedCenter = center;
      await appState.setLocationWithCoordinates(
        'Area peta',
        center.latitude,
        center.longitude,
      );
      if (!mounted) return;
      if (appState.consumerError != null) {
        AppFeedback.snack(context, appState.consumerError!);
        setState(() => _mapMovedByUser = true);
        return;
      }
      setState(() {
        _mapMovedByUser = false;
        _selectedBagId = null;
      });
    } catch (_) {
      if (mounted) {
        AppFeedback.snack(
          context,
          appState.consumerError ?? 'Bag di area ini gagal dimuat.',
        );
      }
    } finally {
      if (mounted) setState(() => _areaBusy = false);
    }
  }

  Future<void> _openLocationSettings() async {
    if (!appState.locationServicesEnabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  @override
  void dispose() {
    _mapReady = false;
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return StatusBarStyle.dark(
      child: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final bags = _mappedBags;
          final selected = _selectedBag(bags);
          _scheduleInitialFit(bags);

          return Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _userCenter,
                    initialZoom: 14,
                    minZoom: 4,
                    maxZoom: 19,
                    backgroundColor: AppColors.mapGridBg,
                    keepAlive: true,
                    onMapReady: () {
                      _mapReady = true;
                      _scheduleInitialFit(_mappedBags);
                    },
                    onTap: (_, _) {
                      setState(() {
                        _selectedBagId = null;
                        _selectionDismissed = true;
                      });
                    },
                    onPositionChanged: (_, hasGesture) {
                      if (hasGesture && !_mapMovedByUser && mounted) {
                        setState(() => _mapMovedByUser = true);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.savebite.savebite',
                      maxNativeZoom: 19,
                    ),
                    if (_hasDeviceLocation &&
                        appState.userLocationAccuracyMeters != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _deviceCenter,
                            radius: appState.userLocationAccuracyMeters!
                                .clamp(5, 5000)
                                .toDouble(),
                            useRadiusInMeter: true,
                            color: AppColors.userDot.withValues(alpha: 0.12),
                            borderStrokeWidth: 1.5,
                            borderColor: AppColors.userDot.withValues(
                              alpha: 0.42,
                            ),
                          ),
                        ],
                      ),
                    if (_hasDeviceLocation)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _deviceCenter,
                            width: 42,
                            height: 42,
                            child: _UserMarker(
                              accuracyMeters:
                                  appState.userLocationAccuracyMeters,
                            ),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final bag in bags)
                          Marker(
                            key: ValueKey('map-marker-${bag.id}'),
                            point: LatLng(
                              bag.merchant.latitude!,
                              bag.merchant.longitude!,
                            ),
                            width: 98,
                            height: 58,
                            alignment: Alignment.topCenter,
                            child: _PricePin(
                              label: _pinLabel(bag.salePrice),
                              selected: bag.id == selected?.id,
                              onTap: () {
                                setState(() {
                                  _selectedBagId = bag.id;
                                  _selectionDismissed = false;
                                });
                                _mapController.move(
                                  LatLng(
                                    bag.merchant.latitude!,
                                    bag.merchant.longitude!,
                                  ),
                                  _mapController.camera.zoom,
                                  offset: const Offset(0, -70),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: topInset + 12,
                left: 16,
                right: 16,
                child: _topBar(),
              ),
              if (_mapMovedByUser)
                Positioned(
                  top: topInset + 72,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: _areaBusy ? null : _searchThisArea,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: AppColors.cream,
                        elevation: 3,
                      ),
                      icon: _areaBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.cream,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: const Text('Cari di area ini'),
                    ),
                  ),
                ),
              if (_hasDeviceLocation && !_mapMovedByUser)
                Positioned(
                  top: topInset + 69,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _LocationAccuracyChip(
                      accuracyMeters: appState.userLocationAccuracyMeters,
                      reduced: appState.userLocationAccuracyReduced,
                    ),
                  ),
                ),
              Positioned(
                right: 16,
                bottom: selected == null ? 54 : 178,
                child: _MapControl(
                  tooltip: 'Tampilkan lokasiku',
                  onTap: _locationBusy ? null : _recenter,
                  child: _locationBusy
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.green,
                          ),
                        )
                      : const Icon(
                          Icons.my_location,
                          color: AppColors.green,
                          size: 21,
                        ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: selected == null ? 8 : 142,
                child: _AttributionLink(onTap: _openAttribution),
              ),
              if (appState.isLoadingConsumer && bags.isEmpty)
                const Positioned.fill(child: _MapLoadingOverlay())
              else if (appState.consumerError != null && bags.isEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  top: topInset + 112,
                  child: _MapMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Bag belum dapat dimuat',
                    message: appState.consumerError!,
                    actionLabel: 'Coba lagi',
                    onAction: appState.loadConsumerHome,
                  ),
                )
              else if (bags.isEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  top: topInset + 112,
                  child: _MapMessage(
                    icon: Icons.location_off_outlined,
                    title: appState.nearbyBags.isEmpty
                        ? 'Belum ada bag di area ini'
                        : 'Lokasi toko belum tersedia',
                    message: appState.nearbyBags.isEmpty
                        ? 'Geser peta lalu cari area lain, atau ubah filter.'
                        : 'Toko belum menambahkan titik peta. Bag tetap dapat '
                              'dilihat dari tab Beranda.',
                    actionLabel: !appState.locationServicesEnabled
                        ? 'Buka pengaturan lokasi'
                        : 'Muat ulang',
                    onAction: !appState.locationServicesEnabled
                        ? _openLocationSettings
                        : appState.loadConsumerHome,
                  ),
                ),
              if (selected != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _bottomCard(selected),
                ),
            ],
          );
        },
      ),
    );
  }

  String _pinLabel(int salePrice) => salePrice >= 1000000
      ? 'Rp${(salePrice / 1000000).toStringAsFixed(1)}jt'
      : 'Rp${salePrice ~/ 1000}rb';

  Future<void> _openAttribution() =>
      launchUrl(_osmCopyright, mode: LaunchMode.externalApplication);

  Widget _topBar() {
    return Material(
      color: AppColors.white,
      elevation: 4,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(14),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => AppNav.toSearch(context),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    const Icon(Icons.search, size: 19, color: AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cari toko atau makanan…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui(14, color: AppColors.mutedAlt),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Filter peta',
            onPressed: _showFilters,
            icon: Badge(
              isLabelVisible: !appState.currentFilter.isEmpty,
              backgroundColor: AppColors.terracotta,
              child: const Icon(Icons.tune, size: 20, color: AppColors.green),
            ),
          ),
          const SizedBox(width: 3),
        ],
      ),
    );
  }

  Widget _bottomCard(Bag bag) {
    return Semantics(
      button: true,
      label:
          '${bag.title}, ${bag.merchant.name}, ${formatRupiah(bag.salePrice)}',
      child: Material(
        color: AppColors.white,
        elevation: 8,
        shadowColor: const Color(0x4D000000),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppNav.toDetail(context, bag),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: FoodImage(bag.image, width: 76, height: 76),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        bag.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.display(15, weight: 700),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              bag.merchant.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.ui(
                                12.5,
                                weight: 600,
                                color: AppColors.body,
                              ),
                            ),
                          ),
                          Text(
                            '★ ${bag.merchant.rating.toStringAsFixed(1)}',
                            style: AppText.ui(
                              11.5,
                              weight: 600,
                              color: AppColors.body,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${bag.merchant.distance} · ambil ${bag.pickupWindow}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui(11.5, color: AppColors.body),
                      ),
                      const SizedBox(height: 5),
                      PriceTag(
                        salePrice: bag.salePrice,
                        originalPrice: bag.originalPrice,
                        saleSize: 16,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppColors.chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PricePin extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PricePin({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = selected ? AppColors.terracotta : AppColors.green;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Surprise Bag $label',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.symmetric(
                horizontal: selected ? 13 : 11,
                vertical: selected ? 8 : 7,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                label,
                style: AppText.ui(12, weight: 800, color: AppColors.white),
              ),
            ),
            CustomPaint(
              size: const Size(13, 8),
              painter: _TrianglePainter(background),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _UserMarker extends StatelessWidget {
  final double? accuracyMeters;

  const _UserMarker({this.accuracyMeters});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: accuracyMeters == null
          ? 'Lokasi kamu'
          : 'Lokasi kamu, akurasi sekitar ${accuracyMeters!.round()} meter',
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.userDot,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x552D7BE5),
                blurRadius: 0,
                spreadRadius: 7,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  const _MapControl({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(tooltip: tooltip, onPressed: onTap, icon: child),
    );
  }
}

class _LocationAccuracyChip extends StatelessWidget {
  final double? accuracyMeters;
  final bool reduced;

  const _LocationAccuracyChip({
    required this.accuracyMeters,
    required this.reduced,
  });

  @override
  Widget build(BuildContext context) {
    final accuracyText = accuracyMeters == null
        ? ''
        : ' · ±${accuracyMeters!.round()} m';
    return Semantics(
      liveRegion: reduced,
      label: reduced
          ? 'Lokasi perangkat berupa perkiraan$accuracyText'
          : 'Akurasi lokasi perangkat$accuracyText',
      child: Material(
        color: AppColors.white.withValues(alpha: 0.94),
        elevation: 2,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                reduced ? Icons.gps_not_fixed : Icons.gps_fixed,
                size: 14,
                color: reduced ? AppColors.terracotta : AppColors.green,
              ),
              const SizedBox(width: 5),
              Text(
                '${reduced ? 'Lokasi perkiraan' : 'GPS'}$accuracyText',
                style: AppText.ui(
                  10.5,
                  weight: 700,
                  color: reduced ? AppColors.terracotta : AppColors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttributionLink extends StatelessWidget {
  final VoidCallback onTap;

  const _AttributionLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Text(
            '© OpenStreetMap contributors',
            style: AppText.ui(9.5, color: AppColors.body),
          ),
        ),
      ),
    );
  }
}

class _MapLoadingOverlay extends StatelessWidget {
  const _MapLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: AppColors.cream.withValues(alpha: 0.58),
        child: Semantics(
          liveRegion: true,
          label: 'Memuat lokasi toko',
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.greenBright),
          ),
        ),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _MapMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      elevation: 5,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.green, size: 23),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.ui(14, weight: 700)),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: AppText.ui(12, color: AppColors.body, height: 1.4),
                  ),
                  const SizedBox(height: 3),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 40),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
