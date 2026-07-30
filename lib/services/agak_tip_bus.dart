import 'package:flutter/foundation.dart';

import '../models/agak_recommendation.dart';

/// One button on an interactive tip — e.g. "I'm okay!" on the stillness
/// check-in. [onSelected] is expected to push a follow-up [AgakTip] (AGAK's
/// reply) back onto the bus; the popup itself doesn't know or care what
/// happens when a choice is tapped, it just calls this.
class AgakTipChoice {
  final String label;
  final VoidCallback onSelected;

  const AgakTipChoice({required this.label, required this.onSelected});
}

/// One thing AGAK wants to briefly say — an emotion to show alongside a
/// short message. Distinct from `AgakCompanionMoment`: a moment is "what is
/// AGAK's whole state right now" (used by the full AGAK screen), a tip is
/// "one specific thing worth popping up about, right now."
///
/// Most tips are passive (show briefly, auto-dismiss). When [choices] is
/// set, the tip is interactive instead — the pop-up stays open (no
/// auto-dismiss timer) until one of the buttons is tapped or the user
/// closes it manually.
class AgakTip {
  final AgakEmotionState emotion;
  final String message;
  final List<AgakTipChoice>? choices;

  const AgakTip({required this.emotion, required this.message, this.choices});
}

/// Event-driven queue for the home-screen tip pop-up. Real triggers (a
/// weather check resolving, viewing a mountain's details, a reminder
/// becoming due) push a tip here; the pop-up widget just displays whatever
/// arrives, once, then waits for the next push.
///
/// Deliberately NOT a timer/poll loop — that repeats stale content when
/// nothing has actually changed, which reads as AGAK "getting stuck."
/// Showing up only when there's something real to say is the whole point.
class AgakTipBus extends ChangeNotifier {
  AgakTipBus._();

  static final AgakTipBus instance = AgakTipBus._();

  AgakTip? _pending;
  int _version = 0;

  AgakTip? get pending => _pending;

  /// Increments on every push so the popup can tell a brand-new push
  /// apart from a rebuild, even if the new tip has identical content.
  int get version => _version;

  void push(AgakTip tip) {
    _pending = tip;
    _version++;
    notifyListeners();
  }
}
