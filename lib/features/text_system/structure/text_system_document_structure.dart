import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import '../page/text_system_layout_tree.dart';

enum TextSystemStructureReferenceKind {
  link,
  source,
  citation,
  footnote,
  project,
  todo,
  figure,
  table,
  unknown;

  String get label {
    return switch (this) {
      TextSystemStructureReferenceKind.link => 'Link',
      TextSystemStructureReferenceKind.source => 'Source',
      TextSystemStructureReferenceKind.citation => 'Citation',
      TextSystemStructureReferenceKind.footnote => 'Footnote',
      TextSystemStructureReferenceKind.project => 'Project',
      TextSystemStructureReferenceKind.todo => 'Todo',
      TextSystemStructureReferenceKind.figure => 'Figure',
      TextSystemStructureReferenceKind.table => 'Table',
      TextSystemStructureReferenceKind.unknown => 'Reference',
    };
  }
}

class TextSystemDocumentStructure {
  const TextSystemDocumentStructure({
    required this.documentId,
    required this.title,
    required this.pageCount,
    required this.outlineEntries,
    required this.sections,
    required this.references,
    required this.stats,
  });

  final String documentId;
  final String title;
  final int pageCount;
  final List<TextSystemOutlineEntry> outlineEntries;
  final List<TextSystemStructureSection> sections;
  final List<TextSystemStructureReference> references;
  final TextSystemDocumentStats stats;

  int get sectionCount => sections.length;
  int get outlineCount => outlineEntries.length;
  int get referenceCount => references.length;

  String get compactLabel =>
      '${sections.length} section${sections.length == 1 ? '' : 's'} · '
      '${outlineEntries.length} heading${outlineEntries.length == 1 ? '' : 's'} · '
      '${stats.wordCount} words';

  List<TextSystemStructureSection> get longestSections {
    final sorted = List<TextSystemStructureSection>.of(sections)
      ..sort((a, b) => b.stats.wordCount.compareTo(a.stats.wordCount));
    return sorted.take(5).toList(growable: false);
  }

  TextSystemStructureSection? sectionForBlockId(String blockId) {
    for (final section in sections) {
      if (section.containsBlockId(blockId)) return section;
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'title': title,
      'pageCount': pageCount,
      'outlineCount': outlineEntries.length,
      'sectionCount': sections.length,
      'referenceCount': references.length,
      'stats': stats.toJson(),
      'outlineEntries': [for (final entry in outlineEntries) entry.toJson()],
      'sections': [for (final section in sections) section.toJson()],
      'references': [for (final reference in references) reference.toJson()],
    };
  }

  static TextSystemDocumentStructure build({
    required TextSystemDocument document,
    TextSystemDocumentLayoutTree? layoutTree,
  }) {
    final pageIndex = _PageIndex.fromLayoutTree(layoutTree);
    final outlineEntries = _buildOutline(document, pageIndex);
    final references = _buildReferences(document, pageIndex);
    final sections = _buildSections(
      document: document,
      pageIndex: pageIndex,
      outlineEntries: outlineEntries,
      references: references,
    );

    return TextSystemDocumentStructure(
      documentId: document.id,
      title: document.title,
      pageCount: layoutTree?.pageCount ?? pageIndex.pageCount,
      outlineEntries: List<TextSystemOutlineEntry>.unmodifiable(outlineEntries),
      sections: List<TextSystemStructureSection>.unmodifiable(sections),
      references: List<TextSystemStructureReference>.unmodifiable(references),
      stats: _statsForRange(
        document.blocks,
        0,
        document.blocks.length,
        references,
      ),
    );
  }

