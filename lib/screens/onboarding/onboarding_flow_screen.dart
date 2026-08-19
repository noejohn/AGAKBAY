import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../main.dart';
import '../../models/agak_mountain.dart';
import '../../models/agak_recommendation.dart';
import '../../services/agak_behavior_database.dart';
import '../../services/onboarding_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/agak_speech_bubble.dart';
import '../../widgets/agak_theme.dart';

/// First-run flow: Welcome -> Name -> Skill level -> Weather preference ->
/// Confirmation. Kyrielle (AGAK) narrates each step, and the confirmation
/// screen turns the two answers into a short mountain shortlist before the
/// user ever sees the dashboard.
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  static const int _stepWelcome = 0;
  static const int _stepName = 1;
  static const int _stepSkill = 2;
  static const int _stepWeather = 3;
  static const int _stepConfirmation = 4;

  final OnboardingService _onboardingService = OnboardingService();
  final WeatherService _weatherService = WeatherService();
  final TextEditingController _nameController = TextEditingController();

  int _step = _stepWelcome;
  String? _skillLevel;
  final Set<String> _weatherPreferences = {};

  bool _loadingRecommendations = false;
  List<MountainCatalogEntry> _recommendations = const [];
  AgakWeatherSnapshot? _liveWeather;
  bool _saving = false;

  String get _firstName => _nameController.text.trim();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_step == _stepWeather) {
      unawaited(_loadRecommendations());
    }
    setState(() => _step += 1);
  }

  void _goBack() {
    if (_step > _stepWelcome && _step < _stepConfirmation) {
      setState(() => _step -= 1);
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loadingRecommendations = true);
    try {
      final results = await Future.wait([
        AgakBehaviorDatabase.instance.getCatalog(),
        _fetchLiveWeather(),
      ]);
      final catalog = results[0] as List<MountainCatalogEntry>;
      final liveWeather = results[1] as AgakWeatherSnapshot?;
      final recommendations = _onboardingService.recommendMountains(
        skillLevel: _skillLevel ?? 'Beginner',
        weatherPreferences: _weatherPreferences.toList(),
        catalog: catalog,
        liveWeather: liveWeather,
      );
      if (!mounted) return;
      setState(() {
        _recommendations = recommendations;
        _liveWeather = liveWeather;
        _loadingRecommendations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecommendations = false);
    }
  }

  /// Best-effort: missing permission, no signal, or a function-call
  /// failure all just mean "recommend on stated preference alone" rather
  /// than failing onboarding — the live weather is a bonus signal, never
  /// a requirement.
  Future<AgakWeatherSnapshot?> _fetchLiveWeather() async {
    try {
      final position = await _weatherService.currentPosition();
      if (position == null) return null;
      return await _weatherService.fetchCurrentSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _finishOnboarding() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await _onboardingService.saveOnboardingAnswers(
        uid: uid,
        firstName: _firstName,
        skillLevel: _skillLevel ?? 'Beginner',
        weatherPreferences: _weatherPreferences.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (context) => const DashboardScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your answers: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _stepWelcome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step > _stepWelcome && _step < _stepConfirmation) {
          _goBack();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: AgakColors.screenBackground),
          child: SafeArea(
            child: Column(
              children: [
                if (_step >= _stepName)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        if (_step > _stepName && _step < _stepConfirmation)
                          IconButton(
                            onPressed: _goBack,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: AgakColors.ink,
                            ),
                          )
                        else
                          const SizedBox(width: 48),
                        Expanded(
                          child: _OnboardingProgress(
                            filledSegments: _step.clamp(1, 4),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _stepName:
        return _NameStep(controller: _nameController, onContinue: _goNext);
      case _stepSkill:
        return _SkillStep(
          firstName: _firstName,
          selected: _skillLevel,
          onSelect: (value) => setState(() => _skillLevel = value),
          onContinue: _goNext,
        );
      case _stepWeather:
        return _WeatherStep(
          firstName: _firstName,
          selected: _weatherPreferences,
          onToggle: (value) => setState(() {
            if (!_weatherPreferences.remove(value)) {
              _weatherPreferences.add(value);
            }
          }),
          onContinue: _goNext,
        );
      case _stepConfirmation:
        return _ConfirmationStep(
          firstName: _firstName,
          skillLevel: _skillLevel ?? 'Beginner',
          weatherPreferences: _weatherPreferences.toList(),
          loadingRecommendations: _loadingRecommendations,
          recommendations: _recommendations,
          liveWeather: _liveWeather,
          saving: _saving,
          onStartExploring: _finishOnboarding,
        );
      case _stepWelcome:
      default:
        return _WelcomeStep(onGetStarted: _goNext);
    }
  }
}

class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress({required this.filledSegments});

  final int filledSegments;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (index) {
        final filled = index < filledSegments;
        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
            decoration: BoxDecoration(
              color: filled
                  ? AgakColors.maroon
                  : AgakColors.ink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AgakColors.maroon,
          foregroundColor: AgakColors.cream,
          disabledBackgroundColor: AgakColors.maroon.withValues(alpha: 0.35),
          disabledForegroundColor: AgakColors.cream.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AgakColors.cream,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _KyrielleImage extends StatelessWidget {
  const _KyrielleImage({required this.emotion, this.size = 150});

  final AgakEmotionState emotion;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(emotion.assetPath, width: size, height: size);
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          const Spacer(),
          const _KyrielleImage(
            emotion: AgakEmotionState.encouragement,
            size: 190,
          ),
          const SizedBox(height: 18),
          const AgakSpeechBubble(
            message:
                "Hi, I'm Kyrielle! I'll get you set up — it takes less "
                'than a minute.',
          ),
          const SizedBox(height: 28),
          const Text(
            "Let's get you trail-ready",
            textAlign: TextAlign.center,
            style: AgakText.screenTitle,
          ),
          const SizedBox(height: 8),
          const Text(
            'A few quick questions before your first hike.',
            textAlign: TextAlign.center,
            style: AgakText.body,
          ),
          const Spacer(),
          _PrimaryButton(label: 'Get started', onPressed: onGetStarted),
        ],
      ),
    );
  }
}

class _NameStep extends StatefulWidget {
  const _NameStep({required this.controller, required this.onContinue});

  final TextEditingController controller;
  final VoidCallback onContinue;

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canContinue = widget.controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KyrielleImage(
            emotion: AgakEmotionState.encouragement,
            size: 120,
          ),
          const SizedBox(height: 14),
          const AgakSpeechBubble(message: 'What should I call you?'),
          const SizedBox(height: 28),
          TextField(
            controller: widget.controller,
            textCapitalization: TextCapitalization.words,
            autofocus: true,
            style: const TextStyle(color: AgakColors.ink, fontSize: 18),
            cursorColor: AgakColors.olive,
            decoration: InputDecoration(
              hintText: 'First name',
              hintStyle: TextStyle(color: AgakColors.ink.withValues(alpha: 0.45)),
              prefixIcon: const Icon(
                Icons.person_outline_rounded,
                color: AgakColors.olive,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.55),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: AgakColors.ink.withValues(alpha: 0.18),
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: AgakColors.olive),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "We'll use this on your profile and trail log.",
            style: AgakText.caption,
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Continue',
            onPressed: canContinue ? widget.onContinue : null,
          ),
        ],
      ),
    );
  }
}

