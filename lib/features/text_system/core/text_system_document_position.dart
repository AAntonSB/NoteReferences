/// Cursor position in the fluent document coordinate system.
///
/// This is not a user-facing "block selection" concept. It is the internal
/// bridge that lets a future continuous editor map one user text cursor into
/// the structured document model underneath.
class TextSystemDocumentPosition implements Comparable<TextSystemDocumentPosition> {
  const TextSystemDocumentPosition({
    required this.blockId,
    required this.blockIndex,
    required this.offset,
  })  : assert(blockIndex >= 0),
        assert(offset >= 0);

  factory TextSystemDocumentPosition.fromJson(Map<String, Object?> json) {
    final blockIndex = ((json['blockIndex'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31).toInt();
    final offset = ((json['offset'] as num?)?.toInt() ?? 0).clamp(0, 1 << 31).toInt();
    return TextSystemDocumentPosition(
      blockId: json['blockId'] as String? ?? 'block',
      blockIndex: blockIndex,
      offset: offset,
    );
  }

  final String blockId;
  final int blockIndex;
  final int offset;

  TextSystemDocumentPosition copyWith({
    String? blockId,
    int? blockIndex,
    int? offset,
  }) {
    return TextSystemDocumentPosition(
      blockId: blockId ?? this.blockId,
      blockIndex: blockIndex ?? this.blockIndex,
      offset: offset ?? this.offset,
    );
  }

  @override
  int compareTo(TextSystemDocumentPosition other) {
    final blockCompare = blockIndex.compareTo(other.blockIndex);
    if (blockCompare != 0) return blockCompare;
    return offset.compareTo(other.offset);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'offset': offset,
    };
  }

  @override
  String toString() => 'TextSystemDocumentPosition(blockId: $blockId, blockIndex: $blockIndex, offset: $offset)';

  @override
  bool operator ==(Object other) {
    return other is TextSystemDocumentPosition &&
        other.blockId == blockId &&
        other.blockIndex == blockIndex &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(blockId, blockIndex, offset);
}