  static List<TextSystemOutlineEntry> _buildOutline(
    TextSystemDocument document,
    _PageIndex pageIndex,
  ) {
    final entries = <TextSystemOutlineEntry>[];
    final currentParentByLevel = <int, String>{};

    for (var index = 0; index < document.blocks.length; index++) {
      final block = document.blocks[index];
      if (block.type != TextSystemBlockType.heading) continue;

      final title = block.text.trim();
      if (title.isEmpty) continue;

      final level = (block.level ?? 1).clamp(1, 6).toInt();
      String? parentId;
      for (var parentLevel = level - 1; parentLevel >= 1; parentLevel--) {
        final candidate = currentParentByLevel[parentLevel];
        if (candidate != null) {
          parentId = candidate;
          break;
        }
      }

      final entry = TextSystemOutlineEntry(
        id: 'outline-${entries.length + 1}',
        blockId: block.id,
        blockIndex: index,
        title: title,
        level: level,
        parentId: parentId,
        pageStart: pageIndex.firstPageForBlock(block.id),
        pageEnd: pageIndex.lastPageForBlock(block.id),
      );
      entries.add(entry);
      currentParentByLevel[level] = entry.id;

      final staleLevels = currentParentByLevel.keys.where((candidate) => candidate > level).toList();
      for (final staleLevel in staleLevels) {
        currentParentByLevel.remove(staleLevel);
      }
    }

    return entries;
  }

  static List<TextSystemStructureSection> _buildSections({
    required TextSystemDocument document,
    required _PageIndex pageIndex,
    required List<TextSystemOutlineEntry> outlineEntries,
    required List<TextSystemStructureReference> references,
  }) {
    final starts = <_SectionStart>[];

    if (document.blocks.isEmpty) {
      return <TextSystemStructureSection>[
        TextSystemStructureSection(
          id: 'section-1',
          title: document.title.trim().isEmpty ? 'Untitled section' : document.title.trim(),
          startBlockIndex: 0,
          endBlockIndexExclusive: 0,
          pageStart: 1,
          pageEnd: 1,
          headingBlockId: null,
          outlineEntryIds: const <String>[],
          blockIds: const <String>[],
          stats: const TextSystemDocumentStats.empty(),
          references: const <TextSystemStructureReference>[],
        ),
      ];
    }

    var foundExplicitStart = false;
    for (var index = 0; index < document.blocks.length; index++) {
      final block = document.blocks[index];

      if (block.type == TextSystemBlockType.heading && (block.level ?? 1) <= 1 && block.text.trim().isNotEmpty) {
        starts.add(
          _SectionStart(
            blockIndex: index,
            blockId: block.id,
            title: block.text.trim(),
            headingBlockId: block.id,
          ),
        );
        foundExplicitStart = true;
      } else if (_isSectionBreakBlock(block)) {
        starts.add(
          _SectionStart(
            blockIndex: index,
            blockId: block.id,
            title: _sectionBreakTitle(block, starts.length + 1),
            headingBlockId: null,
          ),
        );
        foundExplicitStart = true;
      }
    }

    if (!foundExplicitStart || starts.first.blockIndex > 0) {
      starts.insert(
        0,
        _SectionStart(
          blockIndex: 0,
          blockId: document.blocks.first.id,
          title: document.title.trim().isEmpty ? 'Introduction' : document.title.trim(),
          headingBlockId: null,
        ),
      );
    }

    final sections = <TextSystemStructureSection>[];
    for (var index = 0; index < starts.length; index++) {
      final start = starts[index];
      final end = index + 1 < starts.length ? starts[index + 1].blockIndex : document.blocks.length;
      final blockIds = <String>[
        for (var blockIndex = start.blockIndex; blockIndex < end; blockIndex++)
          document.blocks[blockIndex].id,
      ];

      final sectionReferences = references
          .where((reference) => reference.blockIndex >= start.blockIndex && reference.blockIndex < end)
          .toList(growable: false);

      final sectionOutlineIds = outlineEntries
          .where((entry) => entry.blockIndex >= start.blockIndex && entry.blockIndex < end)
          .map((entry) => entry.id)
          .toList(growable: false);

      sections.add(
        TextSystemStructureSection(
          id: 'section-${index + 1}',
          title: start.title,
          startBlockIndex: start.blockIndex,
          endBlockIndexExclusive: end,
          pageStart: pageIndex.firstPageForBlock(start.blockId),
          pageEnd: _lastPageForRange(document.blocks, pageIndex, start.blockIndex, end),
          headingBlockId: start.headingBlockId,
          outlineEntryIds: List<String>.unmodifiable(sectionOutlineIds),
          blockIds: List<String>.unmodifiable(blockIds),
          stats: _statsForRange(document.blocks, start.blockIndex, end, references),
          references: List<TextSystemStructureReference>.unmodifiable(sectionReferences),
        ),
      );
    }

    return sections;
  }

