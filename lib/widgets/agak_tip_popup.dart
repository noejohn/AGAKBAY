import 'dart:async';

import 'package:flutter/material.dart';

import '../models/agak_recommendation.dart';
import '../services/agak_tip_bus.dart';
import 'agak_theme.dart';

/// AGAK's home-screen presence, reimagined as a transient pop-up instead of
/// a permanently-docked card — the docked version was eating a fixed chunk
/// of map real estate on every render.
///
/// Purely reactive: it displays whatever [AgakTipBus] pushes, for 10
/// seconds, then gets out of the way. It does NOT poll or loop on its own
/// — that was showing the same stale message over and over whenever
/// nothing had actually changed. Real triggers (a weather check resolving
/// after app open, opening a mountain's details, a reminder becoming due)
/// are what make it show up, so what it says stays meaningful.
class AgakTipPopup extends StatefulWidget {
  const AgakTipPopup({super.key, this.onTap});

  /// Defaults to nothing — the popup is tap-through when there's no handler.
  final VoidCallback? onTap;

  @override
  State<AgakTipPopup> createState() => _AgakTipPopupState();
}

class _AgakTipPopupState extends State<AgakTipPopup> {
  static const _visibleDuration = Duration(seconds: 10);

  Timer? _hideTimer;
  bool _visible = false;
  AgakTip? _shownTip;
  int _lastHandledVersion = -1;

  @override
  void initState() {
    super.initState();
    AgakTipBus.instance.addListener(_onBusChanged);
    // Pick up anything pushed before this widget was mounted (e.g. a
    // weather check that resolved while the Explore tab wasn't active).
    _onBusChanged();
  }

  @override
  void dispose() {
    AgakTipBus.instance.removeListener(_onBusChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onBusChanged() {
    final bus = AgakTipBus.instance;
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

  /// User-triggered close — same end state as the auto-hide timeout, just
  /// immediate instead of waiting out the remaining visible duration.
  void _dismissNow() {
    _hideTimer?.cancel();
    _hide();
  }

  @override
  Widget build(BuildContext context) {
    final tip = _shownTip;
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, -1.3),
        duration: const Duration(milliseconds: 320),
        curve: _visible ? Curves.easeOutBack : Curves.easeIn,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: tip == null
              ? const SizedBox.shrink()
              : _PopupCard(tip: tip, onTap: widget.onTap, onClose: _dismissNow),
        ),
      ),
    );
  }
}

class _PopupCard extends StatelessWidget {
  const _PopupCard({required this.tip, required this.onClose, this.onTap});

  final AgakTip tip;
  final VoidCallback? onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          decoration: BoxDecoration(
            color: AgakColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AgakColors.border.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: Image.asset(
                    tip.emotion.assetPath,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(
                          color: AgakColors.surfaceRaised,
                          child: Icon(
                            Icons.flutter_dash,
                            color: AgakColors.accentSoft,
                          ),
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AGAK',
                      style: TextStyle(
                        color: AgakColors.accentSoft,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tip.message,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AgakText.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    if (tip.choices != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tip.choices!
                            .map(
                              (choice) => OutlinedButton(
                                onPressed: choice.onSelected,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AgakColors.accentSoft,
                                  side: const BorderSide(
                                    color: AgakColors.accentSoft,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
