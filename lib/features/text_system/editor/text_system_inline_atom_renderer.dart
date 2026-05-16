import 'package:flutter/material.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_range.dart';
import '../references/actions/text_system_reference_actions.dart';

/// Owned-editor inline atom renderer.
///
/// This is the shared inline-atom path for rendering, hit testing, caret
/// geometry, and selection geometry. It intentionally keeps rendered atom text
/// offset-compatible with the source text by padding/truncating to the same
/// UTF-16 length. That lets the owned editor show citations/references/math as
/// atoms without losing document-offset mapping.
class TextSystemInlineAtomRenderer {
  const TextSystemInlineAtomRenderer._();

  static Iterable<RegExpMatch> inlineMathMatchesForText(String text) {
    if (text.isEmpty) return const <RegExpMatch>[];
    return RegExp(r'\\\((.+?)\\\)').allMatches(text);
  }

  static List<TextSystemInlineAtomRange> inlineMathRangesForVisibleText({
    required String text,
    required int globalStart,
    required int globalEnd,
  }) {
    if (text.isEmpty) return const <TextSystemInlineAtomRange>[];
    final ranges = <TextSystemInlineAtomRange>[];
    final visibleRange = TextSystemRange(globalStart, globalEnd);
    for (final match in inlineMathMatchesForText(text)) {
      final localStart = match.start.clamp(0, text.length).toInt();
      final localEnd = match.end.clamp(localStart, text.length).toInt();
      final globalRange = TextSystemRange(globalStart + localStart, globalStart + localEnd)
          .intersection(visibleRange);
      if (globalRange == null || globalRange.isCollapsed) continue;
      ranges.add(TextSystemInlineAtomRange(
        localRange: TextSystemRange(localStart, localEnd),
        globalRange: globalRange,
      ));
    }
    return ranges;
  }

  static List<TextSystemInlineAtom> atomsForVisibleRange({
    required String text,
    required TextSystemBlock block,
    required int blockIndex,
    required int globalStart,
    required int globalEnd,
  }) {
    if (text.isEmpty) return const <TextSystemInlineAtom>[];

    final visibleRange = TextSystemRange(globalStart, globalEnd);
    final atoms = <TextSystemInlineAtom>[];

    for (final match in inlineMathMatchesForText(text)) {
      final localStart = match.start.clamp(0, text.length).toInt();
      final localEnd = match.end.clamp(localStart, text.length).toInt();
      final globalRange = TextSystemRange(globalStart + localStart, globalStart + localEnd)
          .intersection(visibleRange);
      if (globalRange == null || globalRange.isCollapsed) continue;
      final sourceText = text.substring(localStart, localEnd);
      final latex = (match.group(1) ?? '').trim();
      atoms.add(
        TextSystemInlineAtom(
          id: 'math:${block.id}:${globalRange.start}:${globalRange.end}',
          kind: TextSystemInlineAtomRenderKind.math,
          blockId: block.id,
          blockIndex: blockIndex,
          localRange: TextSystemRange(localStart, localEnd),
          globalRange: globalRange,
          sourceText: sourceText,
          displayText: latex.isEmpty ? sourceText : latex,
          latex: latex,
        ),
      );
    }

    for (final mark in block.marks) {
      if (mark.kind != TextMarkKind.link) continue;
      if (isFootnoteReferenceMark(mark)) continue;
      final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
      if (inlineReference == null) continue;
      final intersection = mark.range.intersection(visibleRange);
      if (intersection == null || intersection.isCollapsed) continue;

      final localStart = (intersection.start - globalStart).clamp(0, text.length).toInt();
      final localEnd = (intersection.end - globalStart).clamp(localStart, text.length).toInt();
      if (localStart >= localEnd) continue;
      final localRange = TextSystemRange(localStart, localEnd);
      final overlapsMath = atoms.any(
        (atom) => atom.kind == TextSystemInlineAtomRenderKind.math && atom.localRange.overlaps(localRange),
      );
      if (overlapsMath) continue;

      final sourceText = text.substring(localStart, localEnd);
      final displayText = inlineReference.selectedText?.trim().isNotEmpty == true
          ? inlineReference.selectedText!.trim()
          : sourceText;
      final kind = inlineReference.isCitation
          ? TextSystemInlineAtomRenderKind.citation
          : TextSystemInlineAtomRenderKind.reference;
      atoms.add(
        TextSystemInlineAtom(
          id: inlineReference.id.isNotEmpty
              ? 'reference:${inlineReference.id}'
              : 'reference:${block.id}:${intersection.start}:${intersection.end}',
          kind: kind,
          blockId: block.id,
          blockIndex: blockIndex,
          localRange: localRange,
          globalRange: intersection,
          sourceText: sourceText,
          displayText: displayText,
          referenceMark: mark,
          inlineReference: inlineReference,
        ),
      );
    }

    atoms.sort((a, b) {
      final startCompare = a.localRange.start.compareTo(b.localRange.start);
      if (startCompare != 0) return startCompare;
      return b.localRange.length.compareTo(a.localRange.length);
    });

    final normalized = <TextSystemInlineAtom>[];
    var consumedUntil = 0;
    for (final atom in atoms) {
      if (atom.localRange.start < consumedUntil) continue;
      normalized.add(atom);
      consumedUntil = atom.localRange.end;
    }
    return List<TextSystemInlineAtom>.unmodifiable(normalized);
  }