  static List<TextSystemStructureReference> _buildReferences(
    TextSystemDocument document,
    _PageIndex pageIndex,
  ) {
    final references = <TextSystemStructureReference>[];

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex++) {
      final block = document.blocks[blockIndex];

      if (block.type == TextSystemBlockType.todo) {
        references.add(
          TextSystemStructureReference(
            id: 'todo-${references.length + 1}',
            kind: TextSystemStructureReferenceKind.todo,
            blockId: block.id,
            blockIndex: blockIndex,
            offset: 0,
            label: block.text.trim().isEmpty ? 'Todo' : block.text.trim(),
            targetId: block.id,
            role: 'todo',
            pageNumber: pageIndex.firstPageForBlock(block.id),
          ),
        );
      }

      final blockKind = block.metadata['kind'];
      if (blockKind == 'figure' || blockKind == 'table' || blockKind == 'caption') {
        final kind = blockKind == 'table'
            ? TextSystemStructureReferenceKind.table
            : TextSystemStructureReferenceKind.figure;
        references.add(
          TextSystemStructureReference(
            id: '$blockKind-${references.length + 1}',
            kind: kind,
            blockId: block.id,
            blockIndex: blockIndex,
            offset: 0,
            label: block.text.trim().isEmpty ? kind.label : block.text.trim(),
            targetId: block.id,
            role: '$blockKind',
            pageNumber: pageIndex.firstPageForBlock(block.id),
          ),
        );
      }

      for (final mark in block.marks) {
        if (mark.kind != TextMarkKind.link) continue;

        final role = mark.attributes['role'] ?? mark.attributes['kind'] ?? 'link';
        final kind = _referenceKindForRole(role, mark.attributes);
        final label = _referenceLabel(block, mark, kind);
        final targetId = mark.attributes['targetId'] ??
            mark.attributes['sourceId'] ??
            mark.attributes['citationId'] ??
            mark.attributes['footnoteId'] ??
            mark.attributes['projectId'] ??
            mark.attributes['todoId'];
        final url = mark.attributes['url'] ?? mark.attributes['href'];

        references.add(
          TextSystemStructureReference(
            id: mark.attributes['textSystemReferenceId'] ?? 'ref-${references.length + 1}',
            kind: kind,
            blockId: block.id,
            blockIndex: blockIndex,
            offset: mark.range.start,
            label: label,
            targetId: targetId,
            url: url,
            role: role,
            pageNumber: pageIndex.firstPageForBlock(block.id),
          ),
        );
      }
    }

