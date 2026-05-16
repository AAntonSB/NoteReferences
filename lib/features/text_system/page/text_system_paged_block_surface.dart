import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_range.dart';
import '../core/text_transaction.dart';
import '../references/actions/text_system_reference_actions.dart';
import '../references/citations/text_system_citation.dart';
import '../styles/text_system_document_style.dart';
import '../todos/text_system_embedded_todo.dart';
import 'text_system_document_selection_geometry.dart';
import 'text_system_layout_style_resolver.dart';
import 'text_system_page_furniture.dart';
import 'text_system_page_setup.dart';
import 'text_system_paged_block_layout.dart';

@immutable
class TextSystemPagedCaretAnchor {
  const TextSystemPagedCaretAnchor({
    required this.blockId,
    required this.textOffset,
  });

  final String blockId;
  final int textOffset;

  bool matchesFragment(TextSystemPagedBlockFragment fragment) {
    return blockId == fragment.blockId && fragment.containsTextOffset(textOffset);
  }

  @override
  bool operator ==(Object other) {
    return other is TextSystemPagedCaretAnchor &&
        other.blockId == blockId &&
        other.textOffset == textOffset;
  }

  @override
  int get hashCode => Object.hash(blockId, textOffset);
}

@immutable
class TextSystemPagedSelectionAnchor {
  const TextSystemPagedSelectionAnchor({
    required this.blockId,
    required this.baseOffset,
    required this.extentOffset,
  });

  factory TextSystemPagedSelectionAnchor.collapsed({
    required String blockId,
    required int textOffset,
  }) {
    return TextSystemPagedSelectionAnchor(
      blockId: blockId,
      baseOffset: textOffset,
      extentOffset: textOffset,
    );
  }

  final String blockId;
  final int baseOffset;
  final int extentOffset;

  bool get isCollapsed => baseOffset == extentOffset;
  int get caretOffset => extentOffset;

  TextSystemPagedCaretAnchor get caretAnchor {
    return TextSystemPagedCaretAnchor(
      blockId: blockId,
      textOffset: extentOffset,
    );
  }

  TextSystemPagedSelectionAnchor clampToBlock(TextSystemBlock block) {
    return TextSystemPagedSelectionAnchor(
      blockId: block.id,
      baseOffset: baseOffset.clamp(0, block.text.length).toInt(),
      extentOffset: extentOffset.clamp(0, block.text.length).toInt(),
    );
  }

  bool shouldFocusFragment(TextSystemPagedBlockFragment fragment) {
    return blockId == fragment.blockId && fragment.containsTextOffset(extentOffset);
  }

  @override
  bool operator ==(Object other) {
    return other is TextSystemPagedSelectionAnchor &&
        other.blockId == blockId &&
        other.baseOffset == baseOffset &&
        other.extentOffset == extentOffset;
  }

  @override
  int get hashCode => Object.hash(blockId, baseOffset, extentOffset);
}


@immutable
class TextSystemPagedDocumentSelection {
  const TextSystemPagedDocumentSelection({
    required this.base,
    required this.extent,
  });

  factory TextSystemPagedDocumentSelection.fromAnchor(
    TextSystemPagedSelectionAnchor anchor,
  ) {
    return TextSystemPagedDocumentSelection(
      base: TextSystemPagedCaretAnchor(
        blockId: anchor.blockId,
        textOffset: anchor.baseOffset,
      ),
      extent: TextSystemPagedCaretAnchor(
        blockId: anchor.blockId,
        textOffset: anchor.extentOffset,
      ),
    );
  }

  final TextSystemPagedCaretAnchor base;
  final TextSystemPagedCaretAnchor extent;

  bool get isCollapsed => base == extent;
  bool get isSingleBlock => base.blockId == extent.blockId;

  String? get singleBlockId => isSingleBlock ? base.blockId : null;

  TextSystemDocumentRange? toDocumentRange(TextSystemDocument document) {
    final baseIndex = document.blocks.indexWhere((block) => block.id == base.blockId);
    final extentIndex = document.blocks.indexWhere((block) => block.id == extent.blockId);
    if (baseIndex < 0 || extentIndex < 0) return null;

    final baseBlock = document.blocks[baseIndex];
    final extentBlock = document.blocks[extentIndex];

    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition(
        blockId: baseBlock.id,
        blockIndex: baseIndex,
        offset: base.textOffset.clamp(0, baseBlock.text.length).toInt(),
      ),
      end: TextSystemDocumentPosition(
        blockId: extentBlock.id,
        blockIndex: extentIndex,
        offset: extent.textOffset.clamp(0, extentBlock.text.length).toInt(),
      ),
    ).normalized();
  }

  TextSystemRange? singleBlockRange(TextSystemBlock block) {
    if (!isSingleBlock || block.id != base.blockId) return null;
    final start = math.min(base.textOffset, extent.textOffset)
        .clamp(0, block.text.length)
        .toInt();
    final end = math.max(base.textOffset, extent.textOffset)
        .clamp(start, block.text.length)
        .toInt();
    final range = TextSystemRange(start, end);
    return range.isCollapsed ? null : range;
  }

  String labelFor(TextSystemDocument document) {
    if (isCollapsed) return 'Collapsed selection';
    if (!isSingleBlock) {
      final range = toDocumentRange(document);
      if (range == null) return 'Cross-block selection';
      final start = range.start.blockIndex;
      final end = range.end.blockIndex;
      var characters = 0;
      var blocks = 0;
      for (var index = start; index <= end && index < document.blocks.length; index++) {
        final block = document.blocks[index];
        final startOffset = index == start ? range.start.offset.clamp(0, block.text.length).toInt() : 0;
        final endOffset = index == end ? range.end.offset.clamp(startOffset, block.text.length).toInt() : block.text.length;
        if (endOffset > startOffset) {
          characters += endOffset - startOffset;
          blocks += 1;
        }
      }
      return '$characters selected character${characters == 1 ? '' : 's'} across $blocks block${blocks == 1 ? '' : 's'}';
    }
    final block = document.blockById(base.blockId);
    if (block == null) return 'Unknown selection';
    final range = singleBlockRange(block);
    if (range == null) return 'Collapsed selection';
    return '${range.length} selected character${range.length == 1 ? '' : 's'}';
  }
}


enum _PagedBlockToolbarStyle {
  paragraph,
  heading1,
  heading2,
  heading3,
  quote,
  code,
  bulletList,
  numberedList,
  todo;

  String get styleId {
    return switch (this) {
      _PagedBlockToolbarStyle.paragraph => TextSystemDocumentStyleSheet.paragraph,
      _PagedBlockToolbarStyle.heading1 => TextSystemDocumentStyleSheet.heading1,
      _PagedBlockToolbarStyle.heading2 => TextSystemDocumentStyleSheet.heading2,
      _PagedBlockToolbarStyle.heading3 => TextSystemDocumentStyleSheet.heading3,
      _PagedBlockToolbarStyle.quote => TextSystemDocumentStyleSheet.quote,
      _PagedBlockToolbarStyle.code => TextSystemDocumentStyleSheet.code,
      _PagedBlockToolbarStyle.bulletList => TextSystemDocumentStyleSheet.listParagraph,
      _PagedBlockToolbarStyle.numberedList => TextSystemDocumentStyleSheet.numberedList,
      _PagedBlockToolbarStyle.todo => TextSystemDocumentStyleSheet.todo,
    };
  }

  String label(TextSystemDocumentStyleSheet styleSheet) {
    return styleSheet.styleForId(styleId).name;
  }

  static List<_PagedBlockToolbarStyle> optionsFor(TextSystemDocumentStyleSheet styleSheet) {
    const preferredOrder = <_PagedBlockToolbarStyle>[
      _PagedBlockToolbarStyle.paragraph,
      _PagedBlockToolbarStyle.heading1,
      _PagedBlockToolbarStyle.heading2,
      _PagedBlockToolbarStyle.heading3,
      _PagedBlockToolbarStyle.quote,
      _PagedBlockToolbarStyle.code,
      _PagedBlockToolbarStyle.bulletList,
      _PagedBlockToolbarStyle.numberedList,
      _PagedBlockToolbarStyle.todo,
    ];

    return <_PagedBlockToolbarStyle>[
      for (final option in preferredOrder)
        if (styleSheet.styles.containsKey(option.styleId)) option,
    ];
  }

  static _PagedBlockToolbarStyle fromBlock(
    TextSystemBlock block,
    TextSystemDocumentStyleSheet styleSheet,
  ) {
    final explicitStyleId = block.metadata['styleId'];
    if (explicitStyleId is String) {
      for (final option in _PagedBlockToolbarStyle.values) {
        if (option.styleId == explicitStyleId && styleSheet.styles.containsKey(explicitStyleId)) {
          return option;
        }
      }
    }

    return switch (block.type) {
      TextSystemBlockType.heading => switch (block.level ?? 1) {
          1 => _PagedBlockToolbarStyle.heading1,
          2 => _PagedBlockToolbarStyle.heading2,
          _ => _PagedBlockToolbarStyle.heading3,
        },
      TextSystemBlockType.quote => _PagedBlockToolbarStyle.quote,
      TextSystemBlockType.code => _PagedBlockToolbarStyle.code,
      TextSystemBlockType.listItem => block.metadata['ordered'] == true
          ? _PagedBlockToolbarStyle.numberedList
          : _PagedBlockToolbarStyle.bulletList,
      TextSystemBlockType.todo => _PagedBlockToolbarStyle.todo,
      _ => _PagedBlockToolbarStyle.paragraph,
    };
  }

  Map<String, Object?> metadataFor(TextSystemBlock block) {
    return switch (this) {
      _PagedBlockToolbarStyle.bulletList => <String, Object?>{
          ...block.metadata,
          'styleId': styleId,
          'ordered': false,
          'listKind': 'bullet',
        },
      _PagedBlockToolbarStyle.numberedList => <String, Object?>{
          ...block.metadata,
          'styleId': styleId,
          'ordered': true,
          'listKind': 'numbered',
        },
      _PagedBlockToolbarStyle.todo => <String, Object?>{
          ...block.metadata,
          'styleId': styleId,
          'listKind': 'todo',
        },
      _ => <String, Object?>{'styleId': styleId},
    };
  }
}


enum _EditorInteractionMode {
  idle,
  editingText,
  selectingText,
  selectingBlocks,
  selectingObject,
  editingObject,
  editingTableCell,
  panningWorkspace,
}

@immutable
class _SelectedDocumentObject {
  const _SelectedDocumentObject({
    required this.blockId,
    required this.kind,
  });

  final String blockId;
  final String kind;

  String get label {
    return switch (kind) {
      'figure' => 'Figure selected',
      'table' => 'Table selected',
      'equation' => 'Equation selected',
      _ => 'Object selected',
    };
  }
}

@immutable
class _ActiveTableEditingContext {
  const _ActiveTableEditingContext({
    required this.blockId,
    required this.cellLabel,
    required this.headerRows,
    required this.canDeleteRow,
    required this.canDeleteColumn,
    required this.onInsertRowAbove,
    required this.onInsertRowBelow,
    required this.onInsertColumnLeft,
    required this.onInsertColumnRight,
    required this.onDeleteRow,
    required this.onDeleteColumn,
    required this.onCycleHeaderRows,
    required this.onPaste,
    required this.onProperties,
    required this.onDone,
    required this.onDeleteTable,
  });

  final String blockId;
  final String cellLabel;
  final int headerRows;
  final bool canDeleteRow;
  final bool canDeleteColumn;
  final VoidCallback onInsertRowAbove;
  final VoidCallback onInsertRowBelow;
  final VoidCallback onInsertColumnLeft;
  final VoidCallback onInsertColumnRight;
  final VoidCallback? onDeleteRow;
  final VoidCallback? onDeleteColumn;
  final VoidCallback onCycleHeaderRows;
  final VoidCallback onPaste;
  final VoidCallback onProperties;
  final VoidCallback onDone;
  final VoidCallback onDeleteTable;
}

@immutable
class _InlineAtom {
  const _InlineAtom({
    required this.id,
    required this.type,
    required this.localRange,
    required this.globalRange,
    required this.sourceText,
    required this.displayText,
    this.latex,
    this.referenceMark,
    this.inlineReference,
  });

  final String id;
  final _InlineAtomType type;
  final TextSystemRange localRange;
  final TextSystemRange globalRange;
  final String sourceText;
  final String displayText;
  final String? latex;
  final TextMark? referenceMark;
  final TextSystemInlineReferenceMark? inlineReference;
}

enum _InlineAtomType {
  math,
  crossReference,
}

@immutable
class _PagedFragmentNavigation {
  const _PagedFragmentNavigation({
    this.previousAnchor,
    this.nextAnchor,
  });

  final TextSystemPagedCaretAnchor? previousAnchor;
  final TextSystemPagedCaretAnchor? nextAnchor;
}

/// Narrow command bridge used by the Premium Writer master header.
///
/// The real-page surface still owns caret, selection, and block-local editor
/// state. The parent shell can ask for an editor command through this
/// controller, but the implementation stays inside the paged surface. The
/// controller intentionally does not notify listeners; that avoids parent
/// rebuild loops while the user moves the caret or selection inside pages.
class TextSystemPagedBlockCommandController extends ChangeNotifier {
  _TextSystemPagedBlockSurfaceState? _state;
  Timer? _stateRefreshTimer;
  int _stateRevision = 0;

  /// Monotonic counter used by parent widgets that want to rebuild command
  /// affordances when the real-page selection/caret state changes.
  int get stateRevision => _stateRevision;

  bool get isAttached => _state?.mounted == true;

  bool get canRunEditorCommand {
    final state = _state;
    return state != null && state.mounted && state.widget.editable;
  }

  bool get canCreateEmbeddedTodo {
    final state = _state;
    return canRunEditorCommand && state!.widget.embeddedTodoRepository != null;
  }

  bool get canCreateReference {
    final state = _state;
    return canRunEditorCommand && state!.widget.referenceActionRepository != null;
  }

  bool get canUndo => canRunEditorCommand && (_state?.widget.textController.canUndo ?? false);
  bool get canRedo => canRunEditorCommand && (_state?.widget.textController.canRedo ?? false);
  bool get canCopySelection => canRunEditorCommand && (_state?._canCopySelection ?? false);
  bool get canCutSelection => canRunEditorCommand && (_state?._canCutSelection ?? false);
  bool get canPastePlainText => canRunEditorCommand && (_state?._canPastePlainText ?? false);
  bool get canToggleBold => canRunEditorCommand && (_state?._canToggleBold ?? false);
  bool get canToggleItalic => canRunEditorCommand && (_state?._canToggleItalic ?? false);
  bool get canToggleUnderline => canRunEditorCommand && (_state?._canToggleUnderline ?? false);
  bool get canToggleCode => canRunEditorCommand && (_state?._canToggleCode ?? false);
  bool get canToggleHighlight => canRunEditorCommand && (_state?._canToggleHighlight ?? false);

  bool get boldActive => _state?._activeSelectionIsBold ?? false;
  bool get italicActive => _state?._activeSelectionIsItalic ?? false;
  bool get underlineActive => _state?._activeSelectionIsUnderline ?? false;
  bool get codeActive => _state?._activeSelectionIsCode ?? false;
  bool get highlightActive => _state?._activeSelectionIsHighlighted ?? false;

  void _attach(_TextSystemPagedBlockSurfaceState state) {
    _state = state;
    scheduleStateRefresh();
  }

  void _detach(_TextSystemPagedBlockSurfaceState state) {
    if (identical(_state, state)) {
      _state = null;
      scheduleStateRefresh();
    }
  }

  /// Coalesces rapid selection/caret changes into one parent header refresh.
  ///
  /// The real-page surface updates selection frequently while the user drags
  /// inside native text fields. Notifying the parent on every micro-change can
  /// destabilize the page layout. A short debounce keeps the master header aware
  /// of selected text without rebuilding the whole writer during layout.
  void scheduleStateRefresh() {
    if (_stateRefreshTimer?.isActive ?? false) return;
    _stateRefreshTimer = Timer(const Duration(milliseconds: 80), () {
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

  void undo() {
    _state?._performUndo();
  }

  void redo() {
    _state?._performRedo();
  }

  Future<void> copySelection() async {
    await _state?._copyActiveSelectionToClipboard();
  }

  Future<void> cutSelection() async {
    await _state?._cutActiveSelectionToClipboard();
  }

  Future<void> pastePlainText() async {
    await _state?._pastePlainTextAtActiveSelection();
  }

  void toggleBold() {
    _state?._toggleBoldForActiveSelection();
  }

  void toggleItalic() {
    _state?._toggleItalicForActiveSelection();
  }

  void toggleUnderline() {
    _state?._toggleUnderlineForActiveSelection();
  }

  void toggleInlineCode() {
    _state?._toggleCodeForActiveSelection();
  }

  void toggleHighlight() {
    _state?._toggleHighlightForActiveSelection();
  }

  void changeActiveBlockStyleById(String styleId) {
    final state = _state;
    if (state == null || !state.mounted || !state.widget.editable) return;
    for (final style in _PagedBlockToolbarStyle.values) {
      if (style.styleId == styleId) {
        state._changeActiveBlockStyle(style);
        return;
      }
    }
  }

  void insertPageBreak() {
    _state?._insertPageBreakAtActiveSelection();
  }

  void insertSectionBreak() {
    _state?._insertSectionBreakAtActiveSelection();
  }

  void insertFootnote() {
    _state?._insertFootnoteAtActiveSelection();
  }

  Future<void> insertEmbeddedTodo() async {
    await _state?._insertEmbeddedTodoAtActiveSelection();
  }

  Future<void> insertFigure() async {
    await _state?._insertFigureAtActiveSelection();
  }

  Future<void> insertTable() async {
    await _state?._insertTableAtActiveSelection();
  }

  Future<void> insertEquation() async {
    await _state?._insertEquationAtActiveSelection();
  }

  Future<void> insertInlineMath() async {
    await _state?._insertInlineMathAtActiveSelection();
  }

  Future<void> insertCrossReference() async {
    await _state?._insertCrossReferenceAtActiveSelection();
  }

  Future<void> runReferenceAction(TextSystemReferenceActionType actionType) async {
    await _state?._createReferenceForActiveSelection(actionType);
  }

  Future<void> addMarginComment() async {
    await _state?._addMarginAnnotationAtActivePosition(_MarginAnnotationType.comment);
  }

  Future<void> addMarginTodo() async {
    await _state?._addMarginAnnotationAtActivePosition(_MarginAnnotationType.todo);
  }

  bool get hasSelectedObject => _state?._selectedDocumentObject != null;
  bool get hasBlockSelection => _state?._hasBlockSelection ?? false;
  String get blockSelectionStatusLabel => _state?._blockSelectionStatusLabel ?? '';
  bool get hasActiveTableContext => _state?._activeTableContext != null;
  String get selectedObjectStatusLabel => _state?._selectedObjectStatusLabel ?? '';
  String get selectedObjectKind => _state?._selectedDocumentObject?.kind ?? '';
  String get tableCellLabel => _state?._activeTableContext?.cellLabel ?? '';
  int get tableHeaderRows => _state?._activeTableContext?.headerRows ?? 0;
  bool get canDeleteSelectedTableRow => _state?._activeTableContext?.canDeleteRow ?? false;
  bool get canDeleteSelectedTableColumn => _state?._activeTableContext?.canDeleteColumn ?? false;

  void duplicateSelectedObject() => _state?._duplicateSelectedObjectBlock();
  void moveSelectedObjectUp() => _state?._moveSelectedObjectBlock(-1);
  void moveSelectedObjectDown() => _state?._moveSelectedObjectBlock(1);
  void deleteSelectedObject() => _state?._deleteSelectedObjectBlock();
  void deleteSelectedBlocks() => _state?._deleteSelectedBlocks();
  Future<void> copySelectedBlocks() async => _state?._copySelectedBlocksToClipboard();

  void tableInsertRowAbove() => _state?._activeTableContext?.onInsertRowAbove();
  void tableInsertRowBelow() => _state?._activeTableContext?.onInsertRowBelow();
  void tableInsertColumnLeft() => _state?._activeTableContext?.onInsertColumnLeft();
  void tableInsertColumnRight() => _state?._activeTableContext?.onInsertColumnRight();
  void tableDeleteRow() => _state?._activeTableContext?.onDeleteRow?.call();
  void tableDeleteColumn() => _state?._activeTableContext?.onDeleteColumn?.call();
  void tableCycleHeaderRows() => _state?._activeTableContext?.onCycleHeaderRows();
  void tablePaste() => _state?._activeTableContext?.onPaste();
  void tableProperties() => _state?._activeTableContext?.onProperties();
  void tableDone() => _state?._activeTableContext?.onDone();
  void tableDelete() => _state?._activeTableContext?.onDeleteTable();
}


/// Current production real-page surface for the Premium Writer.
///
/// Phase 16A treats this implementation as the stable legacy/current editor
/// path. It is intentionally kept functional while the next owned document
/// editor is built beside it under `lib/features/text_system/editor/`.
///
/// Important ownership boundary: this widget still delegates body editing to
/// per-fragment `TextField`s. New cross-block selection, caret, hit-testing,
/// and command-pipeline work should be implemented in the owned editor path
/// instead of growing this page-level surface further.
class TextSystemPagedBlockSurface extends StatefulWidget {
  const TextSystemPagedBlockSurface({
    super.key,
    required this.textController,
    required this.document,
    required this.pageSetup,
    required this.pageMaxWidth,
    this.pageZoom = 1.0,
    this.onPageZoomChanged,
    this.pageFurniture = const TextSystemPageFurniture.defaults(),
    this.onPageFurnitureChanged,
    required this.focusMode,
    this.showMarginGuides = true,
    this.showMarginMarkers = false,
    this.showMarginAnnotations = true,
    this.showSurfaceToolbar = true,
    this.editable = true,
    this.scrollController,
    this.commandController,
    this.referenceActionRepository,
    this.embeddedTodoRepository,
    this.onOpenReferenceTarget,
  });

  final TextSystemController textController;
  final TextSystemDocument document;
  final TextSystemPageSetup pageSetup;
  final double pageMaxWidth;
  final double pageZoom;
  final ValueChanged<double>? onPageZoomChanged;
  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture>? onPageFurnitureChanged;
  final bool focusMode;
  final bool showMarginGuides;
  final bool showMarginMarkers;
  final bool showMarginAnnotations;
  final bool showSurfaceToolbar;
  final bool editable;
  final ScrollController? scrollController;
  final TextSystemPagedBlockCommandController? commandController;
  final TextSystemReferenceActionRepository? referenceActionRepository;
  final TextSystemEmbeddedTodoRepository? embeddedTodoRepository;
  final ValueChanged<TextSystemInlineReferenceMark>? onOpenReferenceTarget;

  static const double _a4PortraitReferenceWidthMm = 210;
  static const double _pageHeaderHeight = 42;
  static const double _pageHeaderGap = 8;
  static const double _pageGap = 76;

  @override
  State<TextSystemPagedBlockSurface> createState() => _TextSystemPagedBlockSurfaceState();
}

class _TextSystemPagedBlockSurfaceState extends State<TextSystemPagedBlockSurface> {
  TextSystemPagedCaretAnchor? _activeCaretAnchor;
  TextSystemPagedCaretAnchor? _restoreCaretAnchor;
  TextSystemPagedSelectionAnchor? _activeSelectionAnchor;
  TextSystemPagedSelectionAnchor? _restoreSelectionAnchor;
  TextSystemPagedDocumentSelection? _surfaceDocumentSelection;
  TextSystemPagedCaretAnchor? _surfaceSelectionDragBase;
  Set<String> _selectedBlockIds = <String>{};
  String? _blockSelectionAnchorId;
  bool _documentSelectionMode = false;
  String? _activeBlockId;
  _PagedEditableBlockFieldState? _activeTextField;
  _EditorInteractionMode _interactionMode = _EditorInteractionMode.idle;
  _SelectedDocumentObject? _selectedDocumentObject;
  _ActiveTableEditingContext? _activeTableContext;
  final FocusNode _surfaceFocusNode = FocusNode(debugLabel: 'TextSystem real page surface');
  bool _headerFooterEditMode = false;
  TextSystemHeaderFooterZoneKind? _headerFooterEditTarget;
  Map<String, TextSystemEmbeddedTodoSnapshot> _embeddedTodoSnapshots = const {};
  final Map<String, TextSystemEmbeddedTodoSnapshot> _pendingEmbeddedTodoSync = <String, TextSystemEmbeddedTodoSnapshot>{};
  Timer? _embeddedTodoSyncTimer;
  String? _activeMarginAnnotationId;
  _MarginAnnotationDraftSession? _marginAnnotationDraft;
  final ScrollController _horizontalScrollController = ScrollController();
  bool _workspacePanActive = false;
  Offset? _workspacePanLastGlobalPosition;
  bool _pendingHorizontalViewportCenter = true;
  List<TextSystemPagedBlockPage> _latestSelectionPages = const <TextSystemPagedBlockPage>[];
  double _latestSelectionPageStride = 0;

  @override
  void initState() {
    super.initState();
    widget.commandController?._attach(this);
    _embeddedTodoSnapshots = _embeddedTodoSnapshotsFor(widget.textController.document);
    widget.textController.addListener(_handleEmbeddedTodoDocumentChanged);
  }

  @override
  void didUpdateWidget(covariant TextSystemPagedBlockSurface oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.commandController != widget.commandController) {
      oldWidget.commandController?._detach(this);
      widget.commandController?._attach(this);
    }

    if (oldWidget.pageZoom != widget.pageZoom || oldWidget.pageMaxWidth != widget.pageMaxWidth) {
      _pendingHorizontalViewportCenter = true;
    }

    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_handleEmbeddedTodoDocumentChanged);
      widget.textController.addListener(_handleEmbeddedTodoDocumentChanged);
      _embeddedTodoSnapshots = _embeddedTodoSnapshotsFor(widget.textController.document);
      _pendingEmbeddedTodoSync.clear();
      _embeddedTodoSyncTimer?.cancel();
    } else if (!identical(oldWidget.document, widget.document)) {
      _embeddedTodoSnapshots = _embeddedTodoSnapshotsFor(widget.textController.document);
    }
  }

  @override
  void dispose() {
    widget.commandController?._detach(this);
    _embeddedTodoSyncTimer?.cancel();
    widget.textController.removeListener(_handleEmbeddedTodoDocumentChanged);
    _horizontalScrollController.dispose();
    _surfaceFocusNode.dispose();
    super.dispose();
  }

  TextSystemBlock? get _activeBlock {
    final blockId = _activeBlockId ?? _activeCaretAnchor?.blockId;
    if (blockId == null) return null;
    return widget.document.blockById(blockId);
  }

  Map<String, TextSystemEmbeddedTodoSnapshot> _embeddedTodoSnapshotsFor(
    TextSystemDocument document,
  ) {
    final snapshots = <String, TextSystemEmbeddedTodoSnapshot>{};
    for (final block in document.blocks) {
      if (!TextSystemEmbeddedTodoMetadata.isEmbeddedTodoBlock(block)) {
        continue;
      }
      final snapshot = TextSystemEmbeddedTodoSnapshot.fromBlock(block);
      if (snapshot.todoId.trim().isEmpty) {
        continue;
      }
      snapshots[block.id] = snapshot;
    }
    return snapshots;
  }

  void _handleEmbeddedTodoDocumentChanged() {
    final repository = widget.embeddedTodoRepository;
    final nextSnapshots = _embeddedTodoSnapshotsFor(widget.textController.document);

    if (repository != null) {
      for (final entry in nextSnapshots.entries) {
        final previous = _embeddedTodoSnapshots[entry.key];
        final next = entry.value;
        if (previous == null || !previous.sameTodoState(next)) {
          _pendingEmbeddedTodoSync[next.todoId] = next;
        }
      }
    }

    _embeddedTodoSnapshots = nextSnapshots;

    if (_pendingEmbeddedTodoSync.isNotEmpty) {
      _scheduleEmbeddedTodoSync();
    }
  }

  void _scheduleEmbeddedTodoSync() {
    if (widget.embeddedTodoRepository == null) return;

    _embeddedTodoSyncTimer?.cancel();
    _embeddedTodoSyncTimer = Timer(const Duration(milliseconds: 350), () {
      final repository = widget.embeddedTodoRepository;
      if (repository == null || _pendingEmbeddedTodoSync.isEmpty) return;

      final pending = List<TextSystemEmbeddedTodoSnapshot>.from(
        _pendingEmbeddedTodoSync.values,
      );
      _pendingEmbeddedTodoSync.clear();

      unawaited(() async {
        for (final snapshot in pending) {
          try {
            await repository.syncSnapshot(snapshot);
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Could not sync an embedded TODO with the TODO system.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }());
    });
  }

  void _runSelectionStateUpdate(VoidCallback update) {
    if (!mounted) return;

    void applyUpdate() {
      if (!mounted) return;
      setState(update);
      widget.commandController?.scheduleStateRefresh();
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    final isUnsafeBuildPhase = phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks;

    if (isUnsafeBuildPhase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        applyUpdate();
      });
      return;
    }

    applyUpdate();
  }

  void _setDocumentSelectionMode(bool enabled) {
    if (!mounted || _documentSelectionMode == enabled) return;

    _runSelectionStateUpdate(() {
      _documentSelectionMode = enabled;
      _selectedDocumentObject = null;
      _selectedBlockIds = <String>{};
      _blockSelectionAnchorId = null;
      _surfaceSelectionDragBase = null;
      if (enabled) {
        _activeTextField = null;
        _activeSelectionAnchor = null;
        _restoreSelectionAnchor = null;
        _restoreCaretAnchor = null;
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  int? _indexOfBlock(String blockId) {
    final blocks = widget.textController.document.blocks;
    final index = blocks.indexWhere((block) => block.id == blockId);
    return index < 0 ? null : index;
  }

  bool _isHistoryFocusableBlock(TextSystemBlock block) {
    if (_isStructuralBreakBlock(block)) return false;
    return switch (block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  bool _isSelectableObjectBlock(TextSystemBlock block) {
    return _isDocumentObjectBlock(block);
  }

  String _objectKindForBlock(TextSystemBlock block) {
    if (_isEquationBlock(block)) return 'equation';
    return _academicObjectKind(block);
  }

  String get _selectedObjectStatusLabel {
    final selected = _selectedDocumentObject;
    if (selected == null) return '';
    final block = widget.textController.document.blockById(selected.blockId);
    if (block == null) return '';
    final label = switch (selected.kind) {
      'figure' => _academicCaptionForBlock(block).isEmpty ? 'Figure' : _academicCaptionForBlock(block),
      'table' => _academicCaptionForBlock(block).isEmpty ? 'Table' : _academicCaptionForBlock(block),
      'equation' => _equationLatexForBlock(block).isEmpty ? 'Equation' : _equationLatexForBlock(block),
      _ => selected.kind,
    };
    final trimmed = label.replaceAll('\n', ' ').trim();
    final shortLabel = trimmed.length > 32 ? '${trimmed.substring(0, 32)}…' : trimmed;
    return '${selected.label}: $shortLabel';
  }


  bool get _hasBlockSelection => _selectedBlockIds.isNotEmpty;

  List<int> get _selectedBlockIndexes {
    final blocks = widget.textController.document.blocks;
    final indexes = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      if (_selectedBlockIds.contains(blocks[i].id)) indexes.add(i);
    }
    indexes.sort();
    return indexes;
  }

  String get _blockSelectionStatusLabel {
    final count = _selectedBlockIds.length;
    if (count == 0) return '';
    return '$count selected block${count == 1 ? '' : 's'}';
  }

  bool _isBlockRangeSelected(String blockId) => _selectedBlockIds.contains(blockId);

  bool get _blockSelectionModifierPressed =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _clearBlockSelection() {
    if (!_hasBlockSelection && _blockSelectionAnchorId == null) return;
    _runSelectionStateUpdate(() {
      _selectedBlockIds = <String>{};
      _blockSelectionAnchorId = null;
      if (_interactionMode == _EditorInteractionMode.selectingBlocks) {
        _interactionMode = _EditorInteractionMode.idle;
      }
    });
  }

  void _selectSingleBlock(String blockId) {
    final block = widget.textController.document.blockById(blockId);
    if (block == null || _isHistoryFocusableBlock(block)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _surfaceFocusNode.requestFocus();
    _runSelectionStateUpdate(() {
      _interactionMode = _EditorInteractionMode.selectingBlocks;
      _selectedBlockIds = <String>{blockId};
      _blockSelectionAnchorId = blockId;
      _selectedDocumentObject = null;
      _activeTableContext = null;
      _activeTextField = null;
      _surfaceDocumentSelection = null;
      _surfaceSelectionDragBase = null;
      _activeSelectionAnchor = null;
      _activeCaretAnchor = null;
      _activeBlockId = blockId;
      _restoreSelectionAnchor = null;
      _restoreCaretAnchor = null;
    });
  }

  void _selectBlockRangeTo(String blockId) {
    final blocks = widget.textController.document.blocks;
    final extentIndex = blocks.indexWhere((block) => block.id == blockId);
    if (extentIndex < 0 || _isHistoryFocusableBlock(blocks[extentIndex])) return;

    var anchorId = _blockSelectionAnchorId ??
        _selectedDocumentObject?.blockId ??
        _activeBlockId ??
        _activeCaretAnchor?.blockId ??
        blockId;
    var anchorIndex = blocks.indexWhere((block) => block.id == anchorId);
    if (anchorIndex < 0) {
      anchorId = blockId;
      anchorIndex = extentIndex;
    }

    final start = math.min(anchorIndex, extentIndex);
    final end = math.max(anchorIndex, extentIndex);
    final selectedIds = <String>{
      for (var i = start; i <= end; i++)
        if (!_isHistoryFocusableBlock(blocks[i])) blocks[i].id,
    };
    if (selectedIds.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();
    _surfaceFocusNode.requestFocus();
    _runSelectionStateUpdate(() {
      _interactionMode = _EditorInteractionMode.selectingBlocks;
      _selectedBlockIds = selectedIds;
      _blockSelectionAnchorId = anchorId;
      _selectedDocumentObject = null;
      _activeTableContext = null;
      _activeTextField = null;
      _surfaceDocumentSelection = null;
      _surfaceSelectionDragBase = null;
      _activeSelectionAnchor = null;
      _activeCaretAnchor = null;
      _activeBlockId = blockId;
      _restoreSelectionAnchor = null;
      _restoreCaretAnchor = null;
    });
  }

  void _handleBlockSelectionPointerDown(String blockId, PointerDownEvent event) {
    if (!widget.editable || _workspacePanActive) return;

    // Whole-block selection is intentionally limited to non-text document
    // objects/structural blocks. Paragraphs, headings, lists, todos, quotes,
    // and code blocks should behave like native text: click places the caret,
    // drag selects text, Shift+arrows extend text selection, and Ctrl/Cmd+A
    // selects the active text field. Text blocks are implementation details,
    // not a visible block-editor selection surface.
    final block = widget.textController.document.blockById(blockId);
    if (block == null || _isHistoryFocusableBlock(block)) return;

    final shift = HardwareKeyboard.instance.isShiftPressed;
    final controlOrMeta = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (!shift && !controlOrMeta) return;

    if (shift) {
      _selectBlockRangeTo(blockId);
    } else {
      _selectSingleBlock(blockId);
    }
  }

  String _plainTextForSelectedBlock(TextSystemBlock block) {
    if (_isEquationBlock(block)) {
      final latex = _equationLatexForBlock(block).trim();
      return latex.isEmpty ? '[Equation]' : r'\[' + latex + r'\]';
    }
    if (_isAcademicObjectBlock(block)) {
      final kind = _academicObjectKind(block);
      final caption = _academicCaptionForBlock(block).trim();
      if (kind == 'table') {
        final cells = _academicTableCellsForBlock(block);
        final rows = cells.map((row) => row.join('\t')).where((row) => row.trim().isNotEmpty).toList();
        return <String>[
          caption.isEmpty ? 'Table' : 'Table: $caption',
          ...rows,
        ].join('\n').trim();
      }
      return caption.isEmpty ? '${kind[0].toUpperCase()}${kind.substring(1)}' : '${kind[0].toUpperCase()}${kind.substring(1)}: $caption';
    }
    if (_isPageBreakBlock(block)) return '[Page break]';
    if (_isSectionBreakBlock(block)) return '[Section break]';
    return block.text;
  }

  String _plainTextForSelectedBlocks() {
    final blocks = widget.textController.document.blocks;
    final selected = <String>[];
    for (final index in _selectedBlockIndexes) {
      if (index < 0 || index >= blocks.length) continue;
      selected.add(_plainTextForSelectedBlock(blocks[index]));
    }
    return selected.join('\n');
  }

  Future<void> _copySelectedBlocksToClipboard() async {
    if (!_hasBlockSelection) return;
    await Clipboard.setData(ClipboardData(text: _plainTextForSelectedBlocks()));
  }

  Future<void> _cutSelectedBlocksToClipboard() async {
    if (!_hasBlockSelection || !widget.editable) return;
    await _copySelectedBlocksToClipboard();
    _deleteSelectedBlocks();
  }

  bool _deleteSelectedBlocks() {
    if (!_hasBlockSelection || !widget.editable) return false;
    final blocks = widget.textController.document.blocks;
    final indexes = _selectedBlockIndexes;
    if (indexes.isEmpty) {
      _clearBlockSelection();
      return false;
    }
    final selectedIds = <String>{
      for (final index in indexes)
        if (index >= 0 && index < blocks.length) blocks[index].id,
    };
    if (selectedIds.isEmpty) return false;

    final firstIndex = indexes.first;
    final nextBlocks = <TextSystemBlock>[
      for (final block in blocks)
        if (!selectedIds.contains(block.id)) block,
    ];
    final restoreIndex = firstIndex.clamp(0, math.max(0, nextBlocks.length - 1)).toInt();
    TextSystemPagedCaretAnchor? restore;
    if (nextBlocks.isNotEmpty) {
      final restoreBlock = nextBlocks[restoreIndex];
      if (_isHistoryFocusableBlock(restoreBlock)) {
        restore = TextSystemPagedCaretAnchor(
          blockId: restoreBlock.id,
          textOffset: restoreBlock.text.length.clamp(0, restoreBlock.text.length).toInt(),
        );
      } else {
        restore = _caretAfterBlockAt(nextBlocks, restoreIndex);
      }
    }

    _runSelectionStateUpdate(() {
      _selectedBlockIds = <String>{};
      _blockSelectionAnchorId = null;
      if (_interactionMode == _EditorInteractionMode.selectingBlocks) {
        _interactionMode = _EditorInteractionMode.idle;
      }
    });
    _replaceDocumentBlocks(
      nextBlocks,
      label: 'Delete selected blocks',
      restoreCaret: restore,
    );
    return true;
  }

  void _selectObjectBlock(String blockId, {bool preserveFocus = false}) {
    final block = widget.textController.document.blockById(blockId);
    if (block == null || !_isSelectableObjectBlock(block)) return;

    if (!preserveFocus && _blockSelectionModifierPressed) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _selectBlockRangeTo(blockId);
      } else {
        _selectSingleBlock(blockId);
      }
      return;
    }

    if (!preserveFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _surfaceFocusNode.requestFocus();
    _runSelectionStateUpdate(() {
      _interactionMode = _EditorInteractionMode.selectingObject;
      _selectedDocumentObject = _SelectedDocumentObject(
        blockId: block.id,
        kind: _objectKindForBlock(block),
      );
      _selectedBlockIds = <String>{};
      _blockSelectionAnchorId = null;
      _activeTextField = null;
      _surfaceDocumentSelection = null;
      _surfaceSelectionDragBase = null;
      _activeSelectionAnchor = null;
      _activeCaretAnchor = null;
      _activeBlockId = block.id;
      _restoreSelectionAnchor = null;
      _restoreCaretAnchor = null;
    });
  }

  void _clearObjectSelection({bool clearFocus = false}) {
    if (_selectedDocumentObject == null && _interactionMode != _EditorInteractionMode.selectingObject) return;
    _runSelectionStateUpdate(() {
      _selectedDocumentObject = null;
      if (_interactionMode == _EditorInteractionMode.selectingObject ||
          _interactionMode == _EditorInteractionMode.editingObject) {
        _interactionMode = _EditorInteractionMode.idle;
      }
    });
    if (clearFocus) _surfaceFocusNode.unfocus();
  }

  void _setActiveTableContext(_ActiveTableEditingContext? context) {
    if (!mounted) return;
    final current = _activeTableContext;
    final sameInactive = current == null && context == null;
    final sameActive = current != null &&
        context != null &&
        current.blockId == context.blockId &&
        current.cellLabel == context.cellLabel &&
        current.headerRows == context.headerRows &&
        current.canDeleteRow == context.canDeleteRow &&
        current.canDeleteColumn == context.canDeleteColumn;
    if (sameInactive || sameActive) return;

    _runSelectionStateUpdate(() {
      _activeTableContext = context;
      if (context == null) {
        if (_interactionMode == _EditorInteractionMode.editingTableCell) {
          _interactionMode = _selectedDocumentObject == null
              ? _EditorInteractionMode.idle
              : _EditorInteractionMode.selectingObject;
        }
      } else {
        _interactionMode = _EditorInteractionMode.editingTableCell;
      }
    });
  }

  void _commitEditorDocumentTransaction(
    TextSystemDocument document, {
    required String label,
    TextSystemPagedCaretAnchor? restoreCaret,
  }) {
    widget.textController.replaceDocument(
      document.copyWith(updatedAt: DateTime.now()),
      label: label,
      origin: TextTransactionOrigin.user,
    );
    if (restoreCaret != null) {
      _requestCaretRestore(restoreCaret);
    }
  }

  void _replaceDocumentBlocks(
    List<TextSystemBlock> blocks, {
    required String label,
    TextSystemPagedCaretAnchor? restoreCaret,
  }) {
    _commitEditorDocumentTransaction(
      widget.textController.document.copyWith(
        blocks: blocks.isEmpty
            ? <TextSystemBlock>[
                TextSystemBlock.paragraph(
                  id: 'paragraph_${DateTime.now().microsecondsSinceEpoch}',
                  text: '',
                ),
              ]
            : blocks,
      ),
      label: label,
      restoreCaret: restoreCaret,
    );
  }

  List<TextMark> _marksForTextSlice(
    TextSystemBlock block, {
    required int start,
    required int end,
  }) {
    final sliceRange = TextSystemRange(start, end);
    final marks = <TextMark>[];
    for (final mark in block.marks) {
      final intersection = mark.range.intersection(sliceRange);
      if (intersection == null) continue;
      marks.add(mark.copyWith(range: intersection.relativeTo(start)));
    }
    return marks;
  }

  TextSystemDocumentPosition? _insertObjectBlockTransaction(
    TextSystemDocumentPosition position,
    TextSystemBlock insertedBlock, {
    required String label,
    bool ensureParagraphAfter = true,
  }) {
    final document = widget.textController.document;
    final blocks = document.blocks;
    final blockIndex = blocks.indexWhere((block) => block.id == position.blockId);
    if (blockIndex < 0) return null;

    final block = blocks[blockIndex];
    if (_isStructuralBreakBlock(block)) return null;

    final safeOffset = position.offset.clamp(0, block.text.length).toInt();
    final nextBlocks = <TextSystemBlock>[];
    var insertedIndex = -1;

    for (var i = 0; i < blocks.length; i++) {
      if (i != blockIndex) {
        nextBlocks.add(blocks[i]);
        continue;
      }

      if (safeOffset <= 0) {
        nextBlocks.add(insertedBlock);
        insertedIndex = nextBlocks.length - 1;
        nextBlocks.add(block);
        continue;
      }

      if (safeOffset >= block.text.length) {
        nextBlocks.add(block);
        nextBlocks.add(insertedBlock);
        insertedIndex = nextBlocks.length - 1;
        continue;
      }

      final beforeBlock = block.copyWith(
        text: block.text.substring(0, safeOffset),
        marks: _marksForTextSlice(block, start: 0, end: safeOffset),
      ).normalizeMarks();
      final afterType = block.type == TextSystemBlockType.heading
          ? TextSystemBlockType.paragraph
          : block.type;
      final afterBlock = TextSystemBlock(
        id: 'paragraph_after_object_${DateTime.now().microsecondsSinceEpoch}',
        type: afterType,
        text: block.text.substring(safeOffset),
        marks: _marksForTextSlice(block, start: safeOffset, end: block.text.length),
        level: afterType == TextSystemBlockType.heading ? block.level : null,
        checked: afterType == TextSystemBlockType.todo ? block.checked : null,
        metadata: afterType == TextSystemBlockType.listItem || afterType == TextSystemBlockType.todo
            ? Map<String, Object?>.unmodifiable(block.metadata)
            : const <String, Object?>{},
      ).normalizeMarks();

      nextBlocks.add(beforeBlock);
      nextBlocks.add(insertedBlock);
      insertedIndex = nextBlocks.length - 1;
      nextBlocks.add(afterBlock);
    }

    if (insertedIndex < 0) return null;

    var exitIndex = insertedIndex + 1;
    if (ensureParagraphAfter &&
        (exitIndex >= nextBlocks.length || !_blockCanReceiveObjectExitCaret(nextBlocks[exitIndex]))) {
      final paragraph = TextSystemBlock.paragraph(
        id: 'paragraph_after_object_${DateTime.now().microsecondsSinceEpoch}',
        text: '',
      );
      nextBlocks.insert(exitIndex, paragraph);
    }

    final exitBlock = exitIndex < nextBlocks.length ? nextBlocks[exitIndex] : nextBlocks[insertedIndex];
    _commitEditorDocumentTransaction(
      document.copyWith(blocks: nextBlocks),
      label: label,
    );

    return TextSystemDocumentPosition(
      blockId: exitBlock.id,
      blockIndex: exitIndex.clamp(0, nextBlocks.length - 1).toInt(),
      offset: 0,
    );
  }

  TextSystemDocumentRange? _replaceSingleBlockRangeWithMarkedTextTransaction(
    TextSystemDocumentRange range,
    String insertedText, {
    required TextMark mark,
    required String label,
  }) {
    final normalized = range.normalized();
    if (normalized.start.blockId != normalized.end.blockId) return null;

    final document = widget.textController.document;
    final blockIndex = document.blocks.indexWhere((block) => block.id == normalized.start.blockId);
    if (blockIndex < 0) return null;

    final block = document.blocks[blockIndex];
    final start = normalized.start.offset.clamp(0, block.text.length).toInt();
    final end = normalized.end.offset.clamp(start, block.text.length).toInt();
    final delta = insertedText.length - (end - start);
    final nextText = block.text.replaceRange(start, end, insertedText);
    final nextMarks = <TextMark>[];

    for (final existing in block.marks) {
      if (existing.range.end <= start) {
        nextMarks.add(existing);
      } else if (existing.range.start >= end) {
        nextMarks.add(existing.copyWith(range: existing.range.shift(delta)));
      } else {
        // Drop marks that overlap the replaced text. The inserted semantic atom
        // gets its own mark below, and preserving partial overlaps here can
        // create malformed inline references.
      }
    }

    nextMarks.add(mark.copyWith(range: TextSystemRange(start, start + insertedText.length)));
    final nextBlock = block.copyWith(text: nextText, marks: nextMarks).normalizeMarks();
    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < document.blocks.length; i++)
        if (i == blockIndex) nextBlock else document.blocks[i],
    ];

    _commitEditorDocumentTransaction(
      document.copyWith(blocks: nextBlocks),
      label: label,
    );

    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition(
        blockId: nextBlock.id,
        blockIndex: blockIndex,
        offset: start,
      ),
      end: TextSystemDocumentPosition(
        blockId: nextBlock.id,
        blockIndex: blockIndex,
        offset: start + insertedText.length,
      ),
    );
  }

  String _uniqueDuplicatedLabel(String base, String exceptBlockId) {
    final trimmed = base.trim();
    if (trimmed.isEmpty) return '';
    var candidate = '$trimmed-copy';
    var suffix = 2;
    while (_documentHasAcademicLabel(widget.textController.document, candidate, exceptBlockId: exceptBlockId)) {
      candidate = '$trimmed-copy-$suffix';
      suffix += 1;
    }
    return candidate;
  }

  TextSystemBlock _duplicatedObjectBlock(TextSystemBlock block) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final nextMetadata = Map<String, Object?>.from(block.metadata);
    final label = nextMetadata['label'];
    if (label is String && label.trim().isNotEmpty) {
      nextMetadata['label'] = _uniqueDuplicatedLabel(label, block.id);
    }
    return block.copyWith(
      id: '${_objectKindForBlock(block)}-$now',
      metadata: Map<String, Object?>.unmodifiable(nextMetadata),
    );
  }

  TextSystemPagedCaretAnchor? _caretAfterBlockAt(List<TextSystemBlock> blocks, int index) {
    if (blocks.isEmpty) return null;
    final nextIndex = index + 1;
    if (nextIndex < blocks.length && _blockCanReceiveObjectExitCaret(blocks[nextIndex])) {
      return TextSystemPagedCaretAnchor(blockId: blocks[nextIndex].id, textOffset: 0);
    }
    final fallbackIndex = index.clamp(0, blocks.length - 1).toInt();
    final block = blocks[fallbackIndex];
    return TextSystemPagedCaretAnchor(blockId: block.id, textOffset: block.text.length);
  }

  bool _deleteSelectedObjectBlock() {
    if (!widget.editable) return false;
    final selected = _selectedDocumentObject;
    if (selected == null) return false;

    final blocks = widget.textController.document.blocks;
    final index = blocks.indexWhere((block) => block.id == selected.blockId);
    if (index < 0) {
      _clearObjectSelection();
      return false;
    }

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < blocks.length; i++)
        if (i != index) blocks[i],
    ];
    final restore = _caretAfterBlockAt(nextBlocks, math.min(index, nextBlocks.length - 1));
    _clearObjectSelection();
    _replaceDocumentBlocks(
      nextBlocks,
      label: 'Delete ${selected.kind}',
      restoreCaret: restore,
    );
    return true;
  }

  bool _duplicateSelectedObjectBlock() {
    if (!widget.editable) return false;
    final selected = _selectedDocumentObject;
    if (selected == null) return false;

    final blocks = widget.textController.document.blocks;
    final index = blocks.indexWhere((block) => block.id == selected.blockId);
    if (index < 0) return false;

    final duplicate = _duplicatedObjectBlock(blocks[index]);
    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < blocks.length; i++) ...[
        blocks[i],
        if (i == index) duplicate,
      ],
    ];
    _replaceDocumentBlocks(nextBlocks, label: 'Duplicate ${selected.kind}');
    _selectObjectBlock(duplicate.id, preserveFocus: true);
    return true;
  }

  bool _moveSelectedObjectBlock(int direction) {
    if (!widget.editable || direction == 0) return false;
    final selected = _selectedDocumentObject;
    if (selected == null) return false;

    final blocks = List<TextSystemBlock>.from(widget.textController.document.blocks);
    final index = blocks.indexWhere((block) => block.id == selected.blockId);
    if (index < 0) return false;
    final targetIndex = (index + direction).clamp(0, blocks.length - 1).toInt();
    if (targetIndex == index) return false;

    final block = blocks.removeAt(index);
    blocks.insert(targetIndex, block);
    _replaceDocumentBlocks(blocks, label: direction < 0 ? 'Move ${selected.kind} up' : 'Move ${selected.kind} down');
    _selectObjectBlock(selected.blockId, preserveFocus: true);
    return true;
  }

  bool _placeCaretBeforeObjectBlock(String blockId) {
    if (!widget.editable) return false;
    final block = widget.textController.document.blockById(blockId);
    if (block == null || !_isSelectableObjectBlock(block)) return false;
    final anchor = _ensureCaretBeforeDocumentObject(
      widget.textController,
      blockId,
      label: 'Create paragraph before ${_objectKindForBlock(block)}',
    );
    _requestSelectionRestore(TextSystemPagedSelectionAnchor.collapsed(
      blockId: anchor.blockId,
      textOffset: anchor.textOffset,
    ));
    return true;
  }

  bool _placeCaretAfterObjectBlock(String blockId) {
    if (!widget.editable) return false;
    final block = widget.textController.document.blockById(blockId);
    if (block == null || !_isSelectableObjectBlock(block)) return false;
    final anchor = _ensureCaretAfterDocumentObject(
      widget.textController,
      blockId,
      label: 'Create paragraph after ${_objectKindForBlock(block)}',
    );
    _requestSelectionRestore(TextSystemPagedSelectionAnchor.collapsed(
      blockId: anchor.blockId,
      textOffset: anchor.textOffset,
    ));
    return true;
  }

  bool _placeCaretBeforeSelectedObject() {
    final selected = _selectedDocumentObject;
    if (selected == null) return false;
    return _placeCaretBeforeObjectBlock(selected.blockId);
  }

  bool _placeCaretAfterSelectedObject() {
    final selected = _selectedDocumentObject;
    if (selected == null) return false;
    return _placeCaretAfterObjectBlock(selected.blockId);
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final controlOrMeta = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final altPressed = HardwareKeyboard.instance.isAltPressed;

    if (controlOrMeta && key == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _performRedo();
      } else {
        _performUndo();
      }
      _surfaceFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (controlOrMeta && key == LogicalKeyboardKey.keyY) {
      _performRedo();
      _surfaceFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (_hasBlockSelection) {
      if (key == LogicalKeyboardKey.escape) {
        _clearBlockSelection();
        return KeyEventResult.handled;
      }
      if (controlOrMeta && key == LogicalKeyboardKey.keyC) {
        unawaited(_copySelectedBlocksToClipboard());
        return KeyEventResult.handled;
      }
      if (controlOrMeta && key == LogicalKeyboardKey.keyX) {
        unawaited(_cutSelectedBlocksToClipboard());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
        return _deleteSelectedBlocks() ? KeyEventResult.handled : KeyEventResult.ignored;
      }
    }

    final selected = _selectedDocumentObject;
    if (selected == null) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.escape) {
      _clearObjectSelection(clearFocus: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final handled = HardwareKeyboard.instance.isShiftPressed
          ? _placeCaretBeforeSelectedObject()
          : _placeCaretAfterSelectedObject();
      return handled ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
      return _placeCaretBeforeSelectedObject() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
      return _placeCaretAfterSelectedObject() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      return _deleteSelectedObjectBlock() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (controlOrMeta && key == LogicalKeyboardKey.keyD) {
      return _duplicateSelectedObjectBlock() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (altPressed && key == LogicalKeyboardKey.arrowUp) {
      return _moveSelectedObjectBlock(-1) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (altPressed && key == LogicalKeyboardKey.arrowDown) {
      return _moveSelectedObjectBlock(1) ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  TextSystemPagedSelectionAnchor? _historyRestoreAnchor(
    TextSystemPagedSelectionAnchor? requested,
    int? previousBlockIndex,
  ) {
    final document = widget.textController.document;

    if (requested != null) {
      final block = document.blockById(requested.blockId);
      if (block != null && _isHistoryFocusableBlock(block)) {
        return requested.clampToBlock(block);
      }
    }

    if (document.blocks.isEmpty) return null;

    final startIndex = (previousBlockIndex ?? 0).clamp(0, document.blocks.length - 1).toInt();

    for (var distance = 0; distance < document.blocks.length; distance++) {
      final forwardIndex = startIndex + distance;
      if (forwardIndex < document.blocks.length) {
        final block = document.blocks[forwardIndex];
        if (_isHistoryFocusableBlock(block)) {
          return TextSystemPagedSelectionAnchor.collapsed(
            blockId: block.id,
            textOffset: block.text.length,
          );
        }
      }

      final backwardIndex = startIndex - distance - 1;
      if (backwardIndex >= 0) {
        final block = document.blocks[backwardIndex];
        if (_isHistoryFocusableBlock(block)) {
          return TextSystemPagedSelectionAnchor.collapsed(
            blockId: block.id,
            textOffset: block.text.length,
          );
        }
      }
    }

    return null;
  }

  void _setActiveCaretAnchor(TextSystemPagedCaretAnchor anchor) {
    _setActiveSelectionAnchor(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: anchor.blockId,
        textOffset: anchor.textOffset,
      ),
    );
  }

  void _setActiveSelectionAnchor(TextSystemPagedSelectionAnchor anchor) {
    if (_surfaceSelectionDragBase != null) return;

    if (_activeSelectionAnchor == anchor &&
        _activeBlockId == anchor.blockId &&
        _surfaceDocumentSelection == null) {
      // The active native TextField can update its internal selection without
      // requiring a visual state change in the page surface. The master header
      // still needs a command-state refresh so formatting buttons become aware
      // of mouse selections immediately.
      widget.commandController?.scheduleStateRefresh();
      return;
    }
    _runSelectionStateUpdate(() {
      _selectedDocumentObject = null;
      _selectedBlockIds = <String>{};
      _blockSelectionAnchorId = null;
      _interactionMode = _EditorInteractionMode.editingText;
      _surfaceDocumentSelection = null;
      _surfaceSelectionDragBase = null;
      _activeSelectionAnchor = anchor;
      _activeCaretAnchor = anchor.caretAnchor;
      _activeBlockId = anchor.blockId;
    });
  }

  void _setActiveTextField(_PagedEditableBlockFieldState? field) {
    if (!mounted) return;
    if (field != null && !field.mounted) return;
    if (field != null && _hasBlockSelection && _blockSelectionModifierPressed) return;
    if (identical(_activeTextField, field)) {
      if (field != null) {
        final anchor = field.currentSelectionAnchor;
        if (anchor != null && _activeSelectionAnchor != anchor) {
          _setActiveSelectionAnchor(anchor);
        } else {
          // Keep the parent command header in sync even when the active field
          // remains the same. This is the common path for mouse drag selection
          // inside an already-focused paragraph.
          widget.commandController?.scheduleStateRefresh();
        }
      }
      return;
    }

    _runSelectionStateUpdate(() {
      if (field != null) {
        _selectedDocumentObject = null;
        _selectedBlockIds = <String>{};
        _blockSelectionAnchorId = null;
        _interactionMode = _EditorInteractionMode.editingText;
      }
      _activeTextField = field;
      final anchor = field?.currentSelectionAnchor;
      if (anchor != null) {
        _surfaceDocumentSelection = null;
        _surfaceSelectionDragBase = null;
        _activeSelectionAnchor = anchor;
        _activeCaretAnchor = anchor.caretAnchor;
        _activeBlockId = anchor.blockId;
      }
    });
  }

  void _requestCaretRestore(TextSystemPagedCaretAnchor anchor) {
    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: anchor.blockId,
        textOffset: anchor.textOffset,
      ),
    );
  }

  void _requestSelectionRestore(TextSystemPagedSelectionAnchor anchor) {
    _runSelectionStateUpdate(() {
      _selectedDocumentObject = null;
      _selectedBlockIds = <String>{};
      _blockSelectionAnchorId = null;
      _interactionMode = _EditorInteractionMode.editingText;
      _activeSelectionAnchor = anchor;
      _activeCaretAnchor = anchor.caretAnchor;
      _activeBlockId = anchor.blockId;
      _restoreSelectionAnchor = anchor;
      _restoreCaretAnchor = anchor.caretAnchor;
    });
  }

  TextSystemDocumentPosition _ensureWritableParagraphAfterBlock(
    String blockId, {
    required String label,
  }) {
    final document = widget.textController.document;
    final blocks = document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == blockId);
    if (index < 0) {
      final fallback = _activeInsertPosition();
      if (fallback != null) return fallback;
      final firstBlock = blocks.isNotEmpty
          ? blocks.first
          : TextSystemBlock.paragraph(
              id: 'paragraph_${DateTime.now().microsecondsSinceEpoch}',
              text: '',
            );
      if (blocks.isEmpty) {
        widget.textController.replaceDocument(
          document.copyWith(blocks: [firstBlock], updatedAt: DateTime.now()),
          label: label,
        );
      }
      return TextSystemDocumentPosition(
        blockId: firstBlock.id,
        blockIndex: 0,
        offset: firstBlock.text.length,
      );
    }

    final nextIndex = index + 1;
    if (nextIndex < blocks.length && _blockCanReceiveObjectExitCaret(blocks[nextIndex])) {
      return TextSystemDocumentPosition(
        blockId: blocks[nextIndex].id,
        blockIndex: nextIndex,
        offset: 0,
      );
    }

    final paragraph = TextSystemBlock.paragraph(
      id: 'paragraph_after_object_${DateTime.now().microsecondsSinceEpoch}',
      text: '',
    );
    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < blocks.length; i++) ...[
        blocks[i],
        if (i == index) paragraph,
      ],
    ];
    widget.textController.replaceDocument(
      document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: label,
    );
    return TextSystemDocumentPosition(
      blockId: paragraph.id,
      blockIndex: index + 1,
      offset: 0,
    );
  }

  void _handleRestoreSelectionConsumed(TextSystemPagedSelectionAnchor anchor) {
    if (!mounted || _restoreSelectionAnchor != anchor) return;
    _runSelectionStateUpdate(() {
      _restoreSelectionAnchor = null;
      _restoreCaretAnchor = null;
    });
  }

  TextSystemDocumentRange? _documentRangeForDocumentSelection(TextSystemPagedDocumentSelection selection) {
    return selection.toDocumentRange(widget.textController.document);
  }

  TextSystemDocumentRange? _documentRangeForPagedSelection(TextSystemPagedSelectionAnchor selection) {
    final blockIndex = widget.textController.document.blocks.indexWhere(
      (block) => block.id == selection.blockId,
    );
    if (blockIndex < 0) return null;

    final block = widget.textController.document.blocks[blockIndex];
    final start = math.min(selection.baseOffset, selection.extentOffset)
        .clamp(0, block.text.length)
        .toInt();
    final end = math.max(selection.baseOffset, selection.extentOffset)
        .clamp(start, block.text.length)
        .toInt();

    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: start,
      ),
      end: TextSystemDocumentPosition(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: end,
      ),
    );
  }

  TextSystemDocumentRange? get _activeDocumentRange {
    final documentSelection = _surfaceDocumentSelection;
    if (documentSelection != null && !documentSelection.isCollapsed) {
      return _documentRangeForDocumentSelection(documentSelection);
    }

    final selection = _activeSelectionAnchor;
    if (selection == null || selection.isCollapsed) return null;
    return _documentRangeForPagedSelection(selection);
  }

  TextSystemDocumentRange? _collapsedDocumentRangeForBlock(TextSystemBlock block) {
    final blockIndex = widget.textController.document.blocks.indexWhere(
      (candidate) => candidate.id == block.id,
    );
    if (blockIndex < 0) return null;

    final selectionAnchor = (_activeSelectionAnchor ??
            TextSystemPagedSelectionAnchor.collapsed(
              blockId: block.id,
              textOffset: _activeCaretAnchor?.textOffset ?? block.text.length,
            ))
        .clampToBlock(block);

    return TextSystemDocumentRange.collapsed(
      TextSystemDocumentPosition(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: selectionAnchor.caretOffset.clamp(0, block.text.length).toInt(),
      ),
    );
  }

  TextSystemRange? get _activeSelectionRange {
    final block = _activeBlock;
    final selection = _activeSelectionAnchor;
    if (block == null || selection == null || selection.blockId != block.id) {
      return null;
    }

    final start = math.min(selection.baseOffset, selection.extentOffset)
        .clamp(0, block.text.length)
        .toInt();
    final end = math.max(selection.baseOffset, selection.extentOffset)
        .clamp(start, block.text.length)
        .toInt();
    final range = TextSystemRange(start, end);
    return range.isCollapsed ? null : range;
  }

  _PagedEditableBlockFieldState? get _usableActiveTextField {
    final field = _activeTextField;
    if (field == null || !field.mounted) return null;
    return field;
  }

  bool _canToggleInlineMark(TextMarkKind kind) {
    if (_surfaceDocumentSelection != null && !_surfaceDocumentSelection!.isCollapsed) {
      return widget.editable && _activeDocumentRange != null;
    }

    final field = _usableActiveTextField;
    if (field != null) {
      return field.canToggleMarkFromToolbar(kind);
    }

    final block = _activeBlock;
    final range = _activeSelectionRange;
    if (!widget.editable || block == null || range == null) return false;
    if (_isStructuralBreakBlock(block)) return false;

    return switch (block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  bool get _canToggleBold => _canToggleInlineMark(TextMarkKind.bold);
  bool get _canToggleItalic => _canToggleInlineMark(TextMarkKind.italic);
  bool get _canToggleUnderline => _canToggleInlineMark(TextMarkKind.underline);
  bool get _canToggleCode => _canToggleInlineMark(TextMarkKind.code);
  bool get _canToggleHighlight => _canToggleInlineMark(TextMarkKind.highlight);

  TextSystemPagedDocumentSelection? get _activeDocumentSelection {
    if (_surfaceDocumentSelection != null) return _surfaceDocumentSelection;
    final anchor = _activeSelectionAnchor;
    if (anchor == null) return null;
    return TextSystemPagedDocumentSelection.fromAnchor(anchor);
  }

  String get _selectionStatusLabel {
    if (_hasBlockSelection) return _blockSelectionStatusLabel;
    final objectLabel = _selectedObjectStatusLabel;
    if (objectLabel.isNotEmpty) return objectLabel;
    final selection = _activeDocumentSelection;
    if (selection == null) return 'No active selection';
    return selection.labelFor(widget.document);
  }

  bool get _canCopySelection {
    if (_hasBlockSelection) return true;
    if (_surfaceDocumentSelection != null && !_surfaceDocumentSelection!.isCollapsed) {
      return _activeDocumentRange != null;
    }

    final field = _usableActiveTextField;
    if (field != null) return field.hasNonCollapsedSelection;

    final range = _activeDocumentRange;
    return range != null && !range.isCollapsed;
  }

  bool get _canCutSelection {
    if (_hasBlockSelection) return widget.editable;
    if (_surfaceDocumentSelection != null && !_surfaceDocumentSelection!.isCollapsed) {
      return widget.editable && _activeDocumentRange != null;
    }

    final field = _usableActiveTextField;
    if (field != null) return widget.editable && field.hasNonCollapsedSelection;
    return widget.editable && _canCopySelection;
  }

  bool get _canPastePlainText {
    final field = _usableActiveTextField;
    if (field != null) return field.canPastePlainTextFromToolbar;

    final block = _activeBlock;
    if (!widget.editable || block == null || _isStructuralBreakBlock(block)) return false;
    return switch (block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  bool _activeSelectionHasMark(TextMarkKind kind) {
    final field = _usableActiveTextField;
    if (field != null) return field.selectionHasMarkFromToolbar(kind);

    final block = _activeBlock;
    final range = _activeSelectionRange;
    if (block == null || range == null) return false;
    return _rangeFullyCoveredByKind(block.marks, range, kind);
  }

  bool get _activeSelectionIsBold => _activeSelectionHasMark(TextMarkKind.bold);
  bool get _activeSelectionIsItalic => _activeSelectionHasMark(TextMarkKind.italic);
  bool get _activeSelectionIsUnderline => _activeSelectionHasMark(TextMarkKind.underline);
  bool get _activeSelectionIsCode => _activeSelectionHasMark(TextMarkKind.code);
  bool get _activeSelectionIsHighlighted => _activeSelectionHasMark(TextMarkKind.highlight);

  Future<void> _copyActiveSelectionToClipboard() async {
    if (_hasBlockSelection) {
      await _copySelectedBlocksToClipboard();
      return;
    }

    if (_surfaceDocumentSelection == null) {
      final field = _usableActiveTextField;
      if (field != null && field.copySelectionToClipboardFromToolbar()) {
        _setActiveTextField(field);
        return;
      }
    }

    final range = _activeDocumentRange;
    if (range == null || range.isCollapsed) return;

    final fragment = widget.textController.copyDocumentFragment(range);
    await Clipboard.setData(ClipboardData(text: fragment.plainText));
  }

  Future<void> _cutActiveSelectionToClipboard() async {
    if (_hasBlockSelection) {
      await _cutSelectedBlocksToClipboard();
      return;
    }

    if (_surfaceDocumentSelection == null) {
      final field = _usableActiveTextField;
      if (field != null && field.cutSelectionToClipboardFromToolbar()) {
        _setActiveTextField(field);
        return;
      }
    }

    final range = _activeDocumentRange;
    if (range == null || range.isCollapsed) return;

    final fragment = widget.textController.cutDocumentRange(range);
    await Clipboard.setData(ClipboardData(text: fragment.plainText));

    _surfaceDocumentSelection = null;
    _surfaceSelectionDragBase = null;
    final target = range.normalized().start;
    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: target.blockId,
        textOffset: target.offset,
      ),
    );
  }

  Future<void> _pastePlainTextAtActiveSelection() async {
    if (_surfaceDocumentSelection == null) {
      final field = _usableActiveTextField;
      if (field != null) {
        await field.pastePlainTextFromToolbar();
        _setActiveTextField(field);
        return;
      }
    }

    final block = _activeBlock;
    if (block == null || !_canPastePlainText) return;

    final internalFragment = widget.textController.internalDocumentClipboard;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = clipboard?.text;
    if ((internalFragment == null || internalFragment.isEmpty) &&
        (pastedText == null || pastedText.isEmpty)) {
      return;
    }

    final range = _activeDocumentRange ?? _collapsedDocumentRangeForBlock(block);
    if (range == null) return;

    final result = internalFragment != null && !internalFragment.isEmpty
        ? widget.textController.pasteDocumentClipboardAtRange(range)
        : widget.textController.replaceDocumentRangeWithPlainText(
            range,
            (pastedText ?? '').replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
            label: 'Paste plain text',
          );

    final caret = result.insertedRange.normalized().end;
    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: caret.blockId,
        textOffset: caret.offset,
      ),
    );
  }

  void _toggleInlineMarkForActiveSelection(TextMarkKind kind) {
    if (_surfaceDocumentSelection == null) {
      final field = _usableActiveTextField;
      if (field != null && field.toggleMarkForToolbar(kind)) {
        _setActiveTextField(field);
        return;
      }
    }

    final documentRange = _activeDocumentRange;
    final documentSelection = _activeDocumentSelection;
    if (documentRange == null || documentRange.isCollapsed || documentSelection == null) return;

    final effectiveDocumentSelection = documentSelection;

    widget.textController.toggleMarkForDocumentRange(documentRange, kind);

    if (effectiveDocumentSelection.isSingleBlock) {
      final block = widget.document.blockById(effectiveDocumentSelection.base.blockId);
      if (block != null) {
        _requestSelectionRestore(
          TextSystemPagedSelectionAnchor(
            blockId: block.id,
            baseOffset: effectiveDocumentSelection.base.textOffset,
            extentOffset: effectiveDocumentSelection.extent.textOffset,
          ).clampToBlock(block),
        );
      }
    } else {
      _runSelectionStateUpdate(() {
        _surfaceDocumentSelection = effectiveDocumentSelection;
        _activeCaretAnchor = effectiveDocumentSelection.extent;
        _activeBlockId = effectiveDocumentSelection.extent.blockId;
      });
    }
  }

  void _toggleBoldForActiveSelection() {
    _toggleInlineMarkForActiveSelection(TextMarkKind.bold);
  }

  void _toggleItalicForActiveSelection() {
    _toggleInlineMarkForActiveSelection(TextMarkKind.italic);
  }

  void _toggleUnderlineForActiveSelection() {
    _toggleInlineMarkForActiveSelection(TextMarkKind.underline);
  }

  void _toggleCodeForActiveSelection() {
    _toggleInlineMarkForActiveSelection(TextMarkKind.code);
  }

  void _toggleHighlightForActiveSelection() {
    _toggleInlineMarkForActiveSelection(TextMarkKind.highlight);
  }


  bool get _canOpenReferenceActionMenu {
    return widget.editable && widget.referenceActionRepository != null;
  }

  void _showReferenceSelectionRequiredMessage() {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Select text or place the caret, then choose a reference action.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _visibleLabelForCollapsedReferenceInsertion(
    TextSystemReferenceActionResult result,
  ) {
    final resultLabel = result.visibleLabel.trim();
    if (resultLabel.isNotEmpty) return resultLabel;

    final targetTitle = result.target.title.trim();
    if (targetTitle.isNotEmpty) return targetTitle;

    final inlineLabel = result.inlineMark.label.trim();
    if (inlineLabel.isNotEmpty) return inlineLabel;

    return result.actionType.label;
  }

  Future<void> _createReferenceForActiveSelection(TextSystemReferenceActionType actionType) async {
    final repository = widget.referenceActionRepository;
    if (repository == null) return;

    final isCitationAction = actionType == TextSystemReferenceActionType.citation;
    final activeField = _surfaceDocumentSelection == null ? _usableActiveTextField : null;
    final fieldSelectionAnchor = activeField?.currentSelectionAnchor;
    final fieldDocumentRange = activeField?.documentRangeForToolbarSelection();

    TextSystemDocumentRange? documentRange = fieldDocumentRange ?? _activeDocumentRange;
    TextSystemPagedDocumentSelection? documentSelection = fieldSelectionAnchor == null
        ? _activeDocumentSelection
        : TextSystemPagedDocumentSelection.fromAnchor(fieldSelectionAnchor);

    if (documentRange == null) {
      final position = _activeInsertPosition();
      if (position != null) {
        documentRange = TextSystemDocumentRange.collapsed(position);
        documentSelection = TextSystemPagedDocumentSelection(
          base: TextSystemPagedCaretAnchor(blockId: position.blockId, textOffset: position.offset),
          extent: TextSystemPagedCaretAnchor(blockId: position.blockId, textOffset: position.offset),
        );
      }
    }

    if (documentRange == null || documentSelection == null) {
      _showReferenceSelectionRequiredMessage();
      return;
    }

    final effectiveDocumentRange = documentRange;
    final effectiveDocumentSelection = documentSelection;

    final selectedText = effectiveDocumentRange.isCollapsed
        ? ''
        : widget.textController.plainTextForDocumentRange(effectiveDocumentRange).trim();
    if (!isCitationAction && !effectiveDocumentRange.isCollapsed && selectedText.isEmpty) {
      _showReferenceSelectionRequiredMessage();
      return;
    }

    final result = await showTextSystemReferenceActionPicker(
      context: context,
      selectedText: selectedText,
      repository: repository,
      initialActionType: actionType,
      citationSettings: TextSystemCitationSettings.fromDocument(widget.textController.document),
    );
    if (!mounted || result == null) return;

    if (result.actionType == TextSystemReferenceActionType.citation) {
      final normalized = effectiveDocumentRange.normalized();
      final settings = TextSystemCitationSettings.fromDocument(widget.textController.document);
      final mode = TextSystemCitationInlineModeX.fromId(
        result.inlineMark.metadata['citationInlineMode'] as String?,
      );
      final source = TextSystemCitationSource.fromReferenceTarget(result.target);
      final registry = TextSystemCitationRegistry.fromDocument(widget.textController.document);
      final sequenceNumber = registry.numberForTarget(result.target.id);
      final citationText = TextSystemCitationFormatter.inlineCitation(
        settings: settings,
        source: source,
        sequenceNumber: sequenceNumber,
        inlineMode: mode,
      );
      final citationMark = result.inlineMark.copyWith(
        selectedText: citationText,
        metadata: <String, Object?>{
          ...result.inlineMark.metadata,
          ...source.toMetadata(),
          'citationStyleId': settings.style.id,
          'citationInlineMode': mode.id,
          'citationText': citationText,
          'bibliographyManaged': true,
        },
      );
      final prefix = normalized.isCollapsed ? '' : ' ';
      final insertedText = '$prefix$citationText';
      widget.textController.insertMarkedPlainTextAtDocumentPosition(
        position: normalized.end,
        text: insertedText,
        marks: <TextMark>[
          TextMark(
            kind: TextMarkKind.link,
            range: TextSystemRange(prefix.length, insertedText.length),
            attributes: citationMark.toTextMarkAttributes(),
          ),
        ],
        label: 'Insert citation',
        transformAfterInsert: (document) => TextSystemCitationBibliographyGenerator.refreshDocument(document),
      );

      final endPosition = normalized.end;
      final block = widget.textController.document.blockById(endPosition.blockId);
      if (block != null) {
        _requestSelectionRestore(
          TextSystemPagedSelectionAnchor.collapsed(
            blockId: block.id,
            textOffset: endPosition.offset + insertedText.length,
          ).clampToBlock(block),
        );
      }
      return;
    }

    if (effectiveDocumentRange.isCollapsed) {
      final normalized = effectiveDocumentRange.normalized();
      final visibleLabel = _visibleLabelForCollapsedReferenceInsertion(result);
      final inlineMark = result.inlineMark.copyWith(selectedText: visibleLabel);
      widget.textController.insertMarkedPlainTextAtDocumentPosition(
        position: normalized.end,
        text: visibleLabel,
        marks: <TextMark>[
          TextMark(
            kind: TextMarkKind.link,
            range: TextSystemRange(0, visibleLabel.length),
            attributes: inlineMark.toTextMarkAttributes(),
          ),
        ],
        label: result.actionType.verbLabel,
      );

      final block = widget.textController.document.blockById(normalized.end.blockId);
      if (block != null) {
        _requestSelectionRestore(
          TextSystemPagedSelectionAnchor.collapsed(
            blockId: block.id,
            textOffset: normalized.end.offset + visibleLabel.length,
          ).clampToBlock(block),
        );
      }
      return;
    }

    widget.textController.applyMarkForDocumentRange(
      effectiveDocumentRange,
      TextMarkKind.link,
      attributes: result.inlineMark.toTextMarkAttributes(),
      label: result.actionType.verbLabel,
    );

    if (fieldSelectionAnchor != null) {
      final block = widget.textController.document.blockById(fieldSelectionAnchor.blockId);
      if (block != null) {
        _requestSelectionRestore(fieldSelectionAnchor.clampToBlock(block));
      }
      return;
    }

    if (effectiveDocumentSelection.isSingleBlock) {
      final block = widget.textController.document.blockById(effectiveDocumentSelection.base.blockId);
      if (block != null) {
        _requestSelectionRestore(
          TextSystemPagedSelectionAnchor(
            blockId: block.id,
            baseOffset: effectiveDocumentSelection.base.textOffset,
            extentOffset: effectiveDocumentSelection.extent.textOffset,
          ).clampToBlock(block),
        );
      }
    } else {
      _runSelectionStateUpdate(() {
        _surfaceDocumentSelection = effectiveDocumentSelection;
        _activeCaretAnchor = effectiveDocumentSelection.extent;
        _activeBlockId = effectiveDocumentSelection.extent.blockId;
      });
    }
  }

  void _changeCitationStyle(TextSystemCitationStyle style) {
    final settings = TextSystemCitationSettings.fromDocument(widget.textController.document).copyWith(style: style);
    final nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(
      settings.applyToDocument(widget.textController.document),
      settings: settings,
    );
    widget.textController.replaceDocument(
      nextDocument,
      label: 'Change citation style',
    );
  }

  void _changeCitationInlineMode(TextSystemCitationInlineMode mode) {
    final settings = TextSystemCitationSettings.fromDocument(widget.textController.document).copyWith(inlineMode: mode);
    final nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(
      settings.applyToDocument(widget.textController.document),
      settings: settings,
    );
    widget.textController.replaceDocument(
      nextDocument,
      label: 'Change citation mode',
    );
  }

  void _toggleHeaderFooterEditMode() {
    setState(() {
      if (_headerFooterEditMode) {
        _headerFooterEditMode = false;
        _headerFooterEditTarget = null;
      } else {
        _headerFooterEditMode = true;
        _headerFooterEditTarget = TextSystemHeaderFooterZoneKind.header;
      }
    });
  }

  void _setHeaderFooterEditMode({
    required bool enabled,
    TextSystemHeaderFooterZoneKind? target,
  }) {
    setState(() {
      _headerFooterEditMode = enabled;
      _headerFooterEditTarget = enabled
          ? (target ?? _headerFooterEditTarget ?? TextSystemHeaderFooterZoneKind.header)
          : null;
    });
  }

  void _changeActiveBlockStyle(_PagedBlockToolbarStyle style) {
    final block = _activeBlock;
    if (block == null) return;

    final selectionAnchor = (_activeSelectionAnchor ??
            TextSystemPagedSelectionAnchor.collapsed(
              blockId: block.id,
              textOffset: _activeCaretAnchor?.textOffset ?? block.text.length,
            ))
        .clampToBlock(block);

    switch (style) {
      case _PagedBlockToolbarStyle.paragraph:
        widget.textController.updateBlockType(
          block.id,
          TextSystemBlockType.paragraph,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.heading1:
        widget.textController.updateBlockType(
          block.id,
          TextSystemBlockType.heading,
          level: 1,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.heading2:
        widget.textController.updateBlockType(
          block.id,
          TextSystemBlockType.heading,
          level: 2,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.heading3:
        widget.textController.updateBlockType(
          block.id,
          TextSystemBlockType.heading,
          level: 3,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.quote:
        widget.textController.updateBlockType(
          block.id,
          TextSystemBlockType.quote,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.code:
        widget.textController.updateBlockType(
          block.id,
          TextSystemBlockType.code,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.bulletList:
        widget.textController.updateListGroupBlockType(
          block.id,
          TextSystemBlockType.listItem,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.numberedList:
        widget.textController.updateListGroupBlockType(
          block.id,
          TextSystemBlockType.listItem,
          metadata: style.metadataFor(block),
        );
      case _PagedBlockToolbarStyle.todo:
        widget.textController.updateListGroupBlockType(
          block.id,
          TextSystemBlockType.todo,
          checked: block.checked ?? false,
          metadata: style.metadataFor(block),
        );
    }

    _requestSelectionRestore(selectionAnchor);
  }



  void _insertPageBreakAtActiveSelection() {
    final position = _activeInsertPosition();
    if (position == null) return;

    final block = widget.textController.document.blockById(position.blockId);
    if (block == null || _isStructuralBreakBlock(block) || _isFootnoteBlock(block)) return;

    final target = widget.textController.insertPageBreakAt(
      position.blockId,
      position.offset.clamp(0, block.text.length).toInt(),
    );
    if (target == null) return;

    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: target.blockId,
        textOffset: target.offset,
      ),
    );
  }

  void _insertSectionBreakAtActiveSelection() {
    final position = _activeInsertPosition();
    if (position == null) return;

    final block = widget.textController.document.blockById(position.blockId);
    if (block == null || _isStructuralBreakBlock(block) || _isFootnoteBlock(block)) return;

    final target = widget.textController.insertSectionBreakAt(
      position.blockId,
      position.offset.clamp(0, block.text.length).toInt(),
      restartPageNumbering: true,
      pageNumberStartAt: 1,
    );
    if (target == null) return;

    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: target.blockId,
        textOffset: target.offset,
      ),
    );
  }

  void _insertFootnoteAtActiveSelection() {
    final position = _activeInsertPosition();
    if (position == null) return;

    final block = widget.textController.document.blockById(position.blockId);
    if (block == null || _isStructuralBreakBlock(block) || _isFootnoteBlock(block)) return;

    final target = widget.textController.insertFootnoteAt(
      position.blockId,
      position.offset.clamp(0, block.text.length).toInt(),
      initialText: '',
    );
    if (target == null) return;

    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: target.blockId,
        textOffset: target.offset,
      ),
    );
  }

  TextSystemDocumentPosition? _activeInsertPosition() {
    final fieldSelection = _surfaceDocumentSelection == null
        ? _usableActiveTextField?.currentSelectionAnchor
        : null;
    if (fieldSelection != null) {
      return _documentRangeForPagedSelection(fieldSelection)?.normalized().end;
    }

    final activeRange = _activeDocumentRange;
    if (activeRange != null) {
      return activeRange.normalized().end;
    }

    final block = _activeBlock;
    if (block == null || _isStructuralBreakBlock(block) || _isFootnoteBlock(block)) {
      return null;
    }

    final blockIndex = widget.textController.document.blocks.indexWhere(
      (candidate) => candidate.id == block.id,
    );
    if (blockIndex < 0) return null;

    final caretOffset = (_activeSelectionAnchor?.caretOffset ??
            _activeCaretAnchor?.textOffset ??
            block.text.length)
        .clamp(0, block.text.length)
        .toInt();

    return TextSystemDocumentPosition(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: caretOffset,
    );
  }

  String _selectedTextForEmbeddedTodoDraft() {
    final fieldRange = _surfaceDocumentSelection == null
        ? _usableActiveTextField?.documentRangeForToolbarSelection()
        : null;
    final range = fieldRange ?? _activeDocumentRange;
    if (range == null || range.isCollapsed) {
      return '';
    }
    return widget.textController.plainTextForDocumentRange(range).trim();
  }

  Future<void> _insertEmbeddedTodoAtActiveSelection() async {
    final repository = widget.embeddedTodoRepository;
    if (repository == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Open the writer from the app/library route to create synced TODOs.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final position = _activeInsertPosition();
    if (position == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Place the caret in a text block before inserting an app TODO.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final draft = await _showEmbeddedTodoDraftDialog(
      context: context,
      initialTitle: _selectedTextForEmbeddedTodoDraft(),
    );
    if (!mounted || draft == null) return;

    final blockId = 'embedded-todo-${DateTime.now().microsecondsSinceEpoch}';
    final todoId = await repository.createTodoForDocumentBlock(
      documentId: widget.textController.document.id,
      blockId: blockId,
      title: draft.title,
      priority: draft.priority,
      deadline: draft.deadline,
    );
    if (!mounted) return;

    final todoBlock = TextSystemEmbeddedTodoMetadata.createBlock(
      blockId: blockId,
      documentId: widget.textController.document.id,
      todoId: todoId,
      title: draft.title,
      priority: draft.priority,
      deadline: draft.deadline,
      baseMetadata: const <String, Object?>{
        'styleId': TextSystemDocumentStyleSheet.todo,
      },
    );

    final target = widget.textController.insertBlockAtPosition(
      position.blockId,
      position.offset,
      todoBlock,
      label: 'Insert app TODO',
    );
    if (target == null) return;

    _embeddedTodoSnapshots = _embeddedTodoSnapshotsFor(widget.textController.document);
    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: target.blockId,
        textOffset: target.offset,
      ),
    );
  }



  Future<void> _insertFigureAtActiveSelection() async {
    if (!widget.editable) return;
    final position = _activeInsertPosition();
    if (position == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Place the caret where the figure should be inserted.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final draft = await _showAcademicFigureDraftDialog(
      context: context,
      document: widget.textController.document,
    );
    if (!mounted || draft == null) return;

    final block = _academicFigureBlockFromDraft(draft);
    final exitTarget = _insertObjectBlockTransaction(
      position,
      block,
      label: 'Insert figure',
    );
    if (exitTarget == null) return;

    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: exitTarget.blockId,
        textOffset: exitTarget.offset,
      ),
    );
  }

  Future<void> _insertTableAtActiveSelection() async {
    if (!widget.editable) return;
    final position = _activeInsertPosition();
    if (position == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Place the caret where the table should be inserted.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final draft = await _showAcademicTableDraftDialog(
      context: context,
      document: widget.textController.document,
    );
    if (!mounted || draft == null) return;

    final block = _academicTableBlockFromDraft(draft);
    final exitTarget = _insertObjectBlockTransaction(
      position,
      block,
      label: 'Insert table',
    );
    if (exitTarget == null) return;

    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: exitTarget.blockId,
        textOffset: exitTarget.offset,
      ),
    );
  }

  Future<void> _insertEquationAtActiveSelection() async {
    if (!widget.editable) return;
    final position = _activeInsertPosition();
    if (position == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Place the caret where the equation should be inserted.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final block = _academicEquationBlockFromDraft(
      const _AcademicEquationDraft(
        latex: '',
        label: '',
        note: '',
        numbered: false,
      ),
    );
    final exitTarget = _insertObjectBlockTransaction(
      position,
      block,
      label: 'Insert equation',
    );
    if (exitTarget == null) return;

    _selectObjectBlock(block.id, preserveFocus: true);
  }

  Future<void> _insertInlineMathAtActiveSelection() async {
    if (!widget.editable) return;

    final activeField = _surfaceDocumentSelection == null ? _usableActiveTextField : null;
    final fieldAnchor = activeField?.currentSelectionAnchor;
    TextSystemDocumentRange? range = fieldAnchor == null
        ? _activeDocumentRange
        : _documentRangeForPagedSelection(fieldAnchor);

    if (range == null) {
      final position = _activeInsertPosition();
      if (position != null) range = TextSystemDocumentRange.collapsed(position);
    }

    if (range == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Place the caret where the inline math should be inserted.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final normalized = range.normalized();
    if (normalized.start.blockId != normalized.end.blockId) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Inline math can only be inserted inside one paragraph for now.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final selectedText = normalized.isCollapsed
        ? ''
        : widget.textController
            .plainTextForDocumentRange(normalized)
            .replaceAll('\r\n', ' ')
            .replaceAll('\n', ' ')
            .trim();
    final insertionText = selectedText.isEmpty ? r'\(  \)' : '\\($selectedText\\)';
    final result = widget.textController.replaceDocumentRangeWithPlainText(
      normalized,
      insertionText,
      label: selectedText.isEmpty ? 'Insert inline math' : 'Wrap inline math',
    );

    final inserted = result.insertedRange.normalized();
    final innerStart = inserted.start.offset + 2;
    final innerEnd = selectedText.isEmpty ? innerStart + 2 : innerStart + selectedText.length;
    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor(
        blockId: inserted.start.blockId,
        baseOffset: innerStart,
        extentOffset: innerEnd,
      ),
    );
  }


  Future<void> _insertCrossReferenceAtActiveSelection() async {
    if (!widget.editable) return;

    final activeField = _surfaceDocumentSelection == null ? _usableActiveTextField : null;
    final fieldAnchor = activeField?.currentSelectionAnchor;
    TextSystemDocumentRange? range = fieldAnchor == null
        ? _activeDocumentRange
        : _documentRangeForPagedSelection(fieldAnchor);

    if (range == null) {
      final position = _activeInsertPosition();
      if (position != null) range = TextSystemDocumentRange.collapsed(position);
    }

    if (range == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Place the caret where the cross-reference should be inserted.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final targets = _academicCrossReferenceTargets(widget.textController.document);
    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Insert a figure, table, or equation before adding a cross-reference.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final target = await _showAcademicCrossReferencePickerDialog(
      context: context,
      targets: targets,
    );
    if (!mounted || target == null) return;

    final normalized = range.normalized();
    if (normalized.start.blockId != normalized.end.blockId) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Cross-references can only replace text inside one paragraph for now.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final visibleText = target.visibleText;
    final exportLabel = target.exportLabel;
    final inlineMark = TextSystemInlineReferenceMark(
      id: 'xref-${DateTime.now().microsecondsSinceEpoch}',
      kind: target.referenceKind,
      targetId: target.blockId,
      label: target.title,
      selectedText: visibleText,
      metadata: <String, Object?>{
        'crossReference': true,
        'crossReferenceKind': target.kind,
        'crossReferenceLabel': exportLabel,
        'crossReferenceOrdinal': target.ordinal,
        'crossReferenceVisibleText': visibleText,
        if (target.caption.trim().isNotEmpty) 'crossReferenceCaption': target.caption.trim(),
      },
    );
    final attributes = <String, String>{
      ...inlineMark.toTextMarkAttributes(),
      'role': target.kind,
      'kind': target.kind,
      'textSystemReferenceKind': target.kind,
      if (exportLabel.isNotEmpty) 'label': exportLabel,
      if (exportLabel.isNotEmpty) 'crossReferenceLabel': exportLabel,
    };
    final inserted = _replaceSingleBlockRangeWithMarkedTextTransaction(
      normalized,
      visibleText,
      mark: TextMark(
        kind: TextMarkKind.link,
        range: TextSystemRange.collapsed(0),
        attributes: attributes,
      ),
      label: 'Insert cross-reference',
    )?.normalized();
    if (inserted == null) return;

    _requestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: inserted.start.blockId,
        textOffset: inserted.end.offset,
      ),
    );
  }

  Future<void> _addMarginAnnotationAtActivePosition(_MarginAnnotationType type) async {
    if (!widget.editable) return;
    final position = _activeInsertPosition();
    if (position == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(type == _MarginAnnotationType.todo
              ? 'Place the caret where the document TODO should attach.'
              : 'Place the caret where the document comment should attach.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final selectedText = _selectedTextForEmbeddedTodoDraft();
    final now = DateTime.now();
    final draft = _MarginAnnotationDraftSession(
      id: 'draft-${type.name}-${now.microsecondsSinceEpoch}',
      blockId: position.blockId,
      textOffset: position.offset,
      type: type,
      initialText: type == _MarginAnnotationType.todo && selectedText.isNotEmpty ? selectedText : '',
      checked: false,
      createdAt: now,
    );

    _runSelectionStateUpdate(() {
      _marginAnnotationDraft = draft;
      _activeMarginAnnotationId = null;
      _activeSelectionAnchor = TextSystemPagedSelectionAnchor.collapsed(
        blockId: position.blockId,
        textOffset: position.offset,
      );
      _activeCaretAnchor = TextSystemPagedCaretAnchor(
        blockId: position.blockId,
        textOffset: position.offset,
      );
      _restoreSelectionAnchor = _activeSelectionAnchor;
      _restoreCaretAnchor = _activeCaretAnchor;
      _activeBlockId = position.blockId;
      _surfaceDocumentSelection = null;
      _surfaceSelectionDragBase = null;
    });
  }

  void _submitMarginAnnotationDraft(
    _MarginAnnotationDraftSession draft,
    String text,
    bool checked,
  ) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _cancelMarginAnnotationDraft(draft.id);
      return;
    }

    final now = DateTime.now();
    final annotation = _MarginAnnotationData(
      id: 'margin-${draft.type.name}-${now.microsecondsSinceEpoch}',
      blockId: draft.blockId,
      textOffset: draft.textOffset,
      type: draft.type,
      text: trimmed,
      checked: checked,
      createdAt: now,
      updatedAt: now,
    );

    _runSelectionStateUpdate(() {
      if (_marginAnnotationDraft?.id == draft.id) {
        _marginAnnotationDraft = null;
      }
      _activeMarginAnnotationId = annotation.id;
    });
    _upsertMarginAnnotation(
      annotation,
      label: draft.type == _MarginAnnotationType.todo ? 'Add document TODO' : 'Add document comment',
    );
  }

  void _cancelMarginAnnotationDraft(String draftId) {
    if (!mounted || _marginAnnotationDraft?.id != draftId) return;
    _runSelectionStateUpdate(() {
      _marginAnnotationDraft = null;
    });
  }

  void _upsertMarginAnnotation(_MarginAnnotationData annotation, {String label = 'Update document thread'}) {
    final annotations = _marginAnnotationsFromDocument(widget.textController.document);
    var replaced = false;
    final next = <_MarginAnnotationData>[
      for (final existing in annotations)
        if (existing.id == annotation.id) ...[
          annotation.copyWith(updatedAt: DateTime.now()),
        ] else
          existing,
    ];
    for (final existing in annotations) {
      if (existing.id == annotation.id) {
        replaced = true;
        break;
      }
    }
    if (!replaced) next.add(annotation);
    _replaceMarginAnnotations(next, label: label);
  }

  void _deleteMarginAnnotation(String annotationId) {
    if (_activeMarginAnnotationId == annotationId && mounted) {
      _runSelectionStateUpdate(() => _activeMarginAnnotationId = null);
    }
    final annotations = _marginAnnotationsFromDocument(widget.textController.document)
        .where((annotation) => annotation.id != annotationId)
        .toList();
    _replaceMarginAnnotations(annotations, label: 'Delete document thread');
  }

  void _toggleMarginTodo(String annotationId) {
    final annotations = _marginAnnotationsFromDocument(widget.textController.document);
    final next = <_MarginAnnotationData>[
      for (final annotation in annotations)
        if (annotation.id == annotationId && annotation.type == _MarginAnnotationType.todo)
          annotation.copyWith(checked: !annotation.checked, updatedAt: DateTime.now())
        else
          annotation,
    ];
    _replaceMarginAnnotations(next, label: 'Toggle document TODO');
  }

  void _toggleMarginCommentResolved(String annotationId) {
    final annotations = _marginAnnotationsFromDocument(widget.textController.document);
    final next = <_MarginAnnotationData>[
      for (final annotation in annotations)
        if (annotation.id == annotationId && annotation.type == _MarginAnnotationType.comment)
          annotation.copyWith(resolved: !annotation.resolved, updatedAt: DateTime.now())
        else
          annotation,
    ];
    _replaceMarginAnnotations(next, label: 'Resolve document comment');
  }

  void _selectMarginAnnotation(_MarginAnnotationData annotation) {
    final block = widget.textController.document.blockById(annotation.blockId);
    final maxOffset = math.max(0, block?.text.length ?? annotation.textOffset);
    final textOffset = annotation.textOffset.clamp(0, maxOffset).toInt();
    _runSelectionStateUpdate(() {
      _activeMarginAnnotationId = annotation.id;
      _marginAnnotationDraft = null;
      _activeSelectionAnchor = TextSystemPagedSelectionAnchor.collapsed(
        blockId: annotation.blockId,
        textOffset: textOffset,
      );
      _activeCaretAnchor = TextSystemPagedCaretAnchor(
        blockId: annotation.blockId,
        textOffset: textOffset,
      );
      _restoreSelectionAnchor = _activeSelectionAnchor;
      _restoreCaretAnchor = _activeCaretAnchor;
      _activeBlockId = annotation.blockId;
      _surfaceDocumentSelection = null;
      _surfaceSelectionDragBase = null;
    });
  }

  void _replaceMarginAnnotations(List<_MarginAnnotationData> annotations, {required String label}) {
    final metadata = Map<String, Object?>.from(widget.textController.document.metadata);
    if (annotations.isEmpty) {
      metadata.remove(_marginAnnotationsMetadataKey);
    } else {
      metadata[_marginAnnotationsMetadataKey] = annotations.map((annotation) => annotation.toJson()).toList();
    }
    widget.textController.replaceDocument(
      widget.textController.document.copyWith(metadata: metadata, updatedAt: DateTime.now()),
      label: label,
    );
    widget.commandController?.scheduleStateRefresh();
  }

  Future<void> _editMarginAnnotation(_MarginAnnotationData annotation) async {
    _selectMarginAnnotation(annotation);
    final draft = await _showMarginAnnotationDraftDialog(
      context: context,
      type: annotation.type,
      initialText: annotation.text,
      initialChecked: annotation.checked,
      existingAnnotation: annotation,
    );
    if (!mounted || draft == null) return;
    final text = draft.text.trim();
    if (text.isEmpty) {
      _deleteMarginAnnotation(annotation.id);
      return;
    }
    _upsertMarginAnnotation(
      annotation.copyWith(text: text, checked: draft.checked, updatedAt: DateTime.now()),
      label: annotation.type == _MarginAnnotationType.todo ? 'Edit document TODO' : 'Edit document comment',
    );
  }

  void _performUndo() {
    if (!widget.textController.canUndo) return;
    final anchor = _activeSelectionAnchor ??
        (_activeCaretAnchor == null
            ? null
            : TextSystemPagedSelectionAnchor.collapsed(
                blockId: _activeCaretAnchor!.blockId,
                textOffset: _activeCaretAnchor!.textOffset,
              ));
    final previousBlockIndex = anchor == null ? null : _indexOfBlock(anchor.blockId);

    _activeTextField?.forceSyncFromDocumentBeforeHistory();
    widget.textController.undo();
    _activeTextField = null;

    final restoreAnchor = _historyRestoreAnchor(anchor, previousBlockIndex);
    if (restoreAnchor != null) {
      _requestSelectionRestore(restoreAnchor);
    }
  }

  void _performRedo() {
    if (!widget.textController.canRedo) return;
    final anchor = _activeSelectionAnchor ??
        (_activeCaretAnchor == null
            ? null
            : TextSystemPagedSelectionAnchor.collapsed(
                blockId: _activeCaretAnchor!.blockId,
                textOffset: _activeCaretAnchor!.textOffset,
              ));
    final previousBlockIndex = anchor == null ? null : _indexOfBlock(anchor.blockId);

    _activeTextField?.forceSyncFromDocumentBeforeHistory();
    widget.textController.redo();
    _activeTextField = null;

    final restoreAnchor = _historyRestoreAnchor(anchor, previousBlockIndex);
    if (restoreAnchor != null) {
      _requestSelectionRestore(restoreAnchor);
    }
  }

  ({TextSystemPagedBlockPage page, Offset localPosition}) _resolveSelectionPagePoint(
    TextSystemPagedBlockPage originPage,
    Offset localPosition,
    double pageHeight,
  ) {
    final pages = _latestSelectionPages;
    if (pages.isEmpty || _latestSelectionPageStride <= 0 || pageHeight <= 0) {
      return (page: originPage, localPosition: localPosition);
    }

    var pageIndex = pages.indexWhere((page) => page.pageNumber == originPage.pageNumber);
    if (pageIndex < 0) {
      return (page: originPage, localPosition: localPosition);
    }

    var dy = localPosition.dy;
    final stride = _latestSelectionPageStride;

    while (dy < 0 && pageIndex > 0) {
      pageIndex -= 1;
      dy += stride;
    }

    while (dy > pageHeight && pageIndex < pages.length - 1) {
      pageIndex += 1;
      dy -= stride;
    }

    return (
      page: pages[pageIndex],
      localPosition: Offset(
        localPosition.dx,
        dy.clamp(0.0, pageHeight).toDouble(),
      ),
    );
  }

  TextSystemPagedCaretAnchor? _documentPositionForPagePoint(
    TextSystemPagedBlockPage page,
    Offset localPosition,
    EdgeInsets margins,
  ) {
    final hit = TextSystemDocumentSelectionGeometry.positionForPagePoint(
      context: context,
      document: widget.textController.document,
      page: page,
      pageSetup: widget.pageSetup,
      margins: margins,
      pagePoint: localPosition,
    );

    if (hit == null) return null;

    return TextSystemPagedCaretAnchor(
      blockId: hit.blockId,
      textOffset: hit.offset,
    );
  }

  void _handleSurfaceSelectionPointerDown(
    TextSystemPagedBlockPage page,
    Offset localPosition,
    EdgeInsets margins,
    double pageHeight,
  ) {
    if (!widget.editable || _workspacePanActive || _workspaceModifierPressed) return;

    final resolved = _resolveSelectionPagePoint(page, localPosition, pageHeight);
    final anchor = _documentPositionForPagePoint(resolved.page, resolved.localPosition, margins);
    if (anchor == null) {
      _clearObjectSelection(clearFocus: true);
      _clearBlockSelection();
      return;
    }

    _surfaceSelectionDragBase = anchor;
    _clearObjectSelection(clearFocus: false);
    _clearBlockSelection();

    if (_documentSelectionMode) {
      FocusManager.instance.primaryFocus?.unfocus();
      _runSelectionStateUpdate(() {
        _activeTextField = null;
        _surfaceDocumentSelection = TextSystemPagedDocumentSelection(
          base: anchor,
          extent: anchor,
        );
        _activeSelectionAnchor = null;
        _activeCaretAnchor = anchor;
        _activeBlockId = anchor.blockId;
      });
    }
  }

  TextSystemPagedCaretAnchor _directionalExtentForCrossBlockDrag(
    TextSystemPagedCaretAnchor base,
    TextSystemPagedCaretAnchor rawExtent,
  ) {
    final baseIndex = _indexOfBlock(base.blockId);
    final extentIndex = _indexOfBlock(rawExtent.blockId);
    if (baseIndex == null || extentIndex == null || baseIndex == extentIndex) {
      return rawExtent;
    }

    final extentBlock = widget.textController.document.blocks[extentIndex];
    final textLength = extentBlock.text.length;
    if (textLength == 0) {
      return rawExtent;
    }

    // If the pointer enters the next block near its left edge, TextPainter
    // correctly returns offset 0. For a cross-block drag this produces no
    // visible selection in the target block, which feels like selection is
    // stuck in the previous block. Professional editors normally make the
    // range visibly enter the next paragraph/block as the drag crosses the
    // block boundary.
    if (extentIndex > baseIndex && rawExtent.textOffset <= 0) {
      return TextSystemPagedCaretAnchor(
        blockId: rawExtent.blockId,
        textOffset: textLength,
      );
    }

    // Symmetric case for upward drags: if entering the previous block at its
    // far right edge gives the end offset, snap to the start so the previous
    // block visibly enters the range.
    if (extentIndex < baseIndex && rawExtent.textOffset >= textLength) {
      return TextSystemPagedCaretAnchor(
        blockId: rawExtent.blockId,
        textOffset: 0,
      );
    }

    return rawExtent;
  }

  void _handleSurfaceSelectionPointerMove(
    TextSystemPagedBlockPage page,
    Offset localPosition,
    EdgeInsets margins,
    double pageHeight,
  ) {
    if (!widget.editable) return;

    final base = _surfaceSelectionDragBase;
    if (base == null) return;

    final resolved = _resolveSelectionPagePoint(page, localPosition, pageHeight);
    final rawExtent = _documentPositionForPagePoint(resolved.page, resolved.localPosition, margins);
    if (rawExtent == null) return;

    final extent = _directionalExtentForCrossBlockDrag(base, rawExtent);

    final shouldUseSurfaceSelection =
        _documentSelectionMode ||
        _surfaceDocumentSelection != null ||
        base.blockId != extent.blockId;

    if (!shouldUseSurfaceSelection) return;

    final selection = TextSystemPagedDocumentSelection(
      base: base,
      extent: extent,
    );

    FocusManager.instance.primaryFocus?.unfocus();

    _runSelectionStateUpdate(() {
      _activeTextField = null;
      _surfaceDocumentSelection = selection;
      _activeSelectionAnchor = null;
      _activeCaretAnchor = extent;
      _activeBlockId = extent.blockId;
    });
  }

  void _handleSurfaceSelectionPointerEnd() {
    _surfaceSelectionDragBase = null;
  }

  bool get _workspaceModifierPressed =>
      HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

  void _handleWorkspacePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_workspaceModifierPressed) return;

    final onPageZoomChanged = widget.onPageZoomChanged;
    if (onPageZoomChanged == null) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent resolvedEvent) {
      if (resolvedEvent is! PointerScrollEvent) return;
      final dy = resolvedEvent.scrollDelta.dy;
      if (dy == 0) return;
      final step = dy < 0 ? 0.05 : -0.05;
      onPageZoomChanged((widget.pageZoom + step).clamp(0.75, 1.75).toDouble());
    });
  }

  void _handleWorkspacePointerDown(PointerDownEvent event) {
    final primaryButton = (event.buttons & kPrimaryMouseButton) != 0;
    if (!_workspaceModifierPressed || !primaryButton) return;

    _workspacePanLastGlobalPosition = event.position;
    if (!_workspacePanActive) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _workspacePanActive = true);
    }
  }

  void _handleWorkspacePointerMove(PointerMoveEvent event) {
    final primaryButton = (event.buttons & kPrimaryMouseButton) != 0;
    if (!_workspaceModifierPressed || !primaryButton) {
      _handleWorkspacePointerUpOrCancel();
      return;
    }

    if (_workspacePanLastGlobalPosition == null) {
      _workspacePanLastGlobalPosition = event.position;
      if (!_workspacePanActive && mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _workspacePanActive = true);
      }
      return;
    }

    final delta = event.delta;
    _workspacePanLastGlobalPosition = event.position;

    void panController(ScrollController controller, double deltaPixels) {
      if (!controller.hasClients || deltaPixels == 0) return;
      final position = controller.position;
      final next = (position.pixels - deltaPixels).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ).toDouble();
      if (next != position.pixels) controller.jumpTo(next);
    }

    final verticalController = widget.scrollController;
    if (verticalController != null) {
      panController(verticalController, delta.dy);
    }
    panController(_horizontalScrollController, delta.dx);
  }

  void _handleWorkspacePointerUpOrCancel() {
    if (_workspacePanLastGlobalPosition == null && !_workspacePanActive) return;
    _workspacePanLastGlobalPosition = null;
    if (mounted && _workspacePanActive) {
      setState(() => _workspacePanActive = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _surfaceFocusNode,
      onKeyEvent: _handleEditorKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handleWorkspacePointerSignal,
        onPointerDown: _handleWorkspacePointerDown,
        onPointerMove: _handleWorkspacePointerMove,
        onPointerUp: (_) => _handleWorkspacePointerUpOrCancel(),
        onPointerCancel: (_) => _handleWorkspacePointerUpOrCancel(),
        child: DecoratedBox(
        decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
        child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = widget.focusMode ? 30.0 : 58.0;
          final viewportContentWidth = math.max(320.0, constraints.maxWidth - horizontalPadding * 2);
          final showCommentRail = (widget.showMarginAnnotations || _marginAnnotationDraft != null || _activeMarginAnnotationId != null) && !widget.focusMode;
          final reservedRailWidth = showCommentRail
              ? _PageCommentRail.commentRailWidth + _PageCommentRail.commentRailGap
              : 0.0;
          final zoom = widget.pageZoom.clamp(0.75, 1.75).toDouble();
          final physicalWidth = widget.pageMaxWidth *
              (widget.pageSetup.pageWidthMm / TextSystemPagedBlockSurface._a4PortraitReferenceWidthMm);
          final pageWidth = math.max(320.0, physicalWidth);
          final pageHeight = pageWidth * widget.pageSetup.heightToWidthRatio;
          final pageOuterWidth = pageWidth + reservedRailWidth;
          final pageOuterHeight = TextSystemPagedBlockSurface._pageHeaderHeight +
              TextSystemPagedBlockSurface._pageHeaderGap +
              pageHeight;
          final horizontalContentWidth = math.max(viewportContentWidth, pageOuterWidth * zoom);
          if (_pendingHorizontalViewportCenter) {
            _pendingHorizontalViewportCenter = false;
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_horizontalScrollController.hasClients) return;
              final position = _horizontalScrollController.position;
              if (position.maxScrollExtent <= 0) return;
              _horizontalScrollController.jumpTo(position.maxScrollExtent / 2);
            });
          }
          final margins = widget.pageSetup.margins.toPagePadding(
            pageWidth,
            widget.pageSetup.pageWidthMm,
          );
          final layout = TextSystemPagedBlockLayoutEngine.layout(
            context: context,
            document: widget.document,
            pageSetup: widget.pageSetup,
            pageWidthPx: pageWidth,
          );
          _latestSelectionPages = layout.pages;
          _latestSelectionPageStride = pageOuterHeight + TextSystemPagedBlockSurface._pageGap;
          final navigation = _navigationForLayout(layout);

          return Scrollbar(
            controller: widget.scrollController,
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: EdgeInsets.symmetric(
                vertical: widget.focusMode ? 30 : 58,
              ),
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: horizontalContentWidth),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    if (widget.showSurfaceToolbar) ...[
                      _PagedBlockSurfaceBanner(
                        layout: layout,
                        pageSetup: widget.pageSetup,
                        pageFurniture: widget.pageFurniture,
                        styleSheet: TextSystemDocumentStyleSheet.academicDefault(pageSetup: widget.pageSetup),
                        editable: widget.editable,
                        headerFooterEditMode: _headerFooterEditMode,
                        documentSelectionMode: _documentSelectionMode,
                        activeBlock: _activeBlock,
                        onToggleDocumentSelectionMode: widget.editable
                            ? () => _setDocumentSelectionMode(!_documentSelectionMode)
                            : null,
                        onToggleHeaderFooterEditMode: widget.editable ? _toggleHeaderFooterEditMode : null,
                        onUndo: widget.editable && widget.textController.canUndo
                            ? _performUndo
                            : null,
                        onRedo: widget.editable && widget.textController.canRedo
                            ? _performRedo
                            : null,
                        onBlockStyleChanged: widget.editable ? _changeActiveBlockStyle : null,
                        onInsertPageBreak: widget.editable ? _insertPageBreakAtActiveSelection : null,
                        onInsertSectionBreak: widget.editable ? _insertSectionBreakAtActiveSelection : null,
                        onInsertFootnote: widget.editable ? _insertFootnoteAtActiveSelection : null,
                        onInsertEmbeddedTodo: widget.editable && widget.embeddedTodoRepository != null
                            ? _insertEmbeddedTodoAtActiveSelection
                            : null,
                        onReferenceAction: _canOpenReferenceActionMenu ? _createReferenceForActiveSelection : null,
                        citationSettings: TextSystemCitationSettings.fromDocument(widget.textController.document),
                        onCitationStyleChanged: widget.editable ? _changeCitationStyle : null,
                        onCitationInlineModeChanged: widget.editable ? _changeCitationInlineMode : null,
                        onToggleBold: _canToggleBold ? _toggleBoldForActiveSelection : null,
                        onToggleItalic: _canToggleItalic ? _toggleItalicForActiveSelection : null,
                        onToggleUnderline: _canToggleUnderline ? _toggleUnderlineForActiveSelection : null,
                        onToggleCode: _canToggleCode ? _toggleCodeForActiveSelection : null,
                        onToggleHighlight: _canToggleHighlight ? _toggleHighlightForActiveSelection : null,
                        onCopySelection: _canCopySelection ? _copyActiveSelectionToClipboard : null,
                        onCutSelection: _canCutSelection ? _cutActiveSelectionToClipboard : null,
                        onPastePlainText: _canPastePlainText ? _pastePlainTextAtActiveSelection : null,
                        boldActive: _activeSelectionIsBold,
                        italicActive: _activeSelectionIsItalic,
                        underlineActive: _activeSelectionIsUnderline,
                        codeActive: _activeSelectionIsCode,
                        highlightActive: _activeSelectionIsHighlighted,
                        boldEnabled: _canToggleBold,
                        italicEnabled: _canToggleItalic,
                        underlineEnabled: _canToggleUnderline,
                        codeEnabled: _canToggleCode,
                        highlightEnabled: _canToggleHighlight,
                        selectionStatusLabel: _selectionStatusLabel,
                        selectedObjectStatusLabel: _selectedObjectStatusLabel,
                        activeTableContext: _activeTableContext,
                        onDuplicateSelectedObject: _selectedDocumentObject == null ? null : _duplicateSelectedObjectBlock,
                        onMoveSelectedObjectUp: _selectedDocumentObject == null ? null : () => _moveSelectedObjectBlock(-1),
                        onMoveSelectedObjectDown: _selectedDocumentObject == null ? null : () => _moveSelectedObjectBlock(1),
                        onDeleteSelectedObject: _selectedDocumentObject == null ? null : _deleteSelectedObjectBlock,
                      ),
                      const SizedBox(height: 18),
                    ] else
                      const SizedBox(height: 10),
                    for (final page in layout.pages)
                      Padding(
                        padding: EdgeInsets.only(bottom: TextSystemPagedBlockSurface._pageGap * zoom),
                        child: SizedBox(
                          width: pageOuterWidth * zoom,
                          height: pageOuterHeight * zoom,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: pageOuterWidth,
                              height: pageOuterHeight,
                              child: _PagedBlockPageView(
                                textController: widget.textController,
                                document: widget.document,
                                page: page,
                                pageCount: layout.pageCount,
                                pageSetup: widget.pageSetup,
                                pageFurniture: widget.pageFurniture,
                                onPageFurnitureChanged: widget.onPageFurnitureChanged,
                                headerFooterEditMode: _headerFooterEditMode,
                                headerFooterEditTarget: _headerFooterEditTarget,
                                onHeaderFooterEditModeChanged: (value) => _setHeaderFooterEditMode(enabled: value),
                                onHeaderFooterEditTargetChanged: (target) => _setHeaderFooterEditMode(enabled: true, target: target),
                                pageWidth: pageWidth,
                                pageHeight: pageHeight,
                                margins: margins,
                                showMarginGuides: widget.showMarginGuides,
                                showMarginMarkers: widget.showMarginMarkers,
                                showMarginAnnotations: showCommentRail,
                                activeMarginAnnotationId: _activeMarginAnnotationId,
                                marginAnnotationDraft: _marginAnnotationDraft,
                                editable: widget.editable,
                                selectedObjectBlockId: _selectedDocumentObject?.blockId,
                                selectedBlockIds: _selectedBlockIds,
                                navigation: navigation,
                                restoreCaretAnchor: _restoreCaretAnchor,
                                restoreSelectionAnchor: _restoreSelectionAnchor,
                                surfaceDocumentSelection: _surfaceDocumentSelection,
                                documentSelectionMode: _documentSelectionMode,
                                onSurfaceSelectionPointerDown: _handleSurfaceSelectionPointerDown,
                                onSurfaceSelectionPointerMove: _handleSurfaceSelectionPointerMove,
                                onSurfaceSelectionPointerEnd: _handleSurfaceSelectionPointerEnd,
                                onActiveCaretChanged: _setActiveCaretAnchor,
                                onActiveSelectionChanged: _setActiveSelectionAnchor,
                                onActiveFieldChanged: _setActiveTextField,
                                onRequestCaretRestore: _requestCaretRestore,
                                onRequestSelectionRestore: _requestSelectionRestore,
                                onRestoreSelectionConsumed: _handleRestoreSelectionConsumed,
                                onBlockSelectionPointerDown: _handleBlockSelectionPointerDown,
                                onSelectObjectBlock: _selectObjectBlock,
                                onDuplicateSelectedObject: _duplicateSelectedObjectBlock,
                                onMoveSelectedObjectUp: () => _moveSelectedObjectBlock(-1),
                                onMoveSelectedObjectDown: () => _moveSelectedObjectBlock(1),
                                onDeleteSelectedObject: _deleteSelectedObjectBlock,
                                onActiveTableContextChanged: _setActiveTableContext,
                                onSelectMarginAnnotation: _selectMarginAnnotation,
                                onEditMarginAnnotation: _editMarginAnnotation,
                                onDeleteMarginAnnotation: _deleteMarginAnnotation,
                                onToggleMarginTodo: _toggleMarginTodo,
                                onToggleMarginCommentResolved: _toggleMarginCommentResolved,
                                onSubmitMarginAnnotationDraft: _submitMarginAnnotationDraft,
                                onCancelMarginAnnotationDraft: _cancelMarginAnnotationDraft,
                                onOpenReferenceTarget: widget.onOpenReferenceTarget,
                              ),
                            ),
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  ),
);
  }

  Map<String, _PagedFragmentNavigation> _navigationForLayout(TextSystemPagedBlockLayout layout) {
    final fragments = <TextSystemPagedBlockFragment>[
      for (final page in layout.pages)
        ...page.fragments.where(_fragmentCanReceiveCaret),
    ];
    return <String, _PagedFragmentNavigation>{
      for (var i = 0; i < fragments.length; i++)
        _fragmentKey(fragments[i]): _PagedFragmentNavigation(
          previousAnchor: i == 0
              ? null
              : TextSystemPagedCaretAnchor(
                  blockId: fragments[i - 1].blockId,
                  textOffset: fragments[i - 1].visualTextEndOffset,
                ),
          nextAnchor: i >= fragments.length - 1
              ? null
              : TextSystemPagedCaretAnchor(
                  blockId: fragments[i + 1].blockId,
                  textOffset: fragments[i + 1].visualTextStartOffset,
                ),
        ),
    };
  }
}

String _fragmentKey(TextSystemPagedBlockFragment fragment) {
  return '${fragment.blockId}:${fragment.visualTextStartOffset}:${fragment.visualTextEndOffset}:${fragment.continuesFromPreviousPage}:${fragment.continuesOnNextPage}';
}

bool _fragmentCanReceiveSelection(TextSystemPagedBlockFragment fragment) {
  if (fragment.oversized) return false;
  return switch (fragment.blockType) {
    TextSystemBlockType.paragraph ||
    TextSystemBlockType.heading ||
    TextSystemBlockType.listItem ||
    TextSystemBlockType.todo ||
    TextSystemBlockType.quote ||
    TextSystemBlockType.code => true,
    _ => false,
  };
}

bool _fragmentCanReceiveCaret(TextSystemPagedBlockFragment fragment) {
  if (fragment.oversized) return false;
  return switch (fragment.blockType) {
    TextSystemBlockType.paragraph ||
    TextSystemBlockType.heading ||
    TextSystemBlockType.quote ||
    TextSystemBlockType.code => true,
    _ => false,
  };
}

bool _isPageBreakBlock(TextSystemBlock block) {
  return block.type == TextSystemBlockType.divider && block.metadata['kind'] == 'pageBreak';
}

bool _isSectionBreakBlock(TextSystemBlock block) {
  return block.type == TextSystemBlockType.divider && block.metadata['kind'] == 'sectionBreak';
}

bool _isStructuralBreakBlock(TextSystemBlock block) {
  return _isPageBreakBlock(block) || _isSectionBreakBlock(block);
}

bool _blockCanReceiveObjectExitCaret(TextSystemBlock block) {
  return switch (block.type) {
    TextSystemBlockType.paragraph ||
    TextSystemBlockType.heading ||
    TextSystemBlockType.quote ||
    TextSystemBlockType.code => true,
    _ => false,
  };
}

void _commitUserDocumentTransaction(
  TextSystemController textController,
  TextSystemDocument document, {
  required String label,
}) {
  textController.replaceDocument(
    document.copyWith(updatedAt: DateTime.now()),
    label: label,
    origin: TextTransactionOrigin.user,
  );
}

TextSystemPagedCaretAnchor _replaceBlockInUserTransaction(
  TextSystemController textController,
  String blockId,
  TextSystemBlock replacementBlock, {
  required String label,
  bool ensureParagraphAfter = false,
}) {
  final document = textController.document;
  final blocks = document.blocks;
  final index = blocks.indexWhere((candidate) => candidate.id == blockId);
  if (index < 0) {
    return TextSystemPagedCaretAnchor(blockId: blockId, textOffset: 0);
  }

  final nextBlocks = <TextSystemBlock>[
    for (var i = 0; i < blocks.length; i++)
      if (i == index) replacementBlock else blocks[i],
  ];

  var exitIndex = index + 1;
  if (ensureParagraphAfter &&
      (exitIndex >= nextBlocks.length || !_blockCanReceiveObjectExitCaret(nextBlocks[exitIndex]))) {
    final paragraph = TextSystemBlock.paragraph(
      id: 'paragraph_after_object_${DateTime.now().microsecondsSinceEpoch}',
      text: '',
    );
    nextBlocks.insert(exitIndex, paragraph);
  }

  _commitUserDocumentTransaction(
    textController,
    document.copyWith(blocks: nextBlocks),
    label: label,
  );

  if (ensureParagraphAfter && exitIndex < nextBlocks.length) {
    return TextSystemPagedCaretAnchor(blockId: nextBlocks[exitIndex].id, textOffset: 0);
  }
  return TextSystemPagedCaretAnchor(blockId: replacementBlock.id, textOffset: 0);
}

TextSystemPagedCaretAnchor _deleteBlockInUserTransaction(
  TextSystemController textController,
  String blockId, {
  required String label,
}) {
  final document = textController.document;
  final blocks = document.blocks;
  final index = blocks.indexWhere((candidate) => candidate.id == blockId);
  if (index < 0) {
    final fallback = blocks.isNotEmpty ? blocks.last : TextSystemBlock.paragraph(id: 'paragraph_${DateTime.now().microsecondsSinceEpoch}', text: '');
    return TextSystemPagedCaretAnchor(blockId: fallback.id, textOffset: fallback.text.length);
  }

  final nextBlocks = <TextSystemBlock>[
    for (var i = 0; i < blocks.length; i++)
      if (i != index) blocks[i],
  ];
  if (nextBlocks.isEmpty) {
    nextBlocks.add(
      TextSystemBlock.paragraph(
        id: 'paragraph_${DateTime.now().microsecondsSinceEpoch}',
        text: '',
      ),
    );
  }

  final nextIndex = index < nextBlocks.length ? index : nextBlocks.length - 1;
  final nextBlock = nextBlocks[nextIndex];
  _commitUserDocumentTransaction(
    textController,
    document.copyWith(blocks: nextBlocks),
    label: label,
  );

  return TextSystemPagedCaretAnchor(
    blockId: nextBlock.id,
    textOffset: nextIndex < index ? nextBlock.text.length : 0,
  );
}


bool _isDocumentObjectBlock(TextSystemBlock block) {
  return _isAcademicObjectBlock(block) || _isEquationBlock(block);
}

TextSystemPagedCaretAnchor _ensureCaretBeforeDocumentObject(
  TextSystemController textController,
  String blockId, {
  required String label,
}) {
  final document = textController.document;
  final blocks = document.blocks;
  final index = blocks.indexWhere((candidate) => candidate.id == blockId);

  if (index < 0) {
    final fallback = blocks.isNotEmpty
        ? blocks.first
        : TextSystemBlock.paragraph(
            id: 'paragraph_${DateTime.now().microsecondsSinceEpoch}',
            text: '',
          );
    if (blocks.isEmpty) {
      textController.replaceDocument(
        document.copyWith(blocks: [fallback], updatedAt: DateTime.now()),
        label: label,
        origin: TextTransactionOrigin.user,
      );
    }
    return TextSystemPagedCaretAnchor(blockId: fallback.id, textOffset: 0);
  }

  final previousIndex = index - 1;
  if (previousIndex >= 0 && _blockCanReceiveObjectExitCaret(blocks[previousIndex])) {
    final previous = blocks[previousIndex];
    // A caret landing *before* an object should be a real insertion point
    // immediately before that object. Reusing a non-empty paragraph above the
    // object places the caret at the end of existing content, which feels like
    // jumping to the previous paragraph rather than opening space before the
    // object. Only reuse an already-empty landing paragraph; otherwise insert
    // a fresh empty paragraph directly before the object.
    if (previous.text.trim().isEmpty) {
      return TextSystemPagedCaretAnchor(blockId: previous.id, textOffset: previous.text.length);
    }
  }

  final paragraph = TextSystemBlock.paragraph(
    id: 'paragraph_before_object_${DateTime.now().microsecondsSinceEpoch}',
    text: '',
  );
  final nextBlocks = <TextSystemBlock>[
    for (var i = 0; i < blocks.length; i++) ...[
      if (i == index) paragraph,
      blocks[i],
    ],
  ];
  textController.replaceDocument(
    document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
    label: label,
    origin: TextTransactionOrigin.user,
  );
  return TextSystemPagedCaretAnchor(blockId: paragraph.id, textOffset: 0);
}

TextSystemPagedCaretAnchor _ensureCaretAfterDocumentObject(
  TextSystemController textController,
  String blockId, {
  required String label,
}) {
  final document = textController.document;
  final blocks = document.blocks;
  final index = blocks.indexWhere((candidate) => candidate.id == blockId);

  if (index < 0) {
    final fallback = blocks.isNotEmpty
        ? blocks.last
        : TextSystemBlock.paragraph(
            id: 'paragraph_${DateTime.now().microsecondsSinceEpoch}',
            text: '',
          );
    if (blocks.isEmpty) {
      textController.replaceDocument(
        document.copyWith(blocks: [fallback], updatedAt: DateTime.now()),
        label: label,
        origin: TextTransactionOrigin.user,
      );
    }
    return TextSystemPagedCaretAnchor(blockId: fallback.id, textOffset: fallback.text.length);
  }

  final nextIndex = index + 1;
  if (nextIndex < blocks.length && _blockCanReceiveObjectExitCaret(blocks[nextIndex])) {
    return TextSystemPagedCaretAnchor(blockId: blocks[nextIndex].id, textOffset: 0);
  }

  final paragraph = TextSystemBlock.paragraph(
    id: 'paragraph_after_object_${DateTime.now().microsecondsSinceEpoch}',
    text: '',
  );
  final nextBlocks = <TextSystemBlock>[
    for (var i = 0; i < blocks.length; i++) ...[
      blocks[i],
      if (i == index) paragraph,
    ],
  ];
  textController.replaceDocument(
    document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
    label: label,
    origin: TextTransactionOrigin.user,
  );
  return TextSystemPagedCaretAnchor(blockId: paragraph.id, textOffset: 0);
}

bool _isFootnoteBlock(TextSystemBlock block) {
  return block.type == TextSystemBlockType.custom && block.metadata['kind'] == 'footnote';
}

bool _isFootnoteReferenceMark(TextMark mark) {
  return mark.kind == TextMarkKind.link && mark.attributes['role'] == 'footnoteReference';
}

class _PagedBlockSurfaceBanner extends StatelessWidget {
  const _PagedBlockSurfaceBanner({
    required this.layout,
    required this.pageSetup,
    required this.pageFurniture,
    required this.styleSheet,
    required this.editable,
    required this.headerFooterEditMode,
    required this.documentSelectionMode,
    required this.activeBlock,
    required this.onToggleDocumentSelectionMode,
    required this.onToggleHeaderFooterEditMode,
    required this.onUndo,
    required this.onRedo,
    required this.onBlockStyleChanged,
    required this.onInsertPageBreak,
    required this.onInsertSectionBreak,
    required this.onInsertFootnote,
    required this.onInsertEmbeddedTodo,
    required this.onReferenceAction,
    required this.citationSettings,
    required this.onCitationStyleChanged,
    required this.onCitationInlineModeChanged,
    required this.onToggleBold,
    required this.onToggleItalic,
    required this.onToggleUnderline,
    required this.onToggleCode,
    required this.onToggleHighlight,
    required this.onCopySelection,
    required this.onCutSelection,
    required this.onPastePlainText,
    required this.boldActive,
    required this.italicActive,
    required this.underlineActive,
    required this.codeActive,
    required this.highlightActive,
    required this.boldEnabled,
    required this.italicEnabled,
    required this.underlineEnabled,
    required this.codeEnabled,
    required this.highlightEnabled,
    required this.selectionStatusLabel,
    required this.selectedObjectStatusLabel,
    required this.activeTableContext,
    required this.onDuplicateSelectedObject,
    required this.onMoveSelectedObjectUp,
    required this.onMoveSelectedObjectDown,
    required this.onDeleteSelectedObject,
  });

  final TextSystemPagedBlockLayout layout;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final TextSystemDocumentStyleSheet styleSheet;
  final bool editable;
  final bool headerFooterEditMode;
  final bool documentSelectionMode;
  final TextSystemBlock? activeBlock;
  final VoidCallback? onToggleDocumentSelectionMode;
  final VoidCallback? onToggleHeaderFooterEditMode;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final ValueChanged<_PagedBlockToolbarStyle>? onBlockStyleChanged;
  final VoidCallback? onInsertPageBreak;
  final VoidCallback? onInsertSectionBreak;
  final VoidCallback? onInsertFootnote;
  final VoidCallback? onInsertEmbeddedTodo;
  final ValueChanged<TextSystemReferenceActionType>? onReferenceAction;
  final TextSystemCitationSettings citationSettings;
  final ValueChanged<TextSystemCitationStyle>? onCitationStyleChanged;
  final ValueChanged<TextSystemCitationInlineMode>? onCitationInlineModeChanged;
  final VoidCallback? onToggleBold;
  final VoidCallback? onToggleItalic;
  final VoidCallback? onToggleUnderline;
  final VoidCallback? onToggleCode;
  final VoidCallback? onToggleHighlight;
  final VoidCallback? onCopySelection;
  final VoidCallback? onCutSelection;
  final VoidCallback? onPastePlainText;
  final bool boldActive;
  final bool italicActive;
  final bool underlineActive;
  final bool codeActive;
  final bool highlightActive;
  final bool boldEnabled;
  final bool italicEnabled;
  final bool underlineEnabled;
  final bool codeEnabled;
  final bool highlightEnabled;
  final String selectionStatusLabel;
  final String selectedObjectStatusLabel;
  final _ActiveTableEditingContext? activeTableContext;
  final VoidCallback? onDuplicateSelectedObject;
  final VoidCallback? onMoveSelectedObjectUp;
  final VoidCallback? onMoveSelectedObjectDown;
  final VoidCallback? onDeleteSelectedObject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeStyle = activeBlock == null ? null : _PagedBlockToolbarStyle.fromBlock(activeBlock!, styleSheet);
    final typography = pageSetup.typography;
    final tableContext = activeTableContext;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 940),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_stories_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Real pages experimental · ${layout.label}',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          editable
                              ? 'Phase 14M surface: structural real-page editing with build-safe selection state, block-local inline marks, and clipboard commands.'
                              : 'Real-page preview: the same TextSystemDocument is laid out as block fragments inside ${pageSetup.physicalSizeLabel} pages.',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (layout.oversizedFragmentCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${layout.oversizedFragmentCount} fragment${layout.oversizedFragmentCount == 1 ? '' : 's'} need stronger fragmentation support.',
                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ToolbarCommandButton(
                    icon: Icons.undo_rounded,
                    label: 'Undo',
                    tooltip: onUndo == null ? 'Nothing to undo' : 'Undo last document edit',
                    enabled: onUndo != null,
                    onPressed: onUndo,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.redo_rounded,
                    label: 'Redo',
                    tooltip: onRedo == null ? 'Nothing to redo' : 'Redo last undone edit',
                    enabled: onRedo != null,
                    onPressed: onRedo,
                  ),
                  const SizedBox(width: 8),
                  Text('Style', style: theme.textTheme.labelLarge),
                  _PagedBlockStyleToolbarButton(
                    activeStyle: activeStyle,
                    styleSheet: styleSheet,
                    enabled: activeBlock != null && onBlockStyleChanged != null,
                    onSelected: onBlockStyleChanged,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.vertical_split_rounded,
                    label: 'Page break',
                    tooltip: 'Insert a structural page break at the current caret position',
                    enabled: activeBlock != null && onInsertPageBreak != null,
                    onPressed: onInsertPageBreak,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.splitscreen_rounded,
                    label: 'Section',
                    tooltip: 'Insert a next-page section break and restart page numbering',
                    enabled: activeBlock != null && onInsertSectionBreak != null,
                    onPressed: onInsertSectionBreak,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.format_list_numbered_rounded,
                    label: 'Footnote',
                    tooltip: 'Insert a footnote anchor at the current caret position',
                    enabled: activeBlock != null && onInsertFootnote != null,
                    onPressed: onInsertFootnote,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.add_task_rounded,
                    label: 'App TODO',
                    tooltip: onInsertEmbeddedTodo == null
                        ? 'Open the writer from the app/library route to create synced TODOs'
                        : 'Insert a TODO block that is synced with the app TODO system',
                    enabled: activeBlock != null && onInsertEmbeddedTodo != null,
                    onPressed: onInsertEmbeddedTodo,
                  ),
                  _PagedReferenceActionButton(onReferenceAction: onReferenceAction),
                  _PagedCitationSettingsButton(
                    settings: citationSettings,
                    onStyleChanged: onCitationStyleChanged,
                    onInlineModeChanged: onCitationInlineModeChanged,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.border_top_rounded,
                    label: 'H/F edit',
                    tooltip: headerFooterEditMode
                        ? 'Exit header/footer editing mode'
                        : 'Enter header/footer editing mode',
                    enabled: onToggleHeaderFooterEditMode != null,
                    selected: headerFooterEditMode,
                    onPressed: onToggleHeaderFooterEditMode,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.select_all_rounded,
                    label: 'Range select',
                    tooltip: documentSelectionMode
                        ? 'Exit document range selection mode'
                        : 'Enter document range selection mode to drag-select across headings, paragraphs, lists, and pages',
                    enabled: onToggleDocumentSelectionMode != null,
                    selected: documentSelectionMode,
                    onPressed: onToggleDocumentSelectionMode,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.format_bold_rounded,
                    label: 'Bold',
                    tooltip: boldEnabled
                        ? 'Toggle bold for the active selection'
                        : 'Select text inside one editable block to use Bold',
                    enabled: boldEnabled,
                    selected: boldActive,
                    onPressed: onToggleBold,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.format_italic_rounded,
                    label: 'Italic',
                    tooltip: italicEnabled
                        ? 'Toggle italic for the active selection'
                        : 'Select text inside one editable block to use Italic',
                    enabled: italicEnabled,
                    selected: italicActive,
                    onPressed: onToggleItalic,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.format_underlined_rounded,
                    label: 'Underline',
                    tooltip: underlineEnabled
                        ? 'Toggle underline for the active selection'
                        : 'Select text inside one editable block to use Underline',
                    enabled: underlineEnabled,
                    selected: underlineActive,
                    onPressed: onToggleUnderline,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.code_rounded,
                    label: 'Code',
                    tooltip: codeEnabled
                        ? 'Toggle inline code for the active selection'
                        : 'Select text inside one editable block to use inline Code',
                    enabled: codeEnabled,
                    selected: codeActive,
                    onPressed: onToggleCode,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.border_color_rounded,
                    label: 'Highlight',
                    tooltip: highlightEnabled
                        ? 'Toggle highlight for the active selection'
                        : 'Select text inside one editable block to use Highlight',
                    enabled: highlightEnabled,
                    selected: highlightActive,
                    onPressed: onToggleHighlight,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    tooltip: onCopySelection == null
                        ? 'Select text inside one block to copy'
                        : 'Copy selected text as plain text',
                    enabled: onCopySelection != null,
                    onPressed: onCopySelection,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.content_cut_rounded,
                    label: 'Cut',
                    tooltip: onCutSelection == null
                        ? 'Select text inside one editable block to cut'
                        : 'Cut selected text as plain text',
                    enabled: onCutSelection != null,
                    onPressed: onCutSelection,
                  ),
                  _ToolbarCommandButton(
                    icon: Icons.content_paste_rounded,
                    label: 'Paste',
                    tooltip: onPastePlainText == null
                        ? 'Click inside an editable block to paste'
                        : 'Paste plain text at the active selection/caret',
                    enabled: onPastePlainText != null,
                    onPressed: onPastePlainText,
                  ),
                  _TypographyInfoChip(
                    icon: Icons.select_all_rounded,
                    label: selectionStatusLabel,
                    width: 178,
                  ),
                  const SizedBox(width: 8),
                  _TypographyInfoChip(
                    icon: Icons.font_download_outlined,
                    label: typography.fontFamily ?? 'System font',
                  ),
                  _TypographyInfoChip(
                    icon: Icons.format_size_rounded,
                    label: '${typography.bodyFontSizePt.toStringAsFixed(1)} pt',
                  ),
                  _TypographyInfoChip(
                    icon: Icons.format_line_spacing_rounded,
                    label: '${typography.lineSpacing.toStringAsFixed(2)} line',
                  ),
                  _TypographyInfoChip(
                    icon: Icons.view_agenda_outlined,
                    label: pageSetup.physicalSizeLabel,
                  ),
                  _TypographyInfoChip(
                    icon: Icons.web_asset_outlined,
                    label: pageFurniture.shortLabel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _PagedBlockStyleToolbarButton extends StatelessWidget {
  const _PagedBlockStyleToolbarButton({
    required this.activeStyle,
    required this.styleSheet,
    required this.enabled,
    required this.onSelected,
  });

  final _PagedBlockToolbarStyle? activeStyle;
  final TextSystemDocumentStyleSheet styleSheet;
  final bool enabled;
  final ValueChanged<_PagedBlockToolbarStyle>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = activeStyle?.label(styleSheet) ?? 'Select style';

    return PopupMenuButton<_PagedBlockToolbarStyle>(
      enabled: enabled,
      tooltip: 'Apply paragraph style',
      onSelected: (style) => onSelected?.call(style),
      itemBuilder: (context) {
        return _PagedBlockToolbarStyle.optionsFor(styleSheet)
            .map(
              (style) => PopupMenuItem<_PagedBlockToolbarStyle>(
                value: style,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      child: activeStyle == style
                          ? Icon(Icons.check_rounded, size: 18, color: colorScheme.primary)
                          : null,
                    ),
                    Text(style.label(styleSheet)),
                  ],
                ),
              ),
            )
            .toList();
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.surface.withValues(alpha: 0.78)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_drop_down_rounded, size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}



class _PagedCitationSettingsButton extends StatelessWidget {
  const _PagedCitationSettingsButton({
    required this.settings,
    required this.onStyleChanged,
    required this.onInlineModeChanged,
  });

  final TextSystemCitationSettings settings;
  final ValueChanged<TextSystemCitationStyle>? onStyleChanged;
  final ValueChanged<TextSystemCitationInlineMode>? onInlineModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onStyleChanged != null || onInlineModeChanged != null;

    return PopupMenuButton<Object>(
      enabled: enabled,
      tooltip: 'Citation style and inline citation mode',
      onSelected: (value) {
        if (value is TextSystemCitationStyle) onStyleChanged?.call(value);
        if (value is TextSystemCitationInlineMode) onInlineModeChanged?.call(value);
      },
      itemBuilder: (context) => <PopupMenuEntry<Object>>[
        const PopupMenuItem<Object>(
          enabled: false,
          child: Text('Reference style'),
        ),
        for (final style in TextSystemCitationStyle.values)
          PopupMenuItem<Object>(
            value: style,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: settings.style == style ? const Icon(Icons.check_rounded, size: 18) : null,
                ),
                Text(style.label),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          enabled: false,
          child: Text('Inline citation mode'),
        ),
        for (final mode in TextSystemCitationInlineMode.values)
          PopupMenuItem<Object>(
            value: mode,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: settings.inlineMode == mode ? const Icon(Icons.check_rounded, size: 18) : null,
                ),
                Text(mode.label),
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.surface.withValues(alpha: 0.78)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 17, color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Cite: ${settings.style.label}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded, size: 18, color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagedReferenceActionButton extends StatelessWidget {
  const _PagedReferenceActionButton({required this.onReferenceAction});

  final ValueChanged<TextSystemReferenceActionType>? onReferenceAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onReferenceAction != null;

    return PopupMenuButton<TextSystemReferenceActionType>(
      enabled: enabled,
      tooltip: enabled
          ? 'Create a citation at the caret or a source/link from selected text'
          : 'Place the caret inside a block to add a citation, or select text to create a link',
      onSelected: (type) => onReferenceAction?.call(type),
      itemBuilder: (context) => <PopupMenuEntry<TextSystemReferenceActionType>>[
        for (final type in TextSystemReferenceActionType.values)
          PopupMenuItem<TextSystemReferenceActionType>(
            value: type,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconForReferenceActionType(type), size: 18),
                const SizedBox(width: 10),
                Text(type.verbLabel),
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.surface.withValues(alpha: 0.78)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_outlined, size: 17, color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Reference',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded, size: 18, color: enabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconForReferenceActionType(TextSystemReferenceActionType type) {
  return switch (type) {
    TextSystemReferenceActionType.citation => Icons.format_quote_rounded,
    TextSystemReferenceActionType.source => Icons.source_outlined,
    TextSystemReferenceActionType.document => Icons.description_outlined,
    TextSystemReferenceActionType.project => Icons.account_tree_outlined,
    TextSystemReferenceActionType.todo => Icons.check_circle_outline_rounded,
    TextSystemReferenceActionType.link => Icons.link_rounded,
  };
}

class _EmbeddedTodoDraft {
  const _EmbeddedTodoDraft({
    required this.title,
    required this.priority,
    this.deadline,
  });

  final String title;
  final String priority;
  final DateTime? deadline;
}

Future<_EmbeddedTodoDraft?> _showEmbeddedTodoDraftDialog({
  required BuildContext context,
  required String initialTitle,
}) async {
  final titleController = TextEditingController(
    text: initialTitle.trim().isEmpty ? 'New TODO' : initialTitle.trim(),
  );
  var priority = 'medium';
  DateTime? deadline;

  final result = await showDialog<_EmbeddedTodoDraft>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final deadlineLabel = deadline == null
              ? 'No deadline'
              : MaterialLocalizations.of(context).formatMediumDate(deadline!);

          return AlertDialog(
            title: const Text('Insert app TODO'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'TODO title',
                      hintText: 'What should be done?',
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      final title = titleController.text.trim();
                      if (title.isEmpty) return;
                      Navigator.of(context).pop(
                        _EmbeddedTodoDraft(
                          title: title,
                          priority: priority,
                          deadline: deadline,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => priority = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.event_outlined, size: 18),
                        label: Text(deadlineLabel),
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: deadline ?? now,
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 8),
                          );
                          if (picked != null) {
                            setDialogState(() => deadline = picked);
                          }
                        },
                      ),
                      if (deadline != null)
                        TextButton.icon(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          label: const Text('Clear'),
                          onPressed: () => setDialogState(() => deadline = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This creates a real app TODO and embeds it as its own document block.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('Create TODO'),
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  Navigator.of(context).pop(
                    _EmbeddedTodoDraft(
                      title: title,
                      priority: priority,
                      deadline: deadline,
                    ),
                  );
                },
              ),
            ],
          );
        },
      );
    },
  );

  titleController.dispose();
  return result;
}

class _ToolbarCommandButton extends StatelessWidget {
  const _ToolbarCommandButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : enabled
            ? colorScheme.onSurface
            : colorScheme.onSurfaceVariant;
    return TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 17, color: foreground.withValues(alpha: enabled ? 1 : 0.62)),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          visualDensity: VisualDensity.compact,
          backgroundColor: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.82)
              : enabled
                  ? colorScheme.surface.withValues(alpha: 0.72)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
          ),
        ),
      );
  }
}

class _TypographyInfoChip extends StatelessWidget {
  const _TypographyInfoChip({
    required this.icon,
    required this.label,
    this.width,
  });

  final IconData icon;
  final String label;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PagedBlockPageView extends StatelessWidget {
  const _PagedBlockPageView({
    required this.textController,
    required this.document,
    required this.page,
    required this.pageCount,
    required this.pageSetup,
    required this.pageFurniture,
    required this.onPageFurnitureChanged,
    required this.headerFooterEditMode,
    required this.headerFooterEditTarget,
    required this.onHeaderFooterEditModeChanged,
    required this.onHeaderFooterEditTargetChanged,
    required this.pageWidth,
    required this.pageHeight,
    required this.margins,
    required this.showMarginGuides,
    required this.showMarginMarkers,
    required this.showMarginAnnotations,
    required this.activeMarginAnnotationId,
    required this.marginAnnotationDraft,
    required this.editable,
    required this.selectedObjectBlockId,
    required this.selectedBlockIds,
    required this.navigation,
    required this.restoreCaretAnchor,
    required this.restoreSelectionAnchor,
    required this.surfaceDocumentSelection,
    required this.documentSelectionMode,
    required this.onSurfaceSelectionPointerDown,
    required this.onSurfaceSelectionPointerMove,
    required this.onSurfaceSelectionPointerEnd,
    required this.onActiveCaretChanged,
    required this.onActiveSelectionChanged,
    required this.onActiveFieldChanged,
    required this.onRequestCaretRestore,
    required this.onRequestSelectionRestore,
    required this.onRestoreSelectionConsumed,
    required this.onBlockSelectionPointerDown,
    required this.onSelectObjectBlock,
    required this.onDuplicateSelectedObject,
    required this.onMoveSelectedObjectUp,
    required this.onMoveSelectedObjectDown,
    required this.onDeleteSelectedObject,
    required this.onActiveTableContextChanged,
    required this.onSelectMarginAnnotation,
    required this.onEditMarginAnnotation,
    required this.onDeleteMarginAnnotation,
    required this.onToggleMarginTodo,
    required this.onToggleMarginCommentResolved,
    required this.onSubmitMarginAnnotationDraft,
    required this.onCancelMarginAnnotationDraft,
    this.onOpenReferenceTarget,
  });

  final TextSystemController textController;
  final TextSystemDocument document;
  final TextSystemPagedBlockPage page;
  final int pageCount;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture>? onPageFurnitureChanged;
  final bool headerFooterEditMode;
  final TextSystemHeaderFooterZoneKind? headerFooterEditTarget;
  final ValueChanged<bool> onHeaderFooterEditModeChanged;
  final ValueChanged<TextSystemHeaderFooterZoneKind> onHeaderFooterEditTargetChanged;
  final double pageWidth;
  final double pageHeight;
  final EdgeInsets margins;
  final bool showMarginGuides;
  final bool showMarginMarkers;
  final bool showMarginAnnotations;
  final String? activeMarginAnnotationId;
  final _MarginAnnotationDraftSession? marginAnnotationDraft;
  final bool editable;
  final String? selectedObjectBlockId;
  final Set<String> selectedBlockIds;
  final Map<String, _PagedFragmentNavigation> navigation;
  final TextSystemPagedCaretAnchor? restoreCaretAnchor;
  final TextSystemPagedSelectionAnchor? restoreSelectionAnchor;
  final TextSystemPagedDocumentSelection? surfaceDocumentSelection;
  final bool documentSelectionMode;
  final void Function(TextSystemPagedBlockPage page, Offset localPosition, EdgeInsets margins, double pageHeight) onSurfaceSelectionPointerDown;
  final void Function(TextSystemPagedBlockPage page, Offset localPosition, EdgeInsets margins, double pageHeight) onSurfaceSelectionPointerMove;
  final VoidCallback onSurfaceSelectionPointerEnd;
  final ValueChanged<TextSystemPagedCaretAnchor> onActiveCaretChanged;
  final ValueChanged<TextSystemPagedSelectionAnchor> onActiveSelectionChanged;
  final ValueChanged<_PagedEditableBlockFieldState?> onActiveFieldChanged;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRequestSelectionRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRestoreSelectionConsumed;
  final void Function(String blockId, PointerDownEvent event) onBlockSelectionPointerDown;
  final ValueChanged<String> onSelectObjectBlock;
  final VoidCallback onDuplicateSelectedObject;
  final VoidCallback onMoveSelectedObjectUp;
  final VoidCallback onMoveSelectedObjectDown;
  final VoidCallback onDeleteSelectedObject;
  final ValueChanged<_ActiveTableEditingContext?> onActiveTableContextChanged;
  final ValueChanged<_MarginAnnotationData> onSelectMarginAnnotation;
  final ValueChanged<_MarginAnnotationData> onEditMarginAnnotation;
  final ValueChanged<String> onDeleteMarginAnnotation;
  final ValueChanged<String> onToggleMarginTodo;
  final ValueChanged<String> onToggleMarginCommentResolved;
  final void Function(_MarginAnnotationDraftSession draft, String text, bool checked) onSubmitMarginAnnotationDraft;
  final ValueChanged<String> onCancelMarginAnnotationDraft;
  final ValueChanged<TextSystemInlineReferenceMark>? onOpenReferenceTarget;

  String _sectionTitleForPage() {
    final fragments = page.fragments;
    if (fragments.isEmpty) return document.title;

    final firstBlockIndex = fragments
        .map((fragment) => fragment.blockIndex)
        .fold<int>(fragments.first.blockIndex, math.min);

    for (var i = firstBlockIndex; i >= 0; i--) {
      final block = document.blocks[i];
      if (block.type == TextSystemBlockType.heading && block.text.trim().isNotEmpty) {
        return block.text.trim();
      }
    }

    return document.title.trim().isNotEmpty ? document.title.trim() : 'Section';
  }

  List<_PageMarginMarkerData> _marginMarkersForPage() {
    final markers = <_PageMarginMarkerData>[];
    final seen = <String>{};

    for (final fragment in page.fragments) {
      final block = document.blockById(fragment.blockId);
      if (block == null) continue;
      final markerTop = margins.top + fragment.rect.top;

      if (TextSystemEmbeddedTodoMetadata.isEmbeddedTodoBlock(block) && seen.add('todo:${block.id}')) {
        final metadata = TextSystemEmbeddedTodoMetadata.fromBlock(block);
        final dueLabel = metadata.deadline == null
            ? null
            : metadata.deadline!.toLocal().toIso8601String().split('T').first;
        final detail = <String>[
          if (metadata.priority.trim().isNotEmpty) metadata.priority.toUpperCase(),
          if (dueLabel != null) 'Due $dueLabel',
        ].join(' · ');
        markers.add(
          _PageMarginMarkerData(
            key: 'todo:${block.id}',
            top: markerTop,
            type: _PageMarginMarkerType.todo,
            label: 'TODO',
            tooltip: detail.isEmpty ? 'Synced app TODO' : 'Synced app TODO · $detail',
          ),
        );
      }

      final fragmentStart = fragment.visualTextStartOffset.clamp(0, block.text.length).toInt();
      final fragmentEnd = fragment.visualTextEndOffset.clamp(fragmentStart, block.text.length).toInt();
      final fragmentRange = TextSystemRange(fragmentStart, fragmentEnd);
      if (!fragmentRange.isCollapsed) {
        for (final mark in block.marks) {
          if (mark.kind != TextMarkKind.link || !mark.range.overlaps(fragmentRange)) continue;
          if (_isFootnoteReferenceMark(mark)) {
            if (seen.add('footnote:${block.id}:${mark.range.start}')) {
              markers.add(
                _PageMarginMarkerData(
                  key: 'footnote:${block.id}:${mark.range.start}',
                  top: markerTop,
                  type: _PageMarginMarkerType.footnote,
                  label: 'Note',
                  tooltip: 'Footnote anchor',
                ),
              );
            }
            continue;
          }

          final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
          if (inlineReference == null) continue;
          final isCitation = inlineReference.isCitation;
          final markerKey = '${isCitation ? 'citation' : 'reference'}:${inlineReference.targetId}:${block.id}:${mark.range.start}';
          if (!seen.add(markerKey)) continue;
          markers.add(
            _PageMarginMarkerData(
              key: markerKey,
              top: markerTop,
              type: isCitation ? _PageMarginMarkerType.citation : _PageMarginMarkerType.reference,
              label: isCitation ? 'Cite' : 'Link',
              tooltip: isCitation
                  ? 'Citation: ${inlineReference.label}'
                  : '${inlineReference.kind.label}: ${inlineReference.label}',
            ),
          );
        }
      }
    }

    markers.sort((a, b) => a.top.compareTo(b.top));
    return markers;
  }

  List<_MarginAnnotationData> _marginAnnotationsForPage() {
    final annotations = _marginAnnotationsFromDocument(document);
    if (annotations.isEmpty) return const <_MarginAnnotationData>[];

    final seen = <String>{};
    final pageBlockIds = <String>{for (final fragment in page.fragments) fragment.blockId};
    final result = <_MarginAnnotationData>[];
    for (final annotation in annotations) {
      if (!pageBlockIds.contains(annotation.blockId)) continue;
      if (seen.add(annotation.id)) result.add(annotation);
    }
    return result;
  }

  _MarginAnnotationDraftSession? _marginAnnotationDraftForPage() {
    final draft = marginAnnotationDraft;
    if (draft == null) return null;
    final pageBlockIds = <String>{for (final fragment in page.fragments) fragment.blockId};
    return pageBlockIds.contains(draft.blockId) ? draft : null;
  }

  double _topForMarginAnnotationDraft(_MarginAnnotationDraftSession draft) {
    for (final fragment in page.fragments) {
      if (fragment.blockId != draft.blockId) continue;
      if (fragment.containsTextOffset(draft.textOffset)) {
        return margins.top + fragment.rect.top;
      }
    }
    for (final fragment in page.fragments) {
      if (fragment.blockId == draft.blockId) return margins.top + fragment.rect.top;
    }
    return margins.top;
  }

  double _topForMarginAnnotation(_MarginAnnotationData annotation) {
    for (final fragment in page.fragments) {
      if (fragment.blockId != annotation.blockId) continue;
      if (fragment.containsTextOffset(annotation.textOffset)) {
        return margins.top + fragment.rect.top;
      }
    }
    for (final fragment in page.fragments) {
      if (fragment.blockId == annotation.blockId) return margins.top + fragment.rect.top;
    }
    return margins.top;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dimensionLabel = '${pageSetup.pageWidthMm.toStringAsFixed(0)} × ${pageSetup.pageHeightMm.toStringAsFixed(0)} mm';
    final marginMarkers = showMarginMarkers ? _marginMarkersForPage() : const <_PageMarginMarkerData>[];
    final marginAnnotations = showMarginAnnotations ? _marginAnnotationsForPage() : const <_MarginAnnotationData>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: TextSystemPagedBlockSurface._pageHeaderHeight,
          child: DefaultTextStyle.merge(
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                Text('Page ${page.pageNumber} of $pageCount'),
                Text(pageSetup.shortLabel),
                Text(dimensionLabel),
              ],
            ),
          ),
        ),
        const SizedBox(height: TextSystemPagedBlockSurface._pageHeaderGap),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 24,
                    spreadRadius: 1,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox(
                width: pageWidth,
                height: pageHeight,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) => onSurfaceSelectionPointerDown(page, event.localPosition, margins, pageHeight),
                  onPointerMove: (event) => onSurfaceSelectionPointerMove(page, event.localPosition, margins, pageHeight),
                  onPointerUp: (_) => onSurfaceSelectionPointerEnd(),
                  onPointerCancel: (_) => onSurfaceSelectionPointerEnd(),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                    if (showMarginGuides)
                      Positioned(
                        left: margins.left,
                        top: margins.top,
                        right: margins.right,
                        bottom: margins.bottom,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: colorScheme.primary.withValues(alpha: 0.16),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showMarginMarkers && marginMarkers.isNotEmpty)
                      _PageMarginLayer(
                        pageWidth: pageWidth,
                        margins: margins,
                        markers: marginMarkers,
                      ),
                    for (final fragment in page.fragments)
                  Positioned(
                    key: ValueKey<String>('paged-fragment-${fragment.blockId}-${fragment.visualTextStartOffset}-${fragment.continuesOnNextPage}'),
                    left: margins.left + fragment.rect.left,
                    top: margins.top + fragment.rect.top,
                    width: fragment.rect.width,
                    height: fragment.rect.height,
                    child: IgnorePointer(
                      ignoring: documentSelectionMode,
                      child: _PagedBlockFragmentView(
                        key: ValueKey<String>('paged-block-${fragment.blockId}-${fragment.continuesFromPreviousPage || fragment.continuesOnNextPage ? fragment.visualTextStartOffset : 'whole'}'),
                        textController: textController,
                        block: document.blockById(fragment.blockId),
                        fragment: fragment,
                        pageSetup: pageSetup,
                        editable: editable,
                        selectedObjectBlockId: selectedObjectBlockId,
                        blockRangeSelected: selectedBlockIds.contains(fragment.blockId),
                        navigation: navigation[_fragmentKey(fragment)] ?? const _PagedFragmentNavigation(),
                        restoreCaretAnchor: restoreCaretAnchor,
                        restoreSelectionAnchor: restoreSelectionAnchor,
                        onActiveCaretChanged: onActiveCaretChanged,
                        onActiveSelectionChanged: onActiveSelectionChanged,
                        onActiveFieldChanged: onActiveFieldChanged,
                        onRequestCaretRestore: onRequestCaretRestore,
                        onRequestSelectionRestore: onRequestSelectionRestore,
                        onRestoreSelectionConsumed: onRestoreSelectionConsumed,
                        onBlockSelectionPointerDown: onBlockSelectionPointerDown,
                        onSelectObjectBlock: onSelectObjectBlock,
                        onDuplicateSelectedObject: onDuplicateSelectedObject,
                        onMoveSelectedObjectUp: onMoveSelectedObjectUp,
                        onMoveSelectedObjectDown: onMoveSelectedObjectDown,
                        onDeleteSelectedObject: onDeleteSelectedObject,
                        onActiveTableContextChanged: onActiveTableContextChanged,
                        onOpenReferenceTarget: onOpenReferenceTarget,
                      ),
                    ),
                  ),
                if (surfaceDocumentSelection != null && !surfaceDocumentSelection!.isCollapsed)
                  _PagedCrossBlockSelectionOverlay(
                    document: document,
                    page: page,
                    pageSetup: pageSetup,
                    margins: margins,
                    selection: surfaceDocumentSelection!,
                  ),
                if (documentSelectionMode)
                  Positioned.fill(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) => onSurfaceSelectionPointerDown(page, event.localPosition, margins, pageHeight),
                        onPointerMove: (event) => onSurfaceSelectionPointerMove(page, event.localPosition, margins, pageHeight),
                        onPointerUp: (_) => onSurfaceSelectionPointerEnd(),
                        onPointerCancel: (_) => onSurfaceSelectionPointerEnd(),
                        child: SizedBox.expand(
                          child: ColoredBox(
                            color: Colors.transparent,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: margins.top + 8,
                                  right: margins.right + 8,
                                ),
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.82),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      child: Text(
                                        'Range select',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (page.footnotes.isNotEmpty)
                  _PageFootnotesOverlay(
                    textController: textController,
                    footnotes: page.footnotes,
                    margins: margins,
                    editable: editable,
                  ),
                _PageFurnitureOverlay(
                  documentTitle: document.title,
                  sectionTitle: _sectionTitleForPage(),
                  physicalPageNumber: page.pageNumber,
                  pageNumber: page.displayPageNumber,
                  pageFurniture: pageFurniture,
                  onPageFurnitureChanged: onPageFurnitureChanged,
                  headerFooterEditMode: headerFooterEditMode,
                  headerFooterEditTarget: headerFooterEditTarget,
                  onHeaderFooterEditModeChanged: onHeaderFooterEditModeChanged,
                  onHeaderFooterEditTargetChanged: onHeaderFooterEditTargetChanged,
                  margins: margins,
                ),
                  ],
                  ),
                ),
              ),
            ),
            if (showMarginAnnotations)
              _PageCommentRail(
                pageHeight: pageHeight,
                annotations: marginAnnotations,
                draft: _marginAnnotationDraftForPage(),
                activeAnnotationId: activeMarginAnnotationId,
                topForAnnotation: _topForMarginAnnotation,
                topForDraft: _topForMarginAnnotationDraft,
                editable: editable,
                onSelect: onSelectMarginAnnotation,
                onEdit: onEditMarginAnnotation,
                onDelete: onDeleteMarginAnnotation,
                onToggleTodo: onToggleMarginTodo,
                onToggleResolved: onToggleMarginCommentResolved,
                onSubmitDraft: onSubmitMarginAnnotationDraft,
                onCancelDraft: onCancelMarginAnnotationDraft,
              ),
          ],
        ),
      ],
    );
  }
}



String _academicFootnoteNumber(int value) {
  const superscripts = <String, String>{
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
  };

  return value
      .toString()
      .split('')
      .map((digit) => superscripts[digit] ?? digit)
      .join();
}



const String _marginAnnotationsMetadataKey = 'textSystemMarginAnnotations';

enum _MarginAnnotationType { comment, todo }

@immutable
class _MarginAnnotationData {
  const _MarginAnnotationData({
    required this.id,
    required this.blockId,
    required this.textOffset,
    required this.type,
    required this.text,
    this.checked = false,
    this.resolved = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String blockId;
  final int textOffset;
  final _MarginAnnotationType type;
  final String text;
  final bool checked;
  final bool resolved;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  _MarginAnnotationData copyWith({
    String? id,
    String? blockId,
    int? textOffset,
    _MarginAnnotationType? type,
    String? text,
    bool? checked,
    bool? resolved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return _MarginAnnotationData(
      id: id ?? this.id,
      blockId: blockId ?? this.blockId,
      textOffset: textOffset ?? this.textOffset,
      type: type ?? this.type,
      text: text ?? this.text,
      checked: checked ?? this.checked,
      resolved: resolved ?? this.resolved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory _MarginAnnotationData.fromJson(Map<String, Object?> json) {
    DateTime? parseDate(Object? value) => value is String ? DateTime.tryParse(value) : null;
    final typeName = json['type']?.toString();
    return _MarginAnnotationData(
      id: json['id']?.toString() ?? 'margin-${DateTime.now().microsecondsSinceEpoch}',
      blockId: json['blockId']?.toString() ?? '',
      textOffset: (json['textOffset'] as num?)?.toInt() ?? 0,
      type: typeName == 'todo' ? _MarginAnnotationType.todo : _MarginAnnotationType.comment,
      text: json['text']?.toString() ?? '',
      checked: json['checked'] == true,
      resolved: json['resolved'] == true,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'blockId': blockId,
      'textOffset': textOffset,
      'type': type.name,
      'text': text,
      if (type == _MarginAnnotationType.todo) 'checked': checked,
      if (type == _MarginAnnotationType.comment && resolved) 'resolved': resolved,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

@immutable
class _MarginAnnotationDraftSession {
  const _MarginAnnotationDraftSession({
    required this.id,
    required this.blockId,
    required this.textOffset,
    required this.type,
    this.initialText = '',
    this.checked = false,
    this.createdAt,
  });

  final String id;
  final String blockId;
  final int textOffset;
  final _MarginAnnotationType type;
  final String initialText;
  final bool checked;
  final DateTime? createdAt;
}

List<_MarginAnnotationData> _marginAnnotationsFromDocument(TextSystemDocument document) {
  final raw = document.metadata[_marginAnnotationsMetadataKey];
  if (raw is! List) return const <_MarginAnnotationData>[];
  return raw
      .whereType<Map>()
      .map((item) => _MarginAnnotationData.fromJson(Map<String, Object?>.from(item)))
      .where((item) => item.blockId.trim().isNotEmpty && item.text.trim().isNotEmpty)
      .toList();
}

@immutable
class _MarginAnnotationDraft {
  const _MarginAnnotationDraft({required this.text, this.checked = false});

  final String text;
  final bool checked;
}

Future<_MarginAnnotationDraft?> _showMarginAnnotationDraftDialog({
  required BuildContext context,
  required _MarginAnnotationType type,
  String initialText = '',
  bool initialChecked = false,
  _MarginAnnotationData? existingAnnotation,
}) {
  final textController = TextEditingController(text: initialText);
  var checked = initialChecked;
  return showDialog<_MarginAnnotationDraft>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(type == _MarginAnnotationType.todo ? 'Document TODO' : 'Document comment'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: textController,
                    minLines: type == _MarginAnnotationType.todo ? 1 : 3,
                    maxLines: type == _MarginAnnotationType.todo ? 2 : 6,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: type == _MarginAnnotationType.todo ? 'TODO' : 'Comment',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (type == _MarginAnnotationType.todo) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: checked,
                      onChanged: (value) => setDialogState(() => checked = value ?? false),
                      title: const Text('Completed'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                  if (existingAnnotation != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Attached to this paragraph. The thread appears in the comments rail beside the page.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (existingAnnotation != null)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(const _MarginAnnotationDraft(text: '')),
                  child: const Text('Delete'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _MarginAnnotationDraft(text: textController.text, checked: checked),
                ),
                child: Text(existingAnnotation == null ? 'Add' : 'Save'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(textController.dispose);
}

enum _PageMarginMarkerType {
  todo,
  citation,
  reference,
  footnote,
}

@immutable
class _PageMarginMarkerData {
  const _PageMarginMarkerData({
    required this.key,
    required this.top,
    required this.type,
    required this.label,
    required this.tooltip,
  });

  final String key;
  final double top;
  final _PageMarginMarkerType type;
  final String label;
  final String tooltip;
}


class _PageCommentRail extends StatelessWidget {
  const _PageCommentRail({
    required this.pageHeight,
    required this.annotations,
    required this.draft,
    required this.activeAnnotationId,
    required this.topForAnnotation,
    required this.topForDraft,
    required this.editable,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleTodo,
    required this.onToggleResolved,
    required this.onSubmitDraft,
    required this.onCancelDraft,
  });

  static const double commentRailWidth = 292;
  static const double commentRailGap = 18;

  final double pageHeight;
  final List<_MarginAnnotationData> annotations;
  final _MarginAnnotationDraftSession? draft;
  final String? activeAnnotationId;
  final double Function(_MarginAnnotationData annotation) topForAnnotation;
  final double Function(_MarginAnnotationDraftSession draft) topForDraft;
  final bool editable;
  final ValueChanged<_MarginAnnotationData> onSelect;
  final ValueChanged<_MarginAnnotationData> onEdit;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onToggleTodo;
  final ValueChanged<String> onToggleResolved;
  final void Function(_MarginAnnotationDraftSession draft, String text, bool checked) onSubmitDraft;
  final ValueChanged<String> onCancelDraft;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final railItems = <_PageCommentRailItem>[
      for (final annotation in annotations)
        _PageCommentRailItem.annotation(
          annotation: annotation,
          desiredTop: topForAnnotation(annotation),
        ),
      if (draft != null)
        _PageCommentRailItem.draft(
          draft: draft!,
          desiredTop: topForDraft(draft!),
        ),
    ]..sort((a, b) => a.desiredTop.compareTo(b.desiredTop));

    final placedTopById = <String, double>{};
    var nextAvailableTop = 8.0;
    for (final item in railItems) {
      final desiredTop = (item.desiredTop - 8).clamp(8.0, math.max(8.0, pageHeight - 48.0)).toDouble();
      final placedTop = math.max(desiredTop, nextAvailableTop);
      placedTopById[item.id] = placedTop;
      nextAvailableTop = placedTop + item.estimatedHeight + 12;
    }

    return SizedBox(
      width: commentRailGap + commentRailWidth,
      height: pageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: commentRailGap + commentRailWidth,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.38),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (final item in railItems) ...[
            Positioned(
              left: 0,
              top: (placedTopById[item.id] ?? item.desiredTop) + 22,
              width: commentRailGap + 8,
              height: 1,
              child: IgnorePointer(
                child: ColoredBox(
                  color: (item.annotation?.id == activeAnnotationId
                          ? colorScheme.primary
                          : colorScheme.outlineVariant)
                      .withValues(alpha: item.annotation?.id == activeAnnotationId ? 0.78 : 0.72),
                ),
              ),
            ),
            Positioned(
              key: ValueKey<String>('comment-rail-item-${item.id}'),
              left: commentRailGap,
              top: placedTopById[item.id] ?? item.desiredTop,
              width: commentRailWidth,
              child: item.draft == null
                  ? _GoogleDocsCommentCard(
                      annotation: item.annotation!,
                      selected: item.annotation!.id == activeAnnotationId,
                      editable: editable,
                      onSelect: () => onSelect(item.annotation!),
                      onEdit: () => onEdit(item.annotation!),
                      onDelete: () => onDelete(item.annotation!.id),
                      onToggleTodo: item.annotation!.type == _MarginAnnotationType.todo
                          ? () => onToggleTodo(item.annotation!.id)
                          : null,
                      onToggleResolved: item.annotation!.type == _MarginAnnotationType.comment
                          ? () => onToggleResolved(item.annotation!.id)
                          : null,
                    )
                  : _GoogleDocsDraftCommentCard(
                      draft: item.draft!,
                      editable: editable,
                      onSubmit: (text, checked) => onSubmitDraft(item.draft!, text, checked),
                      onCancel: () => onCancelDraft(item.draft!.id),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

@immutable
class _PageCommentRailItem {
  const _PageCommentRailItem._({
    required this.id,
    required this.desiredTop,
    required this.estimatedHeight,
    this.annotation,
    this.draft,
  });

  factory _PageCommentRailItem.annotation({
    required _MarginAnnotationData annotation,
    required double desiredTop,
  }) {
    return _PageCommentRailItem._(
      id: annotation.id,
      desiredTop: desiredTop,
      estimatedHeight: annotation.text.length > 140 ? 164 : 132,
      annotation: annotation,
    );
  }

  factory _PageCommentRailItem.draft({
    required _MarginAnnotationDraftSession draft,
    required double desiredTop,
  }) {
    return _PageCommentRailItem._(
      id: draft.id,
      desiredTop: desiredTop,
      estimatedHeight: draft.type == _MarginAnnotationType.todo ? 154 : 172,
      draft: draft,
    );
  }

  final String id;
  final double desiredTop;
  final double estimatedHeight;
  final _MarginAnnotationData? annotation;
  final _MarginAnnotationDraftSession? draft;
}

class _GoogleDocsCommentCard extends StatefulWidget {
  const _GoogleDocsCommentCard({
    required this.annotation,
    required this.selected,
    required this.editable,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    this.onToggleTodo,
    this.onToggleResolved,
  });

  final _MarginAnnotationData annotation;
  final bool selected;
  final bool editable;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onToggleTodo;
  final VoidCallback? onToggleResolved;

  @override
  State<_GoogleDocsCommentCard> createState() => _GoogleDocsCommentCardState();
}

class _GoogleDocsCommentCardState extends State<_GoogleDocsCommentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isTodo = widget.annotation.type == _MarginAnnotationType.todo;
    final resolved = widget.annotation.resolved || widget.annotation.checked;
    final accent = isTodo ? colorScheme.tertiary : colorScheme.primary;
    final title = isTodo ? 'Action item' : 'You';
    final subtitle = widget.annotation.updatedAt == null ? 'now' : 'edited';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: resolved
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.72)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? accent.withValues(alpha: 0.88)
                  : colorScheme.outlineVariant.withValues(alpha: _hovered ? 0.95 : 0.68),
              width: widget.selected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: widget.selected ? 0.18 : (_hovered ? 0.13 : 0.08)),
                blurRadius: widget.selected ? 18 : 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: accent.withValues(alpha: resolved ? 0.14 : 0.20),
                      child: Icon(
                        isTodo ? Icons.task_alt_rounded : Icons.person_outline_rounded,
                        size: 15,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            resolved ? (isTodo ? 'done' : 'resolved') : subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.editable && isTodo)
                      IconButton(
                        tooltip: widget.annotation.checked ? 'Mark open' : 'Mark done',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: widget.onToggleTodo,
                        icon: Icon(widget.annotation.checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                      ),
                    if (widget.editable && !isTodo)
                      IconButton(
                        tooltip: widget.annotation.resolved ? 'Reopen' : 'Resolve',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: widget.onToggleResolved,
                        icon: Icon(widget.annotation.resolved ? Icons.replay_rounded : Icons.check_rounded),
                      ),
                    if (widget.editable)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              widget.onEdit();
                              break;
                            case 'delete':
                              widget.onDelete();
                              break;
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  widget.annotation.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.32,
                    color: resolved
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.74)
                        : colorScheme.onSurface,
                    decoration: resolved && isTodo ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleDocsDraftCommentCard extends StatefulWidget {
  const _GoogleDocsDraftCommentCard({
    required this.draft,
    required this.editable,
    required this.onSubmit,
    required this.onCancel,
  });

  final _MarginAnnotationDraftSession draft;
  final bool editable;
  final void Function(String text, bool checked) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_GoogleDocsDraftCommentCard> createState() => _GoogleDocsDraftCommentCardState();
}

class _GoogleDocsDraftCommentCardState extends State<_GoogleDocsDraftCommentCard> {
  late final TextEditingController _textController;
  late bool _checked;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.draft.initialText);
    _checked = widget.draft.checked;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isTodo = widget.draft.type == _MarginAnnotationType.todo;
    final accent = isTodo ? colorScheme.tertiary : colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.85), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: accent.withValues(alpha: 0.20),
                  child: Icon(isTodo ? Icons.task_alt_rounded : Icons.person_outline_rounded, size: 15, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isTodo ? 'New action item' : 'New comment',
                    style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _textController,
              autofocus: true,
              enabled: widget.editable,
              minLines: isTodo ? 1 : 3,
              maxLines: isTodo ? 2 : 5,
              decoration: InputDecoration(
                isDense: true,
                hintText: isTodo ? 'Add an action item…' : 'Comment…',
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.newline,
            ),
            if (isTodo) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _checked,
                onChanged: widget.editable ? (value) => setState(() => _checked = value ?? false) : null,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Completed'),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: widget.editable
                      ? () => widget.onSubmit(_textController.text, _checked)
                      : null,
                  child: Text(isTodo ? 'Add TODO' : 'Comment'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



@immutable
class _AcademicFigureDraft {
  const _AcademicFigureDraft({
    required this.caption,
    required this.label,
    required this.source,
    required this.altText,
    required this.imagePath,
    this.size = 'medium',
    this.captionPosition = 'below',
  });

  final String caption;
  final String label;
  final String source;
  final String altText;
  final String imagePath;
  final String size;
  final String captionPosition;
}


@immutable
class _AcademicCrossReferenceTarget {
  const _AcademicCrossReferenceTarget({
    required this.blockId,
    required this.kind,
    required this.ordinal,
    required this.caption,
    required this.label,
    required this.numbered,
  });

  final String blockId;
  final String kind;
  final int ordinal;
  final String caption;
  final String label;
  final bool numbered;

  bool get isFigure => kind == 'figure';
  bool get isTable => kind == 'table';
  bool get isEquation => kind == 'equation';
  String get noun => isTable ? 'Table' : isEquation ? 'Equation' : 'Figure';
  String get title => '$noun $ordinal';
  String get visibleText => isEquation && numbered ? 'Equation ($ordinal)' : title;
  String get exportLabel => label.trim();
  bool get hasExportLabel => exportLabel.isNotEmpty;
  String get subtitle {
    final bits = <String>[];
    if (caption.trim().isNotEmpty) bits.add(caption.trim());
    if (label.trim().isNotEmpty) {
      bits.add(label.trim());
    } else {
      bits.add('missing label');
    }
    if (isEquation && !numbered) bits.add('unnumbered');
    return bits.join(' · ');
  }

  TextSystemReferenceTargetKind get referenceKind {
    if (isFigure) return TextSystemReferenceTargetKind.figure;
    if (isTable) return TextSystemReferenceTargetKind.table;
    return TextSystemReferenceTargetKind.link;
  }
}

List<_AcademicCrossReferenceTarget> _academicCrossReferenceTargets(TextSystemDocument document) {
  final targets = <_AcademicCrossReferenceTarget>[];
  var figureOrdinal = 0;
  var tableOrdinal = 0;
  var equationOrdinal = 0;

  for (final block in document.blocks) {
    if (_isAcademicObjectBlock(block)) {
      final kind = _academicObjectKind(block);
      final ordinal = kind == 'table' ? ++tableOrdinal : ++figureOrdinal;
      targets.add(
        _AcademicCrossReferenceTarget(
          blockId: block.id,
          kind: kind,
          ordinal: ordinal,
          caption: _academicCaptionForBlock(block),
          label: _academicLabelForBlock(block),
          numbered: true,
        ),
      );
    } else if (_isEquationBlock(block)) {
      equationOrdinal += 1;
      final numbered = _equationIsNumbered(block);
      targets.add(
        _AcademicCrossReferenceTarget(
          blockId: block.id,
          kind: 'equation',
          ordinal: equationOrdinal,
          caption: _equationLatexForBlock(block),
          label: numbered ? _equationLabelForBlock(block) : '',
          numbered: numbered,
        ),
      );
    }
  }

  return targets;
}

Future<_AcademicCrossReferenceTarget?> _showAcademicCrossReferencePickerDialog({
  required BuildContext context,
  required List<_AcademicCrossReferenceTarget> targets,
}) {
  return showDialog<_AcademicCrossReferenceTarget>(
    context: context,
    builder: (context) => _AcademicCrossReferencePickerDialog(targets: targets),
  );
}

class _AcademicCrossReferencePickerDialog extends StatefulWidget {
  const _AcademicCrossReferencePickerDialog({required this.targets});

  final List<_AcademicCrossReferenceTarget> targets;

  @override
  State<_AcademicCrossReferencePickerDialog> createState() => _AcademicCrossReferencePickerDialogState();
}

enum _AcademicCrossReferenceFilter { all, figures, tables, equations }

class _AcademicCrossReferencePickerDialogState extends State<_AcademicCrossReferencePickerDialog> {
  _AcademicCrossReferenceFilter _filter = _AcademicCrossReferenceFilter.all;

  List<_AcademicCrossReferenceTarget> get _visibleTargets {
    return switch (_filter) {
      _AcademicCrossReferenceFilter.all => widget.targets,
      _AcademicCrossReferenceFilter.figures => widget.targets.where((target) => target.isFigure).toList(growable: false),
      _AcademicCrossReferenceFilter.tables => widget.targets.where((target) => target.isTable).toList(growable: false),
      _AcademicCrossReferenceFilter.equations => widget.targets.where((target) => target.isEquation).toList(growable: false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visible = _visibleTargets;

    return AlertDialog(
      title: const Text('Insert cross-reference'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a figure, table, or numbered equation to reference from the text.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CrossReferenceFilterChip(
                  label: 'All',
                  selected: _filter == _AcademicCrossReferenceFilter.all,
                  onSelected: () => setState(() => _filter = _AcademicCrossReferenceFilter.all),
                ),
                _CrossReferenceFilterChip(
                  label: 'Figures',
                  selected: _filter == _AcademicCrossReferenceFilter.figures,
                  onSelected: () => setState(() => _filter = _AcademicCrossReferenceFilter.figures),
                ),
                _CrossReferenceFilterChip(
                  label: 'Tables',
                  selected: _filter == _AcademicCrossReferenceFilter.tables,
                  onSelected: () => setState(() => _filter = _AcademicCrossReferenceFilter.tables),
                ),
                _CrossReferenceFilterChip(
                  label: 'Equations',
                  selected: _filter == _AcademicCrossReferenceFilter.equations,
                  onSelected: () => setState(() => _filter = _AcademicCrossReferenceFilter.equations),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'No objects in this category.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final target = visible[index];
                          return _AcademicCrossReferenceTile(
                            target: target,
                            onSelected: () => Navigator.of(context).pop(target),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _CrossReferenceFilterChip extends StatelessWidget {
  const _CrossReferenceFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AcademicCrossReferenceTile extends StatelessWidget {
  const _AcademicCrossReferenceTile({
    required this.target,
    required this.onSelected,
  });

  final _AcademicCrossReferenceTarget target;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = target.isTable
        ? Icons.table_chart_outlined
        : target.isEquation
            ? Icons.functions_rounded
            : Icons.image_outlined;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          target.visibleText,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (!target.hasExportLabel) ...[
                          const SizedBox(width: 8),
                          Tooltip(
                            message: target.isEquation && !target.numbered
                                ? 'Unnumbered equations cannot export as LaTeX \\ref targets yet.'
                                : 'Add a label for export-safe references.',
                            child: Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.tertiary),
                          ),
                        ],
                      ],
                    ),
                    if (target.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        target.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_return_rounded, size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _AcademicTableDraft {
  const _AcademicTableDraft({
    required this.caption,
    required this.label,
    required this.cells,
    required this.note,
    this.headerRows = 1,
    this.captionPosition = 'above',
  });

  final String caption;
  final String label;
  final List<List<String>> cells;
  final String note;
  final int headerRows;
  final String captionPosition;
}

@immutable
class _AcademicEquationDraft {
  const _AcademicEquationDraft({
    required this.latex,
    required this.label,
    required this.note,
    this.numbered = false,
  });

  final String latex;
  final String label;
  final String note;
  final bool numbered;
}

bool _isAcademicObjectBlock(TextSystemBlock block) {
  final kind = block.metadata['kind'];
  return block.type == TextSystemBlockType.custom && (kind == 'figure' || kind == 'table');
}

bool _isEquationBlock(TextSystemBlock block) {
  return block.type == TextSystemBlockType.custom && block.metadata['kind'] == 'equation';
}

String _equationLatexForBlock(TextSystemBlock block) {
  final latex = block.metadata['latex'];
  if (latex is String && latex.trim().isNotEmpty) return latex.trim();
  return block.text.trim();
}

String _equationLabelForBlock(TextSystemBlock block) {
  final label = block.metadata['label'];
  if (label is String) return label.trim();
  return '';
}

String _equationNoteForBlock(TextSystemBlock block) {
  final note = block.metadata['note'];
  if (note is String) return note.trim();
  return '';
}

bool _equationIsNumbered(TextSystemBlock block) {
  final presentation = block.metadata['presentation'] ?? block.metadata['equationPresentation'];
  return presentation == 'numbered';
}

int _equationOrdinal(TextSystemDocument document, TextSystemBlock block) {
  var count = 0;
  for (final candidate in document.blocks) {
    if (_isEquationBlock(candidate) && _equationIsNumbered(candidate)) {
      count += 1;
    }
    if (candidate.id == block.id) return count == 0 ? 1 : count;
  }
  return count == 0 ? 1 : count;
}

int _nextEquationOrdinal(TextSystemDocument document) {
  return document.blocks.where((block) => _isEquationBlock(block) && _equationIsNumbered(block)).length + 1;
}

String _academicObjectKind(TextSystemBlock block) {
  final kind = block.metadata['kind'];
  return kind == 'table' ? 'table' : 'figure';
}

String _academicObjectTitle(TextSystemBlock block) {
  return _academicObjectKind(block) == 'table' ? 'Table' : 'Figure';
}

String _academicCaptionForBlock(TextSystemBlock block) {
  final caption = block.metadata['caption'];
  if (caption is String && caption.trim().isNotEmpty) return caption.trim();
  return block.text.trim();
}

String _academicLabelForBlock(TextSystemBlock block) {
  final label = block.metadata['label'];
  if (label is String) return label.trim();
  return '';
}

String _academicSourceForBlock(TextSystemBlock block) {
  final source = block.metadata['source'];
  if (source is String) return source.trim();
  return '';
}

String _academicAltTextForBlock(TextSystemBlock block) {
  final altText = block.metadata['altText'];
  if (altText is String) return altText.trim();
  return '';
}

String _academicImagePathForBlock(TextSystemBlock block) {
  final imagePath = block.metadata['imagePath'];
  if (imagePath is String) return imagePath.trim();
  return '';
}

String _academicFileName(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) return '';
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? normalized : parts.last;
}

bool _academicLocalImageExists(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  try {
    return File(trimmed).existsSync();
  } catch (_) {
    return false;
  }
}

String _academicNoteForBlock(TextSystemBlock block) {
  final note = block.metadata['note'];
  if (note is String) return note.trim();
  return '';
}

String _academicFigureSizeForBlock(TextSystemBlock block) {
  final size = block.metadata['figureSize'];
  if (size is String && const ['small', 'medium', 'large', 'fullWidth'].contains(size)) return size;
  return 'medium';
}

String _academicCaptionPositionForBlock(
  TextSystemBlock block, {
  required String defaultPosition,
}) {
  final position = block.metadata['captionPosition'];
  if (position is String && (position == 'above' || position == 'below')) return position;
  return defaultPosition;
}

int _academicHeaderRowsForBlock(TextSystemBlock block) {
  final value = block.metadata['headerRows'];
  if (value is int) return value.clamp(0, 3).toInt();
  return 1;
}

int _academicObjectOrdinal(TextSystemDocument document, TextSystemBlock block) {
  final kind = _academicObjectKind(block);
  var count = 0;
  for (final candidate in document.blocks) {
    if (candidate.type == TextSystemBlockType.custom && candidate.metadata['kind'] == kind) {
      count += 1;
    }
    if (candidate.id == block.id) return count;
  }
  return count == 0 ? 1 : count;
}

int _nextAcademicObjectOrdinal(TextSystemDocument document, String kind) {
  return document.blocks
          .where((block) => block.type == TextSystemBlockType.custom && block.metadata['kind'] == kind)
          .length +
      1;
}

String _academicObjectCaptionLine(TextSystemDocument document, TextSystemBlock block) {
  final prefix = '${_academicObjectTitle(block)} ${_academicObjectOrdinal(document, block)}';
  final caption = _academicCaptionForBlock(block);
  return caption.isEmpty ? prefix : '$prefix: $caption';
}

bool _documentHasAcademicLabel(
  TextSystemDocument document,
  String label, {
  String? exceptBlockId,
}) {
  final normalized = label.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  for (final block in document.blocks) {
    if (block.id == exceptBlockId) continue;
    if (block.type != TextSystemBlockType.custom) continue;
    final candidateLabel = _isEquationBlock(block)
        ? _equationLabelForBlock(block)
        : _isAcademicObjectBlock(block)
            ? _academicLabelForBlock(block)
            : '';
    if (candidateLabel.toLowerCase() == normalized) return true;
  }
  return false;
}

String _academicSlug(String value, {required String fallback}) {
  final trimmed = value.trim().toLowerCase();
  final slug = trimmed
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? fallback : slug;
}

String _academicLabelSuggestion({
  required TextSystemDocument document,
  required String kind,
  required String caption,
}) {
  final prefix = kind == 'table' ? 'tab' : 'fig';
  final fallback = '$kind-${_nextAcademicObjectOrdinal(document, kind)}';
  final base = _academicSlug(caption, fallback: fallback);
  var candidate = '$prefix:$base';
  var suffix = 2;
  while (_documentHasAcademicLabel(document, candidate)) {
    candidate = '$prefix:$base-$suffix';
    suffix += 1;
  }
  return candidate;
}

String _equationLabelSuggestion({
  required TextSystemDocument document,
  required String latex,
}) {
  final fallback = 'equation-${_nextEquationOrdinal(document)}';
  final base = _academicSlug(latex, fallback: fallback);
  var candidate = 'eq:$base';
  var suffix = 2;
  while (_documentHasAcademicLabel(document, candidate)) {
    candidate = 'eq:$base-$suffix';
    suffix += 1;
  }
  return candidate;
}

List<List<String>> _academicTableCellsForBlock(TextSystemBlock block) {
  final rawCells = block.metadata['cells'];
  if (rawCells is List) {
    final parsed = <List<String>>[];
    for (final rawRow in rawCells) {
      if (rawRow is List) {
        parsed.add([for (final cell in rawRow) cell?.toString() ?? '']);
      }
    }
    if (parsed.isNotEmpty) return _normalizedAcademicTableCells(parsed);
  }

  final rows = (block.metadata['rows'] as int? ?? 3).clamp(1, 50).toInt();
  final columns = (block.metadata['columns'] as int? ?? 3).clamp(1, 12).toInt();
  return List<List<String>>.generate(
    rows,
    (_) => List<String>.filled(columns, ''),
  );
}

List<List<String>> _normalizedAcademicTableCells(List<List<String>> cells) {
  if (cells.isEmpty) return const <List<String>>[];
  final columnCount = cells.fold<int>(0, (maxColumns, row) => math.max(maxColumns, row.length));
  final safeColumns = columnCount.clamp(1, 12).toInt();
  final safeRows = cells.take(50).toList();
  return [
    for (final row in safeRows)
      [
        for (var i = 0; i < safeColumns; i++)
          i < row.length ? row[i].trim() : '',
      ],
  ];
}

String _serializeAcademicTableCells(List<List<String>> cells) {
  return cells.map((row) => row.join('\t')).join('\n');
}

List<List<String>> _parseAcademicTableCells(String raw, {required int rows, required int columns}) {
  final lines = raw
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .toList();

  final parsed = <List<String>>[];
  for (final line in lines) {
    final separator = line.contains('\t')
        ? '\t'
        : line.contains(';')
            ? ';'
            : ',';
    parsed.add(line.split(separator).map((cell) => cell.trim()).toList());
  }

  if (parsed.isEmpty) {
    return List<List<String>>.generate(
      rows,
      (_) => List<String>.filled(columns, ''),
    );
  }

  return _normalizedAcademicTableCells(parsed);
}

TextSystemBlock _academicFigureBlockFromDraft(_AcademicFigureDraft draft, {String? id}) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final caption = draft.caption.trim();
  final size = const ['small', 'medium', 'large', 'fullWidth'].contains(draft.size) ? draft.size : 'medium';
  final captionPosition = draft.captionPosition == 'above' ? 'above' : 'below';
  return TextSystemBlock(
    id: id ?? 'figure-$now',
    type: TextSystemBlockType.custom,
    text: caption,
    metadata: <String, Object?>{
      'kind': 'figure',
      'styleId': TextSystemDocumentStyleSheet.custom,
      'caption': caption,
      'figureSize': size,
      'captionPosition': captionPosition,
      if (draft.label.trim().isNotEmpty) 'label': draft.label.trim(),
      if (draft.source.trim().isNotEmpty) 'source': draft.source.trim(),
      if (draft.altText.trim().isNotEmpty) 'altText': draft.altText.trim(),
      if (draft.imagePath.trim().isNotEmpty) 'imagePath': draft.imagePath.trim(),
    },
  );
}

TextSystemBlock _academicTableBlockFromDraft(_AcademicTableDraft draft, {String? id}) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final cells = _normalizedAcademicTableCells(draft.cells);
  final columns = cells.isEmpty ? 0 : cells.first.length;
  final caption = draft.caption.trim();
  final headerRows = draft.headerRows.clamp(0, 3).toInt();
  final captionPosition = draft.captionPosition == 'below' ? 'below' : 'above';
  return TextSystemBlock(
    id: id ?? 'table-$now',
    type: TextSystemBlockType.custom,
    text: caption,
    metadata: <String, Object?>{
      'kind': 'table',
      'styleId': TextSystemDocumentStyleSheet.custom,
      'caption': caption,
      'rows': cells.length,
      'columns': columns,
      'cells': [for (final row in cells) [for (final cell in row) cell]],
      'headerRows': headerRows,
      'captionPosition': captionPosition,
      if (draft.label.trim().isNotEmpty) 'label': draft.label.trim(),
      if (draft.note.trim().isNotEmpty) 'note': draft.note.trim(),
    },
  );
}

TextSystemBlock _academicEquationBlockFromDraft(_AcademicEquationDraft draft, {String? id}) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final latex = draft.latex.trim();
  return TextSystemBlock(
    id: id ?? 'equation-$now',
    type: TextSystemBlockType.custom,
    text: latex,
    metadata: <String, Object?>{
      'kind': 'equation',
      'styleId': TextSystemDocumentStyleSheet.custom,
      'latex': latex,
      'numbered': draft.numbered,
      'presentation': draft.numbered ? 'numbered' : 'display',
      if (draft.label.trim().isNotEmpty) 'label': draft.label.trim(),
      if (draft.note.trim().isNotEmpty) 'note': draft.note.trim(),
    },
  );
}

Future<_AcademicEquationDraft?> _showAcademicEquationDraftDialog({
  required BuildContext context,
  required TextSystemDocument document,
  TextSystemBlock? existingBlock,
}) {
  return showDialog<_AcademicEquationDraft>(
    context: context,
    builder: (context) => _AcademicEquationDraftDialog(
      document: document,
      existingBlock: existingBlock,
    ),
  );
}

Future<_AcademicFigureDraft?> _showAcademicFigureDraftDialog({
  required BuildContext context,
  required TextSystemDocument document,
  TextSystemBlock? existingBlock,
}) {
  return showDialog<_AcademicFigureDraft>(
    context: context,
    builder: (context) => _AcademicFigureDraftDialog(
      document: document,
      existingBlock: existingBlock,
    ),
  );
}

Future<_AcademicTableDraft?> _showAcademicTableDraftDialog({
  required BuildContext context,
  required TextSystemDocument document,
  TextSystemBlock? existingBlock,
}) {
  return showDialog<_AcademicTableDraft>(
    context: context,
    builder: (context) => _AcademicTableDraftDialog(
      document: document,
      existingBlock: existingBlock,
    ),
  );
}


class _AcademicEquationDraftDialog extends StatefulWidget {
  const _AcademicEquationDraftDialog({
    required this.document,
    this.existingBlock,
  });

  final TextSystemDocument document;
  final TextSystemBlock? existingBlock;

  @override
  State<_AcademicEquationDraftDialog> createState() => _AcademicEquationDraftDialogState();
}

class _AcademicEquationDraftDialogState extends State<_AcademicEquationDraftDialog> {
  late final TextEditingController _latexController;
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  late bool _numbered;

  @override
  void initState() {
    super.initState();
    final existingBlock = widget.existingBlock;
    _latexController = TextEditingController(
      text: existingBlock == null ? r'\frac{a}{b} = c' : _equationLatexForBlock(existingBlock),
    )..addListener(_refresh);
    _labelController = TextEditingController(
      text: existingBlock == null ? '' : _equationLabelForBlock(existingBlock),
    )..addListener(_refresh);
    _noteController = TextEditingController(
      text: existingBlock == null ? '' : _equationNoteForBlock(existingBlock),
    );
    _numbered = existingBlock == null ? false : _equationIsNumbered(existingBlock);
  }

  @override
  void dispose() {
    _latexController.dispose();
    _labelController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _suggestLabel() {
    final suggestion = _equationLabelSuggestion(
      document: widget.document,
      latex: _latexController.text,
    );
    _labelController.text = suggestion;
  }

  bool get _duplicateLabel {
    final label = _labelController.text.trim();
    if (label.isEmpty) return false;
    return _documentHasAcademicLabel(
      widget.document,
      label,
      exceptBlockId: widget.existingBlock?.id,
    );
  }

  bool get _canSubmit => _latexController.text.trim().isNotEmpty && !_duplicateLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEditing = widget.existingBlock != null;
    final latex = _latexController.text.trim();

    return AlertDialog(
      title: Text(isEditing ? 'Edit equation' : 'Insert equation'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Write the equation in LaTeX. The editor stores the LaTeX source and renders a document preview.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _latexController,
                minLines: 3,
                maxLines: 6,
                autofocus: !isEditing,
                decoration: const InputDecoration(
                  labelText: 'LaTeX equation',
                  hintText: r'\int_0^1 x^2 \, dx = \frac{1}{3}',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.72)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: latex.isEmpty
                      ? Text(
                          'Equation preview',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        )
                      : Center(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Math.tex(
                              latex,
                              mathStyle: MathStyle.display,
                              textStyle: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
                              onErrorFallback: (error) => Text(
                                error.message,
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      decoration: InputDecoration(
                        labelText: 'Label',
                        hintText: 'eq:capital-accumulation',
                        border: const OutlineInputBorder(),
                        errorText: _duplicateLabel ? 'This label is already used.' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _suggestLabel,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Suggest'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Number equation'),
                subtitle: const Text('Shows a right-aligned equation number in the document.'),
                value: _numbered,
                onChanged: (value) => setState(() => _numbered = value),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Equation note',
                  hintText: 'Optional explanation or source note.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit
              ? () {
                  Navigator.of(context).pop(
                    _AcademicEquationDraft(
                      latex: _latexController.text,
                      label: _labelController.text,
                      note: _noteController.text,
                      numbered: _numbered,
                    ),
                  );
                }
              : null,
          child: Text(isEditing ? 'Save equation' : 'Insert equation'),
        ),
      ],
    );
  }
}

class _AcademicFigureDraftDialog extends StatefulWidget {
  const _AcademicFigureDraftDialog({
    required this.document,
    this.existingBlock,
  });

  final TextSystemDocument document;
  final TextSystemBlock? existingBlock;

  @override
  State<_AcademicFigureDraftDialog> createState() => _AcademicFigureDraftDialogState();
}

class _AcademicFigureDraftDialogState extends State<_AcademicFigureDraftDialog> {
  late final TextEditingController _captionController;
  late final TextEditingController _labelController;
  late final TextEditingController _sourceController;
  late final TextEditingController _altTextController;
  late String _imagePath;
  late String _size;
  late String _captionPosition;

  @override
  void initState() {
    super.initState();
    final existingBlock = widget.existingBlock;
    _captionController = TextEditingController(
      text: existingBlock == null ? '' : _academicCaptionForBlock(existingBlock),
    )..addListener(_refreshLabelWarning);
    _labelController = TextEditingController(
      text: existingBlock == null ? '' : _academicLabelForBlock(existingBlock),
    )..addListener(_refreshLabelWarning);
    _sourceController = TextEditingController(
      text: existingBlock == null ? '' : _academicSourceForBlock(existingBlock),
    );
    _altTextController = TextEditingController(
      text: existingBlock == null ? '' : _academicAltTextForBlock(existingBlock),
    );
    _imagePath = existingBlock == null ? '' : _academicImagePathForBlock(existingBlock);
    _size = existingBlock == null ? 'medium' : _academicFigureSizeForBlock(existingBlock);
    _captionPosition = existingBlock == null
        ? 'below'
        : _academicCaptionPositionForBlock(existingBlock, defaultPosition: 'below');
  }

  @override
  void dispose() {
    _captionController.dispose();
    _labelController.dispose();
    _sourceController.dispose();
    _altTextController.dispose();
    super.dispose();
  }

  void _refreshLabelWarning() {
    if (mounted) setState(() {});
  }

  bool get _labelIsDuplicate => _documentHasAcademicLabel(
        widget.document,
        _labelController.text,
        exceptBlockId: widget.existingBlock?.id,
      );

  void _suggestLabel() {
    _labelController.text = _academicLabelSuggestion(
      document: widget.document,
      kind: 'figure',
      caption: _captionController.text,
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final pickedPath = result.files.single.path;
    if (pickedPath == null || pickedPath.trim().isEmpty) return;
    setState(() {
      _imagePath = pickedPath;
      if (_altTextController.text.trim().isEmpty) {
        _altTextController.text = result.files.single.name;
      }
    });
  }

  void _clearImage() {
    setState(() => _imagePath = '');
  }

  Widget _buildImagePicker(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = _academicFileName(_imagePath);
    final hasImage = _academicLocalImageExists(_imagePath);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 112,
                height: 72,
                child: hasImage
                    ? Image.file(
                        File(_imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _AcademicFigureEmptyPreview(label: fileName),
                      )
                    : const _AcademicFigureEmptyPreview(label: 'No image selected'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasImage ? fileName : 'Upload a figure image',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasImage
                        ? 'The figure will render as the image followed by the academic caption.'
                        : 'Choose a local image file. The file path is stored in the document metadata for now.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(hasImage ? 'Change image' : 'Choose image'),
                      ),
                      if (_imagePath.trim().isNotEmpty)
                        TextButton.icon(
                          onPressed: _clearImage,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Clear'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duplicate = _labelIsDuplicate;
    return AlertDialog(
      title: Text(widget.existingBlock == null ? 'Insert figure' : 'Edit figure'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _captionController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Caption',
                  hintText: 'Short academic figure caption',
                ),
              ),
              const SizedBox(height: 12),
              _buildImagePicker(context),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      decoration: InputDecoration(
                        labelText: 'Label',
                        hintText: 'fig:mechanism or Figure A1',
                        errorText: duplicate ? 'Another figure/table already uses this label.' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _suggestLabel,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: const Text('Suggest'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _size,
                      decoration: const InputDecoration(labelText: 'Figure size'),
                      items: const [
                        DropdownMenuItem<String>(value: 'small', child: Text('Small')),
                        DropdownMenuItem<String>(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem<String>(value: 'large', child: Text('Large')),
                        DropdownMenuItem<String>(value: 'fullWidth', child: Text('Full width')),
                      ],
                      onChanged: (value) => setState(() => _size = value ?? _size),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _captionPosition,
                      decoration: const InputDecoration(labelText: 'Caption position'),
                      items: const [
                        DropdownMenuItem<String>(value: 'below', child: Text('Below figure')),
                        DropdownMenuItem<String>(value: 'above', child: Text('Above figure')),
                      ],
                      onChanged: (value) => setState(() => _captionPosition = value ?? _captionPosition),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sourceController,
                decoration: const InputDecoration(
                  labelText: 'Source / image reference',
                  hintText: 'Optional path, source note, or placeholder reference',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _altTextController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Alt text / figure note',
                  hintText: 'Optional description used later for accessibility/export',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: duplicate
              ? null
              : () {
                  Navigator.of(context).pop(
                    _AcademicFigureDraft(
                      caption: _captionController.text,
                      label: _labelController.text,
                      source: _sourceController.text,
                      altText: _altTextController.text,
                      imagePath: _imagePath,
                      size: _size,
                      captionPosition: _captionPosition,
                    ),
                  );
                },
          child: Text(widget.existingBlock == null ? 'Insert figure' : 'Save figure'),
        ),
      ],
    );
  }
}

class _AcademicTableDraftDialog extends StatefulWidget {
  const _AcademicTableDraftDialog({
    required this.document,
    this.existingBlock,
  });

  final TextSystemDocument document;
  final TextSystemBlock? existingBlock;

  @override
  State<_AcademicTableDraftDialog> createState() => _AcademicTableDraftDialogState();
}

class _AcademicTableDraftDialogState extends State<_AcademicTableDraftDialog> {
  late final TextEditingController _captionController;
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  late final TextEditingController _pasteController;
  final List<List<TextEditingController>> _cellControllers = <List<TextEditingController>>[];
  late int _rows;
  late int _columns;
  late int _headerRows;
  late String _captionPosition;

  @override
  void initState() {
    super.initState();
    final existingBlock = widget.existingBlock;
    final existingCells = existingBlock == null
        ? List<List<String>>.generate(3, (_) => List<String>.filled(3, ''))
        : _academicTableCellsForBlock(existingBlock);
    _captionController = TextEditingController(
      text: existingBlock == null ? '' : _academicCaptionForBlock(existingBlock),
    )..addListener(_refreshLabelWarning);
    _labelController = TextEditingController(
      text: existingBlock == null ? '' : _academicLabelForBlock(existingBlock),
    )..addListener(_refreshLabelWarning);
    _noteController = TextEditingController(
      text: existingBlock == null ? '' : _academicNoteForBlock(existingBlock),
    );
    _pasteController = TextEditingController();
    _headerRows = existingBlock == null ? 1 : _academicHeaderRowsForBlock(existingBlock);
    _captionPosition = existingBlock == null
        ? 'above'
        : _academicCaptionPositionForBlock(existingBlock, defaultPosition: 'above');
    _replaceGrid(existingCells, disposeExisting: false);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _labelController.dispose();
    _noteController.dispose();
    _pasteController.dispose();
    _disposeCellControllers();
    super.dispose();
  }

  void _disposeCellControllers() {
    for (final row in _cellControllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }
    _cellControllers.clear();
  }

  void _replaceGrid(List<List<String>> cells, {bool disposeExisting = true}) {
    final normalized = _normalizedAcademicTableCells(cells);
    final safeCells = normalized.isEmpty
        ? List<List<String>>.generate(3, (_) => List<String>.filled(3, ''))
        : normalized;
    if (disposeExisting) _disposeCellControllers();
    _cellControllers
      ..clear()
      ..addAll([
        for (final row in safeCells)
          [for (final cell in row) TextEditingController(text: cell)],
      ]);
    _rows = safeCells.length.clamp(1, 50).toInt();
    _columns = safeCells.first.length.clamp(1, 12).toInt();
    _headerRows = _headerRows.clamp(0, _rows).toInt();
  }

  List<List<String>> get _currentCells {
    return [
      for (final row in _cellControllers)
        [for (final controller in row) controller.text],
    ];
  }

  void _resizeGrid({int? rows, int? columns}) {
    final nextRows = (rows ?? _rows).clamp(1, 50).toInt();
    final nextColumns = (columns ?? _columns).clamp(1, 12).toInt();
    final current = _currentCells;
    final nextCells = List<List<String>>.generate(
      nextRows,
      (rowIndex) => List<String>.generate(
        nextColumns,
        (columnIndex) => rowIndex < current.length && columnIndex < current[rowIndex].length
            ? current[rowIndex][columnIndex]
            : '',
      ),
    );
    setState(() => _replaceGrid(nextCells));
  }

  void _applyPastedData() {
    final raw = _pasteController.text.trim();
    if (raw.isEmpty) return;
    final parsed = _parseAcademicTableCells(raw, rows: _rows, columns: _columns);
    setState(() {
      _replaceGrid(parsed);
      _pasteController.clear();
    });
  }

  void _refreshLabelWarning() {
    if (mounted) setState(() {});
  }

  bool get _labelIsDuplicate => _documentHasAcademicLabel(
        widget.document,
        _labelController.text,
        exceptBlockId: widget.existingBlock?.id,
      );

  void _suggestLabel() {
    _labelController.text = _academicLabelSuggestion(
      document: widget.document,
      kind: 'table',
      caption: _captionController.text,
    );
  }

  Widget _buildGridEditor(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headerRows = _headerRows.clamp(0, _rows).toInt();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Table cells',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _resizeGrid(rows: _rows + 1),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Row'),
                ),
                TextButton.icon(
                  onPressed: _rows <= 1 ? null : () => _resizeGrid(rows: _rows - 1),
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Row'),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => _resizeGrid(columns: _columns + 1),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Column'),
                ),
                TextButton.icon(
                  onPressed: _columns <= 1 ? null : () => _resizeGrid(columns: _columns - 1),
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Column'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<int>(
                    value: headerRows,
                    decoration: const InputDecoration(
                      labelText: 'Header rows',
                      isDense: true,
                    ),
                    items: [
                      for (var i = 0; i <= math.min(3, _rows); i++)
                        DropdownMenuItem<int>(value: i, child: Text('$i')),
                    ],
                    onChanged: (value) => setState(() => _headerRows = value ?? _headerRows),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Edit values directly in the grid. Use the paste box below for copied Excel/CSV/LaTeX-like rows.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 42),
                          for (var columnIndex = 0; columnIndex < _columns; columnIndex++)
                            SizedBox(
                              width: 156,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6, bottom: 6),
                                child: Text(
                                  'Column ${columnIndex + 1}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      for (var rowIndex = 0; rowIndex < _rows; rowIndex++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 44,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${rowIndex + 1}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: rowIndex < headerRows
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: rowIndex < headerRows ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              for (var columnIndex = 0; columnIndex < _columns; columnIndex++)
                                SizedBox(
                                  width: 156,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: TextField(
                                      controller: _cellControllers[rowIndex][columnIndex],
                                      textInputAction: TextInputAction.next,
                                      minLines: 1,
                                      maxLines: 2,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        filled: rowIndex < headerRows,
                                        fillColor: rowIndex < headerRows
                                            ? colorScheme.primaryContainer.withValues(alpha: 0.22)
                                            : colorScheme.surface,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        border: const OutlineInputBorder(),
                                      ),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: rowIndex < headerRows ? FontWeight.w700 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPastePanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        'Paste table data',
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        'Accepts tab-separated, semicolon-separated, or comma-separated rows.',
        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: _pasteController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Variable\tValue\nWage\t1.24\nPension\t0.31',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: _applyPastedData,
            icon: const Icon(Icons.content_paste_go_outlined, size: 18),
            label: const Text('Replace grid with pasted data'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final duplicate = _labelIsDuplicate;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(widget.existingBlock == null ? 'Insert table' : 'Edit table'),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _captionController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Caption',
                        hintText: 'Short academic table caption',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _labelController,
                      decoration: InputDecoration(
                        labelText: 'Label',
                        hintText: 'tab:baseline-results',
                        errorText: duplicate ? 'Already used.' : null,
                        suffixIcon: IconButton(
                          tooltip: 'Suggest label',
                          onPressed: _suggestLabel,
                          icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _captionPosition,
                decoration: const InputDecoration(labelText: 'Caption position'),
                items: const [
                  DropdownMenuItem<String>(value: 'above', child: Text('Above table')),
                  DropdownMenuItem<String>(value: 'below', child: Text('Below table')),
                ],
                onChanged: (value) => setState(() => _captionPosition = value ?? _captionPosition),
              ),
              const SizedBox(height: 16),
              if (widget.existingBlock == null) ...[
                _buildGridEditor(context),
                const SizedBox(height: 12),
                _buildPastePanel(context),
                const SizedBox(height: 12),
              ] else ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Table cells are edited directly in the document.',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use the table toolbar beside the selected cell to add/remove rows and columns or paste copied data.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int>(
                            value: _headerRows.clamp(0, _rows).toInt(),
                            decoration: const InputDecoration(
                              labelText: 'Header rows',
                              isDense: true,
                            ),
                            items: [
                              for (var i = 0; i <= math.min(3, _rows); i++)
                                DropdownMenuItem<int>(value: i, child: Text('$i')),
                            ],
                            onChanged: (value) => setState(() => _headerRows = value ?? _headerRows),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _noteController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Table note',
                  hintText: 'Optional note shown below the table',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: duplicate
              ? null
              : () {
                  Navigator.of(context).pop(
                    _AcademicTableDraft(
                      caption: _captionController.text,
                      label: _labelController.text,
                      cells: _currentCells,
                      note: _noteController.text,
                      headerRows: _headerRows,
                      captionPosition: _captionPosition,
                    ),
                  );
                },
          child: Text(widget.existingBlock == null ? 'Insert table' : 'Save table'),
        ),
      ],
    );
  }
}

class _AcademicObjectBlockChrome extends StatelessWidget {
  const _AcademicObjectBlockChrome({
    required this.textController,
    required this.block,
    required this.document,
    required this.editable,
    required this.selected,
    required this.onSelect,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDeleteSelected,
    required this.onRequestCaretRestore,
    required this.onCaretBefore,
    required this.onCaretAfter,
    required this.onActiveTableContextChanged,
  });

  final TextSystemController textController;
  final TextSystemBlock block;
  final TextSystemDocument document;
  final bool editable;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDuplicate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDeleteSelected;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final VoidCallback onCaretBefore;
  final VoidCallback onCaretAfter;
  final ValueChanged<_ActiveTableEditingContext?> onActiveTableContextChanged;

  void _replaceWith(TextSystemBlock replacementBlock, {required String label}) {
    _replaceBlockInUserTransaction(
      textController,
      block.id,
      replacementBlock,
      label: label,
      ensureParagraphAfter: true,
    );
  }

  Future<void> _edit(BuildContext context) async {
    if (_academicObjectKind(block) == 'table') {
      final draft = await _showAcademicTableDraftDialog(
        context: context,
        document: document,
        existingBlock: block,
      );
      if (draft == null) return;
      _replaceWith(_academicTableBlockFromDraft(draft, id: block.id), label: 'Update table properties');
    } else {
      final draft = await _showAcademicFigureDraftDialog(
        context: context,
        document: document,
        existingBlock: block,
      );
      if (draft == null) return;
      _replaceWith(_academicFigureBlockFromDraft(draft, id: block.id), label: 'Update figure');
    }
    onRequestCaretRestore(
      TextSystemPagedCaretAnchor(
        blockId: block.id,
        textOffset: 0,
      ),
    );
  }

  void _updateTable(_AcademicTableDraft draft) {
    _replaceWith(_academicTableBlockFromDraft(draft, id: block.id), label: 'Edit table');
  }

  void _delete() {
    final objectKind = _academicObjectKind(block);
    final objectName = objectKind == 'table' ? 'table' : 'figure';
    final caret = _deleteBlockInUserTransaction(
      textController,
      block.id,
      label: 'Delete $objectName',
    );
    onRequestCaretRestore(caret);
  }

  @override
  Widget build(BuildContext context) {
    final isTable = _academicObjectKind(block) == 'table';
    final child = isTable
        ? _AcademicTableBlockView(
            block: block,
            document: document,
            editable: editable,
            onEdit: () => _edit(context),
            onDelete: _delete,
            onTableChanged: _updateTable,
            onActiveTableContextChanged: onActiveTableContextChanged,
          )
        : _AcademicFigureBlockView(
            block: block,
            document: document,
            editable: editable,
            onEdit: () => _edit(context),
            onDelete: _delete,
          );

    return _AcademicObjectSelectionFrame(
      selected: selected,
      editable: editable,
      tooltip: isTable ? 'Table object' : 'Figure object',
      onSelect: onSelect,
      onEdit: () => _edit(context),
      onDuplicate: onDuplicate,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onDelete: onDeleteSelected,
      onCaretBefore: onCaretBefore,
      onCaretAfter: onCaretAfter,
      child: child,
    );
  }
}



class _AcademicEquationBlockChrome extends StatefulWidget {
  const _AcademicEquationBlockChrome({
    required this.textController,
    required this.block,
    required this.document,
    required this.editable,
    required this.selected,
    required this.onSelect,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDeleteSelected,
    required this.onRequestCaretRestore,
    required this.onCaretBefore,
    required this.onCaretAfter,
  });

  final TextSystemController textController;
  final TextSystemBlock block;
  final TextSystemDocument document;
  final bool editable;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDuplicate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDeleteSelected;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final VoidCallback onCaretBefore;
  final VoidCallback onCaretAfter;

  @override
  State<_AcademicEquationBlockChrome> createState() => _AcademicEquationBlockChromeState();
}

class _AcademicEquationBlockChromeState extends State<_AcademicEquationBlockChrome> {
  late final TextEditingController _latexController;
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  late final FocusNode _latexFocusNode;
  bool _editing = false;
  bool _numbered = true;
  bool _finishingEdit = false;

  @override
  void initState() {
    super.initState();
    _latexController = TextEditingController(text: _equationLatexForBlock(widget.block));
    _labelController = TextEditingController(text: _equationLabelForBlock(widget.block));
    _noteController = TextEditingController(text: _equationNoteForBlock(widget.block));
    _latexFocusNode = FocusNode(debugLabel: 'Equation LaTeX source');
    _latexFocusNode.addListener(_handleLatexFocusChanged);
    _numbered = _equationIsNumbered(widget.block);
    _editing = widget.editable && _latexController.text.trim().isEmpty;
    if (_editing) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _latexFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AcademicEquationBlockChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id) return;
    final latex = _equationLatexForBlock(widget.block);
    final label = _equationLabelForBlock(widget.block);
    final note = _equationNoteForBlock(widget.block);
    if (!_editing && latex != _latexController.text) {
      _latexController.text = latex;
    }
    if (!_editing && label != _labelController.text) {
      _labelController.text = label;
    }
    if (!_editing && note != _noteController.text) {
      _noteController.text = note;
    }
    if (!_editing) {
      _numbered = _equationIsNumbered(widget.block);
    }
  }

  @override
  void dispose() {
    _latexFocusNode.removeListener(_handleLatexFocusChanged);
    _latexFocusNode.dispose();
    _latexController.dispose();
    _labelController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _handleLatexFocusChanged() {
    if (_latexFocusNode.hasFocus || !_editing || _finishingEdit) return;
    _finishEditing(commit: true);
  }

  String get _currentEquationLatex {
    final draft = _latexController.text.trim();
    if (draft.isNotEmpty) return draft;
    final stored = _equationLatexForBlock(widget.block).trim();
    if (stored.isNotEmpty) return stored;
    return r'\text{New equation}';
  }

  TextSystemPagedCaretAnchor _replaceWith(
    TextSystemBlock replacementBlock, {
    required String label,
    bool ensureParagraphAfter = false,
  }) {
    return _replaceBlockInUserTransaction(
      widget.textController,
      widget.block.id,
      replacementBlock,
      label: label,
      ensureParagraphAfter: ensureParagraphAfter,
    );
  }

  void _delete() {
    final caret = _deleteBlockInUserTransaction(
      widget.textController,
      widget.block.id,
      label: 'Delete equation',
    );
    widget.onRequestCaretRestore(caret);
  }

  TextSystemPagedCaretAnchor _ensureWritableParagraphAfterEquation({required String label}) {
    final document = widget.textController.document;
    final blocks = document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == widget.block.id);
    if (index < 0) {
      final fallbackBlock = blocks.isNotEmpty
          ? blocks.last
          : TextSystemBlock.paragraph(
              id: 'paragraph_${DateTime.now().microsecondsSinceEpoch}',
              text: '',
            );
      if (blocks.isEmpty) {
        _commitUserDocumentTransaction(
          widget.textController,
          document.copyWith(blocks: [fallbackBlock]),
          label: label,
        );
      }
      return TextSystemPagedCaretAnchor(blockId: fallbackBlock.id, textOffset: fallbackBlock.text.length);
    }

    final nextIndex = index + 1;
    if (nextIndex < blocks.length && _blockCanReceiveObjectExitCaret(blocks[nextIndex])) {
      return TextSystemPagedCaretAnchor(blockId: blocks[nextIndex].id, textOffset: 0);
    }

    final paragraph = TextSystemBlock.paragraph(
      id: 'paragraph_after_equation_${DateTime.now().microsecondsSinceEpoch}',
      text: '',
    );
    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < blocks.length; i++) ...[
        blocks[i],
        if (i == index) paragraph,
      ],
    ];
    _commitUserDocumentTransaction(
      widget.textController,
      document.copyWith(blocks: nextBlocks),
      label: label,
    );
    return TextSystemPagedCaretAnchor(blockId: paragraph.id, textOffset: 0);
  }

  bool get _duplicateLabel {
    final label = _labelController.text.trim();
    if (label.isEmpty) return false;
    return _documentHasAcademicLabel(
      widget.textController.document,
      label,
      exceptBlockId: widget.block.id,
    );
  }

  bool get _canCommit => _latexController.text.trim().isNotEmpty && !_duplicateLabel;

  void _commit({bool closeEditor = true}) {
    if (!_canCommit) return;
    final draft = _AcademicEquationDraft(
      latex: _latexController.text,
      label: _labelController.text,
      note: _noteController.text,
      numbered: _numbered,
    );
    final exitTarget = _replaceWith(
      _academicEquationBlockFromDraft(draft, id: widget.block.id),
      label: 'Update equation',
      ensureParagraphAfter: true,
    );
    widget.onRequestCaretRestore(exitTarget);
    if (closeEditor && mounted) {
      setState(() => _editing = false);
    }
  }

  void _finishEditing({required bool commit}) {
    if (_finishingEdit) return;
    _finishingEdit = true;
    try {
      final storedLatex = _equationLatexForBlock(widget.block).trim();
      final draftLatex = _latexController.text.trim();

      if (draftLatex.isEmpty) {
        _delete();
        return;
      }

      if (commit && !_duplicateLabel) {
        _commit(closeEditor: true);
        return;
      }

      if (mounted) setState(() => _editing = false);
    } finally {
      _finishingEdit = false;
    }
  }

  void _cancelEditing() {
    final storedLatex = _equationLatexForBlock(widget.block).trim();
    if (storedLatex.isEmpty && _latexController.text.trim().isEmpty) {
      _delete();
      return;
    }
    if (storedLatex.isNotEmpty) {
      _latexController.text = storedLatex;
    }
    setState(() => _editing = false);
  }

  void _startEditing() {
    if (!widget.editable) return;
    setState(() => _editing = true);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _latexFocusNode.requestFocus();
      final text = _latexController.text;
      _latexController.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    });
  }

  Widget _buildFormula(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final latex = _currentEquationLatex;
    final ordinal = _numbered ? _equationOrdinal(widget.textController.document, widget.block) : null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.editable
          ? () {
              if (widget.selected) {
                _startEditing();
              } else {
                widget.onSelect();
              }
            }
          : null,
      onDoubleTap: widget.editable ? _startEditing : null,
      child: MouseRegion(
        cursor: widget.editable ? SystemMouseCursors.text : MouseCursor.defer,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Math.tex(
                      latex,
                      mathStyle: MathStyle.display,
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.35,
                      ),
                      onErrorFallback: (error) => SelectableText(
                        latex,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.error,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (ordinal != null)
                Positioned(
                  right: 0,
                  child: Text(
                    '($ordinal)',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLatexSourceField(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ordinal = _numbered ? _equationOrdinal(widget.textController.document, widget.block) : null;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _cancelEditing,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _finishEditing(commit: true),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => _finishEditing(commit: true),
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = math.max(
              140.0,
              math.min(520.0, constraints.maxWidth - (ordinal == null ? 24.0 : 74.0)),
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _latexController,
                      focusNode: _latexFocusNode,
                      autofocus: true,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _finishEditing(commit: true),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: r'\int_0^1 x^2 \, dx = \frac{1}{3}',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
                        ),
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (ordinal != null)
                  Positioned(
                    right: 0,
                    child: Text(
                      '($ordinal)',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return _buildLatexSourceField(context);
    }
    return _AcademicObjectSelectionFrame(
      selected: widget.selected,
      editable: widget.editable,
      tooltip: 'Equation object',
      onSelect: widget.onSelect,
      onEdit: _startEditing,
      onDuplicate: widget.onDuplicate,
      onMoveUp: widget.onMoveUp,
      onMoveDown: widget.onMoveDown,
      onDelete: widget.onDeleteSelected,
      onCaretBefore: widget.onCaretBefore,
      onCaretAfter: widget.onCaretAfter,
      child: _buildFormula(context),
    );
  }
}


class _AcademicObjectSelectionFrame extends StatelessWidget {
  const _AcademicObjectSelectionFrame({
    required this.selected,
    required this.editable,
    required this.tooltip,
    required this.onSelect,
    required this.onEdit,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onCaretBefore,
    required this.onCaretAfter,
    required this.child,
  });

  final bool selected;
  final bool editable;
  final String tooltip;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onCaretBefore;
  final VoidCallback onCaretAfter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final framed = Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: colorScheme.primary.withValues(alpha: 0.74), width: 1.4)
                : Border.all(color: Colors.transparent, width: 1.4),
          ),
          child: child,
        ),
        if (selected && editable) ...[
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _ObjectCaretLandingZone(
              tooltip: 'Place caret before object',
              alignment: Alignment.topCenter,
              onTap: onCaretBefore,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ObjectCaretLandingZone(
              tooltip: 'Place caret after object',
              alignment: Alignment.bottomCenter,
              onTap: onCaretAfter,
            ),
          ),
        ],
      ],
    );

    return MouseRegion(
      cursor: editable ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: editable ? onSelect : null,
        onDoubleTap: editable ? onEdit : null,
        child: Tooltip(
          message: selected
              ? '$tooltip selected · Delete removes it · Alt+↑/↓ moves it · Ctrl+D duplicates it'
              : tooltip,
          waitDuration: const Duration(milliseconds: 700),
          child: framed,
        ),
      ),
    );
  }
}

class _ObjectCaretLandingZone extends StatelessWidget {
  const _ObjectCaretLandingZone({
    required this.tooltip,
    required this.alignment,
    required this.onTap,
  });

  final String tooltip;
  final Alignment alignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap,
          child: SizedBox(
            height: 12,
            child: Align(
              alignment: alignment,
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedObjectFloatingToolbar extends StatelessWidget {
  const _SelectedObjectFloatingToolbar({
    required this.onEdit,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SelectedObjectToolbarButton(icon: Icons.edit_rounded, tooltip: 'Edit object', onPressed: onEdit),
            _SelectedObjectToolbarButton(icon: Icons.copy_rounded, tooltip: 'Duplicate object', onPressed: onDuplicate),
            _SelectedObjectToolbarButton(icon: Icons.keyboard_arrow_up_rounded, tooltip: 'Move object up', onPressed: onMoveUp),
            _SelectedObjectToolbarButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Move object down', onPressed: onMoveDown),
            _SelectedObjectToolbarButton(icon: Icons.delete_outline_rounded, tooltip: 'Delete object', destructive: true, onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _SelectedObjectToolbarButton extends StatelessWidget {
  const _SelectedObjectToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icon,
            size: 16,
            color: destructive ? colorScheme.error : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AcademicFigureBlockView extends StatelessWidget {
  const _AcademicFigureBlockView({
    required this.block,
    required this.document,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });

  final TextSystemBlock block;
  final TextSystemDocument document;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _academicLabelForBlock(block);
    final source = _academicSourceForBlock(block);
    final altText = _academicAltTextForBlock(block);
    final imagePath = _academicImagePathForBlock(block);
    final captionPosition = _academicCaptionPositionForBlock(block, defaultPosition: 'below');
    final caption = _AcademicCaptionLine(
      text: _academicObjectCaptionLine(document, block),
      alignment: TextAlign.center,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (captionPosition == 'above') ...[
            caption,
            const SizedBox(height: 8),
          ],
          _AcademicFigurePreview(block: block),
          if (captionPosition == 'below') ...[
            const SizedBox(height: 8),
            caption,
          ],
          if (imagePath.isNotEmpty || source.isNotEmpty || altText.isNotEmpty || label.isNotEmpty) ...[
            const SizedBox(height: 4),
            _AcademicObjectMetaLine(
              parts: [
                if (label.isNotEmpty) 'Label: $label',
                if (imagePath.isNotEmpty) 'Image: ${_academicFileName(imagePath)}',
                if (source.isNotEmpty) 'Source: $source',
                if (altText.isNotEmpty) 'Alt: $altText',
              ],
              textAlign: TextAlign.center,
            ),
          ],
          Divider(height: 18, thickness: 0.7, color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

class _AcademicTableBlockView extends StatefulWidget {
  const _AcademicTableBlockView({
    required this.block,
    required this.document,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
    required this.onTableChanged,
    required this.onActiveTableContextChanged,
  });

  final TextSystemBlock block;
  final TextSystemDocument document;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<_AcademicTableDraft> onTableChanged;
  final ValueChanged<_ActiveTableEditingContext?> onActiveTableContextChanged;

  @override
  State<_AcademicTableBlockView> createState() => _AcademicTableBlockViewState();
}

class _AcademicTableBlockViewState extends State<_AcademicTableBlockView> {
  final List<List<TextEditingController>> _cellControllers = <List<TextEditingController>>[];
  Timer? _commitTimer;
  late int _headerRows;
  int _selectedRow = 0;
  int _selectedColumn = 0;
  bool _tableActive = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
    _headerRows = _academicHeaderRowsForBlock(widget.block);
    _replaceGrid(_academicTableCellsForBlock(widget.block), disposeExisting: false);
  }

  @override
  void didUpdateWidget(covariant _AcademicTableBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id) {
      _headerRows = _academicHeaderRowsForBlock(widget.block);
      _replaceGrid(_academicTableCellsForBlock(widget.block));
    } else if (oldWidget.block.metadata['headerRows'] != widget.block.metadata['headerRows']) {
      _headerRows = _academicHeaderRowsForBlock(widget.block).clamp(0, _rows).toInt();
    }
  }

  @override
  void dispose() {
    if (_tableActive) {
      widget.onActiveTableContextChanged(null);
    }
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _commitTimer?.cancel();
    _disposeCellControllers();
    super.dispose();
  }

  int get _rows => _cellControllers.length;
  int get _columns => _cellControllers.isEmpty ? 0 : _cellControllers.first.length;

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!_tableActive || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;

    _deactivateTable();
    return true;
  }

  String _columnName(int index) {
    var n = index + 1;
    final chars = <String>[];
    while (n > 0) {
      n -= 1;
      chars.insert(0, String.fromCharCode(65 + (n % 26)));
      n ~/= 26;
    }
    return chars.join();
  }

  void _disposeCellControllers() {
    for (final row in _cellControllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }
    _cellControllers.clear();
  }

  void _replaceGrid(List<List<String>> cells, {bool disposeExisting = true}) {
    final normalized = _normalizedAcademicTableCells(cells);
    final safeCells = normalized.isEmpty
        ? List<List<String>>.generate(3, (_) => List<String>.filled(3, ''))
        : normalized;
    if (disposeExisting) _disposeCellControllers();
    _cellControllers
      ..clear()
      ..addAll([
        for (final row in safeCells)
          [for (final cell in row) TextEditingController(text: cell)],
      ]);
    _selectedRow = _selectedRow.clamp(0, math.max(0, safeCells.length - 1)).toInt();
    _selectedColumn = _selectedColumn.clamp(0, math.max(0, safeCells.first.length - 1)).toInt();
    _headerRows = _headerRows.clamp(0, safeCells.length).toInt();
  }

  List<List<String>> get _currentCells {
    return [
      for (final row in _cellControllers)
        [for (final controller in row) controller.text],
    ];
  }

  _AcademicTableDraft _currentDraft() {
    return _AcademicTableDraft(
      caption: _academicCaptionForBlock(widget.block),
      label: _academicLabelForBlock(widget.block),
      cells: _currentCells,
      note: _academicNoteForBlock(widget.block),
      headerRows: _headerRows,
      captionPosition: _academicCaptionPositionForBlock(widget.block, defaultPosition: 'above'),
    );
  }

  void _scheduleCommit() {
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 1800), _commitNow);
  }

  void _publishTableContext() {
    if (!_tableActive || !widget.editable) {
      widget.onActiveTableContextChanged(null);
      return;
    }
    final maxHeaderRows = math.min(3, _rows);
    final nextHeaderRows = _headerRows >= maxHeaderRows ? 0 : _headerRows + 1;
    widget.onActiveTableContextChanged(
      _ActiveTableEditingContext(
        blockId: widget.block.id,
        cellLabel: 'Cell ${_columnName(_selectedColumn)}${_selectedRow + 1}',
        headerRows: _headerRows,
        canDeleteRow: _rows > 1,
        canDeleteColumn: _columns > 1,
        onInsertRowAbove: () => _insertRow(_selectedRow),
        onInsertRowBelow: () => _insertRow(_selectedRow + 1),
        onInsertColumnLeft: () => _insertColumn(_selectedColumn),
        onInsertColumnRight: () => _insertColumn(_selectedColumn + 1),
        onDeleteRow: _rows <= 1 ? null : _deleteSelectedRow,
        onDeleteColumn: _columns <= 1 ? null : _deleteSelectedColumn,
        onCycleHeaderRows: () => _setHeaderRows(nextHeaderRows),
        onPaste: () => _replaceWithClipboard(context),
        onProperties: widget.onEdit,
        onDone: _deactivateTable,
        onDeleteTable: widget.onDelete,
      ),
    );
  }

  bool _sameCells(List<List<String>> a, List<List<String>> b) {
    if (a.length != b.length) return false;
    for (var row = 0; row < a.length; row++) {
      if (a[row].length != b[row].length) return false;
      for (var column = 0; column < a[row].length; column++) {
        if (a[row][column] != b[row][column]) return false;
      }
    }
    return true;
  }

  void _commitNow() {
    _commitTimer?.cancel();
    final draft = _currentDraft();
    final existingCells = _academicTableCellsForBlock(widget.block);
    final metadataUnchanged =
        draft.caption == _academicCaptionForBlock(widget.block) &&
        draft.label == _academicLabelForBlock(widget.block) &&
        draft.note == _academicNoteForBlock(widget.block) &&
        draft.captionPosition == _academicCaptionPositionForBlock(widget.block, defaultPosition: 'above') &&
        draft.headerRows == _academicHeaderRowsForBlock(widget.block);
    if (metadataUnchanged && _sameCells(draft.cells, existingCells)) return;
    widget.onTableChanged(draft);
  }

  void _selectCell(int row, int column) {
    if (!widget.editable) return;
    setState(() {
      _tableActive = true;
      _selectedRow = row.clamp(0, math.max(0, _rows - 1)).toInt();
      _selectedColumn = column.clamp(0, math.max(0, _columns - 1)).toInt();
    });
    _publishTableContext();
  }

  void _deactivateTable() {
    if (!_tableActive) return;
    _commitNow();
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onActiveTableContextChanged(null);
    if (!mounted) return;
    setState(() => _tableActive = false);
  }

  void _mutateCells(List<List<String>> nextCells) {
    setState(() => _replaceGrid(nextCells));
    _commitNow();
    _publishTableContext();
  }

  void _insertRow(int index) {
    final current = _currentCells;
    final safeIndex = index.clamp(0, current.length).toInt();
    final columns = current.isEmpty ? 3 : current.first.length;
    current.insert(safeIndex, List<String>.filled(columns, ''));
    _selectedRow = safeIndex;
    _mutateCells(current);
  }

  void _insertColumn(int index) {
    final current = _currentCells;
    final safeIndex = index.clamp(0, _columns).toInt();
    for (final row in current) {
      row.insert(safeIndex, '');
    }
    _selectedColumn = safeIndex;
    _mutateCells(current);
  }

  void _deleteSelectedRow() {
    if (_rows <= 1) return;
    final current = _currentCells..removeAt(_selectedRow.clamp(0, _rows - 1).toInt());
    _selectedRow = _selectedRow.clamp(0, math.max(0, current.length - 1)).toInt();
    _mutateCells(current);
  }

  void _deleteSelectedColumn() {
    if (_columns <= 1) return;
    final current = _currentCells;
    final index = _selectedColumn.clamp(0, _columns - 1).toInt();
    for (final row in current) {
      if (index < row.length) row.removeAt(index);
    }
    _selectedColumn = _selectedColumn.clamp(0, math.max(0, _columns - 2)).toInt();
    _mutateCells(current);
  }

  Future<void> _replaceWithClipboard(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Clipboard does not contain table text.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final parsed = _parseAcademicTableCells(text, rows: _rows, columns: _columns);
    _mutateCells(parsed);
  }

  void _setHeaderRows(int value) {
    setState(() => _headerRows = value.clamp(0, _rows).toInt());
    _commitNow();
    _publishTableContext();
  }

  Widget _buildFloatingToolbar(BuildContext context) {
    if (!widget.editable || !_tableActive) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxHeaderRows = math.min(3, _rows);
    final nextHeaderRows = _headerRows >= maxHeaderRows ? 0 : _headerRows + 1;

    return SizedBox(
      height: 46,
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: colorScheme.surface.withValues(alpha: 0.98),
          elevation: 8,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.85)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Cell ${_columnName(_selectedColumn)}${_selectedRow + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _TableContextButton(
                    tooltip: 'Insert row above',
                    icon: Icons.vertical_align_top_rounded,
                    onPressed: () => _insertRow(_selectedRow),
                  ),
                  _TableContextButton(
                    tooltip: 'Insert row below',
                    icon: Icons.vertical_align_bottom_rounded,
                    onPressed: () => _insertRow(_selectedRow + 1),
                  ),
                  _TableContextButton(
                    tooltip: 'Insert column left',
                    icon: Icons.align_horizontal_left_rounded,
                    onPressed: () => _insertColumn(_selectedColumn),
                  ),
                  _TableContextButton(
                    tooltip: 'Insert column right',
                    icon: Icons.align_horizontal_right_rounded,
                    onPressed: () => _insertColumn(_selectedColumn + 1),
                  ),
                  _TableContextButton(
                    tooltip: 'Delete selected row',
                    icon: Icons.table_rows_outlined,
                    onPressed: _rows <= 1 ? null : _deleteSelectedRow,
                  ),
                  _TableContextButton(
                    tooltip: 'Delete selected column',
                    icon: Icons.view_column_outlined,
                    onPressed: _columns <= 1 ? null : _deleteSelectedColumn,
                  ),
                  TextButton(
                    onPressed: () => _setHeaderRows(nextHeaderRows),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      textStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    child: Text('Headers $_headerRows'),
                  ),
                  _TableContextButton(
                    tooltip: 'Replace table with clipboard data',
                    icon: Icons.content_paste_go_outlined,
                    onPressed: () => _replaceWithClipboard(context),
                  ),
                  _TableContextButton(
                    tooltip: 'Table properties',
                    icon: Icons.tune_rounded,
                    onPressed: widget.onEdit,
                  ),
                  _TableContextButton(
                    tooltip: 'Done editing table',
                    icon: Icons.check_rounded,
                    onPressed: _deactivateTable,
                  ),
                  _TableContextButton(
                    tooltip: 'Delete table',
                    icon: Icons.delete_outline_rounded,
                    danger: true,
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditableGrid(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final safeHeaderRows = _headerRows.clamp(0, _rows).toInt();
    const rowHeaderWidth = 30.0;
    const cellHeight = 40.0;
    const minCellWidth = 92.0;
    const maxCellWidth = 220.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 560.0;
        final activeRowHeaderWidth = _tableActive ? rowHeaderWidth : 0.0;
        final baseGridWidth = math.max(260.0, availableWidth);
        final idealCellWidth = (baseGridWidth - activeRowHeaderWidth) / math.max(1, _columns);
        final cellWidth = idealCellWidth.clamp(minCellWidth, maxCellWidth).toDouble();
        final contentWidth = activeRowHeaderWidth + cellWidth * math.max(1, _columns);
        final tableWidth = math.max(baseGridWidth, contentWidth);

        Widget headerCell(String text, {bool selected = false, double? width}) {
          return Container(
            width: width ?? cellWidth,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.46)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.64), width: 0.7),
            ),
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        Widget cell(int rowIndex, int columnIndex) {
          final selected = _tableActive && rowIndex == _selectedRow && columnIndex == _selectedColumn;
          final isHeader = rowIndex < safeHeaderRows;
          return Container(
            width: cellWidth,
            height: cellHeight,
            decoration: BoxDecoration(
              color: isHeader
                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.24)
                  : colorScheme.surface,
              border: Border.all(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.72),
                width: selected ? 1.5 : 0.75,
              ),
            ),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _selectCell(rowIndex, columnIndex),
              child: TextField(
                controller: _cellControllers[rowIndex][columnIndex],
                textInputAction: TextInputAction.next,
                maxLines: 1,
                onTap: () => _selectCell(rowIndex, columnIndex),
                onTapOutside: (_) => _deactivateTable(),
                onSubmitted: (_) => _commitNow(),
                onChanged: (_) => _scheduleCommit(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                  height: 1.16,
                ),
              ),
            ),
          );
        }

        final table = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_tableActive)
              Row(
                children: [
                  headerCell('', width: rowHeaderWidth),
                  for (var columnIndex = 0; columnIndex < _columns; columnIndex++)
                    GestureDetector(
                      onTap: () => _selectCell(_selectedRow, columnIndex),
                      child: headerCell(_columnName(columnIndex), selected: columnIndex == _selectedColumn),
                    ),
                ],
              ),
            for (var rowIndex = 0; rowIndex < _rows; rowIndex++)
              Row(
                children: [
                  if (_tableActive)
                    GestureDetector(
                      onTap: () => _selectCell(rowIndex, _selectedColumn),
                      child: headerCell('${rowIndex + 1}', selected: rowIndex == _selectedRow, width: rowHeaderWidth),
                    ),
                  for (var columnIndex = 0; columnIndex < _columns; columnIndex++)
                    cell(rowIndex, columnIndex),
                ],
              ),
          ],
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.86)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: table,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _academicLabelForBlock(widget.block);
    final note = _academicNoteForBlock(widget.block);
    final captionPosition = _academicCaptionPositionForBlock(widget.block, defaultPosition: 'above');
    final cells = _currentCells;
    final omittedRows = math.max(0, cells.length - 10);
    final caption = _AcademicCaptionLine(text: _academicObjectCaptionLine(widget.document, widget.block));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (captionPosition == 'above') ...[
            caption,
            const SizedBox(height: 8),
          ],
          widget.editable
              ? CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.escape): _deactivateTable,
                  },
                  child: TapRegion(
                    groupId: this,
                    onTapOutside: (_) => _deactivateTable(),
                    child: TextFieldTapRegion(
                      child: _buildEditableGrid(context),
                    ),
                  ),
                )
              : _AcademicTablePreview(
                  cells: cells,
                  headerRows: _headerRows,
                ),
          if (!widget.editable && omittedRows > 0) ...[
            const SizedBox(height: 4),
            _AcademicObjectMetaLine(parts: ['+$omittedRows more row${omittedRows == 1 ? '' : 's'} not shown in preview']),
          ],
          if (captionPosition == 'below') ...[
            const SizedBox(height: 8),
            caption,
          ],
          if (note.isNotEmpty || label.isNotEmpty) ...[
            const SizedBox(height: 4),
            _AcademicObjectMetaLine(
              parts: [
                if (label.isNotEmpty) 'Label: $label',
                if (note.isNotEmpty) 'Note: $note',
              ],
            ),
          ],
        ],
      ),
    );
  }
}


class _TableContextButton extends StatelessWidget {
  const _TableContextButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = danger ? colorScheme.error : colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        color: foreground,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _TableMiniButton extends StatelessWidget {
  const _TableMiniButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _AcademicCaptionLine extends StatelessWidget {
  const _AcademicCaptionLine({
    required this.text,
    this.alignment = TextAlign.left,
  });

  final String text;
  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignment,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.28,
          ),
    );
  }
}

class _AcademicObjectMetaLine extends StatelessWidget {
  const _AcademicObjectMetaLine({
    required this.parts,
    this.textAlign = TextAlign.left,
  });

  final List<String> parts;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      parts.join(' · '),
      textAlign: textAlign,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.25,
          ),
    );
  }
}

class _AcademicObjectActionStrip extends StatelessWidget {
  const _AcademicObjectActionStrip({
    required this.editTooltip,
    required this.deleteTooltip,
    required this.onEdit,
    required this.onDelete,
  });

  final String editTooltip;
  final String deleteTooltip;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            offset: const Offset(0, 3),
            color: colorScheme.shadow.withValues(alpha: 0.10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: editTooltip,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: deleteTooltip,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _AcademicFigureEmptyPreview extends StatelessWidget {
  const _AcademicFigureEmptyPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

class _AcademicFigurePreview extends StatelessWidget {
  const _AcademicFigurePreview({required this.block});

  final TextSystemBlock block;

  bool _isNetworkImage(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  double _widthFactor() {
    return switch (_academicFigureSizeForBlock(block)) {
      'small' => 0.52,
      'large' => 0.88,
      'fullWidth' => 1.0,
      _ => 0.72,
    };
  }

  double _previewHeight() {
    return switch (_academicFigureSizeForBlock(block)) {
      'small' => 82.0,
      'large' => 156.0,
      'fullWidth' => 188.0,
      _ => 118.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final source = _academicSourceForBlock(block);
    final imagePath = _academicImagePathForBlock(block);
    final localImageExists = _academicLocalImageExists(imagePath);
    final sourceIsNetworkImage = source.isNotEmpty && _isNetworkImage(source);
    final fileLabel = _academicFileName(imagePath);
    final placeholderLabel = imagePath.isNotEmpty
        ? (fileLabel.isEmpty ? 'Image file not found' : '$fileLabel not found')
        : (source.isEmpty ? 'Image placeholder' : source);

    Widget imageChild() {
      if (localImageExists) {
        return Image.file(
          File(imagePath),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _AcademicFigureEmptyPreview(label: placeholderLabel),
        );
      }
      if (sourceIsNetworkImage) {
        return Image.network(
          source,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _AcademicFigureEmptyPreview(label: source),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const _AcademicFigureEmptyPreview(label: 'Loading image…');
          },
        );
      }
      return _AcademicFigureEmptyPreview(label: placeholderLabel);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 560.0;
        return Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth * _widthFactor(),
              minHeight: 48,
              maxHeight: _previewHeight(),
            ),
            child: SizedBox(
              height: _previewHeight(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: imageChild(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AcademicTablePreview extends StatelessWidget {
  const _AcademicTablePreview({
    required this.cells,
    required this.headerRows,
  });

  final List<List<String>> cells;
  final int headerRows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final safeCells = cells.isEmpty
        ? List<List<String>>.generate(3, (_) => List<String>.filled(3, ''))
        : cells;
    final visibleRows = safeCells.take(10).toList();
    final safeHeaderRows = headerRows.clamp(0, visibleRows.length).toInt();
    final columnCount = visibleRows.fold<int>(0, (maxColumns, row) => math.max(maxColumns, row.length)).clamp(1, 10).toInt();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outline),
      ),
      child: Table(
        border: TableBorder(
          horizontalInside: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
          verticalInside: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var rowIndex = 0; rowIndex < visibleRows.length; rowIndex++)
            TableRow(
              decoration: BoxDecoration(
                color: rowIndex < safeHeaderRows
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.48)
                    : colorScheme.surface,
              ),
              children: [
                for (var columnIndex = 0; columnIndex < columnCount; columnIndex++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Text(
                      columnIndex < visibleRows[rowIndex].length && visibleRows[rowIndex][columnIndex].isNotEmpty
                          ? visibleRows[rowIndex][columnIndex]
                          : ' ',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: rowIndex < safeHeaderRows ? FontWeight.w700 : FontWeight.w400,
                            height: 1.25,
                          ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AcademicObjectPill extends StatelessWidget {
  const _AcademicObjectPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _PageMarginLayer extends StatelessWidget {
  const _PageMarginLayer({
    required this.pageWidth,
    required this.margins,
    required this.markers,
  });

  final double pageWidth;
  final EdgeInsets margins;
  final List<_PageMarginMarkerData> markers;

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty || margins.right < 34) return const SizedBox.shrink();

    final laneWidth = math.max(28.0, math.min(76.0, margins.right - 12));
    final laneLeft = math.min(
      pageWidth - laneWidth - 6,
      pageWidth - margins.right + 8,
    );

    final placedTopByKey = <String, double>{};
    var nextAvailableTop = margins.top;
    const markerHeight = 22.0;
    const markerGap = 3.0;
    for (final marker in markers) {
      final desiredTop = marker.top.clamp(margins.top, double.infinity).toDouble();
      final placedTop = math.max(desiredTop, nextAvailableTop);
      placedTopByKey[marker.key] = placedTop;
      nextAvailableTop = placedTop + markerHeight + markerGap;
    }

    return Stack(
      children: [
        Positioned(
          left: laneLeft,
          top: margins.top,
          width: laneWidth,
          bottom: margins.bottom,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.34),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final marker in markers)
          Positioned(
            key: ValueKey<String>('margin-marker-${marker.key}'),
            left: laneLeft + 5,
            top: placedTopByKey[marker.key] ?? marker.top.clamp(margins.top, double.infinity).toDouble(),
            width: math.max(20.0, laneWidth - 10),
            child: _PageMarginMarker(marker: marker),
          ),
      ],
    );
  }
}

class _PageMarginMarker extends StatelessWidget {
  const _PageMarginMarker({required this.marker});

  final _PageMarginMarkerData marker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    late final IconData icon;
    late final Color color;
    switch (marker.type) {
      case _PageMarginMarkerType.todo:
        icon = Icons.task_alt_rounded;
        color = colorScheme.tertiary;
        break;
      case _PageMarginMarkerType.citation:
        icon = Icons.format_quote_rounded;
        color = const Color(0xFF8A6D1D);
        break;
      case _PageMarginMarkerType.reference:
        icon = Icons.link_rounded;
        color = colorScheme.primary;
        break;
      case _PageMarginMarkerType.footnote:
        icon = Icons.sticky_note_2_outlined;
        color = colorScheme.secondary;
        break;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color.withValues(alpha: 0.82)),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                marker.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  height: 1,
                  color: color.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PagedCrossBlockSelectionOverlay extends StatelessWidget {
  const _PagedCrossBlockSelectionOverlay({
    required this.document,
    required this.page,
    required this.pageSetup,
    required this.margins,
    required this.selection,
  });

  final TextSystemDocument document;
  final TextSystemPagedBlockPage page;
  final TextSystemPageSetup pageSetup;
  final EdgeInsets margins;
  final TextSystemPagedDocumentSelection selection;

  @override
  Widget build(BuildContext context) {
    final range = selection.toDocumentRange(document);
    if (range == null || range.isCollapsed) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.20);
    final rects = TextSystemDocumentSelectionGeometry.selectionRectsForPage(
      context: context,
      document: document,
      page: page,
      pageSetup: pageSetup,
      margins: margins,
      range: range,
    );

    if (rects.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: Stack(
        children: [
          for (final rect in rects)
            Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }


}


class _PageFootnotesOverlay extends StatelessWidget {
  const _PageFootnotesOverlay({
    required this.textController,
    required this.footnotes,
    required this.margins,
    required this.editable,
  });

  final TextSystemController textController;
  final List<TextSystemPagedFootnote> footnotes;
  final EdgeInsets margins;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    if (footnotes.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxHeight = math.min(132.0, 28.0 + footnotes.length * 28.0);

    return Positioned(
      left: margins.left,
      right: margins.right,
      bottom: margins.bottom + 10,
      child: IgnorePointer(
        ignoring: !editable,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.transparent),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108,
                  child: Divider(
                    height: 7,
                    thickness: 0.8,
                    color: colorScheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: footnotes.length,
                    itemBuilder: (context, index) {
                      final footnote = footnotes[index];
                      return _FootnoteLineEditor(
                        key: ValueKey<String>('footnote-${footnote.footnoteId}'),
                        textController: textController,
                        footnote: footnote,
                        editable: editable,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.2,
                          color: colorScheme.onSurface.withValues(alpha: 0.82),
                          height: 1.16,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FootnoteLineEditor extends StatefulWidget {
  const _FootnoteLineEditor({
    super.key,
    required this.textController,
    required this.footnote,
    required this.editable,
    required this.style,
  });

  final TextSystemController textController;
  final TextSystemPagedFootnote footnote;
  final bool editable;
  final TextStyle? style;

  @override
  State<_FootnoteLineEditor> createState() => _FootnoteLineEditorState();
}

class _FootnoteLineEditorState extends State<_FootnoteLineEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.footnote.text);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _FootnoteLineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.footnote.text != _controller.text) {
      _controller.text = widget.footnote.text;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                _academicFootnoteNumber(widget.footnote.number),
                textAlign: TextAlign.left,
                style: widget.style?.copyWith(
                  fontSize: (widget.style?.fontSize ?? 10.2) * 0.88,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.editable,
              minLines: 1,
              maxLines: 2,
              style: widget.style,
              decoration: InputDecoration(
                isCollapsed: true,
                hintText: 'Footnote text',
                hintStyle: widget.style?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.50),
                  fontStyle: FontStyle.italic,
                ),
                border: InputBorder.none,
              ),
              onChanged: (value) => widget.textController.updateBlockText(
                widget.footnote.blockId,
                value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _PageFurnitureOverlay extends StatelessWidget {
  const _PageFurnitureOverlay({
    required this.documentTitle,
    required this.sectionTitle,
    required this.physicalPageNumber,
    required this.pageNumber,
    required this.pageFurniture,
    required this.onPageFurnitureChanged,
    required this.headerFooterEditMode,
    required this.headerFooterEditTarget,
    required this.onHeaderFooterEditModeChanged,
    required this.onHeaderFooterEditTargetChanged,
    required this.margins,
  });

  final String documentTitle;
  final String sectionTitle;
  final int physicalPageNumber;
  final int pageNumber;
  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture>? onPageFurnitureChanged;
  final bool headerFooterEditMode;
  final TextSystemHeaderFooterZoneKind? headerFooterEditTarget;
  final ValueChanged<bool> onHeaderFooterEditModeChanged;
  final ValueChanged<TextSystemHeaderFooterZoneKind> onHeaderFooterEditTargetChanged;
  final EdgeInsets margins;

  void _updateZone(TextSystemHeaderFooterZoneKind kind, String text) {
    final settings = pageFurniture.headerFooter;
    final currentZone = settings.zoneFor(kind: kind, physicalPageNumber: physicalPageNumber);
    final nextSettings = settings.updateZone(
      kind: kind,
      physicalPageNumber: physicalPageNumber,
      zone: currentZone.copyWith(enabled: true, text: text),
    );
    onPageFurnitureChanged?.call(pageFurniture.copyWith(headerFooter: nextSettings));
  }

  String _resolveTokens(String rawText) {
    return rawText
        .replaceAll('{{pageNumber}}', '$pageNumber')
        .replaceAll('{{documentTitle}}', documentTitle.trim().isEmpty ? 'Untitled document' : documentTitle.trim())
        .replaceAll('{{sectionTitle}}', sectionTitle.trim().isEmpty ? 'Section' : sectionTitle.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.48),
      fontWeight: FontWeight.w600,
    );
    final children = <Widget>[];

    final headerFooter = pageFurniture.headerFooter;
    if (headerFooter.enabled) {
      final headerZone = headerFooter.zoneFor(
        kind: TextSystemHeaderFooterZoneKind.header,
        physicalPageNumber: physicalPageNumber,
      );
      final footerZone = headerFooter.zoneFor(
        kind: TextSystemHeaderFooterZoneKind.footer,
        physicalPageNumber: physicalPageNumber,
      );

      if (headerZone.enabled) {
        children.add(
          Positioned(
            left: margins.left,
            right: margins.right,
            top: math.max(6, margins.top * 0.20),
            child: _HeaderFooterZoneEditor(
              rawText: headerZone.text,
              resolvedText: _resolveTokens(headerZone.text),
              placeholder: physicalPageNumber == 1 && headerFooter.differentFirstPage
                  ? 'First page header'
                  : 'Header — use {{documentTitle}} or {{sectionTitle}}',
              textAlign: TextAlign.left,
              style: labelStyle,
              enabled: onPageFurnitureChanged != null,
              editMode: headerFooterEditMode,
              focusedForEdit: headerFooterEditTarget == TextSystemHeaderFooterZoneKind.header,
              onEnterEditMode: () => onHeaderFooterEditTargetChanged(TextSystemHeaderFooterZoneKind.header),
              onExitEditMode: () => onHeaderFooterEditModeChanged(false),
              onChanged: (value) => _updateZone(TextSystemHeaderFooterZoneKind.header, value),
            ),
          ),
        );
      }

      if (footerZone.enabled) {
        children.add(
          Positioned(
            left: margins.left,
            right: margins.right,
            bottom: math.max(6, margins.bottom * 0.20),
            child: _HeaderFooterZoneEditor(
              rawText: footerZone.text,
              resolvedText: _resolveTokens(footerZone.text),
              placeholder: physicalPageNumber == 1 && headerFooter.differentFirstPage
                  ? 'First page footer'
                  : 'Footer — use {{pageNumber}}',
              textAlign: TextAlign.center,
              style: labelStyle,
              enabled: onPageFurnitureChanged != null,
              editMode: headerFooterEditMode,
              focusedForEdit: headerFooterEditTarget == TextSystemHeaderFooterZoneKind.footer,
              onEnterEditMode: () => onHeaderFooterEditTargetChanged(TextSystemHeaderFooterZoneKind.footer),
              onExitEditMode: () => onHeaderFooterEditModeChanged(false),
              onChanged: (value) => _updateZone(TextSystemHeaderFooterZoneKind.footer, value),
            ),
          ),
        );
      }
    }

    if (pageFurniture.headerMode == TextSystemPageHeaderMode.documentTitle &&
        documentTitle.trim().isNotEmpty) {
      children.add(
        Positioned(
          left: margins.left,
          right: margins.right,
          top: math.max(8, margins.top * 0.50),
          child: IgnorePointer(
            child: Text(
              documentTitle.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: labelStyle,
            ),
          ),
        ),
      );
    }

    final pageNumbers = pageFurniture.pageNumbers;
    if (pageNumbers.visibleOnPage(pageNumber)) {
      final pageLabel = pageNumbers.labelForPage(pageNumber);
      switch (pageNumbers.position) {
        case TextSystemPageNumberPosition.topRight:
          children.add(
            Positioned(
              right: margins.right,
              top: math.max(8, margins.top * 0.50),
              child: IgnorePointer(
                child: Text(pageLabel, textAlign: TextAlign.right, style: labelStyle),
              ),
            ),
          );
        case TextSystemPageNumberPosition.bottomCenter:
          children.add(
            Positioned(
              left: 0,
              right: 0,
              bottom: math.max(8, margins.bottom * 0.50),
              child: IgnorePointer(
                child: Text(pageLabel, textAlign: TextAlign.center, style: labelStyle),
              ),
            ),
          );
        case TextSystemPageNumberPosition.bottomRight:
          children.add(
            Positioned(
              right: margins.right,
              bottom: math.max(8, margins.bottom * 0.50),
              child: IgnorePointer(
                child: Text(pageLabel, textAlign: TextAlign.right, style: labelStyle),
              ),
            ),
          );
      }
    }

    return Stack(children: children);
  }
}


class _HeaderFooterZoneEditor extends StatefulWidget {
  const _HeaderFooterZoneEditor({
    required this.rawText,
    required this.resolvedText,
    required this.placeholder,
    required this.textAlign,
    required this.style,
    required this.enabled,
    required this.editMode,
    required this.focusedForEdit,
    required this.onEnterEditMode,
    required this.onExitEditMode,
    required this.onChanged,
  });

  final String rawText;
  final String resolvedText;
  final String placeholder;
  final TextAlign textAlign;
  final TextStyle? style;
  final bool enabled;
  final bool editMode;
  final bool focusedForEdit;
  final VoidCallback onEnterEditMode;
  final VoidCallback onExitEditMode;
  final ValueChanged<String> onChanged;

  @override
  State<_HeaderFooterZoneEditor> createState() => _HeaderFooterZoneEditorState();
}

class _HeaderFooterZoneEditorState extends State<_HeaderFooterZoneEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _hovered = false;

  bool get _editing => widget.editMode && widget.enabled;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.rawText);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _HeaderFooterZoneEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_focusNode.hasFocus && widget.rawText != _controller.text) {
      _controller.text = widget.rawText;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }

    final shouldTakeFocus = widget.editMode &&
        widget.focusedForEdit &&
        (!oldWidget.editMode || !oldWidget.focusedForEdit);
    if (shouldTakeFocus && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.editMode || !widget.focusedForEdit || !widget.enabled) return;
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      });
    }
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_focusNode.hasFocus && widget.editMode) {
      widget.onExitEditMode();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _enterEditMode() {
    if (!widget.enabled) return;
    widget.onEnterEditMode();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayText = widget.resolvedText.trim();
    final showingPlaceholder = displayText.isEmpty && !_editing;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTap: _enterEditMode,
        onTap: _editing ? () => _focusNode.requestFocus() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 26),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _editing
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.62)
                : _hovered && widget.enabled
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.24)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _editing
                  ? colorScheme.primary.withValues(alpha: 0.42)
                  : _hovered && widget.enabled
                      ? colorScheme.outlineVariant.withValues(alpha: 0.58)
                      : Colors.transparent,
            ),
          ),
          child: _editing
              ? TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlign: widget.textAlign,
                  style: widget.style,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onTapOutside: (_) => _focusNode.unfocus(),
                  onEditingComplete: () => _focusNode.unfocus(),
                  onChanged: widget.onChanged,
                )
              : Row(
                  mainAxisAlignment: switch (widget.textAlign) {
                    TextAlign.center => MainAxisAlignment.center,
                    TextAlign.right || TextAlign.end => MainAxisAlignment.end,
                    _ => MainAxisAlignment.start,
                  },
                  children: [
                    Flexible(
                      child: Text(
                        showingPlaceholder ? widget.placeholder : displayText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: widget.textAlign,
                        style: widget.style?.copyWith(
                          color: showingPlaceholder
                              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.44)
                              : widget.style?.color,
                          fontStyle: showingPlaceholder ? FontStyle.italic : widget.style?.fontStyle,
                        ),
                      ),
                    ),
                    if (_hovered && widget.enabled && !_editing) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.54),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}


class _PagedBlockFragmentView extends StatelessWidget {
  const _PagedBlockFragmentView({
    super.key,
    required this.textController,
    required this.block,
    required this.fragment,
    required this.pageSetup,
    required this.editable,
    required this.selectedObjectBlockId,
    required this.blockRangeSelected,
    required this.navigation,
    required this.restoreCaretAnchor,
    required this.restoreSelectionAnchor,
    required this.onActiveCaretChanged,
    required this.onActiveSelectionChanged,
    required this.onActiveFieldChanged,
    required this.onRequestCaretRestore,
    required this.onRequestSelectionRestore,
    required this.onRestoreSelectionConsumed,
    required this.onBlockSelectionPointerDown,
    required this.onSelectObjectBlock,
    required this.onDuplicateSelectedObject,
    required this.onMoveSelectedObjectUp,
    required this.onMoveSelectedObjectDown,
    required this.onDeleteSelectedObject,
    required this.onActiveTableContextChanged,
    this.onOpenReferenceTarget,
  });

  final TextSystemController textController;
  final TextSystemBlock? block;
  final TextSystemPagedBlockFragment fragment;
  final TextSystemPageSetup pageSetup;
  final bool editable;
  final String? selectedObjectBlockId;
  final bool blockRangeSelected;
  final _PagedFragmentNavigation navigation;
  final TextSystemPagedCaretAnchor? restoreCaretAnchor;
  final TextSystemPagedSelectionAnchor? restoreSelectionAnchor;
  final ValueChanged<TextSystemPagedCaretAnchor> onActiveCaretChanged;
  final ValueChanged<TextSystemPagedSelectionAnchor> onActiveSelectionChanged;
  final ValueChanged<_PagedEditableBlockFieldState?> onActiveFieldChanged;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRequestSelectionRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRestoreSelectionConsumed;
  final void Function(String blockId, PointerDownEvent event) onBlockSelectionPointerDown;
  final ValueChanged<String> onSelectObjectBlock;
  final VoidCallback onDuplicateSelectedObject;
  final VoidCallback onMoveSelectedObjectUp;
  final VoidCallback onMoveSelectedObjectDown;
  final VoidCallback onDeleteSelectedObject;
  final ValueChanged<_ActiveTableEditingContext?> onActiveTableContextChanged;
  final ValueChanged<TextSystemInlineReferenceMark>? onOpenReferenceTarget;

  int _orderedListNumberFor(TextSystemBlock block) {
    if (block.type != TextSystemBlockType.listItem || block.metadata['ordered'] != true) {
      return 1;
    }

    final blocks = textController.document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == block.id);
    if (index < 0) return 1;

    final groupId = block.metadata['listGroupId'];
    var count = 1;

    for (var i = index - 1; i >= 0; i--) {
      final previous = blocks[i];
      if (previous.type != TextSystemBlockType.listItem ||
          previous.metadata['ordered'] != true) {
        break;
      }

      if (groupId != null && previous.metadata['listGroupId'] != groupId) {
        break;
      }

      count++;
    }

    return count;
  }

  bool get _isEditableFragment {
    final resolvedBlock = block;
    if (!editable || resolvedBlock == null || fragment.oversized) return false;

    final safeStart = fragment.visualTextStartOffset.clamp(0, resolvedBlock.text.length).toInt();
    final safeEnd = fragment.visualTextEndOffset.clamp(safeStart, resolvedBlock.text.length).toInt();
    if (safeStart > safeEnd) return false;

    if (fragment.isSplitFragment) {
      return switch (resolvedBlock.type) {
        TextSystemBlockType.paragraph ||
        TextSystemBlockType.listItem ||
        TextSystemBlockType.todo ||
        TextSystemBlockType.quote => true,
        _ => false,
      };
    }

    return switch (resolvedBlock.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  bool get _supportsWholeBlockSelection {
    final resolvedBlock = block;
    if (resolvedBlock == null) return false;
    return _isDocumentObjectBlock(resolvedBlock) ||
        _isPageBreakBlock(resolvedBlock) ||
        _isSectionBreakBlock(resolvedBlock);
  }

  Widget _withBlockSelectionChrome(BuildContext context, Widget child) {
    if (!_supportsWholeBlockSelection) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => onBlockSelectionPointerDown(fragment.blockId, event),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (blockRangeSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedBlock = block ?? TextSystemBlock.paragraph(id: fragment.blockId, text: fragment.text);

    if (_isEquationBlock(resolvedBlock)) {
      return _withBlockSelectionChrome(
        context,
        _AcademicEquationBlockChrome(
        textController: textController,
        block: resolvedBlock,
        document: textController.document,
        editable: editable,
        selected: selectedObjectBlockId == resolvedBlock.id,
        onSelect: () => onSelectObjectBlock(resolvedBlock.id),
        onDuplicate: onDuplicateSelectedObject,
        onMoveUp: onMoveSelectedObjectUp,
        onMoveDown: onMoveSelectedObjectDown,
        onDeleteSelected: onDeleteSelectedObject,
        onRequestCaretRestore: onRequestCaretRestore,
        onCaretBefore: () {
          final anchor = _ensureCaretBeforeDocumentObject(
            textController,
            resolvedBlock.id,
            label: 'Create paragraph before equation',
          );
          onRequestSelectionRestore(TextSystemPagedSelectionAnchor.collapsed(
            blockId: anchor.blockId,
            textOffset: anchor.textOffset,
          ));
        },
        onCaretAfter: () {
          final anchor = _ensureCaretAfterDocumentObject(
            textController,
            resolvedBlock.id,
            label: 'Create paragraph after equation',
          );
          onRequestSelectionRestore(TextSystemPagedSelectionAnchor.collapsed(
            blockId: anchor.blockId,
            textOffset: anchor.textOffset,
          ));
        },
      ),
      );
    }

    if (_isAcademicObjectBlock(resolvedBlock)) {
      return _withBlockSelectionChrome(
        context,
        _AcademicObjectBlockChrome(
        textController: textController,
        block: resolvedBlock,
        document: textController.document,
        editable: editable,
        selected: selectedObjectBlockId == resolvedBlock.id,
        onSelect: () => onSelectObjectBlock(resolvedBlock.id),
        onDuplicate: onDuplicateSelectedObject,
        onMoveUp: onMoveSelectedObjectUp,
        onMoveDown: onMoveSelectedObjectDown,
        onDeleteSelected: onDeleteSelectedObject,
        onRequestCaretRestore: onRequestCaretRestore,
        onCaretBefore: () {
          final anchor = _ensureCaretBeforeDocumentObject(
            textController,
            resolvedBlock.id,
            label: 'Create paragraph before ${_academicObjectKind(resolvedBlock)}',
          );
          onRequestSelectionRestore(TextSystemPagedSelectionAnchor.collapsed(
            blockId: anchor.blockId,
            textOffset: anchor.textOffset,
          ));
        },
        onCaretAfter: () {
          final anchor = _ensureCaretAfterDocumentObject(
            textController,
            resolvedBlock.id,
            label: 'Create paragraph after ${_academicObjectKind(resolvedBlock)}',
          );
          onRequestSelectionRestore(TextSystemPagedSelectionAnchor.collapsed(
            blockId: anchor.blockId,
            textOffset: anchor.textOffset,
          ));
        },
        onActiveTableContextChanged: onActiveTableContextChanged,
      ),
      );
    }

    if (_isPageBreakBlock(resolvedBlock)) {
      return _withBlockSelectionChrome(
        context,
        _PageBreakBlockChip(
        editable: editable,
        mergesAdjacentOnDelete: resolvedBlock.metadata['mergeAdjacentOnDelete'] == true,
        onDelete: editable
            ? () {
                final target = textController.removePageBreak(resolvedBlock.id);
                if (target == null) return;
                onRequestCaretRestore(
                  TextSystemPagedCaretAnchor(
                    blockId: target.blockId,
                    textOffset: target.offset,
                  ),
                );
              }
            : null,
      ),
      );
    }

    if (_isSectionBreakBlock(resolvedBlock)) {
      return _withBlockSelectionChrome(
        context,
        _SectionBreakBlockChip(
        block: resolvedBlock,
        editable: editable,
        onDelete: editable
            ? () {
                final target = textController.removeSectionBreak(resolvedBlock.id);
                if (target == null) return;
                onRequestCaretRestore(
                  TextSystemPagedCaretAnchor(
                    blockId: target.blockId,
                    textOffset: target.offset,
                  ),
                );
              }
            : null,
      ),
      );
    }

    final style = TextSystemLayoutStyleResolver.blockStyle(
      context: context,
      block: resolvedBlock,
      pageSetup: pageSetup,
    );

    final Widget textChild = _isEditableFragment
        ? _PagedEditableBlockField(
            block: resolvedBlock,
            fragment: fragment,
            textController: textController,
            style: style,
            navigation: navigation,
            editable: editable,
            restoreCaretAnchor: restoreCaretAnchor,
            restoreSelectionAnchor: restoreSelectionAnchor,
            onActiveCaretChanged: onActiveCaretChanged,
            onActiveSelectionChanged: onActiveSelectionChanged,
            onActiveFieldChanged: onActiveFieldChanged,
            onRequestCaretRestore: onRequestCaretRestore,
            onRequestSelectionRestore: onRequestSelectionRestore,
            onRestoreSelectionConsumed: onRestoreSelectionConsumed,
            onSelectObjectBlock: onSelectObjectBlock,
            onOpenReferenceTarget: onOpenReferenceTarget,
          )
        : SelectableText(
            fragment.text,
            style: style,
            textScaler: MediaQuery.textScalerOf(context),
          );

    final listAwareTextChild = switch (resolvedBlock.type) {
      TextSystemBlockType.listItem || TextSystemBlockType.todo => _ListTodoBlockShell(
          block: resolvedBlock,
          fragment: fragment,
          listNumber: _orderedListNumberFor(resolvedBlock),
          editable: editable,
          onToggleTodo: resolvedBlock.type == TextSystemBlockType.todo
              ? () {
                  textController.toggleTodoChecked(resolvedBlock.id);
                  onRequestSelectionRestore(
                    TextSystemPagedSelectionAnchor.collapsed(
                      blockId: resolvedBlock.id,
                      textOffset: fragment.visualTextStartOffset.clamp(0, resolvedBlock.text.length).toInt(),
                    ),
                  );
                }
              : null,
          child: textChild,
        ),
      _ => textChild,
    };

    final blockChromeChild = TextSystemEmbeddedTodoMetadata.isEmbeddedTodoBlock(resolvedBlock)
        ? _EmbeddedTodoBlockChrome(
            block: resolvedBlock,
            fragment: fragment,
            child: listAwareTextChild,
          )
        : listAwareTextChild;

    final decorated = switch (fragment.blockType) {
      TextSystemBlockType.quote => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colorScheme.primary.withValues(alpha: 0.35), width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: blockChromeChild,
          ),
        ),
      TextSystemBlockType.code => DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: blockChromeChild,
          ),
        ),
      _ => blockChromeChild,
    };

    return _withBlockSelectionChrome(
      context,
      Stack(
        children: [
          Positioned.fill(child: decorated),
        if (fragment.continuesFromPreviousPage)
          const Positioned(
            left: 0,
            top: 0,
            child: _ContinuationChip(label: 'continued'),
          ),
        if (fragment.continuesOnNextPage)
          const Positioned(
            right: 0,
            bottom: 0,
            child: _ContinuationChip(label: 'continues'),
          ),
        if (fragment.oversized)
          const Positioned(
            right: 0,
            top: 0,
            child: _ContinuationChip(label: 'oversized'),
          ),
        if (!_isEditableFragment && editable && block != null && !fragment.oversized)
          Positioned(
            right: 0,
            top: 0,
            child: _ContinuationChip(label: 'preview'),
          ),
        ],
      ),
    );
  }
}



class _EmbeddedTodoBlockChrome extends StatelessWidget {
  const _EmbeddedTodoBlockChrome({
    required this.block,
    required this.fragment,
    required this.child,
  });

  final TextSystemBlock block;
  final TextSystemPagedBlockFragment fragment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFirstFragment = !fragment.continuesFromPreviousPage;
    final todoTitle = block.text.trim();

    // This decoration is intentionally layout-neutral. The paged layout tree
    // already measured the text fragment height, so embedded app TODO chrome
    // must not add a header row, vertical padding, or any extra intrinsic
    // height. The margin layer now carries the richer TODO metadata affordance.
    return Semantics(
      container: true,
      label: todoTitle.isEmpty ? 'Embedded app TODO' : 'Embedded app TODO, $todoTitle',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.tertiary.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.tertiary.withValues(alpha: 0.68),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
            ),
            child: const SizedBox(width: 3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 4),
          child: child,
        ),
        if (isFirstFragment)
          Positioned(
            right: 4,
            top: 1,
            child: IgnorePointer(
              child: Icon(
                Icons.task_alt_rounded,
                size: 12,
                color: colorScheme.tertiary.withValues(alpha: 0.58),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListTodoBlockShell extends StatelessWidget {
  const _ListTodoBlockShell({
    required this.block,
    required this.fragment,
    required this.listNumber,
    required this.editable,
    required this.onToggleTodo,
    required this.child,
  });

  static const double markerWidth = 30;

  final TextSystemBlock block;
  final TextSystemPagedBlockFragment fragment;
  final int listNumber;
  final bool editable;
  final VoidCallback? onToggleTodo;
  final Widget child;

  bool get _showMarker => !fragment.continuesFromPreviousPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final marker = _buildMarker(theme, colorScheme);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: markerWidth, child: marker),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildMarker(ThemeData theme, ColorScheme colorScheme) {
    if (!_showMarker) {
      return const SizedBox.shrink();
    }

    if (block.type == TextSystemBlockType.todo) {
      final checked = block.checked == true;
      return Align(
        alignment: Alignment.topCenter,
        child: InkResponse(
          radius: 16,
          canRequestFocus: false,
          onTap: editable ? onToggleTodo : null,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 19,
              color: checked
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
            ),
          ),
        ),
      );
    }

    final ordered = block.metadata['ordered'] == true;
    final label = ordered ? '$listNumber.' : '•';

    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: ordered ? FontWeight.w700 : FontWeight.w800,
        ),
      ),
    );
  }
}



class _SectionBreakBlockChip extends StatelessWidget {
  const _SectionBreakBlockChip({
    required this.block,
    required this.editable,
    required this.onDelete,
  });

  final TextSystemBlock block;
  final bool editable;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final restart = block.metadata['restartPageNumbering'] != false;
    final startAt = block.metadata['pageNumberStartAt'] is int
        ? block.metadata['pageNumberStartAt'] as int
        : 1;
    final setupMode = block.metadata['pageSetupMode'] as String? ?? 'inherit';
    final description = restart
        ? 'Next page · numbering restarts at $startAt · setup $setupMode'
        : 'Next page · numbering continues · setup $setupMode';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.72)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.splitscreen_rounded, size: 18, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Section break · $description',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (editable && onDelete != null)
              IconButton(
                tooltip: block.metadata['mergeAdjacentOnDelete'] == true
                    ? 'Delete section break and merge the split text back together'
                    : 'Delete section break',
                onPressed: onDelete,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}


class _PageBreakBlockChip extends StatelessWidget {
  const _PageBreakBlockChip({
    required this.editable,
    required this.mergesAdjacentOnDelete,
    required this.onDelete,
  });

  final bool editable;
  final bool mergesAdjacentOnDelete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.26)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vertical_split_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 7),
              Text(
                mergesAdjacentOnDelete ? 'Page break · split paragraph' : 'Page break',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (editable && onDelete != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: mergesAdjacentOnDelete
                      ? 'Delete page break and merge the split text back together'
                      : 'Delete page break',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                  iconSize: 16,
                  onPressed: onDelete,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _PagedMarkedTextEditingController extends TextEditingController {
  _PagedMarkedTextEditingController({
    required String text,
    required TextSystemBlock block,
    required TextSystemPagedBlockFragment fragment,
    required TextStyle baseStyle,
  })  : _block = block,
        _fragment = fragment,
        _baseStyle = baseStyle,
        super(text: text);

  TextSystemBlock _block;
  TextSystemPagedBlockFragment _fragment;
  TextStyle _baseStyle;

  void updateRendering({
    required TextSystemBlock block,
    required TextSystemPagedBlockFragment fragment,
    required TextStyle baseStyle,
  }) {
    _block = block;
    _fragment = fragment;
    _baseStyle = baseStyle;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final effectiveStyle = style ?? _baseStyle;
    final safeStart = _fragment.visualTextStartOffset.clamp(0, _block.text.length).toInt();
    final safeEnd = _fragment.visualTextEndOffset.clamp(safeStart, _block.text.length).toInt();
    final visibleText = text;
    final atoms = _inlineAtomsForVisibleRange(
      text: visibleText,
      block: _block,
      globalStart: safeStart,
      globalEnd: safeEnd,
    );
    return TextSpan(
      style: effectiveStyle,
      children: atoms.isEmpty
          ? _markedSpansForRange(
              text: visibleText,
              block: _block,
              globalStart: safeStart,
              globalEnd: safeEnd,
              baseStyle: effectiveStyle,
            )
          : _editableInlineAtomSpansForRange(
              context: context,
              text: visibleText,
              block: _block,
              atoms: atoms,
              activeSelection: selection,
              globalStart: safeStart,
              globalEnd: safeEnd,
              baseStyle: effectiveStyle,
            ),
    );
  }
}


Iterable<RegExpMatch> _inlineMathMatchesForText(String text) {
  if (text.isEmpty) return const <RegExpMatch>[];
  return RegExp(r'\\\((.+?)\\\)').allMatches(text);
}

List<TextSystemRange> _inlineMathRangesForVisibleText({
  required String text,
  required int globalStart,
  required int globalEnd,
}) {
  if (text.isEmpty) return const <TextSystemRange>[];
  final ranges = <TextSystemRange>[];
  for (final match in _inlineMathMatchesForText(text)) {
    final localStart = match.start.clamp(0, text.length).toInt();
    final localEnd = match.end.clamp(localStart, text.length).toInt();
    final globalRange = TextSystemRange(globalStart + localStart, globalStart + localEnd)
        .intersection(TextSystemRange(globalStart, globalEnd));
    if (globalRange != null && !globalRange.isCollapsed) ranges.add(globalRange);
  }
  return ranges;
}

List<_InlineAtom> _inlineAtomsForVisibleRange({
  required String text,
  required TextSystemBlock block,
  required int globalStart,
  required int globalEnd,
}) {
  if (text.isEmpty) return const <_InlineAtom>[];

  final visibleRange = TextSystemRange(globalStart, globalEnd);
  final atoms = <_InlineAtom>[];

  for (final match in _inlineMathMatchesForText(text)) {
    final localStart = match.start.clamp(0, text.length).toInt();
    final localEnd = match.end.clamp(localStart, text.length).toInt();
    final globalRange = TextSystemRange(globalStart + localStart, globalStart + localEnd)
        .intersection(visibleRange);
    if (globalRange == null || globalRange.isCollapsed) continue;
    final sourceText = text.substring(localStart, localEnd);
    final latex = (match.group(1) ?? '').trim();
    atoms.add(
      _InlineAtom(
        id: 'math:${globalRange.start}:${globalRange.end}',
        type: _InlineAtomType.math,
        localRange: TextSystemRange(localStart, localEnd),
        globalRange: globalRange,
        sourceText: sourceText,
        displayText: latex.isEmpty ? sourceText : latex,
        latex: latex,
      ),
    );
  }

  for (final mark in block.marks) {
    if (mark.kind != TextMarkKind.link) continue;
    final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
    if (inlineReference == null) continue;
    if (_isFootnoteReferenceMark(mark)) continue;
    final intersection = mark.range.intersection(visibleRange);
    if (intersection == null || intersection.isCollapsed) continue;

    final localStart = (intersection.start - globalStart).clamp(0, text.length).toInt();
    final localEnd = (intersection.end - globalStart).clamp(localStart, text.length).toInt();
    if (localStart >= localEnd) continue;
    final atomRange = TextSystemRange(localStart, localEnd);
    final overlapsMath = atoms.any(
      (atom) => atom.type == _InlineAtomType.math && atom.localRange.intersection(atomRange) != null,
    );
    if (overlapsMath) continue;

    final sourceText = text.substring(localStart, localEnd);
    final displayText = inlineReference.selectedText?.trim().isNotEmpty == true
        ? inlineReference.selectedText!.trim()
        : sourceText;
    atoms.add(
      _InlineAtom(
        id: inlineReference.id.isNotEmpty
            ? 'reference:${inlineReference.id}'
            : 'reference:${intersection.start}:${intersection.end}',
        type: _InlineAtomType.crossReference,
        localRange: atomRange,
        globalRange: intersection,
        sourceText: sourceText,
        displayText: displayText,
        referenceMark: mark,
        inlineReference: inlineReference,
      ),
    );
  }

  atoms.sort((a, b) {
    final startCompare = a.localRange.start.compareTo(b.localRange.start);
    if (startCompare != 0) return startCompare;
    return b.localRange.length.compareTo(a.localRange.length);
  });

  final normalized = <_InlineAtom>[];
  var consumedUntil = 0;
  for (final atom in atoms) {
    if (atom.localRange.start < consumedUntil) continue;
    normalized.add(atom);
    consumedUntil = atom.localRange.end;
  }
  return normalized;
}


List<InlineSpan> _editableInlineAtomSpansForRange({
  required BuildContext context,
  required String text,
  required TextSystemBlock block,
  required List<_InlineAtom> atoms,
  required TextSelection activeSelection,
  required int globalStart,
  required int globalEnd,
  required TextStyle baseStyle,
}) {
  if (text.isEmpty) return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  if (atoms.isEmpty) {
    return _markedSpansForRange(
      text: text,
      block: block,
      globalStart: globalStart,
      globalEnd: globalEnd,
      baseStyle: baseStyle,
    );
  }

  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final spans = <InlineSpan>[];
  var cursor = 0;

  void appendNormal(int start, int end) {
    if (end <= start) return;
    spans.addAll(
      _markedSpansForRange(
        text: text.substring(start, end),
        block: block,
        globalStart: globalStart + start,
        globalEnd: globalStart + end,
        baseStyle: baseStyle,
      ),
    );
  }

  for (final atom in atoms) {
    appendNormal(cursor, atom.localRange.start);
    final active = _selectionActivatesInlineAtom(activeSelection, atom);
    if (active) {
      spans.add(
        TextSpan(
          text: atom.sourceText,
          style: atom.type == _InlineAtomType.math
              ? _inlineMathSourceStyle(baseStyle)
              : _activeInlineAtomSourceStyle(baseStyle, colorScheme),
        ),
      );
    } else {
      switch (atom.type) {
        case _InlineAtomType.math:
          spans.add(
            TextSpan(
              text: _sameLengthInlineAtomDisplay(
                _humanReadableInlineMath(atom.latex ?? atom.displayText),
                atom.sourceText.length,
              ),
              style: _inlineMathRenderedEditingStyle(baseStyle, colorScheme),
            ),
          );
          break;
        case _InlineAtomType.crossReference:
          final reference = atom.inlineReference;
          final broken = reference == null || reference.targetId.trim().isEmpty;
          final coveringMarks = block.marks
              .where((mark) => mark.range.containsRange(atom.globalRange))
              .toList(growable: false);
          final referenceStyle = _styleWithMarks(baseStyle, coveringMarks).copyWith(
            color: broken ? colorScheme.error : colorScheme.primary,
            fontWeight: FontWeight.w600,
            backgroundColor: broken
                ? colorScheme.errorContainer.withValues(alpha: 0.18)
                : colorScheme.primaryContainer.withValues(alpha: 0.18),
          );
          spans.add(
            TextSpan(
              text: _sameLengthInlineAtomDisplay(atom.displayText, atom.sourceText.length),
              style: referenceStyle,
            ),
          );
          break;
      }
    }
    cursor = atom.localRange.end;
  }

  appendNormal(cursor, text.length);
  return spans.isEmpty ? <InlineSpan>[TextSpan(text: text, style: baseStyle)] : spans;
}

bool _selectionActivatesInlineAtom(TextSelection selection, _InlineAtom atom) {
  if (!selection.isValid) return false;
  final localStart = selection.start.clamp(0, 1 << 30).toInt();
  final localEnd = selection.end.clamp(localStart, 1 << 30).toInt();
  if (selection.isCollapsed) {
    final offset = selection.extentOffset;
    // A collapsed caret exactly before or after the atom should mean that the
    // user is typing around the atom, not editing the atom itself. Only expose
    // the source when the caret is inside the atom range. Pointer selection on a
    // rendered atom still selects the full source range and activates source
    // mode through the non-collapsed branch below.
    return offset > atom.localRange.start && offset < atom.localRange.end;
  }
  return localStart < atom.localRange.end && localEnd > atom.localRange.start;
}

String _sameLengthInlineAtomDisplay(String display, int sourceLength) {
  final clean = display.trim().isEmpty ? '□' : display.trim();
  if (sourceLength <= 0) return '';
  if (clean.length == sourceLength) return clean;
  if (clean.length > sourceLength) {
    if (sourceLength == 1) return clean.substring(0, 1);
    final keep = sourceLength - 1;
    return clean.substring(0, keep) + '…';
  }
  // TextEditingController.buildTextSpan is happiest when the displayed span has
  // the same logical text length as the backing controller text. Previously we
  // padded rendered inline atoms with visible spaces, which made active
  // paragraphs look like `H₂O    )`. Use zero-width word joiners instead: the
  // source offsets remain stable, but the document keeps its final visual shape
  // while the paragraph is being edited.
  return clean + List.filled(sourceLength - clean.length, '⁠').join();
}

String _humanReadableInlineMath(String latex) {
  var result = latex.trim();
  if (result.isEmpty) return '□';

  result = result
      .replaceAll(r'\,', ' ')
      .replaceAll(r'\;', ' ')
      .replaceAll(r'\:', ' ')
      .replaceAll(r'\left', '')
      .replaceAll(r'\right', '')
      .replaceAll(r'\cdot', '·')
      .replaceAll(r'\times', '×')
      .replaceAll(r'\to', '→')
      .replaceAll(r'\rightarrow', '→')
      .replaceAll(r'\infty', '∞')
      .replaceAll(r'\leq', '≤')
      .replaceAll(r'\geq', '≥')
      .replaceAll(r'\neq', '≠')
      .replaceAll(r'\approx', '≈')
      .replaceAll(r'\sum', '∑')
      .replaceAll(r'\prod', '∏')
      .replaceAll(r'\int', '∫')
      .replaceAll(r'\partial', '∂')
      .replaceAll(r'\Delta', 'Δ')
      .replaceAll(r'\delta', 'δ')
      .replaceAll(r'\alpha', 'α')
      .replaceAll(r'\beta', 'β')
      .replaceAll(r'\gamma', 'γ')
      .replaceAll(r'\lambda', 'λ')
      .replaceAll(r'\mu', 'μ')
      .replaceAll(r'\pi', 'π')
      .replaceAll(r'\rho', 'ρ')
      .replaceAll(r'\sigma', 'σ')
      .replaceAll(r'\theta', 'θ')
      .replaceAll(r'\phi', 'φ')
      .replaceAll(r'\omega', 'ω');

  result = result.replaceAllMapped(
    RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}'),
    (match) => '${match.group(1)}⁄${match.group(2)}',
  );
  result = result.replaceAllMapped(
    RegExp(r'_\{([^{}]+)\}'),
    (match) => _toSubscript(match.group(1) ?? ''),
  );
  result = result.replaceAllMapped(
    RegExp(r'\^\{([^{}]+)\}'),
    (match) => _toSuperscript(match.group(1) ?? ''),
  );
  result = result.replaceAllMapped(
    RegExp(r'_([A-Za-z0-9+\-=()])'),
    (match) => _toSubscript(match.group(1) ?? ''),
  );
  result = result.replaceAllMapped(
    RegExp(r'\^([A-Za-z0-9+\-=()])'),
    (match) => _toSuperscript(match.group(1) ?? ''),
  );
  result = result.replaceAllMapped(
    RegExp(r'\\operatorname\{([^{}]+)\}'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'\\mathrm\{([^{}]+)\}'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'\\text\{([^{}]+)\}'),
    (match) => match.group(1) ?? '',
  );
  result = result.replaceAll(RegExp(r'\\[A-Za-z]+'), '');
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  return result.isEmpty ? latex.trim() : result;
}

String _toSubscript(String value) {
  const map = <String, String>{
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
    'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ',
    'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ',
    'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ',
    'v': 'ᵥ', 'x': 'ₓ',
  };
  return value.split('').map((char) => map[char] ?? map[char.toLowerCase()] ?? char).join();
}

String _toSuperscript(String value) {
  const map = <String, String>{
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
    'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ',
    'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ',
    'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ',
    'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
    'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
  };
  return value.split('').map((char) => map[char] ?? map[char.toLowerCase()] ?? char).join();
}

TextStyle _inlineMathRenderedEditingStyle(TextStyle baseStyle, ColorScheme colorScheme) {
  return baseStyle.copyWith(
    color: colorScheme.onSurface,
    backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.14),
  );
}

TextStyle _activeInlineAtomSourceStyle(TextStyle baseStyle, ColorScheme colorScheme) {
  return baseStyle.copyWith(
    color: colorScheme.primary,
    fontWeight: FontWeight.w600,
    backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.22),
  );
}

List<InlineSpan> _renderedInlineAtomSpansForRange({
  required BuildContext context,
  required String text,
  required TextSystemBlock block,
  required int globalStart,
  required int globalEnd,
  required TextStyle baseStyle,
}) {
  if (text.isEmpty) return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  final atoms = _inlineAtomsForVisibleRange(
    text: text,
    block: block,
    globalStart: globalStart,
    globalEnd: globalEnd,
  );
  if (atoms.isEmpty) {
    return _markedSpansForRange(
      text: text,
      block: block,
      globalStart: globalStart,
      globalEnd: globalEnd,
      baseStyle: baseStyle,
    );
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  void appendNormal(int start, int end) {
    if (end <= start) return;
    spans.addAll(
      _markedSpansForRange(
        text: text.substring(start, end),
        block: block,
        globalStart: globalStart + start,
        globalEnd: globalStart + end,
        baseStyle: baseStyle,
      ),
    );
  }

  for (final atom in atoms) {
    appendNormal(cursor, atom.localRange.start);
    switch (atom.type) {
      case _InlineAtomType.math:
        final latex = atom.latex?.trim() ?? '';
        if (latex.isEmpty) {
          spans.add(TextSpan(text: atom.sourceText, style: _inlineMathSourceStyle(baseStyle)));
        } else {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Math.tex(
                  latex,
                  mathStyle: MathStyle.text,
                  textStyle: baseStyle.copyWith(
                    color: colorScheme.onSurface,
                    height: 1.0,
                  ),
                  onErrorFallback: (_) => Text(
                    r'\(' + latex + r'\)',
                    style: _inlineMathSourceStyle(baseStyle).copyWith(color: colorScheme.error),
                  ),
                ),
              ),
            ),
          );
        }
        break;
      case _InlineAtomType.crossReference:
        final reference = atom.inlineReference;
        final broken = reference == null || reference.targetId.trim().isEmpty;
        final coveringMarks = block.marks
            .where((mark) => mark.range.containsRange(atom.globalRange))
            .toList(growable: false);
        final style = _styleWithMarks(baseStyle, coveringMarks).copyWith(
          color: broken ? colorScheme.error : colorScheme.primary,
          fontWeight: FontWeight.w600,
          backgroundColor: broken
              ? colorScheme.errorContainer.withValues(alpha: 0.22)
              : colorScheme.primaryContainer.withValues(alpha: 0.22),
        );
        spans.add(TextSpan(text: atom.displayText, style: style));
        break;
    }
    cursor = atom.localRange.end;
  }

  appendNormal(cursor, text.length);
  return spans.isEmpty ? <InlineSpan>[TextSpan(text: text, style: baseStyle)] : spans;
}

bool _rangeInsideAny(TextSystemRange range, List<TextSystemRange> ranges) {
  for (final candidate in ranges) {
    if (candidate.containsRange(range)) return true;
  }
  return false;
}

TextStyle _inlineMathSourceStyle(TextStyle baseStyle) {
  return baseStyle.copyWith(
    fontFamily: 'Consolas',
    fontFamilyFallback: const <String>['Cascadia Mono', 'monospace'],
    color: const Color(0xFF37448D),
    backgroundColor: const Color(0x1437448D),
  );
}

List<InlineSpan> _markedSpansForRange({
  required String text,
  required TextSystemBlock block,
  required int globalStart,
  required int globalEnd,
  required TextStyle baseStyle,
}) {
  if (text.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  }

  final localLength = text.length;
  final boundaries = <int>{0, localLength};
  final inlineMathRanges = _inlineMathRangesForVisibleText(
    text: text,
    globalStart: globalStart,
    globalEnd: globalEnd,
  );
  for (final range in inlineMathRanges) {
    boundaries.add((range.start - globalStart).clamp(0, localLength).toInt());
    boundaries.add((range.end - globalStart).clamp(0, localLength).toInt());
  }

  for (final mark in block.marks) {
    final intersection = mark.range.intersection(TextSystemRange(globalStart, globalEnd));
    if (intersection == null) continue;
    boundaries.add((intersection.start - globalStart).clamp(0, localLength).toInt());
    boundaries.add((intersection.end - globalStart).clamp(0, localLength).toInt());
  }

  final ordered = boundaries.toList()..sort();
  final spans = <InlineSpan>[];

  for (var i = 0; i < ordered.length - 1; i++) {
    final start = ordered[i];
    final end = ordered[i + 1];
    if (start >= end) continue;

    final globalSegment = TextSystemRange(globalStart + start, globalStart + end);
    final coveringMarks = block.marks
        .where((mark) => mark.range.containsRange(globalSegment))
        .toList(growable: false);

    TextMark? footnoteMark;
    for (final mark in coveringMarks) {
      if (_isFootnoteReferenceMark(mark)) {
        footnoteMark = mark;
        break;
      }
    }
    final segmentText = text.substring(start, end);
    final markedStyle = _styleWithMarks(baseStyle, coveringMarks);
    final segmentStyle = _rangeInsideAny(globalSegment, inlineMathRanges)
        ? _inlineMathSourceStyle(markedStyle)
        : markedStyle;
    spans.add(
      TextSpan(
        text: footnoteMark == null
            ? segmentText
            : _academicFootnoteNumber(
                int.tryParse(footnoteMark.attributes['number'] ?? '') ?? 0,
              ),
        style: segmentStyle,
      ),
    );
  }

  return spans.isEmpty ? <InlineSpan>[TextSpan(text: text, style: baseStyle)] : spans;
}

TextStyle _styleWithMarks(TextStyle baseStyle, List<TextMark> marks) {
  var result = baseStyle;
  final decorations = <TextDecoration>[];
  Color? referenceDecorationColor;
  TextDecorationStyle? referenceDecorationStyle;
  double? referenceDecorationThickness;

  for (final mark in marks) {
    switch (mark.kind) {
      case TextMarkKind.bold:
        result = result.copyWith(fontWeight: FontWeight.w800);
        break;
      case TextMarkKind.italic:
        result = result.copyWith(fontStyle: FontStyle.italic);
        break;
      case TextMarkKind.underline:
        decorations.add(TextDecoration.underline);
        break;
      case TextMarkKind.strikethrough:
        decorations.add(TextDecoration.lineThrough);
        break;
      case TextMarkKind.highlight:
        result = result.copyWith(backgroundColor: const Color(0x66FFD54F));
        break;
      case TextMarkKind.code:
        result = result.copyWith(
          fontFamily: 'Consolas',
          fontFamilyFallback: const <String>['Cascadia Mono', 'monospace'],
          backgroundColor: const Color(0x1F000000),
        );
        break;
      case TextMarkKind.link:
        final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
        if (_isFootnoteReferenceMark(mark)) {
          result = result.copyWith(
            fontSize: (result.fontSize ?? 14) * 0.66,
            fontWeight: FontWeight.w700,
            height: 0.95,
          );
        } else if (inlineReference?.isCitation == true) {
          decorations.add(TextDecoration.underline);
          referenceDecorationColor = const Color(0xFF8A6D1D);
          referenceDecorationStyle = TextDecorationStyle.dotted;
          referenceDecorationThickness = 1.2;
          result = result.copyWith(backgroundColor: const Color(0x14B08900));
        } else if (inlineReference != null) {
          decorations.add(TextDecoration.underline);
          referenceDecorationColor = inlineReference.targetId.trim().isEmpty
              ? const Color(0xFFB3261E)
              : const Color(0xFF6B5E8E);
          referenceDecorationStyle = TextDecorationStyle.dotted;
          referenceDecorationThickness = 1.15;
        } else {
          decorations.add(TextDecoration.underline);
          referenceDecorationColor = const Color(0xFF6B5E8E);
          referenceDecorationStyle = TextDecorationStyle.solid;
        }
        break;
    }
  }

  if (decorations.isNotEmpty) {
    result = result.copyWith(
      decoration: TextDecoration.combine(decorations),
      decorationColor: referenceDecorationColor,
      decorationStyle: referenceDecorationStyle,
      decorationThickness: referenceDecorationThickness,
    );
  }

  return result;
}

bool _rangeFullyCoveredByKind(
  List<TextMark> marks,
  TextSystemRange range,
  TextMarkKind kind,
) {
  final intervals = marks
      .where((mark) => mark.kind == kind)
      .map((mark) => mark.range.intersection(range))
      .whereType<TextSystemRange>()
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  var cursor = range.start;
  for (final interval in intervals) {
    if (interval.start > cursor) return false;
    if (interval.end > cursor) cursor = interval.end;
    if (cursor >= range.end) return true;
  }
  return cursor >= range.end;
}


class _PagedEditableBlockField extends StatefulWidget {
  const _PagedEditableBlockField({
    required this.block,
    required this.fragment,
    required this.textController,
    required this.style,
    required this.navigation,
    required this.editable,
    required this.restoreCaretAnchor,
    required this.restoreSelectionAnchor,
    required this.onActiveCaretChanged,
    required this.onActiveSelectionChanged,
    required this.onActiveFieldChanged,
    required this.onRequestCaretRestore,
    required this.onRequestSelectionRestore,
    required this.onRestoreSelectionConsumed,
    required this.onSelectObjectBlock,
    this.onOpenReferenceTarget,
  });

  final TextSystemBlock block;
  final TextSystemPagedBlockFragment fragment;
  final TextSystemController textController;
  final TextStyle style;
  final _PagedFragmentNavigation navigation;
  final bool editable;
  final TextSystemPagedCaretAnchor? restoreCaretAnchor;
  final TextSystemPagedSelectionAnchor? restoreSelectionAnchor;
  final ValueChanged<TextSystemPagedCaretAnchor> onActiveCaretChanged;
  final ValueChanged<TextSystemPagedSelectionAnchor> onActiveSelectionChanged;
  final ValueChanged<_PagedEditableBlockFieldState?> onActiveFieldChanged;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRequestSelectionRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRestoreSelectionConsumed;
  final ValueChanged<String> onSelectObjectBlock;
  final ValueChanged<TextSystemInlineReferenceMark>? onOpenReferenceTarget;

  @override
  State<_PagedEditableBlockField> createState() => _PagedEditableBlockFieldState();
}

class _PagedEditableBlockFieldState extends State<_PagedEditableBlockField> {
  late final _PagedMarkedTextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _selectionSyncTimer;
  Timer? _referencePreviewCloseTimer;
  OverlayEntry? _referencePreviewEntry;
  TextMark? _activeReferencePreviewMark;
  Offset? _activeReferencePreviewGlobalPosition;
  bool _referencePreviewPinned = false;
  bool _pointerInsideReferencePreview = false;
  bool _isApplyingExternalText = false;
  TextSystemPagedSelectionAnchor? _lastReportedSelectionAnchor;
  bool _inlineMathSourceEditing = false;

  TextSystemPagedCaretAnchor? get caretAnchor => selectionAnchor?.caretAnchor;

  TextSystemPagedSelectionAnchor? get selectionAnchor {
    final selection = _controller.selection;
    if (!selection.isValid) return null;
    final safeStart = _safeStartOffset(widget.block, widget.fragment);
    final localBase = selection.baseOffset.clamp(0, _controller.text.length).toInt();
    final localExtent = selection.extentOffset.clamp(0, _controller.text.length).toInt();
    return TextSystemPagedSelectionAnchor(
      blockId: widget.block.id,
      baseOffset: safeStart + localBase,
      extentOffset: safeStart + localExtent,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = _PagedMarkedTextEditingController(
      text: _fragmentText(widget.block, widget.fragment),
      block: widget.block,
      fragment: widget.fragment,
      baseStyle: widget.style,
    );
    _focusNode = FocusNode(debugLabel: 'paged-block-${widget.block.id}-${widget.fragment.visualTextStartOffset}');
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_notifyActiveSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRestoreAnchorIfNeeded());
  }

  @override
  void didUpdateWidget(covariant _PagedEditableBlockField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged = oldWidget.block.id != widget.block.id ||
        oldWidget.fragment.visualTextStartOffset != widget.fragment.visualTextStartOffset ||
        oldWidget.fragment.isSplitFragment != widget.fragment.isSplitFragment;

    final nextFragmentText = _fragmentText(widget.block, widget.fragment);

    final documentTextChanged = oldWidget.block.text != widget.block.text ||
        oldWidget.block.marks != widget.block.marks ||
        oldWidget.block.type != widget.block.type;

    if (identityChanged) {
      _setControllerText(nextFragmentText, collapseToEnd: false);
    } else if (nextFragmentText != _controller.text &&
        (!_focusNode.hasFocus || documentTextChanged)) {
      // While focused, the TextField is usually the user's active local editing
      // buffer. History operations are different: undo/redo changes the
      // canonical document while the field is still focused, so the controller
      // must be synced even though it has focus.
      _setControllerText(nextFragmentText, collapseToEnd: false);
    }

    _controller.updateRendering(
      block: widget.block,
      fragment: widget.fragment,
      baseStyle: widget.style,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRestoreAnchorIfNeeded());
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      widget.onActiveFieldChanged(this);
      _startSelectionSync();
      _scheduleActiveSelectionNotification();
    } else {
      _stopSelectionSync();
      if (_inlineMathSourceEditing && mounted) {
        setState(() => _inlineMathSourceEditing = false);
      }
    }
  }

  void _startSelectionSync() {
    _selectionSyncTimer ??= Timer.periodic(
      const Duration(milliseconds: 80),
      (_) {
        if (!mounted || !_focusNode.hasFocus) {
          _stopSelectionSync();
          return;
        }
        _notifyActiveSelection();
      },
    );
  }

  void _stopSelectionSync() {
    _selectionSyncTimer?.cancel();
    _selectionSyncTimer = null;
  }

  void _scheduleActiveSelectionNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onActiveFieldChanged(this);
      _notifyActiveSelection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onActiveFieldChanged(this);
        _notifyActiveSelection();
      });
      // Native TextField mouse selection can settle after pointer-up on desktop.
      // A few delayed refreshes make the master header reliably observe the
      // final non-collapsed selection without requiring a keyboard command.
      for (final delay in const <Duration>[
        Duration(milliseconds: 80),
        Duration(milliseconds: 180),
        Duration(milliseconds: 320),
      ]) {
        Timer(delay, () {
          if (!mounted) return;
          widget.onActiveFieldChanged(this);
          _notifyActiveSelection();
        });
      }
    });
  }

  void _notifyActiveSelection() {
    if (_isApplyingExternalText || !_focusNode.hasFocus) return;
    final anchor = selectionAnchor;
    if (anchor == null) return;

    // Flutter can emit transient collapsed selections while a drag selection is
    // still settling. Reporting every intermediate collapsed state makes the
    // toolbar/status row blink between "selected" and "collapsed".
    final last = _lastReportedSelectionAnchor;
    if (anchor.isCollapsed && last != null && !last.isCollapsed && last.blockId == anchor.blockId) {
      return;
    }

    if (anchor == last) {
      widget.onActiveFieldChanged(this);
      return;
    }

    _lastReportedSelectionAnchor = anchor;
    widget.onActiveFieldChanged(this);
    widget.onActiveSelectionChanged(anchor);
    widget.onActiveCaretChanged(anchor.caretAnchor);
  }

  void _applyRestoreAnchorIfNeeded() {
    if (!mounted) return;
    final selectionAnchor = widget.restoreSelectionAnchor;
    if (selectionAnchor != null && selectionAnchor.shouldFocusFragment(widget.fragment)) {
      final safeStart = _safeStartOffset(widget.block, widget.fragment);
      final safeEnd = _safeEndOffset(widget.block, widget.fragment, safeStart);
      final localBase = (selectionAnchor.baseOffset.clamp(safeStart, safeEnd).toInt() - safeStart)
          .clamp(0, _controller.text.length)
          .toInt();
      final localExtent = (selectionAnchor.extentOffset.clamp(safeStart, safeEnd).toInt() - safeStart)
          .clamp(0, _controller.text.length)
          .toInt();

      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: localBase,
        extentOffset: localExtent,
      );
      _lastReportedSelectionAnchor = selectionAnchor;
      widget.onActiveSelectionChanged(selectionAnchor);
      widget.onActiveCaretChanged(selectionAnchor.caretAnchor);
      widget.onRestoreSelectionConsumed(selectionAnchor);
      return;
    }

    final caretAnchor = widget.restoreCaretAnchor;
    if (caretAnchor == null || !caretAnchor.matchesFragment(widget.fragment)) return;

    final localOffset = (caretAnchor.textOffset - _safeStartOffset(widget.block, widget.fragment))
        .clamp(0, _controller.text.length)
        .toInt();
    final collapsedSelectionAnchor = TextSystemPagedSelectionAnchor.collapsed(
      blockId: caretAnchor.blockId,
      textOffset: caretAnchor.textOffset,
    );
    _focusNode.requestFocus();
    _controller.selection = TextSelection.collapsed(offset: localOffset);
    _lastReportedSelectionAnchor = collapsedSelectionAnchor;
    widget.onActiveSelectionChanged(collapsedSelectionAnchor);
    widget.onActiveCaretChanged(caretAnchor);
    widget.onRestoreSelectionConsumed(collapsedSelectionAnchor);
  }

  void _setControllerText(String text, {required bool collapseToEnd}) {
    _isApplyingExternalText = true;
    final previousSelection = _controller.selection;
    final selectionOffset = collapseToEnd
        ? text.length
        : previousSelection.baseOffset.clamp(0, text.length).toInt();
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: TextRange.empty,
    );
    _isApplyingExternalText = false;
  }

  void _handleChanged(String value) {
    if (_isApplyingExternalText) return;

    if (!widget.fragment.isSplitFragment) {
      widget.textController.updateBlockText(widget.block.id, value);
      _notifyActiveSelection();
      return;
    }

    final blockText = widget.block.text;
    final safeStart = _safeStartOffset(widget.block, widget.fragment);
    final safeEnd = _safeEndOffset(widget.block, widget.fragment, safeStart);
    final nextText = blockText.replaceRange(safeStart, safeEnd, value);
    widget.textController.updateBlockText(widget.block.id, nextText);
    _notifyActiveSelection();
  }

  _InlineAtom? _inlineAtomAdjacentToCollapsedSelection({required bool backwards}) {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final localOffset = selection.baseOffset.clamp(0, _controller.text.length).toInt();
    final safeStart = _safeStartOffset(widget.block, widget.fragment);
    final safeEnd = _safeEndOffset(widget.block, widget.fragment, safeStart);
    final atoms = _inlineAtomsForVisibleRange(
      text: _controller.text,
      block: widget.block,
      globalStart: safeStart,
      globalEnd: safeEnd,
    );
    for (final atom in atoms) {
      if (backwards && atom.localRange.end == localOffset) return atom;
      if (!backwards && atom.localRange.start == localOffset) return atom;
    }
    return null;
  }

  KeyEventResult _deleteAdjacentInlineAtom({required bool backwards}) {
    final atom = _inlineAtomAdjacentToCollapsedSelection(backwards: backwards);
    if (atom == null) return KeyEventResult.ignored;
    final nextText = _controller.text.replaceRange(atom.localRange.start, atom.localRange.end, '');
    _setControllerText(nextText, collapseToEnd: false);
    _controller.selection = TextSelection.collapsed(offset: atom.localRange.start);
    _handleChanged(nextText);
    _scheduleActiveSelectionNotification();
    return KeyEventResult.handled;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final modifierPressed =
        HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

    if (key == LogicalKeyboardKey.escape && _referencePreviewEntry != null) {
      _hideReferencePreview();
      return KeyEventResult.handled;
    }

    if (modifierPressed && key == LogicalKeyboardKey.keyZ) {
      return _performHistoryShortcut(undo: true);
    }

    if (modifierPressed && key == LogicalKeyboardKey.keyY) {
      return _performHistoryShortcut(undo: false);
    }

    if (modifierPressed &&
        HardwareKeyboard.instance.isShiftPressed &&
        key == LogicalKeyboardKey.keyZ) {
      return _performHistoryShortcut(undo: false);
    }

    // Use the TextSystem clipboard path for keyboard copy/cut/paste inside a
    // stable block selection. This preserves inline marks and block structure
    // for internal paste while still writing plain text to the system clipboard.
    if (modifierPressed && key == LogicalKeyboardKey.keyC) {
      return _copySelectionToClipboard();
    }

    if (modifierPressed && key == LogicalKeyboardKey.keyX) {
      return _cutSelectionToClipboard();
    }

    if (modifierPressed && key == LogicalKeyboardKey.keyV) {
      unawaited(_pastePlainTextFromClipboard());
      return KeyEventResult.handled;
    }

    if (modifierPressed && key == LogicalKeyboardKey.keyB) {
      return _toggleMarkForSelection(TextMarkKind.bold);
    }

    if (modifierPressed && key == LogicalKeyboardKey.keyI) {
      return _toggleMarkForSelection(TextMarkKind.italic);
    }

    if (modifierPressed && key == LogicalKeyboardKey.keyU) {
      return _toggleMarkForSelection(TextMarkKind.underline);
    }

    if (modifierPressed && key == LogicalKeyboardKey.backquote) {
      return _toggleMarkForSelection(TextMarkKind.code);
    }

    if (modifierPressed &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
      final mark = _activeReferencePreviewMark;
      final inlineReference = mark == null
          ? null
          : TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
      if (inlineReference != null) {
        _openReferenceTarget(inlineReference);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.backspace) {
      final atomResult = _deleteAdjacentInlineAtom(backwards: true);
      if (atomResult == KeyEventResult.handled) return atomResult;
    }

    if (key == LogicalKeyboardKey.delete) {
      final atomResult = _deleteAdjacentInlineAtom(backwards: false);
      if (atomResult == KeyEventResult.handled) return atomResult;
    }

    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (_canSplitBlock(widget.block)) {
        return _splitBlockAtCaret();
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.backspace && _isCollapsedAtLocalStart) {
      final globalOffset = _safeStartOffset(widget.block, widget.fragment);
      if (globalOffset == 0) {
        final previousObjectBlockId = _previousObjectBlockIdAtDocumentStart();
        if (previousObjectBlockId != null) {
          return _selectAdjacentObject(previousObjectBlockId);
        }
        if ((widget.block.type == TextSystemBlockType.listItem ||
                widget.block.type == TextSystemBlockType.todo) &&
            widget.block.text.isEmpty) {
          widget.textController.updateBlockType(widget.block.id, TextSystemBlockType.paragraph);
          widget.onRequestCaretRestore(
            TextSystemPagedCaretAnchor(blockId: widget.block.id, textOffset: 0),
          );
          return KeyEventResult.handled;
        }

        final pageBreakTarget = widget.textController.removePageBreakBefore(widget.block.id);
        if (pageBreakTarget != null) {
          widget.onRequestCaretRestore(
            TextSystemPagedCaretAnchor(blockId: pageBreakTarget.blockId, textOffset: pageBreakTarget.offset),
          );
          return KeyEventResult.handled;
        }

        final target = widget.textController.mergeBlockWithPrevious(widget.block.id);
        if (target != null) {
          widget.onRequestCaretRestore(
            TextSystemPagedCaretAnchor(blockId: target.blockId, textOffset: target.offset),
          );
          return KeyEventResult.handled;
        }
      }
      return _moveToAnchor(widget.navigation.previousAnchor);
    }

    if (key == LogicalKeyboardKey.delete && _isCollapsedAtDocumentEnd) {
      final nextObjectBlockId = _nextObjectBlockIdAtDocumentEnd();
      if (nextObjectBlockId != null) {
        return _selectAdjacentObject(nextObjectBlockId);
      }
    }

    if ((key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) && _isCollapsedAtLocalStart) {
      final previousObjectBlockId = _previousObjectBlockIdAtDocumentStart();
      if (previousObjectBlockId != null) {
        return _selectAdjacentObject(previousObjectBlockId);
      }
      return _moveToAnchor(widget.navigation.previousAnchor);
    }

    if ((key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) && _isCollapsedAtLocalEnd) {
      final nextObjectBlockId = _nextObjectBlockIdAtDocumentEnd();
      if (nextObjectBlockId != null) {
        return _selectAdjacentObject(nextObjectBlockId);
      }
      return _moveToAnchor(widget.navigation.nextAnchor);
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _performHistoryShortcut({required bool undo}) {
    if (undo && !widget.textController.canUndo) return KeyEventResult.ignored;
    if (!undo && !widget.textController.canRedo) return KeyEventResult.ignored;

    final anchor = selectionAnchor;
    final fallbackOffset = anchor == null
        ? _safeStartOffset(widget.block, widget.fragment)
        : math.min(anchor.baseOffset, anchor.extentOffset)
            .clamp(0, widget.block.text.length)
            .toInt();

    forceSyncFromDocumentBeforeHistory();

    if (undo) {
      widget.textController.undo();
    } else {
      widget.textController.redo();
    }

    final currentDocument = widget.textController.document;
    final currentBlock = currentDocument.blockById(widget.block.id);
    if (currentBlock != null) {
      widget.onRequestSelectionRestore(
        TextSystemPagedSelectionAnchor.collapsed(
          blockId: currentBlock.id,
          textOffset: fallbackOffset.clamp(0, currentBlock.text.length).toInt(),
        ),
      );
    } else if (currentDocument.blocks.isNotEmpty) {
      final fallbackBlock = currentDocument.blocks.lastWhere(
        (block) => block.text.isNotEmpty,
        orElse: () => currentDocument.blocks.last,
      );
      widget.onRequestSelectionRestore(
        TextSystemPagedSelectionAnchor.collapsed(
          blockId: fallbackBlock.id,
          textOffset: fallbackBlock.text.length,
        ),
      );
    }

    return KeyEventResult.handled;
  }

  KeyEventResult _copySelectionToClipboard() {
    final anchor = selectionAnchor;
    if (anchor == null || anchor.isCollapsed) return KeyEventResult.ignored;

    final documentRange = _documentRangeForAnchor(anchor);
    if (documentRange == null || documentRange.isCollapsed) return KeyEventResult.ignored;

    final fragment = widget.textController.copyDocumentFragment(documentRange);
    Clipboard.setData(ClipboardData(text: fragment.plainText));
    widget.onRequestSelectionRestore(anchor.clampToBlock(widget.block));
    return KeyEventResult.handled;
  }

  KeyEventResult _cutSelectionToClipboard() {
    final anchor = selectionAnchor;
    if (anchor == null || anchor.isCollapsed) return KeyEventResult.ignored;

    final documentRange = _documentRangeForAnchor(anchor);
    if (documentRange == null || documentRange.isCollapsed) return KeyEventResult.ignored;

    final fragment = widget.textController.cutDocumentRange(documentRange);
    Clipboard.setData(ClipboardData(text: fragment.plainText));

    final target = documentRange.normalized().start;
    widget.onRequestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: target.blockId,
        textOffset: target.offset,
      ),
    );
    return KeyEventResult.handled;
  }

  Future<void> _pastePlainTextFromClipboard() async {
    final internalFragment = widget.textController.internalDocumentClipboard;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = clipboard?.text;
    if ((internalFragment == null || internalFragment.isEmpty) &&
        (pastedText == null || pastedText.isEmpty)) {
      return;
    }

    final selection = _controller.selection;
    final fallbackLocalOffset = selection.isValid
        ? selection.extentOffset.clamp(0, _controller.text.length).toInt()
        : _controller.text.length;
    final anchor = selectionAnchor ??
        TextSystemPagedSelectionAnchor.collapsed(
          blockId: widget.block.id,
          textOffset: _safeStartOffset(widget.block, widget.fragment) + fallbackLocalOffset,
        );

    final documentRange = anchor.isCollapsed
        ? _collapsedDocumentRangeForAnchor(anchor)
        : _documentRangeForAnchor(anchor);
    if (documentRange == null) return;

    final result = internalFragment != null && !internalFragment.isEmpty
        ? widget.textController.pasteDocumentClipboardAtRange(documentRange)
        : widget.textController.replaceDocumentRangeWithPlainText(
            documentRange,
            (pastedText ?? '').replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
            label: 'Paste plain text',
          );

    final caret = result.insertedRange.normalized().end;
    widget.onRequestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: caret.blockId,
        textOffset: caret.offset,
      ),
    );
  }

  TextSystemDocumentRange? _documentRangeForAnchor(TextSystemPagedSelectionAnchor anchor) {
    final blockIndex = widget.textController.document.blocks.indexWhere(
      (block) => block.id == anchor.blockId,
    );
    if (blockIndex < 0) return null;

    final block = widget.textController.document.blocks[blockIndex];
    final start = math.min(anchor.baseOffset, anchor.extentOffset)
        .clamp(0, block.text.length)
        .toInt();
    final end = math.max(anchor.baseOffset, anchor.extentOffset)
        .clamp(start, block.text.length)
        .toInt();

    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: start,
      ),
      end: TextSystemDocumentPosition(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: end,
      ),
    );
  }

  TextSystemDocumentRange? _collapsedDocumentRangeForAnchor(TextSystemPagedSelectionAnchor anchor) {
    final blockIndex = widget.textController.document.blocks.indexWhere(
      (block) => block.id == anchor.blockId,
    );
    if (blockIndex < 0) return null;

    final block = widget.textController.document.blocks[blockIndex];
    final offset = anchor.caretOffset.clamp(0, block.text.length).toInt();

    return TextSystemDocumentRange.collapsed(
      TextSystemDocumentPosition(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: offset,
      ),
    );
  }

  TextSystemRange? _rangeForAnchor(TextSystemPagedSelectionAnchor anchor) {
    if (anchor.blockId != widget.block.id || anchor.isCollapsed) return null;
    final start = math.min(anchor.baseOffset, anchor.extentOffset)
        .clamp(0, widget.block.text.length)
        .toInt();
    final end = math.max(anchor.baseOffset, anchor.extentOffset)
        .clamp(start, widget.block.text.length)
        .toInt();
    final range = TextSystemRange(start, end);
    return range.isCollapsed ? null : range;
  }

  KeyEventResult _toggleMarkForSelection(TextMarkKind kind) {
    final anchor = selectionAnchor;
    if (anchor == null || anchor.isCollapsed) return KeyEventResult.ignored;

    final start = math.min(anchor.baseOffset, anchor.extentOffset)
        .clamp(0, widget.block.text.length)
        .toInt();
    final end = math.max(anchor.baseOffset, anchor.extentOffset)
        .clamp(start, widget.block.text.length)
        .toInt();
    if (start >= end) return KeyEventResult.ignored;

    final blockIndex = widget.textController.document.blocks.indexWhere(
      (candidate) => candidate.id == widget.block.id,
    );
    if (blockIndex < 0) return KeyEventResult.ignored;

    widget.textController.toggleMarkForDocumentRange(
      TextSystemDocumentRange(
        start: TextSystemDocumentPosition(
          blockId: widget.block.id,
          blockIndex: blockIndex,
          offset: start,
        ),
        end: TextSystemDocumentPosition(
          blockId: widget.block.id,
          blockIndex: blockIndex,
          offset: end,
        ),
      ),
      kind,
    );

    widget.onRequestSelectionRestore(anchor.clampToBlock(widget.block));
    return KeyEventResult.handled;
  }

  KeyEventResult _toggleBoldForSelection() {
    return _toggleMarkForSelection(TextMarkKind.bold);
  }

  KeyEventResult _splitBlockAtCaret() {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return KeyEventResult.ignored;

    if ((widget.block.type == TextSystemBlockType.listItem ||
            widget.block.type == TextSystemBlockType.todo) &&
        widget.block.text.trim().isEmpty) {
      widget.textController.updateBlockType(widget.block.id, TextSystemBlockType.paragraph);
      widget.onRequestCaretRestore(
        TextSystemPagedCaretAnchor(blockId: widget.block.id, textOffset: 0),
      );
      return KeyEventResult.handled;
    }

    final localOffset = selection.baseOffset.clamp(0, _controller.text.length).toInt();
    final globalOffset = _safeStartOffset(widget.block, widget.fragment) + localOffset;
    final target = widget.textController.splitBlockAt(widget.block.id, globalOffset);
    if (target == null) return KeyEventResult.ignored;
    widget.onRequestCaretRestore(
      TextSystemPagedCaretAnchor(blockId: target.blockId, textOffset: target.offset),
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _moveToAnchor(TextSystemPagedCaretAnchor? anchor) {
    if (anchor == null) return KeyEventResult.ignored;
    widget.onRequestCaretRestore(anchor);
    return KeyEventResult.handled;
  }

  bool get _isCollapsedAtLocalStart {
    final selection = _controller.selection;
    return selection.isValid && selection.isCollapsed && selection.baseOffset <= 0;
  }

  bool get _isCollapsedAtLocalEnd {
    final selection = _controller.selection;
    return selection.isValid && selection.isCollapsed && selection.baseOffset >= _controller.text.length;
  }


  bool get _isCollapsedAtDocumentStart {
    return _isCollapsedAtLocalStart && _safeStartOffset(widget.block, widget.fragment) == 0;
  }

  bool get _isCollapsedAtDocumentEnd {
    final safeStart = _safeStartOffset(widget.block, widget.fragment);
    final safeEnd = _safeEndOffset(widget.block, widget.fragment, safeStart);
    return _isCollapsedAtLocalEnd && safeEnd >= widget.block.text.length;
  }

  String? _previousObjectBlockIdAtDocumentStart() {
    if (!_isCollapsedAtDocumentStart) return null;
    final blocks = widget.textController.document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == widget.block.id);
    if (index <= 0) return null;
    final previous = blocks[index - 1];
    return _isDocumentObjectBlock(previous) ? previous.id : null;
  }

  String? _nextObjectBlockIdAtDocumentEnd() {
    if (!_isCollapsedAtDocumentEnd) return null;
    final blocks = widget.textController.document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == widget.block.id);
    if (index < 0 || index >= blocks.length - 1) return null;
    final next = blocks[index + 1];
    return _isDocumentObjectBlock(next) ? next.id : null;
  }

  KeyEventResult _selectAdjacentObject(String? blockId) {
    if (blockId == null) return KeyEventResult.ignored;
    widget.onSelectObjectBlock(blockId);
    return KeyEventResult.handled;
  }

  static bool _canSplitBlock(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote => true,
      _ => false,
    };
  }

  static int _safeStartOffset(
    TextSystemBlock block,
    TextSystemPagedBlockFragment fragment,
  ) {
    return fragment.visualTextStartOffset.clamp(0, block.text.length).toInt();
  }

  static int _safeEndOffset(
    TextSystemBlock block,
    TextSystemPagedBlockFragment fragment,
    int safeStart,
  ) {
    return fragment.visualTextEndOffset.clamp(safeStart, block.text.length).toInt();
  }

  static String _fragmentText(
    TextSystemBlock block,
    TextSystemPagedBlockFragment fragment,
  ) {
    if (!fragment.isSplitFragment) return block.text;
    final safeStart = _safeStartOffset(block, fragment);
    final safeEnd = _safeEndOffset(block, fragment, safeStart);
    return block.text.substring(safeStart, safeEnd);
  }

  void forceSyncFromDocumentBeforeHistory() {
    final text = _fragmentText(widget.block, widget.fragment);
    if (_controller.text != text) {
      _setControllerText(text, collapseToEnd: false);
    }
  }

  TextSystemPagedSelectionAnchor? get currentSelectionAnchor => selectionAnchor;

  bool get hasNonCollapsedSelection {
    final anchor = selectionAnchor;
    if (anchor == null) return false;
    return _rangeForAnchor(anchor) != null;
  }

  TextSystemDocumentRange? documentRangeForToolbarSelection() {
    final anchor = selectionAnchor;
    if (anchor == null || anchor.isCollapsed) return null;
    return _documentRangeForAnchor(anchor);
  }

  bool get canCreateReferenceFromToolbar {
    if (!widget.textController.document.blocks.any((block) => block.id == widget.block.id)) {
      return false;
    }
    if (!hasNonCollapsedSelection) return false;
    return switch (widget.block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  bool canToggleMarkFromToolbar(TextMarkKind kind) {
    if (!widget.textController.document.blocks.any((block) => block.id == widget.block.id)) {
      return false;
    }
    if (!hasNonCollapsedSelection) return false;
    return switch (widget.block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  bool get canToggleBoldFromToolbar => canToggleMarkFromToolbar(TextMarkKind.bold);

  bool get canPastePlainTextFromToolbar {
    return switch (widget.block.type) {
      TextSystemBlockType.paragraph ||
      TextSystemBlockType.heading ||
      TextSystemBlockType.listItem ||
      TextSystemBlockType.todo ||
      TextSystemBlockType.quote ||
      TextSystemBlockType.code => true,
      _ => false,
    };
  }

  bool selectionHasMarkFromToolbar(TextMarkKind kind) {
    final anchor = selectionAnchor;
    if (anchor == null) return false;
    final range = _rangeForAnchor(anchor);
    if (range == null) return false;
    return _rangeFullyCoveredByKind(widget.block.marks, range, kind);
  }

  bool get selectionIsBoldFromToolbar => selectionHasMarkFromToolbar(TextMarkKind.bold);

  bool copySelectionToClipboardFromToolbar() {
    return _copySelectionToClipboard() == KeyEventResult.handled;
  }

  bool cutSelectionToClipboardFromToolbar() {
    return _cutSelectionToClipboard() == KeyEventResult.handled;
  }

  Future<void> pastePlainTextFromToolbar() {
    return _pastePlainTextFromClipboard();
  }

  bool toggleMarkForToolbar(TextMarkKind kind) {
    return _toggleMarkForSelection(kind) == KeyEventResult.handled;
  }

  bool toggleBoldForToolbar() {
    return toggleMarkForToolbar(TextMarkKind.bold);
  }

  void _handleReferencePointerHover(PointerHoverEvent event) {
    final mark = _referenceMarkAtLocalPosition(event.localPosition);
    if (mark == null) {
      _scheduleReferencePreviewClose();
      return;
    }
    _showReferencePreview(mark: mark, globalPosition: event.position);
  }

  void _handleReferencePointerDown(PointerDownEvent event) {
    final mark = _referenceMarkAtLocalPosition(event.localPosition);
    if (mark == null) {
      if (!_referencePreviewPinned) _hideReferencePreview();
      return;
    }
    _showReferencePreview(mark: mark, globalPosition: event.position, pinned: true);
  }

  TextMark? _referenceMarkAtLocalPosition(Offset localPosition) {
    if (widget.block.marks.isEmpty || _controller.text.isEmpty) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final width = math.max(1.0, renderObject.size.width);
    final painter = TextPainter(
      text: TextSpan(text: _controller.text, style: widget.style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final localOffset = painter
        .getPositionForOffset(
          Offset(
            localPosition.dx.clamp(0.0, width).toDouble(),
            math.max(0.0, localPosition.dy),
          ),
        )
        .offset
        .clamp(0, _controller.text.length)
        .toInt();
    final globalOffset = _safeStartOffset(widget.block, widget.fragment) + localOffset;
    final candidates = widget.block.marks.where((mark) {
      if (mark.kind != TextMarkKind.link) return false;
      if (TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes) == null) {
        return false;
      }
      return mark.range.start <= globalOffset && globalOffset <= mark.range.end;
    }).toList(growable: false)
      ..sort((a, b) {
        final aRef = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(a.attributes);
        final bRef = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(b.attributes);
        if (aRef?.isCitation == true && bRef?.isCitation != true) return -1;
        if (bRef?.isCitation == true && aRef?.isCitation != true) return 1;
        return a.range.length.compareTo(b.range.length);
      });
    return candidates.isEmpty ? null : candidates.first;
  }

  void _showReferencePreview({
    required TextMark mark,
    required Offset globalPosition,
    bool pinned = false,
  }) {
    _referencePreviewCloseTimer?.cancel();
    _activeReferencePreviewMark = mark;
    _activeReferencePreviewGlobalPosition = globalPosition;
    _referencePreviewPinned = pinned || _referencePreviewPinned;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    if (_referencePreviewEntry == null) {
      _referencePreviewEntry = OverlayEntry(builder: _buildReferencePreviewOverlay);
      overlay.insert(_referencePreviewEntry!);
    } else {
      _referencePreviewEntry!.markNeedsBuild();
    }
  }

  Widget _buildReferencePreviewOverlay(BuildContext overlayContext) {
    final mark = _activeReferencePreviewMark;
    final inlineReference = mark == null
        ? null
        : TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
    final position = _activeReferencePreviewGlobalPosition;
    if (mark == null || inlineReference == null || position == null) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(overlayContext);
    const cardWidth = 340.0;
    const cardHeightEstimate = 260.0;
    final left = math.min(
      math.max(12.0, position.dx + 14.0),
      math.max(12.0, size.width - cardWidth - 12.0),
    );
    final top = math.min(
      math.max(12.0, position.dy + 18.0),
      math.max(12.0, size.height - cardHeightEstimate - 12.0),
    );

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: MouseRegion(
        onEnter: (_) {
          _pointerInsideReferencePreview = true;
          _referencePreviewCloseTimer?.cancel();
        },
        onExit: (_) {
          _pointerInsideReferencePreview = false;
          _scheduleReferencePreviewClose();
        },
        child: _ReferencePreviewCard(
          inlineReference: inlineReference,
          citationSettings: TextSystemCitationSettings.fromDocument(widget.textController.document),
          pinned: _referencePreviewPinned,
          onTogglePinned: () {
            _referencePreviewPinned = !_referencePreviewPinned;
            _referencePreviewEntry?.markNeedsBuild();
            if (!_referencePreviewPinned && !_pointerInsideReferencePreview) {
              _scheduleReferencePreviewClose();
            }
          },
          onOpen: () => _openReferenceTarget(inlineReference),
          onCopy: () => _copyReferenceDetails(inlineReference),
          onUnlink: () => _unlinkReferenceMark(mark),
          onCitationModeChanged: inlineReference.isCitation
              ? (mode) => _changeCitationModeForMark(mark, mode)
              : null,
          onClose: _hideReferencePreview,
        ),
      ),
    );
  }

  void _scheduleReferencePreviewClose() {
    if (_referencePreviewPinned || _pointerInsideReferencePreview) return;
    _referencePreviewCloseTimer?.cancel();
    _referencePreviewCloseTimer = Timer(const Duration(milliseconds: 220), () {
      if (!_referencePreviewPinned && !_pointerInsideReferencePreview) {
        _hideReferencePreview();
      }
    });
  }

  void _hideReferencePreview() {
    _referencePreviewCloseTimer?.cancel();
    _referencePreviewCloseTimer = null;
    _referencePreviewEntry?.remove();
    _referencePreviewEntry = null;
    _activeReferencePreviewMark = null;
    _activeReferencePreviewGlobalPosition = null;
    _referencePreviewPinned = false;
    _pointerInsideReferencePreview = false;
  }

  void _openReferenceTarget(TextSystemInlineReferenceMark inlineReference) {
    final openTarget = widget.onOpenReferenceTarget;
    if (openTarget != null) {
      openTarget(inlineReference);
      return;
    }

    final uri = inlineReference.uri?.toString();
    final title = _referencePreviewTitle(inlineReference);
    if (uri != null && uri.trim().isNotEmpty) {
      Clipboard.setData(ClipboardData(text: uri));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Copied target URI for $title. App navigation bridge is not attached here.')),
      );
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Open target: $title. No PDF/source navigation bridge is attached here.')),
    );
  }

  void _copyReferenceDetails(TextSystemInlineReferenceMark inlineReference) {
    Clipboard.setData(ClipboardData(text: _referencePreviewClipboardText(inlineReference)));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Reference details copied.')),
    );
  }

  void _unlinkReferenceMark(TextMark mark) {
    final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
    if (inlineReference == null) return;
    final document = widget.textController.document;
    final nextBlocks = document.blocks.map((block) {
      if (block.id != widget.block.id) return block;
      final nextMarks = block.marks
          .where((candidate) => !_isSameInlineReferenceTextMark(candidate, mark, inlineReference))
          .toList(growable: false);
      return block.copyWith(marks: nextMarks).normalizeMarks();
    }).toList(growable: false);
    var nextDocument = document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now());
    if (inlineReference.isCitation) {
      nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(nextDocument);
    }
    widget.textController.replaceDocument(nextDocument, label: 'Unlink reference');
    _hideReferencePreview();
  }

  void _changeCitationModeForMark(TextMark mark, TextSystemCitationInlineMode mode) {
    final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
    if (inlineReference == null || !inlineReference.isCitation) return;
    final document = widget.textController.document;
    final settings = TextSystemCitationSettings.fromDocument(document);
    final source = TextSystemCitationSource.fromInlineMark(inlineReference);
    final registry = TextSystemCitationRegistry.fromDocument(document);
    final citationText = TextSystemCitationFormatter.inlineCitation(
      settings: settings,
      source: source,
      sequenceNumber: registry.numberForTarget(inlineReference.targetId),
      inlineMode: mode,
    );
    final refreshedReference = inlineReference.copyWith(
      selectedText: citationText,
      metadata: <String, Object?>{
        ...inlineReference.metadata,
        ...source.toMetadata(),
        'citationStyleId': settings.style.id,
        'citationInlineMode': mode.id,
        'citationText': citationText,
        'bibliographyManaged': true,
      },
    );

    final nextBlocks = document.blocks.map((block) {
      if (block.id != widget.block.id) return block;
      final start = mark.range.start.clamp(0, block.text.length).toInt();
      final end = mark.range.end.clamp(start, block.text.length).toInt();
      if (start >= end) return block;
      final delta = citationText.length - (end - start);
      final nextText = block.text.replaceRange(start, end, citationText);
      final nextMarks = block.marks.map((candidate) {
        if (_isSameInlineReferenceTextMark(candidate, mark, inlineReference)) {
          return candidate.copyWith(
            range: TextSystemRange(start, start + citationText.length),
            attributes: refreshedReference.toTextMarkAttributes(),
          );
        }
        if (candidate.range.start >= end) {
          return candidate.copyWith(range: candidate.range.shift(delta));
        }
        if (candidate.range.end > end) {
          return candidate.copyWith(
            range: TextSystemRange(candidate.range.start, candidate.range.end + delta),
          );
        }
        return candidate;
      }).toList(growable: false);
      return block.copyWith(text: nextText, marks: nextMarks).normalizeMarks();
    }).toList(growable: false);

    final nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(
      document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      settings: settings,
    );
    widget.textController.replaceDocument(nextDocument, label: 'Change citation format');
    _hideReferencePreview();
    widget.onRequestSelectionRestore(
      TextSystemPagedSelectionAnchor.collapsed(
        blockId: widget.block.id,
        textOffset: (mark.range.start + citationText.length).clamp(0, nextDocument.blockById(widget.block.id)?.text.length ?? 0).toInt(),
      ),
    );
  }

  static bool _isSameInlineReferenceTextMark(
    TextMark candidate,
    TextMark original,
    TextSystemInlineReferenceMark originalReference,
  ) {
    if (candidate.kind != TextMarkKind.link) return false;
    final candidateReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(candidate.attributes);
    if (candidateReference == null) return false;
    return candidateReference.id == originalReference.id ||
        (candidate.range.start == original.range.start &&
            candidate.range.end == original.range.end &&
            candidateReference.targetId == originalReference.targetId &&
            candidateReference.kind == originalReference.kind);
  }



  bool get _fragmentHasInlineAtoms {
    final safeStart = _safeStartOffset(widget.block, widget.fragment);
    final safeEnd = _safeEndOffset(widget.block, widget.fragment, safeStart);
    final text = _fragmentText(widget.block, widget.fragment);
    return _inlineAtomsForVisibleRange(
      text: text,
      block: widget.block,
      globalStart: safeStart,
      globalEnd: safeEnd,
    ).isNotEmpty;
  }

  void _startInlineMathSourceEditing([Offset? localPosition]) {
    if (!widget.editable) return;
    final requestedSelection = localPosition == null
        ? _controller.selection
        : _selectionForInlineAtomPointer(localPosition);
    setState(() => _inlineMathSourceEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      if (requestedSelection != null && requestedSelection.isValid) {
        _controller.selection = requestedSelection;
      } else {
        final offset = _controller.selection.isValid
            ? _controller.selection.extentOffset.clamp(0, _controller.text.length).toInt()
            : _controller.text.length;
        _controller.selection = TextSelection.collapsed(offset: offset);
      }
      _scheduleActiveSelectionNotification();
    });
  }

  TextSelection? _selectionForInlineAtomPointer(Offset localPosition) {
    if (_controller.text.isEmpty) return const TextSelection.collapsed(offset: 0);
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final width = math.max(1.0, renderObject.size.width);
    final painter = TextPainter(
      text: TextSpan(text: _controller.text, style: widget.style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final offset = painter
        .getPositionForOffset(
          Offset(
            localPosition.dx.clamp(0.0, width).toDouble(),
            math.max(0.0, localPosition.dy),
          ),
        )
        .offset
        .clamp(0, _controller.text.length)
        .toInt();
    final safeStart = _safeStartOffset(widget.block, widget.fragment);
    final safeEnd = _safeEndOffset(widget.block, widget.fragment, safeStart);
    final atoms = _inlineAtomsForVisibleRange(
      text: _controller.text,
      block: widget.block,
      globalStart: safeStart,
      globalEnd: safeEnd,
    );
    for (final atom in atoms) {
      if (offset >= atom.localRange.start && offset <= atom.localRange.end) {
        return TextSelection(baseOffset: atom.localRange.start, extentOffset: atom.localRange.end);
      }
    }
    return TextSelection.collapsed(offset: offset);
  }

  Widget _buildRenderedInlineMathParagraph(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _handleReferencePointerHover,
        onPointerDown: (event) {
          _handleReferencePointerDown(event);
          _startInlineMathSourceEditing(event.localPosition);
        },
        child: MouseRegion(
          cursor: widget.editable ? SystemMouseCursors.text : MouseCursor.defer,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.transparent),
            ),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Align(
                alignment: Alignment.topLeft,
                child: RichText(
                  text: TextSpan(
                    style: widget.style,
                    children: _renderedInlineAtomSpansForRange(
                      context: context,
                      text: _fragmentText(widget.block, widget.fragment),
                      block: widget.block,
                      globalStart: _safeStartOffset(widget.block, widget.fragment),
                      globalEnd: _safeEndOffset(
                        widget.block,
                        widget.fragment,
                        _safeStartOffset(widget.block, widget.fragment),
                      ),
                      baseStyle: widget.style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.onActiveFieldChanged(null);
    _hideReferencePreview();
    _stopSelectionSync();
    _controller.removeListener(_notifyActiveSelection);
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!_inlineMathSourceEditing && !_focusNode.hasFocus && _fragmentHasInlineAtoms) {
      return _buildRenderedInlineMathParagraph(context);
    }
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: _handleReferencePointerHover,
        onPointerDown: (event) {
          _handleReferencePointerDown(event);
          _scheduleActiveSelectionNotification();
        },
        onPointerUp: (_) => _scheduleActiveSelectionNotification(),
        onPointerCancel: (_) => _scheduleActiveSelectionNotification(),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _handleChanged,
          onTap: _scheduleActiveSelectionNotification,
          expands: true,
        minLines: null,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textAlignVertical: TextAlignVertical.top,
        style: widget.style,
        cursorHeight: (widget.style.fontSize ?? 14) * (widget.style.height ?? 1.35),
        scrollPhysics: const NeverScrollableScrollPhysics(),
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isCollapsed: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

class _ReferencePreviewCard extends StatelessWidget {
  const _ReferencePreviewCard({
    required this.inlineReference,
    required this.citationSettings,
    required this.pinned,
    required this.onTogglePinned,
    required this.onOpen,
    required this.onCopy,
    required this.onUnlink,
    required this.onClose,
    this.onCitationModeChanged,
  });

  final TextSystemInlineReferenceMark inlineReference;
  final TextSystemCitationSettings citationSettings;
  final bool pinned;
  final VoidCallback onTogglePinned;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onUnlink;
  final VoidCallback onClose;
  final ValueChanged<TextSystemCitationInlineMode>? onCitationModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _referencePreviewTitle(inlineReference);
    final subtitle = _referencePreviewSubtitle(inlineReference, citationSettings);
    final locator = _referencePreviewLocator(inlineReference);
    final uri = inlineReference.uri?.toString();
    final sourceName = _referencePreviewSourceName(inlineReference);
    final excerpt = _referencePreviewExcerpt(inlineReference);
    final workStatePills = _referencePreviewWorkStatePills(inlineReference);
    final currentMode = TextSystemCitationInlineModeX.fromId(
      inlineReference.metadata['citationInlineMode'] as String?,
    );

    return Material(
      elevation: 10,
      color: colorScheme.surface,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.72)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _referencePreviewIcon(inlineReference.kind),
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inlineReference.kind.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: pinned ? 'Unpin preview' : 'Pin preview',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: onTogglePinned,
                    icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
              if (locator != null || uri != null || sourceName != null || workStatePills.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (sourceName != null)
                      _ReferencePreviewPill(icon: Icons.picture_as_pdf_outlined, label: sourceName),
                    if (locator != null)
                      _ReferencePreviewPill(icon: Icons.pin_drop_outlined, label: locator),
                    for (final pill in workStatePills) pill,
                    if (uri != null)
                      _ReferencePreviewPill(icon: Icons.language, label: Uri.tryParse(uri)?.host.isNotEmpty == true ? Uri.parse(uri).host : uri),
                  ],
                ),
              ],
              if (excerpt != null) ...[
                const SizedBox(height: 8),
                Text(
                  excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (inlineReference.isCitation && onCitationModeChanged != null) ...[
                const SizedBox(height: 10),
                SegmentedButton<TextSystemCitationInlineMode>(
                  segments: TextSystemCitationInlineMode.values
                      .map(
                        (mode) => ButtonSegment<TextSystemCitationInlineMode>(
                          value: mode,
                          label: Text(mode == TextSystemCitationInlineMode.parenthetical ? 'Parenthetical' : 'Narrative'),
                        ),
                      )
                      .toList(growable: false),
                  selected: <TextSystemCitationInlineMode>{currentMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    onCitationModeChanged!(selection.single);
                  },
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Ctrl/Cmd + Enter opens the target. Escape closes the preview.',
                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                  TextButton.icon(
                    onPressed: onUnlink,
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Unlink'),
                  ),
                  FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(_referencePreviewOpenLabel(inlineReference)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferencePreviewPill extends StatelessWidget {
  const _ReferencePreviewPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label.length > 42 ? '${label.substring(0, 39)}…' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String _referencePreviewTitle(TextSystemInlineReferenceMark inlineReference) {
  final metadataTitle = inlineReference.metadata['title']?.toString().trim();
  if (metadataTitle != null && metadataTitle.isNotEmpty) return metadataTitle;
  final citationText = inlineReference.metadata['citationText']?.toString().trim();
  if (inlineReference.isCitation && citationText != null && citationText.isNotEmpty) {
    return citationText;
  }
  final label = inlineReference.label.trim();
  if (label.isNotEmpty) return label;
  return inlineReference.kind.label;
}

String? _referencePreviewSubtitle(
  TextSystemInlineReferenceMark inlineReference,
  TextSystemCitationSettings citationSettings,
) {
  if (inlineReference.isCitation) {
    final source = TextSystemCitationSource.fromInlineMark(inlineReference);
    final parts = <String>[
      if (source.authors.isNotEmpty) source.authors.join(', '),
      if (source.year != null && source.year!.trim().isNotEmpty) source.year!.trim(),
      if (source.containerTitle != null && source.containerTitle!.trim().isNotEmpty) source.containerTitle!.trim(),
      if (_referencePreviewSourceName(inlineReference) != null) _referencePreviewSourceName(inlineReference)!,
      citationSettings.style.label,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
  final selectedText = inlineReference.selectedText?.trim();
  final target = inlineReference.targetId.trim();
  final parts = <String>[
    if (selectedText != null && selectedText.isNotEmpty) 'Text: $selectedText',
    if (target.isNotEmpty) 'Target: $target',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _referencePreviewLocator(TextSystemInlineReferenceMark inlineReference) {
  final sourceLocator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final sourcePageLabel = sourceLocator?.pageLabel?.trim();
  if (sourcePageLabel != null && sourcePageLabel.isNotEmpty) return sourcePageLabel;
  final sourcePage = sourceLocator?.effectivePageNumber;
  if (sourcePage != null && sourcePage > 0) return 'p. $sourcePage';

  final locator = inlineReference.metadata['locator']?.toString().trim();
  if (locator != null && locator.isNotEmpty) {
    if (locator.startsWith('p.') || locator.startsWith('pp.')) return locator;
    return 'p. $locator';
  }
  final page = inlineReference.metadata['page']?.toString().trim() ??
      inlineReference.metadata['pageNumber']?.toString().trim();
  if (page != null && page.isNotEmpty) return 'p. $page';
  return null;
}

String? _referencePreviewSourceName(TextSystemInlineReferenceMark inlineReference) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final title = locator?.sourceTitle?.trim();
  if (title != null && title.isNotEmpty) return title;

  final metadataTitle = inlineReference.metadata['sourceTitle']?.toString().trim();
  if (metadataTitle != null && metadataTitle.isNotEmpty) return metadataTitle;
  return null;
}

String? _referencePreviewExcerpt(TextSystemInlineReferenceMark inlineReference) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final excerpt = locator?.excerpt?.trim() ?? inlineReference.metadata['excerpt']?.toString().trim();
  if (excerpt == null || excerpt.isEmpty) return null;
  return excerpt.length <= 180 ? '“$excerpt”' : '“${excerpt.substring(0, 177)}…”';
}

List<_ReferencePreviewPill> _referencePreviewWorkStatePills(
  TextSystemInlineReferenceMark inlineReference,
) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final workState = locator?.workState ?? _mapFromMetadata(inlineReference.metadata['workState']);
  final sidecarNotes = _intFromObject(workState['sidecarNoteCount']);
  final highlights = _intFromObject(workState['highlightCount']);
  final openTodos = _intFromObject(workState['openTodoCount']);

  return <_ReferencePreviewPill>[
    if (sidecarNotes != null && sidecarNotes > 0)
      _ReferencePreviewPill(
        icon: Icons.sticky_note_2_outlined,
        label: '$sidecarNotes note${sidecarNotes == 1 ? '' : 's'}',
      ),
    if (highlights != null && highlights > 0)
      _ReferencePreviewPill(
        icon: Icons.highlight_outlined,
        label: '$highlights highlight${highlights == 1 ? '' : 's'}',
      ),
    if (openTodos != null && openTodos > 0)
      _ReferencePreviewPill(
        icon: Icons.check_circle_outline_rounded,
        label: '$openTodos TODO${openTodos == 1 ? '' : 's'}',
      ),
  ];
}

String _referencePreviewOpenLabel(TextSystemInlineReferenceMark inlineReference) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  if (locator?.hasPdfTarget == true) return 'Open PDF';
  return 'Open';
}

Map<String, Object?> _mapFromMetadata(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?));
  }
  return const <String, Object?>{};
}

int? _intFromObject(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _referencePreviewClipboardText(TextSystemInlineReferenceMark inlineReference) {
  final lines = <String>[
    '${inlineReference.kind.label}: ${_referencePreviewTitle(inlineReference)}',
    if (_referencePreviewSubtitle(inlineReference, const TextSystemCitationSettings()) != null)
      _referencePreviewSubtitle(inlineReference, const TextSystemCitationSettings())!,
    if (_referencePreviewSourceName(inlineReference) != null) _referencePreviewSourceName(inlineReference)!,
    if (_referencePreviewLocator(inlineReference) != null) _referencePreviewLocator(inlineReference)!,
    if (_referencePreviewExcerpt(inlineReference) != null) _referencePreviewExcerpt(inlineReference)!,
    if (inlineReference.uri != null) inlineReference.uri.toString(),
    'targetId: ${inlineReference.targetId}',
  ];
  return lines.join('\n');
}

IconData _referencePreviewIcon(TextSystemReferenceTargetKind kind) {
  return switch (kind) {
    TextSystemReferenceTargetKind.citation => Icons.format_quote,
    TextSystemReferenceTargetKind.source => Icons.picture_as_pdf_outlined,
    TextSystemReferenceTargetKind.document => Icons.description_outlined,
    TextSystemReferenceTargetKind.project => Icons.folder_open,
    TextSystemReferenceTargetKind.todo => Icons.check_circle_outline,
    TextSystemReferenceTargetKind.link => Icons.link,
    TextSystemReferenceTargetKind.figure => Icons.image_outlined,
    TextSystemReferenceTargetKind.table => Icons.table_chart_outlined,
    TextSystemReferenceTargetKind.unknown => Icons.bookmark_border,
  };
}


class _ContinuationChip extends StatelessWidget {
  const _ContinuationChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