class _SkillStep extends StatelessWidget {
  const _SkillStep({
    required this.firstName,
    required this.selected,
    required this.onSelect,
    required this.onContinue,
  });

  final String firstName;
  final String? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onContinue;

  static const _levels = [
    (
      'Beginner',
      'New to trails, or hikes a few times a year.',
      Icons.hiking_rounded,
    ),
    (
      'Intermediate',
      'Comfortable with steep trails and full-day hikes.',
      Icons.terrain_rounded,
    ),
    (
      'Advanced',
      'Ready for multi-day, technical climbs.',
      Icons.landscape_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final greeting = firstName.isEmpty
        ? "What's your hiking skill level?"
        : "Nice to meet you, $firstName! What's your hiking skill level?";
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KyrielleImage(
            emotion: AgakEmotionState.encouragement,
            size: 110,
          ),
          const SizedBox(height: 14),
          AgakSpeechBubble(message: greeting, highlight: firstName),
          const SizedBox(height: 24),
          for (final level in _levels) ...[
            _SelectableCard(
              title: level.$1,
              description: level.$2,
              icon: level.$3,
              selected: selected == level.$1,
              onTap: () => onSelect(level.$1),
            ),
            const SizedBox(height: 12),
          ],
          const Spacer(),
          _PrimaryButton(
            label: 'Continue',
            onPressed: selected != null ? onContinue : null,
          ),
        ],
      ),
    );
  }
}

class _WeatherStep extends StatelessWidget {
  const _WeatherStep({
    required this.firstName,
    required this.selected,
    required this.onToggle,
    required this.onContinue,
  });

  final String firstName;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onContinue;

