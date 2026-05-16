/// Internal document-coordinate position for the TextSystem editor.
///
/// This is deliberately not a visual/widget coordinate. It is the shared
/// backend coordinate that lets the editor describe carets, selections,
/// comments, citations, source links, cross-references, and future AI actions
/// against the structured document model.
///
/// The legacy text position shape is preserved:
///
/// ```dart
/// TextSystemDocumentPosition(blockId: ..., blockIndex: ..., offset: ...)
/// ```
///
/// Existing callers can keep using that constructor. Newer systems can also
/// distinguish between text offsets, block boundaries, selected object blocks,
/// inline atoms, and table cells through [affinity] and the optional metadata
/// fields.
enum TextSystemDocumentPositionAffinity {
  /// A caret/selection position at [offset] inside a text-bearing block.
  textOffset,

  /// A logical insertion point immediately before the block.
  beforeBlock,

  /// A logical insertion point immediately after the block.
  afterBlock,

  /// The block itself as an atomic object, for figures/tables/equations/page
  /// breaks/section breaks and other non-text blocks.
  onBlock,

  /// A semantic inline object inside a text-bearing block, such as inline math,
  /// a cross-reference, a citation, or a source link.
  insideInlineAtom,

  /// A structured position inside a table block.
  insideTableCell,
}

class TextSystemDocumentPosition implements Comparable<TextSystemDocumentPosition> {
  const TextSystemDocumentPosition({
    required this.blockId,
    required this.blockIndex,
    required this.offset,
    this.affinity = TextSystemDocumentPositionAffinity.textOffset,
    this.atomId,
    this.atomStartOffset,
    this.atomEndOffset,
    this.tableRow,
    this.tableColumn,
  })  : assert(blockIndex >= 0),
        assert(offset >= 0),
        assert(atomStartOffset == null || atomStartOffset >= 0),
        assert(atomEndOffset == null || atomEndOffset >= 0),
        assert(tableRow == null || tableRow >= 0),
        assert(tableColumn == null || tableColumn >= 0);

  factory TextSystemDocumentPosition.text({
    required String blockId,
    required int blockIndex,
    required int offset,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: offset,
    );
  }

  factory TextSystemDocumentPosition.beforeBlock({
    required String blockId,
    required int blockIndex,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: 0,
      affinity: TextSystemDocumentPositionAffinity.beforeBlock,
    );
  }

  factory TextSystemDocumentPosition.afterBlock({
    required String blockId,
    required int blockIndex,
    int offset = 0,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: offset,
      affinity: TextSystemDocumentPositionAffinity.afterBlock,
    );
  }

  factory TextSystemDocumentPosition.onBlock({
    required String blockId,
    required int blockIndex,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: 0,
      affinity: TextSystemDocumentPositionAffinity.onBlock,
    );
  }

  factory TextSystemDocumentPosition.inlineAtom({
    required String blockId,
    required int blockIndex,
    required int atomStartOffset,
    required int atomEndOffset,
    String? atomId,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: atomStartOffset,
      affinity: TextSystemDocumentPositionAffinity.insideInlineAtom,
      atomId: atomId,
      atomStartOffset: atomStartOffset,
      atomEndOffset: atomEndOffset,
    );
  }

  factory TextSystemDocumentPosition.tableCell({
    required String blockId,
    required int blockIndex,
    required int row,
    required int column,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: 0,
      affinity: TextSystemDocumentPositionAffinity.insideTableCell,
      tableRow: row,
      tableColumn: column,
    );
  }

