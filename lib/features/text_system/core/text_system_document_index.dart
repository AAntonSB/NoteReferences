import 'text_mark.dart';
import 'text_system_block_capabilities.dart';
import 'text_system_block.dart';
import 'text_system_document.dart';
import 'text_system_document_position.dart';
import 'text_system_document_range.dart';
import 'text_system_range.dart';

/// Linear semantic unit kinds used by the document interaction core.
///
/// This layer is deliberately model-facing, not widget-facing. It gives future
/// selection, copy/delete, comments, citations, source links, and diagnostics a
/// single way to reason about a block-structured document as ordered semantic
/// content.
enum TextSystemDocumentUnitKind {
  blockStart,
  blockEnd,
  textRun,
  inlineAtom,
  textMark,
  objectBlock,
  figureObject,
  tableObject,
  equationObject,
  pageBreak,
  sectionBreak,
  divider,
  unknownObject,
}

enum TextSystemInlineAtomKind {
  math,
  crossReference,
  citation,
  sourceLink,
  documentLink,
  todo,
  date,
  tag,
  unknown,
}

/// One semantic inline object discovered inside a text-bearing block.
class TextSystemInlineAtomIndexEntry {
  const TextSystemInlineAtomIndexEntry({
    required this.id,
    required this.kind,
    required this.blockId,
    required this.blockIndex,
    required this.range,
    required this.sourceText,
    required this.displayText,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final TextSystemInlineAtomKind kind;
  final String blockId;
  final int blockIndex;
  final TextSystemRange range;
  final String sourceText;
  final String displayText;
  final Map<String, Object?> metadata;

  TextSystemDocumentPosition get startPosition {
    return TextSystemDocumentPosition.inlineAtom(
      blockId: blockId,
      blockIndex: blockIndex,
      atomId: id,
      atomStartOffset: range.start,
      atomEndOffset: range.end,
    );
  }

  TextSystemDocumentPosition get endPosition {
    return TextSystemDocumentPosition.text(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: range.end,
    );
  }

  String get diagnosticLabel => '${kind.name}:$blockId@${range.start}-${range.end}';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      'blockId': blockId,
      'blockIndex': blockIndex,
      'range': range.toJson(),
      'sourceText': sourceText,
      'displayText': displayText,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// A single ordered unit in the document's semantic index.
class TextSystemDocumentIndexUnit {
  const TextSystemDocumentIndexUnit({
    required this.kind,
    required this.blockId,
    required this.blockIndex,
    required this.start,
    required this.end,
    this.text,
    this.mark,
    this.inlineAtom,
    this.block,
    this.metadata = const <String, Object?>{},
  });

  final TextSystemDocumentUnitKind kind;
  final String blockId;
  final int blockIndex;
  final TextSystemDocumentPosition start;
  final TextSystemDocumentPosition end;
  final String? text;
  final TextMark? mark;
  final TextSystemInlineAtomIndexEntry? inlineAtom;
  final TextSystemBlock? block;
  final Map<String, Object?> metadata;

  bool get isBlockBoundary =>
      kind == TextSystemDocumentUnitKind.blockStart || kind == TextSystemDocumentUnitKind.blockEnd;
  bool get isTextRun => kind == TextSystemDocumentUnitKind.textRun;
  bool get isInlineAtom => kind == TextSystemDocumentUnitKind.inlineAtom;
  bool get isObject => <TextSystemDocumentUnitKind>{
        TextSystemDocumentUnitKind.objectBlock,
        TextSystemDocumentUnitKind.figureObject,
        TextSystemDocumentUnitKind.tableObject,
        TextSystemDocumentUnitKind.equationObject,
        TextSystemDocumentUnitKind.pageBreak,
        TextSystemDocumentUnitKind.sectionBreak,
        TextSystemDocumentUnitKind.divider,
        TextSystemDocumentUnitKind.unknownObject,
      }.contains(kind);

  TextSystemDocumentRange get range => TextSystemDocumentRange(start: start, end: end);

  String get plainText {
    final explicit = text;
    if (explicit != null) return explicit;
    final atom = inlineAtom;
    if (atom != null) return atom.displayText;
    final currentBlock = block;
    if (currentBlock != null && isObject) return _objectPlainText(currentBlock);
    return '';
  }

  String get diagnosticLabel =>
      '${kind.name}:$blockId:${start.diagnosticLabel}->${end.diagnosticLabel}';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'blockId': blockId,
      'blockIndex': blockIndex,
      'start': start.toJson(),
      'end': end.toJson(),
      if (text != null) 'text': text,
      if (inlineAtom != null) 'inlineAtom': inlineAtom!.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  static String _objectPlainText(TextSystemBlock block) {
    final kind = _semanticKindForBlock(block);
    final caption = _stringMetadata(block.metadata, const <String>[
      'caption',
      'title',
      'label',
      'altText',
      'note',
    ]);
    switch (kind) {
      case _DocumentObjectKind.figure:
        return caption.isEmpty ? '[Figure]' : 'Figure: $caption';
      case _DocumentObjectKind.table:
        return caption.isEmpty ? '[Table]' : 'Table: $caption';
      case _DocumentObjectKind.equation:
        final latex = _stringMetadata(block.metadata, const <String>['latex', 'source', 'equation']);
        if (latex.isNotEmpty) return latex;
        return block.text.isEmpty ? '[Equation]' : block.text;
      case _DocumentObjectKind.pageBreak:
        return '[Page break]';
      case _DocumentObjectKind.sectionBreak:
        return '[Section break]';
      case _DocumentObjectKind.divider:
        return '---';
      case _DocumentObjectKind.none:
      case _DocumentObjectKind.unknown:
        return block.text;
    }
  }
}

/// Block-level entry with all discovered semantic child units.
class TextSystemDocumentBlockIndexEntry {
  const TextSystemDocumentBlockIndexEntry({
    required this.block,
    required this.blockIndex,
    required this.start,
    required this.end,
    required this.units,
    required this.inlineAtoms,
  });

  final TextSystemBlock block;
  final int blockIndex;
  final TextSystemDocumentPosition start;
  final TextSystemDocumentPosition end;
  final List<TextSystemDocumentIndexUnit> units;
  final List<TextSystemInlineAtomIndexEntry> inlineAtoms;

  String get blockId => block.id;
  TextSystemBlockCapabilities get capabilities =>
      TextSystemBlockCapabilityRegistry.standard.capabilitiesFor(block);
  bool get isTextEditable => capabilities.isTextEditable;
  bool get isObjectBlock => capabilities.isAtomicObject;
  TextSystemDocumentRange get range => TextSystemDocumentRange(start: start, end: end);

  String get diagnosticLabel => '$blockIndex:$blockId:${block.type.name}';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'blockType': block.type.name,
      'capabilities': capabilities.toJson(),
      'start': start.toJson(),
      'end': end.toJson(),
      'units': units.map((unit) => unit.toJson()).toList(),
      if (inlineAtoms.isNotEmpty) 'inlineAtoms': inlineAtoms.map((atom) => atom.toJson()).toList(),
    };
  }
}


/// Coarse classification for a block-level fragment inside a structured slice.
///
/// This lets copy/delete/comment/citation pipelines reason about selections as:
/// a partial starting text block, full middle blocks/objects, and a partial end
/// text block without asking the UI widgets what happened.
enum TextSystemStructuredSlicePartKind {
  singleTextBlockRange,
  startPartialBlock,
  middleFullBlock,
  endPartialBlock,
  objectBlock,
}

/// One block-level part of a [TextSystemStructuredDocumentSlice].
class TextSystemStructuredSlicePart {
  const TextSystemStructuredSlicePart({
    required this.kind,
    required this.blockEntry,
    required this.range,
    required this.units,
    required this.inlineAtoms,
    required this.textMarks,
  });

