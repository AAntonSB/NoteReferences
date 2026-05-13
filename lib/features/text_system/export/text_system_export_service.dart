import 'package:flutter/widgets.dart' show FontStyle;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import '../export/text_system_export_v2.dart';
import '../page/text_system_layout_tree.dart';
import '../page/text_system_page_furniture.dart';
import '../page/text_system_page_setup.dart';
import '../styles/text_system_document_style.dart';
import '../structure/text_system_document_structure.dart';

enum TextSystemExportFormat {
  markdown,
  pdf,
  latex,
  typst,
  html;

  String get label {
    return switch (this) {
      TextSystemExportFormat.markdown => 'Markdown',
      TextSystemExportFormat.pdf => 'PDF',
      TextSystemExportFormat.latex => 'LaTeX draft',
      TextSystemExportFormat.typst => 'Typst',
      TextSystemExportFormat.html => 'HTML',
    };
  }

  String get fileExtension {
    return switch (this) {
      TextSystemExportFormat.markdown => 'md',
      TextSystemExportFormat.pdf => 'pdf',
      TextSystemExportFormat.latex => 'tex',
      TextSystemExportFormat.typst => 'typ',
      TextSystemExportFormat.html => 'html',
    };
  }
}

class TextSystemExportOptions {
  const TextSystemExportOptions({
    this.pageSetup,
    this.pageFurniture,
    this.layoutTree,
    this.styleSheet,
    this.structure,
    this.includeMetadataHeader = true,
    this.includeFootnotes = true,
    this.useExportV2 = true,
  });

  final TextSystemPageSetup? pageSetup;
  final TextSystemPageFurniture? pageFurniture;
  final TextSystemDocumentLayoutTree? layoutTree;
  final TextSystemDocumentStyleSheet? styleSheet;
  final TextSystemDocumentStructure? structure;
  final bool includeMetadataHeader;
  final bool includeFootnotes;
  final bool useExportV2;
}

class TextSystemExportResult {
  const TextSystemExportResult({
    required this.format,
    required this.fileExtension,
    this.text,
    this.bytes,
    this.notes = const <String>[],
    this.pipelineKind,
  });

  final TextSystemExportFormat format;
  final String fileExtension;
  final String? text;
  final Uint8List? bytes;
  final List<String> notes;
  final TextSystemExportPipelineKind? pipelineKind;

  bool get isBinary => bytes != null;
  bool get isSemantic => pipelineKind == TextSystemExportPipelineKind.semantic;
  bool get isVisual => pipelineKind == TextSystemExportPipelineKind.visual;
}

class TextSystemExportService {
  const TextSystemExportService._();

  static Future<TextSystemExportResult> exportDocument({
    required TextSystemDocument document,
    required TextSystemExportFormat format,
    TextSystemExportOptions options = const TextSystemExportOptions(),
  }) async {
    final semanticDocument = _buildSemanticExportDocument(document, options);

    return switch (format) {
      TextSystemExportFormat.markdown => TextSystemExportResult(
          format: format,
          fileExtension: format.fileExtension,
          text: TextSystemSemanticMarkdownExporter.render(
            semanticDocument,
            includeMetadataHeader: options.includeMetadataHeader,
            includeFootnotes: options.includeFootnotes,
          ),
          pipelineKind: TextSystemExportPipelineKind.semantic,
          notes: const <String>[
            'Export v2 semantic Markdown: headings, lists, todos, quotes, code, links, and footnotes.',
            'Markdown intentionally ignores visual page layout, margins, headers, and page numbers.',
          ],
        ),
      TextSystemExportFormat.latex => TextSystemExportResult(
          format: format,
          fileExtension: format.fileExtension,
          text: TextSystemSemanticLatexExporter.render(
            semanticDocument,
            includeMetadataHeader: options.includeMetadataHeader,
          ),
          pipelineKind: TextSystemExportPipelineKind.semantic,
          notes: const <String>[
            'Export v2 semantic LaTeX: academic/typesetting export, not visual page export.',
            'PDF remains the visual/layout export path.',
          ],
        ),
      TextSystemExportFormat.typst => TextSystemExportResult(
          format: format,
          fileExtension: format.fileExtension,
          text: TextSystemSemanticTypstExporter.render(
            semanticDocument,
            includeMetadataHeader: options.includeMetadataHeader,
          ),
          pipelineKind: TextSystemExportPipelineKind.semantic,
          notes: const <String>[
            'Export v2 semantic Typst: modern typesetting export, not visual page export.',
            'Future pass should add templates, bibliography, and figure/table mapping.',
          ],
        ),
      TextSystemExportFormat.html => TextSystemExportResult(
          format: format,
          fileExtension: format.fileExtension,
          text: TextSystemSemanticHtmlExporter.render(
            semanticDocument,
            includeMetadataHeader: options.includeMetadataHeader,
            includeFootnotes: options.includeFootnotes,
          ),
          pipelineKind: TextSystemExportPipelineKind.semantic,
          notes: const <String>[
            'Export v2 semantic HTML: web/share export for document meaning.',
            'It intentionally does not preserve print page layout.',
          ],
        ),
      TextSystemExportFormat.pdf => TextSystemExportResult(
          format: format,
          fileExtension: format.fileExtension,
          bytes: _toPdfSnapshot(document, options: options),
          pipelineKind: TextSystemExportPipelineKind.visual,
          notes: const <String>[
            'Visual PDF export: renders pages, measured lines, page furniture, list/todo markers, and footnotes from TextSystemDocumentLayoutTree.',
            'Markdown, LaTeX, Typst, and HTML use the semantic export pipeline instead.',
          ],
        ),
    };
  }

