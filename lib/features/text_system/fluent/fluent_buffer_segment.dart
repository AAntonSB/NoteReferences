import '../core/text_system_block.dart';
import '../core/text_system_document_position.dart';

/// Maps one visible line inside the fluent editor buffer back to one internal
/// text-system block.
///
/// The user never sees this concept. It is the bridge that lets a single
/// continuous Flutter text editor keep the structured document model underneath.
class FluentBufferSegment {
  const FluentBufferSegment({
    required this.blockId,
    required this.blockIndex,
    required this.blockType,
    required this.bufferStart,
    required this.bufferEnd,
    required this.contentStart,
    required this.contentEnd,
    this.level,
    this.checked,
    this.ordered = false,
  })  : assert(bufferStart >= 0),
        assert(bufferEnd >= bufferStart),
        assert(contentStart >= bufferStart),
        assert(contentEnd >= contentStart),
        assert(contentEnd <= bufferEnd);

  final String blockId;
  final int blockIndex;
  final TextSystemBlockType blockType;
  final int bufferStart;
  final int bufferEnd;
  final int contentStart;
  final int contentEnd;
  final int? level;
  final bool? checked;
  final bool ordered;

  int get bufferLength => bufferEnd - bufferStart;
  int get contentLength => contentEnd - contentStart;
  int get prefixLength => contentStart - bufferStart;

  bool containsBufferOffset(int offset) => offset >= bufferStart && offset <= bufferEnd;

  TextSystemDocumentPosition positionForBufferOffset(int offset) {
    final local = (offset - contentStart).clamp(0, contentLength).toInt();
    return TextSystemDocumentPosition(
      blockId: blockId,
      blockIndex: blockIndex,
      offset: local,
    );
  }

  int bufferOffsetForBlockOffset(int offset) {
    return (contentStart + offset.clamp(0, contentLength)).clamp(bufferStart, bufferEnd).toInt();
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'blockType': blockType.name,
      'bufferStart': bufferStart,
      'bufferEnd': bufferEnd,
      'contentStart': contentStart,
      'contentEnd': contentEnd,
      if (level != null) 'level': level,
      if (checked != null) 'checked': checked,
      if (ordered) 'ordered': true,
    };
  }

  @override
  String toString() {
    return 'FluentBufferSegment(block: $blockId#$blockIndex, type: ${blockType.name}, buffer: $bufferStart-$bufferEnd, content: $contentStart-$contentEnd)';
  }
}