  final TextSystemStructuredSlicePartKind kind;
  final TextSystemDocumentBlockIndexEntry blockEntry;
  final TextSystemDocumentRange range;
  final List<TextSystemDocumentIndexUnit> units;
  final List<TextSystemInlineAtomIndexEntry> inlineAtoms;
  final List<TextMark> textMarks;

  TextSystemBlock get block => blockEntry.block;
  String get blockId => blockEntry.blockId;
  int get blockIndex => blockEntry.blockIndex;

  bool get isObject => kind == TextSystemStructuredSlicePartKind.objectBlock;
  bool get isFullBlock =>
      kind == TextSystemStructuredSlicePartKind.middleFullBlock || isObject;
  bool get isPartial => !isFullBlock;

  TextSystemRange get textRange {
    if (!_isTextEditableBlock(block)) return TextSystemRange.collapsed(0);
    return TextSystemRange(
      range.normalized().start.offset.clamp(0, block.length).toInt(),
      range.normalized().end.offset.clamp(0, block.length).toInt(),
    );
  }

  String get plainText {
    if (isObject) return TextSystemDocumentIndexUnit._objectPlainText(block);
    final selectedRange = textRange.clamp(block.length);
    if (selectedRange.isCollapsed) return '';
    return block.text.substring(selectedRange.start, selectedRange.end);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'blockId': blockId,
      'blockIndex': blockIndex,
      'blockType': block.type.name,
      'range': range.toJson(),
      if (_isTextEditableBlock(block)) 'textRange': textRange.toJson(),
      'unitCount': units.length,
      'inlineAtoms': inlineAtoms.map((atom) => atom.toJson()).toList(),
      if (textMarks.isNotEmpty)
        'textMarks': textMarks.map((mark) => mark.toJson()).toList(),
      'capabilities': blockEntry.capabilities.toJson(),
    };
  }
}

/// Structured, model-layer description of the content covered by a document
/// range.
///
/// This is the core payload future selection/copy/delete/comment/citation/source
/// workflows should consume. It deliberately separates the backend document
/// slice from any visual selection overlay.
class TextSystemStructuredDocumentSlice {
  const TextSystemStructuredDocumentSlice({
    required this.range,
    required this.parts,
    required this.units,
    required this.inlineAtoms,
    required this.textMarks,
  });

  final TextSystemDocumentRange range;
  final List<TextSystemStructuredSlicePart> parts;
  final List<TextSystemDocumentIndexUnit> units;
  final List<TextSystemInlineAtomIndexEntry> inlineAtoms;
  final List<TextMark> textMarks;

  bool get isEmpty => parts.isEmpty;

  List<TextSystemStructuredSlicePart> get textParts {
    return parts.where((part) => !part.isObject).toList(growable: false);
  }