  static TextSystemSemanticExportDocument _buildSemanticExportDocument(
    TextSystemDocument document,
    TextSystemExportOptions options,
  ) {
    final pageSetup = options.pageSetup ?? const TextSystemPageSetup();
    final styleSheet = options.styleSheet ?? TextSystemDocumentStyleSheet.academicDefault(pageSetup: pageSetup);
    final structure = options.structure ??
        TextSystemDocumentStructure.build(
          document: document,
          layoutTree: options.layoutTree,
        );

    return TextSystemSemanticExportDocument.fromTextSystem(
      document: document,
      styleSheet: styleSheet,
      structure: structure,
      layoutTree: options.layoutTree,
      includeFootnotes: options.includeFootnotes,
    );
  }

  static String toMarkdown(
    TextSystemDocument document, {
    TextSystemExportOptions options = const TextSystemExportOptions(),
  }) {
    final model = _ExportModel.fromDocument(document);
    final buffer = StringBuffer();

    if (options.includeMetadataHeader) {
      buffer.writeln('# ${document.title.trim().isEmpty ? 'Untitled document' : document.title.trim()}');
      buffer.writeln();
    }

    for (final block in model.bodyBlocks) {
      final rendered = _renderMarkdownBlock(block, model);
      if (rendered.trim().isEmpty) continue;
      buffer.writeln(rendered);
      buffer.writeln();
    }

    if (options.includeFootnotes && model.orderedFootnotes.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln();
      for (final footnote in model.orderedFootnotes) {
        buffer.writeln('[^${footnote.number}]: ${_escapeMarkdownInline(footnote.block.text.trim())}');
      }
      buffer.writeln();
    }

    return buffer.toString().trimRight() + '\n';
  }

  static String toLatexDraft(
    TextSystemDocument document, {
    TextSystemExportOptions options = const TextSystemExportOptions(),
  }) {
    final model = _ExportModel.fromDocument(document);
    final buffer = StringBuffer();

    buffer.writeln(r'\documentclass[12pt]{article}');
    buffer.writeln(r'\usepackage[utf8]{inputenc}');
    buffer.writeln(r'\usepackage[T1]{fontenc}');
    buffer.writeln(r'\usepackage{csquotes}');
    buffer.writeln(r'\usepackage{hyperref}');
    buffer.writeln("\\title{${_escapeLatex(document.title.trim().isEmpty ? 'Untitled document' : document.title.trim())}}");
    buffer.writeln(r'\begin{document}');
    buffer.writeln(r'\maketitle');
    buffer.writeln();

    var inItemize = false;
    var inEnumerate = false;

    void closeLists() {
      if (inItemize) {
        buffer.writeln(r'\end{itemize}');
        inItemize = false;
      }
      if (inEnumerate) {
        buffer.writeln(r'\end{enumerate}');
        inEnumerate = false;
      }
    }

    for (final block in model.bodyBlocks) {
      if (block.type != TextSystemBlockType.listItem) {
        closeLists();
      }

      switch (block.type) {
        case TextSystemBlockType.heading:
          final level = block.level ?? 1;
          final command = level <= 1
              ? 'section'
              : level == 2
                  ? 'subsection'
                  : 'subsubsection';
          buffer.writeln('\\$command{${_renderLatexInline(block, model)}}');
          buffer.writeln();
          break;
        case TextSystemBlockType.paragraph:
          buffer.writeln(_renderLatexInline(block, model));
          buffer.writeln();
          break;
        case TextSystemBlockType.listItem:
          final ordered = block.metadata['ordered'] == true;
          if (ordered && !inEnumerate) {
            if (inItemize) {
              buffer.writeln(r'\end{itemize}');
              inItemize = false;
            }
            buffer.writeln(r'\begin{enumerate}');
            inEnumerate = true;
          } else if (!ordered && !inItemize) {
            if (inEnumerate) {
              buffer.writeln(r'\end{enumerate}');
              inEnumerate = false;
            }
            buffer.writeln(r'\begin{itemize}');
            inItemize = true;
          }
          buffer.writeln(r'\item ' + _renderLatexInline(block, model));
          break;
        case TextSystemBlockType.todo:
          buffer.writeln(r'\noindent $\square$ ' + _renderLatexInline(block, model));
          buffer.writeln();
          break;
        case TextSystemBlockType.quote:
          buffer.writeln(r'\begin{quote}');
          buffer.writeln(_renderLatexInline(block, model));
          buffer.writeln(r'\end{quote}');
          buffer.writeln();
          break;
        case TextSystemBlockType.code:
          buffer.writeln(r'\begin{verbatim}');
          buffer.writeln(block.text);
          buffer.writeln(r'\end{verbatim}');
          buffer.writeln();
          break;
        case TextSystemBlockType.divider:
          final kind = block.metadata['kind'];
          if (kind == 'pageBreak') {
            buffer.writeln(r'\newpage');
          } else if (kind == 'sectionBreak') {
            buffer.writeln(r'\clearpage');
          }
          buffer.writeln();
          break;
        case TextSystemBlockType.custom:
          break;
      }
    }

    closeLists();
    buffer.writeln(r'\end{document}');
    return buffer.toString();
  }

