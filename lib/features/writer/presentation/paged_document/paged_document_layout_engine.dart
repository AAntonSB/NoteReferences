import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_page_spec.dart';

@immutable
class PageTextSlice {
  const PageTextSlice({
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  final String text;
  final int startOffset;
  final int endOffset;

  bool get isEmpty => text.isEmpty;
}

/// Pure pagination helper for the page-bound writer.
///
/// This class has no controllers and no widget lifecycle. It can later be
/// tested independently or replaced by a richer block layout engine.
class PagedDocumentLayoutEngine {
  const PagedDocumentLayoutEngine({
    required this.pageStyle,
  });

  final AcademicPageStyle pageStyle;

  List<PageTextSlice> paginate(String documentText) {
    if (documentText.isEmpty) {
      return const <PageTextSlice>[
        PageTextSlice(text: '', startOffset: 0, endOffset: 0),
      ];
    }

    final slices = <PageTextSlice>[];
    var cursor = 0;

    while (cursor < documentText.length) {
      final remaining = documentText.substring(cursor);
      final localEnd = _bestFittingEnd(remaining);
      final safeLocalEnd = math.max(1, math.min(localEnd, remaining.length));

      var globalEnd = cursor + safeLocalEnd;

      if (globalEnd < documentText.length) {
        final semanticEnd =
            _lastSemanticBreakBefore(documentText, cursor, globalEnd);

        if (semanticEnd > cursor &&
            semanticEnd > cursor + safeLocalEnd * 0.65) {
          globalEnd = semanticEnd;
        } else {
          final whitespaceEnd =
              _lastWhitespaceBreakBefore(documentText, cursor, globalEnd);

          if (whitespaceEnd > cursor &&
              whitespaceEnd > cursor + safeLocalEnd * 0.65) {
            globalEnd = whitespaceEnd;
          }
        }
      }

      // Avoid starting the next page with invisible leading spaces/tabs.
      final pageText = documentText.substring(cursor, globalEnd).trimRight();
      final trimmedRight = cursor + pageText.length;
      final effectiveEnd = math.max(cursor + 1, trimmedRight);

      slices.add(
        PageTextSlice(
          text: documentText.substring(cursor, effectiveEnd),
          startOffset: cursor,
          endOffset: effectiveEnd,
        ),
      );

      cursor = effectiveEnd;

      while (cursor < documentText.length &&
          (documentText.codeUnitAt(cursor) == 0x20 ||
              documentText.codeUnitAt(cursor) == 0x09)) {
        cursor++;
      }
    }

    if (slices.isEmpty) {
      return const <PageTextSlice>[
        PageTextSlice(text: '', startOffset: 0, endOffset: 0),
      ];
    }

    return slices;
  }

  bool textFitsPage(String text) {
    if (text.trim().isEmpty) {
      return true;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: pageStyle.bodyStyle,
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: math.max(1, pageStyle.contentWidthPt));

    // Small tolerance avoids jitter from font metric rounding.
    return painter.height <= pageStyle.contentHeightPt - 2;
  }

  int _bestFittingEnd(String text) {
    if (text.isEmpty) {
      return 0;
    }

    if (textFitsPage(text)) {
      return text.length;
    }

    var low = 0;
    var high = text.length;
    var best = 0;

    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final candidate = text.substring(0, mid);

      if (textFitsPage(candidate)) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return math.max(1, math.min(best, text.length));
  }

  int _lastSemanticBreakBefore(String text, int globalStart, int globalEnd) {
    var breakAt = -1;
    final boundedStart = math.max(0, math.min(globalStart, text.length));
    final boundedEnd = math.max(boundedStart, math.min(globalEnd, text.length));
    final candidate = text.substring(boundedStart, boundedEnd);

    for (final match in RegExp(r'[\.\!\?]\s+').allMatches(candidate)) {
      breakAt = boundedStart + match.end;
    }

    return breakAt;
  }

  int _lastWhitespaceBreakBefore(String text, int globalStart, int globalEnd) {
    var breakAt = -1;
    final boundedStart = math.max(0, math.min(globalStart, text.length));
    final boundedEnd = math.max(boundedStart, math.min(globalEnd, text.length));
    final candidate = text.substring(boundedStart, boundedEnd);

    for (final match in RegExp(r'\s+').allMatches(candidate)) {
      breakAt = boundedStart + match.end;
    }

    return breakAt;
  }
}
