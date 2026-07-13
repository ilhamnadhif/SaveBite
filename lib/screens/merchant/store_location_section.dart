import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../sb.dart';
import '../../services/store_geocoding_service.dart';
import 'merchant_form_fields.dart';

class StoreCurrentLocation {
  const StoreCurrentLocation({required this.point, this.accuracyMeters});

  final StoreGeoPoint point;
  final double? accuracyMeters;
}

class StoreLocationInputException implements Exception {
  const StoreLocationInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef StoreCurrentLocationReader = Future<StoreCurrentLocation?> Function();

/// Input alamat dan peta yang menjaga alamat serta koordinat toko tetap cocok.
///
/// Alamat yang diketik dicari setelah debounce. Aksi GPS/ketuk peta melakukan
/// reverse-geocoding dan hanya dianggap valid setelah alamat berhasil dibaca.
class StoreLocationSection extends StatefulWidget {
  const StoreLocationSection({
    super.key,
    required this.addressController,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.onPointChanged,
    required this.onBusyChanged,
    required this.readCurrentLocation,
    required this.validator,
    this.enabled = true,
    this.geocodingService,
    this.debounceDuration = const Duration(milliseconds: 850),
  });

  final TextEditingController addressController;
  final double? initialLatitude;
  final double? initialLongitude;
  final ValueChanged<StoreGeoPoint?> onPointChanged;
  final ValueChanged<bool> onBusyChanged;
  final StoreCurrentLocationReader readCurrentLocation;
  final String? Function(String?) validator;
  final bool enabled;
  final StoreGeocodingService? geocodingService;
  final Duration debounceDuration;

  @override
  State<StoreLocationSection> createState() => _StoreLocationSectionState();
}

class _StoreLocationSectionState extends State<StoreLocationSection> {
  static const _fallbackCenter = LatLng(-6.3725, 106.8323);
  static final _osmCopyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  final MapController _mapController = MapController();
  late final StoreGeocodingService _geocoding =
      widget.geocodingService ?? NativeStoreGeocodingService();

