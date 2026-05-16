import 'package:flutter/foundation.dart';

import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_document_selection_controller.dart';
import 'text_system_editor_hit_test.dart';

/// Source that last changed the editor-level selection state.
enum TextSystemEditorSelectionSource {
  none,
  pointer,
  keyboard,
  command,
  textInput,
  programmatic,
}

/// Owned-editor selection state boundary.
///
/// This object deliberately wraps the existing model-level
/// [TextSystemDocumentSelection] with interaction lifecycle metadata. It gives
/// the future surface one state object for caret, drag selection, object
/// selection, keyboard extension, and command-driven updates without depending
/// on `_PagedEditableBlockField` or other legacy widget internals.
@immutable
class TextSystemEditorSelectionState {
  const TextSystemEditorSelectionState({
    this.selection,
    this.interactionMode = TextSystemEditorInteractionMode.idle,
    this.dragPhase = TextSystemDocumentSelectionDragPhase.inactive,
    this.anchorHit,
    this.focusHit,
    this.source = TextSystemEditorSelectionSource.none,
  });

  factory TextSystemEditorSelectionState.idle() {
    return const TextSystemEditorSelectionState();
  }

  factory TextSystemEditorSelectionState.collapsed(
    TextSystemDocumentPosition position, {
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.programmatic,
    TextSystemEditorHitTestResult? hit,
  }) {
    return TextSystemEditorSelectionState(
      selection: TextSystemDocumentSelection.collapsed(position),
      interactionMode: TextSystemEditorInteractionMode.editingText,
      dragPhase: TextSystemDocumentSelectionDragPhase.inactive,
      anchorHit: hit,
      focusHit: hit,
      source: source,
    );
  }

