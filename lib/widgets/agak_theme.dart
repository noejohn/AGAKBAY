import 'package:flutter/material.dart';

/// Shared visual language for Kyrielle's companion surfaces — the home
/// card, the full companion screen, the emotion showcase, and the
/// scheduled-hikes list. One place for the app's cream/gold/olive/maroon
/// palette so these four screens read as one feature instead of four
/// independently eyeballed ones.
///
/// Text/icon colors are NOT re-exported here on purpose (see [AgakText]) —
/// but since this palette flipped from dark to light, every caller that
/// still hardcodes `Colors.white` for text on these surfaces needs to move
/// to [ink] instead, or it'll be invisible against the new background.
class AgakColors {
  AgakColors._();

  /// Warm off-white — the palette's background tone.
  static const Color cream = Color(0xFFFDF8DC);

  /// Golden-yellow — secondary/highlight tone. Backgrounds/fills only —
  /// too pale for reliable text/icon contrast, use [goldDark] for those.
  static const Color gold = Color(0xFFF6DA78);

  /// Deeper amber — same gold family, dark enough to use as text, icons,
  /// or an outline border on a light surface.
  static const Color goldDark = Color(0xFFAD7A0C);

  /// Olive green — primary accent (borders, "good"/active signals).
  static const Color olive = Color(0xFF8FBF5A);

  /// Deep maroon-red — strongest accent, CTAs and alerts.
  static const Color maroon = Color(0xFF97070A);

  /// Dark warm-brown ink — body text/icons on any surface in this
  /// palette (matches the tone already used on Kyrielle's chat screen).
  static const Color ink = Color(0xFF2B2117);

  /// Base card/container fill.
  static const Color surface = Colors.white;

  /// Slightly tinted fill for nested containers (chips, inset panels).
  static const Color surfaceRaised = Color(0xFFFBEFC7);

  /// Screen background gradient stops (top → bottom).
  static const Color backgroundTop = cream;
  static const Color backgroundMid = Color(0xFFFCF0C4);
  static const Color backgroundBottom = gold;

  /// Signature border/icon color.
  static const Color border = olive;

  /// Primary bright accent — CTAs, active state, "good" signals.
  static const Color accent = maroon;

  /// Softer accent for secondary text/labels.
  static const Color accentSoft = olive;

  static LinearGradient get screenBackground => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, backgroundMid, backgroundBottom],
  );
}

/// Typographic scale for AGAK surfaces. All sizes/weights funnel through
/// here so "make the card title bigger" is a one-line change, not a
/// four-file grep. Colors are intentionally excluded — callers set color
/// per-context (e.g. a title on a pastel card needs dark text, the same
/// title on a dark card needs white).
class AgakText {
  AgakText._();

  static const TextStyle screenTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.1,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle body = TextStyle(fontSize: 13.5, height: 1.45);

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
}
