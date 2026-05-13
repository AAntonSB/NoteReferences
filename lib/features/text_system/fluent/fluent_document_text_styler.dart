import 'package:flutter/material.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import 'fluent_buffer_segment.dart';
import 'fluent_document_buffer.dart';

/// Rich text painter for the continuous fluent editor buffer.
///
/// The fluent editor is still one native Flutter editing surface. This styler
/// only changes how that one buffer is drawn: headings, list markers, todos,
/// quotes, code, and inline marks become visible without creating separate
/// editable rows.
class FluentDocumentTextStyler {
  const FluentDocumentTextStyler();

  TextSpan buildTextSpan({
    required BuildContext context,
    required FluentDocumentBuffer buffer,
    required String text,
    required TextRange composing,
    required bool withComposing,
    TextStyle? baseStyle,
  }) {
    final theme = Theme.of(context);
    final effectiveBase = baseStyle ?? theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    if (text.isEmpty) return TextSpan(text: '', style: effectiveBase);

    // During very short transient states, Flutter may ask for a span before the
    // structured projection has been rebuilt. Prefer native editing stability
    // over stale rich styling in that exact moment.
    if (text != buffer.text) return TextSpan(text: text, style: effectiveBase);

    final children = <InlineSpan>[];
    for (var i = 0; i < buffer.segments.length; i++) {
      if (i > 0) children.add(TextSpan(text: '\n', style: effectiveBase));
      final segment = buffer.segments[i];
      final block = buffer.document.blockById(segment.blockId);
      final lineText = text.substring(segment.bufferStart, segment.bufferEnd);
      children.addAll(
        _lineSpans(
          theme: theme,
          fallbackStyle: effectiveBase,
          lineText: lineText,
          segment: segment,
          block: block,
          composing: withComposing ? composing : TextRange.empty,
        ),
      );
    }

    return TextSpan(style: effectiveBase, children: children);
  }

  List<InlineSpan> _lineSpans({
    required ThemeData theme,
    required TextStyle fallbackStyle,
    required String lineText,
    required FluentBufferSegment segment,
    required TextSystemBlock? block,
    required TextRange composing,
  }) {
    if (lineText.isEmpty) {
      return <InlineSpan>[TextSpan(text: '', style: _baseStyleForSegment(theme, fallbackStyle, segment))];
    }

    final prefixLength = segment.prefixLength;
    final contentLength = segment.contentLength;
    final base = _baseStyleForSegment(theme, fallbackStyle, segment);
    final boundaries = <int>{0, lineText.length, prefixLength};

    for (final mark in block?.marks ?? const <TextMark>[]) {
      final range = mark.range.clamp(contentLength);
      if (!range.isCollapsed) {
        boundaries
          ..add(prefixLength + range.start)
          ..add(prefixLength + range.end);
      }
    }

    final composingStart = (composing.start - segment.bufferStart).clamp(0, lineText.length).toInt();
    final composingEnd = (composing.end - segment.bufferStart).clamp(0, lineText.length).toInt();
    if (composing.isValid && composingStart < composingEnd) {
      boundaries
        ..add(composingStart)
        ..add(composingEnd);
    }

    final sorted = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final start = sorted[i];
      final end = sorted[i + 1];
      if (start == end) continue;

      final isPrefix = end <= prefixLength;
      var style = isPrefix
          ? _prefixStyleForSegment(theme, base, segment)
          : _styleForMarks(
              theme,
              base,
              _activeMarksForSlice(
                block?.marks ?? const <TextMark>[],
                start - prefixLength,
                end - prefixLength,
                contentLength,
              ),
            );

      if (composing.isValid && start < composingEnd && composingStart < end) {
        style = _styleForComposing(style);
      }

      spans.add(TextSpan(text: lineText.substring(start, end), style: style));
    }

    return spans;
  }

  List<TextMark> _activeMarksForSlice(
    List<TextMark> marks,
    int localStart,
    int localEnd,
    int textLength,
  ) {
    if (localEnd <= 0 || localStart >= textLength) return const <TextMark>[];
    final safeStart = localStart.clamp(0, textLength).toInt();
    final safeEnd = localEnd.clamp(0, textLength).toInt();
    if (safeStart >= safeEnd) return const <TextMark>[];

    return marks.where((mark) {
      final range = mark.range.clamp(textLength);
      return range.start <= safeStart && range.end >= safeEnd && !range.isCollapsed;
    }).toList();
  }

  TextStyle _baseStyleForSegment(
    ThemeData theme,
    TextStyle fallback,
    FluentBufferSegment segment,
  ) {
    final body = (theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
        .merge(fallback)
        .copyWith(color: fallback.color ?? theme.colorScheme.onSurface);
    final bodySize = body.fontSize ?? 16;

    return switch (segment.blockType) {
      TextSystemBlockType.heading => switch (segment.level ?? 2) {
          1 => body.copyWith(
              fontSize: bodySize * 1.5,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.25,
            ),
          2 => body.copyWith(
              fontSize: bodySize * 1.25,
              fontWeight: FontWeight.w700,
              height: 1.22,
              letterSpacing: -0.1,
            ),
          _ => body.copyWith(
              fontSize: bodySize * 1.12,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
        },
      TextSystemBlockType.quote => body.copyWith(
          fontStyle: FontStyle.italic,
          height: ((body.height ?? 1.42) + 0.05).clamp(1.25, 1.65).toDouble(),
          color: theme.colorScheme.onSurfaceVariant,
        ),
      TextSystemBlockType.code => body.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: null,
          fontSize: bodySize * 0.92,
          height: 1.4,
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        ),
      _ => body,
    };
  }

  TextStyle _prefixStyleForSegment(
    ThemeData theme,
    TextStyle base,
    FluentBufferSegment segment,
  ) {
    return switch (segment.blockType) {
      TextSystemBlockType.listItem => base.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      TextSystemBlockType.todo => base.copyWith(
          color: segment.checked == true ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      _ => base.copyWith(color: theme.colorScheme.onSurfaceVariant),
    };
  }

  TextStyle _styleForMarks(ThemeData theme, TextStyle base, List<TextMark> marks) {
    var style = base;
    for (final mark in marks) {
      style = switch (mark.kind) {
        TextMarkKind.bold => style.copyWith(fontWeight: FontWeight.w800),
        TextMarkKind.italic => style.copyWith(fontStyle: FontStyle.italic),
        TextMarkKind.underline => style.copyWith(
            decoration: _mergeDecoration(style.decoration, TextDecoration.underline),
          ),
        TextMarkKind.strikethrough => style.copyWith(
            decoration: _mergeDecoration(style.decoration, TextDecoration.lineThrough),
          ),
        TextMarkKind.highlight => style.copyWith(
            backgroundColor: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.82),
          ),
        TextMarkKind.code => style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        TextMarkKind.link => style.copyWith(
            color: theme.colorScheme.primary,
            decoration: _mergeDecoration(style.decoration, TextDecoration.underline),
            decorationColor: theme.colorScheme.primary,
          ),
      };
    }
    return style;
  }

  TextStyle _styleForComposing(TextStyle style) {
    return style.copyWith(
      decoration: _mergeDecoration(style.decoration, TextDecoration.underline),
    );
  }

  TextDecoration _mergeDecoration(TextDecoration? existing, TextDecoration next) {
    if (existing == null) return next;
    return TextDecoration.combine(<TextDecoration>[existing, next]);
  }
}