    return references;
  }

  static TextSystemDocumentStats _statsForRange(
    List<TextSystemBlock> blocks,
    int start,
    int end,
    List<TextSystemStructureReference> references,
  ) {
    var wordCount = 0;
    var characterCount = 0;
    var paragraphCount = 0;
    var headingCount = 0;
    var todoCount = 0;
    var completedTodoCount = 0;
    var footnoteCount = 0;
    var citationCount = 0;
    var sourceReferenceCount = 0;
    var figureCount = 0;
    var tableCount = 0;
    var captionCount = 0;
    var bibliographyCount = 0;

    for (var index = start; index < end && index < blocks.length; index++) {
      final block = blocks[index];
      final text = block.text.trim();
      wordCount += _countWords(text);
      characterCount += block.text.length;

      switch (block.type) {
        case TextSystemBlockType.paragraph:
          if (text.isNotEmpty) paragraphCount += 1;
        case TextSystemBlockType.heading:
          headingCount += 1;
        case TextSystemBlockType.todo:
          todoCount += 1;
          if (block.checked == true) completedTodoCount += 1;
        case TextSystemBlockType.custom:
          final kind = block.metadata['kind'];
          if (kind == 'footnote') footnoteCount += 1;
          if (kind == 'figure') figureCount += 1;
          if (kind == 'table') tableCount += 1;
          if (kind == 'caption') captionCount += 1;
          if (kind == 'bibliography') bibliographyCount += 1;
        case TextSystemBlockType.listItem:
        case TextSystemBlockType.quote:
        case TextSystemBlockType.code:
        case TextSystemBlockType.divider:
          break;
      }
    }

    for (final reference in references) {
      if (reference.blockIndex < start || reference.blockIndex >= end) continue;
      switch (reference.kind) {
        case TextSystemStructureReferenceKind.footnote:
          footnoteCount += 1;
        case TextSystemStructureReferenceKind.citation:
          citationCount += 1;
        case TextSystemStructureReferenceKind.source:
          sourceReferenceCount += 1;
        case TextSystemStructureReferenceKind.figure:
          figureCount += 1;
        case TextSystemStructureReferenceKind.table:
          tableCount += 1;
        case TextSystemStructureReferenceKind.todo:
        case TextSystemStructureReferenceKind.project:
        case TextSystemStructureReferenceKind.link:
        case TextSystemStructureReferenceKind.unknown:
          break;
      }
    }

    return TextSystemDocumentStats(
      wordCount: wordCount,
      characterCount: characterCount,
      paragraphCount: paragraphCount,
      headingCount: headingCount,
      todoCount: todoCount,
      completedTodoCount: completedTodoCount,
      footnoteCount: footnoteCount,
      citationCount: citationCount,
      sourceReferenceCount: sourceReferenceCount,
      figureCount: figureCount,
      tableCount: tableCount,
      captionCount: captionCount,
      bibliographyCount: bibliographyCount,
    );
  }

  static int _lastPageForRange(
    List<TextSystemBlock> blocks,
    _PageIndex pageIndex,
    int start,
    int end,
  ) {
    var page = pageIndex.firstPageForBlock(blocks[start].id);
    for (var index = start; index < end && index < blocks.length; index++) {
      page = pageIndex.lastPageForBlock(blocks[index].id) > page
          ? pageIndex.lastPageForBlock(blocks[index].id)
          : page;
    }
    return page;
  }

  static int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }

  static String _sectionBreakTitle(TextSystemBlock block, int number) {
    final title = block.metadata['title'];
    if (title is String && title.trim().isNotEmpty) return title.trim();

    final label = block.metadata['label'];
    if (label is String && label.trim().isNotEmpty) return label.trim();

    return 'Section $number';
  }

  static bool _isSectionBreakBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.divider && block.metadata['kind'] == 'sectionBreak';
  }

  static TextSystemStructureReferenceKind _referenceKindForRole(
    String role,
    Map<String, String> attributes,
  ) {
    final normalized = role.toLowerCase();
    if (normalized.contains('footnote')) return TextSystemStructureReferenceKind.footnote;
    if (normalized.contains('citation') || normalized == 'cite') return TextSystemStructureReferenceKind.citation;
    if (normalized.contains('source')) return TextSystemStructureReferenceKind.source;
    if (normalized.contains('project')) return TextSystemStructureReferenceKind.project;
    if (normalized.contains('todo')) return TextSystemStructureReferenceKind.todo;
    if (normalized.contains('document') || normalized.contains('link')) return TextSystemStructureReferenceKind.link;
    if (normalized.contains('figure')) return TextSystemStructureReferenceKind.figure;
    if (normalized.contains('table')) return TextSystemStructureReferenceKind.table;
    if (attributes['textSystemReferenceKind'] == 'citation') return TextSystemStructureReferenceKind.citation;
    if (attributes['textSystemReferenceKind'] == 'source') return TextSystemStructureReferenceKind.source;
    if (attributes.containsKey('citationId')) return TextSystemStructureReferenceKind.citation;
    if (attributes.containsKey('sourceId')) return TextSystemStructureReferenceKind.source;
    if (attributes.containsKey('footnoteId')) return TextSystemStructureReferenceKind.footnote;
    if (attributes.containsKey('url') || attributes.containsKey('href')) return TextSystemStructureReferenceKind.link;
    return TextSystemStructureReferenceKind.unknown;
  }

  static String _referenceLabel(
    TextSystemBlock block,
    TextMark mark,
    TextSystemStructureReferenceKind kind,
  ) {
    final explicit = mark.attributes['label'] ?? mark.attributes['title'];
    if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();

    final start = mark.range.start.clamp(0, block.text.length).toInt();
    final end = mark.range.end.clamp(start, block.text.length).toInt();
    final selected = block.text.substring(start, end).trim();
    if (selected.isNotEmpty) return selected;

    return kind.label;
  }
}