  static String toTypstDraft(
    TextSystemDocument document, {
    TextSystemExportOptions options = const TextSystemExportOptions(),
  }) {
    final model = _ExportModel.fromDocument(document);
    final buffer = StringBuffer();

    buffer.writeln('// Generated by TextSystem export foundation.');
    buffer.writeln('#set document(title: "${_escapeTypstString(document.title.trim().isEmpty ? 'Untitled document' : document.title.trim())}")');
    buffer.writeln('#set text(font: "Times New Roman", size: 12pt)');
    buffer.writeln();
    buffer.writeln('= ${_escapeTypst(document.title.trim().isEmpty ? 'Untitled document' : document.title.trim())}');
    buffer.writeln();

    for (final block in model.bodyBlocks) {
      switch (block.type) {
        case TextSystemBlockType.heading:
          final level = (block.level ?? 1).clamp(1, 6).toInt();
          buffer.writeln('${List.filled(level, '=').join()} ${_renderTypstInline(block, model)}');
          buffer.writeln();
          break;
        case TextSystemBlockType.paragraph:
          buffer.writeln(_renderTypstInline(block, model));
          buffer.writeln();
          break;
        case TextSystemBlockType.listItem:
          final ordered = block.metadata['ordered'] == true;
          buffer.writeln('${ordered ? '+ ' : '- '}${_renderTypstInline(block, model)}');
          break;
        case TextSystemBlockType.todo:
          buffer.writeln('- [${block.checked == true ? 'x' : ' '}] ${_renderTypstInline(block, model)}');
          break;
        case TextSystemBlockType.quote:
          buffer.writeln('#quote[');
          buffer.writeln(_renderTypstInline(block, model));
          buffer.writeln(']');
          buffer.writeln();
          break;
        case TextSystemBlockType.code:
          buffer.writeln('```');
          buffer.writeln(block.text);
          buffer.writeln('```');
          buffer.writeln();
          break;
        case TextSystemBlockType.divider:
          final kind = block.metadata['kind'];
          if (kind == 'pageBreak' || kind == 'sectionBreak') {
            buffer.writeln('#pagebreak()');
            buffer.writeln();
          }
          break;
        case TextSystemBlockType.custom:
          break;
      }
    }

    return buffer.toString();
  }

  static Uint8List _toPdfSnapshot(
    TextSystemDocument document, {
    required TextSystemExportOptions options,
  }) {
    final layoutTree = options.layoutTree;
    if (layoutTree != null && layoutTree.pages.isNotEmpty) {
      return _toPdfFromLayoutTree(
        document: document,
        layoutTree: layoutTree,
        options: options,
      );
    }

    final pageSetup = options.pageSetup ?? const TextSystemPageSetup();
    final pageFurniture = options.pageFurniture ?? const TextSystemPageFurniture.defaults();
    final model = _ExportModel.fromDocument(document);

    final pageWidthPt = _mmToPt(pageSetup.pageWidthMm);
    final pageHeightPt = _mmToPt(pageSetup.pageHeightMm);
    final margins = _PdfMargins.fromPageSetup(pageSetup);
    final contentWidth = math.max(72.0, pageWidthPt - margins.left - margins.right);
    final contentBottom = pageHeightPt - margins.bottom;

    final pdf = PdfDocument();
    pdf.pageSettings.size = Size(pageWidthPt, pageHeightPt);
    pdf.pageSettings.margins.all = 0;

    final state = _PdfExportState(
      document: document,
      model: model,
      pdf: pdf,
      pageSetup: pageSetup,
      pageFurniture: pageFurniture,
      margins: margins,
      contentWidth: contentWidth,
      contentBottom: contentBottom,
    );

    state.startPage();

    for (final block in model.bodyBlocks) {
      if (block.type == TextSystemBlockType.custom) continue;

      if (block.type == TextSystemBlockType.divider) {
        final kind = block.metadata['kind'];
        if (kind == 'pageBreak') {
          state.startPage();
          continue;
        }
        if (kind == 'sectionBreak') {
          final restart = block.metadata['restartPageNumbering'] != false;
          final rawStartAt = block.metadata['pageNumberStartAt'];
          state.startPage(
            startsSection: true,
            logicalPageStartAt: restart && rawStartAt is int ? rawStartAt : null,
          );
          continue;
        }
      }

      state.drawBlock(block);
    }

    state.finishCurrentPage();

    final bytes = Uint8List.fromList(pdf.saveSync());
    pdf.dispose();
    return bytes;
  }


  static Uint8List _toPdfFromLayoutTree({
    required TextSystemDocument document,
    required TextSystemDocumentLayoutTree layoutTree,
    required TextSystemExportOptions options,
  }) {
    final pdf = PdfDocument();
    pdf.pageSettings.size = Size(
      _mmToPt(layoutTree.pageSetup.pageWidthMm),
      _mmToPt(layoutTree.pageSetup.pageHeightMm),
    );
    pdf.pageSettings.margins.all = 0;

    final renderer = _PdfLayoutTreeRenderer(
      document: document,
      layoutTree: layoutTree,
      pageFurniture: options.pageFurniture ?? layoutTree.pageFurniture,
      pdf: pdf,
    );
    renderer.render();

    final bytes = Uint8List.fromList(pdf.saveSync());
    pdf.dispose();
    return bytes;
  }


  static String _plainAcademicText(TextSystemDocument document) {
    final model = _ExportModel.fromDocument(document);
    final buffer = StringBuffer();

    for (final block in model.bodyBlocks) {
      final text = _renderPlainInline(block, model);
      switch (block.type) {
        case TextSystemBlockType.heading:
          buffer.writeln(text.toUpperCase());
          buffer.writeln();
          break;
        case TextSystemBlockType.listItem:
          buffer.writeln('${block.metadata['ordered'] == true ? '1.' : '•'} $text');
          break;
        case TextSystemBlockType.todo:
          buffer.writeln('${block.checked == true ? '[x]' : '[ ]'} $text');
          break;
        case TextSystemBlockType.quote:
          buffer.writeln('“$text”');
          buffer.writeln();
          break;
        case TextSystemBlockType.code:
          buffer.writeln(block.text);
          buffer.writeln();
          break;
        case TextSystemBlockType.divider:
          final kind = block.metadata['kind'];
          if (kind == 'pageBreak' || kind == 'sectionBreak') {
            buffer.writeln();
            buffer.writeln('---');
            buffer.writeln();
          }
          break;
        case TextSystemBlockType.paragraph:
          buffer.writeln(text);
          buffer.writeln();
          break;
        case TextSystemBlockType.custom:
          break;
      }
    }

    if (model.orderedFootnotes.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('____________________________');
      for (final footnote in model.orderedFootnotes) {
        buffer.writeln('${footnote.number}. ${footnote.block.text}');
      }
    }

    return buffer.toString();
  }

