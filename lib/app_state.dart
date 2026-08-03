import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'data/backend/backend.dart';
import 'data/business_config.dart';
import 'data/models.dart';
import 'services/app_backend.dart';
import 'services/location_permission_support.dart';
import 'services/notification_route.dart';

enum AppMode { consumer, merchant }

enum _LoadScope {
  profile,
  consumer,
  orders,
  favorites,
  notifications,
  store,
  merchant,
  merchantReviews,
  balance,
}

/// Cache reaktif di atas backend aktif. Seluruh cache user dihapus ketika sesi
/// berubah, dan hasil request lama diabaikan memakai [_sessionEpoch].
class AppState extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _onboardingKey = 'onboarding_seen';
  static const _locationPrimedKey = 'location_primed';
  static const _locationLabelKey = 'location_label';
  static const _latitudeKey = 'location_latitude';
  static const _longitudeKey = 'location_longitude';
  static const _locationFromDeviceKey = 'location_from_device';
  static const _deviceLatitudeKey = 'device_location_latitude';
  static const _deviceLongitudeKey = 'device_location_longitude';
  static const _locationAccuracyKey = 'location_accuracy_meters';
  static const _locationReducedAccuracyKey = 'location_reduced_accuracy';
  static const _paymentMethodKey = 'default_payment_method';
  static const _merchantIntentKey = 'pending_merchant_intent';
  static const _checkoutIdempotencyKey = 'pending_checkout_idempotency_v1';
  static const _checkoutOrderIdKey = 'pending_checkout_order_ids_v1';
  static const _payoutIdempotencyKey = 'pending_payout_idempotency_v1';

  final Future<void> Function()? _idempotencyPersistenceOverride;
  SharedPreferences? _preferences;
  int _sessionEpoch = 0;
  int _consumerRequestGeneration = 0;
  int _profileRequestGeneration = 0;
  int _ordersRequestGeneration = 0;
  int _favoritesRequestGeneration = 0;
  int _notificationsRequestGeneration = 0;
  int _storeRequestGeneration = 0;
  int _merchantRequestGeneration = 0;
  int _merchantReviewsRequestGeneration = 0;
  int _balanceRequestGeneration = 0;
  StreamSubscription<List<AppNotification>>? _notificationSubscription;
  StreamSubscription<List<IncomingOrder>>? _incomingSubscription;
  StreamSubscription<List<TxRecord>>? _transactionSubscription;
  bool _isSyncingPendingPayments = false;
  final Map<String, String> _checkoutKeys = {};
  final Map<String, String> _checkoutOrderIds = {};
  final Map<String, int> _checkoutRequestsInFlight = {};
  final Map<String, String> _payoutKeys = {};

  AppState({
    @visibleForTesting Future<void> Function()? idempotencyPersistenceOverride,
  }) : _idempotencyPersistenceOverride = idempotencyPersistenceOverride;

  AppMode mode = AppMode.consumer;
  bool onboardingSeen = false;
  bool merchantSetupDone = false;
  bool locationPrimed = false;
  bool? pendingMerchantIntent;
  String lastMode = 'consumer';

  String location = 'Lokasi belum dipilih';
  double? userLatitude;
  double? userLongitude;
  bool userLocationIsFromDevice = false;
  double? deviceLatitude;
  double? deviceLongitude;
  double? userLocationAccuracyMeters;
  bool userLocationAccuracyReduced = false;
  bool hasLocationPermission = false;
  bool locationPermissionDeniedForever = false;
  bool locationServicesEnabled = true;
  bool isDeterminingLocation = false;
  BagFilter currentFilter = const BagFilter();

  bool get usesBrowserPermissionSettings =>
      LocationPermissionSupport.usesBrowserSettings;
  String get browserLocationPermissionGuidance =>
      LocationPermissionSupport.browserGuidance;
  String get locationSettingsActionLabel =>
      LocationPermissionSupport.settingsActionLabel(
        locationServicesEnabled: locationServicesEnabled,
      );

  bool isBootstrapping = false;
  bool isLoadingConsumer = false;
  bool isLoadingOrders = false;
  bool isLoadingMerchant = false;
  bool isLoadingMerchantReviews = false;
  bool isLoadingBalance = false;
  bool isLoadingNotifications = false;

  /// Error global hanya untuk bootstrap, lokasi, dan operasi lintas-domain.
  /// Loader tab memakai error per-scope agar request paralel tidak saling
  /// menghapus atau menampilkan pesan di layar yang keliru.
  String? errorMessage;
  final Map<_LoadScope, String> _loadErrors = {};

  String? get profileError => _loadErrors[_LoadScope.profile];
  String? get consumerError => _loadErrors[_LoadScope.consumer];
  String? get ordersError => _loadErrors[_LoadScope.orders];
  String? get favoritesError => _loadErrors[_LoadScope.favorites];
  String? get notificationsError => _loadErrors[_LoadScope.notifications];
  String? get storeError => _loadErrors[_LoadScope.store];
  String? get merchantError => _loadErrors[_LoadScope.merchant];
  String? get merchantReviewsError => _loadErrors[_LoadScope.merchantReviews];
  String? get balanceError => _loadErrors[_LoadScope.balance];

  static const cities = [
    'Margonda, Depok',
    'Cibinong, Bogor',
    'Kemang, Jakarta',
  ];
  static const paymentMethods = ['QRIS'];
  String defaultPaymentMethod = 'QRIS';
  String selectedBank = '';
  BusinessConfig businessConfig = const BusinessConfig();

  String userName = 'Pengguna';
  String userEmail = '';
  String userPhone = '';
  String? userAvatarUrl;
  String get userInitials {
    final parts = userName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  String storeName = '';
  String storeCategory = 'Bakery';
  String storeAddress = '';
  String openTime = '08.00';
  String closeTime = '21.00';
  String storeDescription = '';
  String? storeLogoUrl;
  double? storeLatitude;
  double? storeLongitude;

  List<Bag> _allNearby = [];
  List<Bag> _nearby = [];
  Set<String> _favIds = {};
  List<FavoriteStore> _favStores = [];
  List<OrderRecord> _active = [];
  List<OrderRecord> _history = [];
  List<AppNotification> _notifs = [];
  List<MerchantBag> _bags = [];
  List<IncomingOrder> _incoming = [];
  List<MerchantReview> _merchantReviews = [];
  List<TxRecord> _tx = [];
  List<BankAccount> _bankAccounts = [];
  List<PayoutRequest> _payouts = [];
  int balance = 0;
  int bagsSoldToday = 0;
  int incomeToday = 0;
  int incomeThisMonth = 0;
  double foodSavedKg = 0;

  List<Bag> get nearbyBags => List.unmodifiable(_nearby);
  List<Bag> get allNearbyBags => List.unmodifiable(_allNearby);
  bool get hasNearbyBags => _nearby.isNotEmpty;
  List<OrderRecord> get activeOrders => List.unmodifiable(_active);
  List<OrderRecord> get orderHistory => List.unmodifiable(_history);
  List<FavoriteStore> get favoriteStores => List.unmodifiable(_favStores);
  bool isFavorite(String id) => _favIds.contains(id);
  List<AppNotification> get notifications => List.unmodifiable(_notifs);
  int get unreadCount =>
      _notifs.where((notification) => notification.unread).length;
  List<MerchantBag> get activeBags =>
      _bags.where((bag) => bag.active).toList(growable: false);
  List<MerchantBag> get inactiveBags =>
      _bags.where((bag) => !bag.active).toList(growable: false);
  int get activeBagCount => activeBags.length;
  List<IncomingOrder> get pendingOrders => _incoming
      .where(
        (order) =>
            order.status != IncomingOrderStatus.redeemed &&
            order.status != IncomingOrderStatus.cancelled &&
            order.status != IncomingOrderStatus.expired,
      )
      .toList(growable: false);
  List<IncomingOrder> get completedOrders => _incoming
      .where(
        (order) =>
            order.status == IncomingOrderStatus.redeemed ||
            order.status == IncomingOrderStatus.cancelled ||
            order.status == IncomingOrderStatus.expired,
      )
      .toList(growable: false);
  int get redeemedBagCount => _incoming.fold<int>(
    0,
    (total, order) => order.status == IncomingOrderStatus.redeemed
        ? total + order.bags
        : total,
  );
  int get pendingOrderCount => pendingOrders.length;
  List<MerchantReview> get merchantReviews =>
      List.unmodifiable(_merchantReviews);
  List<TxRecord> get transactions => List.unmodifiable(_tx);
  List<BankAccount> get bankAccountRecords => List.unmodifiable(_bankAccounts);
  List<String> get bankAccounts =>
      _bankAccounts.map((account) => account.label).toList(growable: false);
  List<PayoutRequest> get payoutRequests => List.unmodifiable(_payouts);
  bool get usesRemoteBackend => backend.isRemote;

  BankAccount? get selectedBankAccount {
    for (final account in _bankAccounts) {
      if (account.label == selectedBank) return account;
    }
    return _bankAccounts.isEmpty ? null : _bankAccounts.first;
  }

  Future<void> restoreLocalState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _preferences = prefs;
      onboardingSeen = prefs.getBool(_onboardingKey) ?? false;
      locationPrimed = prefs.getBool(_locationPrimedKey) ?? false;
      location = prefs.getString(_locationLabelKey) ?? location;
      userLatitude = prefs.getDouble(_latitudeKey);
      userLongitude = prefs.getDouble(_longitudeKey);
      if (!_validLocationCoordinates(userLatitude, userLongitude)) {
        userLatitude = null;
        userLongitude = null;
      }
      userLocationIsFromDevice =
          prefs.getBool(_locationFromDeviceKey) ??
          (userLatitude != null && location == 'Sekitar saya');
      deviceLatitude = prefs.getDouble(_deviceLatitudeKey);
      deviceLongitude = prefs.getDouble(_deviceLongitudeKey);
      if (!_validLocationCoordinates(deviceLatitude, deviceLongitude)) {
        if (userLocationIsFromDevice) {
          deviceLatitude = userLatitude;
          deviceLongitude = userLongitude;
        } else {
          deviceLatitude = null;
          deviceLongitude = null;
        }
      }
      userLocationAccuracyMeters = deviceLatitude != null
          ? prefs.getDouble(_locationAccuracyKey)
          : null;
      userLocationAccuracyReduced =
          deviceLatitude != null &&
          (prefs.getBool(_locationReducedAccuracyKey) ?? false);
      final storedPaymentMethod = prefs.getString(_paymentMethodKey);
      defaultPaymentMethod = paymentMethods.contains(storedPaymentMethod)
          ? storedPaymentMethod!
          : 'QRIS';
      final intent = prefs.getString(_merchantIntentKey);
      pendingMerchantIntent = switch (intent) {
        'merchant' => true,
        'consumer' => false,
        _ => null,
      };
      _checkoutKeys
        ..clear()
        ..addAll(_decodeStringMap(prefs.getString(_checkoutIdempotencyKey)));
      _checkoutOrderIds
        ..clear()
        ..addAll(_decodeStringMap(prefs.getString(_checkoutOrderIdKey)))
        ..removeWhere((signature, _) => !_checkoutKeys.containsKey(signature));
      _payoutKeys
        ..clear()
        ..addAll(_decodeStringMap(prefs.getString(_payoutIdempotencyKey)));
    } catch (_) {
      // Penyimpanan lokal bukan dependency kritis; app tetap dapat digunakan.
    }
  }

  Future<SharedPreferences?> _prefs() async {
    if (_preferences != null) return _preferences;
    try {
      return _preferences = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _decodeStringMap(String? value) {
    if (value == null || value.isEmpty) return {};
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, item) => MapEntry(key.toString(), item.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistIdempotencyKeys() async {
    final override = _idempotencyPersistenceOverride;
    if (override != null) return override();
    final prefs = await _prefs();
    await Future.wait([
      if (prefs != null)
        prefs.setString(_checkoutIdempotencyKey, jsonEncode(_checkoutKeys)),
      if (prefs != null)
        prefs.setString(_checkoutOrderIdKey, jsonEncode(_checkoutOrderIds)),
      if (prefs != null)
        prefs.setString(_payoutIdempotencyKey, jsonEncode(_payoutKeys)),
    ]);
  }

  Future<void> markOnboardingSeen() async {
    onboardingSeen = true;
    await (await _prefs())?.setBool(_onboardingKey, true);
    notifyListeners();
  }

  Future<void> markLocationPrimed() async {
    locationPrimed = true;
    await (await _prefs())?.setBool(_locationPrimedKey, true);
    notifyListeners();
  }

  Future<void> setPendingMerchantIntent(bool? merchant) async {
    pendingMerchantIntent = merchant;
    final prefs = await _prefs();
    if (merchant == null) {
      await prefs?.remove(_merchantIntentKey);
    } else {
      await prefs?.setString(
        _merchantIntentKey,
        merchant ? 'merchant' : 'consumer',
      );
    }
    notifyListeners();
  }

  bool? consumePendingMerchantIntent() {
    final intent = pendingMerchantIntent;
    pendingMerchantIntent = null;
    unawaited(_prefs().then((prefs) => prefs?.remove(_merchantIntentKey)));
    return intent;
  }

  Future<bool> determineLocation({bool requestPermission = true}) async {
    isDeterminingLocation = true;
    errorMessage = null;
    notifyListeners();
    if (!backend.isRemote) {
      locationServicesEnabled = true;
      hasLocationPermission = true;
      locationPermissionDeniedForever = false;
      await setLocationWithCoordinates(
        'Margonda, Depok',
        -6.3725,
        106.8323,
        reload: false,
      );
      await markLocationPrimed();
      await loadConsumerHome();
      isDeterminingLocation = false;
      notifyListeners();
      return true;
    }
    try {
      locationServicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!locationServicesEnabled) {
        errorMessage =
            LocationPermissionSupport.locationServicesDisabledMessage();
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      hasLocationPermission =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      locationPermissionDeniedForever =
          permission == LocationPermission.deniedForever;
      if (!hasLocationPermission) {
        errorMessage = usesBrowserPermissionSettings
            ? browserLocationPermissionGuidance
            : locationPermissionDeniedForever
            ? LocationPermissionSupport.permissionBlockedMessage()
            : 'Izin lokasi diperlukan untuk menampilkan bag terdekat.';
        return false;
      }
      var reducedAccuracy = false;
      try {
        reducedAccuracy =
            await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced;
      } catch (_) {
        // Tidak semua platform melaporkan status precise/reduced.
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!_validLocationCoordinates(position.latitude, position.longitude)) {
        throw const BackendException(
          'invalid_location',
          'Perangkat mengembalikan titik lokasi yang tidak valid.',
        );
      }
      await setLocationWithCoordinates(
        'Sekitar saya',
        position.latitude,
        position.longitude,
        reload: false,
        fromDevice: true,
        accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
        reducedAccuracy: reducedAccuracy,
      );
      await markLocationPrimed();
      await loadConsumerHome();
      return true;
    } catch (error) {
      errorMessage = _messageFor(
        error,
        fallback: 'Lokasi tidak dapat dibaca. Coba lagi.',
      );
      return false;
    } finally {
      isDeterminingLocation = false;
      notifyListeners();
    }
  }

  /// Membaca titik fisik toko tanpa mengubah lokasi discovery konsumen.
  Future<({double latitude, double longitude, double accuracy})?>
  determineStoreLocation({bool requestPermission = true}) async {
    isDeterminingLocation = true;
    errorMessage = null;
    notifyListeners();
    if (!backend.isRemote) {
      locationServicesEnabled = true;
      hasLocationPermission = true;
      locationPermissionDeniedForever = false;
      isDeterminingLocation = false;
      notifyListeners();
      return (latitude: -6.3720, longitude: 106.8318, accuracy: 5.0);
    }
    try {
      locationServicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!locationServicesEnabled) {
        errorMessage =
            LocationPermissionSupport.locationServicesDisabledMessage();
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      hasLocationPermission =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      locationPermissionDeniedForever =
          permission == LocationPermission.deniedForever;
      if (!hasLocationPermission) {
        errorMessage = usesBrowserPermissionSettings
            ? browserLocationPermissionGuidance
            : locationPermissionDeniedForever
            ? LocationPermissionSupport.permissionBlockedMessage()
            : 'Izin lokasi diperlukan untuk menyimpan titik toko.';
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!_validLocationCoordinates(position.latitude, position.longitude)) {
        throw const BackendException(
          'invalid_store_location',
          'Perangkat mengembalikan titik toko yang tidak valid.',
        );
      }
      return (
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (error) {
      errorMessage = _messageFor(
        error,
        fallback: 'Lokasi toko tidak dapat dibaca. Coba lagi.',
      );
      return null;
    } finally {
      isDeterminingLocation = false;
      notifyListeners();
    }
  }

  Future<bool> openLocationSettings() =>
      LocationPermissionSupport.openSettings(locationServicesEnabled: false);

  Future<bool> openAppSettings() =>
      LocationPermissionSupport.openSettings(locationServicesEnabled: true);

  Future<bool> openRelevantLocationSettings() =>
      LocationPermissionSupport.openSettings(
        locationServicesEnabled: locationServicesEnabled,
      );

  Future<void> setLocationWithCoordinates(
    String label,
    double latitude,
    double longitude, {
    bool reload = true,
    bool fromDevice = false,
    double? accuracyMeters,
    bool reducedAccuracy = false,
  }) async {
    if (!_validLocationCoordinates(latitude, longitude)) {
      throw ArgumentError('Koordinat lokasi tidak valid.');
    }
    location = label;
    userLatitude = latitude;
    userLongitude = longitude;
    userLocationIsFromDevice = fromDevice;
    if (fromDevice) {
      deviceLatitude = latitude;
      deviceLongitude = longitude;
      userLocationAccuracyMeters = accuracyMeters;
      userLocationAccuracyReduced = reducedAccuracy;
    }
    final prefs = await _prefs();
    await prefs?.setString(_locationLabelKey, label);
    await prefs?.setDouble(_latitudeKey, latitude);
    await prefs?.setDouble(_longitudeKey, longitude);
    await prefs?.setBool(_locationFromDeviceKey, fromDevice);
    if (fromDevice) {
      await prefs?.setDouble(_deviceLatitudeKey, latitude);
      await prefs?.setDouble(_deviceLongitudeKey, longitude);
      if (accuracyMeters != null) {
        await prefs?.setDouble(_locationAccuracyKey, accuracyMeters);
      } else {
        await prefs?.remove(_locationAccuracyKey);
      }
      await prefs?.setBool(_locationReducedAccuracyKey, reducedAccuracy);
    }
    notifyListeners();
    if (reload) await loadConsumerHome();
  }

  bool get hasValidUserLocation =>
      _validLocationCoordinates(userLatitude, userLongitude);

  bool get hasValidDeviceLocation =>
      _validLocationCoordinates(deviceLatitude, deviceLongitude);

  static bool _validLocationCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (latitude != 0 || longitude != 0);

  void setLocation(String value) {
    const coordinates = <String, (double, double)>{
      'Margonda, Depok': (-6.3725, 106.8323),
      'Cibinong, Bogor': (-6.4853, 106.8422),
      'Kemang, Jakarta': (-6.2607, 106.8134),
    };
    final point = coordinates[value];
    if (point != null) {
      unawaited(setLocationWithCoordinates(value, point.$1, point.$2));
    } else {
      location = value;
      notifyListeners();
    }
  }

  Future<void> setBagFilter(BagFilter filter) async {
    currentFilter = filter;
    _nearby = _allNearby
        .where((bag) => bagMatchesFilter(bag, currentFilter))
        .toList(growable: false);
    notifyListeners();
  }

  Future<List<Bag>> search(String query) => backend.searchBags(
    query.trim(),
    latitude: userLatitude,
    longitude: userLongitude,
    filter: currentFilter,
  );
  Future<List<Bag>> bagsByMerchant(String id) => backend.bagsByMerchant(id);

  Future<void> bootstrap() async {
    final epoch = _sessionEpoch;
    isBootstrapping = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        backend.currentProfile(),
        backend.myStore(),
        backend.businessConfig(),
      ]);
      if (epoch != _sessionEpoch) return;
      _applyProfile(results[0] as Profile?);
      _applyStore(results[1] as StoreProfile?);
      businessConfig = results[2] as BusinessConfig;
      await _startRealtime(epoch);
    } catch (error) {
      if (epoch == _sessionEpoch) {
        errorMessage = _messageFor(error);
        rethrow;
      }
    } finally {
      if (epoch == _sessionEpoch) {
        isBootstrapping = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadProfile() async {
    final epoch = _sessionEpoch;
    final generation = ++_profileRequestGeneration;
    _clearLoadError(_LoadScope.profile);
    try {
      final profile = await backend.currentProfile();
      if (epoch != _sessionEpoch || generation != _profileRequestGeneration) {
        return;
      }
      _applyProfile(profile);
      notifyListeners();
    } catch (error) {
      if (generation == _profileRequestGeneration) {
        _setLoadError(_LoadScope.profile, error, epoch);
      }
    }
  }

  Future<void> loadBusinessConfig() async {
    final epoch = _sessionEpoch;
    try {
      final config = await backend.businessConfig();
      if (epoch != _sessionEpoch) return;
      businessConfig = config;
      notifyListeners();
    } catch (_) {
      // Default migration tetap dipakai saat konfigurasi remote tak terjangkau.
    }
  }

  Future<void> loadConsumerHome() async {
    final epoch = _sessionEpoch;
    final generation = ++_consumerRequestGeneration;
    isLoadingConsumer = true;
    _loadErrors.remove(_LoadScope.consumer);
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        backend.nearbyBags(
          latitude: userLatitude,
          longitude: userLongitude,
          filter: const BagFilter(),
        ),
        backend.favoriteMerchantIds(),
      ]);
      if (epoch != _sessionEpoch || generation != _consumerRequestGeneration) {
        return;
      }
      _allNearby = results[0] as List<Bag>;
      _nearby = _allNearby
          .where((bag) => bagMatchesFilter(bag, currentFilter))
          .toList(growable: false);
      _favIds = results[1] as Set<String>;
    } catch (error) {
      if (generation == _consumerRequestGeneration) {
        _setLoadError(_LoadScope.consumer, error, epoch);
      }
    } finally {
      if (epoch == _sessionEpoch && generation == _consumerRequestGeneration) {
        isLoadingConsumer = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadOrders() async {
    final epoch = _sessionEpoch;
    final generation = ++_ordersRequestGeneration;
    final checkoutKeysAtRequestStart = Map<String, String>.from(_checkoutKeys);
    final checkoutOrderIdsAtRequestStart = Map<String, String>.from(
      _checkoutOrderIds,
    );
    isLoadingOrders = true;
    _loadErrors.remove(_LoadScope.orders);
    notifyListeners();
    try {
      final results = await Future.wait([
        backend.activeOrders(),
        backend.orderHistory(),
      ]);
      if (epoch != _sessionEpoch || generation != _ordersRequestGeneration) {
        return;
      }
      final loadedActive = results[0];
      _active = loadedActive
          .where((order) => !order.paymentState.isTerminalFailure)
          .toList();
      _history = [...results[1]];
      for (final terminal in loadedActive.where(
        (order) => order.paymentState.isTerminalFailure,
      )) {
        if (!_history.any((order) => order.id == terminal.id)) {
          _history.add(terminal);
        }
      }
      if (checkoutKeysAtRequestStart.isNotEmpty) {
        for (final resolved in <OrderRecord>[
          ..._active,
          ..._history,
        ].where((order) => !order.paymentState.isAwaitingCustomer)) {
          final signature = _checkoutSignatureForOrder(resolved);
          final expectedKey = checkoutKeysAtRequestStart[signature];
          final expectedOrderId = checkoutOrderIdsAtRequestStart[signature];
          if (expectedKey != null && expectedOrderId == resolved.id) {
            await _clearCompletedCheckoutKey(
              resolved,
              expectedKey: expectedKey,
              expectedOrderId: expectedOrderId,
            );
          }
        }
      }
      if (backend.isRemote &&
          _active.any((order) => order.paymentState.isAwaitingCustomer)) {
        unawaited(_syncPendingPayments(epoch));
      }
    } catch (error) {
      if (generation == _ordersRequestGeneration) {
        _setLoadError(_LoadScope.orders, error, epoch);
      }
    } finally {
      if (epoch == _sessionEpoch && generation == _ordersRequestGeneration) {
        isLoadingOrders = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadFavorites() async {
    final epoch = _sessionEpoch;
    final generation = ++_favoritesRequestGeneration;
    _clearLoadError(_LoadScope.favorites);
    try {
      final results = await Future.wait<dynamic>([
        backend.favoriteMerchantIds(),
        backend.favoriteStores(),
      ]);
      if (epoch != _sessionEpoch || generation != _favoritesRequestGeneration) {
        return;
      }
      _favIds = results[0] as Set<String>;
      _favStores = results[1] as List<FavoriteStore>;
      notifyListeners();
    } catch (error) {
      if (generation == _favoritesRequestGeneration) {
        _setLoadError(_LoadScope.favorites, error, epoch);
      }
    }
  }

  Future<void> loadNotifications() async {
    final epoch = _sessionEpoch;
    final generation = ++_notificationsRequestGeneration;
    isLoadingNotifications = true;
    _loadErrors.remove(_LoadScope.notifications);
    notifyListeners();
    try {
      final values = await backend.notifications();
      if (epoch != _sessionEpoch ||
          generation != _notificationsRequestGeneration) {
        return;
      }
      _notifs = values;
    } catch (error) {
      if (generation == _notificationsRequestGeneration) {
        _setLoadError(_LoadScope.notifications, error, epoch);
      }
    } finally {
      if (epoch == _sessionEpoch &&
          generation == _notificationsRequestGeneration) {
        isLoadingNotifications = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadStore() async {
    final epoch = _sessionEpoch;
    final generation = ++_storeRequestGeneration;
    _clearLoadError(_LoadScope.store);
    try {
      final store = await backend.myStore();
      if (epoch != _sessionEpoch || generation != _storeRequestGeneration) {
        return;
      }
      _applyStore(store);
      notifyListeners();
    } catch (error) {
      if (generation == _storeRequestGeneration) {
        _setLoadError(_LoadScope.store, error, epoch);
      }
    }
  }

  Future<void> loadMerchantData() async {
    final epoch = _sessionEpoch;
    final generation = ++_merchantRequestGeneration;
    isLoadingMerchant = true;
    _loadErrors.remove(_LoadScope.merchant);
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        backend.myBags(),
        backend.incomingOrders(),
        backend.merchantStats(),
      ]);
      if (epoch != _sessionEpoch || generation != _merchantRequestGeneration) {
        return;
      }
      _bags = results[0] as List<MerchantBag>;
      _incoming = results[1] as List<IncomingOrder>;
      _applyStats(results[2] as MerchantStats);
    } catch (error) {
      if (generation == _merchantRequestGeneration) {
        _setLoadError(_LoadScope.merchant, error, epoch);
      }
    } finally {
      if (epoch == _sessionEpoch && generation == _merchantRequestGeneration) {
        isLoadingMerchant = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMerchantReviews() async {
    final epoch = _sessionEpoch;
    final generation = ++_merchantReviewsRequestGeneration;
    isLoadingMerchantReviews = true;
    _loadErrors.remove(_LoadScope.merchantReviews);
    notifyListeners();
    try {
      final values = await backend.merchantReviews();
      if (epoch != _sessionEpoch ||
          generation != _merchantReviewsRequestGeneration) {
        return;
      }
      _merchantReviews = values;
    } catch (error) {
      if (generation == _merchantReviewsRequestGeneration) {
        _setLoadError(_LoadScope.merchantReviews, error, epoch);
      }
    } finally {
      if (epoch == _sessionEpoch &&
          generation == _merchantReviewsRequestGeneration) {
        isLoadingMerchantReviews = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadBalance() async {
    final epoch = _sessionEpoch;
    final generation = ++_balanceRequestGeneration;
    isLoadingBalance = true;
    _loadErrors.remove(_LoadScope.balance);
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        backend.balance(),
        backend.transactions(),
        backend.bankAccounts(),
        backend.payoutRequests(),
      ]);
      if (epoch != _sessionEpoch || generation != _balanceRequestGeneration) {
        return;
      }
      balance = results[0] as int;
      _tx = results[1] as List<TxRecord>;
      _bankAccounts = results[2] as List<BankAccount>;
      _payouts = results[3] as List<PayoutRequest>;
      if (_bankAccounts.isNotEmpty &&
          !_bankAccounts.any((account) => account.label == selectedBank)) {
        final defaultAccount = _bankAccounts.where(
          (account) => account.isDefault,
        );
        selectedBank =
            (defaultAccount.isEmpty
                    ? _bankAccounts.first
                    : defaultAccount.first)
                .label;
      }
    } catch (error) {
      if (generation == _balanceRequestGeneration) {
        _setLoadError(_LoadScope.balance, error, epoch);
      }
    } finally {
      if (epoch == _sessionEpoch && generation == _balanceRequestGeneration) {
        isLoadingBalance = false;
        notifyListeners();
      }
    }
  }

  Future<void> _startRealtime(int epoch) async {
    await _cancelRealtime();
    if (epoch != _sessionEpoch) return;
    _notificationSubscription = backend.watchNotifications().listen(
      (values) {
        if (epoch != _sessionEpoch) return;
        final previous = {
          for (final notification in _notifs)
            notification.id: notification.unread,
        };
        final changed = values.where(
          (notification) =>
              !previous.containsKey(notification.id) ||
              previous[notification.id] != notification.unread,
        );
        _notifs = values;
        notifyListeners();
        final routes = changed.map((value) => value.route).whereType<String>();
        if (routes.any(
          (route) => route == 'orders' || route.startsWith('order:'),
        )) {
          unawaited(loadOrders());
        }
        if (merchantSetupDone &&
            routes.any(isMerchantOrdersNotificationRoute)) {
          unawaited(loadMerchantData());
        }
        if (merchantSetupDone && routes.contains('merchant_reviews')) {
          unawaited(loadMerchantReviews());
        }
        if (merchantSetupDone && routes.contains('merchant_balance')) {
          unawaited(loadBalance());
        }
        if (routes.contains('consumer_home')) {
          unawaited(loadConsumerHome());
        }
      },
      onError: (Object error) {
        _setLoadError(_LoadScope.notifications, error, epoch);
      },
    );
    if (!merchantSetupDone) return;
    _incomingSubscription = backend.watchIncomingOrders().listen(
      (values) {
        if (epoch != _sessionEpoch) return;
        _incoming = values;
        notifyListeners();
      },
      onError: (Object error) {
        _setLoadError(_LoadScope.merchant, error, epoch);
      },
    );
    _transactionSubscription = backend.watchTransactions().listen(
      (values) async {
        if (epoch != _sessionEpoch) return;
        _tx = values;
        try {
          balance = await backend.balance();
        } catch (_) {}
        if (epoch == _sessionEpoch) notifyListeners();
      },
      onError: (Object error) {
        _setLoadError(_LoadScope.balance, error, epoch);
      },
    );
  }

  Future<void> _cancelRealtime() async {
    await _notificationSubscription?.cancel();
    await _incomingSubscription?.cancel();
    await _transactionSubscription?.cancel();
    _notificationSubscription = null;
    _incomingSubscription = null;
    _transactionSubscription = null;
  }

  Future<bool> toggleFavorite(String merchantId) async {
    final added = await backend.toggleFavorite(merchantId);
    added ? _favIds.add(merchantId) : _favIds.remove(merchantId);
    notifyListeners();
    unawaited(loadFavorites());
    return added;
  }

  Future<OrderRecord> placeOrder(
    Bag bag,
    int quantity,
    String method, {
    String? idempotencyKey,
  }) async {
    final requestEpoch = _sessionEpoch;
    // Snapshot bag dari order lama sengaja tidak membawa stok katalog terbaru.
    // Pada backend remote, PostgreSQL tetap menjadi validator stok otoritatif.
    if (quantity < 1 || (!backend.isRemote && quantity > bag.quantityLeft)) {
      throw const BackendException(
        'invalid_quantity',
        'Jumlah bag tidak sesuai stok yang tersedia.',
      );
    }
    final requestSignature = _checkoutSignature(bag, quantity, method);
    final previousKey = _checkoutKeys[requestSignature];
    final key = idempotencyKey ?? previousKey ?? _uuid.v4();
    if (previousKey != null && previousKey != key) {
      _checkoutOrderIds.remove(requestSignature);
    }
    _checkoutKeys[requestSignature] = key;
    _checkoutRequestsInFlight.update(
      requestSignature,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    try {
      try {
        await _persistIdempotencyKeys();
      } catch (_) {
        // SharedPreferences/localStorage bersifat best-effort. Key tetap ada
        // di memori dan wajib diteruskan ke server; kegagalan storage browser
        // tidak boleh menghentikan pembuatan order sebelum RPC dipanggil.
      }
      final order = await backend.placeOrder(
        bag,
        quantity,
        method,
        idempotencyKey: key,
      );
      _cacheOrder(order);
      if (_checkoutKeys[requestSignature] == key) {
        if (order.paymentState.isAwaitingCustomer && order.id.isNotEmpty) {
          _checkoutOrderIds[requestSignature] = order.id;
        } else if (!order.paymentState.isAwaitingCustomer) {
          _checkoutKeys.remove(requestSignature);
          _checkoutOrderIds.remove(requestSignature);
        }
        try {
          await _persistIdempotencyKeys();
        } catch (_) {
          // Order sudah committed dan key telah dipersist sebelum request.
          // Asosiasi/cleanup dapat dipulihkan lewat retry berikutnya.
        }
      }
      notifyListeners();
      return order;
    } finally {
      if (requestEpoch == _sessionEpoch) {
        final remaining =
            (_checkoutRequestsInFlight[requestSignature] ?? 1) - 1;
        if (remaining <= 0) {
          _checkoutRequestsInFlight.remove(requestSignature);
        } else {
          _checkoutRequestsInFlight[requestSignature] = remaining;
        }
      }
    }
  }

  /// Memulihkan order yang sudah committed ketika respons create terputus.
  /// Pencocokan memakai seluruh signature checkout dan hanya menerima state
  /// pembayaran yang masih dapat dilanjutkan atau sudah terverifikasi lunas.
  Future<OrderRecord?> recoverCheckout(
    Bag bag,
    int quantity,
    String method,
  ) async {
    final orders = await backend.activeOrders();
    final candidates =
        orders
            .where(
              (order) =>
                  order.bag.id == bag.id &&
                  order.quantity == quantity &&
                  order.paymentMethod == method &&
                  (order.paymentState.isAwaitingCustomer ||
                      order.paymentState.isPaid),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final leftTime =
                left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final rightTime =
                right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return rightTime.compareTo(leftTime);
          });
    if (candidates.isEmpty) return null;
    final recovered = candidates.first.copyWith(bag: bag);
    _cacheOrder(recovered);
    if (recovered.id.isNotEmpty) {
      _checkoutOrderIds[_checkoutSignature(bag, quantity, method)] =
          recovered.id;
      try {
        await _persistIdempotencyKeys();
      } catch (_) {
        // Recovery tetap sah; asosiasi lokal dapat dibuat lagi saat startup.
      }
    }
    notifyListeners();
    return recovered;
  }

  /// Sinkronisasi eksplisit setelah pengguna menyelesaikan pemindaian QRIS.
  /// UI tidak pernah dipakai sebagai bukti pembayaran; backend mengambil
  /// status resmi provider terlebih dahulu.
  Future<OrderRecord> refreshPayment(OrderRecord order) async {
    final epoch = _sessionEpoch;
    final refreshed = await backend.refreshPayment(order);
    if (epoch != _sessionEpoch) return refreshed;
    _cacheOrder(refreshed);
    await _clearCompletedCheckoutKey(refreshed);
    notifyListeners();
    return refreshed;
  }

  Future<void> _syncPendingPayments(int epoch) async {
    if (_isSyncingPendingPayments || epoch != _sessionEpoch) return;
    _isSyncingPendingPayments = true;
    try {
      final pending = _active
          .where((order) => order.paymentState.isAwaitingCustomer)
          .take(5)
          .toList(growable: false);
      for (final order in pending) {
        if (epoch != _sessionEpoch) return;
        try {
          final refreshed = await backend.refreshPayment(order);
          if (epoch != _sessionEpoch) return;
          _cacheOrder(refreshed);
          await _clearCompletedCheckoutKey(refreshed);
        } catch (_) {
          // Daftar tetap dapat dipakai ketika provider sementara tidak dapat
          // dijangkau. Pengguna dapat mencoba cek status secara manual.
        }
      }
      if (epoch == _sessionEpoch) notifyListeners();
    } finally {
      _isSyncingPendingPayments = false;
    }
  }

  void _cacheOrder(OrderRecord order) {
    _active = [
      for (final item in _active)
        if (item.id != order.id) item,
    ];
    _history = [
      for (final item in _history)
        if (item.id != order.id) item,
    ];
    if (order.status == OrderStatus.done ||
        order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.expired ||
        order.paymentState.isTerminalFailure) {
      _history = [order, ..._history];
    } else {
      _active = [order, ..._active];
    }
  }

  String _checkoutSignature(Bag bag, int quantity, String method) =>
      '${bag.id}|$quantity|$method';

  String _checkoutSignatureForOrder(OrderRecord order) =>
      _checkoutSignature(order.bag, order.quantity, order.paymentMethod);

  Future<void> _clearCompletedCheckoutKey(
    OrderRecord order, {
    String? expectedKey,
    String? expectedOrderId,
  }) async {
    if (order.paymentState.isAwaitingCustomer) return;
    final signature = _checkoutSignatureForOrder(order);
    final associatedOrderId = _checkoutOrderIds[signature];
    if (associatedOrderId == null || associatedOrderId != order.id) return;
    if (expectedOrderId != null && associatedOrderId != expectedOrderId) return;
    if ((_checkoutRequestsInFlight[signature] ?? 0) > 0) return;
    if (_active.any(
      (active) =>
          active.paymentState.isAwaitingCustomer &&
          _checkoutSignatureForOrder(active) == signature,
    )) {
      return;
    }
    if (expectedKey != null && _checkoutKeys[signature] != expectedKey) return;
    if (_checkoutKeys.remove(signature) == null) return;
    _checkoutOrderIds.remove(signature);
    try {
      await _persistIdempotencyKeys();
    } catch (_) {
      // Status provider sudah tersimpan di server. Cleanup lokal boleh dicoba
      // lagi saat sesi berikutnya tanpa mengubah hasil pembayaran.
    }
  }

  Future<OrderRecord> issuePickupToken(OrderRecord order) async {
    final refreshed = await backend.issuePickupToken(order);
    final activeIndex = _active.indexWhere((item) => item.id == order.id);
    if (activeIndex >= 0) _active[activeIndex] = refreshed;
    final historyIndex = _history.indexWhere((item) => item.id == order.id);
    if (historyIndex >= 0) _history[historyIndex] = refreshed;
    notifyListeners();
    return refreshed;
  }

  Future<void> submitReview(
    OrderRecord order,
    int rating,
    List<String> tags,
    String comment,
  ) async {
    await backend.submitReview(order, rating, tags, comment);
    final index = _history.indexWhere((item) => item.id == order.id);
    if (index >= 0) {
      _history[index] = _history[index].copyWith(
        reviewed: true,
        canRate: false,
      );
    }
    notifyListeners();
  }

  Future<void> addBag({
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    required String description,
    required List<String> contents,
    required int originalPrice,
    String? imageUrl,
    DateTime? availableOn,
    DateTime? pickupStartsAt,
    DateTime? pickupEndsAt,
  }) async {
    await backend.addBag(
      title: title,
      salePrice: salePrice,
      pickupWindow: pickupWindow,
      total: total,
      description: description,
      contents: contents,
      originalPrice: originalPrice,
      imageUrl: imageUrl,
      availableOn: availableOn,
      pickupStartsAt: pickupStartsAt,
      pickupEndsAt: pickupEndsAt,
    );
    unawaited(loadMerchantData());
  }

  Future<void> updateBag(
    MerchantBag bag, {
    required String title,
    required int salePrice,
    required String pickupWindow,
    required int total,
    required String description,
    required List<String> contents,
    required int originalPrice,
    String? imageUrl,
    DateTime? availableOn,
    DateTime? pickupStartsAt,
    DateTime? pickupEndsAt,
  }) async {
    await backend.updateBag(
      bag,
      title: title,
      salePrice: salePrice,
      pickupWindow: pickupWindow,
      total: total,
      description: description,
      contents: contents,
      originalPrice: originalPrice,
      imageUrl: imageUrl,
      availableOn: availableOn,
      pickupStartsAt: pickupStartsAt,
      pickupEndsAt: pickupEndsAt,
    );
    unawaited(loadMerchantData());
  }

  Future<void> toggleBagActive(MerchantBag bag) async {
    await backend.setBagActive(bag, !bag.active);
    final index = _bags.indexWhere((item) => item.id == bag.id);
    if (index >= 0) _bags[index] = bag.copyWith(active: !bag.active);
    notifyListeners();
    unawaited(loadMerchantData());
  }

  Future<void> duplicateBag(MerchantBag bag) async {
    await backend.duplicateBag(bag);
    unawaited(loadMerchantData());
  }

  Future<void> markOrderReady(String orderId) async {
    await backend.markOrderReady(orderId);
    final index = _incoming.indexWhere((order) => order.id == orderId);
    if (index >= 0) {
      _incoming[index] = _incoming[index].copyWith(
        status: IncomingOrderStatus.ready,
        needsAction: false,
      );
    }
    notifyListeners();
    unawaited(loadMerchantData());
    unawaited(loadOrders());
  }

  Future<IncomingOrder> cancelMerchantOrder(String orderId) async {
    final cancelled = await backend.cancelMerchantOrder(orderId);
    final incomingIndex = _incoming.indexWhere(
      (order) => order.id == cancelled.id,
    );
    if (incomingIndex >= 0) {
      _incoming[incomingIndex] = cancelled;
    } else {
      _incoming.insert(0, cancelled);
    }

    final consumerIndex = _active.indexWhere(
      (order) => order.id == cancelled.id,
    );
    if (consumerIndex >= 0) {
      final consumerOrder = _active.removeAt(consumerIndex);
      _history.insert(
        0,
        consumerOrder.copyWith(
          status: OrderStatus.cancelled,
          canRate: false,
          clearPickupToken: true,
        ),
      );
    }
    notifyListeners();
    unawaited(loadMerchantData());
    unawaited(loadOrders());
    unawaited(loadConsumerHome());
    return cancelled;
  }

  Future<IncomingOrder?> redeemOrder(String pickupToken) async {
    final order = await backend.redeemOrder(pickupToken);
    if (order != null) {
      final index = _incoming.indexWhere((item) => item.id == order.id);
      if (index >= 0) {
        _incoming[index] = order;
      } else {
        _incoming.insert(0, order);
      }
    }
    notifyListeners();
    unawaited(loadMerchantData());
    unawaited(loadBalance());
    unawaited(loadOrders());
    return order;
  }

  Future<BankAccount> saveBankAccount({
    required String bankCode,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
    String? idempotencyKey,
  }) async {
    final account = await backend.saveBankAccount(
      bankCode: bankCode,
      bankName: bankName,
      accountNumber: accountNumber,
      accountHolder: accountHolder,
      idempotencyKey: idempotencyKey ?? _uuid.v4(),
    );
    // Backend remote mengembalikan snapshot read-only/fixed-length. Bentuk
    // daftar baru agar penambahan rekening tidak gagal setelah RPC sebenarnya
    // sudah berhasil menyimpan data.
    _bankAccounts = [
      account,
      for (final item in _bankAccounts)
        if (item.id != account.id) item,
    ];
    selectedBank = account.label;
    notifyListeners();
    unawaited(loadBalance());
    return account;
  }

  Future<PayoutRequest> withdraw(int amount, {String? idempotencyKey}) async {
    if (!businessConfig.payoutsEnabled) {
      throw const BackendException(
        'payout_disabled',
        'Fitur penarikan dana belum diaktifkan oleh operator.',
      );
    }
    final account = selectedBankAccount;
    if (account == null) {
      throw const BackendException(
        'bank_required',
        'Tambahkan rekening bank sebelum menarik saldo.',
      );
    }
    final signature = '${account.id}|$amount';
    final key = idempotencyKey ?? _payoutKeys.putIfAbsent(signature, _uuid.v4);
    _payoutKeys[signature] = key;
    await _persistIdempotencyKeys();
    final request = await backend.requestPayout(
      amount: amount,
      bankAccountId: account.id,
      idempotencyKey: key,
    );
    if (_payoutKeys[signature] == key) {
      _payoutKeys.remove(signature);
      try {
        await _persistIdempotencyKeys();
      } catch (_) {
        // Request sudah committed; cleanup lokal dapat dicoba saat sesi ditutup.
      }
    }
    _payouts.insert(0, request);
    notifyListeners();
    unawaited(loadBalance());
    return request;
  }

  Future<void> markAllNotificationsRead() async {
    await backend.markAllNotificationsRead();
    _notifs = [
      for (final notification in _notifs) notification.copyWith(unread: false),
    ];
    notifyListeners();
    unawaited(loadNotifications());
  }

  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
  }) async {
    await backend.updateProfile(
      name: name,
      email: email,
      phone: phone,
      avatarUrl: avatarUrl,
    );
    if (name != null && name.trim().isNotEmpty) userName = name.trim();
    if (phone != null) userPhone = phone.trim();
    if (avatarUrl != null) userAvatarUrl = avatarUrl;
    notifyListeners();
    unawaited(loadProfile());
  }

  Future<void> updateStore({
    String? name,
    String? category,
    String? address,
    String? open,
    String? close,
    String? description,
    String? logoUrl,
    double? latitude,
    double? longitude,
  }) async {
    final resolvedLatitude = latitude ?? storeLatitude;
    final resolvedLongitude = longitude ?? storeLongitude;
    if (!_validLocationCoordinates(resolvedLatitude, resolvedLongitude)) {
      throw const BackendException(
        'invalid_store_location',
        'Alamat toko harus memiliki titik peta yang valid.',
      );
    }
    await backend.upsertStore(
      name: name ?? storeName,
      category: category ?? storeCategory,
      address: address ?? storeAddress,
      open: open ?? openTime,
      close: close ?? closeTime,
      description: description ?? storeDescription,
      logoUrl: logoUrl ?? storeLogoUrl,
      latitude: resolvedLatitude,
      longitude: resolvedLongitude,
    );
    merchantSetupDone = true;
    if (name != null && name.trim().isNotEmpty) storeName = name.trim();
    if (category != null) storeCategory = category;
    if (address != null && address.trim().isNotEmpty) {
      storeAddress = address.trim();
    }
    if (open != null) openTime = open;
    if (close != null) closeTime = close;
    if (description != null) storeDescription = description;
    if (logoUrl != null) storeLogoUrl = logoUrl;
    storeLatitude = resolvedLatitude;
    storeLongitude = resolvedLongitude;
    await _startRealtime(_sessionEpoch);
    notifyListeners();
  }

  Future<String?> uploadImage(BackendBucket bucket) =>
      backend.uploadImage(bucket);

  Future<String?> uploadImageBytes(
    BackendBucket bucket,
    Uint8List bytes, {
    required String filename,
  }) => backend.uploadImageBytes(bucket, bytes, filename: filename);

  void setDefaultPaymentMethod(String method) {
    final supportedMethod = paymentMethods.contains(method) ? method : 'QRIS';
    defaultPaymentMethod = supportedMethod;
    unawaited(
      _prefs().then(
        (prefs) => prefs?.setString(_paymentMethodKey, supportedMethod),
      ),
    );
    notifyListeners();
  }

  Future<void> setBankAccount(BankAccount account) async {
    await backend.setDefaultBankAccount(account.id);
    _bankAccounts = [
      for (final item in _bankAccounts)
        item.copyWith(isDefault: item.id == account.id),
    ];
    selectedBank = account.label;
    notifyListeners();
  }

  void rememberMode(String value) {
    lastMode = value;
    unawaited(
      backend.setLastMode(value).catchError((Object error) {
        if (kDebugMode) debugPrint('Mode preference was not persisted: $error');
      }),
    );
  }

  void switchToMerchant() {
    mode = AppMode.merchant;
    notifyListeners();
  }

  void switchToConsumer() {
    mode = AppMode.consumer;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await backend.deleteAccount();
    await clearSessionState();
  }

  Future<void> clearSessionState({bool notify = true}) async {
    _sessionEpoch++;
    _invalidateLoadRequests();
    await _cancelRealtime();
    backend.clearSessionCache();
    _checkoutKeys.clear();
    _checkoutOrderIds.clear();
    _checkoutRequestsInFlight.clear();
    _payoutKeys.clear();
    _isSyncingPendingPayments = false;
    final prefs = await _prefs();
    await Future.wait([
      if (prefs != null) prefs.remove(_checkoutIdempotencyKey),
      if (prefs != null) prefs.remove(_checkoutOrderIdKey),
      if (prefs != null) prefs.remove(_payoutIdempotencyKey),
      if (prefs != null) prefs.remove(_locationPrimedKey),
      if (prefs != null) prefs.remove(_locationLabelKey),
      if (prefs != null) prefs.remove(_latitudeKey),
      if (prefs != null) prefs.remove(_longitudeKey),
      if (prefs != null) prefs.remove(_locationFromDeviceKey),
      if (prefs != null) prefs.remove(_deviceLatitudeKey),
      if (prefs != null) prefs.remove(_deviceLongitudeKey),
      if (prefs != null) prefs.remove(_locationAccuracyKey),
      if (prefs != null) prefs.remove(_locationReducedAccuracyKey),
      if (prefs != null) prefs.remove(_paymentMethodKey),
    ]);
    pendingMerchantIntent = null;
    mode = AppMode.consumer;
    lastMode = 'consumer';
    locationPrimed = false;
    location = 'Lokasi belum dipilih';
    userLatitude = null;
    userLongitude = null;
    userLocationIsFromDevice = false;
    deviceLatitude = null;
    deviceLongitude = null;
    userLocationAccuracyMeters = null;
    userLocationAccuracyReduced = false;
    hasLocationPermission = false;
    locationPermissionDeniedForever = false;
    locationServicesEnabled = true;
    currentFilter = const BagFilter();
    defaultPaymentMethod = 'QRIS';
    merchantSetupDone = false;
    userName = 'Pengguna';
    userEmail = '';
    userPhone = '';
    userAvatarUrl = null;
    storeName = '';
    storeCategory = 'Bakery';
    storeAddress = '';
    openTime = '08.00';
    closeTime = '21.00';
    storeDescription = '';
    storeLogoUrl = null;
    storeLatitude = null;
    storeLongitude = null;
    _allNearby = [];
    _nearby = [];
    _favIds = {};
    _favStores = [];
    _active = [];
    _history = [];
    _notifs = [];
    _bags = [];
    _incoming = [];
    _merchantReviews = [];
    _tx = [];
    _bankAccounts = [];
    _payouts = [];
    selectedBank = '';
    businessConfig = const BusinessConfig();
    balance = 0;
    bagsSoldToday = 0;
    incomeToday = 0;
    incomeThisMonth = 0;
    foodSavedKg = 0;
    _resetLoadingState();
    errorMessage = null;
    _loadErrors.clear();
    await setPendingMerchantIntent(null);
    if (notify) notifyListeners();
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  void reportError(Object error) {
    _setError(error, _sessionEpoch);
  }

  void _applyProfile(Profile? profile) {
    if (profile == null) return;
    userName = profile.name;
    userEmail = profile.email;
    userPhone = profile.phone;
    userAvatarUrl = profile.avatarUrl;
    lastMode = profile.lastMode;
  }

  void _applyStore(StoreProfile? store) {
    merchantSetupDone = store != null;
    if (store == null) return;
    storeName = store.name;
    storeCategory = store.category;
    storeAddress = store.address;
    openTime = store.openTime;
    closeTime = store.closeTime;
    storeDescription = store.description;
    storeLogoUrl = store.logoUrl;
    storeLatitude = store.latitude;
    storeLongitude = store.longitude;
  }

  void _applyStats(MerchantStats stats) {
    bagsSoldToday = stats.bagsSoldToday;
    incomeToday = stats.incomeToday;
    incomeThisMonth = stats.incomeThisMonth;
    foodSavedKg = stats.foodSavedKg;
  }

  void _setError(Object error, int epoch) {
    if (epoch != _sessionEpoch) return;
    errorMessage = _messageFor(error);
    notifyListeners();
  }

  void _setLoadError(_LoadScope scope, Object error, int epoch) {
    if (epoch != _sessionEpoch) return;
    _loadErrors[scope] = _messageFor(error);
    notifyListeners();
  }

  void _clearLoadError(_LoadScope scope) {
    if (_loadErrors.remove(scope) != null) notifyListeners();
  }

  void _invalidateLoadRequests() {
    _consumerRequestGeneration++;
    _profileRequestGeneration++;
    _ordersRequestGeneration++;
    _favoritesRequestGeneration++;
    _notificationsRequestGeneration++;
    _storeRequestGeneration++;
    _merchantRequestGeneration++;
    _merchantReviewsRequestGeneration++;
    _balanceRequestGeneration++;
  }

  void _resetLoadingState() {
    isBootstrapping = false;
    isLoadingConsumer = false;
    isLoadingOrders = false;
    isLoadingMerchant = false;
    isLoadingMerchantReviews = false;
    isLoadingBalance = false;
    isLoadingNotifications = false;
    isDeterminingLocation = false;
  }

  String _messageFor(
    Object error, {
    String fallback = 'Terjadi kendala. Silakan coba lagi.',
  }) {
    if (error is BackendException) return error.message;
    if (kDebugMode) debugPrint('SaveBite error: $error');
    return fallback;
  }

  @visibleForTesting
  void resetSession() {
    unawaited(_cancelRealtime());
    useFakeBackend();
    _sessionEpoch++;
    _invalidateLoadRequests();
    _checkoutKeys.clear();
    _checkoutOrderIds.clear();
    _checkoutRequestsInFlight.clear();
    _payoutKeys.clear();
    mode = AppMode.consumer;
    onboardingSeen = false;
    location = 'Margonda, Depok';
    userLatitude = -6.3725;
    userLongitude = 106.8323;
    userLocationIsFromDevice = false;
    deviceLatitude = null;
    deviceLongitude = null;
    userLocationAccuracyMeters = null;
    userLocationAccuracyReduced = false;
    hasLocationPermission = false;
    locationPermissionDeniedForever = false;
    locationServicesEnabled = true;
    isDeterminingLocation = false;
    merchantSetupDone = false;
    locationPrimed = false;
    pendingMerchantIntent = null;
    currentFilter = const BagFilter();
    defaultPaymentMethod = 'QRIS';
    selectedBank = '';
    businessConfig = const BusinessConfig();
    userName = 'Ilham Hidayat';
    userEmail = 'ilham@gmail.com';
    userPhone = '0812-3456-7890';
    userAvatarUrl = null;
    storeName = 'Roti Nyaman Bakery';
    storeCategory = 'Bakery';
    storeAddress = 'Jl. Margonda Raya No. 88, Depok';
    openTime = '08.00';
    closeTime = '21.00';
    storeDescription = '';
    storeLogoUrl = null;
    storeLatitude = -6.3720;
    storeLongitude = 106.8318;
    _allNearby = [];
    _nearby = [];
    _favIds = {};
    _favStores = [];
    _active = [];
    _history = [];
    _notifs = [];
    _bags = [];
    _incoming = [];
    _merchantReviews = [];
    _tx = [];
    _bankAccounts = [];
    _payouts = [];
    balance = 0;
    bagsSoldToday = 0;
    incomeToday = 0;
    incomeThisMonth = 0;
    foodSavedKg = 0;
    _resetLoadingState();
    errorMessage = null;
    _loadErrors.clear();
    notifyListeners();
  }
}

final appState = AppState();
