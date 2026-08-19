import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/agak_recommendation.dart';
import '../widgets/agak_speech_bubble.dart';

/// The screen opened by tapping AGAK's floating speech bubble — a warm,
/// light "talk to your trail companion" landing distinct from the rest of
/// the app's dark theme, matching a reference mockup the user shared.
///
/// Typed or spoken questions are answered right here as an inline
/// conversation (via [askQuestion], the same answer logic the dark
/// hike-assistant chat uses) rather than navigating to that other screen —
/// jumping to a differently-themed surface mid-conversation broke the
/// "talking to Kyrielle" feel. Only "Nearest trail" leaves this screen, since
/// that's a real feature (the nearby-trails sheet) rather than a question.
class KyrielleCompanionChatScreen extends StatefulWidget {
  const KyrielleCompanionChatScreen({
    super.key,
    required this.userFirstName,
    required this.onNearestTrail,
    required this.askQuestion,
  });

  final String userFirstName;

  /// Opens the app's existing nearby-trails sheet.
  final VoidCallback onNearestTrail;

  /// Answers a typed or spoken question, reusing the same logic the
  /// hike-assistant chat uses (mountain search, organizer lookup, AI
  /// fallback) so the two surfaces never give different answers.
  final Future<KyrielleAnswer> Function(String question) askQuestion;

  @override
  State<KyrielleCompanionChatScreen> createState() =>
      _KyrielleCompanionChatScreenState();
}

/// An answer from [KyrielleCompanionChatScreen.askQuestion], plus the specific
/// mountain it mentioned (if any) so the bubble can show a tappable card for
/// it — mirroring how a real trail buddy would point at a spot on the map
/// rather than just describing it in prose.
class KyrielleAnswer {
  const KyrielleAnswer({required this.text, this.mountain});

  final String text;
  final KyrielleMountainMention? mountain;
}

