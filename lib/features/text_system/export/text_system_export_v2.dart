import 'dart:convert';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import '../page/text_system_layout_tree.dart';
import '../references/actions/text_system_reference_action_models.dart';
import '../references/actions/text_system_reference_semantic_export_adapter.dart';
import '../styles/text_system_document_style.dart';
import '../structure/text_system_document_structure.dart';

enum TextSystemExportPipelineKind {
  visual,
  semantic,
}

enum TextSystemExportNodeType {
  paragraph,
  heading,
  listItem,
  todo,
  quote,
  code,
  pageBreak,
  sectionBreak,
  divider,
  figure,
  table,
  caption,
  bibliography,
  custom,
}

class TextSystemSemanticExportDocument {
  const TextSystemSemanticExportDocument({
    required this.metadata,
    required this.nodes,
    required this.footnotes,
    required this.references,
    required this.styleSheet,
    this.structure,
    this.layoutTree,
  });

  factory TextSystemSemanticExportDocument.fromTextSystem({
    required TextSystemDocument document,
    required TextSystemDocumentStyleSheet styleSheet,
    TextSystemDocumentStructure? structure,
    TextSystemDocumentLayoutTree? layoutTree,
    bool includeFootnotes = true,
  }) {
    final footnoteBlocksById = <String, TextSystemBlock>{};
    final nodes = <TextSystemExportNode>[];

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex++) {
      final block = document.blocks[blockIndex];
      if (_isFootnoteBlock(block)) {
        final footnoteId = block.metadata['footnoteId'];
        if (footnoteId is String && footnoteId.isNotEmpty) {
          footnoteBlocksById[footnoteId] = block;
        }
        continue;
      }

      nodes.add(_nodeForBlock(block, blockIndex));
    }

    final footnotes = <TextSystemExportFootnote>[];
    final seenFootnoteIds = <String>{};

    if (includeFootnotes) {
      for (final node in nodes) {
        for (final mark in node.marks) {
          final footnoteId = mark.attributes['footnoteId'];
          if (!_isFootnoteReferenceMark(mark) ||
              footnoteId == null ||
              footnoteId.isEmpty ||
              seenFootnoteIds.contains(footnoteId)) {
            continue;
          }

          final footnoteBlock = footnoteBlocksById[footnoteId];
          if (footnoteBlock == null) continue;

          seenFootnoteIds.add(footnoteId);
          footnotes.add(
            TextSystemExportFootnote(
              id: footnoteId,
              number: footnotes.length + 1,
              text: footnoteBlock.text.trim(),
              blockId: footnoteBlock.id,
            ),
          );
        }
      }
    }

    final references = <TextSystemExportReference>[
      if (structure != null)
        for (final reference in structure.references)
          TextSystemExportReference(
            id: reference.id,
            kind: reference.kind.name,
            label: reference.label,
            blockId: reference.blockId,
            targetId: reference.targetId,
            url: reference.url,
            pageNumber: reference.pageNumber,
            role: reference.role,
          ),
    ];

