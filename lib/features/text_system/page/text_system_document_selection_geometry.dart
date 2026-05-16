import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import '../core/text_system_document_range.dart';
import 'text_system_layout_style_resolver.dart';
import 'text_system_page_setup.dart';
import 'text_system_paged_block_layout.dart';

@immutable
class TextSystemDocumentSelectionHit {
  const TextSystemDocumentSelectionHit({
    required this.blockId,
    required this.blockIndex,
    required this.offset,
    required this.pageNumber,
  });

  final String blockId;
  final int blockIndex;
  final int offset;
  final int pageNumber;
}

/// Line-accurate selection geometry for the real-page block surface.
///
/// This is the missing layer between the page UI and the document model:
///
///   pointer position -> document block/offset
///   document range   -> page-local highlight rectangles
///
/// Earlier range-select patches tried to infer selection from whole block
/// rectangles. That fails for wrapped paragraphs and cross-block drags because
/// a paragraph is not one horizontal line. This geometry layer measures each
/// selectable fragment with TextPainter and uses the resulting line/box metrics.
class TextSystemDocumentSelectionGeometry {
  const TextSystemDocumentSelectionGeometry._();

  static TextSystemDocumentSelectionHit? positionForPagePoint({
    required BuildContext context,
    required TextSystemDocument document,
    required TextSystemPagedBlockPage page,
    required TextSystemPageSetup pageSetup,
    required EdgeInsets margins,
    required Offset pagePoint,
  }) {
    if (page.fragments.isEmpty) return null;

    final contentPoint = Offset(
      pagePoint.dx - margins.left,
      pagePoint.dy - margins.top,
    );

    _MeasuredSelectionLine? bestLine;
    _MeasuredSelectionFragment? bestFragment;
    var bestScore = double.infinity;

    for (final fragment in page.fragments) {
      if (!_fragmentCanReceiveSelection(fragment)) continue;

      final block = document.blockById(fragment.blockId);
      if (block == null) continue;

      final measuredFragment = _measureFragment(
        context: context,
        block: block,
        fragment: fragment,
        pageSetup: pageSetup,
      );
      if (measuredFragment == null) continue;

      for (final line in measuredFragment.lines) {
        final score = _scoreLine(contentPoint, line.contentRect);
        if (score < bestScore) {
          bestScore = score;
          bestLine = line;
          bestFragment = measuredFragment;
        }
      }

      if (measuredFragment.lines.isEmpty) {
        final score = _scoreLine(contentPoint, fragment.rect);
        if (score < bestScore) {
          bestScore = score;
          bestLine = null;
          bestFragment = measuredFragment;
        }
      }
    }

    final measuredFragment = bestFragment;
    if (measuredFragment == null) return null;

    final line = bestLine;
    final localPainterPoint = Offset(
      (contentPoint.dx - measuredFragment.fragment.rect.left - measuredFragment.markerGutter)
          .clamp(0.0, measuredFragment.textWidth)
          .toDouble(),
      (contentPoint.dy - measuredFragment.fragment.rect.top)
          .clamp(0.0, measuredFragment.painter.height)
          .toDouble(),
    );

    var localOffset = measuredFragment.painter.getPositionForOffset(localPainterPoint).offset;
    if (line != null) {
      if (contentPoint.dx <= line.contentRect.left) {
        localOffset = line.localStart;
      } else if (contentPoint.dx >= line.contentRect.right) {
        localOffset = line.localEnd;
      } else {
        localOffset = localOffset.clamp(line.localStart, line.localEnd).toInt();
      }
    }

    final documentOffset = (measuredFragment.fragmentStart + localOffset)
        .clamp(measuredFragment.fragmentStart, measuredFragment.fragmentEnd)
        .toInt();

    return TextSystemDocumentSelectionHit(
      blockId: measuredFragment.fragment.blockId,
      blockIndex: measuredFragment.fragment.blockIndex,
      offset: documentOffset,
      pageNumber: page.pageNumber,
    );
  }