  static String _renderMarkdownBlock(TextSystemBlock block, _ExportModel model) {
    final text = _renderMarkdownInline(block, model);
    return switch (block.type) {
      TextSystemBlockType.heading => '${List.filled((block.level ?? 1).clamp(1, 6).toInt(), '#').join()} $text',
      TextSystemBlockType.paragraph => text,
      TextSystemBlockType.listItem => '${block.metadata['ordered'] == true ? '1.' : '-'} $text',
      TextSystemBlockType.todo => '- [${block.checked == true ? 'x' : ' '}] $text',
      TextSystemBlockType.quote => '> $text',
      TextSystemBlockType.code => '```\n${block.text}\n```',
      TextSystemBlockType.divider => block.metadata['kind'] == 'sectionBreak'
          ? '\n<!-- section break -->\n'
          : block.metadata['kind'] == 'pageBreak'
              ? '\n<!-- page break -->\n'
              : '---',
      TextSystemBlockType.custom => '',
    };
  }

  static String _renderPlainInline(TextSystemBlock block, _ExportModel model) {
    return _renderInlineSegments(
      block,
      model,
      normal: (text) => text,
      footnote: (number, id) => '[$number]',
      bold: (text) => text,
      italic: (text) => text,
      underline: (text) => text,
      code: (text) => text,
      highlight: (text) => text,
      link: (text, url) => text,
    );
  }

  static String _renderMarkdownInline(TextSystemBlock block, _ExportModel model) {
    return _renderInlineSegments(
      block,
      model,
      normal: _escapeMarkdownInline,
      footnote: (number, id) => '[^$number]',
      bold: (text) => '**${_escapeMarkdownInline(text)}**',
      italic: (text) => '*${_escapeMarkdownInline(text)}*',
      underline: _escapeMarkdownInline,
      code: (text) => '`${text.replaceAll('`', r'\`')}`',
      highlight: (text) => '==${_escapeMarkdownInline(text)}==',
      link: (text, url) => url == null || url.isEmpty
          ? _escapeMarkdownInline(text)
          : '[${_escapeMarkdownInline(text)}]($url)',
    );
  }

  static String _renderLatexInline(TextSystemBlock block, _ExportModel model) {
    return _renderInlineSegments(
      block,
      model,
      normal: _escapeLatex,
      footnote: (number, id) => '\\footnote{${_escapeLatex(model.footnoteText(id))}}',
      bold: (text) => '\\textbf{${_escapeLatex(text)}}',
      italic: (text) => '\\emph{${_escapeLatex(text)}}',
      underline: _escapeLatex,
      code: (text) => '\\texttt{${_escapeLatex(text)}}',
      highlight: _escapeLatex,
      link: (text, url) => url == null || url.isEmpty
          ? _escapeLatex(text)
          : '\\href{${_escapeLatex(url)}}{${_escapeLatex(text)}}',
    );
  }

  static String _renderTypstInline(TextSystemBlock block, _ExportModel model) {
    return _renderInlineSegments(
      block,
      model,
      normal: _escapeTypst,
      footnote: (number, id) => '#footnote[${_escapeTypst(model.footnoteText(id))}]',
      bold: (text) => '*${_escapeTypst(text)}*',
      italic: (text) => '_${_escapeTypst(text)}_',
      underline: _escapeTypst,
      code: (text) => '`$text`',
      highlight: _escapeTypst,
      link: (text, url) => url == null || url.isEmpty
          ? _escapeTypst(text)
          : '#link("${_escapeTypstString(url)}")[${_escapeTypst(text)}]',
    );
  }

  static String _renderInlineSegments(
    TextSystemBlock block,
    _ExportModel model, {
    required String Function(String text) normal,
    required String Function(int number, String footnoteId) footnote,
    required String Function(String text) bold,
    required String Function(String text) italic,
    required String Function(String text) underline,
    required String Function(String text) code,
    required String Function(String text) highlight,
    required String Function(String text, String? url) link,
  }) {
    if (block.text.isEmpty) return '';

    final boundaries = <int>{0, block.text.length};
    for (final mark in block.marks) {
      boundaries.add(mark.range.start.clamp(0, block.text.length).toInt());
      boundaries.add(mark.range.end.clamp(0, block.text.length).toInt());
    }
    final ordered = boundaries.toList()..sort();
    final buffer = StringBuffer();

    for (var i = 0; i < ordered.length - 1; i++) {
      final start = ordered[i];
      final end = ordered[i + 1];
      if (start >= end) continue;

      final segment = block.text.substring(start, end);
      final marks = block.marks
          .where((mark) => mark.range.start <= start && mark.range.end >= end)
          .toList(growable: false);

      final footnoteMark = marks.where(_isFootnoteReferenceMark).firstOrNull;
      if (footnoteMark != null) {
        final id = footnoteMark.attributes['footnoteId'] ?? '';
        final number = int.tryParse(footnoteMark.attributes['number'] ?? '') ?? model.numberForFootnoteId(id);
        buffer.write(footnote(number, id));
        continue;
      }

      var rendered = normal(segment);
      for (final mark in marks) {
        switch (mark.kind) {
          case TextMarkKind.bold:
            rendered = bold(segment);
            break;
          case TextMarkKind.italic:
            rendered = italic(segment);
            break;
          case TextMarkKind.underline:
            rendered = underline(segment);
            break;
          case TextMarkKind.highlight:
            rendered = highlight(segment);
            break;
          case TextMarkKind.code:
            rendered = code(segment);
            break;
          case TextMarkKind.link:
            rendered = link(segment, mark.attributes['href'] ?? mark.attributes['url']);
            break;
          case TextMarkKind.strikethrough:
            break;
        }
      }
      buffer.write(rendered);
    }

    return buffer.toString().replaceAll('\uFFFC', '');
  }

  static bool _isFootnoteReferenceMark(TextMark mark) {
    return mark.kind == TextMarkKind.link && mark.attributes['role'] == 'footnoteReference';
  }

  static String _escapeMarkdownInline(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('[', r'\[').replaceAll(']', r'\]');
  }

