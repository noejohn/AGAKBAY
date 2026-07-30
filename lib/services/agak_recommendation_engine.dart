import '../models/agak_behavior.dart';
import '../models/agak_mountain.dart';
import '../models/agak_preference_profile.dart';
import '../models/agak_recommendation.dart';

// Pure-Dart, offline, rule-based recommendation logic for AGAK. No Flutter
// or Firebase imports on purpose — this is the one piece of the feature
// that must never depend on network/AI availability. When an LLM is
// available (see AgakController), it only ever rephrases the output of
// this engine; it never decides what to recommend.
//
// Callers are expected to load event lists already filtered to a recent
// window (e.g. the last 90 days) via AgakBehaviorDatabase before calling
// computeProfile/recommend — this file stays pure and doesn't own that.

// ---- Tunable weights (kept as named constants for easy retuning) ----

const double _kWeightCompletedHike = 4.0;
const double _kWeightBookmark = 3.0;
const double _kWeightView = 2.0;
const double _kWeightSearch = 1.0;

const int _kEasyStreakThreshold = 3;
const double _kElevationSeekingWeight = 3.0;
const double _kDifficultyProgressionWeight = 2.5;
const double _kEasyToIntermediateNudgeWeight = 4.0;
const double _kRegionAffinityWeight = 2.0;
const double _kFeatureAffinityMinThreshold = 0.3;
const double _kFeatureAffinityWeight = 2.5;
const double _kSimilarToClimbedWeight = 3.5;
const double _kSimilarElevationBandMasl = 300;

const int _kMinHardSearchShareCount = 10;
const double _kHardShareThreshold = 0.5;

/// Keyword lexicon applied to raw search text so free-text *intent* counts
/// even when a query didn't resolve to a catalog match (e.g. "overnight
/// hike", "camping mountain", "sunrise viewpoint").
const Map<String, List<String>> _kSearchIntentTrailTypeKeywords = {
  'overnight': ['overnight', 'camp', 'camping'],
};
const Map<String, List<String>> _kSearchIntentFeatureKeywords = {
  'sunrise-viewpoint': ['sunrise', 'sunset', 'viewpoint'],
  'waterfall': ['waterfall', 'falls'],
  'camping-suitable': ['camp', 'camping', 'overnight'],
};

const List<String> _kDifficultyOrder = ['Easy', 'Moderate', 'Hard'];

int _difficultyRank(String? difficulty) {
  final idx = _kDifficultyOrder.indexOf(difficulty ?? '');
  return idx == -1 ? 0 : idx;
}

Map<String, double> _normalized(Map<String, double> raw) {
  if (raw.isEmpty) return const {};
  final maxValue = raw.values.reduce((a, b) => a > b ? a : b);
  if (maxValue <= 0) return raw.map((k, v) => MapEntry(k, 0.0));
  return raw.map((k, v) => MapEntry(k, v / maxValue));
}

