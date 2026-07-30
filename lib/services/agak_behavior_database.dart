import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/agak_behavior.dart';
import '../models/agak_mountain.dart';

/// Local (sqflite) storage for everything AGAK learns from: search/view
/// history, bookmarks, timestamped completed hikes, the seeded mountain
/// catalog, and a cached derived preference profile.
///
/// Deliberately a separate DB file from `OfflineActivityDatabase` — that one
/// is scoped to GPS-recording session lifecycle with its own sync-flag
/// conventions; this one is a different concern (behavior analytics + a
/// read-mostly catalog) with no sync flags in Phase 1.
///
/// Fully offline by design: nothing in this file touches Firestore. See the
/// AGAK Phase 1 plan for the rationale.
class AgakBehaviorDatabase {
  AgakBehaviorDatabase._();

  static final AgakBehaviorDatabase instance = AgakBehaviorDatabase._();

  Database? _database;

  static String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'local';

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'agak_behavior.db');
    final opened = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE mountain_catalog (
            id TEXT PRIMARY KEY,
            match_key TEXT NOT NULL,
            name TEXT NOT NULL,
            region TEXT NOT NULL,
            elevation_masl INTEGER NOT NULL,
            difficulty TEXT NOT NULL,
            trail_types TEXT NOT NULL,
            features TEXT NOT NULL,
            distance_km REAL NOT NULL,
            description TEXT NOT NULL,
            place_id TEXT,
            latitude REAL,
            longitude REAL,
            seeded_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_catalog_match_key ON mountain_catalog(match_key)',
        );
        await db.execute(
          'CREATE INDEX idx_catalog_region ON mountain_catalog(region)',
        );

        await db.execute('''
          CREATE TABLE search_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            query TEXT NOT NULL,
            matched_mountain_id TEXT,
            matched_mountain_name TEXT,
            source TEXT NOT NULL,
            searched_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_search_user_time ON search_history(user_id, searched_at)',
        );

        await db.execute('''
          CREATE TABLE view_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            mountain_id TEXT,
            mountain_name TEXT NOT NULL,
            source TEXT NOT NULL,
            viewed_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_view_user_time ON view_history(user_id, viewed_at)',
        );
        await db.execute(
          'CREATE INDEX idx_view_mountain ON view_history(mountain_id)',
        );

        await db.execute('''
          CREATE TABLE bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            mountain_id TEXT,
            mountain_name TEXT NOT NULL,
            region TEXT,
            difficulty TEXT,
            elevation_masl INTEGER,
            created_at INTEGER NOT NULL,
            UNIQUE(user_id, mountain_id, mountain_name)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_bookmarks_user ON bookmarks(user_id)',
        );

        await db.execute('''
          CREATE TABLE completed_hikes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            mountain_id TEXT,
            mountain_name TEXT NOT NULL,
            region TEXT,
            difficulty TEXT,
            elevation_masl INTEGER NOT NULL DEFAULT 0,
            distance_km REAL NOT NULL DEFAULT 0,
            reached_summit INTEGER NOT NULL DEFAULT 0,
            completed_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_completed_user_time ON completed_hikes(user_id, completed_at)',
        );

        await db.execute('''
          CREATE TABLE preference_profile_cache (
            id INTEGER PRIMARY KEY,
            user_id TEXT NOT NULL UNIQUE,
            profile_json TEXT NOT NULL,
            computed_at INTEGER NOT NULL
          )
        ''');

        await _createScheduledHikesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2: scheduled_hikes was added after this app had already
        // shipped, so onCreate alone never runs it for existing installs —
        // an already-open database only ever gets onCreate once, at first
        // creation. IF NOT EXISTS makes this safe to re-run too.
        if (oldVersion < 2) {
          await _createScheduledHikesTable(db);
        }
      },
    );
    _database = opened;
    await _seedCatalogIfEmpty(opened);
    return opened;
  }

  Future<void> _createScheduledHikesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_hikes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        mountain_id TEXT,
        mountain_name TEXT NOT NULL,
        region TEXT,
        difficulty TEXT,
        elevation_masl INTEGER NOT NULL DEFAULT 0,
        scheduled_date INTEGER NOT NULL,
        notes TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scheduled_user_date '
      'ON scheduled_hikes(user_id, scheduled_date)',
    );
  }

  Future<void> _seedCatalogIfEmpty(Database db) async {
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM mountain_catalog',
    );
    final count = Sqflite.firstIntValue(countResult) ?? 0;
    if (count > 0) return;

    try {
      final raw = await rootBundle.loadString(
        'assets/agak/mountain_catalog_seed.json',
      );
      final decoded = jsonDecode(raw) as List;
      final entries = decoded
          .map((e) => MountainCatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      final batch = db.batch();
      final seededAt = DateTime.now().millisecondsSinceEpoch;
      for (final entry in entries) {
        batch.insert(
          'mountain_catalog',
          entry.toDbMap(seededAtMillis: seededAt),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // Seeding is best-effort: if the bundled asset is missing/malformed,
      // the catalog simply stays empty and the recommendation engine
      // degrades gracefully (empty recommendations -> discouraging state).
    }
  }

  // ---- Catalog ----

  Future<List<MountainCatalogEntry>> getCatalog() async {
    final db = await database;
    final rows = await db.query('mountain_catalog');
    return rows.map(MountainCatalogEntry.fromDbMap).toList();
  }

  // ---- Search history ----

  Future<void> logSearch({
    required String query,
    String? matchedMountainId,
    String? matchedMountainName,
    required String source,
  }) async {
    try {
      final db = await database;
      await db.insert(
        'search_history',
        SearchHistoryEntry(
          query: query,
          matchedMountainId: matchedMountainId,
          matchedMountainName: matchedMountainName,
          source: source,
          searchedAt: DateTime.now(),
        ).toDbMap(userId: _currentUserId),
      );
    } catch (_) {
      // Instrumentation must never break the calling UX.
    }
  }

  Future<List<SearchHistoryEntry>> getRecentSearches({int days = 90}) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      'search_history',
      where: 'user_id = ? AND searched_at >= ?',
      whereArgs: [_currentUserId, since],
      orderBy: 'searched_at DESC',
    );
    return rows.map(SearchHistoryEntry.fromDbMap).toList();
  }

  // ---- View history ----

  Future<void> logView({
    String? mountainId,
    required String mountainName,
    required String source,
  }) async {
    try {
      final db = await database;
      await db.insert(
        'view_history',
        ViewHistoryEntry(
          mountainId: mountainId,
          mountainName: mountainName,
          source: source,
          viewedAt: DateTime.now(),
        ).toDbMap(userId: _currentUserId),
      );
    } catch (_) {
      // Ignore — best-effort logging.
    }
  }

  Future<List<ViewHistoryEntry>> getRecentViews({int days = 90}) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      'view_history',
      where: 'user_id = ? AND viewed_at >= ?',
      whereArgs: [_currentUserId, since],
      orderBy: 'viewed_at DESC',
    );
    return rows.map(ViewHistoryEntry.fromDbMap).toList();
  }

  // ---- Bookmarks ----

  Future<void> addBookmark({
    String? mountainId,
    required String mountainName,
    String? region,
    String? difficulty,
    int? elevationMasl,
  }) async {
    final db = await database;
    await db.insert(
      'bookmarks',
      BookmarkEntry(
        mountainId: mountainId,
        mountainName: mountainName,
        region: region,
        difficulty: difficulty,
        elevationMasl: elevationMasl,
        createdAt: DateTime.now(),
      ).toDbMap(userId: _currentUserId),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeBookmark({
    String? mountainId,
    required String mountainName,
  }) async {
    final db = await database;
    await db.delete(
      'bookmarks',
      where: 'user_id = ? AND mountain_id IS ? AND mountain_name = ?',
      whereArgs: [_currentUserId, mountainId, mountainName],
    );
  }

  Future<bool> isBookmarked({
    String? mountainId,
    required String mountainName,
  }) async {
    final db = await database;
    final rows = await db.query(
      'bookmarks',
      where: 'user_id = ? AND mountain_id IS ? AND mountain_name = ?',
      whereArgs: [_currentUserId, mountainId, mountainName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<BookmarkEntry>> getBookmarks() async {
    final db = await database;
    final rows = await db.query(
      'bookmarks',
      where: 'user_id = ?',
      whereArgs: [_currentUserId],
      orderBy: 'created_at DESC',
    );
    return rows.map(BookmarkEntry.fromDbMap).toList();
  }

  // ---- Completed hikes ----

  Future<void> logCompletedHike({
    String? mountainId,
    required String mountainName,
    String? region,
    String? difficulty,
    required int elevationMasl,
    required double distanceKm,
    required bool reachedSummit,
  }) async {
    try {
      final db = await database;
      await db.insert(
        'completed_hikes',
        CompletedHikeEntry(
          mountainId: mountainId,
          mountainName: mountainName,
          region: region,
          difficulty: difficulty,
          elevationMasl: elevationMasl,
          distanceKm: distanceKm,
          reachedSummit: reachedSummit,
          completedAt: DateTime.now(),
        ).toDbMap(userId: _currentUserId),
      );
    } catch (_) {
      // Ignore — best-effort logging; the Firestore leaderboard write is
      // the source of truth for completion, this is additive.
    }
  }

  Future<List<CompletedHikeEntry>> getCompletedHikes({int? days}) async {
    final db = await database;
    if (days == null) {
      final rows = await db.query(
        'completed_hikes',
        where: 'user_id = ?',
        whereArgs: [_currentUserId],
        orderBy: 'completed_at DESC',
      );
      return rows.map(CompletedHikeEntry.fromDbMap).toList();
    }
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      'completed_hikes',
      where: 'user_id = ? AND completed_at >= ?',
      whereArgs: [_currentUserId, since],
      orderBy: 'completed_at DESC',
    );
    return rows.map(CompletedHikeEntry.fromDbMap).toList();
  }

  // ---- Preference profile cache ----

  Future<void> cacheProfile(String profileJson) async {
    final db = await database;
    await db.insert('preference_profile_cache', {
      'id': 1,
      'user_id': _currentUserId,
      'profile_json': profileJson,
      'computed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getCachedProfile() async {
    final db = await database;
    final rows = await db.query(
      'preference_profile_cache',
      where: 'user_id = ?',
      whereArgs: [_currentUserId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['profile_json'] as String?;
  }

  // ---- Scheduled hikes ----

  Future<int> scheduleHike({
    String? mountainId,
    required String mountainName,
    String? region,
    String? difficulty,
    required int elevationMasl,
    required DateTime scheduledDate,
    String? notes,
  }) async {
    final db = await database;
    return db.insert(
      'scheduled_hikes',
      ScheduledHikeEntry(
        mountainId: mountainId,
        mountainName: mountainName,
        region: region,
        difficulty: difficulty,
        elevationMasl: elevationMasl,
        scheduledDate: scheduledDate,
        notes: notes,
        createdAt: DateTime.now(),
      ).toDbMap(userId: _currentUserId),
    );
  }

  /// Hikes scheduled for today or later, soonest first.
  Future<List<ScheduledHikeEntry>> getUpcomingScheduledHikes() async {
    final db = await database;
    final startOfToday = DateTime.now();
    final since = DateTime(
      startOfToday.year,
      startOfToday.month,
      startOfToday.day,
    ).millisecondsSinceEpoch;
    final rows = await db.query(
      'scheduled_hikes',
      where: 'user_id = ? AND scheduled_date >= ?',
      whereArgs: [_currentUserId, since],
      orderBy: 'scheduled_date ASC',
    );
    return rows.map(ScheduledHikeEntry.fromDbMap).toList();
  }

  Future<void> cancelScheduledHike(int id) async {
    final db = await database;
    await db.delete(
      'scheduled_hikes',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, _currentUserId],
    );
  }
}