  static List<Rect> selectionRectsForPage({
    required BuildContext context,
    required TextSystemDocument document,
    required TextSystemPagedBlockPage page,
    required TextSystemPageSetup pageSetup,
    required EdgeInsets margins,
    required TextSystemDocumentRange range,
  }) {
    final rects = <Rect>[];

    for (final fragment in page.fragments) {
      final block = document.blockById(fragment.blockId);
      if (block == null) continue;
      if (fragment.blockIndex < range.start.blockIndex ||
          fragment.blockIndex > range.end.blockIndex) {
        continue;
      }

      if (!_fragmentCanReceiveSelection(fragment)) {
        // Phase 8 rule: document-level cross-block selections treat non-text
        // fragments as atomic objects. If a drag range passes through a figure,
        // table, equation, divider, page break, or section break, the whole
        // object receives a selection rectangle. The object itself remains
        // responsible for its own internal editing mode; this is only the
        // document-level selection visual.
        if (_fragmentShouldSelectAsObject(fragment, range)) {
          rects.add(
            Rect.fromLTWH(
              margins.left + fragment.rect.left,
              margins.top + fragment.rect.top,
              fragment.rect.width,
              fragment.rect.height,
            ).inflate(2.0),
          );
        }
        continue;
      }

      final measuredFragment = _measureFragment(
        context: context,
        block: block,
        fragment: fragment,
        pageSetup: pageSetup,
      );
      if (measuredFragment == null) continue;

      final blockStart = fragment.blockIndex == range.start.blockIndex
          ? range.start.offset.clamp(0, block.text.length).toInt()
          : 0;
      final blockEnd = fragment.blockIndex == range.end.blockIndex
          ? range.end.offset.clamp(blockStart, block.text.length).toInt()
          : block.text.length;

      final selectedStart = math.max(blockStart, measuredFragment.fragmentStart);
      final selectedEnd = math.min(blockEnd, measuredFragment.fragmentEnd);
      if (selectedEnd <= selectedStart) continue;

      final localStart = (selectedStart - measuredFragment.fragmentStart)
          .clamp(0, measuredFragment.text.length)
          .toInt();
      final localEnd = (selectedEnd - measuredFragment.fragmentStart)
          .clamp(localStart, measuredFragment.text.length)
          .toInt();
      if (localEnd <= localStart) continue;

      final boxes = measuredFragment.painter.getBoxesForSelection(
        TextSelection(baseOffset: localStart, extentOffset: localEnd),
      );

      if (boxes.isEmpty) {
        rects.add(
          Rect.fromLTWH(
            margins.left + fragment.rect.left + measuredFragment.markerGutter,
            margins.top + fragment.rect.top,
            math.max(2.0, measuredFragment.textWidth),
            math.max(2.0, measuredFragment.painter.height),
          ),
        );
        continue;
      }

      for (final box in boxes) {
        final rect = Rect.fromLTRB(
          margins.left + fragment.rect.left + measuredFragment.markerGutter + box.left,
          margins.top + fragment.rect.top + box.top,
          margins.left + fragment.rect.left + measuredFragment.markerGutter + box.right,
          margins.top + fragment.rect.top + box.bottom,
        );

        if (rect.width <= 0 || rect.height <= 0) continue;
        rects.add(rect.inflate(1.25));
      }
    }

    return rects;
  }


  static bool _fragmentShouldSelectAsObject(
    TextSystemPagedBlockFragment fragment,
    TextSystemDocumentRange range,
  ) {
    // A non-text object is selected only when the normalized document range
    // actually spans across it. This avoids making ordinary clicks near an
    // object look like whole-object selection while still supporting the first
    // proper cross-block rule: paragraph -> object -> paragraph selects the
    // object as part of the range.
    return fragment.blockIndex > range.start.blockIndex &&
        fragment.blockIndex < range.end.blockIndex;
  }

