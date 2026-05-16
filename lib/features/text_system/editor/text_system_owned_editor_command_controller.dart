import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/text_mark.dart';
import '../references/actions/text_system_reference_actions.dart';

/// Public command target boundary implemented by the owned editor surface.
///
/// Keeping this interface in the controller file avoids a cyclic import between
/// the command bridge and the editor widget while still letting the Premium
/// Writer toolbar talk to the owned editor through document-level commands.
abstract class TextSystemOwnedEditorCommandTarget {
  bool get ownedCommandTargetMounted;
  bool get ownedCanCreateReference;
  bool get ownedCanUndo;
  bool get ownedCanRedo;
  bool get ownedCanCopySelection;
  bool get ownedCanCutSelection;
  bool get ownedCanPastePlainText;
  bool get ownedCanChangeActiveBlockStyle;
  bool get ownedCanInsertAtSelection;
  bool get ownedCanInsertEmbeddedTodo;

  bool get ownedHasSelectedObject;
  String get ownedSelectedObjectKind;
  String get ownedSelectedObjectStatusLabel;
  bool get ownedCanMoveSelectedObjectUp;
  bool get ownedCanMoveSelectedObjectDown;
  bool get ownedCanDuplicateSelectedObject;
  bool get ownedCanDeleteSelectedObject;
  bool get ownedCanCopySelectedObjectReference;
  bool get ownedCanCommentOnSelectedObject;

  bool ownedCanToggleMark(TextMarkKind kind);
  bool ownedActiveRangeFullyCoveredBy(TextMarkKind kind);

  void ownedPerformUndo();
  void ownedPerformRedo();
  Future<void> ownedCopySelectionToClipboard();
  Future<void> ownedCutSelectionToClipboard();
  Future<void> ownedPasteAtSelection();
  void ownedChangeActiveBlockStyleById(String styleId);
  void ownedInsertPageBreak();
  void ownedInsertSectionBreak();
  void ownedInsertFootnote();
  Future<void> ownedInsertEmbeddedTodo();
  Future<void> ownedInsertFigure();
  Future<void> ownedInsertTable();
  Future<void> ownedInsertEquation();
  Future<void> ownedInsertInlineMath();
  Future<void> ownedCopySelectedObjectReferenceToClipboard();
  Future<void> ownedAddCommentToSelectedObject();
  void ownedDuplicateSelectedObject();
  void ownedMoveSelectedObjectUp();
  void ownedMoveSelectedObjectDown();
  void ownedDeleteSelectedObject();
  void ownedToggleMarkForActiveRange(TextMarkKind kind);
  Future<void> ownedCreateReferenceForActiveSelection(TextSystemReferenceActionType actionType);
}

/// Command bridge for the owned document editor.
///
/// This mirrors the command-facing surface of the current paged editor without
/// sharing its TextField-backed internals. The Premium Writer header can ask
/// this controller whether a document selection exists and can dispatch copy,
/// cut, paste, formatting, and reference actions against the owned editor's
/// document-level selection model.
class TextSystemOwnedEditorCommandController extends ChangeNotifier {
  TextSystemOwnedEditorCommandTarget? _state;
  Timer? _stateRefreshTimer;
  int _stateRevision = 0;

  /// Monotonic counter used by parent widgets to rebuild toolbar affordances.
  int get stateRevision => _stateRevision;

  bool get isAttached => _state?.ownedCommandTargetMounted == true;

  bool get canRunEditorCommand {
    final state = _state;
    return state != null && state.ownedCommandTargetMounted;
  }

  bool get canCreateReference => canRunEditorCommand && (_state?.ownedCanCreateReference ?? false);

  bool get canUndo => canRunEditorCommand && (_state?.ownedCanUndo ?? false);
  bool get canRedo => canRunEditorCommand && (_state?.ownedCanRedo ?? false);
  bool get canCopySelection => canRunEditorCommand && (_state?.ownedCanCopySelection ?? false);
  bool get canCutSelection => canRunEditorCommand && (_state?.ownedCanCutSelection ?? false);
  bool get canPastePlainText => canRunEditorCommand && (_state?.ownedCanPastePlainText ?? false);
  bool get canChangeActiveBlockStyle => canRunEditorCommand && (_state?.ownedCanChangeActiveBlockStyle ?? false);
  bool get canInsertAtSelection => canRunEditorCommand && (_state?.ownedCanInsertAtSelection ?? false);
  bool get canInsertEmbeddedTodo => canRunEditorCommand && (_state?.ownedCanInsertEmbeddedTodo ?? false);