  static String _escapeLatex(String value) {
    return value
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

  static String _escapeTypst(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('*', r'\*')
        .replaceAll('_', r'\_')
        .replaceAll('#', r'\#');
  }

  static String _escapeTypstString(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  static double _mmToPt(double mm) => mm * 72.0 / 25.4;
}



class _PdfLayoutTreeRenderer {
  _PdfLayoutTreeRenderer({
    required this.document,
    required this.layoutTree,
    required this.pageFurniture,
    required this.pdf,
  })  : blocksById = <String, TextSystemBlock>{
          for (final block in document.blocks) block.id: block,
        },
        styleSheet = TextSystemDocumentStyleSheet.academicDefault(pageSetup: layoutTree.pageSetup),
        scaleX = TextSystemExportService._mmToPt(layoutTree.pageSetup.pageWidthMm) /
            layoutTree.visualPageWidthPx,
        scaleY = TextSystemExportService._mmToPt(layoutTree.pageSetup.pageHeightMm) /
            layoutTree.visualPageHeightPx;

  final TextSystemDocument document;
  final TextSystemDocumentLayoutTree layoutTree;
  final TextSystemPageFurniture pageFurniture;
  final PdfDocument pdf;
  final Map<String, TextSystemBlock> blocksById;
  final TextSystemDocumentStyleSheet styleSheet;
  final double scaleX;
  final double scaleY;

  void render() {
    if (layoutTree.pages.isEmpty) {
      pdf.pages.add();
      return;
    }

    for (final layoutPage in layoutTree.pages) {
      final page = pdf.pages.add();
      _drawPageFurniture(page, layoutPage);
      _drawMeasuredLines(page, layoutPage);
      _drawFootnotes(page, layoutPage);
    }
  }

  void _drawMeasuredLines(PdfPage page, TextSystemLayoutPage layoutPage) {
    final markerDrawnForBlock = <String>{};

    for (final line in layoutPage.lineFragments) {
      final block = blocksById[line.blockId];
      if (block == null || block.type == TextSystemBlockType.custom) continue;
      if (block.type == TextSystemBlockType.divider) continue;

      final rect = _scaleRect(line.rect);
      if (rect.width <= 0 || rect.height <= 0) continue;

      final style = _styleForLine(line, block);
      final text = line.text.replaceAll('\uFFFC', '').trimRight();

      final fragmentStart = _fragmentStartForLine(layoutPage, line);
      final shouldDrawMarker = fragmentStart != null &&
          line.textStartOffset == fragmentStart &&
          line.textStartOffset == 0 &&
          markerDrawnForBlock.add(line.blockId);
      final marker = shouldDrawMarker ? _markerForBlock(block) : null;
      final renderedText = marker == null ? text : '$marker $text';
      final textRect = marker == null
          ? rect
          : Rect.fromLTWH(
              math.max(0.0, rect.left - 26.0 * scaleX),
              rect.top,
              rect.width + 26.0 * scaleX,
              rect.height,
            );

      if (renderedText.isEmpty) continue;

      page.graphics.drawString(
        renderedText,
        style.font,
        brush: style.brush,
        bounds: textRect,
      );
    }
  }

  int? _fragmentStartForLine(
    TextSystemLayoutPage page,
    TextSystemLayoutLineFragment line,
  ) {
    for (final fragment in page.blockFragments) {
      if (fragment.blockId != line.blockId) continue;
      if (line.textStartOffset >= fragment.textStartOffset &&
          line.textStartOffset <= fragment.textEndOffset) {
        return fragment.textStartOffset;
      }
    }
    return null;
  }

  String? _markerForBlock(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.listItem =>
        block.metadata['ordered'] == true ? '${_orderedListNumberFor(block)}.' : '•',
      TextSystemBlockType.todo => block.checked == true ? '[x]' : '[ ]',
      _ => null,
    };
  }

  int _orderedListNumberFor(TextSystemBlock block) {
    final blocks = document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == block.id);
    if (index < 0) return 1;

    final groupId = block.metadata['listGroupId'];
    var count = 1;
    for (var i = index - 1; i >= 0; i--) {
      final previous = blocks[i];
      if (previous.type != TextSystemBlockType.listItem ||
          previous.metadata['ordered'] != true) {
        break;
      }
      if (groupId != null && previous.metadata['listGroupId'] != groupId) {
        break;
      }
      count += 1;
    }

    return count;
  }

