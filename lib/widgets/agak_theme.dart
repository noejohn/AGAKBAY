import 'package:flutter/material.dart';

/// Shared visual language for AGAK's companion surfaces — the home card,
/// the full AGAK screen, the emotion showcase, and the scheduled-hikes
/// list. One place for the dark, nature-green palette (reusing the same
/// hex values already established in main.dart — `0xFF53D97A` as the
/// primary accent, `0xFF2F8C5A` as the AGAK border/icon green, etc.) so
/// these four screens read as one feature instead of four independently
/// eyeballed ones.
class AgakColors {
  AgakColors._();

  /// Base card/container fill.
  static const Color surface = Color(0xFF0B241A);

  /// Slightly lighter fill for nested containers (chips, inset panels).
  static const Color surfaceRaised = Color(0xFF12231A);

  /// Screen background gradient stops (top → bottom).
  static const Color backgroundTop = Color(0xFF15432D);
  static const Color backgroundMid = Color(0xFF082A1C);
  static const Color backgroundBottom = Color(0xFF020D09);

  /// AGAK's signature border/icon green.
  static const Color border = Color(0xFF2F8C5A);

  /// Primary bright accent — CTAs, active state, "good" signals.
  static const Color accent = Color(0xFF53D97A);

  /// Softer accent for secondary text/labels on dark surfaces.
  static const Color accentSoft = Color(0xFF7FE0A9);

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
