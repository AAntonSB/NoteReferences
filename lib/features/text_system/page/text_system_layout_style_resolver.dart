import 'package:flutter/material.dart';

import '../core/text_system_block.dart';
import 'text_system_page_setup.dart';

/// Shared layout style resolver for page measurement and the premium writer.
///
/// Phase 13D makes page setup responsible for both paper geometry and broad
/// typography. The fluent editor is still the only editing surface, but the
/// visible body style and passive pagination now resolve from the same setup.
class TextSystemLayoutStyleResolver {
  const TextSystemLayoutStyleResolver._();

  static TextStyle editorBodyStyle({
    required BuildContext context,
    required TextSystemPageSetup pageSetup,
  }) {
    final theme = Theme.of(context);
    final typography = pageSetup.typography;
    final base = theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    return base.copyWith(
      fontFamily: typography.fontFamily,
      fontFamilyFallback: typography.fontFamilyFallback.isEmpty ? null : typography.fontFamilyFallback,
      fontSize: pageSetup.defaultFontSize,
      height: pageSetup.lineSpacing <= 0 ? typography.lineSpacing : pageSetup.lineSpacing,
      letterSpacing: 0,
      color: theme.colorScheme.onSurface,
    );
  }

  static TextStyle blockStyle({
    required BuildContext context,
    required TextSystemBlock block,
    required TextSystemPageSetup pageSetup,
  }) {
    final theme = Theme.of(context);
    final body = editorBodyStyle(context: context, pageSetup: pageSetup);
    final typography = pageSetup.typography;

    if (block.metadata['kind'] == 'displayEquation') {
      return body.copyWith(
        fontSize: pageSetup.defaultFontSize * 1.30,
        fontWeight: FontWeight.w800,
        height: 1.80,
        color: theme.colorScheme.onSurface,
        fontFamilyFallback: null,
      );
    }

    return switch (block.type) {
      TextSystemBlockType.heading => body.copyWith(
          fontSize: typography.headingFontSizeForLevel(block.level ?? 2),
          fontWeight: (block.level ?? 2) == 1 ? FontWeight.w800 : FontWeight.w700,
          height: typography.headingLineHeight,
          letterSpacing: (block.level ?? 2) == 1 ? -0.25 : -0.1,
        ),
      TextSystemBlockType.quote => body.copyWith(
          fontStyle: FontStyle.italic,
          height: (pageSetup.lineSpacing + 0.05).clamp(1.25, 1.65).toDouble(),
          color: theme.colorScheme.onSurfaceVariant,
        ),
      TextSystemBlockType.code => body.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: null,
          fontSize: pageSetup.defaultFontSize * 0.92,
          height: 1.4,
        ),
      TextSystemBlockType.divider when block.metadata['kind'] == 'pageBreak' => body.copyWith(
          color: theme.colorScheme.primary,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      TextSystemBlockType.divider => body.copyWith(
          color: theme.colorScheme.outline,
          height: 1.2,
        ),
      _ => body,
    };
  }

  static double afterBlockSpacing({
    required TextSystemBlock block,
    required TextStyle style,
    required TextSystemPageSetup pageSetup,
  }) {
    final fontSize = style.fontSize ?? pageSetup.defaultFontSize;
    final baseSpacing = pageSetup.typography.paragraphSpacingPt;
    return switch (block.type) {
      TextSystemBlockType.heading => switch (block.level ?? 2) {
          1 => baseSpacing + fontSize * 0.35,
          2 => baseSpacing + fontSize * 0.20,
          _ => baseSpacing + fontSize * 0.08,
        },
      TextSystemBlockType.listItem => baseSpacing * 0.25,
      TextSystemBlockType.todo => baseSpacing * 0.25,
      _ when block.metadata['kind'] == 'displayEquation' => baseSpacing * 0.85,
      TextSystemBlockType.divider when block.metadata['kind'] == 'pageBreak' => baseSpacing * 0.4,
      TextSystemBlockType.divider => baseSpacing * 0.8,
      _ => baseSpacing,
    };
  }

  static String visibleTextForBlock(TextSystemBlock block, int blockIndex) {
    return switch (block.type) {
      TextSystemBlockType.listItem => block.metadata['ordered'] == true
          ? '${block.metadata['index'] is int ? block.metadata['index'] : blockIndex + 1}. ${block.text}'
          : '• ${block.text}',
      TextSystemBlockType.todo => block.checked == true ? '☑ ${block.text}' : '☐ ${block.text}',
      TextSystemBlockType.divider when block.metadata['kind'] == 'pageBreak' => 'Page break',
      TextSystemBlockType.divider => '────────',
      _ => block.text.isEmpty ? ' ' : block.text,
    };
  }
}