  void _drawFootnotes(PdfPage page, TextSystemLayoutPage layoutPage) {
    if (layoutPage.footnotes.isEmpty) return;

    final footnoteArea = _scaleRect(layoutPage.footnoteRect);
    final ruleY = footnoteArea.top;
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(80, 80, 80)),
      bounds: Rect.fromLTWH(footnoteArea.left, ruleY, 96.0 * scaleX, 0.55),
    );

    final numberFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      math.max(6.0, 8.0 * scaleY),
      style: PdfFontStyle.bold,
    );
    final textFont = PdfStandardFont(
      PdfFontFamily.timesRoman,
      math.max(7.0, 9.2 * scaleY),
    );

    for (final footnote in layoutPage.footnotes) {
      final rect = _scaleRect(footnote.rect);
      if (rect.width <= 0 || rect.height <= 0) continue;

      final y = math.max(ruleY + 7.0, rect.top);
      page.graphics.drawString(
        '${footnote.number}.',
        numberFont,
        brush: PdfBrushes.black,
        bounds: Rect.fromLTWH(rect.left, y, 18.0 * scaleX, rect.height),
      );
      page.graphics.drawString(
        footnote.text.trim(),
        textFont,
        brush: PdfBrushes.black,
        bounds: Rect.fromLTWH(rect.left + 20.0 * scaleX, y, rect.width - 20.0 * scaleX, rect.height),
      );
    }
  }

  void _drawPageFurniture(PdfPage page, TextSystemLayoutPage layoutPage) {
    final headerFooter = pageFurniture.headerFooter;
    if (!headerFooter.enabled) return;

    final header = headerFooter.zoneFor(
      kind: TextSystemHeaderFooterZoneKind.header,
      physicalPageNumber: layoutPage.physicalPageNumber,
    );
    final footer = headerFooter.zoneFor(
      kind: TextSystemHeaderFooterZoneKind.footer,
      physicalPageNumber: layoutPage.physicalPageNumber,
    );

    final font = PdfStandardFont(PdfFontFamily.timesRoman, math.max(6.5, 9.0 * scaleY));
    final brush = PdfSolidBrush(PdfColor(105, 105, 105));

    if (header.enabled && header.text.trim().isNotEmpty) {
      page.graphics.drawString(
        _resolveTokens(header.text, layoutPage),
        font,
        brush: brush,
        bounds: _scaleRect(layoutPage.headerRect),
      );
    }

    if (footer.enabled && footer.text.trim().isNotEmpty) {
      page.graphics.drawString(
        _resolveTokens(footer.text, layoutPage),
        font,
        brush: brush,
        bounds: _scaleRect(layoutPage.footerRect),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
    }
  }

  String _resolveTokens(String value, TextSystemLayoutPage page) {
    final title = document.title.trim().isEmpty ? 'Untitled document' : document.title.trim();
    return value
        .replaceAll('{{pageNumber}}', '${page.logicalPageNumber}')
        .replaceAll('{{documentTitle}}', title)
        .replaceAll('{{sectionTitle}}', _sectionTitleForPage(page));
  }

  String _sectionTitleForPage(TextSystemLayoutPage page) {
    if (page.blockFragments.isEmpty) {
      return document.title.trim().isEmpty ? 'Section' : document.title.trim();
    }

    final firstBlockIndex = page.blockFragments
        .map((fragment) => fragment.blockIndex)
        .fold<int>(page.blockFragments.first.blockIndex, math.min);

    for (var i = firstBlockIndex; i >= 0; i--) {
      final block = document.blocks[i];
      if (block.type == TextSystemBlockType.heading && block.text.trim().isNotEmpty) {
        return block.text.trim();
      }
    }

    return document.title.trim().isEmpty ? 'Section' : document.title.trim();
  }

  _PdfTreeTextStyle _styleForLine(
    TextSystemLayoutLineFragment line,
    TextSystemBlock block,
  ) {
    final paragraphStyle = styleSheet.styleForId(line.styleId);
    final spec = paragraphStyle.textStyle;
    final pdfFontSize = math.max(6.0, spec.fontSize * scaleY);
    final family = spec.fontFamily.toLowerCase().contains('consolas') ||
            spec.fontFamily.toLowerCase().contains('courier')
        ? PdfFontFamily.courier
        : PdfFontFamily.timesRoman;

    var pdfStyle = PdfFontStyle.regular;
    if (spec.fontWeight.value >= 700) {
      pdfStyle = PdfFontStyle.bold;
    } else if (spec.fontStyle == FontStyle.italic) {
      pdfStyle = PdfFontStyle.italic;
    }

    return _PdfTreeTextStyle(
      font: PdfStandardFont(family, pdfFontSize, style: pdfStyle),
      brush: PdfBrushes.black,
    );
  }

  Rect _scaleRect(Rect rect) {
    return Rect.fromLTWH(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.width * scaleX,
      rect.height * scaleY,
    );
  }
}

class _PdfTreeTextStyle {
  const _PdfTreeTextStyle({
    required this.font,
    required this.brush,
  });

  final PdfFont font;
  final PdfBrush brush;
}


class _PdfMargins {
  const _PdfMargins({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  factory _PdfMargins.fromPageSetup(TextSystemPageSetup pageSetup) {
    return _PdfMargins(
      top: TextSystemExportService._mmToPt(pageSetup.margins.topMm),
      right: TextSystemExportService._mmToPt(pageSetup.margins.rightMm),
      bottom: TextSystemExportService._mmToPt(pageSetup.margins.bottomMm),
      left: TextSystemExportService._mmToPt(pageSetup.margins.leftMm),
    );
  }

  final double top;
  final double right;
  final double bottom;
  final double left;
}

class _PdfExportState {
  _PdfExportState({
    required this.document,
    required this.model,
    required this.pdf,
    required this.pageSetup,
    required this.pageFurniture,
    required this.margins,
    required this.contentWidth,
    required this.contentBottom,
  });

  final TextSystemDocument document;
  final _ExportModel model;
  final PdfDocument pdf;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final _PdfMargins margins;
  final double contentWidth;
  final double contentBottom;

  PdfPage? _page;
  double _cursorY = 0;
  int _physicalPageNumber = 0;
  int _logicalPageNumber = 0;
  final List<_ExportFootnote> _pageFootnotes = <_ExportFootnote>[];

  PdfPage get page => _page!;

  void startPage({
    bool startsSection = false,
    int? logicalPageStartAt,
  }) {
    if (_page != null) {
      finishCurrentPage();
    }

    _page = pdf.pages.add();
    _physicalPageNumber += 1;
    _logicalPageNumber = startsSection
        ? (logicalPageStartAt ?? 1)
        : (_logicalPageNumber <= 0 ? 1 : _logicalPageNumber + 1);
    _cursorY = margins.top;

    _drawPageFurniture();
  }

  void finishCurrentPage() {
    if (_page == null) return;
    _drawFootnotes();
    _pageFootnotes.clear();
  }

  void drawBlock(TextSystemBlock block) {
    final style = _styleForBlock(block);
    final spacingAfter = _spacingAfter(block, style.fontSize);
    final text = _textForBlock(block);
    final marker = _markerForBlock(block);

    if (text.trim().isEmpty && block.type != TextSystemBlockType.code) {
      _ensureVerticalSpace(style.lineHeight + spacingAfter);
      _cursorY += style.lineHeight + spacingAfter;
      return;
    }

    final markerWidth = marker == null ? 0.0 : 22.0;
    final textLeft = margins.left + markerWidth;
    final textWidth = contentWidth - markerWidth;
    final lines = _wrapLines(text, textWidth, style.fontSize);
    final height = math.max(style.lineHeight, lines.length * style.lineHeight) + spacingAfter;

    _ensureVerticalSpace(height);

    if (marker != null) {
      page.graphics.drawString(
        marker,
        style.font,
        brush: PdfBrushes.black,
        bounds: Rect.fromLTWH(margins.left, _cursorY, markerWidth - 4, style.lineHeight),
      );
    }

    for (final line in lines) {
      page.graphics.drawString(
        line,
        style.font,
        brush: PdfBrushes.black,
        bounds: Rect.fromLTWH(textLeft, _cursorY, textWidth, style.lineHeight),
      );
      _cursorY += style.lineHeight;
    }

    if (block.type == TextSystemBlockType.heading && (block.level ?? 2) <= 1) {
      page.graphics.drawRectangle(
        brush: PdfSolidBrush(PdfColor(210, 210, 210)),
        bounds: Rect.fromLTWH(margins.left, _cursorY + 1, contentWidth, 0.45),
      );
    }

    _cursorY += spacingAfter;

    for (final footnote in model.footnotesForBlock(block)) {
      if (!_pageFootnotes.any((candidate) => candidate.id == footnote.id)) {
        _pageFootnotes.add(footnote);
      }
    }
  }

  void _ensureVerticalSpace(double requiredHeight) {
    final reserveForFootnotes = _pageFootnotes.isEmpty ? 0.0 : math.min(104.0, 24.0 + _pageFootnotes.length * 24.0);
    if (_cursorY + requiredHeight <= contentBottom - reserveForFootnotes) return;
    startPage();
  }

  String _textForBlock(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.heading ||
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote => TextSystemExportService._renderPlainInline(block, model),
      TextSystemBlockType.code => block.text,
      TextSystemBlockType.divider => '',
      TextSystemBlockType.custom => '',
    };
  }

  String? _markerForBlock(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.listItem => block.metadata['ordered'] == true ? '${_orderedListNumberFor(block)}.' : '•',
      TextSystemBlockType.todo => block.checked == true ? '☑' : '☐',
      _ => null,
    };
  }

