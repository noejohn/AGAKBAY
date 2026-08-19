import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';

import '../models/agak_recommendation.dart';

/// Live current-conditions lookup for the user's location. The actual
/// Google Weather API call and risk classification happen server-side in
/// the `fetchWeatherSnapshot` Cloud Function (see functions/index.js) —
/// this class never sees or needs the Weather API key, unlike the old
/// client-side implementation it replaced.
class WeatherService {
  static const _cacheTtl = Duration(minutes: 5);

  final FirebaseFunctions _functions;
  ({double lat, double lon})? _cacheKey;
  DateTime? _cachedAt;
  AgakWeatherSnapshot? _cachedSnapshot;

  WeatherService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  /// Null on denied/disabled location, not just an error — callers should
  /// treat "no fix" the same as "no live weather" rather than surfacing it.
  Future<Position?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Reuses the last result when called again for essentially the same
  /// spot within [_cacheTtl] — e.g. the dashboard's ambient check and
  /// Hiking Mode's periodic check landing close together shouldn't each
  /// trigger their own function invocation. Rounded to ~1km (2 decimal
  /// places) so small GPS jitter between calls still hits the cache.
  Future<AgakWeatherSnapshot?> fetchCurrentSnapshot({
    required double latitude,
    required double longitude,
  }) async {
    final roundedLat = double.parse(latitude.toStringAsFixed(2));
    final roundedLon = double.parse(longitude.toStringAsFixed(2));
    final cachedAt = _cachedAt;
    final cacheKey = _cacheKey;
    if (cachedAt != null &&
        cacheKey != null &&
        cacheKey.lat == roundedLat &&
        cacheKey.lon == roundedLon &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _cachedSnapshot;
    }

    try {
      final result = await _functions
          .httpsCallable('fetchWeatherSnapshot')
          .call<Map<String, dynamic>?>({
            'latitude': latitude,
            'longitude': longitude,
          });
      final data = result.data;
      final snapshot = data == null
          ? null
          : AgakWeatherSnapshot(
              isSevere: data['isSevere'] == true,
              isCaution: data['isCaution'] == true,
              isSunny: data['isSunny'] == true,
              headline: data['headline']?.toString() ?? '',
            );
      _cacheKey = (lat: roundedLat, lon: roundedLon);
      _cachedAt = DateTime.now();
      _cachedSnapshot = snapshot;
      return snapshot;
    } catch (_) {
      return null;
    }
  }
}
