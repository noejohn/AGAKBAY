import 'package:flutter/material.dart';

import '../models/agak_recommendation.dart';
import '../services/agak_controller.dart';
import '../widgets/agak_speech_bubble.dart';
import '../widgets/agak_theme.dart';
import 'agak_emotion_showcase_screen.dart';

/// AGAK's full-screen surface: the recommendation feed plus a way to open
/// the existing hike-assistant chat. Reached from the dashboard's "Hike
/// Assistant" entry point (repointed here) and from the peek overlay's
/// "Ask AGAK" button.
///
/// Deliberately does NOT re-implement the chat UI — "Open full chat" pushes
/// the existing, untouched hike-assistant screen via [openHikeAssistantChat]
/// so this stays additive rather than risking a merge of two chat surfaces.
///
/// Scheduled-hike management deliberately does NOT live here — see
/// AgakScheduledHikesScreen (reached from the hamburger menu) — this screen
/// stays focused on mood + recommendations only.
class AgakCompanionScreen extends StatefulWidget {
  const AgakCompanionScreen({super.key, this.openHikeAssistantChat});

  /// Pushes the app's existing hike-assistant chat screen. Optional so this
  /// screen/file has no compile-time dependency on main.dart; when null,
  /// falls back to a message directing the user back to the dashboard.
  final VoidCallback? openHikeAssistantChat;

  @override
  State<AgakCompanionScreen> createState() => _AgakCompanionScreenState();
}

class _AgakCompanionScreenState extends State<AgakCompanionScreen> {
  @override
  void initState() {
    super.initState();
    if (AgakController.instance.current == null) {
      AgakController.instance.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AgakColors.screenBackground),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: AgakController.instance,
            builder: (context, _) {
              final moment = AgakController.instance.current;
              final isLoading = AgakController.instance.isLoading;
              final recommendations = moment?.recommendations ?? const [];

              return RefreshIndicator(
                onRefresh: () => AgakController.instance.refresh(force: true),
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      pinned: false,
                      floating: true,
                      title: const Text('AGAK', style: AgakText.screenTitle),
                      actions: [
                        IconButton(
                          tooltip: "Meet Agak's Emotions",
                          icon: const Icon(Icons.auto_awesome_rounded),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    const AgakEmotionShowcaseScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      sliver: SliverToBoxAdapter(
                        child: _CompanionHero(moment: moment, isLoading: isLoading),
                      ),
                    ),
                    if (moment?.upcomingHike != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverToBoxAdapter(
                          child: _WhatToBringCard(
                            reminder: moment!.upcomingHike!,
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'SUGGESTED FOR YOU',
                          style: AgakText.caption.copyWith(
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      sliver: recommendations.isEmpty && !isLoading
                          ? SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Text(
                                  "I don't have enough to go on yet — "
                                  'search, view, bookmark, or complete a '
                                  "hike and I'll start suggesting mountains "
                                  'that fit your style.',
                                  style: AgakText.body.copyWith(
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            )
                          : SliverList.list(
                              children: recommendations
                                  .map(
                                    (r) => _RecommendationCard(
                                      recommendation: r,
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                      sliver: SliverToBoxAdapter(
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (widget.openHikeAssistantChat != null) {
                                widget.openHikeAssistantChat!();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Open Hike Assistant from the dashboard.',
                                    ),
                                  ),
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AgakColors.accent,
                              side: const BorderSide(color: AgakColors.accent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: const Text('Open full chat'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The screen's hero: a tagline, AGAK's artwork at real size (no
/// background, no frame — same "just the character" treatment as the
/// dashboard's floating companion), and a comic speech bubble carrying
/// whatever AGAK currently has to say. Loosely modeled on a reference the
/// user shared of a generic "AI companion" hero card — reworked with
/// AGAK's own eagle art, dark green palette, and hiking-flavored copy
/// rather than copied wholesale.
class _CompanionHero extends StatelessWidget {
  const _CompanionHero({required this.moment, required this.isLoading});

  final AgakCompanionMoment? moment;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final emotion = moment?.emotion ?? AgakEmotionState.pointingSuggestion;
    final message = isLoading && moment == null
        ? 'Getting to know your hiking style...'
        : (moment?.message ?? "I'm still learning what you like.");

    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AgakText.screenTitle.copyWith(
              color: Colors.white,
              fontSize: 25,
              height: 1.2,
            ),
            children: const [
              TextSpan(text: 'Your '),
              TextSpan(
                text: 'AGAK',
                style: TextStyle(color: AgakColors.accent),
              ),
              TextSpan(text: '\nTrail Companion'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 230,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 4,
                bottom: 0,
                child: Image.asset(
                  emotion.assetPath,
                  width: 190,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox(width: 190, height: 190),
                ),
              ),
              Positioned(
                right: 0,
                top: 14,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: AgakSpeechBubble(
                    message: message,
                    maxLines: 6,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WhatToBringCard extends StatelessWidget {
  const _WhatToBringCard({required this.reminder});

  final AgakUpcomingHikeReminder reminder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgakColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.backpack_rounded,
                color: AgakColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'WHAT TO BRING · ${reminder.mountainName.toUpperCase()}',
                style: AgakText.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...reminder.packingList.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: AgakColors.accent,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: AgakText.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});

  final AgakRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final mountain = recommendation.mountain;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AgakColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AgakColors.border.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.landscape_rounded,
              color: AgakColors.accentSoft,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mountain.name,
                  style: AgakText.cardTitle.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _statChip(mountain.region),
                    _statChip('${mountain.elevationMasl}m'),
                    _statChip(mountain.difficulty),
                  ],
                ),
                if (recommendation.supportingFact != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    recommendation.supportingFact!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.68),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
