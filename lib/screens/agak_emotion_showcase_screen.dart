import 'package:flutter/material.dart';

import '../models/agak_recommendation.dart';
import '../widgets/agak_theme.dart';

/// Static feature-showcase page explaining AGAK's 5 mascot moods to the
/// user. Purely informational — it reuses the same 5 eagle illustrations
/// that back [AgakEmotionState] (via [AgakEmotionAssetX.assetPath]) but maps
/// them onto a separate, more user-facing set of labels than the production
/// recommendation-driven states in agak_emotion_selector.dart.
class AgakEmotionShowcaseScreen extends StatelessWidget {
  const AgakEmotionShowcaseScreen({super.key});

  static final List<_EmotionShowcaseItem> _items = [
    _EmotionShowcaseItem(
      emoji: '😊',
      title: 'Normal Conversation',
      pastelColor: const Color(0xFFDFF3E3),
      accentColor: const Color(0xFF2F8C5A),
      icon: Icons.chat_bubble_rounded,
      assetPath: AgakEmotionState.pointingSuggestion.assetPath,
      description:
          'Agak greets the user, gives daily tips, hiking suggestions, and '
          'personalized recommendations.',
      sampleMessage: 'Good morning! Ready for your next adventure?',
      triggers: const [
        'Opens the app',
        'Browsing mountains',
        'Daily greeting',
      ],
      relatedRecommendations: const [
        'Nearby trails worth a look today',
        'Mountains matching your usual difficulty',
        'A gentle nudge back in if you\'ve been away',
      ],
    ),
    _EmotionShowcaseItem(
      emoji: '😄',
      title: 'Happy',
      pastelColor: const Color(0xFFFFF3CE),
      accentColor: const Color(0xFFC98A00),
      icon: Icons.sentiment_very_satisfied_rounded,
      assetPath: AgakEmotionState.encouragement.assetPath,
      description:
          'Appears when the user completes a hike, finishes goals, or '
          'packs everything needed.',
      sampleMessage: 'Great job! You completed your hike. Keep exploring!',
      triggers: const [
        'Completed hike',
        'Finished checklist',
        'Packed all equipment',
      ],
      relatedRecommendations: const [
        'A slightly harder trail for next time',
        'Gear you\'re still missing for future hikes',
        'Nearby mountains you haven\'t logged yet',
      ],
    ),
    _EmotionShowcaseItem(
      emoji: '🤩',
      title: 'Amazed',
      pastelColor: const Color(0xFFEDE3FA),
      accentColor: const Color(0xFF7C5CD1),
      icon: Icons.auto_awesome_rounded,
      assetPath: AgakEmotionState.rewardReveal.assetPath,
      description:
          'Appears when the user achieves something impressive such as '
          'highest elevation climbed, a personal record, a rare mountain '
          'discovered, or a difficult trail completed.',
      sampleMessage: "Wow! That's your highest mountain yet!",
      triggers: const [
        'Highest elevation climbed',
        'Personal record',
        'Rare mountain discovered',
        'Difficult trail completed',
      ],
      relatedRecommendations: const [
        'Other rare peaks near your record',
        'Trails other climbers found similarly tough',
        'A milestone badge you\'re close to unlocking',
      ],
    ),
    _EmotionShowcaseItem(
      emoji: '🌧️',
      title: 'Weather Warning',
      pastelColor: const Color(0xFFDCEEFB),
      accentColor: const Color(0xFF3B9FD6),
      icon: Icons.thunderstorm_rounded,
      assetPath: AgakEmotionState.discouraging.assetPath,
      description:
          'Warns users about dangerous weather, strong winds, heavy rain, '
          'or trail closures.',
      sampleMessage:
          'Heavy rain is expected tomorrow. Consider postponing your hike.',
      triggers: const [
        'Heavy rain',
        'Storm',
        'Strong wind',
        'Dangerous trail',
      ],
      relatedRecommendations: const [
        'Easier, low-exposure trails as an alternative',
        'A better window later in the week',
        'Safety checklist before heading out anyway',
      ],
    ),
    _EmotionShowcaseItem(
      emoji: '🎉',
      title: 'Celebrate',
      pastelColor: const Color(0xFFFBE0EC),
      accentColor: const Color(0xFFD1618F),
      icon: Icons.celebration_rounded,
      assetPath: AgakEmotionState.celebration.assetPath,
      description:
          'Celebrates achievements, new badges, hiking streaks, milestones, '
          'and community events.',
      sampleMessage: "Congratulations! You earned the Explorer Badge!",
      triggers: const [
        'Badge unlocked',
        'Hiking streak',
        'Challenge completed',
        'Community milestone',
      ],
      relatedRecommendations: const [
        'The next badge on your path',
        'A community event to keep the streak going',
        'Friends nearby hitting similar milestones',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF15432D), Color(0xFF082A1C), Color(0xFF020D09)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 380 ? 1 : 2;
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: false,
                    floating: true,
                    title: const Text(
                      'AI Companion Emotions',
                      style: AgakText.screenTitle,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        "Agak understands your hiking journey and changes "
                        "emotions to guide, encourage, and protect you.",
                        style: AgakText.body.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: crossAxisCount == 1 ? 1.5 : 0.74,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _EmotionCard(item: _items[index]),
                        childCount: _items.length,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
                    sliver: SliverToBoxAdapter(
                      child: _HowAgakDecidesSection(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmotionShowcaseItem {
  const _EmotionShowcaseItem({
    required this.emoji,
    required this.title,
    required this.pastelColor,
    required this.accentColor,
    required this.icon,
    required this.assetPath,
    required this.description,
    required this.sampleMessage,
    required this.triggers,
    required this.relatedRecommendations,
  });

  final String emoji;
  final String title;
  final Color pastelColor;
  final Color accentColor;
  final IconData icon;
  final String assetPath;
  final String description;
  final String sampleMessage;
  final List<String> triggers;
  final List<String> relatedRecommendations;
}

class _EmotionCard extends StatefulWidget {
  const _EmotionCard({required this.item});

  final _EmotionShowcaseItem item;

  @override
  State<_EmotionCard> createState() => _EmotionCardState();
}

class _EmotionCardState extends State<_EmotionCard> {
  bool _hovering = false;
  bool _pressed = false;

  void _openDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmotionDetailSheet(item: widget.item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scale = _pressed ? 0.97 : (_hovering ? 1.03 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: item.accentColor.withValues(
                  alpha: _hovering ? 0.32 : 0.16,
                ),
                blurRadius: _hovering ? 22 : 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: item.pastelColor,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openDetail(context),
              onHighlightChanged: (v) => setState(() => _pressed = v),
              splashColor: item.accentColor.withValues(alpha: 0.18),
              highlightColor: item.accentColor.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.emoji} ${item.title}',
                            style: TextStyle(
                              color: const Color(0xFF1D2A22),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: item.accentColor.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item.icon,
                            color: item.accentColor,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Center(
                        child: Image.asset(
                          item.assetPath,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.flutter_dash,
                            color: item.accentColor,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF3B473F),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmotionDetailSheet extends StatelessWidget {
  const _EmotionDetailSheet({required this.item});

  final _EmotionShowcaseItem item;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B241A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: BoxDecoration(
                  color: item.pastelColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 150,
                      child: Image.asset(
                        item.assetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.flutter_dash,
                          color: item.accentColor,
                          size: 64,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${item.emoji} ${item.title}',
                      style: const TextStyle(
                        color: Color(0xFF1D2A22),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _detailLabel('Sample message'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12231A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: item.accentColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Image.asset(
                                item.assetPath,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    ColoredBox(
                                  color: item.accentColor,
                                  child: const Icon(
                                    Icons.flutter_dash,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.sampleMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _detailLabel('When this appears'),
                    const SizedBox(height: 8),
                    ...item.triggers.map(
                      (t) => _bulletRow(
                        icon: Icons.check_circle_rounded,
                        color: item.accentColor,
                        text: t,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _detailLabel('Related recommendations'),
                    const SizedBox(height: 8),
                    ...item.relatedRecommendations.map(
                      (r) => _bulletRow(
                        icon: Icons.arrow_right_rounded,
                        color: Colors.white70,
                        text: r,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _bulletRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowAgakDecidesSection extends StatelessWidget {
  const _HowAgakDecidesSection();

  static const _steps = [
    (icon: Icons.person_pin_circle_rounded, label: 'User Data'),
    (icon: Icons.psychology_alt_rounded, label: 'AI Companion Engine'),
    (icon: Icons.mood_rounded, label: 'Emotion Detection'),
    (icon: Icons.recommend_rounded, label: 'Recommendation Engine'),
    (icon: Icons.chat_bubble_outline_rounded, label: 'Personalized Message'),
    (icon: Icons.animation_rounded, label: 'Animated Emotion'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How Agak Decides',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < _steps.length; i++) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF061F16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Icon(_steps[i].icon, color: const Color(0xFF53D97A), size: 20),
                const SizedBox(width: 12),
                Text(
                  _steps[i].label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (i != _steps.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Icon(
                Icons.arrow_downward_rounded,
                color: Colors.white.withValues(alpha: 0.4),
                size: 18,
              ),
            ),
        ],
      ],
    );
  }
}