class TextSystemOutlineEntry {
  const TextSystemOutlineEntry({
    required this.id,
    required this.blockId,
    required this.blockIndex,
    required this.title,
    required this.level,
    required this.parentId,
    required this.pageStart,
    required this.pageEnd,
  });

  final String id;
  final String blockId;
  final int blockIndex;
  final String title;
  final int level;
  final String? parentId;
  final int pageStart;
  final int pageEnd;

  String get pageLabel => pageStart == pageEnd ? 'p. $pageStart' : 'pp. $pageStart–$pageEnd';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'blockId': blockId,
      'blockIndex': blockIndex,
      'title': title,
      'level': level,
      'parentId': parentId,
      'pageStart': pageStart,
      'pageEnd': pageEnd,
    };
  }
}

class TextSystemStructureSection {
  const TextSystemStructureSection({
    required this.id,
    required this.title,
    required this.startBlockIndex,
    required this.endBlockIndexExclusive,
    required this.pageStart,
    required this.pageEnd,
    required this.headingBlockId,
    required this.outlineEntryIds,
    required this.blockIds,
    required this.stats,
    required this.references,
  });

  final String id;
  final String title;
  final int startBlockIndex;
  final int endBlockIndexExclusive;
  final int pageStart;
  final int pageEnd;
  final String? headingBlockId;
  final List<String> outlineEntryIds;
  final List<String> blockIds;
  final TextSystemDocumentStats stats;
  final List<TextSystemStructureReference> references;

  int get blockCount => endBlockIndexExclusive - startBlockIndex;
  String get pageLabel => pageStart == pageEnd ? 'p. $pageStart' : 'pp. $pageStart–$pageEnd';
  String get compactLabel => '$pageLabel · ${stats.wordCount} words · ${stats.todoCount} todos';

  bool containsBlockId(String blockId) => blockIds.contains(blockId);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'startBlockIndex': startBlockIndex,
      'endBlockIndexExclusive': endBlockIndexExclusive,
      'pageStart': pageStart,
      'pageEnd': pageEnd,
      'headingBlockId': headingBlockId,
      'outlineEntryIds': outlineEntryIds,
      'blockIds': blockIds,
      'stats': stats.toJson(),
      'references': [for (final reference in references) reference.toJson()],
    };
  }
}

class TextSystemDocumentStats {
  const TextSystemDocumentStats({
    required this.wordCount,
    required this.characterCount,
    required this.paragraphCount,
    required this.headingCount,
    required this.todoCount,
    required this.completedTodoCount,
    required this.footnoteCount,
    required this.citationCount,
    required this.sourceReferenceCount,
    required this.figureCount,
    required this.tableCount,
    required this.captionCount,
    required this.bibliographyCount,
  });

