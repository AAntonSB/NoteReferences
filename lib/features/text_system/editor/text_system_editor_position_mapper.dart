import '../core/text_system_block.dart';
import '../core/text_system_block_capabilities.dart';
import '../core/text_system_document.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_document_selection_controller.dart';
import '../core/text_system_document_selection_mapper.dart';

/// Pure document-coordinate helpers for the owned editor.
///
/// This class keeps block/position normalization and capability-aware decisions
/// out of widget code. It is safe to use from the current paged bridge, future
/// custom renderers, command handlers, diagnostics panels, and tests.
class TextSystemEditorPositionMapper {
  const TextSystemEditorPositionMapper._();

  static int resolveBlockIndex(
    TextSystemDocument document,
    TextSystemDocumentPosition position,
  ) {
    if (document.blocks.isEmpty) return 0;
    final byId = document.blocks.indexWhere((block) => block.id == position.blockId);
    if (byId >= 0) return byId;
    return position.blockIndex.clamp(0, document.blocks.length - 1).toInt();
  }

  static TextSystemBlock? blockForPosition(
    TextSystemDocument document,
    TextSystemDocumentPosition position,
  ) {
    if (document.blocks.isEmpty) return null;
    return document.blocks[resolveBlockIndex(document, position)];
  }

  static TextSystemDocumentPosition clampPosition(
    TextSystemDocument document,
    TextSystemDocumentPosition position,
  ) {
    final block = blockForPosition(document, position);
    if (block == null) {
      return TextSystemDocumentPosition.text(
        blockId: 'document-start',
        blockIndex: 0,
        offset: 0,
      );
    }

    final blockIndex = resolveBlockIndex(document, position);
    return position.copyWith(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: position.offset.clamp(0, block.text.length).toInt(),
    );
  }

  static TextSystemDocumentPosition? firstPosition(TextSystemDocument document) {
    if (document.blocks.isEmpty) return null;
    final block = document.blocks.first;
    return TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: 0,
      offset: 0,
    );
  }

  static TextSystemDocumentPosition? lastPosition(TextSystemDocument document) {
    if (document.blocks.isEmpty) return null;
    final blockIndex = document.blocks.length - 1;
    final block = document.blocks[blockIndex];
    return TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: block.text.length,
    );
  }

  static TextSystemDocumentPosition positionAtBlockStart(
    TextSystemDocument document,
    int blockIndex,
  ) {
    final safeIndex = _safeBlockIndex(document, blockIndex);
    final block = document.blocks[safeIndex];
    return TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: safeIndex,
      offset: 0,
    );
  }

  static TextSystemDocumentPosition positionAtBlockEnd(
    TextSystemDocument document,
    int blockIndex,
  ) {
    final safeIndex = _safeBlockIndex(document, blockIndex);
    final block = document.blocks[safeIndex];
    return TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: safeIndex,
      offset: block.text.length,
    );
  }

  static TextSystemDocumentPosition objectPositionForBlock(
    TextSystemDocument document,
    int blockIndex,
  ) {
    final safeIndex = _safeBlockIndex(document, blockIndex);
    final block = document.blocks[safeIndex];
    return TextSystemDocumentPosition.onBlock(
      blockId: block.id,
      blockIndex: safeIndex,
    );
  }

  static TextSystemDocumentRange rangeForWholeBlock(
    TextSystemDocument document,
    int blockIndex,
  ) {
    final safeIndex = _safeBlockIndex(document, blockIndex);
    final block = document.blocks[safeIndex];
    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: safeIndex,
        offset: 0,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: safeIndex,
        offset: block.text.length,
      ),
    );
  }

  static TextSystemDocumentSelection selectionForWholeBlock(
    TextSystemDocument document,
    int blockIndex, {
    TextSystemBlockCapabilityRegistry capabilityRegistry =
        TextSystemBlockCapabilityRegistry.standard,
  }) {
    final safeIndex = _safeBlockIndex(document, blockIndex);
    final block = document.blocks[safeIndex];
    final capabilities = capabilityRegistry.capabilitiesFor(block);
    if (capabilities.isAtomicObject || capabilities.supportsObjectSelection) {
      return TextSystemDocumentSelection.object(
        blockId: block.id,
        blockIndex: safeIndex,
        metadata: <String, Object?>{
          'semanticKind': capabilities.semanticKind.name,
          'displayName': capabilities.displayName,
        },
      );
    }

    return TextSystemDocumentSelection.range(
      anchor: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: safeIndex,
        offset: 0,
      ),
      focus: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: safeIndex,
        offset: block.text.length,
      ),
    );
  }

  static bool isTextEditableBlock(
    TextSystemBlock block, {
    TextSystemBlockCapabilityRegistry capabilityRegistry =
        TextSystemBlockCapabilityRegistry.standard,
  }) {
    return capabilityRegistry.capabilitiesFor(block).isTextEditable;
  }

  static bool isAtomicObjectBlock(
    TextSystemBlock block, {
    TextSystemBlockCapabilityRegistry capabilityRegistry =
        TextSystemBlockCapabilityRegistry.standard,
  }) {
    return capabilityRegistry.capabilitiesFor(block).isAtomicObject;
  }

  static String describePosition(
    TextSystemDocument document,
    TextSystemDocumentPosition position,
  ) {
    final clamped = clampPosition(document, position);
    return TextSystemDocumentSelectionMapper.describePosition(document, clamped);
  }

  static String describeRange(
    TextSystemDocument document,
    TextSystemDocumentRange range,
  ) {
    return TextSystemDocumentSelectionMapper.describeRange(document, range.normalized());
  }

  static int _safeBlockIndex(TextSystemDocument document, int blockIndex) {
    if (document.blocks.isEmpty) {
      throw StateError('Cannot resolve a block position in an empty document.');
    }
    return blockIndex.clamp(0, document.blocks.length - 1).toInt();
  }
}
