import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart' as xml;

double _readDouble(Object? value, String fieldName) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }

  throw FormatException('Invalid double for $fieldName: $value');
}

double? _readOptionalDouble(Object? value, String fieldName) {
  if (value == null) return null;
  return _readDouble(value, fieldName);
}

/// Represents a GPX track point
class GpxTrackPoint {
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? timestamp;

  GpxTrackPoint({
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'elevation': elevation,
    'timestamp': timestamp?.toIso8601String(),
  };

  factory GpxTrackPoint.fromJson(Map<String, dynamic> json) {
    return GpxTrackPoint(
      latitude: _readDouble(json['latitude'], 'latitude'),
      longitude: _readDouble(json['longitude'], 'longitude'),
      elevation: _readOptionalDouble(json['elevation'], 'elevation'),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }
}

/// Represents a cached trail
class CachedTrail {
  final String id;
  final String name;
  final String description;
  final List<GpxTrackPoint> trackPoints;
  final double? difficulty;
  final double? duration;
  final double distance;
  final DateTime cachedAt;

  CachedTrail({
    required this.id,
    required this.name,
    required this.description,
    required this.trackPoints,
    this.difficulty,
    this.duration,
    required this.distance,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'trackPoints': trackPoints.map((p) => p.toJson()).toList(),
    'difficulty': difficulty,
    'duration': duration,
    'distance': distance,
    'cachedAt': cachedAt.toIso8601String(),
  };

  factory CachedTrail.fromJson(Map<String, dynamic> json) {
    return CachedTrail(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      trackPoints: (json['trackPoints'] as List<dynamic>)
          .map(
            (p) => GpxTrackPoint.fromJson(
              Map<String, dynamic>.from(p as Map<dynamic, dynamic>),
            ),
          )
          .toList(),
      difficulty: _readOptionalDouble(json['difficulty'], 'difficulty'),
      duration: _readOptionalDouble(json['duration'], 'duration'),
      distance: _readDouble(json['distance'], 'distance'),
      cachedAt: DateTime.parse(json['cachedAt'] as String),
    );
  }

  double get elevationGain {
    if (trackPoints.length < 2) return 0;
    double gain = 0;
    for (int i = 1; i < trackPoints.length; i++) {
      final prev = trackPoints[i - 1];
      final curr = trackPoints[i];
      if (prev.elevation != null && curr.elevation != null) {
        final diff = curr.elevation! - prev.elevation!;
        if (diff > 0) gain += diff;
      }
    }
    return gain;
  }
}

/// Service for managing offline trail/GPX data
class OfflineTrailService {
  static const String _trailCacheDir = 'offline_trails';
  static const String _metadataFile = 'trails_metadata.json';
  late Directory _cacheDirectory;
  bool _isInitialized = false;
  final Map<String, CachedTrail> _trailCache = {};

  /// Initialize the offline trail service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDirectory = Directory('${appDir.path}/$_trailCacheDir');

      if (!await _cacheDirectory.exists()) {
        await _cacheDirectory.create(recursive: true);
      }

      await _loadCachedMetadata();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing offline trail service: $e');
    }
  }

  /// Cache a trail from GPX content
  Future<CachedTrail> cacheTrailFromGpx({
    required String trailId,
    required String trailName,
    required String gpxContent,
    String description = '',
    double? difficulty,
    double? duration,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      final trackPoints = _parseGpxContent(gpxContent);
      final distance = _calculateDistance(trackPoints);

      final trail = CachedTrail(
        id: trailId,
        name: trailName,
        description: description,
        trackPoints: trackPoints,
        difficulty: difficulty,
        duration: duration,
        distance: distance,
        cachedAt: DateTime.now(),
      );

      // Save trail data
      final trailFile = File('${_cacheDirectory.path}/$trailId.json');
      await trailFile.writeAsString(jsonEncode(trail.toJson()));

      _trailCache[trailId] = trail;
      await _saveMetadata();

      return trail;
    } catch (e) {
      debugPrint('Error caching trail: $e');
      rethrow;
    }
  }

  /// Cache trail from file path
  Future<CachedTrail> cacheTrailFromFile({
    required String trailId,
    required String trailName,
    required String filePath,
    String description = '',
    double? difficulty,
    double? duration,
  }) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      return await cacheTrailFromGpx(
        trailId: trailId,
        trailName: trailName,
        gpxContent: content,
        description: description,
        difficulty: difficulty,
        duration: duration,
      );
    } catch (e) {
      debugPrint('Error caching trail from file: $e');
      rethrow;
    }
  }

  /// Get cached trail
  Future<CachedTrail?> getCachedTrail(String trailId) async {
    if (!_isInitialized) await initialize();

    if (_trailCache.containsKey(trailId)) {
      return _trailCache[trailId];
    }

    try {
      final trailFile = File('${_cacheDirectory.path}/$trailId.json');
      if (await trailFile.exists()) {
        final content = await trailFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final trail = CachedTrail.fromJson(json);
        _trailCache[trailId] = trail;
        return trail;
      }
    } catch (e) {
      debugPrint('Error loading cached trail: $e');
    }

    return null;
  }

  /// Get all cached trails
  Future<List<CachedTrail>> getAllCachedTrails() async {
    if (!_isInitialized) await initialize();

    try {
      final files = _cacheDirectory.listSync();
      final trails = <CachedTrail>[];

      for (final file in files) {
        if (file is File &&
            file.path.endsWith('.json') &&
            !file.path.endsWith('_metadata.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            trails.add(CachedTrail.fromJson(json));
          } catch (e) {
            debugPrint('Error loading trail file: $e');
          }
        }
      }

      return trails;
    } catch (e) {
      debugPrint('Error getting cached trails: $e');
      return [];
    }
  }

  /// Delete cached trail
  Future<void> deleteCachedTrail(String trailId) async {
    if (!_isInitialized) await initialize();

    try {
      final trailFile = File('${_cacheDirectory.path}/$trailId.json');
      if (await trailFile.exists()) {
        await trailFile.delete();
      }

      _trailCache.remove(trailId);
      await _saveMetadata();
    } catch (e) {
      debugPrint('Error deleting cached trail: $e');
    }
  }

  /// Get cache size in MB
  Future<double> getCacheSizeInMB() async {
    if (!_isInitialized) await initialize();

    try {
      int totalSize = 0;
      await for (final file in _cacheDirectory.list(recursive: true)) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      return totalSize / (1024 * 1024);
    } catch (e) {
      debugPrint('Error getting cache size: $e');
      return 0.0;
    }
  }

  /// Clear all cached trails
  Future<void> clearCache() async {
    if (!_isInitialized) await initialize();

    try {
      if (await _cacheDirectory.exists()) {
        await _cacheDirectory.delete(recursive: true);
        await _cacheDirectory.create(recursive: true);
      }

      _trailCache.clear();
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Parse GPX content and extract track points
  List<GpxTrackPoint> _parseGpxContent(String gpxContent) {
    final trackPoints = <GpxTrackPoint>[];

    try {
      final document = xml.XmlDocument.parse(gpxContent);
      final trkpts = document.findAllElements('trkpt');

      for (final point in trkpts) {
        final lat = double.tryParse(point.getAttribute('lat') ?? '');
        final lng = double.tryParse(point.getAttribute('lon') ?? '');

        if (lat != null && lng != null) {
          final elevElement = point.findElements('ele').firstOrNull;
          final elevation = elevElement != null
              ? double.tryParse(elevElement.innerText)
              : null;

          final timeElement = point.findElements('time').firstOrNull;
          final timestamp = timeElement != null
              ? DateTime.tryParse(timeElement.innerText)
              : null;

          trackPoints.add(
            GpxTrackPoint(
              latitude: lat,
              longitude: lng,
              elevation: elevation,
              timestamp: timestamp,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error parsing GPX content: $e');
    }

    return trackPoints;
  }

  /// Calculate total distance of track in kilometers
  double _calculateDistance(List<GpxTrackPoint> trackPoints) {
    if (trackPoints.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < trackPoints.length; i++) {
      totalDistance += _haversineDistance(
        trackPoints[i - 1].latitude,
        trackPoints[i - 1].longitude,
        trackPoints[i].latitude,
        trackPoints[i].longitude,
      );
    }

    return totalDistance;
  }

  /// Calculate distance between two coordinates using Haversine formula (in km)
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371.0; // Earth's radius in kilometers

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        (_sin(dLat / 2) * _sin(dLat / 2)) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLon / 2) *
            _sin(dLon / 2);

    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (3.14159265359 / 180);

  // Math helper functions
  double _sin(double radians) {
    // Simplified sine approximation for small angles
    return radians -
        (radians * radians * radians) / 6 +
        (radians * radians * radians * radians * radians) / 120;
  }

  double _cos(double radians) {
    return 1 -
        (radians * radians) / 2 +
        (radians * radians * radians * radians) / 24;
  }

  double _sqrt(double value) {
    if (value < 0) return 0;
    double x = value;
    double y = (x + 1) / 2;
    while (y < x) {
      x = y;
      y = (x + value / x) / 2;
    }
    return x;
  }

  double _atan2(double y, double x) {
    const pi = 3.14159265359;
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + pi;
    if (x < 0 && y < 0) return _atan(y / x) - pi;
    if (x == 0 && y > 0) return pi / 2;
    if (x == 0 && y < 0) return -pi / 2;
    return 0;
  }

  double _atan(double value) {
    return value / (1 + 0.28 * value * value);
  }

  /// Save metadata to file
  Future<void> _saveMetadata() async {
    try {
      final metadataFile = File('${_cacheDirectory.path}/$_metadataFile');
      final metadata = {
        'trails': _trailCache.values
            .map(
              (t) => {
                'id': t.id,
                'name': t.name,
                'cachedAt': t.cachedAt.toIso8601String(),
                'distance': t.distance,
                'elevationGain': t.elevationGain,
              },
            )
            .toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await metadataFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      debugPrint('Error saving metadata: $e');
    }
  }

  /// Load cached metadata
  Future<void> _loadCachedMetadata() async {
    try {
      final metadataFile = File('${_cacheDirectory.path}/$_metadataFile');
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        debugPrint('Loaded cached trails metadata: $content');
      }
    } catch (e) {
      debugPrint('Error loading metadata: $e');
    }
  }
}
