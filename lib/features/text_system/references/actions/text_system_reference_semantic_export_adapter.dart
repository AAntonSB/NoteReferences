import 'dart:convert';

import 'text_system_reference_action_models.dart';

/// Small semantic rendering adapter for inline reference marks.
///
/// Hook this into Export v2 wherever inline marks/spans are rendered. PDF should
/// continue to render visually from the layout tree; this adapter is for semantic
/// Markdown/LaTeX/Typst/HTML output.
class TextSystemReferenceSemanticExportAdapter {
  const TextSystemReferenceSemanticExportAdapter._();

  static String markdown({
    required String visibleText,
    required TextSystemInlineReferenceMark mark,
  }) {
    switch (mark.kind) {
      case TextSystemReferenceTargetKind.citation:
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
    switch (mark.kind) {
      case TextSystemReferenceTargetKind.citation:
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
    switch (mark.kind) {
      case TextSystemReferenceTargetKind.citation:
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