/// Computes a derived preference profile from raw behavior events. Pure
/// function — callers load the event lists (already filtered to the last
/// [_kProfileWindowDays] days) from `AgakBehaviorDatabase` first.
UserPreferenceProfile computeProfile({
  required List<SearchHistoryEntry> searches,
  required List<ViewHistoryEntry> views,
  required List<BookmarkEntry> bookmarks,
  required List<CompletedHikeEntry> completedHikes,
  required List<MountainCatalogEntry> catalog,
}) {
  // Keyed by matchKey (not the catalog `id` slug) — every behavior event's
  // *MountainId field is populated with a matchKey computed at logging
  // time (via buildMountainMatchKey), so events can reference a mountain
  // even before/without a confirmed catalog `id` lookup.
  final catalogById = {for (final m in catalog) m.matchKey: m};

  final trailTypeScore = <String, double>{};
  final featureScore = <String, double>{};
  final regionScore = <String, double>{};
  final difficultyScore = <String, double>{};
  final elevations = <double>[];
  final distances = <double>[];

  void addTags(Iterable<String> tags, double weight, Map<String, double> into) {
    for (final tag in tags) {
      into[tag] = (into[tag] ?? 0) + weight;
    }
  }

  void applyKeywordLexicon(String query, double weight) {
    final lower = query.toLowerCase();
    _kSearchIntentTrailTypeKeywords.forEach((tag, keywords) {
      if (keywords.any(lower.contains)) {
        trailTypeScore[tag] = (trailTypeScore[tag] ?? 0) + weight;
      }
    });
    _kSearchIntentFeatureKeywords.forEach((tag, keywords) {
      if (keywords.any(lower.contains)) {
        featureScore[tag] = (featureScore[tag] ?? 0) + weight;
      }
    });
  }

  void applyMountainSignal(
    MountainCatalogEntry? mountain,
    String? difficulty,
    String? region,
    int? elevationMasl,
    double weight,
  ) {
    if (mountain != null) {
      addTags(mountain.trailTypes, weight, trailTypeScore);
      addTags(mountain.features, weight, featureScore);
      regionScore[mountain.region] = (regionScore[mountain.region] ?? 0) + weight;
      difficultyScore[mountain.difficulty] =
          (difficultyScore[mountain.difficulty] ?? 0) + weight;
      elevations.add(mountain.elevationMasl.toDouble());
      distances.add(mountain.distanceKm);
      return;
    }
    if (difficulty != null) {
      difficultyScore[difficulty] = (difficultyScore[difficulty] ?? 0) + weight;
    }
    if (region != null) {
      regionScore[region] = (regionScore[region] ?? 0) + weight;
    }
    if (elevationMasl != null) {
      elevations.add(elevationMasl.toDouble());
    }
  }

  for (final s in searches) {
    final mountain = s.matchedMountainId == null
        ? null
        : catalogById[s.matchedMountainId];
    applyMountainSignal(mountain, null, null, null, _kWeightSearch);
    applyKeywordLexicon(s.query, _kWeightSearch);
  }

  for (final v in views) {
    final mountain = v.mountainId == null ? null : catalogById[v.mountainId];
    applyMountainSignal(mountain, null, null, null, _kWeightView);
  }

  for (final b in bookmarks) {
    final mountain = b.mountainId == null ? null : catalogById[b.mountainId];
    applyMountainSignal(
      mountain,
      b.difficulty,
      b.region,
      b.elevationMasl,
      _kWeightBookmark,
    );
  }

  for (final c in completedHikes) {
    final mountain = c.mountainId == null ? null : catalogById[c.mountainId];
    applyMountainSignal(
      mountain,
      c.difficulty,
      c.region,
      c.elevationMasl,
      _kWeightCompletedHike,
    );
  }

  String? preferredDifficulty;
  if (difficultyScore.isNotEmpty) {
    final maxScore = difficultyScore.values.reduce((a, b) => a > b ? a : b);
    final topDifficulties = difficultyScore.entries
        .where((e) => e.value == maxScore)
        .map((e) => e.key)
        .toList();
    // Tie-break toward the harder difficulty, matching "if user prefers
    // difficult trails" leaning rather than a neutral pick.
    topDifficulties.sort(
      (a, b) => _difficultyRank(b).compareTo(_difficultyRank(a)),
    );
    preferredDifficulty = topDifficulties.first;
  }

  int? elevationMin;
  int? elevationMax;
  if (elevations.isNotEmpty) {
    final avg = elevations.reduce((a, b) => a + b) / elevations.length;
    final spread = elevations.length < 3 ? 400.0 : 250.0;
    elevationMin = (avg - spread).round();
    elevationMax = (avg + spread).round();
  }

  double? distanceMin;
  double? distanceMax;
  if (distances.isNotEmpty) {
    final avg = distances.reduce((a, b) => a + b) / distances.length;
    final spread = distances.length < 3 ? 5.0 : 3.0;
    distanceMin = (avg - spread).clamp(0, double.infinity);
    distanceMax = avg + spread;
  }

  // Sort completed hikes newest-first to compute the easy streak.
  final sortedCompleted = [...completedHikes]
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  var easyStreak = 0;
  for (final hike in sortedCompleted) {
    if (hike.difficulty == 'Easy') {
      easyStreak++;
    } else {
      break;
    }
  }

  double hikingFrequencyPerMonth = 0;
  if (completedHikes.isNotEmpty) {
    final oldest = completedHikes
        .map((h) => h.completedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final monthsSince =
        (DateTime.now().difference(oldest).inDays / 30.0).clamp(1, double.infinity);
    hikingFrequencyPerMonth = completedHikes.length / monthsSince;
  }

  return UserPreferenceProfile(
    preferredDifficulty: preferredDifficulty,
    preferredElevationMinMasl: elevationMin,
    preferredElevationMaxMasl: elevationMax,
    preferredDistanceMinKm: distanceMin,
    preferredDistanceMaxKm: distanceMax,
    trailTypeAffinity: _normalized(trailTypeScore),
    featureAffinity: _normalized(featureScore),
    regionAffinity: _normalized(regionScore),
    easyHikeStreak: easyStreak,
    hikingFrequencyPerMonth: hikingFrequencyPerMonth,
    lastComputedAt: DateTime.now(),
  );
}

/// Scores every non-completed catalog entry and returns the top
/// [maxResults], highest score first. Weather/closures/community
/// enhancement is explicitly out of scope for Phase 1 — [weatherRiskProvider]
/// is a Phase 2 extension point only, unused today.
List<AgakRecommendation> recommend({
  required UserPreferenceProfile profile,
  required List<MountainCatalogEntry> catalog,
  required Set<String> completedMatchKeys,
  required List<SearchHistoryEntry> recentSearches,
  required List<BookmarkEntry> bookmarks,
  required List<CompletedHikeEntry> completedHikes,
  int maxResults = 5,
  Future<String> Function(MountainCatalogEntry mountain)? weatherRiskProvider,
}) {
  final bookmarkedRegions = bookmarks.map((b) => b.region).whereType<String>();
  final bookmarkedMatchKeys = bookmarks
      .map((b) => b.mountainId)
      .whereType<String>()
      .toSet();

  final candidates = catalog
      .where((m) => !completedMatchKeys.contains(m.matchKey))
      .toList();

  // Hard/high-elevation search-share, used by the elevation-seeking rule.
  final recentResolvedSearches = recentSearches
      .take(_kMinHardSearchShareCount)
      .where((s) => s.matchedMountainId != null)
      .toList();
  // Keyed by matchKey (not the catalog `id` slug) — every behavior event's
  // *MountainId field is populated with a matchKey computed at logging
  // time (via buildMountainMatchKey), so events can reference a mountain
  // even before/without a confirmed catalog `id` lookup.
  final catalogById = {for (final m in catalog) m.matchKey: m};
  final hardSearchShare = recentResolvedSearches.isEmpty
      ? 0.0
      : recentResolvedSearches
              .where((s) => catalogById[s.matchedMountainId]?.difficulty == 'Hard')
              .length /
          recentResolvedSearches.length;

  final scored = <AgakRecommendation>[];

  for (final mountain in candidates) {
    double score = 0;
    AgakRecommendationReason reason = AgakRecommendationReason.general;
    String? supportingFact;

    // Elevation-seeking: recent searches/views skew Hard-tier.
    if (hardSearchShare >= _kHardShareThreshold && mountain.difficulty == 'Hard') {
      score += _kElevationSeekingWeight;
      reason = AgakRecommendationReason.elevationSeeking;
      supportingFact ??= 'You keep searching for high, challenging peaks.';
    }

    // Difficulty progression: prefers Hard, boost same/harder tier.
    if (profile.preferredDifficulty == 'Hard' &&
        _difficultyRank(mountain.difficulty) >= _difficultyRank('Hard')) {
      score += _kDifficultyProgressionWeight;
      if (reason == AgakRecommendationReason.general) {
        reason = AgakRecommendationReason.difficultyProgression;
        supportingFact ??= 'You tend to go for the harder trails.';
      }
    } else if (profile.preferredDifficulty == 'Moderate' &&
        _difficultyRank(mountain.difficulty) >= _difficultyRank('Moderate')) {
      score += _kDifficultyProgressionWeight * 0.6;
      if (reason == AgakRecommendationReason.general) {
        reason = AgakRecommendationReason.difficultyProgression;
      }
    }

    // Easy-to-intermediate nudge: dominant, higher-priority than generic
    // progression when the user has a live easy streak.
    if (profile.easyHikeStreak >= _kEasyStreakThreshold &&
        mountain.difficulty == 'Moderate') {
      final avgCompletedElevation = profile.preferredElevationMaxMasl;
      final aboveAverage = avgCompletedElevation == null ||
          mountain.elevationMasl >= avgCompletedElevation - 400;
      if (aboveAverage) {
        score += _kEasyToIntermediateNudgeWeight;
        reason = AgakRecommendationReason.easyToIntermediateNudge;
        supportingFact =
            "You've completed ${profile.easyHikeStreak} easy hikes in a row — time to level up.";
      }
    }

    // Region affinity from bookmarks.
    for (final region in bookmarkedRegions) {
      if (mountain.region == region) {
        final affinity = profile.regionAffinity[region] ?? 0.5;
        score += _kRegionAffinityWeight * affinity;
        if (reason == AgakRecommendationReason.general) {
          reason = AgakRecommendationReason.regionAffinityFromBookmark;
          supportingFact = "You've bookmarked mountains in $region.";
        }
      }
    }

    // Trail-type / feature affinity — mechanically covers waterfall,
    // forest, sunrise-viewpoint and overnight/camping since they're tags.
    var featureBoost = 0.0;
    String? matchedFeature;
    for (final feature in mountain.features) {
      final affinity = profile.featureAffinity[feature] ?? 0;
      if (affinity >= _kFeatureAffinityMinThreshold) {
        featureBoost += affinity;
        matchedFeature ??= feature;
      }
    }
    for (final type in mountain.trailTypes) {
      final affinity = profile.trailTypeAffinity[type] ?? 0;
      if (affinity >= _kFeatureAffinityMinThreshold) {
        featureBoost += affinity;
        matchedFeature ??= type;
      }
    }
    if (featureBoost > 0) {
      score += _kFeatureAffinityWeight * featureBoost;
      if (reason == AgakRecommendationReason.general) {
        reason = AgakRecommendationReason.trailTypeAffinity;
        supportingFact = matchedFeature == null
            ? null
            : 'You seem to enjoy $matchedFeature trails.';
      }
    }

    // Similar-to-climbed: close in elevation/difficulty/features to an
    // already-completed peak (but never the same peak, excluded above).
    for (final hike in completedHikes) {
      if (hike.difficulty != mountain.difficulty) continue;
      if (hike.elevationMasl == 0) continue;
      final elevationDelta =
          (hike.elevationMasl - mountain.elevationMasl).abs();
      if (elevationDelta > _kSimilarElevationBandMasl) continue;
      final completedMountain = hike.mountainId == null
          ? null
          : catalogById[hike.mountainId];
      final sharesFeature = completedMountain != null &&
          completedMountain.features.any(mountain.features.contains);
      if (completedMountain == null || sharesFeature) {
        score += _kSimilarToClimbedWeight;
        reason = AgakRecommendationReason.similarToClimbed;
        supportingFact = 'Similar to ${hike.mountainName}, which you completed.';
        break;
      }
    }

    if (score <= 0) continue;

    scored.add(
      AgakRecommendation(
        mountain: mountain,
        reason: reason,
        score: score,
        headline: _headlineFor(reason, mountain),
        supportingFact: supportingFact,
      ),
    );
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  // Keep already-bookmarked mountains from crowding out fresh suggestions
  // when there's a positive-scoring alternative available.
  final withoutRebookmarks = scored
      .where((r) => !bookmarkedMatchKeys.contains(r.mountain.matchKey))
      .toList();
  final result = withoutRebookmarks.isNotEmpty ? withoutRebookmarks : scored;
  return result.take(maxResults).toList();
}

String _headlineFor(AgakRecommendationReason reason, MountainCatalogEntry m) {
  switch (reason) {
    case AgakRecommendationReason.elevationSeeking:
      return 'Ready for another high peak? Try ${m.name}.';
    case AgakRecommendationReason.difficultyProgression:
      return '${m.name} matches the challenge level you\'re after.';
    case AgakRecommendationReason.regionAffinityFromBookmark:
      return '${m.name} is in a region you\'ve been eyeing.';
    case AgakRecommendationReason.trailTypeAffinity:
      return '${m.name} has the kind of trail you keep coming back to.';
    case AgakRecommendationReason.easyToIntermediateNudge:
      return "You've earned a step up — ${m.name} is a good next challenge.";
    case AgakRecommendationReason.similarToClimbed:
      return '${m.name} feels a lot like a peak you\'ve already conquered.';
    case AgakRecommendationReason.general:
      return 'Consider ${m.name} for your next hike.';
  }
}
