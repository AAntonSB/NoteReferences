import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextRange, TextSelection;

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_range.dart';
import 'text_system_inline_atom_renderer.dart';
import 'objects/owned_equation_source_model.dart';

/// Shared marked-text layout helpers for the owned editor.
///
/// Rendering, hit testing, caret placement, and selection geometry must all
/// build the same [InlineSpan] tree. If any path falls back to a plain
/// TextSpan, glyph geometry drifts as soon as selected text contains bold,
/// italic, inline code, links, highlighting, or future inline typographic
/// attributes such as font-size overrides.
class TextSystemEditorMarkedTextLayout {
  const TextSystemEditorMarkedTextLayout._();

  static TextSystemEditorVisibleTextFragment visibleFragmentFor({
    required TextSystemBlock block,
    int blockIndex = 0,
    required int sourceStart,
    required int sourceEnd,
    required bool continuesFromPreviousPage,
  }) {
    final safeStart = sourceStart.clamp(0, block.text.length).toInt();
    final safeEnd = sourceEnd.clamp(safeStart, block.text.length).toInt();
    final rawSourceText = block.text.substring(safeStart, safeEnd);

    // Display equations are edited as normal document text, not as inline-math
    // atoms. Older 16K builds stored display equations as \( ... \), which
    // caused the inline atom renderer to compress them into a tiny inline glyph
    // and made caret/editing behavior feel broken. When the whole display
    // equation is visible, strip only those legacy delimiters for layout while
    // keeping document-offset mapping anchored to the real source range.
    var layoutSourceStart = safeStart;
    var layoutSourceEnd = safeEnd;
    var sourceText = rawSourceText;
    if (isDisplayEquationBlock(block) &&
        safeStart == 0 &&
        safeEnd == block.text.length &&
        rawSourceText.startsWith(r'\(') &&
        rawSourceText.endsWith(r'\)') &&
        rawSourceText.length >= 4) {
      layoutSourceStart = 2;
      layoutSourceEnd = block.text.length - 2;
      sourceText = rawSourceText.substring(2, rawSourceText.length - 2);
    }
    sourceText = sanitizeUtf16ForLayout(sourceText);

    // List markers are deliberately not injected into the editable text. They
    // live in a separate marker gutter so document offsets, caret geometry,
    // selection boxes, deletion, and clipboard all refer only to the user's
    // actual text.
    final visibleText = sourceText.isEmpty ? ' ' : sourceText;
    return TextSystemEditorVisibleTextFragment(
      block: block,
      blockIndex: blockIndex,
      sourceStart: safeStart,
      sourceEnd: safeEnd,
      layoutSourceStart: layoutSourceStart,
      layoutSourceEnd: layoutSourceEnd,
      prefix: '',
      sourceText: sourceText,
      visibleText: visibleText,
    );
  }

