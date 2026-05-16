import 'package:flutter/foundation.dart';

import 'text_system_document_position.dart';
import 'text_system_document_range.dart';

/// High-level interaction mode for the document editor.
///
/// This intentionally describes the editor's current interaction context, not a
/// specific widget state. Paragraph fields, object blocks, inline atoms, table
/// cells, and future systems should report user intent to the central selection
/// controller instead of each owning incompatible selection state.
enum TextSystemEditorInteractionMode {
  idle,
  editingText,
  selectingText,
  selectingObject,
  editingObject,
  editingInlineAtom,
  editingTableCell,
  panningWorkspace,
}

/// Model-level selection kind.
///
/// The visual overlay should be derived from this model. The model itself must
/// stay independent of page widgets, scroll views, and rendered rectangles.
enum TextSystemDocumentSelectionKind {
  collapsed,
  textRange,
  object,
  inlineAtom,
  tableCell,
  mixedRange,
}

/// Direction of the current anchor/focus selection.
enum TextSystemDocumentSelectionDirection {
  collapsed,
  forward,
  backward,
}

/// Current drag lifecycle for document selection.
enum TextSystemDocumentSelectionDragPhase {
  inactive,
  pending,
  dragging,
  committed,
  canceled,
}

/// Immutable model object for the central document selection.
class TextSystemDocumentSelection {
  const TextSystemDocumentSelection({
    required this.kind,
    required this.anchor,
    required this.focus,
    this.objectBlockId,
    this.inlineAtomId,
    this.tableBlockId,
    this.tableRow,
    this.tableColumn,
    this.tableEndRow,
    this.tableEndColumn,
    this.metadata = const <String, Object?>{},
  });

  factory TextSystemDocumentSelection.collapsed(TextSystemDocumentPosition position) {
    return TextSystemDocumentSelection(
      kind: TextSystemDocumentSelectionKind.collapsed,
      anchor: position,
      focus: position,
    );
  }

  factory TextSystemDocumentSelection.range({
    required TextSystemDocumentPosition anchor,
    required TextSystemDocumentPosition focus,
  }) {
    return TextSystemDocumentSelection(
      kind: _rangeKindFor(anchor, focus),
      anchor: anchor,
      focus: focus,
    );
  }