  static const _options = [
    ('Sunny', Icons.wb_sunny_rounded),
    ('Overcast', Icons.cloud_rounded),
    ('Rain', Icons.umbrella_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final emotion = selected.contains('Sunny')
        ? AgakEmotionState.sunny
        : selected.contains('Rain')
        ? AgakEmotionState.discouraging
        : AgakEmotionState.encouragement;
    final question = firstName.isEmpty
        ? 'What conditions do you usually hike in?'
        : 'What conditions do you usually hike in, $firstName?';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KyrielleImage(emotion: emotion, size: 110),
          const SizedBox(height: 14),
          AgakSpeechBubble(message: question),
          const SizedBox(height: 8),
          const Text('Pick as many as apply.', style: AgakText.caption),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              for (final option in _options)
                _SelectableCard(
                  title: option.$1,
                  icon: option.$2,
                  selected: selected.contains(option.$1),
                  onTap: () => onToggle(option.$1),
                  compact: true,
                ),
            ],
          ),
          const Spacer(),
          _PrimaryButton(
            label: 'Continue',
            onPressed: selected.isNotEmpty ? onContinue : null,
          ),
        ],
      ),
    );
  }
}

class _ConfirmationStep extends StatelessWidget {
  const _ConfirmationStep({
    required this.firstName,
    required this.skillLevel,
    required this.weatherPreferences,
    required this.loadingRecommendations,
    required this.recommendations,
    required this.liveWeather,
    required this.saving,
    required this.onStartExploring,
  });

  final String firstName;
  final String skillLevel;
  final List<String> weatherPreferences;
  final bool loadingRecommendations;
  final List<MountainCatalogEntry> recommendations;
  final AgakWeatherSnapshot? liveWeather;
  final bool saving;
  final VoidCallback onStartExploring;

  @override
  Widget build(BuildContext context) {
    final weatherList = weatherPreferences.join(', ').toLowerCase();
    final name = firstName.isEmpty ? 'there' : firstName;
    final summary =
        'Got it, $name — a ${skillLevel.toLowerCase()} hiker who loves '
        '$weatherList days. Here\'s where I\'d start:';
    final weather = liveWeather;
    final liveWeatherLine = weather == null
        ? null
        : weather.isSevere || weather.isCaution
        ? "By the way, it's ${weather.headline.toLowerCase()} near you right "
              'now, so I leaned toward trails that hold up well in the rain.'
        : "It's ${weather.headline.toLowerCase()} near you right now — good "
              'timing for a hike.';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _KyrielleImage(
            emotion: AgakEmotionState.celebration,
            size: 150,
          ),
          const SizedBox(height: 14),
          AgakSpeechBubble(message: summary, highlight: name),
          if (liveWeatherLine != null) ...[
            const SizedBox(height: 10),
            AgakSpeechBubble(
              message: liveWeatherLine,
              playful: true,
              tailAlignment: AgakSpeechBubbleTailAlignment.right,
            ),
          ],
          const SizedBox(height: 20),
          if (loadingRecommendations)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AgakColors.olive),
              ),
            )
          else
            for (final mountain in recommendations) ...[
              _MountainSummaryCard(mountain: mountain),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 18),
          _PrimaryButton(
            label: 'Start exploring',
            loading: saving,
            onPressed: onStartExploring,
          ),
        ],
      ),
    );
  }
}

class _MountainSummaryCard extends StatelessWidget {
  const _MountainSummaryCard({required this.mountain});

  final MountainCatalogEntry mountain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgakColors.border.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.landscape_rounded,
            color: AgakColors.goldDark,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mountain.name, style: AgakText.cardTitle),
                const SizedBox(height: 2),
                Text(
                  '${mountain.difficulty} · ${mountain.elevationMasl}m · ${mountain.region}',
                  style: AgakText.body.copyWith(
                    color: AgakColors.ink.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.description,
    this.compact = false,
  });

  final String title;
  final String? description;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(compact ? 14 : 16),
        decoration: BoxDecoration(
          color: selected
              ? AgakColors.olive.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AgakColors.olive
                : AgakColors.ink.withValues(alpha: 0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: compact
            ? Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? AgakColors.olive : AgakColors.goldDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: AgakText.cardTitle),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AgakColors.olive,
                      size: 18,
                    ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    color: selected ? AgakColors.olive : AgakColors.goldDark,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AgakText.cardTitle),
                        if (description != null) ...[
                          const SizedBox(height: 3),
                          Text(description!, style: AgakText.body),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AgakColors.olive,
                    ),
                ],
              ),
      ),
    );
  }
}
