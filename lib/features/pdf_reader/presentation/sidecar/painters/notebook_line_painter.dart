import 'package:flutter/material.dart';

class NotebookLinePainter extends CustomPainter {
  final Color lineColor;

  const NotebookLinePainter({
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor.withOpacity(0.35)
      ..strokeWidth = 1;

    const spacing = 40.0;

    for (double y = 80; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NotebookLinePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}