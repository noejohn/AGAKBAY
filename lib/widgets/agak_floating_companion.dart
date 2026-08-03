import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/material.dart';

import '../models/agak_recommendation.dart';
import '../services/agak_controller.dart';
import '../services/agak_tip_bus.dart';
import 'agak_speech_bubble.dart';

/// AGAK's dashboard-wide presence: big, alive mascot artwork (no background,
/// no frame) with a comic-style speech bubble that always shows whatever
/// AGAK currently has to say — mountain trivia, today's weather verdict, an
/// upcoming-hike reminder, or a recommendation. It stays put across every
/// tab (Explore/My Hikes/Community/Profile) instead of disappearing like a
/// notification, and can be dragged anywhere on screen.
///
/// Two distinct taps:
///  - tapping AGAK's body is a poke — a playful bounce and a one-off reaction
///    line, purely for delight, then it settles back to what it was saying.
///  - tapping the speech bubble opens the full AGAK screen.
///
/// Content comes straight from the two sources that already feed AGAK
/// elsewhere: [AgakTipBus] (event-driven — trivia on opening a mountain,
/// weather once a check resolves, milestones, reminders) takes priority
/// when something has been pushed, falling back to [AgakController]'s
/// standing recommendation message. Neither source needs new plumbing —
/// this widget just gives them a permanent, non-intrusive home.
///
/// On cold start those two sources can each fire more than once within a
/// couple of seconds (a local greeting, then an AI-rephrased version of the
/// same greeting, then an ambient weather check resolving) — swapping the
/// bubble instantly every time reads as a flicker and the user never gets
/// to actually finish reading anything. [_holdDurationFor] keeps each
/// message on screen for a stretch that scales with how long it is before
/// the next one is allowed to replace it, and [AnimatedSwitcher] fades
/// between them instead of snapping.
class AgakFloatingCompanion extends StatefulWidget {
  const AgakFloatingCompanion({
    super.key,
    required this.onTap,
    required this.onDragDelta,
  });

  final VoidCallback onTap;

  /// Fired with the raw pointer movement while being dragged; the parent
  /// owns the actual on-screen position (it's the one positioning this
  /// widget via `Positioned`), so this widget only ever reports deltas.
  final ValueChanged<Offset> onDragDelta;

  @override
  State<AgakFloatingCompanion> createState() => _AgakFloatingCompanionState();
}

class _AgakFloatingCompanionState extends State<AgakFloatingCompanion>
    with TickerProviderStateMixin {
  static const double _characterWidth = 200;
  static const double _bubbleMaxWidth = 260;

  static const String _initialGreeting =
      "Hi there! I'm AGAK — how are you doing today?";

  static const List<String> _pokeReactions = [
    "Hehe, that tickles!",
    "Ready for an adventure?",
    "You called? I'm here!",
    "Tap my bubble if you want to really talk!",
    "Squawk! Hi there!",
    "Let's climb something today.",
  ];

  String _displayedMessage = _initialGreeting;
  AgakEmotionState _displayedEmotion = AgakEmotionState.encouragement;
  DateTime? _lastChangeAt;
  Timer? _pendingSwapTimer;
  bool _bubblePressed = false;
  bool _characterPressed = false;

  String? _pokeReaction;
  Timer? _pokeTimer;
  final _random = Random();

  late final AnimationController _idleController;
  late final AnimationController _pokeController;

  @override
  void initState() {
    super.initState();
    if (AgakController.instance.current == null) {
      AgakController.instance.refresh();
    }
    // Starts the hold clock on the greeting itself (rather than leaving
    // this null) so the very first thing AGAK says gets the same
    // guaranteed reading time as everything after it, instead of being
    // swapped out the instant real data loads.
    _lastChangeAt = DateTime.now();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pokeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _pendingSwapTimer?.cancel();
    _pokeTimer?.cancel();
    _idleController.dispose();
    _pokeController.dispose();
    super.dispose();
  }

  /// Longer messages get more time on screen — paced for comfortable
  /// reading (~14 chars/sec, well under average adult reading speed to
  /// leave room for glancing at the app itself at the same time) — instead
  /// of one flat duration too short for anything but the shortest tips.
  Duration _holdDurationFor(String message) {
    final millis = (message.length * 70).clamp(5000, 11000);
    return Duration(milliseconds: millis);
  }

  void _maybeAdopt(String message, AgakEmotionState emotion) {
    if (message == _displayedMessage) return;
    final now = DateTime.now();
    final last = _lastChangeAt;
    final holdDuration = _holdDurationFor(_displayedMessage);
    final elapsed = last == null ? holdDuration : now.difference(last);

    if (elapsed >= holdDuration) {
      _pendingSwapTimer?.cancel();
      setState(() {
        _displayedMessage = message;
        _displayedEmotion = emotion;
        _lastChangeAt = now;
      });
      return;
    }

    _pendingSwapTimer?.cancel();
    _pendingSwapTimer = Timer(holdDuration - elapsed, () {
      if (!mounted) return;
      setState(() {
        _displayedMessage = message;
        _displayedEmotion = emotion;
        _lastChangeAt = DateTime.now();
      });
    });
  }

  void _poke() {
    _pokeController.forward(from: 0);
    _pokeTimer?.cancel();
    setState(() {
      _pokeReaction = _pokeReactions[_random.nextInt(_pokeReactions.length)];
    });
    _pokeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _pokeReaction = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AgakController.instance, AgakTipBus.instance]),
      builder: (context, _) {
        final tip = AgakTipBus.instance.pending;
        final moment = AgakController.instance.current;
        final latestEmotion =
            tip?.emotion ?? moment?.emotion ?? AgakEmotionState.encouragement;
        final latestMessage = tip?.message ?? moment?.message ?? _initialGreeting;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeAdopt(latestMessage, latestEmotion),
        );

        final bubbleText = _pokeReaction ?? _displayedMessage;

        return GestureDetector(
          onPanUpdate: (details) => widget.onDragDelta(details.delta),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: widget.onTap,
                onTapDown: (_) => setState(() => _bubblePressed = true),
                onTapCancel: () => setState(() => _bubblePressed = false),
                onTapUp: (_) => setState(() => _bubblePressed = false),
                behavior: HitTestBehavior.opaque,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _bubbleMaxWidth),
                  child: AnimatedScale(
                    scale: _bubblePressed ? 0.96 : 1,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 380),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                      child: AgakSpeechBubble(
                        key: ValueKey(bubbleText),
                        message: bubbleText,
                        playful: _pokeReaction != null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: _poke,
                onTapDown: (_) => setState(() => _characterPressed = true),
                onTapCancel: () => setState(() => _characterPressed = false),
                onTapUp: (_) => setState(() => _characterPressed = false),
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_idleController, _pokeController]),
                  builder: (context, child) {
                    final breathe = 1.0 + (_idleController.value * 0.035);
                    final pokeBounce =
                        1.0 +
                        (Curves.elasticOut.transform(_pokeController.value) *
                            0.22 *
                            (1 - _pokeController.value));
                    final pressScale = _characterPressed ? 0.95 : 1.0;
                    return Transform.scale(
                      scale: breathe * pokeBounce * pressScale,
                      child: child,
                    );
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Image.asset(
                      _displayedEmotion.assetPath,
                      key: ValueKey(_displayedEmotion),
                      width: _characterWidth,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(
                            width: _characterWidth,
                            height: _characterWidth,
                          ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
