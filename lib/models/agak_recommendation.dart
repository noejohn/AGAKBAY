import 'agak_mountain.dart';

enum AgakRecommendationReason {
  elevationSeeking,
  difficultyProgression,
  regionAffinityFromBookmark,
  trailTypeAffinity,
  easyToIntermediateNudge,
  similarToClimbed,
  general,
}

class AgakRecommendation {
  final MountainCatalogEntry mountain;
  final AgakRecommendationReason reason;
  final double score;
  final String headline;
  final String? supportingFact;

  const AgakRecommendation({
    required this.mountain,
    required this.reason,
    required this.score,
    required this.headline,
    this.supportingFact,
  });
}

/// The 5 emotional states AGAK can express, each backed by one of the
/// custom eagle illustrations under assets/images/.
enum AgakEmotionState {
  discouraging,
  rewardReveal,
  encouragement,
  celebration,
  pointingSuggestion,
}

extension AgakEmotionAssetX on AgakEmotionState {
  String get assetPath {
    switch (this) {
      case AgakEmotionState.discouraging:
        return 'assets/images/agak_discouraging_rain.png';
      case AgakEmotionState.rewardReveal:
        return 'assets/images/agak_reward_gems.png';
      case AgakEmotionState.encouragement:
        return 'assets/images/agak_encouragement_soar.png';
      case AgakEmotionState.celebration:
        return 'assets/images/agak_celebration_confetti.png';
      case AgakEmotionState.pointingSuggestion:
        return 'assets/images/agak_pointing_suggestion.png';
    }
  }
}

/// A milestone that just occurred, used to trigger the celebration state.
class AgakMilestoneEvent {
  final String label;
  final int completedHikeCount;

  const AgakMilestoneEvent({
    required this.label,
    required this.completedHikeCount,
  });
}

/// A scheduled hike due for a reminder (see agakUpcomingHikeReminderWindowDays
/// in agak_emotion_selector.dart) — carries just enough to render the
/// reminder message without the controller reaching back into the DB.
class AgakUpcomingHikeReminder {
  final String mountainName;
  final int daysUntil;
  final List<String> packingList;

  const AgakUpcomingHikeReminder({
    required this.mountainName,
    required this.daysUntil,
    required this.packingList,
  });
}

/// A pre-classified snapshot of current weather at the user's location,
/// used to decide whether Agak should show the weather-warning mood. The
/// actual forecast lookup lives in the dashboard (it already owns the
/// Google Weather API key and the user's location) — this is just the
/// verdict handed to the emotion selector.
class AgakWeatherSnapshot {
  final bool isSevere;

  /// True for "caution" tier — not severe enough to warn against hiking
  /// outright, but not a clear/safe day either (e.g. heavy overcast that
  /// could turn to rain). Lets callers avoid calling an unsettled day
  /// "great weather" just because it isn't a storm.
  final bool isCaution;
  final String headline;

  const AgakWeatherSnapshot({
    required this.isSevere,
    this.isCaution = false,
    required this.headline,
  });
}

/// The single object the companion UI renders: current top recommendation
/// (if any), which emotion to show, and the message text (rule-based
/// template by default, optionally re-phrased by Gemini when online).
class AgakCompanionMoment {
  final List<AgakRecommendation> recommendations;
  final AgakEmotionState emotion;
  final String message;
  final DateTime createdAt;

  /// Set when the current moment is a scheduled-hike reminder — carries
  /// the full packing list so the UI can show it in full (the message
  /// itself only ever quotes the first few items).
  final AgakUpcomingHikeReminder? upcomingHike;

  const AgakCompanionMoment({
    required this.recommendations,
    required this.emotion,
    required this.message,
    required this.createdAt,
    this.upcomingHike,
  });

  AgakRecommendation? get topRecommendation =>
      recommendations.isEmpty ? null : recommendations.first;

  AgakCompanionMoment copyWith({String? message}) => AgakCompanionMoment(
    recommendations: recommendations,
    emotion: emotion,
    message: message ?? this.message,
    createdAt: createdAt,
    upcomingHike: upcomingHike,
  );
}