  factory TextSystemEditorSelectionState.object({
    required String blockId,
    required int blockIndex,
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.programmatic,
    TextSystemEditorHitTestResult? hit,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return TextSystemEditorSelectionState(
      selection: TextSystemDocumentSelection.object(
        blockId: blockId,
        blockIndex: blockIndex,
        metadata: metadata,
      ),
      interactionMode: TextSystemEditorInteractionMode.selectingObject,
      dragPhase: TextSystemDocumentSelectionDragPhase.inactive,
      anchorHit: hit,
      focusHit: hit,
      source: source,
    );
  }

  factory TextSystemEditorSelectionState.fromHit(
    TextSystemEditorHitTestResult hit, {
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.pointer,
  }) {
    final position = hit.position;
    if (position == null) {
      return TextSystemEditorSelectionState(
        anchorHit: hit,
        focusHit: hit,
        source: source,
      );
    }

    if (hit.isObjectLike || position.isOnBlock) {
      return TextSystemEditorSelectionState.object(
        blockId: position.blockId,
        blockIndex: position.blockIndex,
        source: source,
        hit: hit,
        metadata: <String, Object?>{
          'hitKind': hit.kind.name,
        },
      );
    }

    if (hit.isInlineAtom || position.isInlineAtom) {
      return TextSystemEditorSelectionState(
        selection: TextSystemDocumentSelection.inlineAtom(
          blockId: position.blockId,
          blockIndex: position.blockIndex,
          atomStartOffset: position.atomStartOffset ?? position.offset,
          atomEndOffset: position.atomEndOffset ?? position.offset,
          atomId: position.atomId,
          metadata: <String, Object?>{
            'hitKind': hit.kind.name,
          },
        ),
        interactionMode: TextSystemEditorInteractionMode.editingInlineAtom,
        anchorHit: hit,
        focusHit: hit,
        source: source,
      );
    }

    if (hit.isTableCell || position.isTableCell) {
      return TextSystemEditorSelectionState(
        selection: TextSystemDocumentSelection.tableCell(
          blockId: position.blockId,
          blockIndex: position.blockIndex,
          row: position.tableRow ?? 0,
          column: position.tableColumn ?? 0,
          metadata: <String, Object?>{
            'hitKind': hit.kind.name,
          },
        ),
        interactionMode: TextSystemEditorInteractionMode.editingTableCell,
        anchorHit: hit,
        focusHit: hit,
        source: source,
      );
    }

    return TextSystemEditorSelectionState.collapsed(
      position,
      source: source,
      hit: hit,
    );
  }

  final TextSystemDocumentSelection? selection;
  final TextSystemEditorInteractionMode interactionMode;
  final TextSystemDocumentSelectionDragPhase dragPhase;
  final TextSystemEditorHitTestResult? anchorHit;
  final TextSystemEditorHitTestResult? focusHit;
  final TextSystemEditorSelectionSource source;

  bool get hasSelection => selection != null;
  bool get isCollapsed => selection?.isCollapsed ?? true;
  bool get isDragging => dragPhase == TextSystemDocumentSelectionDragPhase.dragging;
  bool get isObjectSelection => selection?.isObject ?? false;
  bool get isTextRange => selection?.isRange ?? false;
  TextSystemDocumentRange? get range => selection?.range;
  TextSystemDocumentPosition? get anchor => selection?.anchor;
  TextSystemDocumentPosition? get focus => selection?.focus;

  TextSystemEditorSelectionState beginDrag(
    TextSystemEditorHitTestResult hit,
  ) {
    final position = hit.position;
    if (position == null) {
      return copyWith(
        anchorHit: hit,
        focusHit: hit,
        dragPhase: TextSystemDocumentSelectionDragPhase.pending,
        interactionMode: TextSystemEditorInteractionMode.selectingText,
        source: TextSystemEditorSelectionSource.pointer,
      );
    }

    return TextSystemEditorSelectionState(
      selection: TextSystemDocumentSelection.collapsed(position),
      interactionMode: TextSystemEditorInteractionMode.selectingText,
      dragPhase: TextSystemDocumentSelectionDragPhase.pending,
      anchorHit: hit,
      focusHit: hit,
      source: TextSystemEditorSelectionSource.pointer,
    );
  }

  TextSystemEditorSelectionState updateDragFocus(
    TextSystemEditorHitTestResult hit,
  ) {
    final currentAnchor = anchor;
    final focusPosition = hit.position;
    if (currentAnchor == null || focusPosition == null) {
      return copyWith(
        focusHit: hit,
        dragPhase: TextSystemDocumentSelectionDragPhase.dragging,
        source: TextSystemEditorSelectionSource.pointer,
      );
    }

    return copyWith(
      selection: TextSystemDocumentSelection.range(
        anchor: currentAnchor,
        focus: focusPosition,
      ),
      focusHit: hit,
      dragPhase: TextSystemDocumentSelectionDragPhase.dragging,
      interactionMode: TextSystemEditorInteractionMode.selectingText,
      source: TextSystemEditorSelectionSource.pointer,
    );
  }

  TextSystemEditorSelectionState commitDrag() {
    final currentSelection = selection;
    final nextMode = currentSelection?.isObject == true
        ? TextSystemEditorInteractionMode.selectingObject
        : currentSelection?.isRange == true
            ? TextSystemEditorInteractionMode.selectingText
            : TextSystemEditorInteractionMode.editingText;
    return copyWith(
      dragPhase: TextSystemDocumentSelectionDragPhase.committed,
      interactionMode: nextMode,
    );
  }

  TextSystemEditorSelectionState cancelDrag() {
    return copyWith(
      dragPhase: TextSystemDocumentSelectionDragPhase.canceled,
      interactionMode: TextSystemEditorInteractionMode.idle,
    );
  }

  TextSystemEditorSelectionState clear() {
    return const TextSystemEditorSelectionState();
  }

  TextSystemEditorSelectionState copyWith({
    TextSystemDocumentSelection? selection,
    bool clearSelection = false,
    TextSystemEditorInteractionMode? interactionMode,
    TextSystemDocumentSelectionDragPhase? dragPhase,
    TextSystemEditorHitTestResult? anchorHit,
    bool clearAnchorHit = false,
    TextSystemEditorHitTestResult? focusHit,
    bool clearFocusHit = false,
    TextSystemEditorSelectionSource? source,
  }) {
    return TextSystemEditorSelectionState(
      selection: clearSelection ? null : selection ?? this.selection,
      interactionMode: interactionMode ?? this.interactionMode,
      dragPhase: dragPhase ?? this.dragPhase,
      anchorHit: clearAnchorHit ? null : anchorHit ?? this.anchorHit,
      focusHit: clearFocusHit ? null : focusHit ?? this.focusHit,
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toDiagnosticsJson() {
    return <String, Object?>{
      'selection': selection?.toJson(),
      'interactionMode': interactionMode.name,
      'dragPhase': dragPhase.name,
      'source': source.name,
      if (anchorHit != null) 'anchorHit': anchorHit!.toDiagnosticsJson(),
      if (focusHit != null) 'focusHit': focusHit!.toDiagnosticsJson(),
    };
  }
}