  Timer? _addressDebounce;
  StoreGeoPoint? _point;
  late LatLng _cameraCenter;
  bool _mapReady = false;
  bool _busy = false;
  bool _synchronized = false;
  bool _statusIsError = false;
  String _status = 'Ketik alamat, ketuk peta, atau gunakan lokasi saat ini.';
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initialPoint = _validPoint(
      widget.initialLatitude,
      widget.initialLongitude,
    );
    _point = initialPoint;
    _cameraCenter = initialPoint == null
        ? _fallbackCenter
        : LatLng(initialPoint.latitude, initialPoint.longitude);
    _synchronized =
        initialPoint != null &&
        widget.addressController.text.trim().length >= 8;
    if (_synchronized) {
      _status = 'Alamat dan titik peta sudah sinkron.';
    } else if (widget.addressController.text.trim().length >= 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _queueAddressLookup(widget.addressController.text);
      });
    }
  }

  @override
  void didUpdateWidget(StoreLocationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final coordinatesChanged =
        oldWidget.initialLatitude != widget.initialLatitude ||
        oldWidget.initialLongitude != widget.initialLongitude;
    if (!coordinatesChanged || _busy) return;
    final incoming = _validPoint(
      widget.initialLatitude,
      widget.initialLongitude,
    );
    final samePoint =
        incoming?.latitude == _point?.latitude &&
        incoming?.longitude == _point?.longitude;
    if (samePoint) return;
    setState(() {
      _point = incoming;
      _synchronized =
          incoming != null && widget.addressController.text.trim().length >= 8;
      if (incoming != null) {
        _cameraCenter = LatLng(incoming.latitude, incoming.longitude);
        _status = 'Alamat dan titik peta sudah sinkron.';
        _statusIsError = false;
      }
    });
    if (incoming != null) _moveMap(incoming, zoom: 17);
  }

  @override
  void dispose() {
    _requestGeneration++;
    _addressDebounce?.cancel();
    _mapReady = false;
    _mapController.dispose();
    super.dispose();
  }

  StoreGeoPoint? _validPoint(double? latitude, double? longitude) =>
      isValidStoreCoordinate(latitude, longitude)
      ? StoreGeoPoint(latitude: latitude!, longitude: longitude!)
      : null;

  void _onAddressChanged(String value) {
    _requestGeneration++;
    _addressDebounce?.cancel();
    widget.onPointChanged(null);
    final query = value.trim();
    final searchable = query.length >= 8;
    setState(() {
      _point = null;
      _synchronized = false;
      _statusIsError = false;
      _status = searchable
          ? 'Mencari titik dari alamat…'
          : 'Lengkapi alamat agar pin dapat dicari.';
    });
    _setBusy(searchable);
    if (!searchable) return;
    final request = _requestGeneration;
    _addressDebounce = Timer(
      widget.debounceDuration,
      () => unawaited(_resolveTypedAddress(query, request)),
    );
  }

  void _queueAddressLookup(String address) {
    _onAddressChanged(address);
  }

  Future<void> _resolveTypedAddress(String address, int request) async {
    try {
      final point = await _geocoding.findPoint(address);
      if (!mounted || request != _requestGeneration) return;
      if (point == null) {
        _finishWithError(
          'Alamat belum ditemukan. Tambahkan kelurahan, kota, atau kode pos.',
        );
        return;
      }
      setState(() {
        _point = point;
        _cameraCenter = LatLng(point.latitude, point.longitude);
        _synchronized = true;
        _statusIsError = false;
        _status = 'Pin otomatis disesuaikan dengan alamat yang diketik.';
      });
      widget.onPointChanged(point);
      _moveMap(point, zoom: 17);
      _setBusy(false);
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      _finishWithError(_messageFor(error));
    }
  }

  Future<void> _useCurrentLocation() async {
    if (!widget.enabled) return;
    FocusScope.of(context).unfocus();
    _addressDebounce?.cancel();
    final request = ++_requestGeneration;
    widget.onPointChanged(null);
    setState(() {
      _point = null;
      _synchronized = false;
      _statusIsError = false;
      _status = 'Membaca lokasi toko…';
    });
    _setBusy(true);
    try {
      final current = await widget.readCurrentLocation();
      if (!mounted || request != _requestGeneration) return;
      if (current == null || !current.point.isValid) {
        _finishWithError('Lokasi toko belum berhasil dibaca. Coba lagi.');
        return;
      }
      await _reversePoint(
        current.point,
        request: request,
        successMessage: current.accuracyMeters == null
            ? 'Alamat diisi dari lokasi toko saat ini.'
            : 'Alamat diisi dari GPS (±${current.accuracyMeters!.round()} m).',
      );
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      _finishWithError(_messageFor(error));
    }
  }

  Future<void> _selectMapPoint(LatLng coordinate) async {
    if (!widget.enabled) return;
    FocusScope.of(context).unfocus();
    _addressDebounce?.cancel();
    final point = StoreGeoPoint(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
    );
    if (!point.isValid) return;
    final request = ++_requestGeneration;
    widget.onPointChanged(null);
    setState(() {
      _point = point;
      _cameraCenter = coordinate;
      _synchronized = false;
      _statusIsError = false;
      _status = 'Membaca alamat dari titik peta…';
    });
    _moveMap(point, zoom: _mapController.camera.zoom);
    _setBusy(true);
    try {
      await _reversePoint(
        point,
        request: request,
        successMessage: 'Alamat diisi dari titik yang dipilih di peta.',
      );
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      _finishWithError(_messageFor(error));
    }
  }

  Future<void> _reversePoint(
    StoreGeoPoint point, {
    required int request,
    required String successMessage,
  }) async {
    setState(() {
      _point = point;
      _cameraCenter = LatLng(point.latitude, point.longitude);
    });
    _moveMap(point, zoom: 17);
    final address = await _geocoding.findAddress(point);
    if (!mounted || request != _requestGeneration) return;
    if (address == null || address.trim().length < 8) {
      _finishWithError(
        'Titik ditemukan, tetapi alamatnya belum terbaca. Ketuk ulang atau '
        'pilih titik di dekatnya.',
      );
      return;
    }
    widget.addressController.value = TextEditingValue(
      text: address,
      selection: TextSelection.collapsed(offset: address.length),
    );
    setState(() {
      _point = point;
      _synchronized = true;
      _statusIsError = false;
      _status = successMessage;
    });
    widget.onPointChanged(point);
    _setBusy(false);
  }

  void _finishWithError(String message) {
    widget.onPointChanged(null);
    setState(() {
      _synchronized = false;
      _statusIsError = true;
      _status = message;
    });
    _setBusy(false);
  }

  void _setBusy(bool value) {
    if (_busy == value || !mounted) return;
    setState(() => _busy = value);
    widget.onBusyChanged(value);
  }

  String _messageFor(Object error) => switch (error) {
    StoreGeocodingException(:final message) => message,
    StoreLocationInputException(:final message) => message,
    _ => 'Lokasi belum dapat disinkronkan. Periksa koneksi lalu coba lagi.',
  };

  void _moveMap(StoreGeoPoint point, {required double zoom}) {
    _cameraCenter = LatLng(point.latitude, point.longitude);
    if (!_mapReady) return;
    _mapController.move(_cameraCenter, zoom.clamp(4, 19).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Alamat'),
        MerchantFormField(
          key: const Key('store-address-field'),
          controller: widget.addressController,
          hintText: 'Jalan, nomor, kelurahan, kota',
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          enabled: widget.enabled,
          validator: widget.validator,
          onChanged: _onAddressChanged,
          borderColor: _statusIsError
              ? AppColors.danger
              : _synchronized
              ? AppColors.greenSoftBorder
              : AppColors.inputBorder,
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _synchronized
                      ? Icons.check_circle_outline
                      : Icons.location_searching_outlined,
                  size: 19,
                  color: _synchronized
                      ? AppColors.greenAccent
                      : AppColors.muted,
                ),
        ),
        const SizedBox(height: 10),
        _map(),
        const SizedBox(height: 8),
        _statusLine(),
      ],
    );
  }

  Widget _map() {
    return Container(
      height: 228,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _statusIsError ? AppColors.danger : AppColors.inputBorder,
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !widget.enabled,
              child: FlutterMap(
                key: const Key('store-location-map'),
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _cameraCenter,
                  initialZoom: _point == null ? 13 : 17,
                  minZoom: 4,
                  maxZoom: 19,
                  backgroundColor: AppColors.mapGridBg,
                  onMapReady: () => _mapReady = true,
                  onTap: (_, point) => unawaited(_selectMapPoint(point)),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.savebite.savebite',
                    maxNativeZoom: 19,
                  ),
                  if (_point != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          key: const Key('store-location-marker'),
                          point: LatLng(_point!.latitude, _point!.longitude),
                          width: 50,
                          height: 50,
                          child: _StorePin(synchronized: _synchronized),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: _MapHint(synchronized: _synchronized),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: _CurrentLocationButton(
              busy: _busy,
              enabled: widget.enabled && !_busy,
              onTap: _useCurrentLocation,
            ),
          ),
          Positioned(
            left: 7,
            bottom: 6,
            child: GestureDetector(
              onTap: () => launchUrl(
                _osmCopyright,
                mode: LaunchMode.externalApplication,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                color: AppColors.white.withValues(alpha: 0.88),
                child: Text(
                  '© OpenStreetMap',
                  style: AppText.ui(9.5, color: AppColors.body),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine() {
    final icon = _busy
        ? Icons.sync
        : _statusIsError
        ? Icons.error_outline
        : _synchronized
        ? Icons.check_circle_outline
        : Icons.info_outline;
    final color = _statusIsError
        ? AppColors.danger
        : _synchronized
        ? AppColors.greenAccent
        : AppColors.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _status,
            key: const Key('store-location-status'),
            style: AppText.ui(12, color: color, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _StorePin extends StatelessWidget {
  const _StorePin({required this.synchronized});

  final bool synchronized;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: synchronized ? AppColors.terracotta : AppColors.muted,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.storefront, color: AppColors.white, size: 23),
    );
  }
}

class _MapHint extends StatelessWidget {
  const _MapHint({required this.synchronized});

  final bool synchronized;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 235),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 5)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            synchronized
                ? Icons.check_circle_outline
                : Icons.touch_app_outlined,
            size: 15,
            color: synchronized ? AppColors.greenAccent : AppColors.terracotta,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              synchronized
                  ? 'Alamat dan pin sinkron'
                  : 'Ketuk peta untuk memilih titik',
              style: AppText.ui(11, weight: 700, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentLocationButton extends StatelessWidget {
  const _CurrentLocationButton({
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('store-current-location-button'),
      button: true,
      label: 'Gunakan lokasi toko saat ini',
      child: Material(
        color: AppColors.white,
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.my_location,
                    color: AppColors.terracotta,
                    size: 19,
                  ),
                const SizedBox(width: 7),
                Text(
                  busy ? 'Membaca…' : 'Lokasi saat ini',
                  style: AppText.ui(
                    11.5,
                    weight: 700,
                    color: enabled ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