    return TextSystemSemanticExportDocument(
      metadata: TextSystemExportMetadata(
        documentId: document.id,
        title: document.title.trim().isEmpty ? 'Untitled document' : document.title.trim(),
        createdAt: document.createdAt,
        updatedAt: document.updatedAt,
        rawMetadata: Map<String, Object?>.unmodifiable(document.metadata),
      ),
      nodes: List<TextSystemExportNode>.unmodifiable(nodes),
      footnotes: List<TextSystemExportFootnote>.unmodifiable(footnotes),
      references: List<TextSystemExportReference>.unmodifiable(references),
      styleSheet: styleSheet,
      structure: structure,
      layoutTree: layoutTree,
    );
  }

  final TextSystemExportMetadata metadata;
  final List<TextSystemExportNode> nodes;
  final List<TextSystemExportFootnote> footnotes;
  final List<TextSystemExportReference> references;
  final TextSystemDocumentStyleSheet styleSheet;
  final TextSystemDocumentStructure? structure;
  final TextSystemDocumentLayoutTree? layoutTree;

  bool get hasFootnotes => footnotes.isNotEmpty;

  TextSystemExportFootnote? footnoteForId(String id) {
    for (final footnote in footnotes) {
      if (footnote.id == id) return footnote;
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metadata': metadata.toJson(),
      'nodeCount': nodes.length,
      'footnoteCount': footnotes.length,
      'referenceCount': references.length,
      'styleSheet': styleSheet.id,
      if (structure != null) 'structure': structure!.toJson(),
      'nodes': [for (final node in nodes) node.toJson()],
      'footnotes': [for (final footnote in footnotes) footnote.toJson()],
      'references': [for (final reference in references) reference.toJson()],
    };
  }

  static TextSystemExportNode _nodeForBlock(TextSystemBlock block, int blockIndex) {
    final kind = block.metadata['kind'];
    final nodeType = switch (block.type) {
      TextSystemBlockType.paragraph => TextSystemExportNodeType.paragraph,
      TextSystemBlockType.heading => TextSystemExportNodeType.heading,
      TextSystemBlockType.listItem => TextSystemExportNodeType.listItem,
      TextSystemBlockType.todo => TextSystemExportNodeType.todo,
      TextSystemBlockType.quote => TextSystemExportNodeType.quote,
      TextSystemBlockType.code => TextSystemExportNodeType.code,
      TextSystemBlockType.divider => kind == 'pageBreak'
          ? TextSystemExportNodeType.pageBreak
          : kind == 'sectionBreak'
              ? TextSystemExportNodeType.sectionBreak
              : TextSystemExportNodeType.divider,
      TextSystemBlockType.custom => kind == 'figure'
          ? TextSystemExportNodeType.figure
          : kind == 'table'
              ? TextSystemExportNodeType.table
              : kind == 'caption'
                  ? TextSystemExportNodeType.caption
                  : kind == 'bibliography'
                      ? TextSystemExportNodeType.bibliography
                      : TextSystemExportNodeType.custom,
    };

    return TextSystemExportNode(
      id: block.id,
      type: nodeType,
      text: block.text,
      blockIndex: blockIndex,
      level: block.level,
      checked: block.checked,
      ordered: block.metadata['ordered'] == true,
      styleId: block.metadata['styleId'] as String? ?? '',
      marks: List<TextMark>.unmodifiable(block.marks),
      metadata: Map<String, Object?>.unmodifiable(block.metadata),
    );
  }

  static bool _isFootnoteBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.custom && block.metadata['kind'] == 'footnote';
  }

  static bool _isFootnoteReferenceMark(TextMark mark) {
    return mark.kind == TextMarkKind.link && mark.attributes.containsKey('footnoteId');
  }
}

class TextSystemExportMetadata {
  const TextSystemExportMetadata({
    required this.documentId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.rawMetadata,
  });

  final String documentId;
  final String title;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, Object?> rawMetadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'title': title,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (rawMetadata.isNotEmpty) 'rawMetadata': rawMetadata,
    };
  }
}

class TextSystemExportNode {
  const TextSystemExportNode({
    required this.id,
    required this.type,
    required this.text,
    required this.blockIndex,
    required this.level,
    required this.checked,
    required this.ordered,
    required this.styleId,
    required this.marks,
    required this.metadata,
  });

  final String id;
  final TextSystemExportNodeType type;
  final String text;
  final int blockIndex;
  final int? level;
  final bool? checked;
  final bool ordered;
  final String styleId;
  final List<TextMark> marks;
  final Map<String, Object?> metadata;

  bool get isListLike => type == TextSystemExportNodeType.listItem || type == TextSystemExportNodeType.todo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type.name,
      'text': text,
      'blockIndex': blockIndex,
      if (level != null) 'level': level,
      if (checked != null) 'checked': checked,
      if (ordered) 'ordered': ordered,
      if (styleId.isNotEmpty) 'styleId': styleId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TextSystemExportFootnote {
  const TextSystemExportFootnote({
    required this.id,
    required this.number,
    required this.text,
    required this.blockId,
  });

  final String id;
  final int number;
  final String text;
  final String blockId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'number': number,
      'text': text,
      'blockId': blockId,
    };
  }
}

class TextSystemExportReference {
  const TextSystemExportReference({
    required this.id,
    required this.kind,
    required this.label,
    required this.blockId,
    this.targetId,
    this.url,
    this.pageNumber,
    this.role,
  });

