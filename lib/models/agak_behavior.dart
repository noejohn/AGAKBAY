/// User behavior events AGAK learns from. Each entry denormalizes enough
/// mountain data (name/region/difficulty/elevation) to stay useful even
/// when `mountainId` doesn't resolve to a `MountainCatalogEntry`.
///
/// `mountainId`/`matchedMountainId` fields hold a `matchKey` (see
/// `buildMountainMatchKey` in agak_mountain.dart) — the same normalized
/// `name__region` key used for the catalog and for `_mountainKeyForTrail`
/// in main.dart — not the catalog's `id` slug. This lets an event reference
/// a mountain at logging time even when no catalog entry exists yet.
class SearchHistoryEntry {
  final int? id;
  final String query;
  final String? matchedMountainId;
  final String? matchedMountainName;
  final String source; // 'dashboard_search' | 'assistant_chat'
  final DateTime searchedAt;

  const SearchHistoryEntry({
    this.id,
    required this.query,
    this.matchedMountainId,
    this.matchedMountainName,
    required this.source,
    required this.searchedAt,
  });

  factory SearchHistoryEntry.fromDbMap(Map<String, Object?> map) {
    return SearchHistoryEntry(
      id: map['id'] as int?,
      query: map['query'] as String,
      matchedMountainId: map['matched_mountain_id'] as String?,
      matchedMountainName: map['matched_mountain_name'] as String?,
      source: map['source'] as String,
      searchedAt: DateTime.fromMillisecondsSinceEpoch(
        map['searched_at'] as int,
      ),
    );
  }

  Map<String, Object?> toDbMap({String userId = 'local'}) => {
    'user_id': userId,
    'query': query,
    'matched_mountain_id': matchedMountainId,
    'matched_mountain_name': matchedMountainName,
    'source': source,
    'searched_at': searchedAt.millisecondsSinceEpoch,
  };
}

class ViewHistoryEntry {
  final int? id;
  final String? mountainId;
  final String mountainName;
  final String source; // e.g. 'details_card'
  final DateTime viewedAt;

  const ViewHistoryEntry({
    this.id,
    this.mountainId,
    required this.mountainName,
    required this.source,
    required this.viewedAt,
  });

  factory ViewHistoryEntry.fromDbMap(Map<String, Object?> map) {
    return ViewHistoryEntry(
      id: map['id'] as int?,
      mountainId: map['mountain_id'] as String?,
      mountainName: map['mountain_name'] as String,
      source: map['source'] as String,
      viewedAt: DateTime.fromMillisecondsSinceEpoch(map['viewed_at'] as int),
    );
  }

  Map<String, Object?> toDbMap({String userId = 'local'}) => {
    'user_id': userId,
    'mountain_id': mountainId,
    'mountain_name': mountainName,
    'source': source,
    'viewed_at': viewedAt.millisecondsSinceEpoch,
  };
}

class BookmarkEntry {
  final int? id;
  final String? mountainId;
  final String mountainName;
  final String? region;
  final String? difficulty;
  final int? elevationMasl;
  final DateTime createdAt;

  const BookmarkEntry({
    this.id,
    this.mountainId,
    required this.mountainName,
    this.region,
    this.difficulty,
    this.elevationMasl,
    required this.createdAt,
  });

  factory BookmarkEntry.fromDbMap(Map<String, Object?> map) {
    return BookmarkEntry(
      id: map['id'] as int?,
      mountainId: map['mountain_id'] as String?,
      mountainName: map['mountain_name'] as String,
      region: map['region'] as String?,
      difficulty: map['difficulty'] as String?,
      elevationMasl: map['elevation_masl'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
      ),
    );
  }

  Map<String, Object?> toDbMap({String userId = 'local'}) => {
    'user_id': userId,
    'mountain_id': mountainId,
    'mountain_name': mountainName,
    'region': region,
    'difficulty': difficulty,
    'elevation_masl': elevationMasl,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}

class CompletedHikeEntry {
  final int? id;
  final String? mountainId;
  final String mountainName;
  final String? region;
  final String? difficulty;
  final int elevationMasl;
  final double distanceKm;
  final bool reachedSummit;
  final DateTime completedAt;

  const CompletedHikeEntry({
    this.id,
    this.mountainId,
    required this.mountainName,
    this.region,
    this.difficulty,
    required this.elevationMasl,
    required this.distanceKm,
    required this.reachedSummit,
    required this.completedAt,
  });

  factory CompletedHikeEntry.fromDbMap(Map<String, Object?> map) {
    return CompletedHikeEntry(
      id: map['id'] as int?,
      mountainId: map['mountain_id'] as String?,
      mountainName: map['mountain_name'] as String,
      region: map['region'] as String?,
      difficulty: map['difficulty'] as String?,
      elevationMasl: map['elevation_masl'] as int? ?? 0,
      distanceKm: (map['distance_km'] as num?)?.toDouble() ?? 0,
      reachedSummit: (map['reached_summit'] as int? ?? 0) != 0,
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        map['completed_at'] as int,
      ),
    );
  }

  Map<String, Object?> toDbMap({String userId = 'local'}) => {
    'user_id': userId,
    'mountain_id': mountainId,
    'mountain_name': mountainName,
    'region': region,
    'difficulty': difficulty,
    'elevation_masl': elevationMasl,
    'distance_km': distanceKm,
    'reached_summit': reachedSummit ? 1 : 0,
    'completed_at': completedAt.millisecondsSinceEpoch,
  };
}

/// A hike the user has planned for a future date. `mountainId` follows the
/// same `matchKey` convention as the other entries in this file (see the
/// note above), which lets AGAK cross-reference it against the mountain
/// catalog for a richer packing list without storing trail metadata twice.
class ScheduledHikeEntry {
  final int? id;
  final String? mountainId;
  final String mountainName;
  final String? region;
  final String? difficulty;
  final int elevationMasl;
  final DateTime scheduledDate;
  final String? notes;
  final DateTime createdAt;

  const ScheduledHikeEntry({
    this.id,
    this.mountainId,
    required this.mountainName,
    this.region,
    this.difficulty,
    required this.elevationMasl,
    required this.scheduledDate,
    this.notes,
    required this.createdAt,
  });

  /// Whole days from today until the hike; 0 = today, negative = past.
  int get daysUntil {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
    );
    return dateOnly.difference(todayOnly).inDays;
  }

  factory ScheduledHikeEntry.fromDbMap(Map<String, Object?> map) {
    return ScheduledHikeEntry(
      id: map['id'] as int?,
      mountainId: map['mountain_id'] as String?,
      mountainName: map['mountain_name'] as String,
      region: map['region'] as String?,
      difficulty: map['difficulty'] as String?,
      elevationMasl: map['elevation_masl'] as int? ?? 0,
      scheduledDate: DateTime.fromMillisecondsSinceEpoch(
        map['scheduled_date'] as int,
      ),
      notes: map['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int,
      ),
    );
  }

  Map<String, Object?> toDbMap({String userId = 'local'}) => {
    'user_id': userId,
    'mountain_id': mountainId,
    'mountain_name': mountainName,
    'region': region,
    'difficulty': difficulty,
    'elevation_masl': elevationMasl,
    'scheduled_date': scheduledDate.millisecondsSinceEpoch,
    'notes': notes,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}
