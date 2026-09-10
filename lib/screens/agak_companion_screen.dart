import 'dart:async';

import 'package:flutter/material.dart';

import '../models/agak_recommendation.dart';
import '../services/agak_behavior_database.dart';
import '../services/agak_controller.dart';
import '../services/agak_item_reaction.dart';
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
  const AgakCompanionScreen({super.key, this.chatPanelBuilder});

  /// Builds the ask-Kyrielle box, embedded directly in this screen rather
  /// than pushed as a separate route. Takes the same `onAnswer` callback
  /// used for packing-item reactions, so the assistant's answer shows in
  /// this screen's own hero speech bubble instead of a chat log of its
  /// own. A builder (not the widget itself) so this screen/file keeps no
  /// compile-time dependency on main.dart; when null, shows a message
  /// directing the user back to the dashboard instead.
  final Widget Function(BuildContext context, ValueChanged<String> onAnswer)?
  chatPanelBuilder;

  @override
  State<AgakCompanionScreen> createState() => _AgakCompanionScreenState();
}

class _AgakCompanionScreenState extends State<AgakCompanionScreen> {
  String? _reactionOverride;
  Timer? _reactionOverrideTimer;

  void _showReactionInHero(String message) {
    setState(() => _reactionOverride = message);
    _reactionOverrideTimer?.cancel();
    _reactionOverrideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _reactionOverride = null);
      }
    });
  }

  @override
  void dispose() {
    _reactionOverrideTimer?.cancel();
    super.dispose();
  }

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
                      title: const Text(
                        'Kyrielle',
                        style: TextStyle(
                          color: AgakColors.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.1,
                        ),
                      ),
                      actions: [
                        IconButton(
                          tooltip: "Meet Kyrielle's Emotions",
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
                        child: _CompanionHero(
                          moment: moment,
                          isLoading: isLoading,
                          overrideMessage: _reactionOverride,
                        ),
                      ),
                    ),
                    if (moment?.upcomingHike != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverToBoxAdapter(
                          child: _WhatToBringCard(
                            reminder: moment!.upcomingHike!,
                            onReaction: _showReactionInHero,
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'SUGGESTED FOR YOU',
                          style: AgakText.caption.copyWith(
                            color: AgakColors.ink.withValues(alpha: 0.55),
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
                                    color: AgakColors.ink.withValues(alpha: 0.6),
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
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AgakColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AgakColors.ink.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: AgakColors.accent,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ASK KYRIELLE ANYTHING',
                                    style: AgakText.caption.copyWith(
                                      color: AgakColors.ink.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (widget.chatPanelBuilder != null)
                                widget.chatPanelBuilder!(
                                  context,
                                  _showReactionInHero,
                                )
                              else
                                Text(
                                  'Open Kyrielle from the dashboard to ask '
                                  'questions.',
                                  style: AgakText.body.copyWith(
                                    color: AgakColors.ink.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                            ],
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
/// Kyrielle's own eagle art, cream/gold/olive/maroon palette, and
/// hiking-flavored copy rather than copied wholesale.
class _CompanionHero extends StatelessWidget {
  const _CompanionHero({
    required this.moment,
    required this.isLoading,
    this.overrideMessage,
  });

  final AgakCompanionMoment? moment;
  final bool isLoading;

  /// When set (e.g. Kyrielle reacting to a packing-list item the user just
  /// added), replaces the normal moment message temporarily — the caller
  /// is responsible for clearing it back to null after a delay.
  final String? overrideMessage;

  @override
  Widget build(BuildContext context) {
    final emotion = moment?.emotion ?? AgakEmotionState.pointingSuggestion;
    final message = overrideMessage ??
        (isLoading && moment == null
            ? 'Getting to know your hiking style...'
            : (moment?.message ?? "I'm still learning what you like."));

    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AgakText.screenTitle.copyWith(
              color: AgakColors.ink,
              fontSize: 25,
              height: 1.2,
            ),
            children: const [
              TextSpan(text: 'Your '),
              TextSpan(
                text: 'Kyrielle',
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

class _WhatToBringCard extends StatefulWidget {
  const _WhatToBringCard({required this.reminder, required this.onReaction});

  final AgakUpcomingHikeReminder reminder;

  /// Called with Kyrielle's reaction text once an item's been added — the
  /// parent screen shows it in the hero's existing speech bubble rather
  /// than this card popping up a second one of its own.
  final ValueChanged<String> onReaction;

  @override
  State<_WhatToBringCard> createState() => _WhatToBringCardState();
}

class _WhatToBringCardState extends State<_WhatToBringCard> {
  final _itemController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _itemController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final hikeId = widget.reminder.hikeId;
    final item = _itemController.text.trim();
    if (item.isEmpty || hikeId == null || _isAdding) {
      return;
    }
    setState(() => _isAdding = true);
    _itemController.clear();
    FocusScope.of(context).unfocus();

    await AgakBehaviorDatabase.instance.addCustomPackingItem(hikeId, item);
    unawaited(AgakController.instance.refresh(force: true));

    final reaction = await reactionForPackingItem(item);
    if (!mounted) {
      return;
    }
    setState(() => _isAdding = false);
    widget.onReaction(reaction);
  }

  @override
  Widget build(BuildContext context) {
    final reminder = widget.reminder;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgakColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.08)),
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
                  color: AgakColors.ink.withValues(alpha: 0.6),
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
                        color: AgakColors.ink.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.reminder.hikeId != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemController,
                    enabled: !_isAdding,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addItem(),
                    decoration: InputDecoration(
                      hintText: 'Add your own item...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isAdding ? null : _addItem,
                  icon: _isAdding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_circle, color: AgakColors.accent),
                  tooltip: 'Add item',
                ),
              ],
            ),
          ],
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
        border: Border.all(color: AgakColors.ink.withValues(alpha: 0.08)),
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
                  style: AgakText.cardTitle.copyWith(color: AgakColors.ink),
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
                      color: AgakColors.ink.withValues(alpha: 0.68),
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
        color: AgakColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AgakColors.ink.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
