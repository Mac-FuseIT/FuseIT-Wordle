import 'package:flutter/material.dart';
import 'dart:math';

class WavyBackground extends StatelessWidget {
  final Color backgroundColor;
  final Color accentColor;

  const WavyBackground({super.key, required this.backgroundColor, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _WavyPainter(backgroundColor: backgroundColor, accentColor: accentColor),
    );
  }
}

class _WavyPainter extends CustomPainter {
  final Color backgroundColor;
  final Color accentColor;

  _WavyPainter({required this.backgroundColor, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = backgroundColor);

    final layers = [0.15, 0.10, 0.07];
    final widths = [0.14, 0.11, 0.18];

    for (int i = 0; i < layers.length; i++) {
      final paint = Paint()..color = accentColor.withValues(alpha: layers[i]);
      final w = size.width * widths[i];

      // Left wave
      final leftPath = Path();
      leftPath.moveTo(0, 0);
      leftPath.cubicTo(w * 1.5, size.height * 0.15, w * 0.5, size.height * 0.35, w * 1.2, size.height * 0.5);
      leftPath.cubicTo(w * 1.8, size.height * 0.65, w * 0.6, size.height * 0.8, 0, size.height);
      leftPath.lineTo(0, 0);
      leftPath.close();
      canvas.drawPath(leftPath, paint);

      // Right wave
      final rightPath = Path();
      rightPath.moveTo(size.width, 0);
      rightPath.cubicTo(size.width - w * 1.5, size.height * 0.15, size.width - w * 0.5, size.height * 0.35, size.width - w * 1.2, size.height * 0.5);
      rightPath.cubicTo(size.width - w * 1.8, size.height * 0.65, size.width - w * 0.6, size.height * 0.8, size.width, size.height);
      rightPath.lineTo(size.width, 0);
      rightPath.close();
      canvas.drawPath(rightPath, paint);
    }
  }

  @override
  bool shouldRepaint(_WavyPainter old) => old.backgroundColor != backgroundColor || old.accentColor != accentColor;
}