  int _orderedListNumberFor(TextSystemBlock block) {
    final blocks = document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == block.id);
    if (index < 0) return 1;

    final groupId = block.metadata['listGroupId'];
    var count = 1;
    for (var i = index - 1; i >= 0; i--) {
      final previous = blocks[i];
      if (previous.type != TextSystemBlockType.listItem || previous.metadata['ordered'] != true) break;
      if (groupId != null && previous.metadata['listGroupId'] != groupId) break;
      count += 1;
    }

    return count;
  }

  _PdfBlockStyle _styleForBlock(TextSystemBlock block) {
    final baseSize = pageSetup.defaultFontSize;
    return switch (block.type) {
      TextSystemBlockType.heading => switch (block.level ?? 2) {
          1 => _PdfBlockStyle(
              font: PdfStandardFont(PdfFontFamily.timesRoman, baseSize + 4, style: PdfFontStyle.bold),
              fontSize: baseSize + 4,
              lineHeight: (baseSize + 4) * 1.20,
            ),
          2 => _PdfBlockStyle(
              font: PdfStandardFont(PdfFontFamily.timesRoman, baseSize + 2, style: PdfFontStyle.bold),
              fontSize: baseSize + 2,
              lineHeight: (baseSize + 2) * 1.18,
            ),
          _ => _PdfBlockStyle(
              font: PdfStandardFont(PdfFontFamily.timesRoman, baseSize + 1, style: PdfFontStyle.bold),
              fontSize: baseSize + 1,
              lineHeight: (baseSize + 1) * 1.16,
            ),
        },
      TextSystemBlockType.quote => _PdfBlockStyle(
          font: PdfStandardFont(PdfFontFamily.timesRoman, baseSize, style: PdfFontStyle.italic),
          fontSize: baseSize,
          lineHeight: baseSize * pageSetup.lineSpacing,
        ),
      TextSystemBlockType.code => _PdfBlockStyle(
          font: PdfStandardFont(PdfFontFamily.courier, baseSize * 0.92),
          fontSize: baseSize * 0.92,
          lineHeight: baseSize * 1.30,
        ),
      _ => _PdfBlockStyle(
          font: PdfStandardFont(PdfFontFamily.timesRoman, baseSize),
          fontSize: baseSize,
          lineHeight: baseSize * pageSetup.lineSpacing,
        ),
    };
  }

  double _spacingAfter(TextSystemBlock block, double fontSize) {
    final paragraphSpacing = math.max(5.0, fontSize * 0.58);
    return switch (block.type) {
      TextSystemBlockType.heading => paragraphSpacing + fontSize * 0.16,
      TextSystemBlockType.listItem || TextSystemBlockType.todo => paragraphSpacing * 0.28,
      TextSystemBlockType.code => paragraphSpacing * 0.70,
      _ => paragraphSpacing,
    };
  }

  List<String> _wrapLines(String text, double width, double fontSize) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final paragraphs = normalized.split('\n');
    final maxChars = math.max(12, (width / (fontSize * 0.48)).floor());
    final result = <String>[];

    for (final paragraph in paragraphs) {
      final words = paragraph.trimRight().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
      if (words.isEmpty) {
        result.add('');
        continue;
      }

      final line = StringBuffer();
      for (final word in words) {
        if (line.isEmpty) {
          line.write(word);
          continue;
        }

        if (line.length + 1 + word.length > maxChars) {
          result.add(line.toString());
          line
            ..clear()
            ..write(word);
        } else {
          line
            ..write(' ')
            ..write(word);
        }
      }

      if (line.isNotEmpty) {
        result.add(line.toString());
      }
    }

    return result.isEmpty ? <String>[''] : result;
  }

  void _drawFootnotes() {
    if (_page == null || _pageFootnotes.isEmpty) return;

    final font = PdfStandardFont(PdfFontFamily.timesRoman, 9.2);
    final lineHeight = 10.8;
    final startY = math.max(
      _cursorY + 8,
      contentBottom - math.min(110.0, 16.0 + _pageFootnotes.length * lineHeight * 2),
    );

    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(80, 80, 80)),
      bounds: Rect.fromLTWH(margins.left, startY, 96, 0.55),
    );

    var y = startY + 7;
    for (final footnote in _pageFootnotes) {
      final prefix = '${footnote.number}. ';
      final text = '$prefix${footnote.block.text.trim()}';
      final lines = _wrapLines(text, contentWidth, 9.2);
      for (final line in lines.take(2)) {
        page.graphics.drawString(
          line,
          font,
          brush: PdfBrushes.black,
          bounds: Rect.fromLTWH(margins.left, y, contentWidth, lineHeight),
        );
        y += lineHeight;
      }
    }
  }

  void _drawPageFurniture() {
    final headerFooter = pageFurniture.headerFooter;
    if (!headerFooter.enabled) return;

    final header = headerFooter.zoneFor(
      kind: TextSystemHeaderFooterZoneKind.header,
      physicalPageNumber: _physicalPageNumber,
    );
    final footer = headerFooter.zoneFor(
      kind: TextSystemHeaderFooterZoneKind.footer,
      physicalPageNumber: _physicalPageNumber,
    );

    final font = PdfStandardFont(PdfFontFamily.timesRoman, 9);
    final brush = PdfSolidBrush(PdfColor(105, 105, 105));

    if (header.enabled && header.text.trim().isNotEmpty) {
      page.graphics.drawString(
        _resolveTokens(header.text),
        font,
        brush: brush,
        bounds: Rect.fromLTWH(margins.left, math.max(8, margins.top * 0.40), contentWidth, 12),
      );
    }

    if (footer.enabled && footer.text.trim().isNotEmpty) {
      page.graphics.drawString(
        _resolveTokens(footer.text),
        font,
        brush: brush,
        bounds: Rect.fromLTWH(margins.left, page.getClientSize().height - math.max(18, margins.bottom * 0.52), contentWidth, 12),
        format: PdfStringFormat(alignment: PdfTextAlignment.center),
      );
    }
  }

  String _resolveTokens(String value) {
    final title = document.title.trim().isEmpty ? 'Untitled document' : document.title.trim();
    return value
        .replaceAll('{{pageNumber}}', '$_logicalPageNumber')
        .replaceAll('{{documentTitle}}', title)
        .replaceAll('{{sectionTitle}}', _sectionTitleForCurrentPage());
  }

  String _sectionTitleForCurrentPage() {
    // Foundation fallback: use document title until the exporter reads section
    // headings directly from the page layout tree.
    return document.title.trim().isEmpty ? 'Section' : document.title.trim();
  }
}