  final String id;
  final String kind;
  final String label;
  final String blockId;
  final String? targetId;
  final String? url;
  final int? pageNumber;
  final String? role;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'label': label,
      'blockId': blockId,
      if (targetId != null) 'targetId': targetId,
      if (url != null) 'url': url,
      if (pageNumber != null) 'pageNumber': pageNumber,
      if (role != null) 'role': role,
    };
  }
}

class TextSystemSemanticMarkdownExporter {
  const TextSystemSemanticMarkdownExporter._();

  static String render(
    TextSystemSemanticExportDocument document, {
    bool includeMetadataHeader = true,
    bool includeFootnotes = true,
  }) {
    final buffer = StringBuffer();

    if (includeMetadataHeader) {
      buffer.writeln('# ${_escapeMarkdown(document.metadata.title)}');
      buffer.writeln();
    }

    var orderedCounter = 0;
    var previousWasOrderedList = false;

    for (final node in document.nodes) {
      if (node.type != TextSystemExportNodeType.listItem || !node.ordered) {
        orderedCounter = 0;
        previousWasOrderedList = false;
      }

      final rendered = switch (node.type) {
        TextSystemExportNodeType.heading => '${'#' * ((node.level ?? 1).clamp(1, 6).toInt())} ${_markdownInline(node, document)}',
        TextSystemExportNodeType.paragraph => _markdownInline(node, document),
        TextSystemExportNodeType.listItem => () {
            if (node.ordered) {
              orderedCounter = previousWasOrderedList ? orderedCounter + 1 : 1;
              previousWasOrderedList = true;
              return '$orderedCounter. ${_markdownInline(node, document)}';
            }
            return '- ${_markdownInline(node, document)}';
          }(),
        TextSystemExportNodeType.todo => '- [${node.checked == true ? 'x' : ' '}] ${_markdownInline(node, document)}',
        TextSystemExportNodeType.quote => '> ${_markdownInline(node, document)}',
        TextSystemExportNodeType.code => '```\n${node.text}\n```',
        TextSystemExportNodeType.pageBreak => '<!-- pagebreak -->',
        TextSystemExportNodeType.sectionBreak => '\n---',
        TextSystemExportNodeType.divider => '---',
        TextSystemExportNodeType.figure => '<!-- figure: ${_escapeMarkdown(node.text.trim())} -->',
        TextSystemExportNodeType.table => '<!-- table: ${_escapeMarkdown(node.text.trim())} -->',
        TextSystemExportNodeType.caption => '*${_markdownInline(node, document)}*',
        TextSystemExportNodeType.bibliography => _markdownInline(node, document),
        TextSystemExportNodeType.custom => _markdownInline(node, document),
      };

      if (rendered.trim().isEmpty) continue;
      buffer.writeln(rendered);
      buffer.writeln();
    }

    if (includeFootnotes && document.footnotes.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln();
      for (final footnote in document.footnotes) {
        buffer.writeln('[^${footnote.number}]: ${_escapeMarkdown(footnote.text)}');
      }
    }

    return buffer.toString().trimRight() + '\n';
  }

  static String _markdownInline(TextSystemExportNode node, TextSystemSemanticExportDocument document) {
    return _renderInline(
      node.text,
      node.marks,
      (text, marks) {
        var value = _escapeMarkdown(text);
        final linkMark = marks.where((mark) => mark.kind == TextMarkKind.link).lastOrNull;
        final inlineReference = _inlineReferenceMarkForMarks(marks);
        if (inlineReference != null) {
          value = TextSystemReferenceSemanticExportAdapter.markdown(
            visibleText: text,
            mark: inlineReference,
          );
        } else if (linkMark != null) {
          final footnoteId = linkMark.attributes['footnoteId'];
          if (footnoteId != null) {
            final number = document.footnoteForId(footnoteId)?.number;
            if (number != null) value += '[^$number]';
          } else {
            final url = linkMark.attributes['url'] ?? linkMark.attributes['href'];
            if (url != null && url.isNotEmpty) value = '[$value]($url)';
          }
        }
        if (marks.any((mark) => mark.kind == TextMarkKind.code)) value = '`$value`';
        if (marks.any((mark) => mark.kind == TextMarkKind.bold)) value = '**$value**';
        if (marks.any((mark) => mark.kind == TextMarkKind.italic)) value = '*$value*';
        if (marks.any((mark) => mark.kind == TextMarkKind.strikethrough)) value = '~~$value~~';
        return value;
      },
    );
  }
}

