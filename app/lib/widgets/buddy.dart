import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum Mood { happy, calm }

/// The Mapa mascot: a round handset buddy with a coiled cord on top.
/// Drawn in code so it scales crisply and takes the person's phone colour.
class Buddy extends StatefulWidget {
  const Buddy({
    super.key,
    required this.color,
    this.size = 140,
    this.mood = Mood.happy,
    this.wobble = false,
  });

  final Color color;
  final double size;
  final Mood mood;
  final bool wobble;

  @override
  State<Buddy> createState() => _BuddyState();
}

class _BuddyState extends State<Buddy> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (widget.wobble && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = .5;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _BuddyPainter(
          widget.color,
          widget.mood,
          // Cord and ear cups are plum; on the night ground they need to be lighter.
          context.c.isDark ? const Color(0xFF9A93C0) : const Color(0xFF2D2A3E),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -6 * math.sin(t * math.pi) * (widget.wobble ? 1 : 0)),
          child: Transform.rotate(
            angle: widget.wobble ? (t - .5) * 2 * .12 : 0,
            child: child,
          ),
        );
      },
      child: paint,
    );
  }
}

class _BuddyPainter extends CustomPainter {
  _BuddyPainter(this.color, this.mood, this.trim);
  final Color color, trim;
  final Mood mood;
  static const _plum = Color(0xFF2D2A3E);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 140;
    canvas.scale(s);

    final line = Paint()
      ..color = _plum
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = _plum;
    final trimLine = Paint()
      ..color = trim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final trimFill = Paint()..color = trim;

    // cord on top
    canvas.drawPath(
        Path()
          ..moveTo(62, 18)
          ..cubicTo(52, 16, 48, 6, 56, 2)
          ..cubicTo(63, -2, 71, 4, 67, 11)
          ..cubicTo(75, 8, 84, 12, 82, 20)
          ..cubicTo(80, 26, 72, 26, 68, 21),
        trimLine);

    // ear cups (handset)
    canvas.drawRRect(RRect.fromLTRBR(6, 52, 26, 98, const Radius.circular(10)), trimFill);
    canvas.drawRRect(RRect.fromLTRBR(114, 52, 134, 98, const Radius.circular(10)), trimFill);

    // body
    canvas.drawPath(
        Path()
          ..moveTo(70, 24)
          ..cubicTo(104, 24, 122, 46, 122, 74)
          ..cubicTo(122, 104, 102, 124, 70, 124)
          ..cubicTo(38, 124, 18, 104, 18, 74)
          ..cubicTo(18, 46, 36, 24, 70, 24)
          ..close(),
        Paint()..color = color);

    // cheeks
    final cheek = Paint()..color = const Color(0x8CFF8FA8);
    canvas.drawOval(Rect.fromCenter(center: const Offset(36, 92), width: 16, height: 11), cheek);
    canvas.drawOval(Rect.fromCenter(center: const Offset(104, 92), width: 16, height: 11), cheek);

    if (mood == Mood.happy) {
      canvas.drawOval(Rect.fromCenter(center: const Offset(50, 72), width: 15, height: 20), fill);
      canvas.drawOval(Rect.fromCenter(center: const Offset(90, 72), width: 15, height: 20), fill);
      final w = Paint()..color = Colors.white;
      canvas.drawCircle(const Offset(53, 68), 2.8, w);
      canvas.drawCircle(const Offset(93, 68), 2.8, w);
      canvas.drawPath(
          Path()
            ..moveTo(58, 90)
            ..cubicTo(62, 99, 78, 99, 82, 90),
          line);
    } else {
      canvas.drawPath(
          Path()
            ..moveTo(40, 74)
            ..cubicTo(44, 80, 54, 80, 58, 74)
            ..moveTo(82, 74)
            ..cubicTo(86, 80, 96, 80, 100, 74),
          line);
      canvas.drawPath(
          Path()
            ..moveTo(62, 94)
            ..cubicTo(67, 98, 73, 98, 78, 94),
          line);
    }
  }

  @override
  bool shouldRepaint(_BuddyPainter old) => old.color != color || old.mood != mood || old.trim != trim;
}
