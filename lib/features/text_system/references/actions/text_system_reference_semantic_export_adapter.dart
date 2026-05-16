import 'dart:convert';

import 'text_system_reference_action_models.dart';

/// Small semantic rendering adapter for inline reference marks.
///
/// Hook this into Export v2 wherever inline marks/spans are rendered. PDF should
/// continue to render visually from the layout tree; this adapter is for semantic
/// Markdown/LaTeX/Typst/HTML output.
class TextSystemReferenceSemanticExportAdapter {
  const TextSystemReferenceSemanticExportAdapter._();

  static bool _hasPreRenderedCitationText({
    required String visibleText,
    required TextSystemInlineReferenceMark mark,
  }) {
    final citationText = mark.metadata['citationText']?.toString().trim();
    return citationText != null && citationText.isNotEmpty && visibleText.trim() == citationText;
  }

  static bool _isCrossReference(TextSystemInlineReferenceMark mark) {
    return mark.metadata['crossReference'] == true ||
        (mark.metadata['crossReferenceKind']?.toString().trim().isNotEmpty ?? false);
  }

  static String _crossReferenceKind(TextSystemInlineReferenceMark mark) {
    final value = mark.metadata['crossReferenceKind']?.toString().trim().toLowerCase();
    if (value == 'figure' || value == 'table' || value == 'equation') return value!;
    if (mark.kind == TextSystemReferenceTargetKind.figure) return 'figure';
    if (mark.kind == TextSystemReferenceTargetKind.table) return 'table';
    return 'reference';
  }

  static String _crossReferenceLabel(TextSystemInlineReferenceMark mark) {
    if (mark.metadata.containsKey('crossReferenceLabel')) {
      return mark.metadata['crossReferenceLabel']?.toString().trim() ?? '';
    }
    return mark.exportKey.trim();
  }

  static String _crossReferenceNoun(String kind) {
    switch (kind) {
      case 'figure':
        return 'Figure';
      case 'table':
        return 'Table';
      case 'equation':
        return 'Equation';
      default:
        return 'Reference';
    }
  }

  static String markdown({
    required String visibleText,
    required TextSystemInlineReferenceMark mark,
  }) {
    if (_isCrossReference(mark)) {
      final label = _crossReferenceLabel(mark);
      if (label.isEmpty) return _escapeMarkdownText(visibleText);
      return '[${_escapeMarkdownLinkText(visibleText)}](#${_escapeMarkdownUrl(label)})';
    }
    switch (mark.kind) {
      case TextSystemReferenceTargetKind.citation:
        if (_hasPreRenderedCitationText(visibleText: visibleText, mark: mark)) {
          return _escapeMarkdownText(visibleText);
        }
        return '${_escapeMarkdownText(visibleText)} [@${_markdownCitationKey(mark)}]';
      case TextSystemReferenceTargetKind.link:
      case TextSystemReferenceTargetKind.source:
        final href = mark.uri?.toString();
        if (href == null || href.trim().isEmpty) {
          return _escapeMarkdownText(visibleText);
        }
        return '[${_escapeMarkdownLinkText(visibleText)}](${_escapeMarkdownUrl(href)})';
      case TextSystemReferenceTargetKind.document:
      case TextSystemReferenceTargetKind.project:
      case TextSystemReferenceTargetKind.todo:
      case TextSystemReferenceTargetKind.figure:
      case TextSystemReferenceTargetKind.table:
      case TextSystemReferenceTargetKind.unknown:
        return _escapeMarkdownText(visibleText);
    }
  }

  static String latex({
    required String visibleText,
    required TextSystemInlineReferenceMark mark,
  }) {
    if (_isCrossReference(mark)) {
      final label = _crossReferenceLabel(mark);
      if (label.isEmpty) return _escapeLatex(visibleText);
      final kind = _crossReferenceKind(mark);
      if (kind == 'equation') return 'Equation~\\ref{${_latexKey(label)}}';
      return '${_crossReferenceNoun(kind)}~\\ref{${_latexKey(label)}}';
    }
    switch (mark.kind) {
      case TextSystemReferenceTargetKind.citation:
        if (_hasPreRenderedCitationText(visibleText: visibleText, mark: mark)) {
          return _escapeLatex(visibleText);
        }
        return '${_escapeLatex(visibleText)} \\cite{${_latexKey(mark.exportKey)}}';
      case TextSystemReferenceTargetKind.link:
      case TextSystemReferenceTargetKind.source:
        final href = mark.uri?.toString();
        if (href == null || href.trim().isEmpty) {
          return _escapeLatex(visibleText);
        }
        return '\\href{${_escapeLatexUrl(href)}}{${_escapeLatex(visibleText)}}';
      case TextSystemReferenceTargetKind.document:
      case TextSystemReferenceTargetKind.project:
      case TextSystemReferenceTargetKind.todo:
      case TextSystemReferenceTargetKind.figure:
      case TextSystemReferenceTargetKind.table:
      case TextSystemReferenceTargetKind.unknown:
        return _escapeLatex(visibleText);
    }
  }