  List<TextSystemStructuredSlicePart> get objectParts {
    return parts.where((part) => part.isObject).toList(growable: false);
  }

  TextSystemStructuredSlicePart? get startPartialBlock {
    for (final part in parts) {
      if (part.kind == TextSystemStructuredSlicePartKind.startPartialBlock ||
          part.kind == TextSystemStructuredSlicePartKind.singleTextBlockRange) {
        return part;
      }
    }
    return null;
  }

  List<TextSystemStructuredSlicePart> get middleFullBlocks {
    return parts
        .where((part) =>
            part.kind == TextSystemStructuredSlicePartKind.middleFullBlock || part.isObject)
        .toList(growable: false);
  }

  TextSystemStructuredSlicePart? get endPartialBlock {
    for (final part in parts.reversed) {
      if (part.kind == TextSystemStructuredSlicePartKind.endPartialBlock ||
          part.kind == TextSystemStructuredSlicePartKind.singleTextBlockRange) {
        return part;
      }
    }
    return null;
  }

  List<TextSystemInlineAtomIndexEntry> get crossReferences => inlineAtoms
      .where((atom) => atom.kind == TextSystemInlineAtomKind.crossReference)
      .toList(growable: false);

  List<TextSystemInlineAtomIndexEntry> get citations => inlineAtoms
      .where((atom) => atom.kind == TextSystemInlineAtomKind.citation)
      .toList(growable: false);

  List<TextSystemInlineAtomIndexEntry> get sourceLinks => inlineAtoms
      .where((atom) => atom.kind == TextSystemInlineAtomKind.sourceLink)
      .toList(growable: false);

  List<TextSystemInlineAtomIndexEntry> get documentLinks => inlineAtoms
      .where((atom) => atom.kind == TextSystemInlineAtomKind.documentLink)
      .toList(growable: false);

  List<TextMark> get commentMarks => textMarks
      .where((mark) => _markHasSemanticHint(mark, const <String>['comment', 'annotation']))
      .toList(growable: false);

  List<TextMark> get citationMarks => textMarks
      .where((mark) => _markHasSemanticHint(mark, const <String>['citation', 'cite']))
      .toList(growable: false);

  List<TextMark> get sourceLinkMarks => textMarks
      .where((mark) => _markHasSemanticHint(mark, const <String>['source', 'pdf', 'locator']))
      .toList(growable: false);

  String get plainText {
    final buffer = StringBuffer();
    String? previousBlockId;
    for (final part in parts) {
      final text = part.plainText;
      if (text.isEmpty) continue;
      if (previousBlockId != null && previousBlockId != part.blockId && buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(text);
      previousBlockId = part.blockId;
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'range': range.toJson(),
      'parts': parts.map((part) => part.toJson()).toList(),
      'unitCount': units.length,
      'inlineAtoms': inlineAtoms.map((atom) => atom.toJson()).toList(),
      if (textMarks.isNotEmpty)
        'textMarks': textMarks.map((mark) => mark.toJson()).toList(),
      'summary': <String, Object?>{
        'textPartCount': textParts.length,
        'objectPartCount': objectParts.length,
        'inlineAtomCount': inlineAtoms.length,
        'crossReferenceCount': crossReferences.length,
        'citationCount': citations.length,
        'sourceLinkCount': sourceLinks.length,
        'commentMarkCount': commentMarks.length,
      },
    };
  }
}

/// Result of resolving a document range through [TextSystemDocumentIndex].
class TextSystemDocumentIndexSlice {
  const TextSystemDocumentIndexSlice({
    required this.range,
    required this.units,
    required this.blocks,
    required this.inlineAtoms,
  });

  final TextSystemDocumentRange range;
  final List<TextSystemDocumentIndexUnit> units;
  final List<TextSystemDocumentBlockIndexEntry> blocks;
  final List<TextSystemInlineAtomIndexEntry> inlineAtoms;

  bool get isEmpty => units.isEmpty && blocks.isEmpty && inlineAtoms.isEmpty;
  bool get spansMultipleBlocks => range.normalized().spansMultipleBlocks;

  List<TextSystemDocumentIndexUnit> get textMarks {
    return units.where((unit) => unit.kind == TextSystemDocumentUnitKind.textMark).toList(growable: false);
  }

  List<TextSystemInlineAtomIndexEntry> get crossReferences => inlineAtoms
      .where((atom) => atom.kind == TextSystemInlineAtomKind.crossReference)
      .toList(growable: false);

  List<TextSystemInlineAtomIndexEntry> get citations => inlineAtoms
      .where((atom) => atom.kind == TextSystemInlineAtomKind.citation)
      .toList(growable: false);

  List<TextSystemInlineAtomIndexEntry> get sourceLinks => inlineAtoms
      .where((atom) => atom.kind == TextSystemInlineAtomKind.sourceLink)
      .toList(growable: false);

  List<TextSystemDocumentIndexUnit> get commentMarks {
    return textMarks
        .where((unit) => unit.mark != null &&
            _markHasSemanticHint(unit.mark!, const <String>['comment', 'annotation']))
        .toList(growable: false);
  }