  static double _scoreLine(Offset point, Rect rect) {
    final clampedX = point.dx.clamp(rect.left, rect.right).toDouble();
    final clampedY = point.dy.clamp(rect.top, rect.bottom).toDouble();
    final dx = point.dx - clampedX;
    final dy = point.dy - clampedY;
    final centerY = rect.top + rect.height / 2;
    final verticalCenterDistance = (point.dy - centerY).abs();

    if (rect.top <= point.dy && point.dy <= rect.bottom) {
      return verticalCenterDistance + (point.dx < rect.left ? rect.left - point.dx : 0) * 0.05;
    }

    return dx * dx + dy * dy + verticalCenterDistance;
  }

  static _MeasuredSelectionFragment? _measureFragment({
    required BuildContext context,
    required TextSystemBlock block,
    required TextSystemPagedBlockFragment fragment,
    required TextSystemPageSetup pageSetup,
  }) {
    final fragmentStart = fragment.visualTextStartOffset.clamp(0, block.text.length).toInt();
    final fragmentEnd = fragment.visualTextEndOffset.clamp(fragmentStart, block.text.length).toInt();

    final rawText = fragment.text.isNotEmpty
        ? fragment.text
        : block.text.substring(fragmentStart, fragmentEnd);
    final text = rawText.isEmpty ? ' ' : rawText;

    final markerGutter = _markerGutterForBlock(block);
    final textWidth = math.max(1.0, fragment.rect.width - markerGutter);

    final style = TextSystemLayoutStyleResolver.blockStyle(
      context: context,
      block: block,
      pageSetup: pageSetup,
    );

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      maxLines: null,
    )..layout(maxWidth: textWidth);

    final lines = <_MeasuredSelectionLine>[];
    var localOffset = 0;
    for (final metric in painter.computeLineMetrics()) {
      if (localOffset >= text.length) break;

      final boundary = painter.getLineBoundary(TextPosition(offset: localOffset));
      final localStart = boundary.start.clamp(0, text.length).toInt();
      final localEnd = boundary.end.clamp(localStart, text.length).toInt();

      final top = fragment.rect.top + metric.baseline - metric.ascent;
      final rect = Rect.fromLTWH(
        fragment.rect.left + markerGutter,
        top,
        math.max(2.0, metric.width <= 0 ? textWidth : metric.width),
        math.max(2.0, metric.height),
      );

      lines.add(
        _MeasuredSelectionLine(
          localStart: localStart,
          localEnd: localEnd,
          contentRect: rect,
        ),
      );

      final nextOffset = localEnd <= localOffset ? localOffset + 1 : localEnd;
      localOffset = nextOffset.clamp(0, text.length).toInt();
    }

    if (lines.isEmpty) {
      lines.add(
        _MeasuredSelectionLine(
          localStart: 0,
          localEnd: text.length,
          contentRect: Rect.fromLTWH(
            fragment.rect.left + markerGutter,
            fragment.rect.top,
            textWidth,
            math.max(2.0, painter.height),
          ),
        ),
      );
    }

    return _MeasuredSelectionFragment(
      fragment: fragment,
      fragmentStart: fragmentStart,
      fragmentEnd: fragmentEnd,
      text: text,
      markerGutter: markerGutter,
      textWidth: textWidth,
      painter: painter,
      lines: lines,
    );
  }

  static double _markerGutterForBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.listItem || block.type == TextSystemBlockType.todo
        ? 30.0
        : 0.0;
  }

  static bool _fragmentCanReceiveSelection(TextSystemPagedBlockFragment fragment) {
    if (fragment.oversized) return false;
    return switch (fragment.blockType) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }
}

class _MeasuredSelectionFragment {
  const _MeasuredSelectionFragment({
    required this.fragment,
    required this.fragmentStart,
    required this.fragmentEnd,
    required this.text,
    required this.markerGutter,
    required this.textWidth,
    required this.painter,
    required this.lines,
  });

  final TextSystemPagedBlockFragment fragment;
  final int fragmentStart;
  final int fragmentEnd;
  final String text;
  final double markerGutter;
  final double textWidth;
  final TextPainter painter;
  final List<_MeasuredSelectionLine> lines;
}

class _MeasuredSelectionLine {
  const _MeasuredSelectionLine({
    required this.localStart,
    required this.localEnd,
    required this.contentRect,
  });

  final int localStart;
  final int localEnd;
  final Rect contentRect;
}
