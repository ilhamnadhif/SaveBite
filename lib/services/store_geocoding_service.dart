import 'dart:async';

import 'package:flutter/material.dart' show Locale;
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;

/// Titik hasil pencarian alamat yang sudah divalidasi.
class StoreGeoPoint {
  const StoreGeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid => isValidStoreCoordinate(latitude, longitude);
}

/// Error geocoding yang aman ditampilkan langsung pada form merchant.
class StoreGeocodingException implements Exception {
  const StoreGeocodingException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class StoreGeocodingService {
  Future<StoreGeoPoint?> findPoint(String address);

  Future<String?> findAddress(StoreGeoPoint point);
}

/// Forward/reverse geocoding dari layanan native Android/iOS.
///
/// Layanan native tidak memerlukan API key. Hasil tetap dapat kosong atau
/// terkena rate limit, sehingga caller harus menyediakan alur retry/manual.
class NativeStoreGeocodingService implements StoreGeocodingService {
  NativeStoreGeocodingService({geo.Geocoding? geocoding})
    : _geocoding = geocoding ?? geo.Geocoding(locale: _indonesianLocale);

  static const _indonesianLocale = Locale('id', 'ID');
  static const _requestTimeout = Duration(seconds: 12);

  final geo.Geocoding _geocoding;

  @override
  Future<StoreGeoPoint?> findPoint(String address) async {
    final query = address.trim();
    if (query.isEmpty) return null;
    try {
      final locations = await _geocoding
          .locationFromAddress(query, locale: _indonesianLocale)
          .timeout(_requestTimeout);
      for (final location in locations) {
        final point = StoreGeoPoint(
          latitude: location.latitude,
          longitude: location.longitude,
        );
        if (point.isValid) return point;
      }
      return null;
    } on PlatformException catch (error) {
      throw _friendlyException(error);
    } on TimeoutException {
      throw const StoreGeocodingException(
        'Pencarian alamat terlalu lama. Periksa koneksi lalu coba lagi.',
      );
    } catch (error) {
      if (error is StoreGeocodingException) rethrow;
      throw const StoreGeocodingException(
        'Alamat belum dapat dicari. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  @override
  Future<String?> findAddress(StoreGeoPoint point) async {
    if (!point.isValid) return null;
    try {
      final placemarks = await _geocoding
          .placemarkFromCoordinates(
            point.latitude,
            point.longitude,
            locale: _indonesianLocale,
          )
          .timeout(_requestTimeout);
      for (final placemark in placemarks) {
        final address = formatStorePlacemark(placemark);
        if (address != null) return address;
      }
      return null;
    } on PlatformException catch (error) {
      throw _friendlyException(error);
    } on TimeoutException {
      throw const StoreGeocodingException(
        'Pembacaan alamat terlalu lama. Periksa koneksi lalu coba lagi.',
      );
    } catch (error) {
      if (error is StoreGeocodingException) rethrow;
      throw const StoreGeocodingException(
        'Alamat dari titik peta belum dapat dibaca. Coba lagi.',
      );
    }
  }

  StoreGeocodingException _friendlyException(PlatformException error) {
    final detail = '${error.code} ${error.message ?? ''}'.toLowerCase();
    if (detail.contains('io_error') ||
        detail.contains('rate') ||
        detail.contains('network')) {
      return const StoreGeocodingException(
        'Layanan alamat sedang sibuk. Tunggu sebentar lalu coba lagi.',
      );
    }
    return const StoreGeocodingException(
      'Alamat belum dapat diproses oleh perangkat. Coba alamat yang lebih lengkap.',
    );
  }
}

bool isValidStoreCoordinate(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    (latitude != 0 || longitude != 0);

/// Membentuk alamat yang ringkas tanpa komponen berulang dari Placemark.
String? formatStorePlacemark(geo.Placemark placemark) {
  final parts = <String>[];
  final normalized = <String>{};

  void add(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (cleaned.isEmpty) return;
    final key = cleaned.toLowerCase();
    if (normalized.add(key)) parts.add(cleaned);
  }

  final street = placemark.street?.trim();
  if (street != null && street.isNotEmpty) {
    add(street);
  } else {
    final streetParts = [placemark.subThoroughfare, placemark.thoroughfare]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' ');
    add(streetParts.isEmpty ? placemark.name : streetParts);
  }
  add(placemark.subLocality);
  add(placemark.locality);
  add(placemark.subAdministrativeArea);
  add(placemark.administrativeArea);
  add(placemark.postalCode);
  add(placemark.country);

  return parts.isEmpty ? null : parts.join(', ');
}