  String get plainText {
    if (units.isEmpty) return '';
    final buffer = StringBuffer();
    String? previousBlockId;
    for (final unit in units) {
      if (unit.isBlockBoundary) continue;
      final unitText = unit.plainText;
      if (unitText.isEmpty) continue;
      if (previousBlockId != null && previousBlockId != unit.blockId && buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(unitText);
      previousBlockId = unit.blockId;
    }
    return buffer.toString();
  }

  String get diagnosticLabel {
    final unitLabels = units.map((unit) => unit.diagnosticLabel).join(', ');
    return '${range.diagnosticLabel} [$unitLabels]';
  }
}

/// Linearized semantic index for a [TextSystemDocument].
class TextSystemDocumentIndex {
  const TextSystemDocumentIndex({
    required this.documentId,
    required this.blockEntries,
    required this.units,
    required this.inlineAtoms,
  });

  factory TextSystemDocumentIndex.fromDocument(TextSystemDocument document) {
    final blockEntries = <TextSystemDocumentBlockIndexEntry>[];
    final units = <TextSystemDocumentIndexUnit>[];
    final inlineAtoms = <TextSystemInlineAtomIndexEntry>[];

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex += 1) {
      final block = document.blocks[blockIndex];
      final entryUnits = <TextSystemDocumentIndexUnit>[];
      final entryAtoms = _scanInlineAtoms(block, blockIndex);
      inlineAtoms.addAll(entryAtoms);

      final start = TextSystemDocumentPosition.beforeBlock(
        blockId: block.id,
        blockIndex: blockIndex,
      );
      final end = TextSystemDocumentPosition.afterBlock(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: block.length,
      );

      void addUnit(TextSystemDocumentIndexUnit unit) {
        entryUnits.add(unit);
        units.add(unit);
      }

      addUnit(TextSystemDocumentIndexUnit(
        kind: TextSystemDocumentUnitKind.blockStart,
        blockId: block.id,
        blockIndex: blockIndex,
        start: start,
        end: TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: blockIndex,
          offset: 0,
        ),
        block: block,
      ));

      final capabilities = TextSystemBlockCapabilityRegistry.standard.capabilitiesFor(block);
      final objectKind = _semanticKindForBlock(block);
      if (!capabilities.isAtomicObject && capabilities.isTextEditable) {
        _appendTextUnits(
          block: block,
          blockIndex: blockIndex,
          atoms: entryAtoms,
          addUnit: addUnit,
        );
        _appendMarkUnits(block: block, blockIndex: blockIndex, addUnit: addUnit);
      } else {
        addUnit(TextSystemDocumentIndexUnit(
          kind: _unitKindForObject(objectKind),
          blockId: block.id,
          blockIndex: blockIndex,
          start: TextSystemDocumentPosition.onBlock(
            blockId: block.id,
            blockIndex: blockIndex,
          ),
          end: end,
          block: block,
          metadata: <String, Object?>{
            'blockType': block.type.name,
            'semanticKind': capabilities.semanticKind.name,
            if (objectKind != _DocumentObjectKind.none) 'objectKind': objectKind.name,
          },
        ));
      }

      addUnit(TextSystemDocumentIndexUnit(
        kind: TextSystemDocumentUnitKind.blockEnd,
        blockId: block.id,
        blockIndex: blockIndex,
        start: TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: blockIndex,
          offset: block.length,
        ),
        end: end,
        block: block,
      ));

      blockEntries.add(TextSystemDocumentBlockIndexEntry(
        block: block,
        blockIndex: blockIndex,
        start: start,
        end: end,
        units: List<TextSystemDocumentIndexUnit>.unmodifiable(entryUnits),
        inlineAtoms: List<TextSystemInlineAtomIndexEntry>.unmodifiable(entryAtoms),
      ));
    }