  factory TextSystemDocumentPosition.fromJson(Map<String, Object?> json) {
    final blockIndex = ((json['blockIndex'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31).toInt();
    final offset = ((json['offset'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31).toInt();
    final affinityName = json['affinity'] as String?;
    final affinity = TextSystemDocumentPositionAffinity.values.firstWhere(
      (value) => value.name == affinityName,
      orElse: () => TextSystemDocumentPositionAffinity.textOffset,
    );

    int? optionalInt(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return null;
    }

    return TextSystemDocumentPosition(
      blockId: json['blockId'] as String? ?? 'block',
      blockIndex: blockIndex,
      offset: offset,
      affinity: affinity,
      atomId: json['atomId'] as String?,
      atomStartOffset: optionalInt('atomStartOffset'),
      atomEndOffset: optionalInt('atomEndOffset'),
      tableRow: optionalInt('tableRow'),
      tableColumn: optionalInt('tableColumn'),
    );
  }

  /// Stable block identity. This should survive layout changes and pagination.
  final String blockId;

  /// Current document-order index. This is useful for ordering, but [blockId]
  /// remains the durable identity.
  final int blockIndex;

  /// Text offset for text-bearing positions. For object/table positions this is
  /// a deterministic ordering offset, not necessarily a user-visible character.
  final int offset;

  /// Describes what kind of document location this position represents.
  final TextSystemDocumentPositionAffinity affinity;

  /// Optional inline atom identity for semantic inline objects.
  final String? atomId;

  /// Source-buffer offsets occupied by an inline atom when this position refers
  /// to inline math, a cross-reference, a citation, or a future source chip.
  final int? atomStartOffset;
  final int? atomEndOffset;

  /// Optional table-cell coordinates when the position is inside a table block.
  final int? tableRow;
  final int? tableColumn;

  bool get isTextOffset => affinity == TextSystemDocumentPositionAffinity.textOffset;
  bool get isBeforeBlock => affinity == TextSystemDocumentPositionAffinity.beforeBlock;
  bool get isAfterBlock => affinity == TextSystemDocumentPositionAffinity.afterBlock;
  bool get isOnBlock => affinity == TextSystemDocumentPositionAffinity.onBlock;
  bool get isInlineAtom => affinity == TextSystemDocumentPositionAffinity.insideInlineAtom;
  bool get isTableCell => affinity == TextSystemDocumentPositionAffinity.insideTableCell;
  bool get isBlockBoundary => isBeforeBlock || isAfterBlock;

  int get inlineAtomLength {
    final start = atomStartOffset;
    final end = atomEndOffset;
    if (start == null || end == null || end < start) return 0;
    return end - start;
  }

  TextSystemDocumentPosition copyWith({
    String? blockId,
    int? blockIndex,
    int? offset,
    TextSystemDocumentPositionAffinity? affinity,
    String? atomId,
    bool clearAtomId = false,
    int? atomStartOffset,
    bool clearAtomStartOffset = false,
    int? atomEndOffset,
    bool clearAtomEndOffset = false,
    int? tableRow,
    bool clearTableRow = false,
    int? tableColumn,
    bool clearTableColumn = false,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId ?? this.blockId,
      blockIndex: blockIndex ?? this.blockIndex,
      offset: offset ?? this.offset,
      affinity: affinity ?? this.affinity,
      atomId: clearAtomId ? null : atomId ?? this.atomId,
      atomStartOffset: clearAtomStartOffset ? null : atomStartOffset ?? this.atomStartOffset,
      atomEndOffset: clearAtomEndOffset ? null : atomEndOffset ?? this.atomEndOffset,
      tableRow: clearTableRow ? null : tableRow ?? this.tableRow,
      tableColumn: clearTableColumn ? null : tableColumn ?? this.tableColumn,
    );
  }

  @override
  int compareTo(TextSystemDocumentPosition other) {
    final blockCompare = blockIndex.compareTo(other.blockIndex);
    if (blockCompare != 0) return blockCompare;

    final offsetCompare = _orderingOffset.compareTo(other._orderingOffset);
    if (offsetCompare != 0) return offsetCompare;

    final affinityCompare = _affinityOrder.compareTo(other._affinityOrder);
    if (affinityCompare != 0) return affinityCompare;

    final rowCompare = (tableRow ?? -1).compareTo(other.tableRow ?? -1);
    if (rowCompare != 0) return rowCompare;

    final columnCompare = (tableColumn ?? -1).compareTo(other.tableColumn ?? -1);
    if (columnCompare != 0) return columnCompare;

    return (atomId ?? '').compareTo(other.atomId ?? '');
  }

  int get _orderingOffset {
    switch (affinity) {
      case TextSystemDocumentPositionAffinity.beforeBlock:
        return -2;
      case TextSystemDocumentPositionAffinity.onBlock:
        return -1;
      case TextSystemDocumentPositionAffinity.textOffset:
      case TextSystemDocumentPositionAffinity.insideInlineAtom:
      case TextSystemDocumentPositionAffinity.insideTableCell:
        return offset;
      case TextSystemDocumentPositionAffinity.afterBlock:
        return 1 << 30;
    }
  }

  int get _affinityOrder {
    switch (affinity) {
      case TextSystemDocumentPositionAffinity.beforeBlock:
        return 0;
      case TextSystemDocumentPositionAffinity.onBlock:
        return 1;
      case TextSystemDocumentPositionAffinity.textOffset:
        return 2;
      case TextSystemDocumentPositionAffinity.insideInlineAtom:
        return 3;
      case TextSystemDocumentPositionAffinity.insideTableCell:
        return 4;
      case TextSystemDocumentPositionAffinity.afterBlock:
        return 5;
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'offset': offset,
      'affinity': affinity.name,
      if (atomId != null) 'atomId': atomId,
      if (atomStartOffset != null) 'atomStartOffset': atomStartOffset,
      if (atomEndOffset != null) 'atomEndOffset': atomEndOffset,
      if (tableRow != null) 'tableRow': tableRow,
      if (tableColumn != null) 'tableColumn': tableColumn,
    };
  }

  String get diagnosticLabel {
    switch (affinity) {
      case TextSystemDocumentPositionAffinity.textOffset:
        return '$blockId@$offset';
      case TextSystemDocumentPositionAffinity.beforeBlock:
        return 'before($blockId)';
      case TextSystemDocumentPositionAffinity.afterBlock:
        return 'after($blockId)';
      case TextSystemDocumentPositionAffinity.onBlock:
        return 'object($blockId)';
      case TextSystemDocumentPositionAffinity.insideInlineAtom:
        return 'atom(${atomId ?? '$blockId:$atomStartOffset-$atomEndOffset'})';
      case TextSystemDocumentPositionAffinity.insideTableCell:
        return 'cell($blockId:${tableRow ?? 0},${tableColumn ?? 0})';
    }
  }

  @override
  String toString() {
    return 'TextSystemDocumentPosition('
        'blockId: $blockId, '
        'blockIndex: $blockIndex, '
        'offset: $offset, '
        'affinity: ${affinity.name}, '
        'atomId: $atomId, '
        'atomStartOffset: $atomStartOffset, '
        'atomEndOffset: $atomEndOffset, '
        'tableRow: $tableRow, '
        'tableColumn: $tableColumn)';
  }

  @override
  bool operator ==(Object other) {
    return other is TextSystemDocumentPosition &&
        other.blockId == blockId &&
        other.blockIndex == blockIndex &&
        other.offset == offset &&
        other.affinity == affinity &&
        other.atomId == atomId &&
        other.atomStartOffset == atomStartOffset &&
        other.atomEndOffset == atomEndOffset &&
        other.tableRow == tableRow &&
        other.tableColumn == tableColumn;
  }

  @override
  int get hashCode {
    return Object.hash(
      blockId,
      blockIndex,
      offset,
      affinity,
      atomId,
      atomStartOffset,
      atomEndOffset,
      tableRow,
      tableColumn,
    );
  }
}
