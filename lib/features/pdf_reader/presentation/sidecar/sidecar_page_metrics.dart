import 'package:flutter/material.dart';

class SidecarPageMetrics {
  final int pageNumber;
  final double left;
  final double top;
  final double width;
  final double height;
  final Rect pdfPageRect;

  const SidecarPageMetrics({
    required this.pageNumber,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.pdfPageRect,
  });

  double get bottom => top + height;
}