    return TextSystemDocumentIndex(
      documentId: document.id,
      blockEntries: List<TextSystemDocumentBlockIndexEntry>.unmodifiable(blockEntries),
      units: List<TextSystemDocumentIndexUnit>.unmodifiable(units),
      inlineAtoms: List<TextSystemInlineAtomIndexEntry>.unmodifiable(inlineAtoms),
    );
  }

  final String documentId;
  final List<TextSystemDocumentBlockIndexEntry> blockEntries;
  final List<TextSystemDocumentIndexUnit> units;
  final List<TextSystemInlineAtomIndexEntry> inlineAtoms;

  Map<String, TextSystemDocumentBlockIndexEntry> get blockEntryById {
    return <String, TextSystemDocumentBlockIndexEntry>{
      for (final entry in blockEntries) entry.blockId: entry,
    };
  }

  TextSystemDocumentBlockIndexEntry? entryForBlockId(String blockId) {
    for (final entry in blockEntries) {
      if (entry.blockId == blockId) return entry;
    }
    return null;
  }

  TextSystemDocumentBlockIndexEntry? entryForBlockIndex(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= blockEntries.length) return null;
    return blockEntries[blockIndex];
  }

  TextSystemDocumentIndexSlice sliceForRange(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    final selectedUnits = <TextSystemDocumentIndexUnit>[];
    final selectedBlocks = <TextSystemDocumentBlockIndexEntry>[];
    final selectedAtoms = <TextSystemInlineAtomIndexEntry>[];

    for (final unit in units) {
      if (_unitIntersectsRange(unit, normalized)) selectedUnits.add(unit);
    }

    for (final entry in blockEntries) {
      if (_positionsOverlap(entry.start, entry.end, normalized.start, normalized.end)) {
        selectedBlocks.add(entry);
      }
    }

    for (final atom in inlineAtoms) {
      if (_rangeContainsOrOverlapsInlineAtom(normalized, atom)) selectedAtoms.add(atom);
    }

    return TextSystemDocumentIndexSlice(
      range: normalized,
      units: List<TextSystemDocumentIndexUnit>.unmodifiable(selectedUnits),
      blocks: List<TextSystemDocumentBlockIndexEntry>.unmodifiable(selectedBlocks),
      inlineAtoms: List<TextSystemInlineAtomIndexEntry>.unmodifiable(selectedAtoms),
    );
  }

  TextSystemStructuredDocumentSlice structuredSliceForRange(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    final parts = <TextSystemStructuredSlicePart>[];
    final selectedUnits = <TextSystemDocumentIndexUnit>[];
    final selectedAtoms = <TextSystemInlineAtomIndexEntry>[];
    final selectedMarks = <TextMark>[];

    for (final entry in blockEntries) {
      if (!_positionsOverlap(entry.start, entry.end, normalized.start, normalized.end)) {
        continue;
      }

      final block = entry.block;
      final isObject = entry.isObjectBlock;
      final isText = entry.isTextEditable;
      if (isObject || !isText) {
        final unitRange = TextSystemDocumentRange(
          start: entry.start,
          end: entry.end,
        );
        final unitList = entry.units
            .where((unit) => _unitIntersectsRange(unit, normalized))
            .toList(growable: false);
        parts.add(TextSystemStructuredSlicePart(
          kind: TextSystemStructuredSlicePartKind.objectBlock,
          blockEntry: entry,
          range: unitRange,
          units: unitList,
          inlineAtoms: const <TextSystemInlineAtomIndexEntry>[],
          textMarks: const <TextMark>[],
        ));
        selectedUnits.addAll(unitList);
        continue;
      }

      final selectedTextRange = _textRangeForBlockWithinRange(entry, normalized);
      if (selectedTextRange.isCollapsed && !normalized.isCollapsed) {
        continue;
      }

      final partRange = TextSystemDocumentRange(
        start: TextSystemDocumentPosition.text(
          blockId: entry.blockId,
          blockIndex: entry.blockIndex,
          offset: selectedTextRange.start,
        ),
        end: TextSystemDocumentPosition.text(
          blockId: entry.blockId,
          blockIndex: entry.blockIndex,
          offset: selectedTextRange.end,
        ),
      );
      final partUnits = entry.units
          .where((unit) => _unitIntersectsTextRange(unit, selectedTextRange))
          .toList(growable: false);
      final partAtoms = entry.inlineAtoms
          .where((atom) => atom.range.overlaps(selectedTextRange))
          .toList(growable: false);
      final partMarks = entry.block.marks
          .map((mark) => mark.clamp(entry.block.length))
          .where((mark) => !mark.isEmpty && mark.range.overlaps(selectedTextRange))
          .toList(growable: false);

      parts.add(TextSystemStructuredSlicePart(
        kind: _slicePartKindForEntry(entry, normalized, selectedTextRange),
        blockEntry: entry,
        range: partRange,
        units: partUnits,
        inlineAtoms: partAtoms,
        textMarks: partMarks,
      ));
      selectedUnits.addAll(partUnits);
      selectedAtoms.addAll(partAtoms);
      selectedMarks.addAll(partMarks);
    }

    return TextSystemStructuredDocumentSlice(
      range: normalized,
      parts: List<TextSystemStructuredSlicePart>.unmodifiable(parts),
      units: List<TextSystemDocumentIndexUnit>.unmodifiable(selectedUnits),
      inlineAtoms: List<TextSystemInlineAtomIndexEntry>.unmodifiable(selectedAtoms),
      textMarks: List<TextMark>.unmodifiable(selectedMarks),
    );
  }

  /// Alias with a user-facing name for future copy/delete/comment/citation
  /// pipelines.
  TextSystemStructuredDocumentSlice structuredContentForRange(TextSystemDocumentRange range) {
    return structuredSliceForRange(range);
  }

  List<TextSystemInlineAtomIndexEntry> inlineAtomsForBlock(String blockId) {
    return inlineAtoms.where((atom) => atom.blockId == blockId).toList(growable: false);
  }

  TextSystemInlineAtomIndexEntry? inlineAtomAtPosition(TextSystemDocumentPosition position) {
    for (final atom in inlineAtoms) {
      if (atom.blockId != position.blockId) continue;
      if (position.offset >= atom.range.start && position.offset <= atom.range.end) return atom;
    }
    return null;
  }

  TextSystemDocumentPosition? positionForBlockOffset({
    required String blockId,
    required int offset,
  }) {
    final entry = entryForBlockId(blockId);
    if (entry == null) return null;
    final safeOffset = offset.clamp(0, entry.block.length).toInt();
    return TextSystemDocumentPosition.text(
      blockId: blockId,
      blockIndex: entry.blockIndex,
      offset: safeOffset,
    );
  }

  String plainTextForRange(TextSystemDocumentRange range) => sliceForRange(range).plainText;

  Map<String, Object?> toDiagnosticsJson() {
    return <String, Object?>{
      'documentId': documentId,
      'blocks': blockEntries.map((entry) => entry.toJson()).toList(),
      'unitCount': units.length,
      'inlineAtomCount': inlineAtoms.length,
      'capabilitySummary': _capabilitySummary(),
    };
  }

  Map<String, Object?> _capabilitySummary() {
    final byKind = <String, int>{};
    var textEditable = 0;
    var atomicObjects = 0;
    var crossReferenceable = 0;
    for (final entry in blockEntries) {
      final capabilities = entry.capabilities;
      byKind.update(capabilities.semanticKind.name, (value) => value + 1, ifAbsent: () => 1);
      if (capabilities.isTextEditable) textEditable += 1;
      if (capabilities.isAtomicObject) atomicObjects += 1;
      if (capabilities.canBeCrossReferenced) crossReferenceable += 1;
    }
    return <String, Object?>{
      'bySemanticKind': byKind,
      'textEditableBlocks': textEditable,
      'atomicObjects': atomicObjects,
      'crossReferenceableBlocks': crossReferenceable,
    };
  }
}

