import 'package:flutter/material.dart';

/// AGAK's comic-style speech bubble — white (or a warm cream tint for
/// playful asides), black outline, small pointed tail. Shared between the
/// dashboard's floating companion and the full AGAK screen's hero section
/// so both read as the same character talking, just at different scales.
class AgakSpeechBubble extends StatelessWidget {
  const AgakSpeechBubble({
    super.key,
    required this.message,
    this.playful = false,
    this.maxLines = 4,
    this.fontSize = 13.5,
    this.tailAlignment = AgakSpeechBubbleTailAlignment.left,
    this.highlight,
    this.highlightColor = const Color(0xFFC1440E),
    this.footer,
    this.child,
    this.onClose,
  });

  final String message;

  /// When set, replaces the default [message] text entirely (chrome —
  /// border, tail, footer — stays the same). Lets callers like the
  /// "thinking" state show an animated indicator inside the same bubble
  /// shape instead of static text.
  final Widget? child;

  /// True for a brief one-off reaction — tinted slightly so it reads as a
  /// distinct, playful aside rather than AGAK's usual message.
  final bool playful;

  final int maxLines;
  final double fontSize;
  final AgakSpeechBubbleTailAlignment tailAlignment;

  /// When set and found in [message] (case-insensitive), every occurrence
  /// is bolded and tinted with [highlightColor] instead of the default
  /// body color — e.g. calling out a recommended mountain's name inline.
  final String? highlight;
  final Color highlightColor;

  /// Optional content shown below the message, separated by a dashed
  /// divider — e.g. a tappable mountain-mention card. Absent by default so
  /// existing callers are unaffected.
  final Widget? footer;

  /// When set, shows a small dismiss (×) button floating over the
  /// bubble's top-right corner. Absent by default — most callers (e.g.
  /// Kyrielle's chat history) show conversation content, not a
  /// dismissible popup, and shouldn't get a stray close button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final tailLeft = tailAlignment == AgakSpeechBubbleTailAlignment.left;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: playful ? const Color(0xFFFFF4D6) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black87, width: 2.4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child ??
                  Text.rich(
                    TextSpan(
                      children: _highlightedSpans(
                        message,
                        highlight,
                        TextStyle(
                          color: Colors.black87,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.32,
                        ),
                        highlightColor,
                      ),
                    ),
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
              if (footer != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: _DashedDivider(),
                ),
                footer!,
              ],
            ],
          ),
        ),
        Positioned(
          bottom: -10,
          left: tailLeft ? 30 : null,
          right: tailLeft ? null : 30,
          child: SizedBox(
            width: 24,
            height: 13,
            child: CustomPaint(
              painter: _BubbleTailPainter(mirrored: !tailLeft),
            ),
          ),
        ),
        if (onClose != null)
          Positioned(
            top: -8,
            right: -8,
            child: _BubbleCloseButton(onTap: onClose!),
          ),
      ],
    );
  }
}

/// The small circular (×) button shown when [AgakSpeechBubble.onClose] is
/// set — its own tap target so it dismisses the bubble without also
/// triggering whatever the bubble itself is wrapped in (e.g. a parent
/// "tap to open" handler).
class _BubbleCloseButton extends StatelessWidget {
  const _BubbleCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.close_rounded, color: Colors.white, size: 14),
        ),
      ),
    );
  }
}

enum AgakSpeechBubbleTailAlignment { left, right }

/// Splits [message] into spans, bolding and tinting every case-insensitive
/// occurrence of [term] with [color]. Falls back to a single plain span
/// when [term] is absent or not found.
List<TextSpan> _highlightedSpans(
  String message,
  String? term,
  TextStyle baseStyle,
  Color color,
) {
  if (term == null || term.isEmpty) {
    return [TextSpan(text: message, style: baseStyle)];
  }
  final lowerMessage = message.toLowerCase();
  final lowerTerm = term.toLowerCase();
  final spans = <TextSpan>[];
  var start = 0;
  var index = lowerMessage.indexOf(lowerTerm, start);
  if (index == -1) {
    return [TextSpan(text: message, style: baseStyle)];
  }
  while (index != -1) {
    if (index > start) {
      spans.add(TextSpan(text: message.substring(start, index), style: baseStyle));
    }
    spans.add(
      TextSpan(
        text: message.substring(index, index + term.length),
        style: baseStyle.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
    start = index + term.length;
    index = lowerMessage.indexOf(lowerTerm, start);
  }
  if (start < message.length) {
    spans.add(TextSpan(text: message.substring(start), style: baseStyle));
  }
  return spans;
}

/// A thin dashed rule separating a bubble's message from its [footer].
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        const dashSpace = 4.0;
        final count = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            children: List.generate(
              count < 0 ? 0 : count,
              (_) => Container(
                width: dashWidth,
                height: 1,
                margin: const EdgeInsets.only(right: dashSpace),
                color: Colors.black26,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A small triangular tail pointing down toward AGAK's head. Only the two
/// outer slanted edges are stroked — the top edge is deliberately left
/// unstroked since it sits flush against the bubble's own bottom border,
/// avoiding a doubled-up seam line.
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.mirrored});

  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final tipX = mirrored ? size.width * 0.82 : size.width * 0.18;
    final farX = mirrored ? size.width : 0.0;
    final nearX = mirrored ? size.width * 0.45 : size.width * 0.55;

    final body = Path()
      ..moveTo(farX, 0)
      ..lineTo(nearX, 0)
      ..lineTo(tipX, size.height)
      ..close();
    canvas.drawPath(body, fill);

    final edges = Path()
      ..moveTo(farX, 0)
      ..lineTo(tipX, size.height)
      ..moveTo(nearX, 0)
      ..lineTo(tipX, size.height);
    canvas.drawPath(edges, stroke);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.mirrored != mirrored;
}
