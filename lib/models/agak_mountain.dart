import 'dart:convert';

/// Normalizes a string the same way `_normalizeTokenString` in main.dart does,
/// so catalog match keys line up with `_mountainKeyForTrail` without a shared import.
String normalizeMountainToken(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

/// Builds the same `name__province` key shape as `_mountainKeyForTrail`.
String buildMountainMatchKey({required String name, required String region}) {
  final nameKey = normalizeMountainToken(name);
  final areaKey = normalizeMountainToken(region);
  if (areaKey.isEmpty) return nameKey;
  return '${nameKey}__$areaKey';
}

/// A curated mountain/trail entry used by the AGAK recommendation engine.
///
/// Distinct from `_NearbyTrail` (live Google Places data): this carries the
/// editorial metadata (trail types, feature tags) that Places can't provide.
class MountainCatalogEntry {
  final String id;
  final String matchKey;
  final String name;
  final String region;
  final int elevationMasl;
  final String difficulty;
  final List<String> trailTypes;
  final List<String> features;
  final double distanceKm;
  final String description;
  final String? placeId;
  final double? latitude;
  final double? longitude;

  const MountainCatalogEntry({
    required this.id,
    required this.matchKey,
    required this.name,
    required this.region,
    required this.elevationMasl,
    required this.difficulty,
    required this.trailTypes,
    required this.features,
    required this.distanceKm,
    required this.description,
    this.placeId,
    this.latitude,
    this.longitude,
  });

  factory MountainCatalogEntry.fromJson(Map<String, dynamic> json) {
    return MountainCatalogEntry(
      id: json['id'] as String,
      matchKey: json['matchKey'] as String,
      name: json['name'] as String,
      region: json['region'] as String,
      elevationMasl: (json['elevationMasl'] as num).toInt(),
      difficulty: json['difficulty'] as String,
      trailTypes: List<String>.from(json['trailTypes'] as List? ?? const []),
      features: List<String>.from(json['features'] as List? ?? const []),
      distanceKm: (json['distanceKm'] as num).toDouble(),
      description: json['description'] as String? ?? '',
      placeId: json['placeId'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'matchKey': matchKey,
    'name': name,
    'region': region,
    'elevationMasl': elevationMasl,
    'difficulty': difficulty,
    'trailTypes': trailTypes,
    'features': features,
    'distanceKm': distanceKm,
    'description': description,
    'placeId': placeId,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory MountainCatalogEntry.fromDbMap(Map<String, Object?> map) {
    return MountainCatalogEntry(
      id: map['id'] as String,
      matchKey: map['match_key'] as String,
      name: map['name'] as String,
      region: map['region'] as String,
      elevationMasl: map['elevation_masl'] as int,
      difficulty: map['difficulty'] as String,
      trailTypes: List<String>.from(
        _decodeJsonList(map['trail_types'] as String?),
      ),
      features: List<String>.from(_decodeJsonList(map['features'] as String?)),
      distanceKm: (map['distance_km'] as num).toDouble(),
      description: map['description'] as String? ?? '',
      placeId: map['place_id'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, Object?> toDbMap({required int seededAtMillis}) => {
    'id': id,
    'match_key': matchKey,
    'name': name,
    'region': region,
    'elevation_masl': elevationMasl,
    'difficulty': difficulty,
    'trail_types': _encodeJsonList(trailTypes),
    'features': _encodeJsonList(features),
    'distance_km': distanceKm,
    'description': description,
    'place_id': placeId,
    'latitude': latitude,
    'longitude': longitude,
    'seeded_at': seededAtMillis,
  };
}

List<String> _decodeJsonList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return List<String>.from(jsonDecode(raw) as List);
}

String _encodeJsonList(List<String> values) => jsonEncode(values);