class _PdfBlockStyle {
  const _PdfBlockStyle({
    required this.font,
    required this.fontSize,
    required this.lineHeight,
  });

  final PdfFont font;
  final double fontSize;
  final double lineHeight;
}


class _ExportModel {
  _ExportModel({
    required this.bodyBlocks,
    required this.orderedFootnotes,
    required this.footnotesById,
    required this.numbersByFootnoteId,
  });

  factory _ExportModel.fromDocument(TextSystemDocument document) {
    final bodyBlocks = <TextSystemBlock>[];
    final footnotesById = <String, TextSystemBlock>{};

    for (final block in document.blocks) {
      if (_isFootnoteBlock(block)) {
        final id = block.metadata['footnoteId'] as String?;
        if (id != null) footnotesById[id] = block;
      } else {
        bodyBlocks.add(block);
      }
    }

    final orderedFootnotes = <_ExportFootnote>[];
    final numbersByFootnoteId = <String, int>{};

    for (final block in bodyBlocks) {
      for (final mark in block.marks) {
        if (!TextSystemExportService._isFootnoteReferenceMark(mark)) continue;
        final id = mark.attributes['footnoteId'];
        if (id == null || numbersByFootnoteId.containsKey(id)) continue;
        final footnoteBlock = footnotesById[id];
        if (footnoteBlock == null) continue;
        final number = orderedFootnotes.length + 1;
        numbersByFootnoteId[id] = number;
        orderedFootnotes.add(_ExportFootnote(id: id, number: number, block: footnoteBlock));
      }
    }

    return _ExportModel(
      bodyBlocks: bodyBlocks,
      orderedFootnotes: orderedFootnotes,
      footnotesById: footnotesById,
      numbersByFootnoteId: numbersByFootnoteId,
    );
  }

  final List<TextSystemBlock> bodyBlocks;
  final List<_ExportFootnote> orderedFootnotes;
  final Map<String, TextSystemBlock> footnotesById;
  final Map<String, int> numbersByFootnoteId;

  int numberForFootnoteId(String footnoteId) {
    return numbersByFootnoteId[footnoteId] ?? 0;
  }

  String footnoteText(String footnoteId) {
    return footnotesById[footnoteId]?.text.trim() ?? '';
  }

  List<_ExportFootnote> footnotesForBlock(TextSystemBlock block) {
    final result = <_ExportFootnote>[];
    for (final mark in block.marks) {
      if (!TextSystemExportService._isFootnoteReferenceMark(mark)) continue;
      final id = mark.attributes['footnoteId'];
      if (id == null) continue;
      final number = numberForFootnoteId(id);
      final footnoteBlock = footnotesById[id];
      if (number <= 0 || footnoteBlock == null) continue;
      result.add(_ExportFootnote(id: id, number: number, block: footnoteBlock));
    }
    result.sort((a, b) => a.number.compareTo(b.number));
    return result;
  }

  static bool _isFootnoteBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.custom && block.metadata['kind'] == 'footnote';
  }
}

class _ExportFootnote {
  const _ExportFootnote({
    required this.id,
    required this.number,
    required this.block,
  });

  final String id;
  final int number;
  final TextSystemBlock block;
}

extension _TextSystemExportIterableX<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