class KyrielleMountainMention {
  const KyrielleMountainMention({
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  final String name;
  final String subtitle;

  /// Opens the mountain on the app's existing map/details view.
  final VoidCallback onTap;
}

class _KyrielleCompanionChatScreenState extends State<KyrielleCompanionChatScreen>
    with TickerProviderStateMixin {
  static const Color _ink = Color(0xFF2B2117);
  static const Color _rust = Color(0xFFC1440E);
  static const Color _cream = Color(0xFFFAF3E8);

  final TextEditingController _questionController = TextEditingController();
  final FocusNode _questionFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechAvailable = false;

  /// True for the whole physical press-to-release duration — this is
  /// what release checks to decide whether to send, since the speech
  /// engine itself ([_listening]) can stop on its own mid-hold (it has
  /// its own silence/pause detection) well before the hiker lets go.
  bool _holding = false;

  /// True only while the speech engine is actively streaming — drives
  /// the button's visuals and whether [_speech.stop] needs calling, but
  /// never gates whether release sends (see [_holding]).
  bool _listening = false;
  bool _answering = false;
  String? _lastQuestion;
  KyrielleAnswer? _lastAnswer;

  /// Live mic amplitude while [_listening] (roughly 0-10 from the speech
  /// plugin), driving the held-button ring and waveform bars so they react
  /// to actual voice instead of just looping a canned animation.
  double _soundLevel = 0;

  late final AnimationController _idleController;

  /// Drives the push-to-talk button's pulsing ring and waveform bars while
  /// the mic is held down.
  late final AnimationController _micPulseController;

  /// Drives Kyrielle looping around the mascot circle while [_answering] —
  /// the fast-response cue isn't just the text bubble, it's her visibly
  /// taking flight instead of sitting on a static pose during the wait.
  late final AnimationController _flyController;

  /// Which of Kyrielle's emotion illustrations best fits the current moment —
  /// welcoming while idle, thoughtful while answering, pointing when a
  /// specific mountain is being called out, and a rain-cloud caution when
  /// the answer itself reads as a weather warning.
  AgakEmotionState get _currentEmotion {
    if (_lastQuestion == null) return AgakEmotionState.encouragement;
    if (_answering) return AgakEmotionState.pointingSuggestion;
    if (_lastAnswer?.mountain != null) return AgakEmotionState.pointingSuggestion;
    final answer = _lastAnswer?.text.toLowerCase() ?? '';
    const cautionWords = [
      'storm',
      'unsafe',
      'severe',
      'heavy rain',
      'flood',
      'lightning',
      'typhoon',
    ];
    if (cautionWords.any(answer.contains)) return AgakEmotionState.discouraging;
    return AgakEmotionState.encouragement;
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status != 'done' && status != 'notListening') return;
        if (!mounted || !_listening) return;
        setState(() => _listening = false);
        if (_holding && !_answering) {
          // The engine has its own pause/silence detection and can stop
          // itself mid-hold, well before the hiker actually lets go —
          // restart it so one hold can still capture a full sentence
          // with natural pauses, instead of only the first fragment.
          unawaited(_restartListening());
        } else {
          _micPulseController.stop();
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _listening = false);
        if (!_holding) _micPulseController.stop();
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _restartListening() async {
    if (!mounted || !_holding) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _questionController.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(
            offset: result.recognizedWords.length,
          ),
        );
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        setState(() => _soundLevel = level);
      },
    );
  }

  /// Starts capturing on mic press-down — no long-press delay, so recording
  /// begins the instant the button is touched.
  Future<void> _startListening() async {
    if (_holding || _answering) return;
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Voice input isn't available on this device."),
        ),
      );
      return;
    }
    _questionFocusNode.unfocus();
    _questionController.clear();
    setState(() {
      _holding = true;
      _soundLevel = 0;
    });
    _micPulseController.repeat();
    await _restartListening();
  }

  /// Releasing the mic — however briefly — is what sends. This always
  /// submits once a hold was in progress, regardless of whether the
  /// speech engine itself ([_listening]) had already auto-stopped in the
  /// background — otherwise a natural pause right before release would
  /// silently swallow the question (the original bug this guards).
  Future<void> _stopListeningAndSend() async {
    if (!_holding) return;
    _holding = false;
    await _speech.stop();
    _micPulseController.stop();
    if (!mounted) return;
    setState(() => _listening = false);
    _submit();
  }

  void _submit() {
    final question = _questionController.text.trim();
    if (question.isEmpty) return;
    _questionController.clear();
    _ask(question);
  }

  Future<void> _ask(String question) async {
    if (_answering) return;
    setState(() {
      _lastQuestion = question;
      _lastAnswer = null;
      _answering = true;
    });
    _scrollToBottom();
    final answer = await widget.askQuestion(question);
    if (!mounted) return;
    setState(() {
      _lastAnswer = answer;
      _answering = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _questionController.dispose();
    _questionFocusNode.dispose();
    _scrollController.dispose();
    _idleController.dispose();
    _micPulseController.dispose();
    _flyController.dispose();
    super.dispose();
  }

  List<Widget> _buildGreeting() {
    return [
      RichText(
        textAlign: TextAlign.center,
        text: const TextSpan(
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.25,
            color: _ink,
          ),
          children: [
            TextSpan(text: 'Your '),
            TextSpan(text: '✱ AI ', style: TextStyle(color: _rust)),
            TextSpan(text: 'Trail Companion\nfor Every Hike'),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _mascot(AgakEmotionState.encouragement),
      Transform.translate(
        offset: const Offset(0, -14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Hi ${widget.userFirstName}, I'm Kyrielle 👋",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _rust,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Your trail companion — I'll guide the way "
                'and keep you company out there.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: _ink.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 16),
              _quickActionChips(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        "Talk it out or type it in — Kyrielle's listening either way",
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: _ink.withValues(alpha: 0.5)),
      ),
    ];
  }

  List<Widget> _buildAnswerPanel() {
    return [
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_on_rounded,
            size: 15,
            color: _ink.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'You asked — "$_lastQuestion"',
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: _ink.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: _answering
              ? const _ThinkingBubble()
              : AgakSpeechBubble(
                  message: _lastAnswer?.text ?? '',
                  maxLines: 12,
                  fontSize: 14,
                  highlight: _lastAnswer?.mountain?.name,
                  highlightColor: _rust,
                  footer: _lastAnswer?.mountain == null
                      ? null
                      : _MountainMentionCard(mention: _lastAnswer!.mountain!),
                ),
        ),
      ),
      const SizedBox(height: 28),
      _mascot(_currentEmotion, flying: _answering),
      const SizedBox(height: 8),
      _quickActionChips(),
    ];
  }

  Widget _mascot(AgakEmotionState emotion, {bool flying = false}) {
    return SizedBox(
      height: 190,
      child: Center(
        child: Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [_rust.withValues(alpha: 0.18), _rust.withValues(alpha: 0.0)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedBuilder(
              animation: Listenable.merge([_idleController, _flyController]),
              builder: (context, child) {
                final breathe = 1.0 + (_idleController.value * 0.035);
                if (!flying) {
                  return Transform.scale(scale: breathe, child: child);
                }
                // A slow elliptical loop around the badge, with a gentle
                // bank on each turn — reads as circling flight rather
                // than a sprite just sliding side to side.
                final t = _flyController.value * 2 * math.pi;
                final orbit = Offset(34 * math.cos(t), 20 * math.sin(t * 2));
                final bank = math.sin(t) * 0.3;
                return Transform.translate(
                  offset: orbit,
                  child: Transform.rotate(
                    angle: bank,
                    child: Transform.scale(scale: breathe, child: child),
                  ),
                );
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Image.asset(
                  // The in-flight banking pose reads far better mid-orbit
                  // than the standing soar illustration, which was drawn
                  // to be planted on a rock.
                  flying ? 'assets/images/fly.png' : emotion.assetPath,
                  key: ValueKey(flying ? 'flying' : emotion),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _QuickActionChip(label: 'Nearest trail', onTap: widget.onNearestTrail),
        _QuickActionChip(
          label: 'Weather check',
          onTap: () =>
              _ask("What's the weather looking like for hiking today?"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF3E6D3), _cream, Color(0xFFFDF9F2)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: _ink,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                  child: Column(
                    children: _lastQuestion == null
                        ? _buildGreeting()
                        : _buildAnswerPanel(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: _ink.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _questionController,
                                focusNode: _questionFocusNode,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _submit(),
                                style: const TextStyle(color: _ink),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: _holding
                                      ? "Listening..."
                                      : 'Ask about the trail ahead...',
                                  hintStyle: TextStyle(
                                    color: _ink.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _questionFocusNode.requestFocus(),
                              icon: Icon(
                                Icons.keyboard_alt_outlined,
                                color: _ink.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _PushToTalkMicButton(
                      listening: _holding,
                      enabled: !_answering,
                      soundLevel: _soundLevel,
                      pulse: _micPulseController,
                      color: _rust,
                      onHoldStart: _startListening,
                      onHoldEnd: _stopListeningAndSend,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  children: [
                    _FootnoteBullet('Voice guide on trail'),
                    _FootnoteBullet('Type when it\'s quiet'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MountainMentionCard extends StatelessWidget {
  const _MountainMentionCard({required this.mention});

  final KyrielleMountainMention mention;

  static const Color _ink = Color(0xFF2B2117);
  static const Color _rust = Color(0xFFC1440E);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: mention.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: _rust,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mention.name,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mention.subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _ink.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: _ink.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFBEEE2),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFC1440E).withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC1440E),
            ),
          ),
        ),
      ),
    );
  }
}

class _FootnoteBullet extends StatelessWidget {
  const _FootnoteBullet(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(right: 6),
          decoration: const BoxDecoration(
            color: Color(0xFFC1440E),
            shape: BoxShape.circle,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: const Color(0xFF2B2117).withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

/// Hold-to-record mic button. Press-down starts capture immediately (no
/// long-press delay to wait out); releasing — a clean tap-up or the gesture
/// getting cancelled — is what sends, so there's no separate "confirm" step.
/// A pulsing ring plus a floating waveform react to live mic amplitude so
/// the held state reads clearly at a glance.
class _PushToTalkMicButton extends StatelessWidget {
  const _PushToTalkMicButton({
    required this.listening,
    required this.enabled,
    required this.soundLevel,
    required this.pulse,
    required this.color,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool listening;
  final bool enabled;
  final double soundLevel;
  final AnimationController pulse;
  final Color color;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final level = (soundLevel / 10).clamp(0.0, 1.0);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => onHoldStart() : null,
        onTapUp: enabled ? (_) => onHoldEnd() : null,
        onTapCancel: enabled ? onHoldEnd : null,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (listening)
                Positioned(
                  top: -34,
                  child: _MicWaveform(level: level, color: color),
                ),
              if (listening)
                AnimatedBuilder(
                  animation: pulse,
                  builder: (context, child) {
                    final t = pulse.value;
                    final scale = 1.0 + t * 0.7 + level * 0.3;
                    final opacity = (1 - t) * 0.45;
                    return Container(
                      width: 52 * scale,
                      height: 52 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: opacity),
                      ),
                    );
                  },
                ),
              AnimatedScale(
                scale: listening ? 0.92 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: Material(
                  color: color,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      listening ? Icons.mic : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small floating amplitude readout shown above the mic while held — each
/// bar's height eases toward the live [level] so it reads as a real
/// waveform rather than a looping placeholder animation.
class _MicWaveform extends StatelessWidget {
  const _MicWaveform({required this.level, required this.color});

  final double level;
  final Color color;

  static const _barWeights = [0.5, 1.0, 0.7, 0.85, 0.6];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final weight in _barWeights)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 3,
                height: 4 + (level * weight * 22),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The fast-response cue shown the instant a question is submitted —
/// swaps in immediately (before the AI reply arrives) so Kyrielle visibly
/// starts responding right away instead of leaving a static "Thinking…"
/// left sitting on screen.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgakSpeechBubble(
      message: 'Thinking',
      fontSize: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Thinking',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.32,
            ),
          ),
          const SizedBox(width: 5),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = ((_controller.value - i * 0.2) % 1.0 + 1.0) % 1.0;
                  final bounce = t < 0.5 ? t * 2 : (1 - t) * 2;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Transform.translate(
                      offset: Offset(0, -bounce * 4),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}