  static bool isListLikeBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.listItem || block.type == TextSystemBlockType.todo;
  }

  static bool isDisplayEquationBlock(TextSystemBlock block) {
    final kind = block.metadata['kind'];
    return kind == 'displayEquation' ||
        (block.type == TextSystemBlockType.custom && kind == 'equation');
  }

  static TextAlign textAlignFor(TextSystemBlock block) {
    return isDisplayEquationBlock(block) ? TextAlign.center : TextAlign.start;
  }

  static TextStyle effectiveTextStyleFor(
    BuildContext context,
    TextSystemBlock block,
    TextStyle baseStyle,
  ) {
    if (!isDisplayEquationBlock(block)) return baseStyle;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseFontSize = baseStyle.fontSize ?? theme.textTheme.bodyLarge?.fontSize ?? 16.0;
    return baseStyle.copyWith(
      color: colorScheme.onSurface,
      fontSize: baseFontSize * 1.30,
      fontWeight: FontWeight.w800,
      height: 1.70,
      fontFamilyFallback: null,
    );
  }

  static TextStyle displayEquationSourceTextStyleFor(
    BuildContext context,
    TextStyle displayStyle,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayFontSize = displayStyle.fontSize ?? theme.textTheme.bodyLarge?.fontSize ?? 18.0;
    return displayStyle.copyWith(
      color: colorScheme.onSurface,
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Consolas', 'Menlo', 'monospace'],
      fontSize: displayFontSize * 0.84,
      fontWeight: FontWeight.w600,
      height: 1.45,
      letterSpacing: -0.1,
    );
  }

  static const double displayEquationSourceTopInset = 148.0;
  // The focused equation authoring surface positions the RichText inside a
  // source lane with an 18 px left gutter plus a 2 px leading rule. Caret,
  // hit-testing, and selection must use the text origin, not the lane origin.
  static const double displayEquationSourceLeftInset = 20.0;
  static const double displayEquationSourceRightInset = 18.0;

  static double displayEquationSourceTextMaxWidth({required double availableWidth}) {
    if (!availableWidth.isFinite || availableWidth <= 0) return 1.0;
    final width = availableWidth - displayEquationSourceLeftInset - displayEquationSourceRightInset;
    return width < 1.0 ? 1.0 : width;
  }

  static double displayEquationVerticalTextInset({
    required double fragmentHeight,
    required double textHeight,
  }) {
    if (!fragmentHeight.isFinite || fragmentHeight <= 0 || !textHeight.isFinite || textHeight <= 0) {
      return 0.0;
    }
    final maxInset = (fragmentHeight - textHeight).clamp(0.0, double.infinity).toDouble();
    return maxInset < displayEquationSourceTopInset ? maxInset : displayEquationSourceTopInset;
  }

  static double displayEquationSourceHorizontalInset({
    required TextPainter painter,
    required String visibleText,
    required double maxWidth,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) return 0.0;
    return maxWidth <= displayEquationSourceLeftInset + 4 ? 0.0 : displayEquationSourceLeftInset;
  }

  static TextAlign sourceTextAlignFor(TextSystemBlock block) {
    return isDisplayEquationBlock(block) ? TextAlign.start : textAlignFor(block);
  }

  static List<InlineSpan> displayEquationSourceSpans({
    required BuildContext context,
    required String source,
    required TextStyle baseStyle,
    int? activeSourceOffset,
  }) {
    if (source.isEmpty) return <InlineSpan>[TextSpan(text: ' ', style: baseStyle)];
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final commandStyle = baseStyle.copyWith(
      color: colorScheme.primary,
      fontWeight: FontWeight.w800,
    );
    final delimiterStyle = baseStyle.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      fontWeight: FontWeight.w800,
    );
    final operatorStyle = baseStyle.copyWith(
      color: colorScheme.tertiary,
      fontWeight: FontWeight.w800,
    );
    final numberStyle = baseStyle.copyWith(
      color: colorScheme.secondary,
      fontWeight: FontWeight.w700,
    );
    final textModeStyle = baseStyle.copyWith(
      color: colorScheme.onSurface,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
    );
    final matchingDelimiterIndices = _matchingDelimiterIndices(source, activeSourceOffset);
    final activeCommandRange = _activeCommandRange(source, activeSourceOffset);
    final activeCommandStyle = commandStyle.copyWith(
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.42),
    );
    final matchingDelimiterStyle = delimiterStyle.copyWith(
      color: colorScheme.primary,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.48),
    );
    final diagnostics = OwnedEquationSourceModel.analyze(source).diagnostics;
    TextStyle diagnosticAware(TextStyle style, int tokenStart, int tokenEnd) {
      for (final diagnostic in diagnostics) {
        if (!diagnostic.intersects(tokenStart, tokenEnd)) continue;
        return switch (diagnostic.severity) {
          OwnedEquationDiagnosticSeverity.error => style.copyWith(
              color: colorScheme.error,
              backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.52),
              fontWeight: FontWeight.w900,
            ),
          OwnedEquationDiagnosticSeverity.warning => style.copyWith(
              backgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.44),
              fontWeight: FontWeight.w800,
            ),
          OwnedEquationDiagnosticSeverity.info => style.copyWith(
              backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.30),
            ),
        };
      }
      return style;
    }

    final spans = <InlineSpan>[];
    var i = 0;
    while (i < source.length) {
      final unit = source.codeUnitAt(i);
      final char = source[i];
      if (char == '\\') {
        var j = i + 1;
        while (j < source.length) {
          final c = source.codeUnitAt(j);
          final isLetter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
          if (!isLetter) break;
          j++;
        }
        // A bare backslash or a control-symbol delimiter such as \[ should
        // stay literal while the user is typing. Suggestions are shown by the
        // equation surface, but we do not visually pretend to know the intended
        // command until the user has typed at least one command letter.
        if (j == i + 1) {
          spans.add(TextSpan(text: char, style: diagnosticAware(delimiterStyle, i, i + 1)));
          i++;
          continue;
        }
        final token = source.substring(i, j);
        final tokenStyle = activeCommandRange != null && i >= activeCommandRange.start && j <= activeCommandRange.end
            ? activeCommandStyle
            : commandStyle;
        spans.add(TextSpan(text: token, style: diagnosticAware(tokenStyle, i, j)));
        i = j;
        continue;
      }
      if (char == '{' || char == '}' || char == '[' || char == ']' || char == '(' || char == ')') {
        final tokenStyle = matchingDelimiterIndices.contains(i) ? matchingDelimiterStyle : delimiterStyle;
        spans.add(TextSpan(text: char, style: diagnosticAware(tokenStyle, i, i + 1)));
        i++;
        continue;
      }
      if (char == '^' || char == '_' || char == '&' || char == '=' || char == '+' || char == '-' || char == '/' || char == '*') {
        spans.add(TextSpan(text: char, style: diagnosticAware(operatorStyle, i, i + 1)));
        i++;
        continue;
      }
      if (unit >= 48 && unit <= 57) {
        var j = i + 1;
        while (j < source.length) {
          final c = source.codeUnitAt(j);
          if (!((c >= 48 && c <= 57) || source[j] == '.')) break;
          j++;
        }
        spans.add(TextSpan(text: source.substring(i, j), style: diagnosticAware(numberStyle, i, j)));
        i = j;
        continue;
      }
      if (source.startsWith('eller', i) || source.startsWith('where', i) || source.startsWith('if', i)) {
        var j = i;
        while (j < source.length) {
          final c = source.codeUnitAt(j);
          final isWord = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
          if (!isWord) break;
          j++;
        }
        spans.add(TextSpan(text: source.substring(i, j), style: diagnosticAware(textModeStyle, i, j)));
        i = j;
        continue;
      }
      spans.add(TextSpan(text: char, style: diagnosticAware(baseStyle, i, i + 1)));
      i++;
    }

    return spans;
  }

  static Set<int> _matchingDelimiterIndices(String source, int? activeSourceOffset) {
    if (source.isEmpty || activeSourceOffset == null) return const <int>{};
    var index = activeSourceOffset.clamp(0, source.length).toInt();
    if (index == source.length) index = source.length - 1;
    if (index < 0) return const <int>{};

    final candidates = <int>[];
    if (_isDelimiterAt(source, index)) candidates.add(index);
    if (index > 0 && _isDelimiterAt(source, index - 1)) candidates.add(index - 1);
    for (final candidate in candidates) {
      final match = _matchingDelimiterFor(source, candidate);
      if (match != null) return <int>{candidate, match};
    }
    return const <int>{};
  }

  static bool _isDelimiterAt(String source, int index) {
    if (index < 0 || index >= source.length) return false;
    final char = source[index];
    return char == '{' || char == '}' || char == '[' || char == ']' || char == '(' || char == ')';
  }

  static int? _matchingDelimiterFor(String source, int index) {
    if (index < 0 || index >= source.length) return null;
    final char = source[index];
    final pairs = <String, String>{'{': '}', '[': ']', '(': ')'};
    final reversePairs = <String, String>{'}': '{', ']': '[', ')': '('};
    if (pairs.containsKey(char)) {
      final target = pairs[char]!;
      var depth = 0;
      for (var i = index; i < source.length; i++) {
        if (source[i] == char) depth++;
        if (source[i] == target) {
          depth--;
          if (depth == 0) return i;
        }
      }
      return null;
    }
    if (reversePairs.containsKey(char)) {
      final target = reversePairs[char]!;
      var depth = 0;
      for (var i = index; i >= 0; i--) {
        if (source[i] == char) depth++;
        if (source[i] == target) {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return null;
  }

  static TextRange? _activeCommandRange(String source, int? activeSourceOffset) {
    if (source.isEmpty || activeSourceOffset == null) return null;
    final offset = activeSourceOffset.clamp(0, source.length).toInt();
    var start = offset;
    if (start > 0 && start == source.length) start -= 1;
    while (start > 0) {
      final previous = source.codeUnitAt(start - 1);
      final isLetter = (previous >= 65 && previous <= 90) || (previous >= 97 && previous <= 122);
      if (!isLetter) break;
      start--;
    }
    if (start <= 0 || source[start - 1] != '\\') return null;
    start -= 1;
    var end = start + 1;
    while (end < source.length) {
      final c = source.codeUnitAt(end);
      final isLetter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
      if (!isLetter) break;
      end++;
    }
    if (end <= start + 1) return null;
    return TextRange(start: start, end: end);
  }

  static double listTextInsetFor(TextSystemBlock block) {
    return isListLikeBlock(block) ? 30.0 : 0.0;
  }

  static double listMarkerWidthFor(TextSystemBlock block) {
    return isListLikeBlock(block) ? 24.0 : 0.0;
  }

  static String listMarkerFor(TextSystemBlock block) {
    if (block.type == TextSystemBlockType.todo) {
      return block.checked == true ? '☑' : '☐';
    }
    if (block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true) {
      final rawIndex = block.metadata['index'];
      final index = rawIndex is num ? rawIndex.toInt() : int.tryParse('$rawIndex') ?? 1;
      return '$index.';
    }
    if (block.type == TextSystemBlockType.listItem) return '•';
    return '';
  }

  static TextSpan textSpanForVisibleFragment({
    required BuildContext context,
    required TextSystemEditorVisibleTextFragment visible,
    required TextStyle baseStyle,
    TextSystemRange? activeInlineAtomSourceRange,
    int? activeSourceOffset,
  }) {
    return TextSpan(
      style: baseStyle,
      children: spansForVisibleFragment(
        context: context,
        visible: visible,
        baseStyle: baseStyle,
        activeInlineAtomSourceRange: activeInlineAtomSourceRange,
        activeSourceOffset: activeSourceOffset,
      ),
    );
  }

  static List<InlineSpan> spansForVisibleFragment({
    required BuildContext context,
    required TextSystemEditorVisibleTextFragment visible,
    required TextStyle baseStyle,
    TextSystemRange? activeInlineAtomSourceRange,
    int? activeSourceOffset,
  }) {
    final spans = <InlineSpan>[];
    if (visible.prefix.isNotEmpty) {
      spans.add(TextSpan(text: visible.prefix, style: baseStyle));
    }

    if (visible.sourceText.isEmpty) {
      if (spans.isEmpty) spans.add(TextSpan(text: visible.visibleText, style: baseStyle));
      return spans;
    }

    if (isDisplayEquationBlock(visible.block)) {
      spans.addAll(displayEquationSourceSpans(
        context: context,
        source: visible.visibleText,
        baseStyle: baseStyle,
        activeSourceOffset: activeSourceOffset,
      ));
      return spans;
    }

    spans.addAll(TextSystemInlineAtomRenderer.spansForTextRange(
      context: context,
      text: sanitizeUtf16ForLayout(visible.sourceText),
      block: visible.block,
      blockIndex: visible.blockIndex,
      globalStart: visible.layoutSourceStart,
      globalEnd: visible.layoutSourceEnd,
      baseStyle: baseStyle,
      activeInlineAtomSourceRange: activeInlineAtomSourceRange,
    ));

    return spans.isEmpty ? <InlineSpan>[TextSpan(text: visible.visibleText, style: baseStyle)] : spans;
  }

  /// Returns a string that Flutter's text pipeline can safely lay out.
  ///
  /// A previous half-surrogate deletion can leave a Dart string with an
  /// unpaired UTF-16 surrogate. TextPainter/Paragraph then throws
  /// `string is not well-formed UTF-16`. This helper preserves all valid scalar
  /// values and replaces only malformed surrogate code units with U+FFFD. The
  /// replacement is one UTF-16 code unit, so document-offset mapping remains
  /// stable for the malformed character.
  static String sanitizeUtf16ForLayout(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      if (_isHighSurrogate(codeUnit)) {
        if (i + 1 < text.length && _isLowSurrogate(text.codeUnitAt(i + 1))) {
          buffer.writeCharCode(codeUnit);
          i++;
          buffer.writeCharCode(text.codeUnitAt(i));
        } else {
          buffer.write('�');
        }
        continue;
      }
      if (_isLowSurrogate(codeUnit)) {
        buffer.write('�');
        continue;
      }
      buffer.writeCharCode(codeUnit);
    }
    return buffer.toString();
  }

  static bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  static TextStyle styleWithMarks(
    BuildContext context,
    TextStyle baseStyle,
    List<TextMark> marks,
  ) {
    return TextSystemInlineAtomRenderer.styleWithMarks(context, baseStyle, marks);
  }

  static TextStyle _styleWithTypographicAttributes(
    TextStyle style,
    Map<String, String> attributes,
  ) {
    if (attributes.isEmpty) return style;
    var result = style;

    final fontSize = _doubleAttribute(attributes, const <String>['fontSize', 'fontSizePx', 'size']);
    if (fontSize != null && fontSize > 0) {
      result = result.copyWith(fontSize: fontSize);
    }

    final fontScale = _doubleAttribute(attributes, const <String>['fontScale', 'scale']);
    if (fontScale != null && fontScale > 0) {
      final baseSize = result.fontSize ?? style.fontSize;
      if (baseSize != null) {
        result = result.copyWith(fontSize: baseSize * fontScale);
      }
    }

    final family = attributes['fontFamily']?.trim();
    if (family != null && family.isNotEmpty) {
      result = result.copyWith(fontFamily: family);
    }

    return result;
  }

  static double? _doubleAttribute(
    Map<String, String> attributes,
    List<String> keys,
  ) {
    for (final key in keys) {
      final raw = attributes[key];
      if (raw == null) continue;
      final value = double.tryParse(raw.trim());
      if (value != null) return value;
    }
    return null;
  }
}

class TextSystemEditorVisibleTextFragment {
  const TextSystemEditorVisibleTextFragment({
    required this.block,
    required this.blockIndex,
    required this.sourceStart,
    required this.sourceEnd,
    int? layoutSourceStart,
    int? layoutSourceEnd,
    required this.prefix,
    required this.sourceText,
    required this.visibleText,
  })  : layoutSourceStart = layoutSourceStart ?? sourceStart,
        layoutSourceEnd = layoutSourceEnd ?? sourceEnd;

  final TextSystemBlock block;
  final int blockIndex;
  final int sourceStart;
  final int sourceEnd;
  final int layoutSourceStart;
  final int layoutSourceEnd;
  final String prefix;
  final String sourceText;
  final String visibleText;

  int get prefixLength => prefix.length;
  int get sourceLength => sourceText.length;

  int documentOffsetToVisual(int documentOffset) {
    final local = documentOffset.clamp(layoutSourceStart, layoutSourceEnd).toInt() - layoutSourceStart;
    return (prefixLength + local).clamp(0, visibleText.length).toInt();
  }

  int visualOffsetToDocument(int visualOffset) {
    final local = (visualOffset - prefixLength).clamp(0, sourceLength).toInt();
    return (layoutSourceStart + local).clamp(layoutSourceStart, layoutSourceEnd).toInt();
  }
}
