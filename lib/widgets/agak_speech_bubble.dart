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
  });

  final String message;

  /// True for a brief one-off reaction — tinted slightly so it reads as a
  /// distinct, playful aside rather than AGAK's usual message.
  final bool playful;

  final int maxLines;
  final double fontSize;
  final AgakSpeechBubbleTailAlignment tailAlignment;

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
          child: Text(
            message,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.black87,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.32,
            ),
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
      ],
    );
  }
}

enum AgakSpeechBubbleTailAlignment { left, right }

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
