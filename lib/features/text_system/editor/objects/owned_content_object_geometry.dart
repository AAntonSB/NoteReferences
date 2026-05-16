import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/text_system_block.dart';

/// Shared geometry for owned Premium Writer content objects.
///
/// This keeps rendered figure/table affordances and selection/caret overlays from
/// using separate guesses. The first consumers are the owned figure renderer and
/// owned selection overlay; future object surfaces should use this same helper
/// instead of inventing local rectangle math.
class OwnedContentObjectGeometry {
  const OwnedContentObjectGeometry._();

  static double figureWidthFactor(TextSystemBlock? block) {
    final rawSize = block?.metadata['figureSize'] ?? block?.metadata['size'];
    return switch (rawSize?.toString()) {
      'small' => 0.52,
      'large' => 0.88,
      'fullWidth' => 1.0,
      _ => 0.72,
    };
  }

  static double figureAspectRatio(TextSystemBlock? block) {
    final rawAspect = block?.metadata['imageAspectRatio'] ?? block?.metadata['aspectRatio'];
    final parsed = rawAspect is num ? rawAspect.toDouble() : double.tryParse('$rawAspect');
    if (parsed != null && parsed.isFinite && parsed > 0.05) {
      return parsed.clamp(0.15, 8.0).toDouble();
    }

    final rawWidth = block?.metadata['imageWidth'];
    final rawHeight = block?.metadata['imageHeight'];
    final width = rawWidth is num ? rawWidth.toDouble() : double.tryParse('$rawWidth');
    final height = rawHeight is num ? rawHeight.toDouble() : double.tryParse('$rawHeight');
    if (width != null && height != null && width > 0 && height > 0) {
      return (width / height).clamp(0.15, 8.0).toDouble();
    }

    return 1.0;
  }

  static Rect applyFigureVisibleContentInsets({
    required Rect imageRect,
    required TextSystemBlock? block,
  }) {
    double? readRatio(String key) {
      final raw = block?.metadata[key];
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (value == null || !value.isFinite) return null;
      return value.clamp(0.0, 1.0).toDouble();
    }

    final left = readRatio('imageVisibleLeft');
    final top = readRatio('imageVisibleTop');
    final right = readRatio('imageVisibleRight');
    final bottom = readRatio('imageVisibleBottom');
    if (left == null || top == null || right == null || bottom == null) return imageRect;
    if (right <= left || bottom <= top) return imageRect;

    final trimmed = Rect.fromLTRB(
      imageRect.left + imageRect.width * left,
      imageRect.top + imageRect.height * top,
      imageRect.left + imageRect.width * right,
      imageRect.top + imageRect.height * bottom,
    );
    // Keep a small selection affordance around the visible pixels. The frame
    // should track the image content, not the transparent canvas, but it still
    // needs to be easy to see and grab with the pointer.
    return trimmed.inflate(3).intersect(imageRect);
  }

  static Rect centeredFigureImageRect({
    required Rect reservedRect,
    required TextSystemBlock? block,
    double topInset = 4,
    double bottomInset = 4,
    double horizontalInset = 0,
  }) {
    final availableWidth = math.max(20.0, reservedRect.width - horizontalInset * 2);
    final availableHeight = math.max(20.0, reservedRect.height - topInset - bottomInset);
    final maxWidth = availableWidth * figureWidthFactor(block);
    final aspectRatio = figureAspectRatio(block);

    var width = math.min(maxWidth, availableHeight * aspectRatio);
    var height = width / aspectRatio;
    if (height > availableHeight) {
      height = availableHeight;
      width = height * aspectRatio;
    }

    width = width.clamp(20.0, availableWidth).toDouble();
    height = height.clamp(20.0, availableHeight).toDouble();

    return Rect.fromLTWH(
      reservedRect.left + (reservedRect.width - width) / 2,
      reservedRect.top + topInset + (availableHeight - height) / 2,
      width,
      height,
    );
  }

  static Size centeredFigureImageSize({
    required BoxConstraints constraints,
    required TextSystemBlock? block,
  }) {
    final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 560.0;
    final maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 180.0;
    final rect = centeredFigureImageRect(
      reservedRect: Rect.fromLTWH(0, 0, maxWidth, maxHeight),
      block: block,
      topInset: 0,
      bottomInset: 0,
    );
    return rect.size;
  }

  static Rect figureImageRectInsideBlock({
    required Rect blockRect,
    required TextSystemBlock? block,
  }) {
    final captionReserve = _figureCaptionReserve(blockRect.height);
    final imageReserved = Rect.fromLTWH(
      blockRect.left,
      blockRect.top,
      blockRect.width,
      math.max(20.0, blockRect.height - captionReserve),
    );
    final imageRect = centeredFigureImageRect(
      reservedRect: imageReserved,
      block: block,
      topInset: 4,
      bottomInset: 4,
    );
    return applyFigureVisibleContentInsets(imageRect: imageRect, block: block);
  }

  static double _figureCaptionReserve(double blockHeight) {
    return math.min(76.0, math.max(38.0, blockHeight * 0.26));
  }
}