  factory TextSystemDocumentSelection.object({
    required String blockId,
    required int blockIndex,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final position = TextSystemDocumentPosition.onBlock(
      blockId: blockId,
      blockIndex: blockIndex,
    );
    return TextSystemDocumentSelection(
      kind: TextSystemDocumentSelectionKind.object,
      anchor: position,
      focus: position,
      objectBlockId: blockId,
      metadata: metadata,
    );
  }

  factory TextSystemDocumentSelection.inlineAtom({
    required String blockId,
    required int blockIndex,
    required int atomStartOffset,
    required int atomEndOffset,
    String? atomId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final position = TextSystemDocumentPosition.inlineAtom(
      blockId: blockId,
      blockIndex: blockIndex,
      atomStartOffset: atomStartOffset,
      atomEndOffset: atomEndOffset,
      atomId: atomId,
    );
    return TextSystemDocumentSelection(
      kind: TextSystemDocumentSelectionKind.inlineAtom,
      anchor: position,
      focus: position,
      inlineAtomId: atomId,
      metadata: metadata,
    );
  }

  factory TextSystemDocumentSelection.tableCell({
    required String blockId,
    required int blockIndex,
    required int row,
    required int column,
    int? endRow,
    int? endColumn,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final anchor = TextSystemDocumentPosition.tableCell(
      blockId: blockId,
      blockIndex: blockIndex,
      row: row,
      column: column,
    );
    final focus = TextSystemDocumentPosition.tableCell(
      blockId: blockId,
      blockIndex: blockIndex,
      row: endRow ?? row,
      column: endColumn ?? column,
    );
    return TextSystemDocumentSelection(
      kind: TextSystemDocumentSelectionKind.tableCell,
      anchor: anchor,
      focus: focus,
      tableBlockId: blockId,
      tableRow: row,
      tableColumn: column,
      tableEndRow: endRow ?? row,
      tableEndColumn: endColumn ?? column,
      metadata: metadata,
    );
  }

  final TextSystemDocumentSelectionKind kind;
  final TextSystemDocumentPosition anchor;
  final TextSystemDocumentPosition focus;

  /// Populated for [TextSystemDocumentSelectionKind.object].
  final String? objectBlockId;

  /// Populated for [TextSystemDocumentSelectionKind.inlineAtom].
  final String? inlineAtomId;

  /// Populated for [TextSystemDocumentSelectionKind.tableCell].
  final String? tableBlockId;
  final int? tableRow;
  final int? tableColumn;
  final int? tableEndRow;
  final int? tableEndColumn;

  /// Feature-specific payload for future systems. This should stay small and
  /// diagnostic-friendly; semantic document data still belongs in the document
  /// model/marks/metadata, not only here.
  final Map<String, Object?> metadata;

  TextSystemDocumentRange get range {
    return TextSystemDocumentRange.fromAnchorFocus(anchor: anchor, focus: focus);
  }

  TextSystemDocumentRange get normalizedRange => range.normalized();

  bool get isCollapsed => kind == TextSystemDocumentSelectionKind.collapsed || anchor == focus;
  bool get isRange => kind == TextSystemDocumentSelectionKind.textRange || kind == TextSystemDocumentSelectionKind.mixedRange;
  bool get isObject => kind == TextSystemDocumentSelectionKind.object;
  bool get isInlineAtom => kind == TextSystemDocumentSelectionKind.inlineAtom;
  bool get isTableCell => kind == TextSystemDocumentSelectionKind.tableCell;

  TextSystemDocumentSelectionDirection get direction {
    final comparison = anchor.compareTo(focus);
    if (comparison == 0) return TextSystemDocumentSelectionDirection.collapsed;
    return comparison < 0
        ? TextSystemDocumentSelectionDirection.forward
        : TextSystemDocumentSelectionDirection.backward;
  }

  TextSystemDocumentPosition get extent => focus;
  TextSystemDocumentPosition get base => anchor;

  TextSystemDocumentSelection copyWith({
    TextSystemDocumentSelectionKind? kind,
    TextSystemDocumentPosition? anchor,
    TextSystemDocumentPosition? focus,
    String? objectBlockId,
    bool clearObjectBlockId = false,
    String? inlineAtomId,
    bool clearInlineAtomId = false,
    String? tableBlockId,
    bool clearTableBlockId = false,
    int? tableRow,
    bool clearTableRow = false,
    int? tableColumn,
    bool clearTableColumn = false,
    int? tableEndRow,
    bool clearTableEndRow = false,
    int? tableEndColumn,
    bool clearTableEndColumn = false,
    Map<String, Object?>? metadata,
  }) {
    return TextSystemDocumentSelection(
      kind: kind ?? this.kind,
      anchor: anchor ?? this.anchor,
      focus: focus ?? this.focus,
      objectBlockId: clearObjectBlockId ? null : objectBlockId ?? this.objectBlockId,
      inlineAtomId: clearInlineAtomId ? null : inlineAtomId ?? this.inlineAtomId,
      tableBlockId: clearTableBlockId ? null : tableBlockId ?? this.tableBlockId,
      tableRow: clearTableRow ? null : tableRow ?? this.tableRow,
      tableColumn: clearTableColumn ? null : tableColumn ?? this.tableColumn,
      tableEndRow: clearTableEndRow ? null : tableEndRow ?? this.tableEndRow,
      tableEndColumn: clearTableEndColumn ? null : tableEndColumn ?? this.tableEndColumn,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'anchor': anchor.toJson(),
      'focus': focus.toJson(),
      'direction': direction.name,
      if (objectBlockId != null) 'objectBlockId': objectBlockId,
      if (inlineAtomId != null) 'inlineAtomId': inlineAtomId,
      if (tableBlockId != null) 'tableBlockId': tableBlockId,
      if (tableRow != null) 'tableRow': tableRow,
      if (tableColumn != null) 'tableColumn': tableColumn,
      if (tableEndRow != null) 'tableEndRow': tableEndRow,
      if (tableEndColumn != null) 'tableEndColumn': tableEndColumn,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  String get diagnosticLabel {
    switch (kind) {
      case TextSystemDocumentSelectionKind.collapsed:
        return 'caret:${anchor.diagnosticLabel}';
      case TextSystemDocumentSelectionKind.textRange:
      case TextSystemDocumentSelectionKind.mixedRange:
        return '${kind.name}:${anchor.diagnosticLabel} → ${focus.diagnosticLabel}';
      case TextSystemDocumentSelectionKind.object:
        return 'object:${objectBlockId ?? anchor.blockId}';
      case TextSystemDocumentSelectionKind.inlineAtom:
        return 'inlineAtom:${inlineAtomId ?? anchor.diagnosticLabel}';
      case TextSystemDocumentSelectionKind.tableCell:
        return 'tableCell:${tableBlockId ?? anchor.blockId}:${tableRow ?? 0},${tableColumn ?? 0} → ${tableEndRow ?? tableRow ?? 0},${tableEndColumn ?? tableColumn ?? 0}';
    }
  }

  @override
  String toString() => 'TextSystemDocumentSelection(${diagnosticLabel})';

  @override
  bool operator ==(Object other) {
    return other is TextSystemDocumentSelection &&
        other.kind == kind &&
        other.anchor == anchor &&
        other.focus == focus &&
        other.objectBlockId == objectBlockId &&
        other.inlineAtomId == inlineAtomId &&
        other.tableBlockId == tableBlockId &&
        other.tableRow == tableRow &&
        other.tableColumn == tableColumn &&
        other.tableEndRow == tableEndRow &&
        other.tableEndColumn == tableEndColumn &&
        mapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode {
    return Object.hash(
      kind,
      anchor,
      focus,
      objectBlockId,
      inlineAtomId,
      tableBlockId,
      tableRow,
      tableColumn,
      tableEndRow,
      tableEndColumn,
      Object.hashAll(metadata.entries.map((entry) => Object.hash(entry.key, entry.value))),
    );
  }
}

TextSystemDocumentSelectionKind _rangeKindFor(
  TextSystemDocumentPosition anchor,
  TextSystemDocumentPosition focus,
) {
  if (anchor == focus) return TextSystemDocumentSelectionKind.collapsed;
  final touchesNonText =
      anchor.affinity != TextSystemDocumentPositionAffinity.textOffset ||
      focus.affinity != TextSystemDocumentPositionAffinity.textOffset;
  if (touchesNonText || anchor.blockId != focus.blockId) {
    return TextSystemDocumentSelectionKind.mixedRange;
  }
  return TextSystemDocumentSelectionKind.textRange;
}

/// Immutable drag-state snapshot for the central selection controller.
class TextSystemDocumentSelectionDragState {
  const TextSystemDocumentSelectionDragState({
    required this.phase,
    this.anchor,
    this.focus,
  });

  const TextSystemDocumentSelectionDragState.inactive()
      : phase = TextSystemDocumentSelectionDragPhase.inactive,
        anchor = null,
        focus = null;

  final TextSystemDocumentSelectionDragPhase phase;
  final TextSystemDocumentPosition? anchor;
  final TextSystemDocumentPosition? focus;

  bool get isActive =>
      phase == TextSystemDocumentSelectionDragPhase.pending ||
      phase == TextSystemDocumentSelectionDragPhase.dragging;

  TextSystemDocumentSelectionDragState copyWith({
    TextSystemDocumentSelectionDragPhase? phase,
    TextSystemDocumentPosition? anchor,
    bool clearAnchor = false,
    TextSystemDocumentPosition? focus,
    bool clearFocus = false,
  }) {
    return TextSystemDocumentSelectionDragState(
      phase: phase ?? this.phase,
      anchor: clearAnchor ? null : anchor ?? this.anchor,
      focus: clearFocus ? null : focus ?? this.focus,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'phase': phase.name,
      if (anchor != null) 'anchor': anchor!.toJson(),
      if (focus != null) 'focus': focus!.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TextSystemDocumentSelectionDragState &&
        other.phase == phase &&
        other.anchor == anchor &&
        other.focus == focus;
  }

  @override
  int get hashCode => Object.hash(phase, anchor, focus);
}

/// Central, model-layer owner for document selection.
///
/// This controller deliberately does not know about Flutter text fields, page
/// widgets, or overlays. Widgets should translate user interaction into
/// [TextSystemDocumentPosition] values and report those values here. Rendering
/// layers can then derive caret/object/range visuals from [currentSelection].
class TextSystemDocumentSelectionController extends ChangeNotifier {
  TextSystemDocumentSelectionController({
    TextSystemDocumentSelection? initialSelection,
    TextSystemEditorInteractionMode interactionMode = TextSystemEditorInteractionMode.idle,
  })  : _currentSelection = initialSelection,
        _interactionMode = interactionMode;

  TextSystemDocumentSelection? _currentSelection;
  TextSystemEditorInteractionMode _interactionMode;
  TextSystemDocumentSelectionDragState _dragState = const TextSystemDocumentSelectionDragState.inactive();
  bool _keyboardExtensionActive = false;

  TextSystemDocumentSelection? get currentSelection => _currentSelection;
  TextSystemDocumentRange? get currentRange => _currentSelection?.range;
  TextSystemDocumentPosition? get anchor => _currentSelection?.anchor;
  TextSystemDocumentPosition? get focus => _currentSelection?.focus;
  TextSystemDocumentPosition? get extent => _currentSelection?.focus;
  TextSystemDocumentPosition? get base => _currentSelection?.anchor;
  TextSystemEditorInteractionMode get interactionMode => _interactionMode;
  TextSystemDocumentSelectionDragState get dragState => _dragState;
  bool get keyboardExtensionActive => _keyboardExtensionActive;
  bool get hasSelection => _currentSelection != null;
  bool get hasRangeSelection => _currentSelection?.isRange ?? false;
  bool get hasObjectSelection => _currentSelection?.isObject ?? false;
  bool get hasInlineAtomSelection => _currentSelection?.isInlineAtom ?? false;
  bool get hasTableCellSelection => _currentSelection?.isTableCell ?? false;

  TextSystemDocumentSelectionDirection get direction {
    return _currentSelection?.direction ?? TextSystemDocumentSelectionDirection.collapsed;
  }

  /// Moves the caret to [position] and clears any range/object/cell selection.
  void collapseTo(
    TextSystemDocumentPosition position, {
    TextSystemEditorInteractionMode mode = TextSystemEditorInteractionMode.editingText,
  }) {
    _setState(
      selection: TextSystemDocumentSelection.collapsed(position),
      mode: mode,
      dragState: const TextSystemDocumentSelectionDragState.inactive(),
      keyboardExtensionActive: false,
    );
  }

  /// Extends the current anchor to [position]. If there is no existing anchor,
  /// this collapses to [position].
  void extendTo(
    TextSystemDocumentPosition position, {
    bool keyboard = false,
  }) {
    final current = _currentSelection;
    if (current == null) {
      collapseTo(position);
      return;
    }
    _setState(
      selection: TextSystemDocumentSelection.range(
        anchor: current.anchor,
        focus: position,
      ),
      mode: TextSystemEditorInteractionMode.selectingText,
      keyboardExtensionActive: keyboard,
    );
  }

  /// Selects a document object block such as a figure, table, equation, page
  /// break, or section break.
  void selectObject(
    String blockId, {
    int blockIndex = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _setState(
      selection: TextSystemDocumentSelection.object(
        blockId: blockId,
        blockIndex: blockIndex,
        metadata: metadata,
      ),
      mode: TextSystemEditorInteractionMode.selectingObject,
      dragState: const TextSystemDocumentSelectionDragState.inactive(),
      keyboardExtensionActive: false,
    );
  }

  /// Selects an explicit anchor/focus range.
  void selectRange(
    TextSystemDocumentPosition anchor,
    TextSystemDocumentPosition focus, {
    TextSystemEditorInteractionMode mode = TextSystemEditorInteractionMode.selectingText,
  }) {
    _setState(
      selection: TextSystemDocumentSelection.range(anchor: anchor, focus: focus),
      mode: mode,
      dragState: const TextSystemDocumentSelectionDragState.inactive(),
      keyboardExtensionActive: false,
    );
  }

  /// Selects a semantic inline atom such as inline math, a cross-reference,
  /// citation, or future source link.
  void selectInlineAtom({
    required String blockId,
    required int blockIndex,
    required int atomStartOffset,
    required int atomEndOffset,
    String? atomId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _setState(
      selection: TextSystemDocumentSelection.inlineAtom(
        blockId: blockId,
        blockIndex: blockIndex,
        atomStartOffset: atomStartOffset,
        atomEndOffset: atomEndOffset,
        atomId: atomId,
        metadata: metadata,
      ),
      mode: TextSystemEditorInteractionMode.editingInlineAtom,
      dragState: const TextSystemDocumentSelectionDragState.inactive(),
      keyboardExtensionActive: false,
    );
  }

  /// Selects a table cell or rectangular table-cell range.
  void selectTableCell({
    required String blockId,
    required int blockIndex,
    required int row,
    required int column,
    int? endRow,
    int? endColumn,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _setState(
      selection: TextSystemDocumentSelection.tableCell(
        blockId: blockId,
        blockIndex: blockIndex,
        row: row,
        column: column,
        endRow: endRow,
        endColumn: endColumn,
        metadata: metadata,
      ),
      mode: TextSystemEditorInteractionMode.editingTableCell,
      dragState: const TextSystemDocumentSelectionDragState.inactive(),
      keyboardExtensionActive: false,
    );
  }

  /// Enters object-editing mode without changing the selected object.
  void editSelectedObject() {
    final selection = _currentSelection;
    if (selection == null || !selection.isObject) return;
    _setState(selection: selection, mode: TextSystemEditorInteractionMode.editingObject);
  }

  /// Begins a mouse/stylus drag selection.
  void beginDragSelection(TextSystemDocumentPosition anchor) {
    _setState(
      selection: TextSystemDocumentSelection.collapsed(anchor),
      mode: TextSystemEditorInteractionMode.selectingText,
      dragState: TextSystemDocumentSelectionDragState(
        phase: TextSystemDocumentSelectionDragPhase.pending,
        anchor: anchor,
        focus: anchor,
      ),
      keyboardExtensionActive: false,
    );
  }

  /// Updates a drag selection's focus position.
  void updateDragSelection(TextSystemDocumentPosition focus) {
    final dragAnchor = _dragState.anchor ?? _currentSelection?.anchor;
    if (dragAnchor == null) {
      beginDragSelection(focus);
      return;
    }
    _setState(
      selection: TextSystemDocumentSelection.range(anchor: dragAnchor, focus: focus),
      mode: TextSystemEditorInteractionMode.selectingText,
      dragState: TextSystemDocumentSelectionDragState(
        phase: TextSystemDocumentSelectionDragPhase.dragging,
        anchor: dragAnchor,
        focus: focus,
      ),
      keyboardExtensionActive: false,
    );
  }

  /// Commits the current drag selection.
  void endDragSelection() {
    if (!_dragState.isActive) return;
    _setState(
      selection: _currentSelection,
      mode: _currentSelection?.isCollapsed ?? true
          ? TextSystemEditorInteractionMode.editingText
          : TextSystemEditorInteractionMode.selectingText,
      dragState: _dragState.copyWith(phase: TextSystemDocumentSelectionDragPhase.committed),
      keyboardExtensionActive: false,
    );
  }

  /// Cancels the current drag and clears the drag lifecycle state. The current
  /// selection is kept by default because pointer cancellation should not
  /// silently erase a committed caret/selection.
  void cancelDragSelection({bool clearSelection = false}) {
    _setState(
      selection: clearSelection ? null : _currentSelection,
      mode: clearSelection ? TextSystemEditorInteractionMode.idle : _interactionMode,
      dragState: const TextSystemDocumentSelectionDragState(
        phase: TextSystemDocumentSelectionDragPhase.canceled,
      ),
      keyboardExtensionActive: false,
    );
  }

  void beginKeyboardExtension() {
    if (_currentSelection == null) return;
    _setState(
      selection: _currentSelection,
      mode: TextSystemEditorInteractionMode.selectingText,
      keyboardExtensionActive: true,
    );
  }

  void endKeyboardExtension() {
    if (!_keyboardExtensionActive) return;
    _setState(
      selection: _currentSelection,
      mode: _currentSelection?.isCollapsed ?? true
          ? TextSystemEditorInteractionMode.editingText
          : TextSystemEditorInteractionMode.selectingText,
      keyboardExtensionActive: false,
    );
  }

  void setInteractionMode(TextSystemEditorInteractionMode mode) {
    _setState(selection: _currentSelection, mode: mode);
  }

  /// Clears all document selection and interaction context.
  void clearSelection({
    TextSystemEditorInteractionMode mode = TextSystemEditorInteractionMode.idle,
  }) {
    _setState(
      selection: null,
      mode: mode,
      dragState: const TextSystemDocumentSelectionDragState.inactive(),
      keyboardExtensionActive: false,
    );
  }

  Map<String, Object?> toDiagnostics() {
    return <String, Object?>{
      'mode': _interactionMode.name,
      'keyboardExtensionActive': _keyboardExtensionActive,
      'direction': direction.name,
      'drag': _dragState.toJson(),
      if (_currentSelection != null) 'selection': _currentSelection!.toJson(),
      if (_currentSelection != null) 'label': _currentSelection!.diagnosticLabel,
    };
  }

  void _setState({
    required TextSystemDocumentSelection? selection,
    TextSystemEditorInteractionMode? mode,
    TextSystemDocumentSelectionDragState? dragState,
    bool? keyboardExtensionActive,
  }) {
    final nextMode = mode ?? _interactionMode;
    final nextDragState = dragState ?? _dragState;
    final nextKeyboardExtensionActive = keyboardExtensionActive ?? _keyboardExtensionActive;
    final unchanged =
        selection == _currentSelection &&
        nextMode == _interactionMode &&
        nextDragState == _dragState &&
        nextKeyboardExtensionActive == _keyboardExtensionActive;
    if (unchanged) return;

    _currentSelection = selection;
    _interactionMode = nextMode;
    _dragState = nextDragState;
    _keyboardExtensionActive = nextKeyboardExtensionActive;
    notifyListeners();
  }
}