typedef _DocumentIndexUnitSink = void Function(TextSystemDocumentIndexUnit unit);

enum _DocumentObjectKind {
  none,
  figure,
  table,
  equation,
  pageBreak,
  sectionBreak,
  divider,
  unknown,
}

void _appendTextUnits({
  required TextSystemBlock block,
  required int blockIndex,
  required List<TextSystemInlineAtomIndexEntry> atoms,
  required _DocumentIndexUnitSink addUnit,
}) {
  final sortedAtoms = atoms.toList()..sort((a, b) => a.range.start.compareTo(b.range.start));
  var cursor = 0;

  for (final atom in sortedAtoms) {
    final start = atom.range.start.clamp(0, block.length).toInt();
    final end = atom.range.end.clamp(start, block.length).toInt();
    if (start > cursor) {
      _addTextRun(block, blockIndex, cursor, start, addUnit);
    }
    addUnit(TextSystemDocumentIndexUnit(
      kind: TextSystemDocumentUnitKind.inlineAtom,
      blockId: block.id,
      blockIndex: blockIndex,
      start: TextSystemDocumentPosition.inlineAtom(
        blockId: block.id,
        blockIndex: blockIndex,
        atomId: atom.id,
        atomStartOffset: start,
        atomEndOffset: end,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: end,
      ),
      text: atom.displayText,
      inlineAtom: atom,
      metadata: atom.metadata,
    ));
    cursor = end;
  }

  if (cursor < block.length) {
    _addTextRun(block, blockIndex, cursor, block.length, addUnit);
  }

  if (block.length == 0 && sortedAtoms.isEmpty) {
    _addTextRun(block, blockIndex, 0, 0, addUnit);
  }
}

void _addTextRun(
  TextSystemBlock block,
  int blockIndex,
  int startOffset,
  int endOffset,
  _DocumentIndexUnitSink addUnit,
) {
  final safeStart = startOffset.clamp(0, block.length).toInt();
  final safeEnd = endOffset.clamp(safeStart, block.length).toInt();
  addUnit(TextSystemDocumentIndexUnit(
    kind: TextSystemDocumentUnitKind.textRun,
    blockId: block.id,
    blockIndex: blockIndex,
    start: TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: safeStart,
    ),
    end: TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: safeEnd,
    ),
    text: block.text.substring(safeStart, safeEnd),
    block: block,
  ));
}

void _appendMarkUnits({
  required TextSystemBlock block,
  required int blockIndex,
  required _DocumentIndexUnitSink addUnit,
}) {
  for (final mark in block.marks) {
    final range = mark.range.clamp(block.length);
    if (range.isCollapsed) continue;
    addUnit(TextSystemDocumentIndexUnit(
      kind: TextSystemDocumentUnitKind.textMark,
      blockId: block.id,
      blockIndex: blockIndex,
      start: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: range.start,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: range.end,
      ),
      mark: mark,
      block: block,
      metadata: <String, Object?>{
        'markKind': mark.kind.name,
        if (mark.attributes.isNotEmpty) 'attributes': mark.attributes,
      },
    ));
  }
}

List<TextSystemInlineAtomIndexEntry> _scanInlineAtoms(TextSystemBlock block, int blockIndex) {
  if (!_isTextEditableBlock(block)) return const <TextSystemInlineAtomIndexEntry>[];
  final atoms = <TextSystemInlineAtomIndexEntry>[];
  atoms.addAll(_scanInlineMathAtoms(block, blockIndex));
  atoms.addAll(_scanMarkedInlineAtoms(block, blockIndex));
  atoms.sort((a, b) {
    final startCompare = a.range.start.compareTo(b.range.start);
    if (startCompare != 0) return startCompare;
    return a.range.end.compareTo(b.range.end);
  });
  return _removeOverlappingAtoms(atoms);
}

List<TextSystemInlineAtomIndexEntry> _scanInlineMathAtoms(TextSystemBlock block, int blockIndex) {
  final atoms = <TextSystemInlineAtomIndexEntry>[];
  final expression = RegExp(r'\\\((.+?)\\\)');
  var index = 0;
  for (final match in expression.allMatches(block.text)) {
    final source = match.group(0) ?? '';
    final latex = match.group(1) ?? '';
    atoms.add(TextSystemInlineAtomIndexEntry(
      id: '${block.id}:math:$index:${match.start}-${match.end}',
      kind: TextSystemInlineAtomKind.math,
      blockId: block.id,
      blockIndex: blockIndex,
      range: TextSystemRange(match.start, match.end),
      sourceText: source,
      displayText: latex,
      metadata: <String, Object?>{
        'latex': latex,
        'source': source,
      },
    ));
    index += 1;
  }
  return atoms;
}

