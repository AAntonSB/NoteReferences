import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/text_system_block.dart';
import '../core/text_system_document.dart';
import '../core/text_system_document_layout_index.dart';
import '../core/text_system_document_position.dart';

/// Immutable editor-facing view of the current document and visual layout.
///
/// This is the seam the owned editor will consume instead of reaching into the
/// legacy paged surface state. It combines the model document with the latest
/// layout index and a small amount of viewport metadata while staying free of
/// widget-local caret, selection, and TextField state.
@immutable
class TextSystemEditorLayoutSnapshot {
  const TextSystemEditorLayoutSnapshot({
    required this.document,
    required this.layoutIndex,
    this.revision = 0,
    this.surfaceSize,
    this.viewportOffset = Offset.zero,
  });

  factory TextSystemEditorLayoutSnapshot.empty(TextSystemDocument document) {
    return TextSystemEditorLayoutSnapshot(
      document: document,
      layoutIndex: TextSystemDocumentLayoutIndex.empty(document.id),
    );
  }

  final TextSystemDocument document;
  final TextSystemDocumentLayoutIndex layoutIndex;

  /// Document/controller revision associated with this layout. A value of zero
  /// means the snapshot was not tied to a controller revision.
  final int revision;

  /// Size of the editor surface that produced [layoutIndex], when known.
  final Size? surfaceSize;

  /// Scroll/viewport offset used by the surface that produced [layoutIndex].
  /// The layout index itself remains in surface/global coordinates.
  final Offset viewportOffset;

  bool get isEmpty => document.blocks.isEmpty;
  int get blockCount => document.blocks.length;
  int get fragmentCount => layoutIndex.fragments.length;
  int get pageCount => layoutIndex.pages.length;
  bool get hasLayout => fragmentCount > 0;

  TextSystemBlock? blockAt(int index) {
    if (index < 0 || index >= document.blocks.length) return null;
    return document.blocks[index];
  }

  TextSystemBlock? blockById(String blockId) => document.blockById(blockId);

  int indexOfBlockId(String blockId) {
    return document.blocks.indexWhere((block) => block.id == blockId);
  }

  int resolveBlockIndex(TextSystemDocumentPosition position) {
    final byId = indexOfBlockId(position.blockId);
    if (byId >= 0) return byId;
    if (document.blocks.isEmpty) return 0;
    return position.blockIndex.clamp(0, document.blocks.length - 1).toInt();
  }

  TextSystemBlock? blockForPosition(TextSystemDocumentPosition position) {
    if (document.blocks.isEmpty) return null;
    return blockAt(resolveBlockIndex(position));
  }

  TextSystemDocumentPosition clampPosition(TextSystemDocumentPosition position) {
    final block = blockForPosition(position);
    if (block == null) {
      return TextSystemDocumentPosition.text(
        blockId: 'document-start',
        blockIndex: 0,
        offset: 0,
      );
    }

    final blockIndex = resolveBlockIndex(position);
    final safeOffset = position.offset.clamp(0, block.text.length).toInt();
    return position.copyWith(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: safeOffset,
    );
  }

  TextSystemDocumentPosition? get firstPosition {
    if (document.blocks.isEmpty) return null;
    final block = document.blocks.first;
    return TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: 0,
      offset: 0,
    );
  }

  TextSystemDocumentPosition? get lastPosition {
    if (document.blocks.isEmpty) return null;
    final blockIndex = document.blocks.length - 1;
    final block = document.blocks[blockIndex];
    return TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: block.text.length,
    );
  }

  TextSystemDocumentLayoutHit? hitAtGlobalOffset(
    Offset offset, {
    double tolerance = 0,
  }) {
    return layoutIndex.hitAtGlobalOffset(offset, tolerance: tolerance);
  }

  Rect? rectForPosition(TextSystemDocumentPosition position) {
    return layoutIndex.rectForPosition(clampPosition(position));
  }

  TextSystemEditorLayoutSnapshot copyWith({
    TextSystemDocument? document,
    TextSystemDocumentLayoutIndex? layoutIndex,
    int? revision,
    Size? surfaceSize,
    bool clearSurfaceSize = false,
    Offset? viewportOffset,
  }) {
    return TextSystemEditorLayoutSnapshot(
      document: document ?? this.document,
      layoutIndex: layoutIndex ?? this.layoutIndex,
      revision: revision ?? this.revision,
      surfaceSize: clearSurfaceSize ? null : surfaceSize ?? this.surfaceSize,
      viewportOffset: viewportOffset ?? this.viewportOffset,
    );
  }

  Map<String, Object?> toDiagnosticsJson() {
    return <String, Object?>{
      'documentId': document.id,
      'revision': revision,
      'blockCount': blockCount,
      'fragmentCount': fragmentCount,
      'pageCount': pageCount,
      'hasLayout': hasLayout,
      if (surfaceSize != null)
        'surfaceSize': <String, Object?>{
          'width': surfaceSize!.width,
          'height': surfaceSize!.height,
        },
      'viewportOffset': <String, Object?>{
        'dx': viewportOffset.dx,
        'dy': viewportOffset.dy,
      },
      'layout': layoutIndex.toDiagnosticsJson(),
    };
  }
}
