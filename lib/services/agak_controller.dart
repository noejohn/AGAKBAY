import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agak_behavior.dart';
import '../models/agak_mountain.dart';
import '../models/agak_recommendation.dart';
import 'agak_behavior_database.dart';
import 'agak_emotion_selector.dart';
import 'agak_packing_list.dart';
import 'agak_recommendation_engine.dart';
import 'agak_tip_bus.dart';
import 'gemini_client.dart';

/// Ties the offline recommendation engine to the companion UI. Owns the
/// current `AgakCompanionMoment` and notifies listeners when it changes.
///
/// The recommendation *decision* always comes from `agak_recommendation_engine`
/// and is available immediately, fully offline. If a Gemini key is
/// available and the device is online, [refresh] best-effort rephrases the
/// same decision into warmer text — it never asks the LLM what to
/// recommend, only how to phrase what was already decided.
class AgakController extends ChangeNotifier {
  AgakController._();

  static final AgakController instance = AgakController._();

  AgakCompanionMoment? _current;
  bool _isLoading = false;
  DateTime? _lastRefreshAt;
  AgakWeatherSnapshot? _ambientWeather;
  String? _lastPushedReminderKey;

  AgakCompanionMoment? get current => _current;
  bool get isLoading => _isLoading;

  /// The most recent current-location weather check, if one has resolved
  /// yet — populated for good weather too (not just warnings), so surfaces
  /// like the rotating tip popup have something to say about "today's
  /// weather" even when there's nothing to warn about.
  AgakWeatherSnapshot? get ambientWeather => _ambientWeather;

  /// Called once a current-location weather check resolves (see
  /// _refreshAgakAmbientWeather in the dashboard). Cheap to call again on
  /// every check — only forces a recompute when the good/bad verdict
  /// actually flips, so a routine re-check doesn't cause a visible flicker.
  void updateAmbientWeather(AgakWeatherSnapshot? snapshot) {
    final changed = snapshot?.isSevere != _ambientWeather?.isSevere;
    _ambientWeather = snapshot;
    if (changed) {
      unawaited(refresh(force: true));
    }
  }