List<TextSystemInlineAtomIndexEntry> _scanMarkedInlineAtoms(TextSystemBlock block, int blockIndex) {
  final atoms = <TextSystemInlineAtomIndexEntry>[];
  var index = 0;
  for (final mark in block.marks) {
    final atomKind = _atomKindForMark(mark);
    if (atomKind == null) continue;
    final range = mark.range.clamp(block.length);
    if (range.isCollapsed) continue;
    final source = block.text.substring(range.start, range.end);
    atoms.add(TextSystemInlineAtomIndexEntry(
      id: mark.attributes['atomId'] ??
          mark.attributes['referenceId'] ??
          mark.attributes['targetBlockId'] ??
          '${block.id}:${atomKind.name}:$index:${range.start}-${range.end}',
      kind: atomKind,
      blockId: block.id,
      blockIndex: blockIndex,
      range: range,
      sourceText: source,
      displayText: mark.attributes['displayText'] ?? source,
      metadata: Map<String, Object?>.from(mark.attributes),
    ));
    index += 1;
  }
  return atoms;
}

List<TextSystemInlineAtomIndexEntry> _removeOverlappingAtoms(List<TextSystemInlineAtomIndexEntry> atoms) {
  final result = <TextSystemInlineAtomIndexEntry>[];
  var cursor = 0;
  for (final atom in atoms) {
    if (atom.range.start < cursor) continue;
    result.add(atom);
    cursor = atom.range.end;
  }
  return result;
}

TextSystemInlineAtomKind? _atomKindForMark(TextMark mark) {
  final rawKind = mark.attributes['atomKind'] ??
      mark.attributes['semanticKind'] ??
      mark.attributes['semanticType'] ??
      mark.attributes['referenceKind'] ??
      mark.attributes['type'];
  final normalized = _normalizeKind(rawKind);
  if (normalized.contains('math')) return TextSystemInlineAtomKind.math;
  if (normalized.contains('crossreference') || normalized.contains('crossref')) {
    return TextSystemInlineAtomKind.crossReference;
  }
  if (normalized.contains('citation') || normalized.contains('cite')) {
    return TextSystemInlineAtomKind.citation;
  }
  if (normalized.contains('sourcelink') || normalized == 'source') {
    return TextSystemInlineAtomKind.sourceLink;
  }
  if (normalized.contains('documentlink') || normalized == 'document') {
    return TextSystemInlineAtomKind.documentLink;
  }
  if (normalized.contains('todo')) return TextSystemInlineAtomKind.todo;
  if (normalized.contains('date') || normalized.contains('deadline')) {
    return TextSystemInlineAtomKind.date;
  }
  if (normalized.contains('tag')) return TextSystemInlineAtomKind.tag;

  if (mark.kind == TextMarkKind.link) {
    final target = _normalizeKind(mark.attributes['targetType'] ?? mark.attributes['targetKind']);
    if (target.contains('figure') || target.contains('table') || target.contains('equation')) {
      return TextSystemInlineAtomKind.crossReference;
    }
  }
  return null;
}

bool _unitIntersectsRange(TextSystemDocumentIndexUnit unit, TextSystemDocumentRange range) {
  if (unit.isBlockBoundary) return range.containsBlockIndex(unit.blockIndex);
  return _positionsOverlap(unit.start, unit.end, range.start, range.end);
}

bool _rangeContainsOrOverlapsInlineAtom(
  TextSystemDocumentRange range,
  TextSystemInlineAtomIndexEntry atom,
) {
  if (atom.blockIndex < range.start.blockIndex || atom.blockIndex > range.end.blockIndex) {
    return false;
  }
  final atomStart = atom.startPosition;
  final atomEnd = atom.endPosition;
  return _positionsOverlap(atomStart, atomEnd, range.start, range.end);
}

bool _positionsOverlap(
  TextSystemDocumentPosition aStart,
  TextSystemDocumentPosition aEnd,
  TextSystemDocumentPosition bStart,
  TextSystemDocumentPosition bEnd,
) {
  final aForward = aStart.compareTo(aEnd) <= 0;
  final bForward = bStart.compareTo(bEnd) <= 0;
  final startA = aForward ? aStart : aEnd;
  final endA = aForward ? aEnd : aStart;
  final startB = bForward ? bStart : bEnd;
  final endB = bForward ? bEnd : bStart;
  return startA.compareTo(endB) <= 0 && startB.compareTo(endA) <= 0;
}


TextSystemRange _textRangeForBlockWithinRange(
  TextSystemDocumentBlockIndexEntry entry,
  TextSystemDocumentRange range,
) {
  var start = 0;
  var end = entry.block.length;
  if (entry.blockIndex == range.start.blockIndex) {
    start = _textOffsetForPosition(range.start, entry.block.length);
  }
  if (entry.blockIndex == range.end.blockIndex) {
    end = _textOffsetForPosition(range.end, entry.block.length);
  }
  if (end < start) end = start;
  return TextSystemRange(start, end).clamp(entry.block.length);
}