  static String typst({
    required String visibleText,
    required TextSystemInlineReferenceMark mark,
  }) {
    if (_isCrossReference(mark)) {
      final label = _crossReferenceLabel(mark);
      if (label.isEmpty) return _escapeTypstText(visibleText);
      return '@${_typstKey(label)}';
    }
    switch (mark.kind) {
      case TextSystemReferenceTargetKind.citation:
        if (_hasPreRenderedCitationText(visibleText: visibleText, mark: mark)) {
          return _escapeTypstText(visibleText);
        }
        return '${_escapeTypstText(visibleText)} @${_typstKey(mark.exportKey)}';
      case TextSystemReferenceTargetKind.link:
      case TextSystemReferenceTargetKind.source:
        final href = mark.uri?.toString();
        if (href == null || href.trim().isEmpty) {
          return _escapeTypstText(visibleText);
        }
        return '#link("${_escapeTypstString(href)}")[${_escapeTypstText(visibleText)}]';
      case TextSystemReferenceTargetKind.document:
      case TextSystemReferenceTargetKind.project:
      case TextSystemReferenceTargetKind.todo:
      case TextSystemReferenceTargetKind.figure:
      case TextSystemReferenceTargetKind.table:
      case TextSystemReferenceTargetKind.unknown:
        return _escapeTypstText(visibleText);
    }
  }

  static String html({
    required String visibleText,
    required TextSystemInlineReferenceMark mark,
  }) {
    if (_isCrossReference(mark)) {
      final label = _crossReferenceLabel(mark);
      final kind = _crossReferenceKind(mark);
      if (label.isEmpty) {
        return '<span class="ts-cross-reference ts-cross-reference-missing" data-reference-kind="${_escapeHtmlAttribute(kind)}">${_escapeHtml(visibleText)}</span>';
      }
      return '<a class="ts-cross-reference ts-cross-reference-${_escapeHtmlAttribute(kind)}" href="#${_escapeHtmlAttribute(label)}" data-reference-id="${_escapeHtmlAttribute(mark.id)}" data-reference-kind="${_escapeHtmlAttribute(kind)}">${_escapeHtml(visibleText)}</a>';
    }
    switch (mark.kind) {
      case TextSystemReferenceTargetKind.citation:
        return '<span class="ts-citation" data-reference-id="${_escapeHtmlAttribute(mark.id)}" data-citation-key="${_escapeHtmlAttribute(mark.exportKey)}">${_escapeHtml(visibleText)}</span>';
      case TextSystemReferenceTargetKind.link:
      case TextSystemReferenceTargetKind.source:
        final href = mark.uri?.toString();
        if (href == null || href.trim().isEmpty) {
          return _escapeHtml(visibleText);
        }
        return '<a href="${_escapeHtmlAttribute(href)}" data-reference-id="${_escapeHtmlAttribute(mark.id)}">${_escapeHtml(visibleText)}</a>';
      case TextSystemReferenceTargetKind.document:
      case TextSystemReferenceTargetKind.project:
      case TextSystemReferenceTargetKind.todo:
      case TextSystemReferenceTargetKind.figure:
      case TextSystemReferenceTargetKind.table:
      case TextSystemReferenceTargetKind.unknown:
        return '<span data-reference-id="${_escapeHtmlAttribute(mark.id)}" data-reference-kind="${_escapeHtmlAttribute(mark.kind.id)}">${_escapeHtml(visibleText)}</span>';
    }
  }

  static String debugJson(TextSystemInlineReferenceMark mark) {
    return const JsonEncoder.withIndent('  ').convert(mark.toJson());
  }

  static String _markdownCitationKey(TextSystemInlineReferenceMark mark) {
    return mark.exportKey.replaceAll(RegExp(r'[^A-Za-z0-9_:\-./]'), '');
  }

  static String _latexKey(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9_:\-./]'), '');
  }

  static String _typstKey(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9_:\-./]'), '');
  }

  static String _escapeMarkdownText(String raw) {
    return raw
        .replaceAll(r'\', r'\\')
        .replaceAll('*', r'\*')
        .replaceAll('_', r'\_')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('`', r'\`');
  }

  static String _escapeMarkdownLinkText(String raw) {
    return _escapeMarkdownText(raw);
  }

  static String _escapeMarkdownUrl(String raw) {
    return raw.replaceAll(')', r'\)');
  }

  static String _escapeLatex(String raw) {
    return raw
        .replaceAll(r'\', r'\textbackslash{}')
        .replaceAll('&', r'\&')
        .replaceAll('%', r'\%')
        .replaceAll(r'$', r'\$')
        .replaceAll('#', r'\#')
        .replaceAll('_', r'\_')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('~', r'\textasciitilde{}')
        .replaceAll('^', r'\textasciicircum{}');
  }

  static String _escapeLatexUrl(String raw) {
    return raw.replaceAll(r'\', r'\textbackslash{}').replaceAll('%', r'\%');
  }

  static String _escapeTypstText(String raw) {
    return raw
        .replaceAll(r'\', r'\\')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('*', r'\*')
        .replaceAll('_', r'\_')
        .replaceAll('`', r'\`');
  }

  static String _escapeTypstString(String raw) {
    return raw.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  static String _escapeHtml(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _escapeHtmlAttribute(String raw) => _escapeHtml(raw);
}