  const TextSystemDocumentStats.empty()
      : wordCount = 0,
        characterCount = 0,
        paragraphCount = 0,
        headingCount = 0,
        todoCount = 0,
        completedTodoCount = 0,
        footnoteCount = 0,
        citationCount = 0,
        sourceReferenceCount = 0,
        figureCount = 0,
        tableCount = 0,
        captionCount = 0,
        bibliographyCount = 0;

  final int wordCount;
  final int characterCount;
  final int paragraphCount;
  final int headingCount;
  final int todoCount;
  final int completedTodoCount;
  final int footnoteCount;
  final int citationCount;
  final int sourceReferenceCount;
  final int figureCount;
  final int tableCount;
  final int captionCount;
  final int bibliographyCount;

  int get openTodoCount => todoCount - completedTodoCount;
  double get todoCompletionRatio => todoCount == 0 ? 1 : completedTodoCount / todoCount;

  String get todoLabel => todoCount == 0 ? '0 todos' : '$completedTodoCount/$todoCount done';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'wordCount': wordCount,
      'characterCount': characterCount,
      'paragraphCount': paragraphCount,
      'headingCount': headingCount,
      'todoCount': todoCount,
      'completedTodoCount': completedTodoCount,
      'openTodoCount': openTodoCount,
      'todoCompletionRatio': todoCompletionRatio,
      'footnoteCount': footnoteCount,
      'citationCount': citationCount,
      'sourceReferenceCount': sourceReferenceCount,
      'figureCount': figureCount,
      'tableCount': tableCount,
      'captionCount': captionCount,
      'bibliographyCount': bibliographyCount,
    };
  }
}

class TextSystemStructureReference {
  const TextSystemStructureReference({
    required this.id,
    required this.kind,
    required this.blockId,
    required this.blockIndex,
    required this.offset,
    required this.label,
    required this.pageNumber,
    this.targetId,
    this.url,
    this.role,
  });

  final String id;
  final TextSystemStructureReferenceKind kind;
  final String blockId;
  final int blockIndex;
  final int offset;
  final String label;
  final int pageNumber;
  final String? targetId;
  final String? url;
  final String? role;

  String get pageLabel => 'p. $pageNumber';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      'blockId': blockId,
      'blockIndex': blockIndex,
      'offset': offset,
      'label': label,
      'pageNumber': pageNumber,
      'targetId': targetId,
      'url': url,
      'role': role,
    };
  }
}

class _SectionStart {
  const _SectionStart({
    required this.blockIndex,
    required this.blockId,
    required this.title,
    required this.headingBlockId,
  });

  final int blockIndex;
  final String blockId;
  final String title;
  final String? headingBlockId;
}

class _PageIndex {
  const _PageIndex({
    required this.pageCount,
    required this.firstPageByBlockId,
    required this.lastPageByBlockId,
  });

  final int pageCount;
  final Map<String, int> firstPageByBlockId;
  final Map<String, int> lastPageByBlockId;

  int firstPageForBlock(String blockId) => firstPageByBlockId[blockId] ?? 1;
  int lastPageForBlock(String blockId) => lastPageByBlockId[blockId] ?? firstPageForBlock(blockId);

  static _PageIndex fromLayoutTree(TextSystemDocumentLayoutTree? layoutTree) {
    if (layoutTree == null || layoutTree.pages.isEmpty) {
      return const _PageIndex(
        pageCount: 1,
        firstPageByBlockId: <String, int>{},
        lastPageByBlockId: <String, int>{},
      );
    }

    final first = <String, int>{};
    final last = <String, int>{};

    for (final page in layoutTree.pages) {
      for (final fragment in page.blockFragments) {
        first.putIfAbsent(fragment.blockId, () => page.logicalPageNumber);
        final previous = last[fragment.blockId] ?? page.logicalPageNumber;
        last[fragment.blockId] = page.logicalPageNumber > previous ? page.logicalPageNumber : previous;
      }
    }

    return _PageIndex(
      pageCount: layoutTree.pageCount,
      firstPageByBlockId: Map<String, int>.unmodifiable(first),
      lastPageByBlockId: Map<String, int>.unmodifiable(last),
    );
  }
}