class TextSystemSemanticLatexExporter {
  const TextSystemSemanticLatexExporter._();

  static String render(
    TextSystemSemanticExportDocument document, {
    bool includeMetadataHeader = true,
  }) {
    final buffer = StringBuffer();

    if (includeMetadataHeader) {
      buffer.writeln(r'\documentclass[12pt]{article}');
      buffer.writeln(r'\usepackage[margin=1in]{geometry}');
      buffer.writeln(r'\usepackage{hyperref}');
      buffer.writeln(r'\usepackage{xcolor}');
      buffer.writeln('\\title{${_escapeLatex(document.metadata.title)}}');
      buffer.writeln(r'\begin{document}');
      buffer.writeln(r'\maketitle');
      buffer.writeln();
    }

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

    for (final node in document.nodes) {
      if (node.type != TextSystemExportNodeType.listItem) closeLists();

      switch (node.type) {
        case TextSystemExportNodeType.heading:
          final command = switch ((node.level ?? 1).clamp(1, 6).toInt()) {
            1 => 'section',
            2 => 'subsection',
            3 => 'subsubsection',
            _ => 'paragraph',
          };
          buffer.writeln('\\$command{${_latexInline(node, document)}}');
          buffer.writeln();
        case TextSystemExportNodeType.paragraph:
          buffer.writeln(_latexInline(node, document));
          buffer.writeln();
        case TextSystemExportNodeType.listItem:
          if (node.ordered && !inEnumerate) {
            if (inItemize) {
              buffer.writeln(r'\end{itemize}');
              inItemize = false;
            }
            buffer.writeln(r'\begin{enumerate}');
            inEnumerate = true;
          } else if (!node.ordered && !inItemize) {
            if (inEnumerate) {
              buffer.writeln(r'\end{enumerate}');
              inEnumerate = false;
            }
            buffer.writeln(r'\begin{itemize}');
            inItemize = true;
          }
          buffer.writeln(r'\item ' + _latexInline(node, document));
        case TextSystemExportNodeType.todo:
          buffer.writeln(r'\noindent ' + (node.checked == true ? r'$\boxtimes$ ' : r'$\square$ ') + _latexInline(node, document));
          buffer.writeln();
        case TextSystemExportNodeType.quote:
          buffer.writeln(r'\begin{quote}');
          buffer.writeln(_latexInline(node, document));
          buffer.writeln(r'\end{quote}');
          buffer.writeln();
        case TextSystemExportNodeType.code:
          buffer.writeln(r'\begin{verbatim}');
          buffer.writeln(node.text);
          buffer.writeln(r'\end{verbatim}');
          buffer.writeln();
        case TextSystemExportNodeType.pageBreak:
          buffer.writeln(r'\newpage');
          buffer.writeln();
        case TextSystemExportNodeType.sectionBreak:
          buffer.writeln(r'\clearpage');
          buffer.writeln();
        case TextSystemExportNodeType.divider:
          buffer.writeln(r'\medskip\hrule\medskip');
          buffer.writeln();
        case TextSystemExportNodeType.figure:
          buffer.writeln('% TODO figure: ${_escapeLatex(node.text)}');
          buffer.writeln();
        case TextSystemExportNodeType.table:
          buffer.writeln('% TODO table: ${_escapeLatex(node.text)}');
          buffer.writeln();
        case TextSystemExportNodeType.caption:
          buffer.writeln(r'\caption{' + _latexInline(node, document) + '}');
          buffer.writeln();
        case TextSystemExportNodeType.bibliography:
          buffer.writeln('% Bibliography');
          buffer.writeln(_latexInline(node, document));
          buffer.writeln();
        case TextSystemExportNodeType.custom:
          if (node.text.trim().isNotEmpty) {
            buffer.writeln(_latexInline(node, document));
            buffer.writeln();
          }
      }
    }

    closeLists();
    if (includeMetadataHeader) {
      buffer.writeln(r'\end{document}');
    }

    return buffer.toString();
  }