int _textOffsetForPosition(TextSystemDocumentPosition position, int textLength) {
  switch (position.affinity) {
    case TextSystemDocumentPositionAffinity.beforeBlock:
      return 0;
    case TextSystemDocumentPositionAffinity.afterBlock:
    case TextSystemDocumentPositionAffinity.onBlock:
      return textLength;
    case TextSystemDocumentPositionAffinity.insideInlineAtom:
      return (position.atomStartOffset ?? position.offset).clamp(0, textLength).toInt();
    case TextSystemDocumentPositionAffinity.insideTableCell:
    case TextSystemDocumentPositionAffinity.textOffset:
      return position.offset.clamp(0, textLength).toInt();
  }
}

bool _unitIntersectsTextRange(TextSystemDocumentIndexUnit unit, TextSystemRange range) {
  if (unit.isBlockBoundary) return false;
  if (unit.isObject) return true;
  if (unit.start.blockIndex != unit.end.blockIndex) return true;
  final unitRange = TextSystemRange(
    unit.start.offset.clamp(0, 1 << 31).toInt(),
    unit.end.offset.clamp(unit.start.offset, 1 << 31).toInt(),
  );
  return unitRange.overlaps(range);
}

TextSystemStructuredSlicePartKind _slicePartKindForEntry(
  TextSystemDocumentBlockIndexEntry entry,
  TextSystemDocumentRange range,
  TextSystemRange selectedTextRange,
) {
  final sameStart = entry.blockIndex == range.start.blockIndex;
  final sameEnd = entry.blockIndex == range.end.blockIndex;
  final fullBlock = selectedTextRange.start == 0 && selectedTextRange.end == entry.block.length;
  if (sameStart && sameEnd) return TextSystemStructuredSlicePartKind.singleTextBlockRange;
  if (fullBlock && !sameStart && !sameEnd) {
    return TextSystemStructuredSlicePartKind.middleFullBlock;
  }
  if (sameStart) return TextSystemStructuredSlicePartKind.startPartialBlock;
  if (sameEnd) return TextSystemStructuredSlicePartKind.endPartialBlock;
  return TextSystemStructuredSlicePartKind.middleFullBlock;
}

bool _markHasSemanticHint(TextMark mark, List<String> hints) {
  final haystack = StringBuffer(mark.kind.name.toLowerCase());
  for (final entry in mark.attributes.entries) {
    haystack
      ..write(' ')
      ..write(entry.key.toLowerCase())
      ..write(' ')
      ..write(entry.value.toLowerCase());
  }
  final text = haystack.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  for (final hint in hints) {
    if (text.contains(hint.toLowerCase())) return true;
  }
  return false;
}

bool _isTextEditableBlock(TextSystemBlock block) {
  return TextSystemBlockCapabilityRegistry.standard.capabilitiesFor(block).isTextEditable;
}

TextSystemDocumentUnitKind _unitKindForObject(_DocumentObjectKind kind) {
  switch (kind) {
    case _DocumentObjectKind.figure:
      return TextSystemDocumentUnitKind.figureObject;
    case _DocumentObjectKind.table:
      return TextSystemDocumentUnitKind.tableObject;
    case _DocumentObjectKind.equation:
      return TextSystemDocumentUnitKind.equationObject;
    case _DocumentObjectKind.pageBreak:
      return TextSystemDocumentUnitKind.pageBreak;
    case _DocumentObjectKind.sectionBreak:
      return TextSystemDocumentUnitKind.sectionBreak;
    case _DocumentObjectKind.divider:
      return TextSystemDocumentUnitKind.divider;
    case _DocumentObjectKind.unknown:
      return TextSystemDocumentUnitKind.unknownObject;
    case _DocumentObjectKind.none:
      return TextSystemDocumentUnitKind.objectBlock;
  }
}

_DocumentObjectKind _semanticKindForBlock(TextSystemBlock block) {
  final capabilities = TextSystemBlockCapabilityRegistry.standard.capabilitiesFor(block);
  switch (capabilities.semanticKind) {
    case TextSystemBlockSemanticKind.figure:
      return _DocumentObjectKind.figure;
    case TextSystemBlockSemanticKind.table:
      return _DocumentObjectKind.table;
    case TextSystemBlockSemanticKind.equation:
      return _DocumentObjectKind.equation;
    case TextSystemBlockSemanticKind.pageBreak:
      return _DocumentObjectKind.pageBreak;
    case TextSystemBlockSemanticKind.sectionBreak:
      return _DocumentObjectKind.sectionBreak;
    case TextSystemBlockSemanticKind.divider:
      return _DocumentObjectKind.divider;
    case TextSystemBlockSemanticKind.unknownObject:
      return capabilities.isAtomicObject ? _DocumentObjectKind.unknown : _DocumentObjectKind.none;
    case TextSystemBlockSemanticKind.paragraph:
    case TextSystemBlockSemanticKind.heading:
    case TextSystemBlockSemanticKind.listItem:
    case TextSystemBlockSemanticKind.todo:
    case TextSystemBlockSemanticKind.quote:
    case TextSystemBlockSemanticKind.code:
      return _DocumentObjectKind.none;
  }
}

String _stringMetadata(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

String _normalizeKind(Object? value) {
  if (value == null) return '';
  return '$value'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
