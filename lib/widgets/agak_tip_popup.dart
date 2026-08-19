import 'dart:async';

import 'package:flutter/material.dart';

import '../models/agak_recommendation.dart';
import '../services/agak_tip_bus.dart';
import 'agak_speech_bubble.dart';
import 'agak_theme.dart';

/// Kyrielle's live-hike presence — her artwork stays docked on the Hiking
/// Mode map for the whole hike (not just a transient pop-up), so she reads
/// as a companion who's there with you, not a notification widget. A
/// speech bubble appears above her whenever [AgakTipBus] pushes something
/// (checkpoint reached, wrong-turn warning, "almost at the next station"
/// encouragement, still-not-moving check-in, weather), stays up for 10
/// seconds (or until answered, for interactive tips), then fades on its
/// own — she just goes back to her idle pose, she never leaves. There's no
/// manual close button: tap Kyrielle herself to bring the bubble back if
/// it already faded and you want to re-read what she said.
///
/// Every one of those triggers is computed locally from GPS/timers already
/// on-device, so this keeps working with no network connection; only the
/// mid-hike weather re-check needs connectivity, and that one already
/// no-ops itself when offline.
///
/// Purely reactive: it displays whatever [AgakTipBus] pushes. It does NOT
/// poll or loop on its own — that was showing the same stale message over
/// and over whenever nothing had actually changed.
///
/// Deliberately does NOT replay [AgakTipBus.pending] on mount (unlike a
/// dashboard-style tip surface might) — this widget is only ever embedded
/// in Hiking Mode, a screen entered fresh for every hike. Replaying
/// whatever was last pushed *anywhere* in the app would surface stale,
/// wrong content — e.g. a "First summit completed!" milestone left over
/// from a previous, unrelated hike, reappearing at the start of a brand
/// new one that hasn't been completed yet. Only tips pushed while this
/// screen is actually open (this hike's checkpoints, weather, and — once
/// it actually finishes — its own completion milestone) should show here.
class AgakTipPopup extends StatefulWidget {
  const AgakTipPopup({super.key, this.onTap, this.onDragDelta});

  /// Defaults to nothing — the popup is tap-through when there's no handler.
  final VoidCallback? onTap;

  /// Fired with the raw pointer movement while being dragged — same
  /// contract as [AgakFloatingCompanion.onDragDelta]: the parent owns the
  /// actual on-screen position (via `Positioned`), this widget only ever
  /// reports deltas. Null means not draggable.
  final ValueChanged<Offset>? onDragDelta;

  @override
  State<AgakTipPopup> createState() => _AgakTipPopupState();
}

class _AgakTipPopupState extends State<AgakTipPopup> {
  static const _visibleDuration = Duration(seconds: 10);

  Timer? _hideTimer;
  bool _visible = false;
  AgakTip? _shownTip;
  late int _lastHandledVersion;

  @override
  void initState() {
    super.initState();
    // Sync to the bus's current version WITHOUT displaying its current
    // pending tip (see class doc) — only a tip pushed after this point
    // will trigger `_onBusChanged` to actually show something.
    _lastHandledVersion = AgakTipBus.instance.version;
    debugPrint(
      'DEBUG AgakTipPopup: mounted, syncing to bus version '
      '$_lastHandledVersion',
    );
    AgakTipBus.instance.addListener(_onBusChanged);
  }

  @override
  void dispose() {
    AgakTipBus.instance.removeListener(_onBusChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onBusChanged() {
    final bus = AgakTipBus.instance;
    debugPrint(
      'DEBUG AgakTipPopup: _onBusChanged fired, busVersion=${bus.version}, '
      'lastHandled=$_lastHandledVersion, mounted=$mounted, '
      'pendingIsNull=${bus.pending == null}',
    );
    if (bus.version == _lastHandledVersion) return;
    _lastHandledVersion = bus.version;
    final tip = bus.pending;
    if (tip == null || !mounted) return;

    _hideTimer?.cancel();
    setState(() {
      _shownTip = tip;
      _visible = true;
    });
    // Interactive tips (choices present) stay open until answered or
    // manually dismissed — auto-hiding a question the user hasn't
    // responded to yet would be worse than not asking at all.
    if (tip.choices == null) {
      _hideTimer = Timer(_visibleDuration, _hide);
    }
  }

  void _hide() {
    if (!mounted) return;
    setState(() => _visible = false);
  }

  /// Tapping Kyrielle brings back whatever she last said, even if the
  /// bubble already faded out — a "what did you say?" gesture rather than
  /// a way to dismiss her. No-op before she's said anything yet this hike.
  void _revealLastTip() {
    final tip = _shownTip;
    if (tip == null) return;
    _hideTimer?.cancel();
    setState(() => _visible = true);
    if (tip.choices == null) {
      _hideTimer = Timer(_visibleDuration, _hide);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tip = _shownTip;
    final speaking = _visible && tip != null;
    return GestureDetector(
      onPanUpdate: widget.onDragDelta == null
          ? null
          : (details) => widget.onDragDelta!(details.delta),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            ignoring: !speaking,
            child: AnimatedSlide(
              offset: speaking ? Offset.zero : const Offset(0, 0.15),
              duration: const Duration(milliseconds: 320),
              curve: speaking ? Curves.easeOutBack : Curves.easeIn,
              child: AnimatedOpacity(
                opacity: speaking ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: tip == null
                    ? const SizedBox.shrink()
                    : _TipBubble(tip: tip, onTap: widget.onTap),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Kyrielle herself — always here for the whole hike, not just
          // while she has something to say. Wears whichever mood her
          // latest tip called for while the bubble above is showing,
          // otherwise her default "keeping you company" pose. Sized to
          // match her dashboard presence rather than reading as a small
          // corner icon, draggable so she never permanently blocks the map
          // underneath, and tappable to bring her last message back.
          GestureDetector(
            onTap: _revealLastTip,
            child: SizedBox(
              width: 200,
              height: 200,
              child: Image.asset(
                speaking
                    ? tip.emotion.assetPath
                    : AgakEmotionState.pointingSuggestion.assetPath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same "just the character" treatment as [AgakFloatingCompanion] on the
/// dashboard — a comic speech bubble (with its tail, no card chrome or
/// name-tag header), rather than a separate notification-card look. Reads
/// as one consistent character across screens instead of two
/// differently-styled surfaces.
class _TipBubble extends StatelessWidget {
  const _TipBubble({required this.tip, this.onTap});

  final AgakTip tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AgakSpeechBubble(
          message: tip.message,
          maxLines: 4,
          fontSize: 13,
          footer: tip.choices == null
              ? null
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tip.choices!
                      .map(
                        (choice) => OutlinedButton(
                          onPressed: choice.onSelected,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AgakColors.maroon,
                            side: const BorderSide(color: AgakColors.maroon),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            choice.label,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ),
    );
  }
}