  static TextSystemInlineAtom? atomAtDocumentOffset({
    required TextSystemBlock block,
    required int blockIndex,
    required String visibleText,
    required int globalStart,
    required int globalEnd,
    required int documentOffset,
  }) {
    final atoms = atomsForVisibleRange(
      text: visibleText,
      block: block,
      blockIndex: blockIndex,
      globalStart: globalStart,
      globalEnd: globalEnd,
    );
    for (final atom in atoms) {
      // Make endpoints feel clickable. This is useful for rendered chips where
      // users expect the whole visual atom to be interactive.
      if (documentOffset >= atom.globalRange.start && documentOffset <= atom.globalRange.end) {
        return atom;
      }
    }
    return null;
  }

  static TextSystemInlineAtom? atomAtTextLocalOffset({
    required TextPainter painter,
    required Offset localOffset,
    required TextSystemBlock block,
    required int blockIndex,
    required String sourceText,
    required int globalStart,
    required int globalEnd,
    required int prefixLength,
    TextSystemRange? activeInlineAtomSourceRange,
    double hitSlop = 2.0,
  }) {
    final atoms = atomsForVisibleRange(
      text: sourceText,
      block: block,
      blockIndex: blockIndex,
      globalStart: globalStart,
      globalEnd: globalEnd,
    );
    for (final atom in atoms) {
      if (activeInlineAtomSourceRange != null && activeInlineAtomSourceRange.overlaps(atom.globalRange)) {
        continue;
      }
      final localStart = (atom.globalRange.start - globalStart).clamp(0, sourceText.length).toInt();
      final localEnd = (atom.globalRange.end - globalStart).clamp(localStart, sourceText.length).toInt();
      final visualStart = prefixLength + localStart;
      final visualEnd = prefixLength + localEnd;
      if (visualEnd <= visualStart) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: visualStart, extentOffset: visualEnd),
      );
      for (final box in boxes) {
        final rect = box.toRect().inflate(hitSlop);
        if (rect.contains(localOffset)) return atom;
      }
    }
    return null;
  }

  static int adjustDocumentOffsetForInlineAtomEdge({
    required TextPainter painter,
    required Offset localOffset,
    required TextSystemBlock block,
    required int blockIndex,
    required String sourceText,
    required int globalStart,
    required int globalEnd,
    required int prefixLength,
    required int documentOffset,
    TextSystemRange? activeInlineAtomSourceRange,
    double verticalSlop = 3.0,
  }) {
    final atoms = atomsForVisibleRange(
      text: sourceText,
      block: block,
      blockIndex: blockIndex,
      globalStart: globalStart,
      globalEnd: globalEnd,
    );
    for (final atom in atoms) {
      if (activeInlineAtomSourceRange != null && activeInlineAtomSourceRange.overlaps(atom.globalRange)) {
        continue;
      }
      if (documentOffset < atom.globalRange.start || documentOffset > atom.globalRange.end) {
        continue;
      }
      final localStart = (atom.globalRange.start - globalStart).clamp(0, sourceText.length).toInt();
      final localEnd = (atom.globalRange.end - globalStart).clamp(localStart, sourceText.length).toInt();
      final visualStart = prefixLength + localStart;
      final visualEnd = prefixLength + localEnd;
      if (visualEnd <= visualStart) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: visualStart, extentOffset: visualEnd),
      );
      for (final box in boxes) {
        final rect = box.toRect();
        if (localOffset.dy < rect.top - verticalSlop || localOffset.dy > rect.bottom + verticalSlop) {
          continue;
        }
        if (localOffset.dx > rect.right) return atom.globalRange.end;
        if (localOffset.dx < rect.left) return atom.globalRange.start;
      }
    }
    return documentOffset;
  }

  static List<InlineSpan> spansForTextRange({
    required BuildContext context,
    required String text,
    required TextSystemBlock block,
    required int blockIndex,
    required int globalStart,
    required int globalEnd,
    required TextStyle baseStyle,
    TextSystemRange? activeInlineAtomSourceRange,
  }) {
    if (text.isEmpty) return <InlineSpan>[TextSpan(text: text, style: baseStyle)];

    final atoms = atomsForVisibleRange(
      text: text,
      block: block,
      blockIndex: blockIndex,
      globalStart: globalStart,
      globalEnd: globalEnd,
    );
    if (atoms.isEmpty) {
      return markedSpansForRange(
        context: context,
        text: text,
        block: block,
        globalStart: globalStart,
        globalEnd: globalEnd,
        baseStyle: baseStyle,
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;

    void appendNormal(int start, int end) {
      if (end <= start) return;
      spans.addAll(
        markedSpansForRange(
          context: context,
          text: text.substring(start, end),
          block: block,
          globalStart: globalStart + start,
          globalEnd: globalStart + end,
          baseStyle: baseStyle,
        ),
      );
    }

    for (final atom in atoms) {
      appendNormal(cursor, atom.localRange.start);
      spans.add(_spanForAtom(
        context: context,
        block: block,
        atom: atom,
        baseStyle: baseStyle,
        activeInlineAtomSourceRange: activeInlineAtomSourceRange,
      ));
      cursor = atom.localRange.end;
    }

    appendNormal(cursor, text.length);
    return spans.isEmpty ? <InlineSpan>[TextSpan(text: text, style: baseStyle)] : spans;
  }

  static InlineSpan _spanForAtom({
    required BuildContext context,
    required TextSystemBlock block,
    required TextSystemInlineAtom atom,
    required TextStyle baseStyle,
    TextSystemRange? activeInlineAtomSourceRange,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = activeInlineAtomSourceRange != null && activeInlineAtomSourceRange.overlaps(atom.globalRange);
    if (active) {
      return TextSpan(
        text: atom.sourceText,
        style: atom.kind == TextSystemInlineAtomRenderKind.math
            ? inlineMathSourceStyle(baseStyle)
            : activeInlineAtomSourceStyle(baseStyle, colorScheme),
      );
    }

    switch (atom.kind) {
      case TextSystemInlineAtomRenderKind.math:
        return TextSpan(
          text: sameLengthInlineAtomDisplay(
            humanReadableInlineMath(atom.latex ?? atom.displayText),
            atom.sourceText.length,
          ),
          style: inlineMathRenderedEditingStyle(baseStyle, colorScheme),
        );
      case TextSystemInlineAtomRenderKind.reference:
      case TextSystemInlineAtomRenderKind.citation:
        final reference = atom.inlineReference;
        final broken = reference == null || reference.targetId.trim().isEmpty;
        final coveringMarks = block.marks
            .where((mark) => mark.range.containsRange(atom.globalRange))
            .toList(growable: false);
        final style = styleWithMarks(context, baseStyle, coveringMarks).copyWith(
          color: broken ? colorScheme.error : colorScheme.primary,
          fontWeight: FontWeight.w700,
          backgroundColor: broken
              ? colorScheme.errorContainer.withValues(alpha: 0.22)
              : colorScheme.primaryContainer.withValues(alpha: atom.kind == TextSystemInlineAtomRenderKind.citation ? 0.30 : 0.22),
        );
        return TextSpan(
          text: sameLengthInlineAtomDisplay(atom.displayText, atom.sourceText.length),
          style: style,
        );
    }
  }

  static List<InlineSpan> markedSpansForRange({
    required BuildContext context,
    required String text,
    required TextSystemBlock block,
    required int globalStart,
    required int globalEnd,
    required TextStyle baseStyle,
  }) {
    if (text.isEmpty) return <InlineSpan>[TextSpan(text: text, style: baseStyle)];

    final localLength = text.length;
    final boundaries = <int>{0, localLength};
    final inlineMathRanges = inlineMathRangesForVisibleText(
      text: text,
      globalStart: globalStart,
      globalEnd: globalEnd,
    );
    for (final range in inlineMathRanges) {
      boundaries.add((range.globalRange.start - globalStart).clamp(0, localLength).toInt());
      boundaries.add((range.globalRange.end - globalStart).clamp(0, localLength).toInt());
    }

    for (final mark in block.marks) {
      final intersection = mark.range.intersection(TextSystemRange(globalStart, globalEnd));
      if (intersection == null) continue;
      boundaries.add((intersection.start - globalStart).clamp(0, localLength).toInt());
      boundaries.add((intersection.end - globalStart).clamp(0, localLength).toInt());
    }

    final ordered = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < ordered.length - 1; i++) {
      final start = ordered[i];
      final end = ordered[i + 1];
      if (start >= end) continue;

      final globalSegment = TextSystemRange(globalStart + start, globalStart + end);
      final coveringMarks = block.marks
          .where((mark) => mark.range.containsRange(globalSegment))
          .toList(growable: false);
      TextMark? footnoteMark;
      for (final mark in coveringMarks) {
        if (isFootnoteReferenceMark(mark)) {
          footnoteMark = mark;
          break;
        }
      }
      final segmentText = text.substring(start, end);
      final markedStyle = styleWithMarks(context, baseStyle, coveringMarks);
      final insideInlineMath = inlineMathRanges.any((range) => range.globalRange.containsRange(globalSegment));
      final segmentStyle = insideInlineMath ? inlineMathSourceStyle(markedStyle) : markedStyle;
      spans.add(TextSpan(
        text: footnoteMark == null
            ? segmentText
            : academicFootnoteNumber(int.tryParse(footnoteMark.attributes['number'] ?? '') ?? 0),
        style: segmentStyle,
      ));
    }
    return spans.isEmpty ? <InlineSpan>[TextSpan(text: text, style: baseStyle)] : spans;
  }

  static bool isFootnoteReferenceMark(TextMark mark) {
    return mark.kind == TextMarkKind.link && mark.attributes['role'] == 'footnoteReference';
  }

  static String academicFootnoteNumber(int value) {
    const superscripts = <String, String>{
      '0': '⁰',
      '1': '¹',
      '2': '²',
      '3': '³',
      '4': '⁴',
      '5': '⁵',
      '6': '⁶',
      '7': '⁷',
      '8': '⁸',
      '9': '⁹',
    };
    return value.toString().split('').map((digit) => superscripts[digit] ?? digit).join();
  }

  static TextStyle styleWithMarks(
    BuildContext context,
    TextStyle baseStyle,
    List<TextMark> marks,
  ) {
    var result = baseStyle;
    final colorScheme = Theme.of(context).colorScheme;
    final decorations = <TextDecoration>[];
    Color? decorationColor;
    TextDecorationStyle? decorationStyle;
    double? decorationThickness;

    for (final mark in marks) {
      switch (mark.kind) {
        case TextMarkKind.bold:
          result = result.copyWith(fontWeight: FontWeight.w800);
          break;
        case TextMarkKind.italic:
          result = result.copyWith(fontStyle: FontStyle.italic);
          break;
        case TextMarkKind.underline:
          decorations.add(TextDecoration.underline);
          break;
        case TextMarkKind.strikethrough:
          decorations.add(TextDecoration.lineThrough);
          break;
        case TextMarkKind.highlight:
          result = result.copyWith(backgroundColor: const Color(0x66FFD54F));
          break;
        case TextMarkKind.code:
          result = result.copyWith(
            fontFamily: 'Consolas',
            fontFamilyFallback: const <String>['Cascadia Mono', 'monospace'],
            backgroundColor: const Color(0x1F000000),
          );
          break;
        case TextMarkKind.link:
          decorations.add(TextDecoration.underline);
          decorationColor = colorScheme.primary;
          decorationStyle = TextDecorationStyle.dotted;
          decorationThickness = 1.15;
          result = result.copyWith(color: colorScheme.primary);
          break;
      }
      result = _styleWithTypographicAttributes(result, mark.attributes);
    }

    if (decorations.isNotEmpty) {
      result = result.copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        decorationThickness: decorationThickness,
      );
    }
    return result;
  }

  static TextStyle inlineMathSourceStyle(TextStyle baseStyle) {
    return baseStyle.copyWith(
      fontFamily: 'Consolas',
      fontFamilyFallback: const <String>['Cascadia Mono', 'monospace'],
      color: const Color(0xFF37448D),
    );
  }

  static TextStyle inlineMathRenderedEditingStyle(TextStyle baseStyle, ColorScheme colorScheme) {
    return baseStyle.copyWith(
      color: colorScheme.onSurface,
      fontFamilyFallback: const <String>['Cambria Math', 'STIX Two Math', 'serif'],
    );
  }

  static TextStyle activeInlineAtomSourceStyle(TextStyle baseStyle, ColorScheme colorScheme) {
    return baseStyle.copyWith(
      color: colorScheme.primary,
      fontWeight: FontWeight.w700,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.24),
    );
  }

  static String sameLengthInlineAtomDisplay(String display, int sourceLength) {
    final clean = display.trim().isEmpty ? '□' : display.trim();
    if (sourceLength <= 0) return '';
    if (clean.length == sourceLength) return clean;
    if (clean.length > sourceLength) {
      if (sourceLength == 1) return clean.substring(0, 1);
      final keep = sourceLength - 1;
      return clean.substring(0, keep) + '…';
    }
    return clean + List.filled(sourceLength - clean.length, '⁠').join();
  }

  static String humanReadableInlineMath(String latex) {
    var result = latex.trim();
    if (result.isEmpty) return '□';
    final replacements = <String, String>{
      r'\,': ' ',
      r'\;': ' ',
      r'\:': ' ',
      r'\left': '',
      r'\right': '',
      r'\cdot': '·',
      r'\times': '×',
      r'\rightarrow': '→',
      r'\to': '→',
      r'\infty': '∞',
      r'\leq': '≤',
      r'\geq': '≥',
      r'\neq': '≠',
      r'\approx': '≈',
      r'\sum': '∑',
      r'\prod': '∏',
      r'\int': '∫',
      r'\partial': '∂',
      r'\Delta': 'Δ',
      r'\delta': 'δ',
      r'\alpha': 'α',
      r'\beta': 'β',
      r'\gamma': 'γ',
      r'\lambda': 'λ',
      r'\mu': 'μ',
      r'\pi': 'π',
      r'\rho': 'ρ',
      r'\sigma': 'σ',
      r'\theta': 'θ',
      r'\phi': 'φ',
      r'\omega': 'ω',
    };
    replacements.forEach((from, to) => result = result.replaceAll(from, to));
    result = result.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}'),
      (match) => '${match.group(1)}⁄${match.group(2)}',
    );
    result = result.replaceAllMapped(RegExp(r'_\{([^{}]+)\}'), (match) => toSubscript(match.group(1) ?? ''));
    result = result.replaceAllMapped(RegExp(r'\^\{([^{}]+)\}'), (match) => toSuperscript(match.group(1) ?? ''));
    result = result.replaceAllMapped(RegExp(r'_([A-Za-z0-9+\-=()])'), (match) => toSubscript(match.group(1) ?? ''));
    result = result.replaceAllMapped(RegExp(r'\^([A-Za-z0-9+\-=()])'), (match) => toSuperscript(match.group(1) ?? ''));
    result = result.replaceAllMapped(RegExp(r'\\operatorname\{([^{}]+)\}'), (match) => match.group(1) ?? '');
    result = result.replaceAllMapped(RegExp(r'\\mathrm\{([^{}]+)\}'), (match) => match.group(1) ?? '');
    result = result.replaceAllMapped(RegExp(r'\\text\{([^{}]+)\}'), (match) => match.group(1) ?? '');
    result = result.replaceAll(RegExp(r'\\[A-Za-z]+'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result.isEmpty ? latex.trim() : result;
  }

  static String toSubscript(String value) {
    const map = <String, String>{
      '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
      '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
      '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
      'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ',
      'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ',
      'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
      'v': 'ᵥ', 'x': 'ₓ',
    };
    return value.split('').map((char) => map[char] ?? map[char.toLowerCase()] ?? char).join();
  }

  static String toSuperscript(String value) {
    const map = <String, String>{
      '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
      '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
      '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
      'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ',
      'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ',
      'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ',
      'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
      'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
    };
    return value.split('').map((char) => map[char] ?? map[char.toLowerCase()] ?? char).join();
  }

  static TextStyle _styleWithTypographicAttributes(TextStyle style, Map<String, String> attributes) {
    if (attributes.isEmpty) return style;
    var result = style;
    final fontSize = _doubleAttribute(attributes, const <String>['fontSize', 'fontSizePx', 'size']);
    if (fontSize != null && fontSize > 0) result = result.copyWith(fontSize: fontSize);
    final fontScale = _doubleAttribute(attributes, const <String>['fontScale', 'scale']);
    if (fontScale != null && fontScale > 0) {
      final baseSize = result.fontSize ?? style.fontSize;
      if (baseSize != null) result = result.copyWith(fontSize: baseSize * fontScale);
    }
    final family = attributes['fontFamily']?.trim();
    if (family != null && family.isNotEmpty) result = result.copyWith(fontFamily: family);
    return result;
  }

  static double? _doubleAttribute(Map<String, String> attributes, List<String> keys) {
    for (final key in keys) {
      final raw = attributes[key];
      if (raw == null) continue;
      final value = double.tryParse(raw.trim());
      if (value != null) return value;
    }
    return null;
  }
}

class TextSystemInlineAtomRange {
  const TextSystemInlineAtomRange({required this.localRange, required this.globalRange});

  final TextSystemRange localRange;
  final TextSystemRange globalRange;
}

enum TextSystemInlineAtomRenderKind { math, reference, citation }

class TextSystemInlineAtom {
  const TextSystemInlineAtom({
    required this.id,
    required this.kind,
    required this.blockId,
    required this.blockIndex,
    required this.localRange,
    required this.globalRange,
    required this.sourceText,
    required this.displayText,
    this.latex,
    this.referenceMark,
    this.inlineReference,
  });

  final String id;
  final TextSystemInlineAtomRenderKind kind;
  final String blockId;
  final int blockIndex;
  final TextSystemRange localRange;
  final TextSystemRange globalRange;
  final String sourceText;
  final String displayText;
  final String? latex;
  final TextMark? referenceMark;
  final TextSystemInlineReferenceMark? inlineReference;

  bool get isMath => kind == TextSystemInlineAtomRenderKind.math;
  bool get isReference => kind == TextSystemInlineAtomRenderKind.reference || kind == TextSystemInlineAtomRenderKind.citation;
}