  static String _latexInline(TextSystemExportNode node, TextSystemSemanticExportDocument document) {
    return _renderInline(
      node.text,
      node.marks,
      (text, marks) {
        var value = _escapeLatex(text);
        final linkMark = marks.where((mark) => mark.kind == TextMarkKind.link).lastOrNull;
        final inlineReference = _inlineReferenceMarkForMarks(marks);
        if (inlineReference != null) {
          value = TextSystemReferenceSemanticExportAdapter.latex(
            visibleText: text,
            mark: inlineReference,
          );
        } else if (linkMark != null) {
          final footnoteId = linkMark.attributes['footnoteId'];
          if (footnoteId != null) {
            final footnote = document.footnoteForId(footnoteId);
            if (footnote != null) value += r'\footnote{' + _escapeLatex(footnote.text) + '}';
          } else {
            final url = linkMark.attributes['url'] ?? linkMark.attributes['href'];
            if (url != null && url.isNotEmpty) value = r'\href{' + _escapeLatex(url) + '}{' + value + '}';
          }
        }
        if (marks.any((mark) => mark.kind == TextMarkKind.code)) value = r'\texttt{' + value + '}';
        if (marks.any((mark) => mark.kind == TextMarkKind.bold)) value = r'\textbf{' + value + '}';
        if (marks.any((mark) => mark.kind == TextMarkKind.italic)) value = r'\emph{' + value + '}';
        if (marks.any((mark) => mark.kind == TextMarkKind.underline)) value = r'\underline{' + value + '}';
        return value;
      },
    );
  }
}

class TextSystemSemanticTypstExporter {
  const TextSystemSemanticTypstExporter._();

  static String render(
    TextSystemSemanticExportDocument document, {
    bool includeMetadataHeader = true,
  }) {
    final buffer = StringBuffer();

    if (includeMetadataHeader) {
      buffer.writeln('#set document(title: "${_escapeTypstString(document.metadata.title)}")');
      buffer.writeln('#set page(margin: 1in)');
      buffer.writeln();
    }

    for (final node in document.nodes) {
      final rendered = switch (node.type) {
        TextSystemExportNodeType.heading => '${'=' * ((node.level ?? 1).clamp(1, 6).toInt())} ${_typstInline(node, document)}',
        TextSystemExportNodeType.paragraph => _typstInline(node, document),
        TextSystemExportNodeType.listItem => '${node.ordered ? '+' : '-'} ${_typstInline(node, document)}',
        TextSystemExportNodeType.todo => '- [${node.checked == true ? 'x' : ' '}] ${_typstInline(node, document)}',
        TextSystemExportNodeType.quote => '#quote[${_typstInline(node, document)}]',
        TextSystemExportNodeType.code => '```text\n${node.text}\n```',
        TextSystemExportNodeType.pageBreak => '#pagebreak()',
        TextSystemExportNodeType.sectionBreak => '#pagebreak()',
        TextSystemExportNodeType.divider => '#line(length: 100%)',
        TextSystemExportNodeType.figure => '#figure(rect(width: 100%, height: 20pt), caption: [${_typstInline(node, document)}])',
        TextSystemExportNodeType.table => '// TODO table: ${_escapeTypstText(node.text)}',
        TextSystemExportNodeType.caption => '#align(center)[_${_typstInline(node, document)}_]',
        TextSystemExportNodeType.bibliography => _typstInline(node, document),
        TextSystemExportNodeType.custom => _typstInline(node, document),
      };

      if (rendered.trim().isEmpty) continue;
      buffer.writeln(rendered);
      buffer.writeln();
    }

    return buffer.toString().trimRight() + '\n';
  }

