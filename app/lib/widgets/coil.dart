import 'package:flutter/material.dart';

/// A vertical phone cord, used on the Next Call card.
class VCoil extends StatelessWidget {
  const VCoil({super.key, required this.color, this.width = 34, this.height = 82});
  final Color color;
  final double width, height;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: _VCoilPainter(color),
      );
}

class _VCoilPainter extends CustomPainter {
  _VCoilPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 34, size.height / 82);
    canvas.drawPath(
      Path()
        ..moveTo(17, 2)
        ..cubicTo(31, 7, 31, 13, 17, 16)
        ..cubicTo(3, 19, 3, 24, 17, 28)
        ..cubicTo(31, 32, 31, 39, 17, 42)
        ..cubicTo(3, 45, 3, 51, 17, 55)
        ..cubicTo(26, 58, 28, 63, 28, 69),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_VCoilPainter old) => old.color != color;
}

/// A horizontal cord that stretches: loops get wider and flatter as [stretch]
/// grows from 0 (relaxed) to 1 (taut). Used by slide-to-answer.
class HCoil extends StatelessWidget {
  const HCoil({super.key, required this.color, required this.stretch, this.height = 56});
  final Color color;
  final double stretch;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.fromHeight(height),
        painter: _HCoilPainter(color, stretch.clamp(0, 1)),
      );
}

class _HCoilPainter extends CustomPainter {
  _HCoilPainter(this.color, this.stretch);
  final Color color;
  final double stretch;

  @override
  void paint(Canvas canvas, Size size) {
    const loops = 7;
    final seg = size.width / (loops * 2);
    final amp = (size.height / 2) * (1 - .72 * stretch);
    final mid = size.height / 2;
    final p = Path()..moveTo(0, mid);
    for (var i = 0; i < loops * 2; i++) {
      final x0 = i * seg;
      final dir = i.isEven ? -1.0 : 1.0;
      p.cubicTo(x0 + seg * .25, mid + dir * amp * 1.35, x0 + seg * .75, mid + dir * amp * 1.35,
          x0 + seg, mid);
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_HCoilPainter old) => old.stretch != stretch || old.color != color;
}
