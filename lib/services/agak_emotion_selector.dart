import '../models/agak_preference_profile.dart';
import '../models/agak_recommendation.dart';

/// Picks which of AGAK's 5 emotion states best fits the current moment.
/// Pure function, first-match-wins priority order.
AgakEmotionState selectEmotion({
  required List<AgakRecommendation> recommendations,
  required UserPreferenceProfile profile,
  AgakMilestoneEvent? justHitMilestone,
  AgakWeatherSnapshot? weatherNow,
  AgakUpcomingHikeReminder? upcomingHike,
}) {
  if (justHitMilestone != null) {
    return AgakEmotionState.celebration;
  }

  // A real-time milestone always wins, but bad weather right now outranks
  // the ranking-based moods below — no point looking excited about a
  // recommendation while warning the user about a storm.
  if (weatherNow != null && weatherNow.isSevere) {
    return AgakEmotionState.discouraging;
  }

  // A hike coming up soon is good news worth being excited about — same
  // energetic mood as the difficulty-progression nudge below.
  if (upcomingHike != null) {
    return AgakEmotionState.encouragement;
  }

  if (recommendations.isEmpty) {
    // A brand-new profile or an offline/empty catalog — nothing ranked to
    // react to yet, but nothing wrong either, so this stays a neutral
    // greeting rather than the rainy "discouraging" mood (that one is
    // reserved for an actual weather warning above).
    return AgakEmotionState.pointingSuggestion;
  }

  final top = recommendations.first;
  final second = recommendations.length > 1 ? recommendations[1] : null;
  final isDominant = second == null || top.score >= second.score * 1.5;

  if (top.reason == AgakRecommendationReason.similarToClimbed || isDominant) {
    return AgakEmotionState.rewardReveal;
  }

  if (top.reason == AgakRecommendationReason.easyToIntermediateNudge ||
      top.reason == AgakRecommendationReason.difficultyProgression) {
    return AgakEmotionState.encouragement;
  }

  return AgakEmotionState.pointingSuggestion;
}

/// Milestone thresholds for the celebration state — easy to retune later.
const List<int> agakMilestoneCompletedHikeCounts = [1, 5, 10, 25, 50];

/// A scheduled hike starts surfacing as a companion reminder once it's
/// this many days away or closer (0 = the day itself).
const int agakUpcomingHikeReminderWindowDays = 3;

AgakMilestoneEvent? detectCompletedHikeMilestone(int completedHikeCount) {
  if (!agakMilestoneCompletedHikeCounts.contains(completedHikeCount)) {
    return null;
  }
  return AgakMilestoneEvent(
    label: completedHikeCount == 1
        ? 'First summit completed!'
        : '$completedHikeCount hikes completed!',
    completedHikeCount: completedHikeCount,
  );
}