  static String _typstInline(TextSystemExportNode node, TextSystemSemanticExportDocument document) {
    return _renderInline(
      node.text,
      node.marks,
      (text, marks) {
        var value = _escapeTypstText(text);
        final linkMark = marks.where((mark) => mark.kind == TextMarkKind.link).lastOrNull;
        final inlineReference = _inlineReferenceMarkForMarks(marks);
        if (inlineReference != null) {
          value = TextSystemReferenceSemanticExportAdapter.typst(
            visibleText: text,
            mark: inlineReference,
          );
        } else if (linkMark != null) {
          final footnoteId = linkMark.attributes['footnoteId'];
          if (footnoteId != null) {
            final footnote = document.footnoteForId(footnoteId);
            if (footnote != null) value += '#footnote[${_escapeTypstText(footnote.text)}]';
          } else {
            final url = linkMark.attributes['url'] ?? linkMark.attributes['href'];
            if (url != null && url.isNotEmpty) value = '#link("${_escapeTypstString(url)}")[$value]';
          }
        }
        if (marks.any((mark) => mark.kind == TextMarkKind.code)) value = '`$value`';
        if (marks.any((mark) => mark.kind == TextMarkKind.bold)) value = '*$value*';
        if (marks.any((mark) => mark.kind == TextMarkKind.italic)) value = '_${value}_';
        return value;
      },
    );
  }
}

class TextSystemSemanticHtmlExporter {
  const TextSystemSemanticHtmlExporter._();

  static String render(
    TextSystemSemanticExportDocument document, {
    bool includeMetadataHeader = true,
    bool includeFootnotes = true,
  }) {
    final buffer = StringBuffer();
    if (includeMetadataHeader) {
      buffer.writeln('<!doctype html>');
      buffer.writeln('<html lang="en">');
      buffer.writeln('<head>');
      buffer.writeln('  <meta charset="utf-8">');
      buffer.writeln('  <meta name="viewport" content="width=device-width, initial-scale=1">');
      buffer.writeln('  <title>${htmlEscape.convert(document.metadata.title)}</title>');
      buffer.writeln('</head>');
      buffer.writeln('<body>');
    }

    buffer.writeln('<article data-document-id="${htmlEscape.convert(document.metadata.documentId)}">');
    var openList = '';

    void closeList() {
      if (openList.isNotEmpty) {
        buffer.writeln('</$openList>');
        openList = '';
      }
    }

    for (final node in document.nodes) {
      if (node.type != TextSystemExportNodeType.listItem) closeList();

      switch (node.type) {
        case TextSystemExportNodeType.heading:
          final level = (node.level ?? 1).clamp(1, 6).toInt();
          buffer.writeln('<h$level>${_htmlInline(node, document)}</h$level>');
        case TextSystemExportNodeType.paragraph:
          if (node.text.trim().isNotEmpty) buffer.writeln('<p>${_htmlInline(node, document)}</p>');
        case TextSystemExportNodeType.listItem:
          final tag = node.ordered ? 'ol' : 'ul';
          if (openList != tag) {
            closeList();
            buffer.writeln('<$tag>');
            openList = tag;
          }
          buffer.writeln('  <li>${_htmlInline(node, document)}</li>');
        case TextSystemExportNodeType.todo:
          buffer.writeln('<p><input type="checkbox" disabled${node.checked == true ? ' checked' : ''}> ${_htmlInline(node, document)}</p>');
        case TextSystemExportNodeType.quote:
          buffer.writeln('<blockquote>${_htmlInline(node, document)}</blockquote>');
        case TextSystemExportNodeType.code:
          buffer.writeln('<pre><code>${htmlEscape.convert(node.text)}</code></pre>');
        case TextSystemExportNodeType.pageBreak:
          buffer.writeln('<hr class="page-break">');
        case TextSystemExportNodeType.sectionBreak:
          buffer.writeln('<hr class="section-break">');
        case TextSystemExportNodeType.divider:
          buffer.writeln('<hr>');
        case TextSystemExportNodeType.figure:
          buffer.writeln('<figure><figcaption>${_htmlInline(node, document)}</figcaption></figure>');
        case TextSystemExportNodeType.table:
          buffer.writeln('<figure class="table-placeholder"><figcaption>${_htmlInline(node, document)}</figcaption></figure>');
        case TextSystemExportNodeType.caption:
          buffer.writeln('<figcaption>${_htmlInline(node, document)}</figcaption>');
        case TextSystemExportNodeType.bibliography:
          buffer.writeln('<section class="bibliography">${_htmlInline(node, document)}</section>');
        case TextSystemExportNodeType.custom:
          if (node.text.trim().isNotEmpty) buffer.writeln('<p>${_htmlInline(node, document)}</p>');
      }
    }

    closeList();

    if (includeFootnotes && document.footnotes.isNotEmpty) {
      buffer.writeln('<section class="footnotes">');
      buffer.writeln('<h2>Footnotes</h2>');
      buffer.writeln('<ol>');
      for (final footnote in document.footnotes) {
        buffer.writeln('  <li id="fn-${footnote.number}">${htmlEscape.convert(footnote.text)}</li>');
      }
      buffer.writeln('</ol>');
      buffer.writeln('</section>');
    }

    buffer.writeln('</article>');

    if (includeMetadataHeader) {
      buffer.writeln('</body>');
      buffer.writeln('</html>');
    }

    return buffer.toString();
  }

