import 'dart:convert';

/// A derived, cached snapshot of what the user seems to prefer, computed by
/// `agak_recommendation_engine.dart` from raw behavior events. Never
/// user-entered directly.
class UserPreferenceProfile {
  final String? preferredDifficulty; // 'Easy' | 'Moderate' | 'Hard'
  final int? preferredElevationMinMasl;
  final int? preferredElevationMaxMasl;
  final double? preferredDistanceMinKm;
  final double? preferredDistanceMaxKm;
  final Map<String, double> trailTypeAffinity;
  final Map<String, double> featureAffinity;
  final Map<String, double> regionAffinity;
  final int easyHikeStreak;
  final double hikingFrequencyPerMonth;
  final DateTime lastComputedAt;

  const UserPreferenceProfile({
    this.preferredDifficulty,
    this.preferredElevationMinMasl,
    this.preferredElevationMaxMasl,
    this.preferredDistanceMinKm,
    this.preferredDistanceMaxKm,
    this.trailTypeAffinity = const {},
    this.featureAffinity = const {},
    this.regionAffinity = const {},
    this.easyHikeStreak = 0,
    this.hikingFrequencyPerMonth = 0,
    required this.lastComputedAt,
  });

  factory UserPreferenceProfile.empty() => UserPreferenceProfile(
    lastComputedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'preferredDifficulty': preferredDifficulty,
    'preferredElevationMinMasl': preferredElevationMinMasl,
    'preferredElevationMaxMasl': preferredElevationMaxMasl,
    'preferredDistanceMinKm': preferredDistanceMinKm,
    'preferredDistanceMaxKm': preferredDistanceMaxKm,
    'trailTypeAffinity': trailTypeAffinity,
    'featureAffinity': featureAffinity,
    'regionAffinity': regionAffinity,
    'easyHikeStreak': easyHikeStreak,
    'hikingFrequencyPerMonth': hikingFrequencyPerMonth,
    'lastComputedAt': lastComputedAt.toIso8601String(),
  };

  factory UserPreferenceProfile.fromJson(Map<String, dynamic> json) {
    Map<String, double> readMap(String key) {
      final raw = json[key];
      if (raw is! Map) return const {};
      return raw.map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      );
    }

    return UserPreferenceProfile(
      preferredDifficulty: json['preferredDifficulty'] as String?,
      preferredElevationMinMasl: (json['preferredElevationMinMasl'] as num?)
          ?.toInt(),
      preferredElevationMaxMasl: (json['preferredElevationMaxMasl'] as num?)
          ?.toInt(),
      preferredDistanceMinKm: (json['preferredDistanceMinKm'] as num?)
          ?.toDouble(),
      preferredDistanceMaxKm: (json['preferredDistanceMaxKm'] as num?)
          ?.toDouble(),
      trailTypeAffinity: readMap('trailTypeAffinity'),
      featureAffinity: readMap('featureAffinity'),
      regionAffinity: readMap('regionAffinity'),
      easyHikeStreak: (json['easyHikeStreak'] as num?)?.toInt() ?? 0,
      hikingFrequencyPerMonth:
          (json['hikingFrequencyPerMonth'] as num?)?.toDouble() ?? 0,
      lastComputedAt: DateTime.tryParse(
            json['lastComputedAt'] as String? ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String encode() => jsonEncode(toJson());

  factory UserPreferenceProfile.decode(String raw) =>
      UserPreferenceProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