  /// Recomputes the profile + recommendations from local behavior data and
  /// updates [current]. Debounced to avoid a full recompute on every single
  /// instrumentation call — pass [force] to bypass (e.g. right after a
  /// completed hike, a strong signal worth reacting to immediately).
  Future<void> refresh({bool force = false, AgakMilestoneEvent? milestone}) async {
    final last = _lastRefreshAt;
    if (!force &&
        milestone == null &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastRefreshAt = DateTime.now();

    _isLoading = true;
    notifyListeners();

    try {
      final db = AgakBehaviorDatabase.instance;
      final List<MountainCatalogEntry> catalog = await db.getCatalog();
      final List<SearchHistoryEntry> searches = await db.getRecentSearches();
      final List<ViewHistoryEntry> views = await db.getRecentViews();
      final List<BookmarkEntry> bookmarks = await db.getBookmarks();
      final List<CompletedHikeEntry> completedHikes =
          await db.getCompletedHikes();
      final List<ScheduledHikeEntry> upcomingScheduledHikes =
          await db.getUpcomingScheduledHikes();

      final profile = computeProfile(
        searches: searches,
        views: views,
        bookmarks: bookmarks,
        completedHikes: completedHikes,
        catalog: catalog,
      );
      unawaited(db.cacheProfile(profile.encode()));

      final completedMatchKeys = completedHikes
          .map((h) => h.mountainId)
          .whereType<String>()
          .toSet();

      final upcomingHike = _buildUpcomingHikeReminder(
        upcomingScheduledHikes,
        catalog,
      );

      final recommendations = recommend(
        profile: profile,
        catalog: catalog,
        completedMatchKeys: completedMatchKeys,
        recentSearches: searches,
        bookmarks: bookmarks,
        completedHikes: completedHikes,
      );

      final emotion = selectEmotion(
        recommendations: recommendations,
        profile: profile,
        justHitMilestone: milestone,
        weatherNow: _ambientWeather,
        upcomingHike: upcomingHike,
      );

      final message = _templateMessage(
        recommendations: recommendations,
        emotion: emotion,
        milestone: milestone,
        weatherNow: _ambientWeather,
        upcomingHike: upcomingHike,
      );

      _current = AgakCompanionMoment(
        recommendations: recommendations,
        emotion: emotion,
        message: message,
        createdAt: DateTime.now(),
        upcomingHike: upcomingHike,
      );
      _isLoading = false;
      notifyListeners();
      _pushTipIfNotable(milestone: milestone, upcomingHike: upcomingHike);

      unawaited(_tryPhraseWithAi(_current!));
    } catch (error) {
      debugPrint('AgakController.refresh failed: $error');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pushes a home-screen pop-up for the two event-like categories that
  /// deserve one: a just-hit milestone (always, it's a one-off real-time
  /// event) and a due hike reminder (deduped by mountain+daysUntil, so it
  /// surfaces once when it first becomes relevant and again if the day
  /// count changes, but doesn't re-pop on every unrelated refresh).
  void _pushTipIfNotable({
    required AgakMilestoneEvent? milestone,
    required AgakUpcomingHikeReminder? upcomingHike,
  }) {
    final moment = _current;
    if (moment == null) return;

    if (milestone != null) {
      AgakTipBus.instance.push(
        AgakTip(emotion: moment.emotion, message: moment.message),
      );
      return;
    }

    if (upcomingHike != null) {
      final reminderKey = '${upcomingHike.mountainName}|${upcomingHike.daysUntil}';
      if (reminderKey != _lastPushedReminderKey) {
        _lastPushedReminderKey = reminderKey;
        AgakTipBus.instance.push(
          AgakTip(emotion: moment.emotion, message: moment.message),
        );
      }
    }
  }

  /// The soonest scheduled hike that's due for a reminder, enriched with a
  /// packing list from the catalog when a match is found (falling back to
  /// the denormalized difficulty/elevation stored on the entry itself).
  AgakUpcomingHikeReminder? _buildUpcomingHikeReminder(
    List<ScheduledHikeEntry> upcomingScheduledHikes,
    List<MountainCatalogEntry> catalog,
  ) {
    if (upcomingScheduledHikes.isEmpty) return null;
    final next = upcomingScheduledHikes.first;
    if (next.daysUntil > agakUpcomingHikeReminderWindowDays) return null;

    final catalogMatches = next.mountainId == null
        ? const <MountainCatalogEntry>[]
        : catalog.where((m) => m.matchKey == next.mountainId).toList();
    final catalogMatch = catalogMatches.isEmpty ? null : catalogMatches.first;

    return AgakUpcomingHikeReminder(
      mountainName: next.mountainName,
      daysUntil: next.daysUntil,
      packingList: buildPackingList(
        difficulty: catalogMatch?.difficulty ?? next.difficulty ?? 'Moderate',
        elevationMasl: catalogMatch?.elevationMasl ?? next.elevationMasl,
        trailTypes: catalogMatch?.trailTypes ?? const [],
        features: catalogMatch?.features ?? const [],
      ),
    );
  }

  String _templateMessage({
    required List<AgakRecommendation> recommendations,
    required AgakEmotionState emotion,
    AgakMilestoneEvent? milestone,
    AgakWeatherSnapshot? weatherNow,
    AgakUpcomingHikeReminder? upcomingHike,
  }) {
    if (milestone != null) {
      return '${milestone.label} I\'m proud of you — ready for what\'s next?';
    }
    if (weatherNow != null && weatherNow.isSevere) {
      final tip = recommendations.isEmpty
          ? ' Maybe use today to sort your gear or plan your next route instead.'
          : ' How about planning ${recommendations.first.mountain.name} for a '
                'clearer day instead?';
      return '${weatherNow.headline}.$tip';
    }
    if (upcomingHike != null) {
      final when = switch (upcomingHike.daysUntil) {
        <= 0 => 'today',
        1 => 'tomorrow',
        final days => 'in $days days',
      };
      final gearPreview = upcomingHike.packingList.take(3).join(', ');
      return 'Your hike to ${upcomingHike.mountainName} is $when! '
          "Don't forget: $gearPreview.";
    }
    if (recommendations.isEmpty) {
      return "Hey there! I'm still getting to know your hiking style — "
          'search, view, or bookmark a mountain, or schedule your next '
          "hike and I'll start putting together a gear list for it.";
    }
    final top = recommendations.first;
    final buffer = StringBuffer(top.headline);
    if (top.supportingFact != null) {
      buffer.write(' ${top.supportingFact}');
    }
    return buffer.toString();
  }

  Future<void> _tryPhraseWithAi(AgakCompanionMoment moment) async {
    try {
      final apiKey = await loadGeminiApiKey();
      if (apiKey.isEmpty) return;

      final top = moment.topRecommendation;
      final prompt = top == null
          ? 'Rephrase this warmly in 2 short sentences, like a companion '
              'greeting a friend: keep both the encouraging tone AND every '
              'concrete suggestion it mentions (searching, viewing, '
              'bookmarking, or scheduling a hike) — do not drop the call '
              'to action, and do not invent mountain names or facts: '
              '"${moment.message}"'
          : 'Rephrase this hiking recommendation warmly in 1-2 sentences. '
              'Do not invent new mountains or facts beyond what is given. '
              'Mountain: ${top.mountain.name} (${top.mountain.region}, '
              '${top.mountain.elevationMasl}m, ${top.mountain.difficulty}). '
              'Reason: ${top.reason.name}. '
              'Original message: "${moment.message}"';

      final phrased = await fetchGeminiResponse(
        apiKey: apiKey,
        systemInstruction:
            'You are AGAK, a friendly bald-eagle hiking companion mascot '
            'for the Agakbay app, guiding hikers in Mindanao, Philippines. '
            'You are given a recommendation someone else already decided — '
            'your only job is to phrase it warmly and briefly. Never '
            'suggest a different mountain or invent new facts.',
        prompt: prompt,
        maxOutputTokens: 120,
      );

      if (phrased.isNotEmpty && _current?.createdAt == moment.createdAt) {
        _current = moment.copyWith(message: phrased);
        notifyListeners();
      }
    } catch (error) {
      debugPrint('AgakController AI phrasing failed: $error');
    }
  }
}