  static String _htmlInline(TextSystemExportNode node, TextSystemSemanticExportDocument document) {
    return _renderInline(
      node.text,
      node.marks,
      (text, marks) {
        var value = htmlEscape.convert(text);
        final linkMark = marks.where((mark) => mark.kind == TextMarkKind.link).lastOrNull;
        final inlineReference = _inlineReferenceMarkForMarks(marks);
        if (inlineReference != null) {
          value = TextSystemReferenceSemanticExportAdapter.html(
            visibleText: text,
            mark: inlineReference,
          );
        } else if (linkMark != null) {
          final footnoteId = linkMark.attributes['footnoteId'];
          if (footnoteId != null) {
            final footnote = document.footnoteForId(footnoteId);
            if (footnote != null) {
              value += '<sup><a href="#fn-${footnote.number}">${footnote.number}</a></sup>';
            }
          } else {
            final url = linkMark.attributes['url'] ?? linkMark.attributes['href'];
            if (url != null && url.isNotEmpty) value = '<a href="${htmlEscape.convert(url)}">$value</a>';
          }
        }
        if (marks.any((mark) => mark.kind == TextMarkKind.code)) value = '<code>$value</code>';
        if (marks.any((mark) => mark.kind == TextMarkKind.bold)) value = '<strong>$value</strong>';
        if (marks.any((mark) => mark.kind == TextMarkKind.italic)) value = '<em>$value</em>';
        if (marks.any((mark) => mark.kind == TextMarkKind.underline)) value = '<u>$value</u>';
        if (marks.any((mark) => mark.kind == TextMarkKind.strikethrough)) value = '<s>$value</s>';
        return value;
      },
    );
  }
}

TextSystemInlineReferenceMark? _inlineReferenceMarkForMarks(List<TextMark> marks) {
  for (final mark in marks.reversed) {
    if (mark.kind != TextMarkKind.link) continue;
    final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
    if (inlineReference != null) return inlineReference;
  }
  return null;
}

String _renderInline(
  String text,
  List<TextMark> marks,
  String Function(String text, List<TextMark> activeMarks) renderSegment,
) {
  if (text.isEmpty) return '';

  final boundaries = <int>{0, text.length};
  for (final mark in marks) {
    final start = mark.range.start.clamp(0, text.length).toInt();
    final end = mark.range.end.clamp(start, text.length).toInt();
    if (start == end) continue;
    boundaries.add(start);
    boundaries.add(end);
  }

  final sorted = boundaries.toList()..sort();
  final buffer = StringBuffer();

  for (var index = 0; index < sorted.length - 1; index++) {
    final start = sorted[index];
    final end = sorted[index + 1];
    if (end <= start) continue;

    final segment = text.substring(start, end);
    final activeMarks = marks
        .where((mark) => mark.range.start <= start && mark.range.end >= end)
        .toList(growable: false);

    buffer.write(renderSegment(segment, activeMarks));
  }

  return buffer.toString();
}

String _escapeMarkdown(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('*', r'\*')
      .replaceAll('_', r'\_')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll('`', r'\`');
}

String _escapeLatex(String value) {
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

String _escapeTypstText(String value) {
  return value
      .replaceAll('\\', '\\\\')
      .replaceAll('[', '\\[')
      .replaceAll(']', '\\]')
      .replaceAll('#', '\\#')
      .replaceAll('*', '\\*')
      .replaceAll('_', '\\_');
}


String _escapeTypstString(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}


extension _IterableLastOrNull<T> on Iterable<T> {
  T? get lastOrNull {
    T? value;
    var found = false;
    for (final item in this) {
      value = item;
      found = true;
    }
    return found ? value : null;
  }
}
