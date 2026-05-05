import 'package:flutter/material.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';

/// Shared structured-text renderer used by read-only previews and lightweight
/// surface diagnostics.
///
/// Editable surfaces can still use platform text editing controls. This helper
/// makes sure the same [TextSystemBlock] model has one canonical display path
/// for marks such as bold, italic, highlight, code, and links.
class TextSystemRichTextRenderer {
  const TextSystemRichTextRenderer._();

  static Widget block(
    BuildContext context, {
    required TextSystemBlock block,
    bool selectable = true,
    TextStyle? baseStyle,
    TextAlign textAlign = TextAlign.start,
    void Function(TextMark mark)? onLinkTap,
  }) {
    final theme = Theme.of(context);
    final effectiveBaseStyle = baseStyle ?? _baseStyleForBlock(theme, block);
    final textSpan = span(
      context,
      block: block,
      baseStyle: effectiveBaseStyle,
      onLinkTap: onLinkTap,
    );

    final content = selectable
        ? SelectableText.rich(textSpan, textAlign: textAlign)
        : RichText(text: textSpan, textAlign: textAlign);

    return switch (block.type) {
      TextSystemBlockType.heading => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: content,
        ),
      TextSystemBlockType.listItem => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_listPrefix(block), style: effectiveBaseStyle),
              ),
              const SizedBox(width: 8),
              Expanded(child: content),
            ],
          ),
        ),
      TextSystemBlockType.todo => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                block.checked == true
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: content),
            ],
          ),
        ),
      TextSystemBlockType.quote => Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
            ),
          ),
          child: content,
        ),
      TextSystemBlockType.divider => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: theme.colorScheme.outlineVariant),
        ),
      _ => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: content,
        ),
    };
  }

  static TextSpan span(
    BuildContext context, {
    required TextSystemBlock block,
    TextStyle? baseStyle,
    void Function(TextMark mark)? onLinkTap,
  }) {
    final theme = Theme.of(context);
    final text = block.text;
    final base = baseStyle ?? _baseStyleForBlock(theme, block);
    if (text.isEmpty) {
      return TextSpan(text: '', style: base);
    }

    final boundaries = <int>{0, text.length};
    for (final mark in block.marks) {
      final range = mark.range.clamp(text.length);
      if (!range.isCollapsed) {
        boundaries
          ..add(range.start)
          ..add(range.end);
      }
    }

    final sorted = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final start = sorted[i];
      final end = sorted[i + 1];
      if (start == end) continue;

      final activeMarks = block.marks.where((mark) {
        final range = mark.range.clamp(text.length);
        return range.start <= start && range.end >= end && !range.isCollapsed;
      }).toList();

      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: _styleForMarks(theme, base, activeMarks),
        ),
      );
    }

    return TextSpan(style: base, children: spans);
  }

  static TextStyle _baseStyleForBlock(ThemeData theme, TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.heading => switch (block.level ?? 2) {
          1 => theme.textTheme.headlineMedium ?? const TextStyle(fontSize: 28),
          2 => theme.textTheme.titleLarge ?? const TextStyle(fontSize: 22),
          _ => theme.textTheme.titleMedium ?? const TextStyle(fontSize: 18),
        },
      TextSystemBlockType.code => theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace') ??
          const TextStyle(fontFamily: 'monospace'),
      TextSystemBlockType.quote => theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic) ??
          const TextStyle(fontStyle: FontStyle.italic),
      _ => theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16),
    };
  }

  static TextStyle _styleForMarks(
    ThemeData theme,
    TextStyle base,
    List<TextMark> marks,
  ) {
    var style = base;
    for (final mark in marks) {
      style = switch (mark.kind) {
        TextMarkKind.bold => style.copyWith(fontWeight: FontWeight.w700),
        TextMarkKind.italic => style.copyWith(fontStyle: FontStyle.italic),
        TextMarkKind.underline => style.copyWith(decoration: _mergeDecoration(style.decoration, TextDecoration.underline)),
        TextMarkKind.strikethrough => style.copyWith(decoration: _mergeDecoration(style.decoration, TextDecoration.lineThrough)),
        TextMarkKind.highlight => style.copyWith(backgroundColor: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.75)),
        TextMarkKind.code => style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        TextMarkKind.link => style.copyWith(
            color: theme.colorScheme.primary,
            decoration: _mergeDecoration(style.decoration, TextDecoration.underline),
          ),
      };
    }
    return style;
  }

  static TextDecoration _mergeDecoration(TextDecoration? existing, TextDecoration next) {
    if (existing == null) return next;
    return TextDecoration.combine(<TextDecoration>[existing, next]);
  }

  static String _listPrefix(TextSystemBlock block) {
    final ordered = block.metadata['ordered'] == true;
    if (!ordered) return '•';
    final index = block.metadata['index'];
    return '${index is int ? index : 1}.';
  }
}