  bool get hasSelectedObject => canRunEditorCommand && (_state?.ownedHasSelectedObject ?? false);
  String get selectedObjectKind => _state?.ownedSelectedObjectKind ?? '';
  String get selectedObjectStatusLabel => _state?.ownedSelectedObjectStatusLabel ?? '';
  bool get canMoveSelectedObjectUp => canRunEditorCommand && (_state?.ownedCanMoveSelectedObjectUp ?? false);
  bool get canMoveSelectedObjectDown => canRunEditorCommand && (_state?.ownedCanMoveSelectedObjectDown ?? false);
  bool get canDuplicateSelectedObject => canRunEditorCommand && (_state?.ownedCanDuplicateSelectedObject ?? false);
  bool get canDeleteSelectedObject => canRunEditorCommand && (_state?.ownedCanDeleteSelectedObject ?? false);
  bool get canCopySelectedObjectReference => canRunEditorCommand && (_state?.ownedCanCopySelectedObjectReference ?? false);
  bool get canCommentOnSelectedObject => canRunEditorCommand && (_state?.ownedCanCommentOnSelectedObject ?? false);

  bool get canToggleBold => canRunEditorCommand && (_state?.ownedCanToggleMark(TextMarkKind.bold) ?? false);
  bool get canToggleItalic => canRunEditorCommand && (_state?.ownedCanToggleMark(TextMarkKind.italic) ?? false);
  bool get canToggleUnderline => canRunEditorCommand && (_state?.ownedCanToggleMark(TextMarkKind.underline) ?? false);
  bool get canToggleCode => canRunEditorCommand && (_state?.ownedCanToggleMark(TextMarkKind.code) ?? false);
  bool get canToggleHighlight => canRunEditorCommand && (_state?.ownedCanToggleMark(TextMarkKind.highlight) ?? false);

  bool get boldActive => _state?.ownedActiveRangeFullyCoveredBy(TextMarkKind.bold) ?? false;
  bool get italicActive => _state?.ownedActiveRangeFullyCoveredBy(TextMarkKind.italic) ?? false;
  bool get underlineActive => _state?.ownedActiveRangeFullyCoveredBy(TextMarkKind.underline) ?? false;
  bool get codeActive => _state?.ownedActiveRangeFullyCoveredBy(TextMarkKind.code) ?? false;
  bool get highlightActive => _state?.ownedActiveRangeFullyCoveredBy(TextMarkKind.highlight) ?? false;

  void attachSurface(TextSystemOwnedEditorCommandTarget state) {
    _state = state;
    scheduleStateRefresh();
  }

  void detachSurface(TextSystemOwnedEditorCommandTarget state) {
    if (identical(_state, state)) {
      _state = null;
      scheduleStateRefresh();
    }
  }

  void scheduleStateRefresh() {
    if (_stateRefreshTimer?.isActive ?? false) return;
    _stateRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      _stateRefreshTimer = null;
      _stateRevision++;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _stateRefreshTimer?.cancel();
    _stateRefreshTimer = null;
    super.dispose();
  }

  void undo() => _state?.ownedPerformUndo();
  void redo() => _state?.ownedPerformRedo();

  Future<void> copySelection() async => _state?.ownedCopySelectionToClipboard();
  Future<void> cutSelection() async => _state?.ownedCutSelectionToClipboard();
  Future<void> pastePlainText() async => _state?.ownedPasteAtSelection();

  void changeActiveBlockStyleById(String styleId) => _state?.ownedChangeActiveBlockStyleById(styleId);
  void insertPageBreak() => _state?.ownedInsertPageBreak();
  void insertSectionBreak() => _state?.ownedInsertSectionBreak();
  void insertFootnote() => _state?.ownedInsertFootnote();
  Future<void> insertEmbeddedTodo() async => _state?.ownedInsertEmbeddedTodo();
  Future<void> insertFigure() async => _state?.ownedInsertFigure();
  Future<void> insertTable() async => _state?.ownedInsertTable();
  Future<void> insertEquation() async => _state?.ownedInsertEquation();
  Future<void> insertInlineMath() async => _state?.ownedInsertInlineMath();

  Future<void> copySelectedObjectReference() async => _state?.ownedCopySelectedObjectReferenceToClipboard();
  Future<void> addCommentToSelectedObject() async => _state?.ownedAddCommentToSelectedObject();
  void duplicateSelectedObject() => _state?.ownedDuplicateSelectedObject();
  void moveSelectedObjectUp() => _state?.ownedMoveSelectedObjectUp();
  void moveSelectedObjectDown() => _state?.ownedMoveSelectedObjectDown();
  void deleteSelectedObject() => _state?.ownedDeleteSelectedObject();

  void toggleBold() => _state?.ownedToggleMarkForActiveRange(TextMarkKind.bold);
  void toggleItalic() => _state?.ownedToggleMarkForActiveRange(TextMarkKind.italic);
  void toggleUnderline() => _state?.ownedToggleMarkForActiveRange(TextMarkKind.underline);
  void toggleInlineCode() => _state?.ownedToggleMarkForActiveRange(TextMarkKind.code);
  void toggleHighlight() => _state?.ownedToggleMarkForActiveRange(TextMarkKind.highlight);

  Future<void> runReferenceAction(TextSystemReferenceActionType actionType) async {
    await _state?.ownedCreateReferenceForActiveSelection(actionType);
  }
}
