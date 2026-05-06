import '../core/text_system_document.dart';
import '../core/text_system_document_position.dart';
import 'fluent_buffer_segment.dart';

/// Continuous editable projection of a [TextSystemDocument].
///
/// This is deliberately a projection, not the source of truth. The structured
/// document remains authoritative; this buffer exists so Flutter can expose one
/// native selection across the whole document.
class FluentDocumentBuffer {
  const FluentDocumentBuffer({
    required this.document,
    required this.text,
    required this.segments,
  });

  final TextSystemDocument document;
  final String text;
  final List<FluentBufferSegment> segments;

  int get length => text.length;
  bool get isEmpty => text.isEmpty;

  FluentBufferSegment? segmentForOffset(int offset) {
    if (segments.isEmpty) return null;
    final clamped = offset.clamp(0, text.length).toInt();
    for (final segment in segments) {
      if (segment.containsBufferOffset(clamped)) return segment;
    }
    return clamped >= text.length ? segments.last : segments.first;
  }

  TextSystemDocumentPosition positionForOffset(int offset) {
    final segment = segmentForOffset(offset);
    if (segment == null) {
      return const TextSystemDocumentPosition(blockId: 'document-start', blockIndex: 0, offset: 0);
    }
    return segment.positionForBufferOffset(offset);
  }

  int offsetForPosition(TextSystemDocumentPosition position) {
    if (segments.isEmpty) return 0;
    final byId = segments.where((segment) => segment.blockId == position.blockId).toList();
    final segment = byId.isNotEmpty
        ? byId.first
        : segments[position.blockIndex.clamp(0, segments.length - 1).toInt()];
    return segment.bufferOffsetForBlockOffset(position.offset);
  }

  List<Map<String, Object?>> debugSegments() {
    return segments.map((segment) => segment.toJson()).toList();
  }
}
