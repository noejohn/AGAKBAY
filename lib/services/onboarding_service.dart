import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agak_mountain.dart';
import '../models/agak_recommendation.dart';

/// Persists the first-run onboarding answers and turns them into a first
/// batch of mountain suggestions for the confirmation screen.
class OnboardingService {
  OnboardingService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Accounts created before onboarding existed have no `onboardingComplete`
  /// field at all — treated as already-onboarded so existing users aren't
  /// suddenly interrupted by a flow that didn't exist when they signed up.
  Future<bool> hasCompletedOnboarding(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final value = snapshot.data()?['onboardingComplete'];
    if (value is bool) return value;
    return true;
  }

  Future<void> saveOnboardingAnswers({
    required String uid,
    required String firstName,
    required String skillLevel,
    required List<String> weatherPreferences,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'firstName': firstName,
      'skillLevel': skillLevel,
      'weatherPreferences': weatherPreferences,
      'onboardingComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static const Map<String, String> difficultyBySkill = {
    'Beginner': 'Easy',
    'Intermediate': 'Moderate',
    'Advanced': 'Hard',
  };

  /// The catalog has no per-trail weather field, so weather preference
  /// can't filter mountains the way skill level can — it only re-ranks
  /// within the skill-matched set, using feature tags as a proxy (open
  /// viewpoints for sun, canopy/waterfalls for rain). [liveWeather], when
  /// available, adds the same bias as if the user had picked the matching
  /// preference themselves — this is what makes the confirmation shortlist
  /// reflect what's actually happening at their location, not just what
  /// they said they usually like.
  List<MountainCatalogEntry> recommendMountains({
    required String skillLevel,
    required List<String> weatherPreferences,
    required List<MountainCatalogEntry> catalog,
    AgakWeatherSnapshot? liveWeather,
    int maxResults = 3,
  }) {
    final targetDifficulty = difficultyBySkill[skillLevel];
    var candidates = targetDifficulty == null
        ? List<MountainCatalogEntry>.of(catalog)
        : catalog.where((m) => m.difficulty == targetDifficulty).toList();
    if (candidates.isEmpty) {
      candidates = List<MountainCatalogEntry>.of(catalog);
    }
    candidates.sort(
      (a, b) => _weatherScore(
        b,
        weatherPreferences,
        liveWeather,
      ).compareTo(_weatherScore(a, weatherPreferences, liveWeather)),
    );
    return candidates.take(maxResults).toList();
  }

  int _weatherScore(
    MountainCatalogEntry mountain,
    List<String> weatherPreferences,
    AgakWeatherSnapshot? liveWeather,
  ) {
    var score = 0;
    final effectivePreferences = {...weatherPreferences};
    if (liveWeather != null) {
      if (liveWeather.isSunny) effectivePreferences.add('Sunny');
      if (liveWeather.isCaution || liveWeather.isSevere) {
        effectivePreferences.add('Rain');
      }
    }
    for (final preference in effectivePreferences) {
      switch (preference) {
        case 'Sunny':
          if (mountain.features.any(
            const ['sunrise-viewpoint', 'lake-view', 'crater'].contains,
          )) {
            score += 2;
          }
        case 'Overcast':
          if (mountain.features.any(
            const [
              'forest',
              'mossy-forest',
              'wildlife-sanctuary',
              'pygmy-forest',
            ].contains,
          )) {
            score += 2;
          }
        case 'Rain':
          if (mountain.features.any(
            const ['waterfall', 'forest', 'mossy-forest'].contains,
          )) {
            score += 2;
          }
      }
    }
    return score;
  }
}
