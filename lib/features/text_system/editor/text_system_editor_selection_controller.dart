import 'package:flutter/foundation.dart';

import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_document_selection_controller.dart';
import 'text_system_editor_hit_test.dart';
import 'text_system_editor_selection_state.dart';

/// Owned-editor controller for caret, object selection, and pointer range
/// selection.
///
/// This controller is intentionally editor-facing. It wraps the existing
/// model-level [TextSystemDocumentSelection] through
/// [TextSystemEditorSelectionState], but it also tracks the pointer lifecycle
/// needed by the owned surface. The important boundary is that gestures update
/// document positions/ranges here; rendering remains a projection of this state
/// plus the layout index.
class TextSystemEditorSelectionController extends ChangeNotifier {
  TextSystemEditorSelectionController({
    TextSystemEditorSelectionState? initialState,
  }) : _state = initialState ?? TextSystemEditorSelectionState.idle();

  TextSystemEditorSelectionState _state;

  TextSystemEditorSelectionState get state => _state;
  bool get hasSelection => _state.hasSelection;
  bool get isDragging => _state.isDragging;
  bool get hasRangeSelection => _state.selection?.isRange ?? false;
  bool get hasObjectSelection => _state.selection?.isObject ?? false;
  TextSystemDocumentPosition? get anchor => _state.anchor;
  TextSystemDocumentPosition? get focus => _state.focus;

  void clear() {
    _setState(TextSystemEditorSelectionState.idle());
  }

  void collapseTo(
    TextSystemDocumentPosition position, {
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.programmatic,
    TextSystemEditorHitTestResult? hit,
  }) {
    _setState(TextSystemEditorSelectionState.collapsed(
      position,
      source: source,
      hit: hit,
    ));
  }

  void selectFromHit(
    TextSystemEditorHitTestResult hit, {
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.pointer,
  }) {
    _setState(TextSystemEditorSelectionState.fromHit(hit, source: source));
  }

  void selectDocumentRange(
    TextSystemDocumentRange range, {
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.programmatic,
  }) {
    _setState(TextSystemEditorSelectionState(
      selection: TextSystemDocumentSelection.range(
        anchor: range.start,
        focus: range.end,
      ),
      interactionMode: TextSystemEditorInteractionMode.selectingText,
      dragPhase: TextSystemDocumentSelectionDragPhase.committed,
      source: source,
    ));
  }

  void selectObject({
    required String blockId,
    required int blockIndex,
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.programmatic,
    TextSystemEditorHitTestResult? hit,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _setState(TextSystemEditorSelectionState.object(
      blockId: blockId,
      blockIndex: blockIndex,
      source: source,
      hit: hit,
      metadata: metadata,
    ));
  }

  void selectInlineAtom({
    required String blockId,
    required int blockIndex,
    required int atomStartOffset,
    required int atomEndOffset,
    String? atomId,
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.programmatic,
    TextSystemEditorHitTestResult? hit,
  }) {
    _setState(TextSystemEditorSelectionState(
      selection: TextSystemDocumentSelection.inlineAtom(
        blockId: blockId,
        blockIndex: blockIndex,
        atomStartOffset: atomStartOffset,
        atomEndOffset: atomEndOffset,
        atomId: atomId,
        metadata: <String, Object?>{
          if (hit != null) 'hitKind': hit.kind.name,
        },
      ),
      interactionMode: TextSystemEditorInteractionMode.editingInlineAtom,
      dragPhase: TextSystemDocumentSelectionDragPhase.committed,
      anchorHit: hit,
      focusHit: hit,
      source: source,
    ));
  }

  void beginPointerSelection(TextSystemEditorHitTestResult hit) {
    _setState(_state.beginDrag(hit));
  }

  void updatePointerSelection(TextSystemEditorHitTestResult hit) {
    _setState(_state.updateDragFocus(hit));
  }

  void commitPointerSelection() {
    _setState(_state.commitDrag());
  }

  void cancelPointerSelection({bool clearSelection = false}) {
    if (clearSelection) {
      _setState(TextSystemEditorSelectionState.idle().cancelDrag());
      return;
    }
    _setState(_state.cancelDrag());
  }

  void _setState(TextSystemEditorSelectionState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}
