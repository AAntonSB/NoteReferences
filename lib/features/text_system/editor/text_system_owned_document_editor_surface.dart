import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../core/text_system_document_fragment.dart';
import '../core/text_system_document_layout_index.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_range.dart';
import '../references/actions/text_system_reference_actions.dart';
import '../references/citations/text_system_citation.dart';
import '../styles/text_system_document_style.dart';
import '../page/text_system_layout_style_resolver.dart';
import '../page/text_system_page_furniture.dart';
import '../page/text_system_page_setup.dart';
import '../page/text_system_paged_block_layout.dart';
import 'text_system_editor_caret_overlay.dart';
import 'text_system_editor_composing_overlay.dart';
import 'text_system_editor_hit_test.dart';
import 'text_system_editor_layout_snapshot.dart';
import 'text_system_editor_marked_text_layout.dart';
import 'text_system_inline_atom_renderer.dart';
import 'text_system_inline_math_editor_controller.dart';
import 'text_system_inline_reference_interaction_controller.dart';
import 'text_system_owned_editor_command_controller.dart';
import 'text_system_editor_selection_controller.dart';
import 'text_system_editor_selection_overlay.dart';
import 'text_system_editor_selection_state.dart';
import 'text_system_editor_text_input_client.dart';
import 'objects/owned_content_object_geometry.dart';
import 'objects/owned_equation_authoring_surface.dart';
import 'objects/owned_equation_structure_model.dart';

const String _ownedMarginAnnotationsMetadataKey = 'textSystemMarginAnnotations';

/// First owned-editor rendering surface.
///
/// Phase 16H keeps this surface experimental but lets it own the first basic
/// editing and cross-block selection paths plus a real platform text-input
/// bridge for IME/dead-key/emoji composition. The owned editor remains the
/// document source of truth; the input client only owns transient composition
/// state.
class TextSystemOwnedDocumentEditorSurface extends StatefulWidget {
  const TextSystemOwnedDocumentEditorSurface({
    super.key,
    required this.textController,
    required this.document,
    required this.pageSetup,
    required this.pageMaxWidth,
    this.pageZoom = 1.0,
    this.pageFurniture = const TextSystemPageFurniture.defaults(),
    required this.focusMode,
    this.showMarginGuides = true,
    this.showDebugBanner = true,
    this.showPageHeader = true,
    this.pageGap,
    this.verticalPadding,
    this.horizontalPadding,
    this.scrollController,
    this.commandController,
    this.referenceActionRepository,
    this.onOpenReferenceTarget,
    this.onLayoutSnapshotChanged,
  });

  final TextSystemController textController;
  final TextSystemDocument document;
  final TextSystemPageSetup pageSetup;
  final double pageMaxWidth;
  final double pageZoom;
  final TextSystemPageFurniture pageFurniture;
  final bool focusMode;
  final bool showMarginGuides;
  final bool showDebugBanner;
  final bool showPageHeader;
  final double? pageGap;
  final double? verticalPadding;
  final double? horizontalPadding;
  final ScrollController? scrollController;
  final TextSystemOwnedEditorCommandController? commandController;
  final TextSystemReferenceActionRepository? referenceActionRepository;
  final ValueChanged<TextSystemInlineReferenceMark>? onOpenReferenceTarget;
  final ValueChanged<TextSystemEditorLayoutSnapshot>? onLayoutSnapshotChanged;

  static const double _a4PortraitReferenceWidthMm = 210;
  static const double _pageHeaderHeight = 42;
  static const double _pageHeaderGap = 8;
  static const double _pageGap = 76;

  @override
  State<TextSystemOwnedDocumentEditorSurface> createState() => TextSystemOwnedDocumentEditorSurfaceState();
}

class TextSystemOwnedDocumentEditorSurfaceState extends State<TextSystemOwnedDocumentEditorSurface> implements TextSystemOwnedEditorCommandTarget {
  final FocusNode _focusNode = FocusNode(debugLabel: 'TextSystemOwnedDocumentEditorSurface');
  final TextSystemEditorSelectionController _selectionController = TextSystemEditorSelectionController();
  final TextSystemInlineMathEditorController _inlineMathController = TextSystemInlineMathEditorController();
  late final TextSystemEditorTextInputClient _textInputClient;
  late TextSystemInlineReferenceInteractionController _inlineReferenceController;

  TextSystemEditorHitTestResult? _lastHit;
  TextSystemEditorLayoutSnapshot? _lastSnapshot;
  int _equationCompletionHighlightedIndex = 0;
  String? _equationCompletionPrefixSignature;
  final Map<String, int> _equationCompletionUsageCounts = <String, int>{};

  TextSystemEditorSelectionState get _selectionState => _selectionController.state;

  @override
  void initState() {
    super.initState();
    _textInputClient = TextSystemEditorTextInputClient(
      canAcceptInput: _canAcceptTextInput,
      activeRange: () => _activeCommandRange,
      activeTextPosition: () => _activeTextPosition,
      commitText: _commitTextFromInputClient,
      deleteBackward: () => _deleteBackward(),
      deleteForward: () => _deleteForward(),
      insertNewline: () => _splitCurrentBlock(),
    );
    _inlineReferenceController = TextSystemInlineReferenceInteractionController(
      contextForOverlay: () => context,
      textController: widget.textController,
      referenceActionRepository: widget.referenceActionRepository,
      onOpenReferenceTarget: widget.onOpenReferenceTarget,
      onChanged: () {
        widget.commandController?.scheduleStateRefresh();
        if (mounted) setState(() {});
      },
    );
    _focusNode.addListener(_handleFocusNodeChanged);
    _textInputClient.addListener(_handleTextInputClientChanged);
    _selectionController.addListener(_handleSelectionControllerChanged);
    _inlineMathController.addListener(_handleInlineMathControllerChanged);
    widget.commandController?.attachSurface(this);
  }

  @override
  void didUpdateWidget(covariant TextSystemOwnedDocumentEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commandController != widget.commandController) {
      oldWidget.commandController?.detachSurface(this);
      widget.commandController?.attachSurface(this);
    }
    if (oldWidget.referenceActionRepository != widget.referenceActionRepository ||
        oldWidget.onOpenReferenceTarget != widget.onOpenReferenceTarget ||
        oldWidget.textController != widget.textController) {
      _inlineReferenceController.dispose();
      _inlineReferenceController = TextSystemInlineReferenceInteractionController(
        contextForOverlay: () => context,
        textController: widget.textController,
        referenceActionRepository: widget.referenceActionRepository,
        onOpenReferenceTarget: widget.onOpenReferenceTarget,
        onChanged: () {
          widget.commandController?.scheduleStateRefresh();
          if (mounted) setState(() {});
        },
      );
    }
  }

  @override
  void dispose() {
    widget.commandController?.detachSurface(this);
    _focusNode.removeListener(_handleFocusNodeChanged);
    _textInputClient.removeListener(_handleTextInputClientChanged);
    _textInputClient.close();
    _inlineReferenceController.dispose();
    _inlineMathController.removeListener(_handleInlineMathControllerChanged);
    _inlineMathController.dispose();
    _selectionController.removeListener(_handleSelectionControllerChanged);
    _selectionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSelectionControllerChanged() {
    if (!mounted) return;
    _inlineMathController.syncWithDocumentSelection(_activeCommandRange ?? _selectionState.range);
    if (_focusNode.hasFocus) {
      _openTextInputClient();
      _textInputClient.refreshFromEditorSelection();
    }
    widget.commandController?.scheduleStateRefresh();
    setState(() {});
  }

  void _handleInlineMathControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleFocusNodeChanged() {
    if (_focusNode.hasFocus) {
      _openTextInputClient();
    } else {
      _textInputClient.close();
    }
  }

  void _handleTextInputClientChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _openTextInputClient() {
    if (!mounted) return;
    _textInputClient.open(viewId: View.of(context).viewId);
  }


  @override
  Widget build(BuildContext context) {
    final document = widget.textController.document;
    final displayDocument = _documentWithOwnedListIndexes(document);
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleEditorKeyEvent,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
        child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding =
              widget.horizontalPadding ?? (widget.focusMode ? 30.0 : 58.0);
          final verticalPadding =
              widget.verticalPadding ?? (widget.focusMode ? 30.0 : 58.0);
          final pageHeaderHeight = widget.showPageHeader
              ? TextSystemOwnedDocumentEditorSurface._pageHeaderHeight
              : 0.0;
          final pageHeaderGap = widget.showPageHeader
              ? TextSystemOwnedDocumentEditorSurface._pageHeaderGap
              : 0.0;
          final pageGap = widget.pageGap ??
              TextSystemOwnedDocumentEditorSurface._pageGap;
          final viewportContentWidth = math.max(320.0, constraints.maxWidth - horizontalPadding * 2);
          final zoom = widget.pageZoom.clamp(0.75, 1.75).toDouble();
          final physicalWidth = widget.pageMaxWidth * (widget.pageSetup.pageWidthMm / TextSystemOwnedDocumentEditorSurface._a4PortraitReferenceWidthMm);
          final pageWidth = math.max(320.0, physicalWidth);
          final pageHeight = pageWidth * widget.pageSetup.heightToWidthRatio;
          final margins = widget.pageSetup.margins.toPagePadding(
            pageWidth,
            widget.pageSetup.pageWidthMm,
          );
          final layout = TextSystemPagedBlockLayoutEngine.layout(
            context: context,
            document: document,
            pageSetup: widget.pageSetup,
            pageWidthPx: pageWidth,
            activeDisplayEquationBlockId: _activeDisplayEquationBlockForRange()?.id,
          );
          final pageOuterHeight = pageHeaderHeight + pageHeaderGap + pageHeight;
          final horizontalContentWidth = math.max(viewportContentWidth, pageWidth * zoom);
          final snapshot = _OwnedDocumentLayoutSnapshotBuilder.build(
            document: displayDocument,
            layout: layout,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            pageOuterHeight: pageOuterHeight,
            pageGap: pageGap,
            margins: margins,
            revision: widget.textController.revision,
          );
          _lastSnapshot = snapshot;
          widget.onLayoutSnapshotChanged?.call(snapshot);

          return Scrollbar(
            controller: widget.scrollController,
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: EdgeInsets.symmetric(vertical: verticalPadding),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: horizontalContentWidth),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.showDebugBanner) ...[
                          _OwnedDocumentEditorBanner(
                            layout: layout,
                            snapshot: snapshot,
                            selectionState: _selectionState,
                            lastHit: _lastHit,
                          ),
                          const SizedBox(height: 18),
                        ],
                        for (final page in layout.pages)
                          Padding(
                            padding: EdgeInsets.only(bottom: pageGap * zoom),
                            child: SizedBox(
                              width: pageWidth * zoom,
                              height: pageOuterHeight * zoom,
                              child: FittedBox(
                                fit: BoxFit.fill,
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: pageWidth,
                                  height: pageOuterHeight,
                                  child: _OwnedDocumentPageView(
                                    document: displayDocument,
                                    textController: widget.textController,
                                    page: page,
                                    pageCount: layout.pageCount,
                                    pageSetup: widget.pageSetup,
                                    pageFurniture: widget.pageFurniture,
                                    pageWidth: pageWidth,
                                    pageHeight: pageHeight,
                                    margins: margins,
                                    showMarginGuides: widget.showMarginGuides,
                                    showPageHeader: widget.showPageHeader,
                                    pageHeaderHeight: pageHeaderHeight,
                                    pageHeaderGap: pageHeaderGap,
                                    snapshot: snapshot,
                                    selectionState: _selectionState,
                                    textInputClient: _textInputClient,
                                    activeInlineAtomSourceRange: _inlineMathController.activeRange?.normalized(),
                                    onEquationInsertFraction: () => _insertEquationFraction(),
                                    onEquationInsertSuperscript: () => _insertEquationSuperscript(),
                                    onEquationInsertSubscript: () => _insertEquationSubscript(),
                                    onEquationInsertText: () => _insertEquationTextMode(),
                                    onEquationInsertDerivative: () => _insertEquationDerivative(),
                                    onEquationInsertMatrix: () => _insertEquationMatrix(),
                                    onEquationInsertAligned: () => _insertEquationAligned(),
                                    onEquationInsertCases: () => _insertEquationCases(),
                                    onEquationInsertMatrixRow: () => _insertEquationMatrixRow(),
                                    onEquationInsertMatrixColumn: () => _insertEquationMatrixColumn(),
                                    onEquationInsertAlignedLine: () => _insertEquationAlignedLine(),
                                    onEquationInsertAlignmentMarker: () => _insertEquationAlignmentMarker(),
                                    onEquationInsertCasesRow: () => _insertEquationCasesRow(),
                                    onEquationInsertSymbol: (source) => _insertEquationRawSource(source),
                                    onEquationAcceptCommandCompletion: (completion, caretOffset) =>
                                        _acceptEquationCommandCompletion(completion, caretOffset),
                                    equationCompletionHighlightedIndex: _equationCompletionHighlightedIndex,
                                    equationCompletionUsageCounts: _equationCompletionUsageCounts,
                                    onEquationFormatSource: () => _formatActiveEquationSource(),
                                    onEquationJumpNextSlot: () => _jumpEquationSlot(forward: true),
                                    onEquationJumpPreviousSlot: () => _jumpEquationSlot(forward: false),
                                    onEquationPreviewSourceOffset: (position) => _moveEquationPreviewCaret(position),
                                    onEquationPreviewSourceRange: (range) => _selectEquationPreviewRange(range),
                                    onEquationStructureCellSelected: (rowIndex, columnIndex) =>
                                        _jumpToEquationStructureCell(rowIndex, columnIndex),
                                    onEquationToggleNumbering: () => _toggleActiveEquationNumbering(),
                                    onEquationEditLabel: () => _editActiveEquationLabel(),
                                    onEquationCopyReference: () => _copyActiveEquationReference(),
                                    onPageTap: (details) => _handlePageTap(
                                      context: context,
                                      snapshot: snapshot,
                                      layout: layout,
                                      page: page,
                                      margins: margins,
                                      localPageOffset: details.localPosition,
                                      globalPosition: details.globalPosition,
                                    ),
                                    onPageDoubleTap: (details) => _handlePageDoubleTap(
                                      context: context,
                                      snapshot: snapshot,
                                      layout: layout,
                                      page: page,
                                      margins: margins,
                                      localPageOffset: details.localPosition,
                                    ),
                                    onPageHover: (event) => _handlePageHover(
                                      context: context,
                                      snapshot: snapshot,
                                      layout: layout,
                                      page: page,
                                      margins: margins,
                                      localPageOffset: event.localPosition,
                                      globalPosition: event.position,
                                    ),
                                    onPageExit: (_) => _inlineReferenceController.scheduleClose(),
                                    onPageDragStart: (localPageOffset) => _handlePageDragStart(
                                      context: context,
                                      snapshot: snapshot,
                                      layout: layout,
                                      page: page,
                                      margins: margins,
                                      localPageOffset: localPageOffset,
                                    ),
                                    onPageDragUpdate: (localPageOffset) => _handlePageDragUpdate(
                                      context: context,
                                      snapshot: snapshot,
                                      layout: layout,
                                      page: page,
                                      margins: margins,
                                      localPageOffset: localPageOffset,
                                    ),
                                    onPageDragEnd: _handlePageDragEnd,
                                    onPageDragCancel: _handlePageDragCancel,
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
    );
  }





  @override
  bool get ownedCommandTargetMounted => mounted;

  @override
  bool get ownedCanCreateReference => widget.referenceActionRepository != null;
  @override
  bool get ownedCanUndo => widget.textController.canUndo;
  @override
  bool get ownedCanRedo => widget.textController.canRedo;

  TextSystemDocumentRange? get _activeCommandRange {
    final selection = _selectionState.selection;
    if (selection == null) return null;
    if (selection.isObject || selection.isTableCell || selection.isInlineAtom) return null;
    return selection.normalizedRange;
  }

  TextSystemDocumentRange? get _activeNonCollapsedTextRange {
    final range = _activeCommandRange;
    if (range == null || range.isCollapsed) return null;
    if (!_rangeHasVisibleText(range)) return null;
    return range;
  }

  TextSystemDocumentRange? get _activeInsertRange {
    final range = _activeCommandRange;
    if (range != null) {
      final normalized = range.normalized();
      if (_canInsertAtPosition(normalized.end)) return normalized;
    }

    final object = _selectedObjectBlock;
    if (object != null) {
      final position = _caretPositionAfterObject(object) ?? _caretPositionBeforeObject(object);
      if (position != null && _canInsertAtPosition(position)) {
        return TextSystemDocumentRange.collapsed(position);
      }
    }

    return null;
  }

  TextSystemBlock? get _activeStyleBlock {
    final range = _activeCommandRange;
    final position = range?.normalized().start ?? _activeTextPosition;
    if (position == null) return null;
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return null;
    if (_isFootnoteBlock(block)) return null;
    return block;
  }

  bool _canInsertAtPosition(TextSystemDocumentPosition position) {
    final block = _blockAtPosition(position);
    return block != null && _canEditBlockText(block) && !_isFootnoteBlock(block);
  }

  bool _canAcceptTextInput() {
    final range = _activeCommandRange;
    if (range == null) return false;
    final normalized = range.normalized();
    final document = widget.textController.document;
    if (document.blocks.isEmpty) return false;
    final startIndex = normalized.start.blockIndex.clamp(0, document.blocks.length - 1).toInt();
    final endIndex = normalized.end.blockIndex.clamp(startIndex, document.blocks.length - 1).toInt();
    for (var i = startIndex; i <= endIndex; i++) {
      if (!_canEditBlockText(document.blocks[i])) return false;
    }
    return true;
  }

  TextSystemBlock? get _selectedObjectBlock {
    final selection = _selectionState.selection;
    if (selection == null || !selection.isObject) return null;
    final blockId = selection.objectBlockId ?? selection.anchor.blockId;
    final block = widget.textController.document.blockById(blockId);
    if (block == null || !_isOwnedAtomicBlock(block)) return null;
    return block;
  }

  int get _selectedObjectIndex {
    final block = _selectedObjectBlock;
    if (block == null) return -1;
    return widget.textController.document.blocks.indexWhere((candidate) => candidate.id == block.id);
  }

  @override
  bool get ownedCanCopySelection => _activeNonCollapsedTextRange != null || _selectedObjectBlock != null;
  @override
  bool get ownedCanCutSelection => _activeNonCollapsedTextRange != null || _selectedObjectBlock != null;
  @override
  bool get ownedCanPastePlainText => _activeCommandRange != null || _selectedObjectBlock != null;
  @override
  bool get ownedCanChangeActiveBlockStyle => _activeStyleBlock != null;
  @override
  bool get ownedCanInsertAtSelection => _activeInsertRange != null;
  @override
  bool get ownedCanInsertEmbeddedTodo => false;

  @override
  bool get ownedHasSelectedObject => _selectedObjectBlock != null;
  @override
  String get ownedSelectedObjectKind => _selectedObjectBlock == null ? '' : _objectKindForBlock(_selectedObjectBlock!);
  @override
  String get ownedSelectedObjectStatusLabel => _selectedObjectBlock == null ? '' : _objectStatusLabel(_selectedObjectBlock!);
  @override
  bool get ownedCanMoveSelectedObjectUp => _selectedObjectIndex > 0;
  @override
  bool get ownedCanMoveSelectedObjectDown {
    final index = _selectedObjectIndex;
    return index >= 0 && index + 1 < widget.textController.document.blocks.length;
  }
  @override
  bool get ownedCanDuplicateSelectedObject => _selectedObjectBlock != null && !_isStructuralBreakBlock(_selectedObjectBlock!);
  @override
  bool get ownedCanDeleteSelectedObject => _selectedObjectBlock != null;
  @override
  bool get ownedCanCopySelectedObjectReference => _selectedObjectBlock != null && !_isStructuralBreakBlock(_selectedObjectBlock!);
  @override
  bool get ownedCanCommentOnSelectedObject => _selectedObjectBlock != null && !_isStructuralBreakBlock(_selectedObjectBlock!);

  @override
  bool ownedCanToggleMark(TextMarkKind kind) {
    if (kind == TextMarkKind.link || kind == TextMarkKind.strikethrough) {
      return false;
    }
    return _activeNonCollapsedTextRange != null;
  }

  @override
  void ownedPerformUndo() {
    if (!widget.textController.canUndo) return;
    final fallback = _activeCommandRange?.normalized().start;
    widget.textController.undo();
    _restoreCaretNear(fallback);
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  void ownedPerformRedo() {
    if (!widget.textController.canRedo) return;
    final fallback = _activeCommandRange?.normalized().start;
    widget.textController.redo();
    _restoreCaretNear(fallback);
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  Future<void> ownedCopySelectionToClipboard() async {
    final object = _selectedObjectBlock;
    if (object != null) {
      final fragment = widget.textController.copyDocumentBlocksAsFragment(
        <String>[object.id],
        label: 'Copy ${_objectKindForBlock(object)}',
      );
      await Clipboard.setData(ClipboardData(text: _clipboardTextForObject(object, fragment.plainText)));
      widget.commandController?.scheduleStateRefresh();
      return;
    }

    final range = _activeNonCollapsedTextRange;
    if (range == null) return;
    final fragment = widget.textController.copyDocumentFragment(range);
    await Clipboard.setData(ClipboardData(text: fragment.plainText));
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  Future<void> ownedCutSelectionToClipboard() async {
    final object = _selectedObjectBlock;
    if (object != null) {
      await ownedCopySelectionToClipboard();
      ownedDeleteSelectedObject();
      return;
    }

    final range = _activeNonCollapsedTextRange;
    if (range == null) return;
    final normalized = range.normalized();
    final collapseTarget = normalized.start;
    final fragment = widget.textController.cutDocumentRange(normalized);
    await Clipboard.setData(ClipboardData(text: fragment.plainText));
    _restoreCaretNear(collapseTarget);
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  Future<void> ownedPasteAtSelection() async {
    var range = _activeCommandRange;
    final object = _selectedObjectBlock;
    if (range == null && object != null) {
      final position = _caretPositionAfterObject(object) ?? _caretPositionBeforeObject(object);
      if (position != null) {
        range = TextSystemDocumentRange.collapsed(position);
      }
    }
    if (range == null) return;

    final internalFragment = widget.textController.internalDocumentClipboard;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;

    final pastedText = clipboard?.text?.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if ((internalFragment == null || internalFragment.isEmpty) && (pastedText == null || pastedText.isEmpty)) {
      return;
    }

    if (internalFragment != null && !internalFragment.isEmpty && _fragmentContainsOwnedAtomicBlock(internalFragment)) {
      final inserted = _pasteAtomicFragmentAtRange(internalFragment, range);
      _restoreCaretNear(inserted);
      widget.commandController?.scheduleStateRefresh();
      return;
    }

    final result = internalFragment != null && !internalFragment.isEmpty
        ? widget.textController.pasteDocumentClipboardAtRange(range)
        : widget.textController.replaceDocumentRangeWithPlainText(
            range,
            pastedText ?? '',
            label: 'Paste plain text',
          );
    _restoreCaretNear(result.insertedRange.normalized().end);
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  Future<void> ownedCopySelectedObjectReferenceToClipboard() async {
    final object = _selectedObjectBlock;
    if (object == null) return;
    await Clipboard.setData(ClipboardData(text: _objectReferenceText(object)));
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  Future<void> ownedAddCommentToSelectedObject() async {
    final object = _selectedObjectBlock;
    if (object == null || _isStructuralBreakBlock(object)) return;
    final text = await _showOwnedObjectCommentDialog(context: context, objectLabel: _objectStatusLabel(object));
    if (!mounted || text == null || text.trim().isEmpty) return;
    final now = DateTime.now();
    final annotations = _ownedMarginAnnotationsFromDocument(widget.textController.document);
    final nextAnnotations = <Map<String, Object?>>[
      ...annotations,
      <String, Object?>{
        'id': 'owned-object-comment-${now.microsecondsSinceEpoch}',
        'blockId': object.id,
        'textOffset': 0,
        'type': 'comment',
        'text': text.trim(),
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'attachedToObject': true,
        'objectKind': _objectKindForBlock(object),
      },
    ];
    _replaceOwnedMarginAnnotations(nextAnnotations, label: 'Add object comment');
  }

  @override
  void ownedDuplicateSelectedObject() {
    final object = _selectedObjectBlock;
    if (object == null || _isStructuralBreakBlock(object)) return;
    final blocks = widget.textController.document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == object.id);
    if (index < 0) return;
    final duplicate = _duplicatedObjectBlock(object);
    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < blocks.length; i++) ...[
        blocks[i],
        if (i == index) duplicate,
      ],
    ];
    widget.textController.replaceDocument(
      widget.textController.document.copyWith(blocks: nextBlocks),
      label: 'Duplicate ${_objectKindForBlock(object)}',
    );
    _selectObjectBlock(duplicate.id, source: TextSystemEditorSelectionSource.command);
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  void ownedMoveSelectedObjectUp() {
    _moveSelectedObject(-1);
  }

  @override
  void ownedMoveSelectedObjectDown() {
    _moveSelectedObject(1);
  }

  @override
  void ownedDeleteSelectedObject() {
    final object = _selectedObjectBlock;
    if (object == null) return;
    final fallbackPosition = _caretPositionAfterObject(object) ?? _caretPositionBeforeObject(object);
    final blocks = widget.textController.document.blocks;
    final index = blocks.indexWhere((candidate) => candidate.id == object.id);
    if (index < 0) return;
    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < blocks.length; i++)
        if (i != index) blocks[i],
    ];
    TextSystemDocumentPosition? createdFallback;
    if (nextBlocks.isEmpty) {
      final paragraph = TextSystemBlock.paragraph(id: 'owned-empty-${DateTime.now().microsecondsSinceEpoch}', text: '');
      nextBlocks.add(paragraph);
      createdFallback = TextSystemDocumentPosition.text(blockId: paragraph.id, blockIndex: 0, offset: 0);
    }
    widget.textController.replaceDocument(
      widget.textController.document.copyWith(blocks: nextBlocks),
      label: 'Delete ${_objectKindForBlock(object)}',
    );
    _restoreCaretNear(createdFallback ?? fallbackPosition);
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  void ownedToggleMarkForActiveRange(TextMarkKind kind) {
    final range = _activeNonCollapsedTextRange;
    if (range == null) return;
    widget.textController.toggleMarkForDocumentRange(range, kind);
    widget.commandController?.scheduleStateRefresh();
    setState(() {});
  }

  @override
  bool ownedActiveRangeFullyCoveredBy(TextMarkKind kind) {
    final range = _activeNonCollapsedTextRange;
    if (range == null) return false;
    return _rangeFullyCoveredByKind(range, kind);
  }

  @override
  Future<void> ownedCreateReferenceForActiveSelection(TextSystemReferenceActionType actionType) async {
    await _createReferenceForActiveSelection(actionType);
  }

  @override
  void ownedChangeActiveBlockStyleById(String styleId) {
    final block = _activeStyleBlock;
    if (block == null) return;
    final blockIndex = widget.textController.document.blocks.indexWhere((candidate) => candidate.id == block.id);
    if (blockIndex < 0) return;
    final fallbackOffset = (_activeTextPosition?.offset ?? block.text.length).clamp(0, block.text.length).toInt();
    final fallback = TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: fallbackOffset,
    );
    final metadata = _ownedMetadataForStyle(styleId, block);

    switch (styleId) {
      case TextSystemDocumentStyleSheet.heading1:
        widget.textController.updateBlockType(block.id, TextSystemBlockType.heading, level: 1, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.heading2:
        widget.textController.updateBlockType(block.id, TextSystemBlockType.heading, level: 2, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.heading3:
        widget.textController.updateBlockType(block.id, TextSystemBlockType.heading, level: 3, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.quote:
        widget.textController.updateBlockType(block.id, TextSystemBlockType.quote, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.code:
        widget.textController.updateBlockType(block.id, TextSystemBlockType.code, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.listParagraph:
        widget.textController.updateListGroupBlockType(block.id, TextSystemBlockType.listItem, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.numberedList:
        widget.textController.updateListGroupBlockType(block.id, TextSystemBlockType.listItem, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.todo:
        widget.textController.updateListGroupBlockType(block.id, TextSystemBlockType.todo, checked: block.checked ?? false, metadata: metadata);
        break;
      case TextSystemDocumentStyleSheet.paragraph:
      default:
        widget.textController.updateBlockType(block.id, TextSystemBlockType.paragraph, metadata: metadata);
        break;
    }

    _restoreCaretNear(fallback);
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
  }

  @override
  void ownedInsertPageBreak() {
    _insertOwnedStructuralBreak(sectionBreak: false);
  }

  @override
  void ownedInsertSectionBreak() {
    _insertOwnedStructuralBreak(sectionBreak: true);
  }

  @override
  void ownedInsertFootnote() {
    final range = _activeInsertRange;
    if (range == null) {
      _showOwnedCommandSnack('Place the caret in a paragraph before inserting a footnote.');
      return;
    }
    final position = range.normalized().end;
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return;
    final target = widget.textController.insertFootnoteAt(
      position.blockId,
      position.offset.clamp(0, block.text.length).toInt(),
      initialText: '',
    );
    _restoreCaretNear(target);
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  Future<void> ownedInsertEmbeddedTodo() async {
    _showOwnedCommandSnack('Synced app TODO insertion still uses the Real pages fallback.');
  }

  @override
  Future<void> ownedInsertFigure() async {
    final draft = await _showOwnedAcademicFigureDraftDialog(
      context: context,
      document: widget.textController.document,
    );
    if (!mounted || draft == null) return;
    _insertOwnedAtomicBlock(
      _ownedAcademicFigureBlockFromDraft(draft),
      label: 'Insert figure',
      selectObjectAfterInsert: true,
    );
  }

  @override
  Future<void> ownedInsertTable() async {
    final draft = await _showOwnedAcademicTableDraftDialog(
      context: context,
      document: widget.textController.document,
    );
    if (!mounted || draft == null) return;
    _insertOwnedAtomicBlock(
      _ownedAcademicTableBlockFromDraft(draft),
      label: 'Insert table',
      selectObjectAfterInsert: true,
    );
  }

  @override
  Future<void> ownedInsertEquation() async {
    final draft = await _showOwnedAcademicEquationDraftDialog(
      context: context,
      document: widget.textController.document,
    );
    if (!mounted || draft == null) return;
    final range = _activeInsertRange;
    if (range == null) {
      _showOwnedCommandSnack('Place the caret where the display equation should be inserted.');
      return;
    }
    final block = _ownedAcademicEquationBlockFromDraft(draft);
    final target = _insertOwnedBlockAtRange(range, block, label: 'Insert display equation');
    if (target == null) return;
    final blockIndex = widget.textController.document.blocks.indexWhere((candidate) => candidate.id == block.id);
    if (blockIndex >= 0) {
      final innerStart = _ownedDisplayEquationInnerSourceStart(block.text);
      _setKeyboardCaret(TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: innerStart.clamp(0, block.text.length).toInt(),
      ));
    } else {
      _restoreCaretNear(target);
    }
    widget.commandController?.scheduleStateRefresh();
  }

  @override
  Future<void> ownedInsertInlineMath() async {
    final range = _activeInsertRange;
    if (range == null) {
      _showOwnedCommandSnack('Place the caret in a paragraph before inserting inline math.');
      return;
    }
    final normalized = range.normalized();
    if (normalized.start.blockId != normalized.end.blockId) {
      _showOwnedCommandSnack('Inline math can only be inserted inside one paragraph for now.');
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
    final block = widget.textController.document.blockById(inserted.start.blockId);
    final blockIndex = widget.textController.document.blocks.indexWhere((candidate) => candidate.id == inserted.start.blockId);
    if (block != null && blockIndex >= 0) {
      final atoms = TextSystemInlineAtomRenderer.atomsForVisibleRange(
        text: block.text,
        block: block,
        blockIndex: blockIndex,
        globalStart: 0,
        globalEnd: block.text.length,
      );
      for (final atom in atoms) {
        if (atom.isMath && atom.globalRange.start == inserted.start.offset && atom.globalRange.end == inserted.end.offset) {
          _inlineMathController.activate(atom);
          break;
        }
      }
    }
    _selectionController.selectDocumentRange(
      TextSystemDocumentRange(
        start: TextSystemDocumentPosition.text(blockId: inserted.start.blockId, blockIndex: inserted.start.blockIndex, offset: innerStart),
        end: TextSystemDocumentPosition.text(blockId: inserted.start.blockId, blockIndex: inserted.start.blockIndex, offset: innerEnd),
      ),
      source: TextSystemEditorSelectionSource.command,
    );
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
  }

  Map<String, Object?> _ownedMetadataForStyle(String styleId, TextSystemBlock block) {
    return switch (styleId) {
      TextSystemDocumentStyleSheet.listParagraph => <String, Object?>{
          ...block.metadata,
          'styleId': styleId,
          'ordered': false,
          'listKind': 'bullet',
        },
      TextSystemDocumentStyleSheet.numberedList => <String, Object?>{
          ...block.metadata,
          'styleId': styleId,
          'ordered': true,
          'listKind': 'numbered',
        },
      TextSystemDocumentStyleSheet.todo => <String, Object?>{
          ...block.metadata,
          'styleId': styleId,
          'listKind': 'todo',
        },
      _ => <String, Object?>{'styleId': styleId},
    };
  }

  void _insertOwnedStructuralBreak({required bool sectionBreak}) {
    final range = _activeInsertRange;
    if (range == null) {
      _showOwnedCommandSnack(sectionBreak
          ? 'Place the caret in a paragraph before inserting a section break.'
          : 'Place the caret in a paragraph before inserting a page break.');
      return;
    }
    final position = range.normalized().end;
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return;
    final target = sectionBreak
        ? widget.textController.insertSectionBreakAt(
            position.blockId,
            position.offset.clamp(0, block.text.length).toInt(),
            restartPageNumbering: true,
            pageNumberStartAt: 1,
          )
        : widget.textController.insertPageBreakAt(
            position.blockId,
            position.offset.clamp(0, block.text.length).toInt(),
          );
    _restoreCaretNear(target);
    widget.commandController?.scheduleStateRefresh();
  }

  void _insertOwnedAtomicBlock(
    TextSystemBlock block, {
    required String label,
    bool selectObjectAfterInsert = false,
  }) {
    final range = _activeInsertRange;
    if (range == null) {
      _showOwnedCommandSnack('Place the caret where the object should be inserted.');
      return;
    }
    final target = _insertOwnedBlockAtRange(range, block, label: label);
    if (target == null) return;
    if (selectObjectAfterInsert) {
      _selectObjectBlock(block.id, source: TextSystemEditorSelectionSource.command);
    } else {
      _restoreCaretNear(target);
    }
    widget.commandController?.scheduleStateRefresh();
  }

  TextSystemDocumentPosition? _insertOwnedBlockAtRange(
    TextSystemDocumentRange range,
    TextSystemBlock block, {
    required String label,
  }) {
    final normalized = range.normalized();
    if (!normalized.isCollapsed) {
      final deleted = widget.textController.deleteDocumentRange(normalized, label: 'Replace selection with object');
      final collapsed = deleted.insertedRange.normalized().start;
      return widget.textController.insertBlockAtPosition(
        collapsed.blockId,
        collapsed.offset,
        block,
        label: label,
      );
    }
    return widget.textController.insertBlockAtPosition(
      normalized.end.blockId,
      normalized.end.offset,
      block,
      label: label,
    );
  }

  TextSystemBlock _ownedPlaceholderObjectBlock({required String kind}) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return switch (kind) {
      'table' => TextSystemBlock(
          id: 'table-$now',
          type: TextSystemBlockType.custom,
          text: '',
          metadata: <String, Object?>{
            'kind': 'table',
            'styleId': TextSystemDocumentStyleSheet.custom,
            'caption': '',
            'rows': 3,
            'columns': 3,
            'cells': <List<String>>[
              <String>['', '', ''],
              <String>['', '', ''],
              <String>['', '', ''],
            ],
            'headerRows': 1,
            'captionPosition': 'above',
          },
        ),
      'equation' => TextSystemBlock(
          id: 'equation-$now',
          type: TextSystemBlockType.custom,
          text: '',
          metadata: <String, Object?>{
            'kind': 'equation',
            'styleId': TextSystemDocumentStyleSheet.custom,
            'latex': '',
            'numbered': false,
            'presentation': 'display',
          },
        ),
      _ => TextSystemBlock(
          id: 'figure-$now',
          type: TextSystemBlockType.custom,
          text: '',
          metadata: <String, Object?>{
            'kind': 'figure',
            'styleId': TextSystemDocumentStyleSheet.custom,
            'caption': '',
            'figureSize': 'medium',
            'captionPosition': 'below',
          },
        ),
    };
  }

  void _showOwnedCommandSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  bool _rangeHasVisibleText(TextSystemDocumentRange range) {
    return widget.textController.plainTextForDocumentRange(range).trim().isNotEmpty;
  }

  void _selectObjectBlock(
    String blockId, {
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.programmatic,
  }) {
    final document = widget.textController.document;
    final index = document.blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    final block = document.blocks[index];
    if (!_isOwnedAtomicBlock(block)) return;
    _selectionController.selectFromHit(
      TextSystemEditorHitTestResult(
        kind: _isStructuralBreakBlock(block)
            ? TextSystemEditorHitTargetKind.structuralBreak
            : TextSystemEditorHitTargetKind.objectBlock,
        globalOffset: Offset.zero,
        pageIndex: null,
        metadata: <String, Object?>{
          'commandSelection': true,
          'objectKind': _objectKindForBlock(block),
        },
        layoutHit: TextSystemDocumentLayoutHit(
          globalOffset: Offset.zero,
          fragment: TextSystemDocumentLayoutFragment(
            id: 'command-object-${block.id}',
            kind: _layoutKindForBlock(block),
            pageIndex: 0,
            globalRect: Rect.zero,
            blockId: block.id,
            blockIndex: index,
            start: TextSystemDocumentPosition.onBlock(blockId: block.id, blockIndex: index),
            end: TextSystemDocumentPosition.afterBlock(blockId: block.id, blockIndex: index),
          ),
          position: TextSystemDocumentPosition.onBlock(blockId: block.id, blockIndex: index),
          isExactHit: true,
        ),
      ),
      source: source,
    );
  }

  void _moveSelectedObject(int direction) {
    if (direction == 0) return;
    final object = _selectedObjectBlock;
    if (object == null) return;
    final blocks = List<TextSystemBlock>.from(widget.textController.document.blocks);
    final index = blocks.indexWhere((candidate) => candidate.id == object.id);
    if (index < 0) return;
    final targetIndex = (index + direction).clamp(0, blocks.length - 1).toInt();
    if (targetIndex == index) return;
    final moved = blocks.removeAt(index);
    blocks.insert(targetIndex, moved);
    widget.textController.replaceDocument(
      widget.textController.document.copyWith(blocks: blocks),
      label: direction < 0 ? 'Move ${_objectKindForBlock(object)} up' : 'Move ${_objectKindForBlock(object)} down',
    );
    _selectObjectBlock(object.id, source: TextSystemEditorSelectionSource.command);
    widget.commandController?.scheduleStateRefresh();
  }

  TextSystemBlock _duplicatedObjectBlock(TextSystemBlock block) {
    final seed = DateTime.now().microsecondsSinceEpoch;
    final nextMetadata = Map<String, Object?>.from(block.metadata)
      ..remove('sourceBlockId')
      ..remove('sourceBlockIndex')
      ..remove('partial');
    final label = nextMetadata['label'];
    if (label is String && label.trim().isNotEmpty) {
      nextMetadata['label'] = _uniqueDuplicatedObjectLabel(label, block.id);
    }
    return block.copyWith(
      id: '${_objectKindForBlock(block)}-$seed',
      metadata: Map<String, Object?>.unmodifiable(nextMetadata),
    );
  }

  String _uniqueDuplicatedObjectLabel(String base, String sourceBlockId) {
    final trimmed = base.trim();
    if (trimmed.isEmpty) return '';
    var candidate = '$trimmed-copy';
    var suffix = 2;
    while (_documentHasObjectLabel(candidate, exceptBlockId: sourceBlockId)) {
      candidate = '$trimmed-copy-$suffix';
      suffix += 1;
    }
    return candidate;
  }

  bool _documentHasObjectLabel(String label, {required String exceptBlockId}) {
    final normalized = label.trim();
    if (normalized.isEmpty) return false;
    for (final block in widget.textController.document.blocks) {
      if (block.id == exceptBlockId) continue;
      final blockLabel = block.metadata['label'];
      if (blockLabel is String && blockLabel.trim() == normalized) return true;
    }
    return false;
  }

  TextSystemDocumentPosition? _caretPositionBeforeObject(TextSystemBlock object) {
    final document = widget.textController.document;
    final index = document.blocks.indexWhere((block) => block.id == object.id);
    if (index < 0) return null;
    for (var i = index - 1; i >= 0; i--) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(blockId: block.id, blockIndex: i, offset: block.text.length);
    }
    for (var i = index + 1; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(blockId: block.id, blockIndex: i, offset: 0);
    }
    return null;
  }

  TextSystemDocumentPosition? _caretPositionAfterObject(TextSystemBlock object) {
    final document = widget.textController.document;
    final index = document.blocks.indexWhere((block) => block.id == object.id);
    if (index < 0) return null;
    for (var i = index + 1; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(blockId: block.id, blockIndex: i, offset: 0);
    }
    for (var i = index - 1; i >= 0; i--) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(blockId: block.id, blockIndex: i, offset: block.text.length);
    }
    return null;
  }

  String _clipboardTextForObject(TextSystemBlock block, String fallback) {
    final details = _objectReferenceText(block).trim();
    if (details.isNotEmpty) return details;
    if (fallback.trim().isNotEmpty) return fallback;
    return _objectStatusLabel(block);
  }

  String _objectReferenceText(TextSystemBlock block) {
    final kind = _objectKindForBlock(block);
    final label = (block.metadata['label'] as String?)?.trim() ?? '';
    final caption = (block.metadata['caption'] as String?)?.trim() ?? '';
    final latex = block.metadata['latex'] is String ? (block.metadata['latex'] as String).trim() : block.text.trim();
    final bits = <String>[
      _objectDisplayName(kind),
      if (label.isNotEmpty) label,
      if (caption.isNotEmpty) caption,
      if (kind == 'equation' && latex.isNotEmpty) latex,
    ];
    return bits.join(' · ');
  }

  String _objectStatusLabel(TextSystemBlock block) {
    final reference = _objectReferenceText(block);
    if (reference.trim().isNotEmpty) return reference;
    return _objectDisplayName(_objectKindForBlock(block));
  }

  String _objectDisplayName(String kind) {
    return switch (kind) {
      'figure' => 'Figure',
      'table' => 'Table',
      'equation' => 'Equation',
      'pageBreak' => 'Page break',
      'sectionBreak' => 'Section break',
      _ => 'Object',
    };
  }

  List<Map<String, Object?>> _ownedMarginAnnotationsFromDocument(TextSystemDocument document) {
    final raw = document.metadata[_ownedMarginAnnotationsMetadataKey];
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .where((item) => (item['blockId']?.toString().trim().isNotEmpty ?? false))
        .toList(growable: false);
  }

  void _replaceOwnedMarginAnnotations(
    List<Map<String, Object?>> annotations, {
    required String label,
  }) {
    final metadata = Map<String, Object?>.from(widget.textController.document.metadata);
    if (annotations.isEmpty) {
      metadata.remove(_ownedMarginAnnotationsMetadataKey);
    } else {
      metadata[_ownedMarginAnnotationsMetadataKey] = annotations;
    }
    widget.textController.replaceDocument(
      widget.textController.document.copyWith(metadata: Map<String, Object?>.unmodifiable(metadata)),
      label: label,
    );
    widget.commandController?.scheduleStateRefresh();
    setState(() {});
  }

  bool _fragmentContainsOwnedAtomicBlock(TextSystemDocumentFragment fragment) {
    return fragment.blocks.any(_isOwnedAtomicBlock);
  }

  TextSystemDocumentPosition? _pasteAtomicFragmentAtRange(
    TextSystemDocumentFragment fragment,
    TextSystemDocumentRange range,
  ) {
    final normalized = range.normalized();
    final insertion = normalized.start;
    if (!normalized.isCollapsed) {
      final deleted = widget.textController.deleteDocumentRange(normalized, label: 'Replace selection with object');
      final collapsed = deleted.insertedRange.normalized().start;
      final firstAtomic = fragment.blocks.firstWhere(_isOwnedAtomicBlock);
      return widget.textController.insertBlockAtPosition(
        collapsed.blockId,
        collapsed.offset,
        _duplicatedObjectBlock(firstAtomic),
        label: 'Paste object',
      );
    }
    final firstAtomic = fragment.blocks.firstWhere(_isOwnedAtomicBlock);
    return widget.textController.insertBlockAtPosition(
      insertion.blockId,
      insertion.offset,
      _duplicatedObjectBlock(firstAtomic),
      label: 'Paste object',
    );
  }

  void _restoreCaretNear(TextSystemDocumentPosition? preferred) {
    if (preferred == null) return;
    final document = widget.textController.document;
    if (document.blocks.isEmpty) return;
    var blockIndex = document.blocks.indexWhere((block) => block.id == preferred.blockId);
    if (blockIndex < 0) {
      blockIndex = preferred.blockIndex.clamp(0, document.blocks.length - 1).toInt();
    }
    for (var i = blockIndex; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      _setKeyboardCaret(TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: i,
        offset: i == blockIndex ? preferred.offset.clamp(0, block.text.length).toInt() : 0,
      ));
      return;
    }
    for (var i = blockIndex - 1; i >= 0; i--) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      _setKeyboardCaret(TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: i,
        offset: block.text.length,
      ));
      return;
    }
  }

  bool _rangeFullyCoveredByKind(TextSystemDocumentRange range, TextMarkKind kind) {
    final normalized = range.normalized();
    final document = widget.textController.document;
    final startIndex = normalized.start.blockIndex.clamp(0, document.blocks.length - 1).toInt();
    final endIndex = normalized.end.blockIndex.clamp(0, document.blocks.length - 1).toInt();
    var sawText = false;

    for (var i = startIndex; i <= endIndex; i++) {
      final block = document.blocks[i];
      final localStart = i == startIndex ? normalized.start.offset.clamp(0, block.text.length).toInt() : 0;
      final localEnd = i == endIndex ? normalized.end.offset.clamp(localStart, block.text.length).toInt() : block.text.length;
      if (localEnd <= localStart) continue;
      sawText = true;
      if (!_localRangeFullyCoveredByKind(block.marks, TextSystemRange(localStart, localEnd), kind)) {
        return false;
      }
    }

    return sawText;
  }

  bool _localRangeFullyCoveredByKind(
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

    final documentRange = _activeCommandRange;
    if (documentRange == null) {
      _showReferenceSelectionRequiredMessage();
      return;
    }

    final normalized = documentRange.normalized();
    final selectedText = normalized.isCollapsed
        ? ''
        : widget.textController.plainTextForDocumentRange(normalized).trim();
    if (actionType != TextSystemReferenceActionType.citation && !normalized.isCollapsed && selectedText.isEmpty) {
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
      _restoreCaretNear(normalized.end.copyWith(offset: normalized.end.offset + insertedText.length));
      widget.commandController?.scheduleStateRefresh();
      return;
    }

    if (normalized.isCollapsed) {
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
      _restoreCaretNear(normalized.end.copyWith(offset: normalized.end.offset + visibleLabel.length));
      widget.commandController?.scheduleStateRefresh();
      return;
    }

    widget.textController.applyMarkForDocumentRange(
      normalized,
      TextMarkKind.link,
      attributes: result.inlineMark.toTextMarkAttributes(),
      label: result.actionType.verbLabel,
    );
    widget.commandController?.scheduleStateRefresh();
    setState(() {});
  }

  TextSystemBlock? _activeDisplayEquationBlockForRange([TextSystemDocumentRange? candidateRange]) {
    final range = candidateRange ?? _activeCommandRange;
    if (range == null) return null;
    final normalized = range.normalized();
    if (normalized.start.blockId != normalized.end.blockId) return null;
    final block = _blockAtPosition(normalized.start);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) return null;
    return block;
  }

  bool get _isEditingDisplayEquation => _activeDisplayEquationBlockForRange() != null;

  KeyEventResult _finishActiveEquationEditing() {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) {
      return KeyEventResult.ignored;
    }
    final next = _editableBoundaryAfterOrCreateParagraph(
      position.blockIndex,
      label: 'Continue after equation',
    );
    if (next == null) return KeyEventResult.ignored;
    _setKeyboardCaret(next);
    return KeyEventResult.handled;
  }

  TextSystemDocumentPosition? _editableBoundaryAfterOrCreateParagraph(
    int blockIndex, {
    required String label,
  }) {
    final document = widget.textController.document;
    if (blockIndex < 0 || blockIndex >= document.blocks.length) return null;
    if (blockIndex + 1 < document.blocks.length) {
      final nextBlock = document.blocks[blockIndex + 1];
      if (_canEditBlockText(nextBlock) && !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(nextBlock)) {
        return TextSystemDocumentPosition.text(
          blockId: nextBlock.id,
          blockIndex: blockIndex + 1,
          offset: 0,
        );
      }
    }

    final paragraph = TextSystemBlock.paragraph(
      id: 'paragraph-after-equation-${DateTime.now().microsecondsSinceEpoch}',
      text: '',
    );
    final nextBlocks = <TextSystemBlock>[];
    for (var i = 0; i < document.blocks.length; i++) {
      nextBlocks.add(document.blocks[i]);
      if (i == blockIndex) {
        nextBlocks.add(paragraph);
      }
    }
    widget.textController.replaceDocument(
      document.copyWith(
        blocks: List<TextSystemBlock>.unmodifiable(nextBlocks),
        updatedAt: DateTime.now(),
      ),
      label: label,
    );
    return TextSystemDocumentPosition.text(
      blockId: paragraph.id,
      blockIndex: blockIndex + 1,
      offset: 0,
    );
  }

  KeyEventResult _replaceActiveEquationRangeWith(
    String replacement, {
    required int caretOffsetInReplacement,
    required String label,
  }) {
    final range = _activeCommandRange;
    final block = _activeDisplayEquationBlockForRange(range);
    if (range == null || block == null) return KeyEventResult.ignored;
    final normalized = range.normalized();
    final result = widget.textController.replaceDocumentRangeWithPlainText(
      normalized,
      replacement,
      label: label,
    );
    final inserted = result.insertedRange.normalized();
    final safeOffset = inserted.start.offset + caretOffsetInReplacement.clamp(0, replacement.length).toInt();
    _setKeyboardCaret(TextSystemDocumentPosition.text(
      blockId: inserted.start.blockId,
      blockIndex: inserted.start.blockIndex,
      offset: safeOffset,
    ));
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
    return KeyEventResult.handled;
  }

  String _selectedEquationSourceText(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    if (normalized.isCollapsed) return '';
    return widget.textController
        .plainTextForDocumentRange(normalized)
        .replaceAll('\r\n', '\n')
        .trim();
  }

  KeyEventResult _insertEquationRawSource(String source) {
    return _replaceActiveEquationRangeWith(
      source,
      caretOffsetInReplacement: source.length,
      label: 'Insert equation source',
    );
  }

  _EquationCommandPrefixRange? _activeEquationCommandPrefixRange() {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null || !position.isTextOffset) return null;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) {
      return null;
    }
    final offset = position.offset.clamp(0, block.text.length).toInt();
    if (offset <= 0) return null;
    var start = offset;
    while (start > 0 && _isEquationCommandLetter(block.text.codeUnitAt(start - 1))) {
      start--;
    }
    if (start > 0 && block.text[start - 1] == '\\') {
      start--;
    } else if (offset > 0 && block.text[offset - 1] == '\\') {
      start = offset - 1;
    } else {
      return null;
    }
    final typed = block.text.substring(start, offset);
    if (!typed.startsWith('\\')) return null;
    if (typed.length > 1 && !_isEquationCommandLetter(typed.codeUnitAt(1))) {
      return null;
    }
    return _EquationCommandPrefixRange(
      block: block,
      blockIndex: position.blockIndex,
      start: start,
      end: offset,
      typed: typed,
    );
  }

  List<OwnedEquationCommandCompletion> _activeEquationCommandCompletionCandidates() {
    final prefix = _activeEquationCommandPrefixRange();
    if (prefix == null) return const <OwnedEquationCommandCompletion>[];
    final publicPrefix = OwnedEquationCommandPrefix(
      start: prefix.start,
      end: prefix.end,
      typed: prefix.typed,
    );
    return OwnedEquationCommandCompletion.matchesFor(
      publicPrefix,
      source: prefix.block.text,
      activeOffset: prefix.end,
      usageCounts: _equationCompletionUsageCounts,
    );
  }

  void _syncEquationCompletionHighlight() {
    final prefix = _activeEquationCommandPrefixRange();
    final signature = prefix == null
        ? null
        : '${prefix.block.id}:${prefix.start}:${prefix.end}:${prefix.typed}';
    if (signature != _equationCompletionPrefixSignature) {
      _equationCompletionPrefixSignature = signature;
      _equationCompletionHighlightedIndex = 0;
    }
    final candidates = _activeEquationCommandCompletionCandidates();
    if (candidates.isEmpty) {
      _equationCompletionHighlightedIndex = 0;
      return;
    }
    if (_equationCompletionHighlightedIndex >= candidates.length) {
      _equationCompletionHighlightedIndex = candidates.length - 1;
    }
    if (_equationCompletionHighlightedIndex < 0) {
      _equationCompletionHighlightedIndex = 0;
    }
  }

  KeyEventResult _moveEquationCompletionHighlight(int delta) {
    final candidates = _activeEquationCommandCompletionCandidates();
    if (candidates.isEmpty) return KeyEventResult.ignored;
    _syncEquationCompletionHighlight();
    setState(() {
      _equationCompletionHighlightedIndex =
          (_equationCompletionHighlightedIndex + delta) % candidates.length;
      if (_equationCompletionHighlightedIndex < 0) {
        _equationCompletionHighlightedIndex += candidates.length;
      }
    });
    return KeyEventResult.handled;
  }

  KeyEventResult _acceptHighlightedEquationCompletion() {
    final candidates = _activeEquationCommandCompletionCandidates();
    if (candidates.isEmpty) return KeyEventResult.ignored;
    _syncEquationCompletionHighlight();
    final safeIndex = _equationCompletionHighlightedIndex.clamp(0, candidates.length - 1).toInt();
    final candidate = candidates[safeIndex];
    return _acceptEquationCommandCompletion(candidate.completion, candidate.caretOffset);
  }

  bool _isEquationCommandLetter(int unit) {
    return (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  }

  KeyEventResult _acceptEquationCommandCompletion(String completion, int caretOffset) {
    _equationCompletionUsageCounts[completion] = (_equationCompletionUsageCounts[completion] ?? 0) + 1;
    _equationCompletionPrefixSignature = null;
    _equationCompletionHighlightedIndex = 0;
    final prefix = _activeEquationCommandPrefixRange();
    if (prefix == null) {
      return _insertEquationRawSource(completion);
    }
    final range = TextSystemDocumentRange(
      start: TextSystemDocumentPosition.text(
        blockId: prefix.block.id,
        blockIndex: prefix.blockIndex,
        offset: prefix.start,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: prefix.block.id,
        blockIndex: prefix.blockIndex,
        offset: prefix.end,
      ),
    );
    final result = widget.textController.replaceDocumentRangeWithPlainText(
      range,
      completion,
      label: 'Complete equation command',
    );
    final inserted = result.insertedRange.normalized();
    final targetOffset = inserted.start.offset + caretOffset.clamp(0, completion.length).toInt();
    _setKeyboardCaret(TextSystemDocumentPosition.text(
      blockId: inserted.start.blockId,
      blockIndex: inserted.start.blockIndex,
      offset: targetOffset,
    ));
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
    return KeyEventResult.handled;
  }

  KeyEventResult _insertEquationFraction() {
    final range = _activeCommandRange;
    if (range == null || _activeDisplayEquationBlockForRange(range) == null) return KeyEventResult.ignored;
    final selected = _selectedEquationSourceText(range);
    final replacement = selected.isEmpty ? r'\frac{}{}' : '\\frac{$selected}{}';
    final caretOffset = selected.isEmpty ? r'\frac{'.length : replacement.length - 1;
    return _replaceActiveEquationRangeWith(
      replacement,
      caretOffsetInReplacement: caretOffset,
      label: selected.isEmpty ? 'Insert fraction' : 'Wrap fraction',
    );
  }

  KeyEventResult _insertEquationSuperscript() {
    final range = _activeCommandRange;
    if (range == null || _activeDisplayEquationBlockForRange(range) == null) return KeyEventResult.ignored;
    final selected = _selectedEquationSourceText(range);
    final replacement = selected.isEmpty ? r'^{}' : '{$selected}^{}';
    return _replaceActiveEquationRangeWith(
      replacement,
      caretOffsetInReplacement: replacement.length - 1,
      label: selected.isEmpty ? 'Insert superscript' : 'Wrap superscript',
    );
  }

  KeyEventResult _insertEquationSubscript() {
    final range = _activeCommandRange;
    if (range == null || _activeDisplayEquationBlockForRange(range) == null) return KeyEventResult.ignored;
    final selected = _selectedEquationSourceText(range);
    final replacement = selected.isEmpty ? r'_{}' : '{$selected}_{}';
    return _replaceActiveEquationRangeWith(
      replacement,
      caretOffsetInReplacement: replacement.length - 1,
      label: selected.isEmpty ? 'Insert subscript' : 'Wrap subscript',
    );
  }

  KeyEventResult _insertEquationTextMode() {
    return _replaceActiveEquationRangeWith(
      r'\text{}',
      caretOffsetInReplacement: r'\text{'.length,
      label: 'Insert equation text',
    );
  }

  KeyEventResult _insertEquationDerivative() {
    return _replaceActiveEquationRangeWith(
      r'\frac{d}{dt}',
      caretOffsetInReplacement: r'\frac{d}{dt}'.length,
      label: 'Insert derivative',
    );
  }

  KeyEventResult _insertEquationMatrix() {
    const replacement = r'\begin{bmatrix}  &  \\  &  \end{bmatrix}';
    return _insertEquationTopLevelStructureTemplate(
      replacement,
      caretOffsetInReplacement: r'\begin{bmatrix} '.length,
      label: 'Insert matrix',
    );
  }

  KeyEventResult _insertEquationAligned() {
    const replacement = r'\begin{aligned}  &=  \\  &=  \end{aligned}';
    return _insertEquationTopLevelStructureTemplate(
      replacement,
      caretOffsetInReplacement: r'\begin{aligned} '.length,
      label: 'Insert aligned equation',
    );
  }

  KeyEventResult _insertEquationCases() {
    const replacement = r'\begin{cases}  & \text{} \\  & \text{} \end{cases}';
    return _insertEquationTopLevelStructureTemplate(
      replacement,
      caretOffsetInReplacement: r'\begin{cases} '.length,
      label: 'Insert cases equation',
    );
  }

  KeyEventResult _insertEquationTopLevelStructureTemplate(
    String replacement, {
    required int caretOffsetInReplacement,
    required String label,
  }) {
    final range = _activeCommandRange;
    final block = _activeDisplayEquationBlockForRange(range);
    if (range == null || block == null) return KeyEventResult.ignored;

    final normalized = range.normalized();
    if (!normalized.isCollapsed) {
      return _replaceActiveEquationRangeWith(
        replacement,
        caretOffsetInReplacement: caretOffsetInReplacement,
        label: label,
      );
    }

    final caret = normalized.start.offset.clamp(0, block.text.length).toInt();
    final model = OwnedEquationStructureModel.parse(block.text);
    final containingEnvironment = model.environmentForOffset(
      const <String>{
        'matrix',
        'pmatrix',
        'bmatrix',
        'vmatrix',
        'Vmatrix',
        'smallmatrix',
        'aligned',
        'alignedat',
        'split',
        'gathered',
        'cases',
      },
      caret,
    );

    // Main structure buttons are beginner-facing authoring actions. If the
    // caret currently happens to sit inside an existing matrix/aligned/cases
    // environment, inserting another environment into that cell is almost never
    // the intended action and produces broken-looking nested structures. Treat
    // the containing environment as an atomic structure and insert the new
    // structure after it. Structure-specific buttons (+ row, + col, + line,
    // &=, + case) remain context-aware for documents with multiple arrays.
    if (containingEnvironment != null &&
        caret > containingEnvironment.beginStart &&
        caret < containingEnvironment.endEnd) {
      final insertionOffset = containingEnvironment.endEnd.clamp(0, block.text.length).toInt();
      final prefix = _needsSpaceBeforeEquationInsertion(block.text, insertionOffset) ? ' ' : '';
      final suffix = _needsSpaceAfterEquationInsertion(block.text, insertionOffset) ? ' ' : '';
      final insertion = '$prefix$replacement$suffix';
      return _insertInActiveEquationBlock(
        insertionOffset,
        insertion,
        caretOffsetInInsertion: prefix.length + caretOffsetInReplacement,
        label: label,
      );
    }

    return _replaceActiveEquationRangeWith(
      replacement,
      caretOffsetInReplacement: caretOffsetInReplacement,
      label: label,
    );
  }

  bool _needsSpaceBeforeEquationInsertion(String source, int insertionOffset) {
    if (insertionOffset <= 0 || insertionOffset > source.length) return false;
    final previous = source[insertionOffset - 1];
    return previous.trim().isNotEmpty && previous != '{' && previous != '[';
  }

  bool _needsSpaceAfterEquationInsertion(String source, int insertionOffset) {
    if (insertionOffset < 0 || insertionOffset >= source.length) return false;
    final next = source[insertionOffset];
    return next.trim().isNotEmpty && next != '}' && next != ']';
  }

  KeyEventResult _insertEquationMatrixRow() {
    final span = _activeEquationEnvironmentSpan(const <String>{
      'matrix',
      'pmatrix',
      'bmatrix',
      'vmatrix',
      'Vmatrix',
      'smallmatrix',
    });
    if (span == null) return _insertEquationMatrix();

    final rows = _equationEnvironmentCellTexts(span);
    final columnCount = math.max(
      1,
      rows.isEmpty
          ? _equationEnvironmentColumnCount(span)
          : rows.map((row) => row.length).fold<int>(1, (previous, value) => math.max(previous, value).toInt()),
    );
    final normalizedRows = _normalizeEquationMatrixRows(rows, columnCount);
    normalizedRows.add(List<String>.filled(columnCount, '', growable: true));
    final content = _serializeEquationMatrixRows(normalizedRows);
    final caretOffset = _matrixCellCaretOffset(
      span.contentStart,
      normalizedRows,
      normalizedRows.length - 1,
      0,
    );
    return _replaceActiveEquationSourceSlice(
      span.contentStart,
      span.contentEnd,
      content,
      caretOffset: caretOffset,
      label: 'Append matrix row',
    );
  }

  KeyEventResult _insertEquationMatrixColumn() {
    final span = _activeEquationEnvironmentSpan(const <String>{
      'matrix',
      'pmatrix',
      'bmatrix',
      'vmatrix',
      'Vmatrix',
      'smallmatrix',
    });
    if (span == null) return _insertEquationMatrix();

    final rows = _equationEnvironmentCellTexts(span);
    final baseColumnCount = math.max(
      1,
      rows.isEmpty
          ? _equationEnvironmentColumnCount(span)
          : rows.map((row) => row.length).fold<int>(1, (previous, value) => math.max(previous, value).toInt()),
    );
    final normalizedRows = _normalizeEquationMatrixRows(rows, baseColumnCount);
    for (final row in normalizedRows) {
      row.add('');
    }
    final content = _serializeEquationMatrixRows(normalizedRows);
    final caretOffset = _matrixCellCaretOffset(
      span.contentStart,
      normalizedRows,
      0,
      baseColumnCount,
    );
    return _replaceActiveEquationSourceSlice(
      span.contentStart,
      span.contentEnd,
      content,
      caretOffset: caretOffset,
      label: 'Append matrix column',
    );
  }

  KeyEventResult _insertEquationAlignedLine() {
    final span = _activeEquationEnvironmentSpan(const <String>{
      'aligned',
      'alignedat',
      'split',
      'gathered',
    });
    if (span == null) return _insertEquationAligned();
    return _insertInActiveEquationBlock(
      span.contentEnd,
      r' \\  &=  ',
      caretOffsetInInsertion: r' \\  &='.length,
      label: 'Append aligned equation line',
    );
  }

  KeyEventResult _insertEquationAlignmentMarker() {
    final span = _activeEquationEnvironmentSpan(const <String>{
      'aligned',
      'alignedat',
      'split',
      'gathered',
    });
    if (span == null) {
      return _replaceActiveEquationRangeWith(
        r' &= ',
        caretOffsetInReplacement: r' &='.length,
        label: 'Insert alignment marker',
      );
    }
    final rows = _equationEnvironmentRows(span);
    if (rows.isEmpty) {
      return _insertInActiveEquationBlock(
        span.contentStart,
        r' &= ',
        caretOffsetInInsertion: r' &='.length,
        label: 'Insert alignment marker',
      );
    }
    final caret = (_keyboardFocusTextPosition ?? _activeTextPosition)?.offset ?? span.contentStart;
    final currentRow = rows.firstWhere(
      (row) => caret >= row.start && caret <= row.end,
      orElse: () => rows.first,
    );
    final rowText = span.source.substring(currentRow.start, currentRow.end);
    if (rowText.contains('&')) {
      final equalsIndex = rowText.indexOf('=');
      if (equalsIndex >= 0) {
        return _replaceActiveEquationSourceSlice(
          currentRow.start + equalsIndex,
          currentRow.start + equalsIndex,
          '',
          caretOffset: currentRow.start + equalsIndex,
          label: 'Keep alignment marker',
        );
      }
      return KeyEventResult.handled;
    }
    final equalsIndex = rowText.indexOf('=');
    final insertAt = equalsIndex >= 0 ? currentRow.start + equalsIndex : currentRow.end;
    return _insertInActiveEquationBlock(
      insertAt,
      '&',
      caretOffsetInInsertion: 1,
      label: 'Insert alignment marker',
    );
  }

  KeyEventResult _insertEquationCasesRow() {
    final span = _activeEquationEnvironmentSpan(const <String>{'cases'});
    if (span == null) return _insertEquationCases();
    return _insertInActiveEquationBlock(
      span.contentEnd,
      r' \\  & \text{}',
      caretOffsetInInsertion: r' \\  '.length,
      label: 'Append cases row',
    );
  }

  KeyEventResult _insertInActiveEquationBlock(
    int offset,
    String insertion, {
    required int caretOffsetInInsertion,
    required String label,
  }) {
    final safeOffset = offset.clamp(0, (_activeEquationBlock()?.text.length ?? 0)).toInt();
    return _replaceActiveEquationSourceSlice(
      safeOffset,
      safeOffset,
      insertion,
      caretOffset: safeOffset + caretOffsetInInsertion.clamp(0, insertion.length).toInt(),
      label: label,
    );
  }

  KeyEventResult _replaceActiveEquationSourceSlice(
    int start,
    int end,
    String replacement, {
    required int caretOffset,
    required String label,
  }) {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) {
      return KeyEventResult.ignored;
    }
    final safeStart = start.clamp(0, block.text.length).toInt();
    final safeEnd = end.clamp(safeStart, block.text.length).toInt();
    final range = TextSystemDocumentRange(
      start: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: position.blockIndex,
        offset: safeStart,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: position.blockIndex,
        offset: safeEnd,
      ),
    );
    final result = widget.textController.replaceDocumentRangeWithPlainText(
      range,
      replacement,
      label: label,
    );
    final inserted = result.insertedRange.normalized();
    final targetOffset = caretOffset.clamp(0, (block.text.length - (safeEnd - safeStart) + replacement.length)).toInt();
    _setKeyboardCaret(TextSystemDocumentPosition.text(
      blockId: inserted.start.blockId,
      blockIndex: inserted.start.blockIndex,
      offset: targetOffset,
    ));
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
    return KeyEventResult.handled;
  }

  TextSystemBlock? _activeEquationBlock() {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return null;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) return null;
    return block;
  }

  _OwnedEquationEnvironmentSpan? _activeEquationEnvironmentSpan(Set<String> supportedEnvironments) {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return null;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) return null;
    final source = block.text;
    final offset = position.offset.clamp(0, source.length).toInt();
    final model = OwnedEquationStructureModel.parse(source);
    final environment = model.environmentForOffset(supportedEnvironments, offset);
    if (environment == null) return null;
    return _OwnedEquationEnvironmentSpan(
      source: source,
      environment: environment.environment,
      beginStart: environment.beginStart,
      contentStart: environment.contentStart,
      contentEnd: environment.contentEnd,
      endEnd: environment.endEnd,
    );
  }

  List<List<String>> _equationEnvironmentCellTexts(_OwnedEquationEnvironmentSpan span) {
    final structure = _equationEnvironmentStructureForSpan(span);
    if (structure != null) {
      return structure.rows
          .map((row) => row.cells.map((cell) => cell.text.trim()).toList(growable: true))
          .where((row) => row.isNotEmpty)
          .toList(growable: true);
    }
    final rows = _equationEnvironmentRows(span);
    if (rows.isEmpty) return <List<String>>[];
    return rows
        .map((row) => _equationRowCellTexts(span.source, row))
        .where((row) => row.isNotEmpty)
        .toList(growable: true);
  }

  List<String> _equationRowCellTexts(String source, _OwnedEquationRowSpan row) {
    final cells = <String>[];
    var cellStart = row.start;
    var i = row.start;
    while (i < row.end) {
      final escaped = i > row.start && source[i - 1] == r'\'[0];
      if (source[i] == '&' && !escaped) {
        cells.add(source.substring(cellStart, i).trim());
        cellStart = i + 1;
      }
      i++;
    }
    cells.add(source.substring(cellStart, row.end).trim());
    return cells;
  }

  List<List<String>> _normalizeEquationMatrixRows(List<List<String>> rows, int columnCount) {
    final safeColumnCount = math.max(1, columnCount);
    if (rows.isEmpty) return <List<String>>[List<String>.filled(safeColumnCount, '', growable: true)];
    return rows.map((row) {
      final normalized = List<String>.from(row);
      while (normalized.length < safeColumnCount) {
        normalized.add('');
      }
      if (normalized.length > safeColumnCount) {
        return normalized.take(safeColumnCount).toList(growable: true);
      }
      return normalized;
    }).toList(growable: true);
  }

  String _serializeEquationMatrixRows(List<List<String>> rows) {
    return rows
        .map((row) => row.map((cell) => cell.trim()).join(' & '))
        .join(r' \\ ');
  }

  int _matrixCellCaretOffset(
    int contentStart,
    List<List<String>> rows,
    int rowIndex,
    int columnIndex,
  ) {
    final safeRowIndex = rowIndex.clamp(0, math.max(0, rows.length - 1)).toInt();
    final row = rows.isEmpty ? <String>[''] : rows[safeRowIndex];
    final safeColumnIndex = columnIndex.clamp(0, math.max(0, row.length - 1)).toInt();
    var offset = contentStart;
    for (var r = 0; r < safeRowIndex; r++) {
      offset += rows[r].map((cell) => cell.trim()).join(' & ').length;
      offset += r' \\ '.length;
    }
    for (var c = 0; c < safeColumnIndex; c++) {
      offset += row[c].trim().length;
      offset += ' & '.length;
    }
    return offset;
  }

  int _equationEnvironmentColumnCount(_OwnedEquationEnvironmentSpan span) {
    final structure = _equationEnvironmentStructureForSpan(span);
    if (structure != null) return structure.columnCount;
    final rows = _equationEnvironmentRows(span);
    if (rows.isEmpty) return 1;
    return rows.map((row) => _equationRowColumnCount(span.source, row)).fold<int>(1, (previous, value) => math.max(previous, value).toInt());
  }

  int _equationRowColumnCount(String source, _OwnedEquationRowSpan row) {
    var count = 1;
    for (var i = row.start; i < row.end; i++) {
      final escaped = i > row.start && source[i - 1] == r'\'[0];
      if (source[i] == '&' && !escaped) count++;
    }
    return count;
  }

  List<_OwnedEquationRowSpan> _equationEnvironmentRows(_OwnedEquationEnvironmentSpan span) {
    final structure = _equationEnvironmentStructureForSpan(span);
    if (structure != null) {
      return <_OwnedEquationRowSpan>[
        for (final row in structure.rows) _OwnedEquationRowSpan(start: row.start, end: row.end),
      ];
    }
    final rows = <_OwnedEquationRowSpan>[];
    var rowStart = span.contentStart;
    var i = span.contentStart;
    while (i < span.contentEnd) {
      if (i + 1 < span.contentEnd && span.source.codeUnitAt(i) == 92 && span.source.codeUnitAt(i + 1) == 92) {
        rows.add(_OwnedEquationRowSpan(start: rowStart, end: i));
        i += 2;
        rowStart = i;
        continue;
      }
      i++;
    }
    rows.add(_OwnedEquationRowSpan(start: rowStart, end: span.contentEnd));
    return rows;
  }

  OwnedEquationEnvironmentStructure? _equationEnvironmentStructureForSpan(_OwnedEquationEnvironmentSpan span) {
    final model = OwnedEquationStructureModel.parse(span.source);
    for (final environment in model.environments) {
      if (environment.environment == span.environment &&
          environment.beginStart == span.beginStart &&
          environment.contentStart == span.contentStart &&
          environment.contentEnd == span.contentEnd &&
          environment.endEnd == span.endEnd) {
        return environment;
      }
    }
    return null;
  }

  List<_OwnedEquationEnvironmentSpan> _ownedEquationEnvironmentSpans(String source) {
    final pattern = RegExp(r'\\(begin|end)\{([^}]+)\}');
    final stack = <_OwnedEquationEnvironmentSpan>[];
    final spans = <_OwnedEquationEnvironmentSpan>[];
    var i = 0;
    while (i < source.length) {
      final match = pattern.matchAsPrefix(source, i);
      if (match == null) {
        i++;
        continue;
      }
      final command = match.group(1) ?? '';
      final environment = match.group(2) ?? '';
      if (command == 'begin') {
        stack.add(_OwnedEquationEnvironmentSpan(
          source: source,
          environment: environment,
          beginStart: match.start,
          contentStart: match.end,
          contentEnd: source.length,
          endEnd: source.length,
        ));
      } else {
        final index = stack.lastIndexWhere((candidate) => candidate.environment == environment);
        if (index >= 0) {
          final open = stack.removeAt(index);
          spans.add(open.copyWith(contentEnd: match.start, endEnd: match.end));
        }
      }
      i = match.end;
    }
    spans.addAll(stack);
    return spans;
  }

  KeyEventResult _formatActiveEquationSource() {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) {
      return KeyEventResult.ignored;
    }
    final inner = _ownedDisplayEquationSourceFromRaw(block.text).trim();
    final formatted = inner.isEmpty ? r'\[\]' : '\\[\n$inner\n\\]';
    final blockRange = TextSystemDocumentRange(
      start: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: position.blockIndex,
        offset: 0,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: position.blockIndex,
        offset: block.text.length,
      ),
    );
    final result = widget.textController.replaceDocumentRangeWithPlainText(
      blockRange,
      formatted,
      label: 'Format equation source',
    );
    final inserted = result.insertedRange.normalized();
    _setKeyboardCaret(TextSystemDocumentPosition.text(
      blockId: inserted.start.blockId,
      blockIndex: inserted.start.blockIndex,
      offset: formatted.startsWith('\\[\n') ? 3 : math.min(2, formatted.length),
    ));
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
    return KeyEventResult.handled;
  }

  KeyEventResult _jumpEquationSlot({required bool forward}) {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) {
      return KeyEventResult.ignored;
    }
    final text = block.text;
    final slots = OwnedEquationStructureModel.parse(text).slotOffsets();
    if (slots.isEmpty) return KeyEventResult.ignored;
    final current = position.offset.clamp(0, text.length).toInt();
    int target;
    if (forward) {
      target = slots.firstWhere((slot) => slot > current, orElse: () => slots.first);
    } else {
      target = slots.lastWhere((slot) => slot < current, orElse: () => slots.last);
    }
    _setKeyboardCaret(TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: position.blockIndex,
      offset: target,
    ));
    return KeyEventResult.handled;
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final shortcutModifierPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (_isEditingDisplayEquation) {
      if (shortcutModifierPressed && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
        return _finishActiveEquationEditing();
      }
      if (!shortcutModifierPressed && key == LogicalKeyboardKey.escape) {
        return _finishActiveEquationEditing();
      }
      final completionCandidates = _activeEquationCommandCompletionCandidates();
      if (!shortcutModifierPressed && completionCandidates.isNotEmpty) {
        _syncEquationCompletionHighlight();
        if (key == LogicalKeyboardKey.arrowDown) {
          return _moveEquationCompletionHighlight(1);
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          return _moveEquationCompletionHighlight(-1);
        }
        if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
          return _acceptHighlightedEquationCompletion();
        }
      }
      if (!shortcutModifierPressed && key == LogicalKeyboardKey.tab) {
        return _jumpEquationSlot(forward: !HardwareKeyboard.instance.isShiftPressed);
      }
      if (!shortcutModifierPressed && !HardwareKeyboard.instance.isShiftPressed &&
          (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
        return _finishActiveEquationEditing();
      }
      if (!shortcutModifierPressed) {
        final equationCharacter = event.character;
        if (equationCharacter == '^') return _insertEquationSuperscript();
        if (equationCharacter == '_') return _insertEquationSubscript();
        if (equationCharacter == '/' && _activeNonCollapsedTextRange != null) {
          return _insertEquationFraction();
        }
      }
    }

    if (shortcutModifierPressed) {
      if (key == LogicalKeyboardKey.keyZ && !HardwareKeyboard.instance.isShiftPressed) {
        ownedPerformUndo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY ||
          (key == LogicalKeyboardKey.keyZ && HardwareKeyboard.instance.isShiftPressed)) {
        ownedPerformRedo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        return _selectCurrentParagraph();
      }
      if (key == LogicalKeyboardKey.keyC) {
        unawaited(ownedCopySelectionToClipboard());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        unawaited(ownedCutSelectionToClipboard());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        unawaited(ownedPasteAtSelection());
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyB) {
        ownedToggleMarkForActiveRange(TextMarkKind.bold);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI) {
        ownedToggleMarkForActiveRange(TextMarkKind.italic);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyU) {
        ownedToggleMarkForActiveRange(TextMarkKind.underline);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyK) {
        unawaited(ownedCreateReferenceForActiveSelection(TextSystemReferenceActionType.link));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD && _selectedObjectBlock != null) {
        ownedDuplicateSelectedObject();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final selectedObject = _selectedObjectBlock;
    if (selectedObject != null) {
      if (key == LogicalKeyboardKey.escape) {
        _selectionController.clear();
        widget.commandController?.scheduleStateRefresh();
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isAltPressed && key == LogicalKeyboardKey.arrowUp) {
        ownedMoveSelectedObjectUp();
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.isAltPressed && key == LogicalKeyboardKey.arrowDown) {
        ownedMoveSelectedObjectDown();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
        ownedDeleteSelectedObject();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
        final position = _caretPositionBeforeObject(selectedObject);
        if (position == null) return KeyEventResult.ignored;
        _setKeyboardCaret(position);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        final position = _caretPositionAfterObject(selectedObject);
        if (position == null) return KeyEventResult.ignored;
        _setKeyboardCaret(position);
        return KeyEventResult.handled;
      }
    }

    if (HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final extendSelection = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.arrowLeft) {
      return _moveCaretHorizontally(-1, extendSelection: extendSelection);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return _moveCaretHorizontally(1, extendSelection: extendSelection);
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return _moveCaretVertically(-1, extendSelection: extendSelection);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return _moveCaretVertically(1, extendSelection: extendSelection);
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      return _splitCurrentBlock();
    }
    if (key == LogicalKeyboardKey.backspace) {
      final range = _activeCommandRange;
      if (range != null && !range.isCollapsed) {
        if (_deleteWholeSingleListBlockSelection(range) || _deleteWholeSingleDisplayEquationSelection(range)) {
          return KeyEventResult.handled;
        }
        widget.textController.deleteDocumentRange(range);
        _restoreCaretNear(range.normalized().start);
        return KeyEventResult.handled;
      }
      return _deleteBackward();
    }
    if (key == LogicalKeyboardKey.delete) {
      final range = _activeCommandRange;
      if (range != null && !range.isCollapsed) {
        if (_deleteWholeSingleListBlockSelection(range) || _deleteWholeSingleDisplayEquationSelection(range)) {
          return KeyEventResult.handled;
        }
        widget.textController.deleteDocumentRange(range);
        _restoreCaretNear(range.normalized().start);
        return KeyEventResult.handled;
      }
      return _deleteForward();
    }

    final character = event.character;
    if (character != null && _isPlainInsertableCharacter(character)) {
      // Keep ordinary hardware-key typing on the raw keyboard path. Custom
      // TextInputClient implementations do not consistently receive normal
      // desktop key text through updateEditingValue, especially on Windows. The
      // input client still handles IME/composition commits, and suppresses a
      // duplicate platform echo if one arrives for this same raw character.
      _textInputClient.markRawKeyboardTextHandled(character);
      final range = _activeNonCollapsedTextRange;
      if (range != null) {
        final result = widget.textController.replaceDocumentRangeWithPlainText(
          range,
          character,
          label: 'Replace selection',
        );
        _restoreCaretNear(result.insertedRange.normalized().end);
        return KeyEventResult.handled;
      }
      return _insertPlainText(character);
    }

    return KeyEventResult.ignored;
  }

  bool _isPlainInsertableCharacter(String character) {
    if (character.isEmpty) return false;
    if (character == '\n' || character == '\r' || character == '\t') return false;
    return character.runes.every((codePoint) => codePoint >= 0x20 && codePoint != 0x7F);
  }

  Future<void> _commitTextFromInputClient(String text) async {
    if (text.isEmpty) return;
    final range = _activeCommandRange;
    if (range == null) return;
    final result = widget.textController.replaceDocumentRangeWithPlainText(
      range,
      text,
      label: 'Insert text',
    );
    _restoreCaretNear(result.insertedRange.normalized().end);
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
  }

  TextSystemDocumentPosition? get _activeTextPosition {
    final selection = _selectionState.selection;
    if (selection == null || !selection.isCollapsed) return null;
    final focus = selection.focus;
    if (!focus.isTextOffset) return null;
    return _clampedTextPosition(focus);
  }

  TextSystemDocumentPosition? get _keyboardFocusTextPosition {
    final selection = _selectionState.selection;
    if (selection == null) return null;
    final focus = selection.focus;
    if (!focus.isTextOffset) return null;
    return _clampedTextPosition(focus);
  }

  TextSystemDocumentPosition? _clampedTextPosition(TextSystemDocumentPosition position) {
    final document = widget.textController.document;
    final index = document.blocks.indexWhere((block) => block.id == position.blockId);
    if (index < 0) return null;
    final block = document.blocks[index];
    if (!_canEditBlockText(block)) return null;
    return TextSystemDocumentPosition.text(
      blockId: block.id,
      blockIndex: index,
      offset: position.offset.clamp(0, block.text.length).toInt(),
    );
  }

  bool _canEditBlockText(TextSystemBlock block) {
    if (_isObjectBlock(block) || _isPageBreakBlock(block) || _isSectionBreakBlock(block)) {
      return false;
    }
    return block.type != TextSystemBlockType.divider;
  }

  TextSystemBlock? _blockAtPosition(TextSystemDocumentPosition position) {
    final document = widget.textController.document;
    final index = document.blocks.indexWhere((block) => block.id == position.blockId);
    if (index < 0) return null;
    return document.blocks[index];
  }

  KeyEventResult _insertPlainText(String text) {
    final range = _activeCommandRange;
    if (range == null) return KeyEventResult.ignored;
    final normalized = range.normalized();
    final startBlock = _blockAtPosition(normalized.start);
    final endBlock = _blockAtPosition(normalized.end);
    if (startBlock == null || endBlock == null || !_canEditBlockText(startBlock) || !_canEditBlockText(endBlock)) {
      return KeyEventResult.ignored;
    }
    final result = widget.textController.replaceDocumentRangeWithPlainText(
      normalized,
      text,
      label: normalized.isCollapsed ? 'Insert text' : 'Replace selection',
    );
    _restoreCaretNear(result.insertedRange.normalized().end);
    return KeyEventResult.handled;
  }

  bool _isListLikeBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.listItem || block.type == TextSystemBlockType.todo;
  }

  KeyEventResult _exitListItemToParagraph(
    TextSystemBlock block,
    TextSystemDocumentPosition position,
  ) {
    widget.textController.updateBlockType(
      block.id,
      TextSystemBlockType.paragraph,
      metadata: const <String, Object?>{},
    );
    _setKeyboardCaret(
      TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: position.blockIndex,
        offset: position.offset.clamp(0, block.text.length).toInt(),
      ),
    );
    return KeyEventResult.handled;
  }

  bool _deleteWholeSingleListBlockSelection(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    if (normalized.start.blockId != normalized.end.blockId) return false;
    final block = _blockAtPosition(normalized.start);
    if (block == null || !_isListLikeBlock(block)) return false;
    if (normalized.start.offset > 0) return false;
    if (normalized.end.offset < block.text.length) return false;
    final index = widget.textController.document.blocks.indexWhere((candidate) => candidate.id == block.id);
    if (index < 0) return false;
    _removeEditableBlockAt(
      index,
      label: 'Delete list item',
      preferEndOfSurvivingBlock: true,
    );
    return true;
  }

  bool _deleteWholeSingleDisplayEquationSelection(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    if (normalized.start.blockId != normalized.end.blockId) return false;
    final block = _blockAtPosition(normalized.start);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) return false;
    if (normalized.start.offset > 0) return false;
    if (normalized.end.offset < block.text.length) return false;
    final index = widget.textController.document.blocks.indexWhere((candidate) => candidate.id == block.id);
    if (index < 0) return false;
    _removeEditableBlockAt(
      index,
      label: 'Delete display equation',
      preferPreviousBlock: true,
      preferEndOfSurvivingBlock: true,
    );
    return true;
  }

  bool _isCaretAtDisplayEquationBodyStart(TextSystemBlock block, int offset) {
    if (!TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) return false;
    final bodyStart = _ownedDisplayEquationInnerSourceStart(block.text);
    return offset <= bodyStart;
  }

  bool _isCaretAtDisplayEquationBodyEnd(TextSystemBlock block, int offset) {
    if (!TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) return false;
    final bodyEnd = _ownedDisplayEquationInnerSourceEnd(block.text);
    return offset >= bodyEnd;
  }

  void _removeEditableBlockAt(
    int index, {
    required String label,
    bool preferPreviousBlock = false,
    bool preferEndOfSurvivingBlock = false,
  }) {
    final document = widget.textController.document;
    if (index < 0 || index >= document.blocks.length) return;

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < document.blocks.length; i++)
        if (i != index) document.blocks[i],
    ];

    if (nextBlocks.isEmpty) {
      nextBlocks.add(TextSystemBlock.paragraph(id: 'empty-${DateTime.now().microsecondsSinceEpoch}', text: ''));
    }

    final targetIndex = preferPreviousBlock && index > 0
        ? index - 1
        : index < nextBlocks.length
            ? index
            : nextBlocks.length - 1;
    final targetBlock = nextBlocks[targetIndex];
    final targetOffset = preferEndOfSurvivingBlock || targetIndex < index ? targetBlock.text.length : 0;

    widget.textController.replaceDocument(
      document.copyWith(
        blocks: List<TextSystemBlock>.unmodifiable(nextBlocks),
        updatedAt: DateTime.now(),
      ),
      label: label,
    );

    if (_canEditBlockText(targetBlock)) {
      _setKeyboardCaret(
        TextSystemDocumentPosition.text(
          blockId: targetBlock.id,
          blockIndex: targetIndex,
          offset: targetOffset.clamp(0, targetBlock.text.length).toInt(),
        ),
      );
    } else if (_isOwnedAtomicBlock(targetBlock)) {
      _selectObjectBlock(targetBlock.id, source: TextSystemEditorSelectionSource.keyboard);
    }
  }


  int _normalizeUtf16BoundaryForBackward(String text, int rawOffset) {
    final offset = rawOffset.clamp(0, text.length).toInt();
    // If a previous buggy edit left the caret between a surrogate pair, treat
    // Backspace as if the caret were after the whole scalar value. This deletes
    // the complete emoji/non-BMP character rather than leaving an unpaired low
    // surrogate behind.
    if (offset > 0 && offset < text.length) {
      final previous = text.codeUnitAt(offset - 1);
      final current = text.codeUnitAt(offset);
      if (_isHighSurrogate(previous) && _isLowSurrogate(current)) {
        return offset + 1;
      }
    }
    return offset;
  }

  int _normalizeUtf16BoundaryForForward(String text, int rawOffset) {
    final offset = rawOffset.clamp(0, text.length).toInt();
    // If the caret is between a surrogate pair, treat Delete as if the caret
    // were before the whole scalar value.
    if (offset > 0 && offset < text.length) {
      final previous = text.codeUnitAt(offset - 1);
      final current = text.codeUnitAt(offset);
      if (_isHighSurrogate(previous) && _isLowSurrogate(current)) {
        return offset - 1;
      }
    }
    return offset;
  }

  int _previousUtf16Boundary(String text, int rawOffset) {
    final offset = rawOffset.clamp(0, text.length).toInt();
    if (offset <= 0) return 0;
    final previous = text.codeUnitAt(offset - 1);
    if (_isLowSurrogate(previous) && offset >= 2) {
      final high = text.codeUnitAt(offset - 2);
      if (_isHighSurrogate(high)) return offset - 2;
    }
    return offset - 1;
  }

  int _nextUtf16Boundary(String text, int rawOffset) {
    final offset = rawOffset.clamp(0, text.length).toInt();
    if (offset >= text.length) return text.length;
    final current = text.codeUnitAt(offset);
    if (_isHighSurrogate(current) && offset + 1 < text.length) {
      final low = text.codeUnitAt(offset + 1);
      if (_isLowSurrogate(low)) return offset + 2;
    }
    return offset + 1;
  }

  bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  KeyEventResult _deleteBackward() {
    final position = _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return KeyEventResult.ignored;

    final document = widget.textController.document;
    final blockIndex = document.blocks.indexWhere((candidate) => candidate.id == block.id);
    final safeOffset = _normalizeUtf16BoundaryForBackward(block.text, position.offset);

    if (TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block) &&
        _isCaretAtDisplayEquationBodyStart(block, safeOffset)) {
      _removeEditableBlockAt(
        blockIndex,
        label: 'Delete display equation',
        preferPreviousBlock: true,
        preferEndOfSurvivingBlock: true,
      );
      return KeyEventResult.handled;
    }

    if (blockIndex > 0 && safeOffset <= 0) {
      final previousBlock = document.blocks[blockIndex - 1];
      if (TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(previousBlock)) {
        _removeEditableBlockAt(
          blockIndex - 1,
          label: 'Delete display equation',
        );
        return KeyEventResult.handled;
      }
    }

    if (safeOffset > 0) {
      final deleteStart = _previousUtf16Boundary(block.text, safeOffset);
      final nextText = block.text.replaceRange(deleteStart, safeOffset, '');
      widget.textController.updateBlockText(block.id, nextText);
      _setKeyboardCaret(position.copyWith(offset: deleteStart));
      return KeyEventResult.handled;
    }

    if (_isListLikeBlock(block)) {
      _removeEditableBlockAt(
        blockIndex,
        label: 'Delete list item',
        preferEndOfSurvivingBlock: true,
      );
      return KeyEventResult.handled;
    }

    if (block.text.isEmpty && blockIndex > 0) {
      final previousBlock = document.blocks[blockIndex - 1];
      if (_isListLikeBlock(previousBlock)) {
        _removeEditableBlockAt(
          blockIndex,
          label: 'Remove empty paragraph after list',
          preferPreviousBlock: true,
          preferEndOfSurvivingBlock: true,
        );
        return KeyEventResult.handled;
      }
    }

    final mergedPosition = widget.textController.mergeBlockWithPrevious(block.id);
    if (mergedPosition != null) {
      _setKeyboardCaret(mergedPosition);
      return KeyEventResult.handled;
    }

    if (_isListLikeBlock(block)) {
      return _exitListItemToParagraph(block, position);
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _deleteForward() {
    final position = _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return KeyEventResult.ignored;

    final document = widget.textController.document;
    final blockIndex = document.blocks.indexWhere((candidate) => candidate.id == block.id);
    final safeOffset = _normalizeUtf16BoundaryForForward(block.text, position.offset);

    if (TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block) &&
        _isCaretAtDisplayEquationBodyEnd(block, safeOffset)) {
      _removeEditableBlockAt(
        blockIndex,
        label: 'Delete display equation',
      );
      return KeyEventResult.handled;
    }

    if (safeOffset < block.text.length) {
      final deleteEnd = _nextUtf16Boundary(block.text, safeOffset);
      final nextText = block.text.replaceRange(safeOffset, deleteEnd, '');
      widget.textController.updateBlockText(block.id, nextText);
      _setKeyboardCaret(position.copyWith(offset: safeOffset));
      return KeyEventResult.handled;
    }

    if (blockIndex >= 0 && blockIndex + 1 < document.blocks.length) {
      final nextBlock = document.blocks[blockIndex + 1];
      if (TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(nextBlock)) {
        _removeEditableBlockAt(
          blockIndex + 1,
          label: 'Delete display equation',
          preferPreviousBlock: true,
          preferEndOfSurvivingBlock: true,
        );
        return KeyEventResult.handled;
      }
    }

    if (blockIndex < 0 || blockIndex + 1 >= document.blocks.length) {
      if (_isListLikeBlock(block) && block.text.trim().isEmpty) {
        return _exitListItemToParagraph(block, position);
      }
      return KeyEventResult.ignored;
    }
    final nextBlock = document.blocks[blockIndex + 1];
    if (!_canEditBlockText(nextBlock)) {
      if (_isListLikeBlock(block) && block.text.trim().isEmpty) {
        return _exitListItemToParagraph(block, position);
      }
      return KeyEventResult.ignored;
    }
    final mergedPosition = widget.textController.mergeBlockWithPrevious(nextBlock.id);
    if (mergedPosition == null) {
      if (_isListLikeBlock(block) && block.text.trim().isEmpty) {
        return _exitListItemToParagraph(block, position);
      }
      return KeyEventResult.ignored;
    }
    _setKeyboardCaret(mergedPosition);
    return KeyEventResult.handled;
  }

  KeyEventResult _splitCurrentBlock() {
    final position = _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return KeyEventResult.ignored;
    if (_isListLikeBlock(block) && block.text.trim().isEmpty) {
      return _exitListItemToParagraph(block, position);
    }
    final nextPosition = widget.textController.splitBlockAt(block.id, position.offset);
    if (nextPosition == null) return KeyEventResult.ignored;
    _setKeyboardCaret(nextPosition);
    return KeyEventResult.handled;
  }

  KeyEventResult _moveCaretHorizontally(
    int delta, {
    bool extendSelection = false,
  }) {
    if (!extendSelection) {
      final range = _activeNonCollapsedTextRange;
      if (range != null) {
        final normalized = range.normalized();
        _setKeyboardCaret(delta < 0 ? normalized.start : normalized.end);
        return KeyEventResult.handled;
      }
    }

    final position = extendSelection ? _keyboardFocusTextPosition : _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final document = widget.textController.document;
    final blockIndex = document.blocks.indexWhere((block) => block.id == position.blockId);
    if (blockIndex < 0) return KeyEventResult.ignored;
    final block = document.blocks[blockIndex];
    final safeOffset = delta < 0
        ? _normalizeUtf16BoundaryForBackward(block.text, position.offset)
        : _normalizeUtf16BoundaryForForward(block.text, position.offset);

    TextSystemDocumentPosition? nextPosition;
    if (delta < 0 && safeOffset > 0) {
      nextPosition = position.copyWith(offset: _previousUtf16Boundary(block.text, safeOffset));
    } else if (delta > 0 && safeOffset < block.text.length) {
      nextPosition = position.copyWith(offset: _nextUtf16Boundary(block.text, safeOffset));
    } else {
      nextPosition = delta < 0
          ? _nearestNavigableBoundaryBefore(blockIndex)
          : _nearestNavigableBoundaryAfter(blockIndex);
    }

    if (nextPosition == null) return KeyEventResult.ignored;
    if (nextPosition.isOnBlock) {
      _selectObjectAtPosition(nextPosition, source: TextSystemEditorSelectionSource.keyboard);
      return KeyEventResult.handled;
    }
    if (!nextPosition.isTextOffset) return KeyEventResult.ignored;
    final clamped = _clampedTextPosition(nextPosition);
    if (clamped == null) return KeyEventResult.ignored;
    if (!extendSelection && _activateInlineMathAtKeyboardPosition(clamped, movementDelta: delta)) {
      return KeyEventResult.handled;
    }
    if (extendSelection) {
      _extendKeyboardSelectionTo(clamped);
    } else {
      _setKeyboardCaret(clamped);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _moveCaretVertically(
    int direction, {
    bool extendSelection = false,
  }) {
    if (!extendSelection) {
      final range = _activeNonCollapsedTextRange;
      if (range != null) {
        final normalized = range.normalized();
        _setKeyboardCaret(direction < 0 ? normalized.start : normalized.end);
        return KeyEventResult.handled;
      }
    }

    final position = extendSelection ? _keyboardFocusTextPosition : _activeTextPosition;
    final snapshot = _lastSnapshot;
    if (position == null || snapshot == null) return KeyEventResult.ignored;

    final caretRect = snapshot.rectForPosition(position);
    if (caretRect == null) {
      return _moveCaretHorizontally(
        direction < 0 ? -1 : 1,
        extendSelection: extendSelection,
      );
    }

    final targetOffset = Offset(
      caretRect.left,
      caretRect.center.dy + direction * math.max(18.0, caretRect.height * 1.35),
    );
    final hit = TextSystemEditorHitTester(snapshot: snapshot, defaultTolerance: 24).hitTest(
      targetOffset,
      tolerance: 24,
    );
    final hitPosition = hit.position;
    if (hitPosition != null) {
      if (hit.isObjectLike || hitPosition.isOnBlock) {
        final hitBlock = _blockAtPosition(hitPosition);
        if (hitBlock != null && _isStructuralBreakBlock(hitBlock)) {
          return _moveCaretHorizontally(
            direction < 0 ? -1 : 1,
            extendSelection: extendSelection,
          );
        }
        if (extendSelection) {
          _extendKeyboardSelectionTo(hitPosition);
        } else if (hitBlock != null && _isOwnedAtomicBlock(hitBlock)) {
          _selectObjectAtPosition(hitPosition, source: TextSystemEditorSelectionSource.keyboard);
        } else {
          _selectionController.selectFromHit(
            hit,
            source: TextSystemEditorSelectionSource.keyboard,
          );
        }
        _lastHit = hit;
        widget.commandController?.scheduleStateRefresh();
        return KeyEventResult.handled;
      }
      if (hitPosition.isTextOffset) {
        final clamped = _clampedTextPosition(hitPosition);
        if (clamped != null) {
          _lastHit = hit;
          if (!extendSelection && _activateInlineMathAtKeyboardPosition(clamped, movementDelta: direction)) {
            return KeyEventResult.handled;
          }
          if (extendSelection) {
            _extendKeyboardSelectionTo(clamped);
          } else {
            _setKeyboardCaret(clamped);
          }
          return KeyEventResult.handled;
        }
      }
    }

    return _moveCaretHorizontally(
      direction < 0 ? -1 : 1,
      extendSelection: extendSelection,
    );
  }

  TextSystemDocumentPosition? _nearestNavigableBoundaryBefore(int blockIndex) {
    final document = widget.textController.document;
    for (var i = blockIndex - 1; i >= 0; i--) {
      final block = document.blocks[i];
      if (_isOwnedAtomicBlock(block) && !_isStructuralBreakBlock(block)) {
        return TextSystemDocumentPosition.onBlock(blockId: block.id, blockIndex: i);
      }
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: i,
        offset: block.text.length,
      );
    }
    return null;
  }

  TextSystemDocumentPosition? _nearestNavigableBoundaryAfter(int blockIndex) {
    final document = widget.textController.document;
    for (var i = blockIndex + 1; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (_isOwnedAtomicBlock(block) && !_isStructuralBreakBlock(block)) {
        return TextSystemDocumentPosition.onBlock(blockId: block.id, blockIndex: i);
      }
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: i,
        offset: 0,
      );
    }
    return null;
  }

  void _selectObjectAtPosition(
    TextSystemDocumentPosition position, {
    TextSystemEditorSelectionSource source = TextSystemEditorSelectionSource.keyboard,
  }) {
    final document = widget.textController.document;
    if (position.blockIndex < 0 || position.blockIndex >= document.blocks.length) return;
    final block = document.blocks[position.blockIndex];
    if (!_isOwnedAtomicBlock(block) || _isStructuralBreakBlock(block)) return;
    _inlineMathController.deactivate();
    _inlineReferenceController.hide();
    _selectionController.selectObject(
      blockId: block.id,
      blockIndex: position.blockIndex,
      source: source,
      metadata: <String, Object?>{
        'keyboardObjectSelection': true,
        'objectKind': _objectKindForBlock(block),
      },
    );
    widget.commandController?.scheduleStateRefresh();
  }

  void _extendKeyboardSelectionTo(TextSystemDocumentPosition focus) {
    final selection = _selectionState.selection;
    final anchor = selection?.anchor ?? _activeTextPosition ?? focus;
    _inlineMathController.deactivate();
    _inlineReferenceController.hide();
    _selectionController.selectDocumentRange(
      TextSystemDocumentRange(start: anchor, end: focus),
      source: TextSystemEditorSelectionSource.keyboard,
    );
  }

  KeyEventResult _selectCurrentParagraph() {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return KeyEventResult.ignored;
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return KeyEventResult.ignored;
    _inlineMathController.deactivate();
    _inlineReferenceController.hide();
    _selectionController.selectDocumentRange(
      TextSystemDocumentRange(
        start: TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: position.blockIndex,
          offset: 0,
        ),
        end: TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: position.blockIndex,
          offset: block.text.length,
        ),
      ),
      source: TextSystemEditorSelectionSource.keyboard,
    );
    return KeyEventResult.handled;
  }

  TextSystemDocumentPosition? _nearestEditableBoundaryBefore(int blockIndex) {
    final document = widget.textController.document;
    for (var i = blockIndex - 1; i >= 0; i--) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: i,
        offset: block.text.length,
      );
    }
    return null;
  }

  TextSystemDocumentPosition? _nearestEditableBoundaryAfter(int blockIndex) {
    final document = widget.textController.document;
    for (var i = blockIndex + 1; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (!_canEditBlockText(block)) continue;
      return TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: i,
        offset: 0,
      );
    }
    return null;
  }

  void _setKeyboardCaret(TextSystemDocumentPosition position) {
    final clamped = _clampedTextPosition(position);
    if (clamped == null) return;
    setState(() {
      _lastHit = null;
    });
    _selectionController.collapseTo(
      clamped,
      source: TextSystemEditorSelectionSource.keyboard,
    );
  }

  void _moveEquationPreviewCaret(TextSystemDocumentPosition position) {
    // Preview taps happen inside a nested gesture surface while the page itself
    // also owns a tap handler. Defer the final caret update by one frame so the
    // source jump wins after the generic page hit-test has run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _inlineMathController.deactivate();
      _setKeyboardCaret(position);
      widget.commandController?.scheduleStateRefresh();
      if (mounted) setState(() {});
    });
  }

  void _selectEquationPreviewRange(TextSystemDocumentRange range) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final start = _clampedTextPosition(range.start);
      final end = _clampedTextPosition(range.end);
      if (start == null || end == null) return;
      _focusNode.requestFocus();
      _inlineMathController.deactivate();
      _lastHit = null;
      _selectionController.selectDocumentRange(
        TextSystemDocumentRange(start: start, end: end),
        source: TextSystemEditorSelectionSource.pointer,
      );
      widget.commandController?.scheduleStateRefresh();
      if (mounted) setState(() {});
    });
  }


  void _jumpToEquationStructureCell(int rowIndex, int columnIndex) {
    final position = _keyboardFocusTextPosition ?? _activeTextPosition;
    if (position == null) return;
    final block = _blockAtPosition(position);
    if (block == null || !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) {
      return;
    }

    final span = _activeEquationEnvironmentSpan(const <String>{
      'matrix',
      'pmatrix',
      'bmatrix',
      'vmatrix',
      'Vmatrix',
      'smallmatrix',
      'aligned',
      'alignedat',
      'split',
      'gathered',
      'cases',
    });
    if (span == null) return;

    final rows = _equationEnvironmentCellTexts(span);
    final existingColumnCount = rows.isEmpty
        ? _equationEnvironmentColumnCount(span)
        : rows.map((row) => row.length).fold<int>(1, (previous, value) => math.max(previous, value).toInt());
    final targetRow = math.max(0, rowIndex);
    final targetColumn = math.max(0, columnIndex);
    final columnCount = math.max(existingColumnCount, targetColumn + 1);
    final normalizedRows = _normalizeEquationMatrixRows(rows, columnCount);
    while (normalizedRows.length <= targetRow) {
      normalizedRows.add(List<String>.filled(columnCount, '', growable: true));
    }

    final content = _serializeEquationMatrixRows(normalizedRows);
    final caretOffset = _matrixCellCaretOffset(
      span.contentStart,
      normalizedRows,
      targetRow,
      targetColumn,
    );

    _replaceActiveEquationSourceSlice(
      span.contentStart,
      span.contentEnd,
      content,
      caretOffset: caretOffset,
      label: 'Jump to equation structure cell',
    );
  }


  void _replaceOwnedBlock(TextSystemBlock updated, {required String label}) {
    final document = widget.textController.document;
    final blocks = List<TextSystemBlock>.from(document.blocks);
    final index = blocks.indexWhere((candidate) => candidate.id == updated.id);
    if (index < 0) return;
    blocks[index] = updated;
    widget.textController.replaceDocument(
      document.copyWith(blocks: blocks),
      label: label,
    );
    widget.commandController?.scheduleStateRefresh();
    if (mounted) setState(() {});
  }

  void _toggleActiveEquationNumbering() {
    final block = _activeDisplayEquationBlockForRange();
    if (block == null) {
      _showOwnedCommandSnack('Place the caret in a display equation first.');
      return;
    }
    final nextNumbered = !_ownedEquationIsNumbered(block);
    final metadata = Map<String, Object?>.from(block.metadata)
      ..['kind'] = block.metadata['kind'] ?? 'displayEquation'
      ..['numbered'] = nextNumbered
      ..['presentation'] = nextNumbered ? 'numbered' : 'display';
    if (!nextNumbered) {
      metadata['presentation'] = 'display';
    }
    final updatedBlock = block.copyWith(metadata: Map<String, Object?>.unmodifiable(metadata));
    final updatedDocument = widget.textController.document.replaceBlock(updatedBlock);
    _replaceOwnedBlock(
      updatedBlock,
      label: nextNumbered ? 'Number equation' : 'Unnumber equation',
    );
    final text = nextNumbered
        ? 'Equation numbering on: ${_ownedEquationReferenceText(updatedDocument, updatedBlock)}'
        : 'Equation numbering off';
    _showOwnedCommandSnack(text);
  }

  Future<void> _editActiveEquationLabel() async {
    final block = _activeDisplayEquationBlockForRange();
    if (block == null) {
      _showOwnedCommandSnack('Place the caret in a display equation first.');
      return;
    }
    final currentLabel = _ownedObjectLabel(block);
    final labelController = TextEditingController(text: currentLabel);
    try {
      final nextLabel = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Equation label'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: labelController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'eq:main-result',
                      helperText: 'Used for stable cross-references even when equation numbers change.',
                    ),
                    onSubmitted: (_) => Navigator.of(dialogContext).pop(labelController.text),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        labelController.text = _ownedAcademicLabelSuggestion(
                          document: widget.textController.document,
                          kind: 'equation',
                          fallback: 'equation-${_ownedEquationOrdinal(widget.textController.document, block)}',
                          value: _ownedDisplayEquationSource(block),
                        );
                      },
                      icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                      label: const Text('Suggest label'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(''), child: const Text('Remove label')),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(labelController.text),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (!mounted || nextLabel == null) return;
      final trimmed = nextLabel.trim();
      final metadata = Map<String, Object?>.from(block.metadata)
        ..['kind'] = block.metadata['kind'] ?? 'displayEquation';
      if (trimmed.isEmpty) {
        metadata.remove('label');
      } else {
        metadata['label'] = trimmed;
      }
      _replaceOwnedBlock(
        block.copyWith(metadata: Map<String, Object?>.unmodifiable(metadata)),
        label: trimmed.isEmpty ? 'Remove equation label' : 'Set equation label',
      );
      _showOwnedCommandSnack(trimmed.isEmpty ? 'Equation label removed.' : 'Equation label set to $trimmed.');
    } finally {
      labelController.dispose();
    }
  }

  void _copyActiveEquationReference() {
    final block = _activeDisplayEquationBlockForRange();
    if (block == null) {
      _showOwnedCommandSnack('Place the caret in a display equation first.');
      return;
    }
    final reference = _ownedEquationReferenceText(widget.textController.document, block);
    Clipboard.setData(ClipboardData(text: reference));
    final label = _ownedObjectLabel(block);
    final suffix = label.isEmpty ? '' : ' · $label';
    _showOwnedCommandSnack('Copied $reference$suffix');
  }

  bool _activateInlineMathAtKeyboardPosition(
    TextSystemDocumentPosition position, {
    int movementDelta = 0,
  }) {
    final block = _blockAtPosition(position);
    if (block == null || block.text.isEmpty) return false;
    final blockIndex = widget.textController.document.blocks.indexWhere((candidate) => candidate.id == block.id);
    if (blockIndex < 0) return false;
    final atoms = TextSystemInlineAtomRenderer.atomsForVisibleRange(
      text: block.text,
      block: block,
      blockIndex: blockIndex,
      globalStart: 0,
      globalEnd: block.text.length,
    );
    for (final atom in atoms) {
      if (!atom.isMath) continue;
      if (position.offset < atom.globalRange.start || position.offset > atom.globalRange.end) continue;
      final active = _inlineMathController.activeRange?.normalized();
      if (active != null &&
          active.start.blockId == block.id &&
          active.start.offset == atom.globalRange.start &&
          active.end.offset == atom.globalRange.end) {
        return false;
      }
      _inlineReferenceController.hide();
      _inlineMathController.activate(atom);
      _selectionController.collapseTo(
        TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: blockIndex,
          offset: _preferredInlineMathCaretOffset(atom, incomingOffset: position.offset, movementDelta: movementDelta),
        ),
        source: TextSystemEditorSelectionSource.keyboard,
      );
      return true;
    }
    return false;
  }

  int _preferredInlineMathCaretOffset(
    TextSystemInlineAtom atom, {
    required int incomingOffset,
    int movementDelta = 0,
  }) {
    final start = atom.globalRange.start;
    final end = atom.globalRange.end;
    final innerStart = math.min(end, start + 2);
    final innerEnd = math.max(innerStart, end - 2);
    if (incomingOffset <= start) return innerStart;
    if (incomingOffset >= end) return innerEnd;
    return incomingOffset.clamp(innerStart, innerEnd).toInt();
  }

  void _handlePageTap({
    required BuildContext context,
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockLayout layout,
    required TextSystemPagedBlockPage page,
    required EdgeInsets margins,
    required Offset localPageOffset,
    required Offset globalPosition,
  }) {
    _focusNode.requestFocus();
    final hit = _hitForPagePointerOffset(
      context: context,
      snapshot: snapshot,
      layout: layout,
      page: page,
      margins: margins,
      localPageOffset: localPageOffset,
    );
    if (hit == null) {
      if (_placeCaretAtPageTypingEndpoint(
        page: page,
        margins: margins,
        localPageOffset: localPageOffset,
      )) {
        setState(() {
          _lastHit = null;
        });
      }
      return;
    }
    setState(() {
      _lastHit = hit;
    });
    if (_handleInlineAtomTap(hit, globalPosition)) return;
    _inlineMathController.deactivate();
    _selectionController.selectFromHit(hit);
  }


  bool _placeCaretAtPageTypingEndpoint({
    required TextSystemPagedBlockPage page,
    required EdgeInsets margins,
    required Offset localPageOffset,
  }) {
    if (page.fragments.isEmpty) return false;

    TextSystemPagedBlockFragment? lastFragment;
    Rect? lastPageRect;
    for (final fragment in page.fragments) {
      final block = widget.textController.document.blockById(fragment.blockId);
      if (block == null || _isPageBreakBlock(block) || _isSectionBreakBlock(block)) continue;
      final pageRect = fragment.rect.shift(Offset(margins.left, margins.top));
      if (lastPageRect == null || pageRect.bottom > lastPageRect.bottom) {
        lastFragment = fragment;
        lastPageRect = pageRect;
      }
    }

    final fragment = lastFragment;
    final pageRect = lastPageRect;
    if (fragment == null || pageRect == null) return false;

    // Clicking in the unused writing area below the lowest laid-out content on a
    // page should act like clicking at the current typing endpoint. This makes
    // it much easier to continue after compact display equations or objects on
    // an otherwise empty page.
    if (localPageOffset.dy < pageRect.bottom + 8) return false;

    final document = widget.textController.document;
    final blockIndex = document.blocks.indexWhere((candidate) => candidate.id == fragment.blockId);
    if (blockIndex < 0) return false;
    final block = document.blocks[blockIndex];

    _inlineMathController.deactivate();
    if (_canEditBlockText(block) && !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block)) {
      _setKeyboardCaret(TextSystemDocumentPosition.text(
        blockId: block.id,
        blockIndex: blockIndex,
        offset: block.text.length,
      ));
      return true;
    }

    final position = _ensureParagraphAfterBlock(
      blockIndex,
      label: 'Continue writing below page content',
    );
    _setKeyboardCaret(position);
    return true;
  }

  TextSystemDocumentPosition _ensureParagraphAfterBlock(
    int blockIndex, {
    required String label,
  }) {
    final document = widget.textController.document;
    final nextIndex = blockIndex + 1;
    if (nextIndex < document.blocks.length) {
      final nextBlock = document.blocks[nextIndex];
      if (_canEditBlockText(nextBlock) && !TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(nextBlock)) {
        return TextSystemDocumentPosition.text(
          blockId: nextBlock.id,
          blockIndex: nextIndex,
          offset: 0,
        );
      }
    }

    final paragraph = TextSystemBlock.paragraph(
      id: 'paragraph-${DateTime.now().microsecondsSinceEpoch}',
      text: '',
    );
    final nextBlocks = <TextSystemBlock>[];
    for (var i = 0; i < document.blocks.length; i++) {
      nextBlocks.add(document.blocks[i]);
      if (i == blockIndex) nextBlocks.add(paragraph);
    }
    if (blockIndex >= document.blocks.length) nextBlocks.add(paragraph);

    widget.textController.replaceDocument(
      document.copyWith(
        blocks: List<TextSystemBlock>.unmodifiable(nextBlocks),
        updatedAt: DateTime.now(),
      ),
      label: label,
    );
    return TextSystemDocumentPosition.text(
      blockId: paragraph.id,
      blockIndex: math.min(nextIndex, nextBlocks.length - 1).toInt(),
      offset: 0,
    );
  }

  void _handlePageDoubleTap({
    required BuildContext context,
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockLayout layout,
    required TextSystemPagedBlockPage page,
    required EdgeInsets margins,
    required Offset localPageOffset,
  }) {
    _focusNode.requestFocus();
    final hit = _hitForPagePointerOffset(
      context: context,
      snapshot: snapshot,
      layout: layout,
      page: page,
      margins: margins,
      localPageOffset: localPageOffset,
    );
    if (hit == null) return;
    setState(() {
      _lastHit = hit;
    });

    final atom = hit.metadata['inlineAtom'];
    if (atom is TextSystemInlineAtom) {
      if (atom.isMath) {
        _inlineMathController.activate(atom);
        _selectionController.selectDocumentRange(
          TextSystemDocumentRange(
            start: TextSystemDocumentPosition.text(
              blockId: atom.blockId,
              blockIndex: atom.blockIndex,
              offset: atom.globalRange.start,
            ),
            end: TextSystemDocumentPosition.text(
              blockId: atom.blockId,
              blockIndex: atom.blockIndex,
              offset: atom.globalRange.end,
            ),
          ),
          source: TextSystemEditorSelectionSource.pointer,
        );
      } else {
        _handleInlineAtomTap(hit, hit.globalOffset);
      }
      return;
    }

    final position = hit.position;
    if (position == null || !position.isTextOffset) {
      _selectionController.selectFromHit(hit);
      return;
    }
    final block = _blockAtPosition(position);
    if (block == null || !_canEditBlockText(block)) return;
    final wordRange = _wordRangeAtOffset(block.text, position.offset);
    _inlineMathController.deactivate();
    _inlineReferenceController.hide();
    _selectionController.selectDocumentRange(
      TextSystemDocumentRange(
        start: TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: position.blockIndex,
          offset: wordRange.start,
        ),
        end: TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: position.blockIndex,
          offset: wordRange.end,
        ),
      ),
      source: TextSystemEditorSelectionSource.pointer,
    );
  }

  TextSystemRange _wordRangeAtOffset(String text, int rawOffset) {
    if (text.isEmpty) return const TextSystemRange(0, 0);
    final offset = rawOffset.clamp(0, text.length).toInt();
    var probe = offset;
    if (probe == text.length) probe = math.max(0, probe - 1);
    if (probe > 0 && !_isWordCodeUnit(text.codeUnitAt(probe))) {
      final previous = text.codeUnitAt(probe - 1);
      if (_isWordCodeUnit(previous)) probe -= 1;
    }

    if (probe < 0 || probe >= text.length || !_isWordCodeUnit(text.codeUnitAt(probe))) {
      var start = offset;
      while (start > 0 && !_isWordCodeUnit(text.codeUnitAt(start - 1))) {
        start--;
      }
      var end = offset;
      while (end < text.length && !_isWordCodeUnit(text.codeUnitAt(end))) {
        end++;
      }
      if (start == end) end = math.min(text.length, start + 1);
      return TextSystemRange(start, end);
    }

    var start = probe;
    while (start > 0 && _isWordCodeUnit(text.codeUnitAt(start - 1))) {
      start--;
    }
    var end = probe + 1;
    while (end < text.length && _isWordCodeUnit(text.codeUnitAt(end))) {
      end++;
    }
    return TextSystemRange(start, end);
  }

  bool _isWordCodeUnit(int codeUnit) {
    final isAsciiDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    final isUpper = codeUnit >= 0x41 && codeUnit <= 0x5A;
    final isLower = codeUnit >= 0x61 && codeUnit <= 0x7A;
    if (isAsciiDigit || isUpper || isLower || codeUnit == 0x5F) return true;
    if (codeUnit <= 0x20) return false;
    const punctuation = <int>{
      0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A,
      0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E,
      0x3F, 0x40, 0x5B, 0x5C, 0x5D, 0x5E, 0x60, 0x7B, 0x7C, 0x7D,
      0x7E,
    };
    return !punctuation.contains(codeUnit);
  }

  bool _handleInlineAtomTap(TextSystemEditorHitTestResult hit, Offset globalPosition) {
    final atom = hit.metadata['inlineAtom'];
    if (atom is! TextSystemInlineAtom) return false;
    if (atom.isMath) {
      _inlineReferenceController.hide();
      _inlineMathController.activate(atom);
      _selectionController.collapseTo(
        TextSystemDocumentPosition.text(
          blockId: atom.blockId,
          blockIndex: atom.blockIndex,
          offset: _preferredInlineMathCaretOffset(
            atom,
            incomingOffset: atom.globalRange.end,
            movementDelta: 1,
          ),
        ),
        source: TextSystemEditorSelectionSource.pointer,
        hit: hit,
      );
      return true;
    }
    if (atom.isReference) {
      _inlineMathController.deactivate();
      _selectionController.selectInlineAtom(
        blockId: atom.blockId,
        blockIndex: atom.blockIndex,
        atomStartOffset: atom.globalRange.start,
        atomEndOffset: atom.globalRange.end,
        atomId: atom.id,
        source: TextSystemEditorSelectionSource.pointer,
        hit: hit,
      );
      _inlineReferenceController.showForAtom(
        atom: atom,
        globalPosition: globalPosition,
        pinned: true,
      );
      return true;
    }
    return false;
  }

  void _handlePageHover({
    required BuildContext context,
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockLayout layout,
    required TextSystemPagedBlockPage page,
    required EdgeInsets margins,
    required Offset localPageOffset,
    required Offset globalPosition,
  }) {
    final hit = _hitForPagePointerOffset(
      context: context,
      snapshot: snapshot,
      layout: layout,
      page: page,
      margins: margins,
      localPageOffset: localPageOffset,
    );
    final atom = hit?.metadata['inlineAtom'];
    if (atom is TextSystemInlineAtom && atom.isReference) {
      _inlineReferenceController.showForAtom(
        atom: atom,
        globalPosition: globalPosition,
      );
      return;
    }
    _inlineReferenceController.scheduleClose();
  }

  void _handlePageDragStart({
    required BuildContext context,
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockLayout layout,
    required TextSystemPagedBlockPage page,
    required EdgeInsets margins,
    required Offset localPageOffset,
  }) {
    _focusNode.requestFocus();
    final hit = _hitForPagePointerOffset(
      context: context,
      snapshot: snapshot,
      layout: layout,
      page: page,
      margins: margins,
      localPageOffset: localPageOffset,
    );
    if (hit == null) return;
    setState(() {
      _lastHit = hit;
    });
    _selectionController.beginPointerSelection(hit);
  }

  void _handlePageDragUpdate({
    required BuildContext context,
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockLayout layout,
    required TextSystemPagedBlockPage page,
    required EdgeInsets margins,
    required Offset localPageOffset,
  }) {
    final hit = _hitForPagePointerOffset(
      context: context,
      snapshot: snapshot,
      layout: layout,
      page: page,
      margins: margins,
      localPageOffset: localPageOffset,
    );
    if (hit == null) return;
    setState(() {
      _lastHit = hit;
    });
    _selectionController.updatePointerSelection(hit);
  }

  void _handlePageDragEnd() {
    _selectionController.commitPointerSelection();
  }

  void _handlePageDragCancel() {
    _selectionController.cancelPointerSelection();
  }

  TextSystemEditorHitTestResult? _hitForPagePointerOffset({
    required BuildContext context,
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockLayout layout,
    required TextSystemPagedBlockPage page,
    required EdgeInsets margins,
    required Offset localPageOffset,
    bool preferPreciseTextHit = true,
  }) {
    final pageIndex = layout.pages.indexOf(page);
    if (pageIndex < 0) return null;
    Rect? pageRect;
    for (final candidate in snapshot.layoutIndex.pages) {
      if (candidate.pageIndex == pageIndex) {
        pageRect = candidate.globalRect;
        break;
      }
    }
    if (pageRect == null) return null;

    final logicalSurfaceOffset = Offset(
      pageRect.left + localPageOffset.dx,
      pageRect.top + localPageOffset.dy,
    );

    final preciseHit = preferPreciseTextHit
        ? _preciseTextHitForPageOffset(
            context: context,
            snapshot: snapshot,
            page: page,
            pageIndex: pageIndex,
            margins: margins,
            localPageOffset: localPageOffset,
            logicalSurfaceOffset: logicalSurfaceOffset,
          )
        : null;

    return preciseHit ??
        TextSystemEditorHitTester(snapshot: snapshot, defaultTolerance: 18).hitTest(
          logicalSurfaceOffset,
          tolerance: 18,
        );
  }

  TextSystemEditorHitTestResult? _preciseTextHitForPageOffset({
    required BuildContext context,
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockPage page,
    required int pageIndex,
    required EdgeInsets margins,
    required Offset localPageOffset,
    required Offset logicalSurfaceOffset,
  }) {
    const tolerance = 4.0;
    TextSystemPagedBlockFragment? bestFragment;
    Rect? bestPageRect;
    var bestDistance = double.infinity;

    for (final fragment in page.fragments) {
      final block = snapshot.blockById(fragment.blockId);
      if (block == null || _isObjectBlock(block) || _isPageBreakBlock(block) || _isSectionBreakBlock(block)) {
        continue;
      }
      final pageRect = fragment.rect.shift(Offset(margins.left, margins.top));
      final inflated = pageRect.inflate(tolerance);
      if (!inflated.contains(localPageOffset)) continue;
      final dx = localPageOffset.dx < pageRect.left
          ? pageRect.left - localPageOffset.dx
          : localPageOffset.dx > pageRect.right
              ? localPageOffset.dx - pageRect.right
              : 0.0;
      final dy = localPageOffset.dy < pageRect.top
          ? pageRect.top - localPageOffset.dy
          : localPageOffset.dy > pageRect.bottom
              ? localPageOffset.dy - pageRect.bottom
              : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestFragment = fragment;
        bestPageRect = pageRect;
      }
    }

    final fragment = bestFragment;
    final pageRect = bestPageRect;
    if (fragment == null || pageRect == null) return null;

    final block = snapshot.blockById(fragment.blockId);
    if (block == null) return null;

    final style = TextSystemEditorMarkedTextLayout.effectiveTextStyleFor(
      context,
      block,
      TextSystemLayoutStyleResolver.blockStyle(
        context: context,
        block: block,
        pageSetup: widget.pageSetup,
      ),
    );
    final isDisplayEquationBlock = TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block);
    final layoutTextStyle = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationSourceTextStyleFor(context, style)
        : style;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final visible = TextSystemEditorMarkedTextLayout.visibleFragmentFor(
      block: block,
      blockIndex: fragment.blockIndex,
      sourceStart: fragment.visualTextStartOffset,
      sourceEnd: fragment.visualTextEndOffset,
      continuesFromPreviousPage: fragment.continuesFromPreviousPage,
    );
    final codePadding = block.type == TextSystemBlockType.code
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
        : EdgeInsets.zero;
    final listTextInset = TextSystemEditorMarkedTextLayout.listTextInsetFor(block);
    final textLocalOffset = Offset(
      (localPageOffset.dx - pageRect.left - codePadding.left - listTextInset).clamp(0.0, double.infinity).toDouble(),
      (localPageOffset.dy - pageRect.top - codePadding.top).clamp(0.0, double.infinity).toDouble(),
    );
    final availableTextWidth = math.max(1.0, pageRect.width - codePadding.horizontal - listTextInset);
    final maxWidth = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationSourceTextMaxWidth(availableWidth: availableTextWidth)
        : availableTextWidth;
    final activeSourceTextRange = _activeSourceTextRangeForBlock(block);
    final painter = TextPainter(
      text: TextSystemEditorMarkedTextLayout.textSpanForVisibleFragment(
        context: context,
        visible: visible,
        baseStyle: layoutTextStyle,
        activeInlineAtomSourceRange: activeSourceTextRange,
      ),
      textAlign: TextSystemEditorMarkedTextLayout.sourceTextAlignFor(block),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);

    final displayEquationTextTopInset = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationVerticalTextInset(
            fragmentHeight: pageRect.height - codePadding.vertical,
            textHeight: painter.height,
          )
        : 0.0;
    final displayEquationTextLeftInset = isDisplayEquationBlock
        ? TextSystemEditorMarkedTextLayout.displayEquationSourceHorizontalInset(
            painter: painter,
            visibleText: visible.visibleText,
            maxWidth: maxWidth,
          )
        : 0.0;
    var adjustedTextLocalOffset = isDisplayEquationBlock
        ? Offset(
            (textLocalOffset.dx - displayEquationTextLeftInset).clamp(0.0, double.infinity).toDouble(),
            (textLocalOffset.dy - displayEquationTextTopInset).clamp(0.0, double.infinity).toDouble(),
          )
        : textLocalOffset;
    if (isDisplayEquationBlock && visible.visibleText.trim().isNotEmpty) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: visible.visibleText.length),
      );
      if (boxes.isNotEmpty) {
        final textBounds = boxes
            .map((box) => box.toRect())
            .reduce((value, element) => value.expandToInclude(element));
        adjustedTextLocalOffset = Offset(
          adjustedTextLocalOffset.dx.clamp(textBounds.left, textBounds.right).toDouble(),
          adjustedTextLocalOffset.dy.clamp(textBounds.top, math.max(textBounds.bottom, textBounds.top + painter.preferredLineHeight)).toDouble(),
        );
      }
    }

    final textPosition = painter.getPositionForOffset(adjustedTextLocalOffset);
    final rawDocumentOffset = visible.visualOffsetToDocument(textPosition.offset);
    final documentOffset = TextSystemInlineAtomRenderer.adjustDocumentOffsetForInlineAtomEdge(
      painter: painter,
      localOffset: adjustedTextLocalOffset,
      block: block,
      blockIndex: fragment.blockIndex,
      sourceText: visible.sourceText,
      globalStart: visible.sourceStart,
      globalEnd: visible.sourceEnd,
      prefixLength: visible.prefixLength,
      documentOffset: rawDocumentOffset,
      activeInlineAtomSourceRange: activeSourceTextRange,
    );

    final inlineAtom = TextSystemInlineAtomRenderer.atomAtTextLocalOffset(
      painter: painter,
      localOffset: adjustedTextLocalOffset,
      block: block,
      blockIndex: fragment.blockIndex,
      sourceText: visible.sourceText,
      globalStart: visible.sourceStart,
      globalEnd: visible.sourceEnd,
      prefixLength: visible.prefixLength,
      activeInlineAtomSourceRange: activeSourceTextRange,
    );
    final documentPosition = inlineAtom == null
        ? TextSystemDocumentPosition.text(
            blockId: fragment.blockId,
            blockIndex: fragment.blockIndex,
            offset: documentOffset,
          )
        : TextSystemDocumentPosition.inlineAtom(
            blockId: fragment.blockId,
            blockIndex: fragment.blockIndex,
            atomId: inlineAtom.id,
            atomStartOffset: inlineAtom.globalRange.start,
            atomEndOffset: inlineAtom.globalRange.end,
          );

    final layoutFragment = _layoutFragmentForPagedFragment(
      snapshot: snapshot,
      fragment: fragment,
      pageIndex: pageIndex,
    );
    if (layoutFragment == null) return null;

    final caretVisualOffset = visible.documentOffsetToVisual(documentOffset);
    final caretTextPosition = TextPosition(offset: math.min(caretVisualOffset, visible.visibleText.length).toInt());
    final caretOffset = painter.getOffsetForCaret(
      caretTextPosition,
      Rect.fromLTWH(0, 0, 1, painter.preferredLineHeight),
    );
    final caretHeight = math.max(12.0, painter.preferredLineHeight);
    final caretGlobalRect = Rect.fromLTWH(
      pageRect.left + codePadding.left + listTextInset + displayEquationTextLeftInset + caretOffset.dx,
      pageRect.top + codePadding.top + displayEquationTextTopInset + caretOffset.dy,
      1,
      caretHeight,
    ).shift(Offset(0, snapshot.layoutIndex.pages[pageIndex].globalRect.top));

    return TextSystemEditorHitTestResult(
      kind: inlineAtom == null ? TextSystemEditorHitTargetKind.text : TextSystemEditorHitTargetKind.inlineAtom,
      globalOffset: logicalSurfaceOffset,
      layoutHit: TextSystemDocumentLayoutHit(
        globalOffset: logicalSurfaceOffset,
        fragment: layoutFragment,
        position: documentPosition,
        isExactHit: true,
      ),
      pageIndex: pageIndex,
      metadata: <String, Object?>{
        'fragmentId': layoutFragment.id,
        'fragmentKind': layoutFragment.kind.name,
        'isExactHit': true,
        'preciseTextHit': true,
        'caretGlobalRect': caretGlobalRect,
        if (inlineAtom != null) 'inlineAtom': inlineAtom,
        if (inlineAtom != null) 'inlineAtomKind': inlineAtom.kind.name,
      },
    );
  }


  TextSystemRange? _activeSourceTextRangeForBlock(TextSystemBlock block) {
    final range = _inlineMathController.activeRange?.normalized();
    if (range == null || range.start.blockId != block.id || range.end.blockId != block.id) return null;
    return TextSystemRange(
      range.start.offset.clamp(0, block.text.length).toInt(),
      range.end.offset.clamp(0, block.text.length).toInt(),
    );
  }

  TextSystemDocumentLayoutFragment? _layoutFragmentForPagedFragment({
    required TextSystemEditorLayoutSnapshot snapshot,
    required TextSystemPagedBlockFragment fragment,
    required int pageIndex,
  }) {
    for (final layoutFragment in snapshot.layoutIndex.fragmentsForBlock(fragment.blockId)) {
      if (layoutFragment.pageIndex != pageIndex || !layoutFragment.isTextLike) continue;
      if (layoutFragment.start?.offset == fragment.visualTextStartOffset &&
          layoutFragment.end?.offset == fragment.visualTextEndOffset) {
        return layoutFragment;
      }
    }
    return null;
  }
}

class _OwnedDocumentEditorBanner extends StatelessWidget {
  const _OwnedDocumentEditorBanner({
    required this.layout,
    required this.snapshot,
    required this.selectionState,
    required this.lastHit,
  });

  final TextSystemPagedBlockLayout layout;
  final TextSystemEditorLayoutSnapshot snapshot;
  final TextSystemEditorSelectionState selectionState;
  final TextSystemEditorHitTestResult? lastHit;

  String get _selectionLabel {
    final selection = selectionState.selection;
    if (selection == null) {
      return lastHit == null ? '' : ' · last hit: ${lastHit!.kind.name}';
    }
    return ' · ${selection.diagnosticLabel}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 920),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, color: colorScheme.primary, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Owned editor preview · selection, clipboard, formatting, references, IME bridge · ${layout.label} · ${snapshot.fragmentCount} fragments${_selectionLabel}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _EquationCommandPrefixRange {
  const _EquationCommandPrefixRange({
    required this.block,
    required this.blockIndex,
    required this.start,
    required this.end,
    required this.typed,
  });

  final TextSystemBlock block;
  final int blockIndex;
  final int start;
  final int end;
  final String typed;
}

class _OwnedDocumentPageView extends StatelessWidget {
  const _OwnedDocumentPageView({
    required this.document,
    required this.textController,
    required this.page,
    required this.pageCount,
    required this.pageSetup,
    required this.pageFurniture,
    required this.pageWidth,
    required this.pageHeight,
    required this.margins,
    required this.showMarginGuides,
    required this.showPageHeader,
    required this.pageHeaderHeight,
    required this.pageHeaderGap,
    required this.snapshot,
    required this.selectionState,
    required this.textInputClient,
    required this.activeInlineAtomSourceRange,
    required this.onEquationInsertFraction,
    required this.onEquationInsertSuperscript,
    required this.onEquationInsertSubscript,
    required this.onEquationInsertText,
    required this.onEquationInsertDerivative,
    required this.onEquationInsertMatrix,
    required this.onEquationInsertAligned,
    required this.onEquationInsertCases,
    required this.onEquationInsertMatrixRow,
    required this.onEquationInsertMatrixColumn,
    required this.onEquationInsertAlignedLine,
    required this.onEquationInsertAlignmentMarker,
    required this.onEquationInsertCasesRow,
    required this.onEquationInsertSymbol,
    required this.onEquationAcceptCommandCompletion,
    required this.equationCompletionHighlightedIndex,
    required this.equationCompletionUsageCounts,
    required this.onEquationFormatSource,
    required this.onEquationJumpNextSlot,
    required this.onEquationJumpPreviousSlot,
    required this.onEquationPreviewSourceOffset,
    required this.onEquationPreviewSourceRange,
    required this.onEquationStructureCellSelected,
    required this.onEquationToggleNumbering,
    required this.onEquationEditLabel,
    required this.onEquationCopyReference,
    required this.onPageTap,
    required this.onPageDoubleTap,
    required this.onPageHover,
    required this.onPageExit,
    required this.onPageDragStart,
    required this.onPageDragUpdate,
    required this.onPageDragEnd,
    required this.onPageDragCancel,
  });

  final TextSystemDocument document;
  final TextSystemController textController;
  final TextSystemPagedBlockPage page;
  final int pageCount;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final double pageWidth;
  final double pageHeight;
  final EdgeInsets margins;
  final bool showMarginGuides;
  final bool showPageHeader;
  final double pageHeaderHeight;
  final double pageHeaderGap;
  final TextSystemEditorLayoutSnapshot snapshot;
  final TextSystemEditorSelectionState selectionState;
  final TextSystemEditorTextInputClient textInputClient;
  final TextSystemDocumentRange? activeInlineAtomSourceRange;
  final VoidCallback onEquationInsertFraction;
  final VoidCallback onEquationInsertSuperscript;
  final VoidCallback onEquationInsertSubscript;
  final VoidCallback onEquationInsertText;
  final VoidCallback onEquationInsertDerivative;
  final VoidCallback onEquationInsertMatrix;
  final VoidCallback onEquationInsertAligned;
  final VoidCallback onEquationInsertCases;
  final VoidCallback onEquationInsertMatrixRow;
  final VoidCallback onEquationInsertMatrixColumn;
  final VoidCallback onEquationInsertAlignedLine;
  final VoidCallback onEquationInsertAlignmentMarker;
  final VoidCallback onEquationInsertCasesRow;
  final ValueChanged<String> onEquationInsertSymbol;
  final void Function(String completion, int caretOffset) onEquationAcceptCommandCompletion;
  final int equationCompletionHighlightedIndex;
  final Map<String, int> equationCompletionUsageCounts;
  final VoidCallback onEquationFormatSource;
  final VoidCallback onEquationJumpNextSlot;
  final VoidCallback onEquationJumpPreviousSlot;
  final ValueChanged<TextSystemDocumentPosition> onEquationPreviewSourceOffset;
  final ValueChanged<TextSystemDocumentRange> onEquationPreviewSourceRange;
  final void Function(int rowIndex, int columnIndex) onEquationStructureCellSelected;
  final VoidCallback onEquationToggleNumbering;
  final VoidCallback onEquationEditLabel;
  final VoidCallback onEquationCopyReference;
  final ValueChanged<TapDownDetails> onPageTap;
  final ValueChanged<TapDownDetails> onPageDoubleTap;
  final ValueChanged<PointerHoverEvent> onPageHover;
  final ValueChanged<PointerExitEvent> onPageExit;
  final ValueChanged<Offset> onPageDragStart;
  final ValueChanged<Offset> onPageDragUpdate;
  final VoidCallback onPageDragEnd;
  final VoidCallback onPageDragCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        if (showPageHeader) ...[
          SizedBox(
            height: pageHeaderHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Page ${page.displayPageNumber} of $pageCount · owned preview',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(height: pageHeaderGap),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.72)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: MouseRegion(
            onHover: onPageHover,
            onExit: onPageExit,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onPageTap,
            onDoubleTapDown: onPageDoubleTap,
            onPanStart: (details) => onPageDragStart(details.localPosition),
            onPanUpdate: (details) => onPageDragUpdate(details.localPosition),
            onPanEnd: (_) => onPageDragEnd(),
            onPanCancel: onPageDragCancel,
            child: SizedBox(
              width: pageWidth,
              height: pageHeight,
              child: Stack(
                children: [
                if (showMarginGuides)
                  Positioned.fromRect(
                    rect: Rect.fromLTWH(
                      margins.left,
                      margins.top,
                      math.max(0, pageWidth - margins.horizontal),
                      math.max(0, pageHeight - margins.vertical),
                    ),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                _OwnedPageFurniturePreview(
                  documentTitle: document.title,
                  sectionTitle: _sectionTitleForPage(document, page),
                  physicalPageNumber: page.pageNumber,
                  pageNumber: page.displayPageNumber,
                  pageFurniture: pageFurniture,
                  margins: margins,
                ),
                Positioned(
                  left: margins.left,
                  top: margins.top,
                  width: math.max(0, pageWidth - margins.horizontal),
                  height: math.max(0, pageHeight - margins.vertical),
                  child: Stack(
                    children: [
                      for (final fragment in page.fragments)
                        Positioned.fromRect(
                          rect: fragment.rect,
                          child: _OwnedDocumentBlockFragmentView(
                            document: document,
                            textController: textController,
                            fragment: fragment,
                            pageSetup: pageSetup,
                            selectionState: selectionState,
                            activeInlineAtomSourceRange: activeInlineAtomSourceRange,
                            onEquationInsertFraction: onEquationInsertFraction,
                            onEquationInsertSuperscript: onEquationInsertSuperscript,
                            onEquationInsertSubscript: onEquationInsertSubscript,
                            onEquationInsertText: onEquationInsertText,
                            onEquationInsertDerivative: onEquationInsertDerivative,
                            onEquationInsertMatrix: onEquationInsertMatrix,
                            onEquationInsertAligned: onEquationInsertAligned,
                            onEquationInsertCases: onEquationInsertCases,
                            onEquationInsertMatrixRow: onEquationInsertMatrixRow,
                            onEquationInsertMatrixColumn: onEquationInsertMatrixColumn,
                            onEquationInsertAlignedLine: onEquationInsertAlignedLine,
                            onEquationInsertAlignmentMarker: onEquationInsertAlignmentMarker,
                            onEquationInsertCasesRow: onEquationInsertCasesRow,
                            onEquationInsertSymbol: onEquationInsertSymbol,
                            onEquationAcceptCommandCompletion: onEquationAcceptCommandCompletion,
                            equationCompletionHighlightedIndex: equationCompletionHighlightedIndex,
                            equationCompletionUsageCounts: equationCompletionUsageCounts,
                            onEquationFormatSource: onEquationFormatSource,
                            onEquationJumpNextSlot: onEquationJumpNextSlot,
                            onEquationJumpPreviousSlot: onEquationJumpPreviousSlot,
                            onEquationPreviewSourceOffset: onEquationPreviewSourceOffset,
                            onEquationPreviewSourceRange: onEquationPreviewSourceRange,
                            onEquationStructureCellSelected: onEquationStructureCellSelected,
                            onEquationToggleNumbering: onEquationToggleNumbering,
                            onEquationEditLabel: onEquationEditLabel,
                            onEquationCopyReference: onEquationCopyReference,
                          ),
                        ),
                      if (page.footnotes.isNotEmpty)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _OwnedFootnotePreview(
                            footnotes: page.footnotes,
                            textController: textController,
                          ),
                        ),
                    ],
                  ),
                ),
                TextSystemEditorSelectionOverlay(
                  snapshot: snapshot,
                  selectionState: selectionState,
                  pageIndex: page.pageNumber - 1,
                  pageSetup: pageSetup,
                  activeInlineAtomSourceRange: activeInlineAtomSourceRange,
                  selectionColor: colorScheme.primary,
                  borderColor: colorScheme.primary,
                ),
                TextSystemEditorCaretOverlay(
                  snapshot: snapshot,
                  selectionState: selectionState,
                  pageIndex: page.pageNumber - 1,
                  pageSetup: pageSetup,
                  activeInlineAtomSourceRange: activeInlineAtomSourceRange,
                  caretColor: colorScheme.primary,
                  selectionColor: colorScheme.primary,
                ),
                TextSystemEditorComposingOverlay(
                  snapshot: snapshot,
                  textInputClient: textInputClient,
                  pageIndex: page.pageNumber - 1,
                  pageSetup: pageSetup,
                  color: colorScheme.primary,
                ),
                ],
              ),
            ),
          ),
        ),
        ),
      ],
    );
  }
}

class _OwnedPageFurniturePreview extends StatelessWidget {
  const _OwnedPageFurniturePreview({
    required this.documentTitle,
    required this.sectionTitle,
    required this.physicalPageNumber,
    required this.pageNumber,
    required this.pageFurniture,
    required this.margins,
  });

  final String documentTitle;
  final String sectionTitle;
  final int physicalPageNumber;
  final int pageNumber;
  final TextSystemPageFurniture pageFurniture;
  final EdgeInsets margins;

  String _resolveTokens(String rawText) {
    return rawText
        .replaceAll('{{pageNumber}}', '$pageNumber')
        .replaceAll('{{documentTitle}}', documentTitle.trim().isEmpty ? 'Untitled document' : documentTitle.trim())
        .replaceAll('{{sectionTitle}}', sectionTitle.trim().isEmpty ? 'Section' : sectionTitle.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.46),
      fontWeight: FontWeight.w600,
    );
    final children = <Widget>[];

    if (pageFurniture.headerFooter.enabled) {
      final headerZone = pageFurniture.headerFooter.zoneFor(
        kind: TextSystemHeaderFooterZoneKind.header,
        physicalPageNumber: physicalPageNumber,
      );
      final footerZone = pageFurniture.headerFooter.zoneFor(
        kind: TextSystemHeaderFooterZoneKind.footer,
        physicalPageNumber: physicalPageNumber,
      );
      if (headerZone.enabled && headerZone.hasContent) {
        children.add(
          Positioned(
            left: margins.left,
            right: margins.right,
            top: math.max(6, margins.top * 0.20),
            child: Text(
              _resolveTokens(headerZone.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        );
      }
      if (footerZone.enabled && footerZone.hasContent) {
        children.add(
          Positioned(
            left: margins.left,
            right: margins.right,
            bottom: math.max(6, margins.bottom * 0.22),
            child: Text(
              _resolveTokens(footerZone.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
        );
      }
    }

    if (pageFurniture.headerMode == TextSystemPageHeaderMode.documentTitle) {
      children.add(
        Positioned(
          left: margins.left,
          right: margins.right,
          top: math.max(6, margins.top * 0.20),
          child: Text(
            documentTitle.trim().isEmpty ? 'Untitled document' : documentTitle.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      );
    }

    if (pageFurniture.pageNumbers.visibleOnPage(physicalPageNumber)) {
      final label = pageFurniture.pageNumbers.labelForPage(physicalPageNumber);
      final alignment = switch (pageFurniture.pageNumbers.position) {
        TextSystemPageNumberPosition.topRight => Alignment.topRight,
        TextSystemPageNumberPosition.bottomRight => Alignment.bottomRight,
        TextSystemPageNumberPosition.bottomCenter => Alignment.bottomCenter,
      };
      final padding = EdgeInsets.only(
        left: margins.left,
        right: margins.right,
        top: math.max(6, margins.top * 0.20),
        bottom: math.max(6, margins.bottom * 0.22),
      );
      children.add(
        Positioned.fill(
          child: Padding(
            padding: padding,
            child: Align(
              alignment: alignment,
              child: Text(label, style: style),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(child: Stack(children: children));
  }
}

class _OwnedDocumentBlockFragmentView extends StatelessWidget {
  const _OwnedDocumentBlockFragmentView({
    required this.document,
    required this.textController,
    required this.fragment,
    required this.pageSetup,
    required this.selectionState,
    required this.onEquationInsertFraction,
    required this.onEquationInsertSuperscript,
    required this.onEquationInsertSubscript,
    required this.onEquationInsertText,
    required this.onEquationInsertDerivative,
    required this.onEquationInsertMatrix,
    required this.onEquationInsertAligned,
    required this.onEquationInsertCases,
    required this.onEquationInsertMatrixRow,
    required this.onEquationInsertMatrixColumn,
    required this.onEquationInsertAlignedLine,
    required this.onEquationInsertAlignmentMarker,
    required this.onEquationInsertCasesRow,
    required this.onEquationInsertSymbol,
    required this.onEquationAcceptCommandCompletion,
    required this.equationCompletionHighlightedIndex,
    required this.equationCompletionUsageCounts,
    required this.onEquationFormatSource,
    required this.onEquationJumpNextSlot,
    required this.onEquationJumpPreviousSlot,
    required this.onEquationPreviewSourceOffset,
    required this.onEquationPreviewSourceRange,
    required this.onEquationStructureCellSelected,
    required this.onEquationToggleNumbering,
    required this.onEquationEditLabel,
    required this.onEquationCopyReference,
    this.activeInlineAtomSourceRange,
  });

  final TextSystemDocument document;
  final TextSystemController textController;
  final TextSystemPagedBlockFragment fragment;
  final TextSystemPageSetup pageSetup;
  final TextSystemEditorSelectionState selectionState;
  final TextSystemDocumentRange? activeInlineAtomSourceRange;
  final VoidCallback onEquationInsertFraction;
  final VoidCallback onEquationInsertSuperscript;
  final VoidCallback onEquationInsertSubscript;
  final VoidCallback onEquationInsertText;
  final VoidCallback onEquationInsertDerivative;
  final VoidCallback onEquationInsertMatrix;
  final VoidCallback onEquationInsertAligned;
  final VoidCallback onEquationInsertCases;
  final VoidCallback onEquationInsertMatrixRow;
  final VoidCallback onEquationInsertMatrixColumn;
  final VoidCallback onEquationInsertAlignedLine;
  final VoidCallback onEquationInsertAlignmentMarker;
  final VoidCallback onEquationInsertCasesRow;
  final ValueChanged<String> onEquationInsertSymbol;
  final void Function(String completion, int caretOffset) onEquationAcceptCommandCompletion;
  final int equationCompletionHighlightedIndex;
  final Map<String, int> equationCompletionUsageCounts;
  final VoidCallback onEquationFormatSource;
  final VoidCallback onEquationJumpNextSlot;
  final VoidCallback onEquationJumpPreviousSlot;
  final ValueChanged<TextSystemDocumentPosition> onEquationPreviewSourceOffset;
  final ValueChanged<TextSystemDocumentRange> onEquationPreviewSourceRange;
  final void Function(int rowIndex, int columnIndex) onEquationStructureCellSelected;
  final VoidCallback onEquationToggleNumbering;
  final VoidCallback onEquationEditLabel;
  final VoidCallback onEquationCopyReference;

  TextSystemBlock? get _block {
    if (fragment.blockIndex >= 0 && fragment.blockIndex < document.blocks.length) {
      final candidate = document.blocks[fragment.blockIndex];
      if (candidate.id == fragment.blockId) return candidate;
    }
    return document.blockById(fragment.blockId);
  }

  @override
  Widget build(BuildContext context) {
    final block = _block;
    final resolvedBlock = block ?? TextSystemBlock.paragraph(id: fragment.blockId, text: fragment.text);
    if (_isObjectBlock(resolvedBlock)) {
      return _OwnedObjectBlockPreview(
        document: document,
        textController: textController,
        block: resolvedBlock,
      );
    }
    if (_isPageBreakBlock(resolvedBlock) || _isSectionBreakBlock(resolvedBlock)) {
      return const SizedBox.shrink();
    }

    final style = TextSystemEditorMarkedTextLayout.effectiveTextStyleFor(
      context,
      resolvedBlock,
      TextSystemLayoutStyleResolver.blockStyle(
        context: context,
        block: resolvedBlock,
        pageSetup: pageSetup,
      ),
    );
    if (TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(resolvedBlock)) {
      return _OwnedDisplayEquationFragment(
        document: document,
        block: resolvedBlock,
        fragment: fragment,
        style: style,
        selectionState: selectionState,
        onInsertFraction: onEquationInsertFraction,
        onInsertSuperscript: onEquationInsertSuperscript,
        onInsertSubscript: onEquationInsertSubscript,
        onInsertText: onEquationInsertText,
        onInsertDerivative: onEquationInsertDerivative,
        onInsertMatrix: onEquationInsertMatrix,
        onInsertAligned: onEquationInsertAligned,
        onInsertCases: onEquationInsertCases,
        onInsertMatrixRow: onEquationInsertMatrixRow,
        onInsertMatrixColumn: onEquationInsertMatrixColumn,
        onInsertAlignedLine: onEquationInsertAlignedLine,
        onInsertAlignmentMarker: onEquationInsertAlignmentMarker,
        onInsertCasesRow: onEquationInsertCasesRow,
        onInsertSymbol: onEquationInsertSymbol,
        onAcceptCommandCompletion: onEquationAcceptCommandCompletion,
        commandCompletionHighlightedIndex: equationCompletionHighlightedIndex,
        commandCompletionUsageCounts: equationCompletionUsageCounts,
        onFormatSource: onEquationFormatSource,
        onJumpNextSlot: onEquationJumpNextSlot,
        onJumpPreviousSlot: onEquationJumpPreviousSlot,
        onPreviewSourceOffset: onEquationPreviewSourceOffset,
        onPreviewSourceRange: onEquationPreviewSourceRange,
        onStructureCellSelected: onEquationStructureCellSelected,
        onToggleNumbering: onEquationToggleNumbering,
        onEditLabel: onEquationEditLabel,
        onCopyReference: onEquationCopyReference,
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: _OwnedTextFragment(
        block: resolvedBlock,
        fragment: fragment,
        style: style,
        activeInlineAtomSourceRange: activeInlineAtomSourceRange,
      ),
    );
  }
}

class _OwnedDisplayEquationFragment extends StatelessWidget {
  const _OwnedDisplayEquationFragment({
    required this.document,
    required this.block,
    required this.fragment,
    required this.style,
    required this.selectionState,
    required this.onInsertFraction,
    required this.onInsertSuperscript,
    required this.onInsertSubscript,
    required this.onInsertText,
    required this.onInsertDerivative,
    required this.onInsertMatrix,
    required this.onInsertAligned,
    required this.onInsertCases,
    required this.onInsertMatrixRow,
    required this.onInsertMatrixColumn,
    required this.onInsertAlignedLine,
    required this.onInsertAlignmentMarker,
    required this.onInsertCasesRow,
    required this.onInsertSymbol,
    required this.onAcceptCommandCompletion,
    required this.commandCompletionHighlightedIndex,
    required this.commandCompletionUsageCounts,
    required this.onFormatSource,
    required this.onJumpNextSlot,
    required this.onJumpPreviousSlot,
    required this.onPreviewSourceOffset,
    required this.onPreviewSourceRange,
    required this.onStructureCellSelected,
    required this.onToggleNumbering,
    required this.onEditLabel,
    required this.onCopyReference,
  });

  final TextSystemDocument document;
  final TextSystemBlock block;
  final TextSystemPagedBlockFragment fragment;
  final TextStyle style;
  final TextSystemEditorSelectionState selectionState;
  final VoidCallback onInsertFraction;
  final VoidCallback onInsertSuperscript;
  final VoidCallback onInsertSubscript;
  final VoidCallback onInsertText;
  final VoidCallback onInsertDerivative;
  final VoidCallback onInsertMatrix;
  final VoidCallback onInsertAligned;
  final VoidCallback onInsertCases;
  final VoidCallback onInsertMatrixRow;
  final VoidCallback onInsertMatrixColumn;
  final VoidCallback onInsertAlignedLine;
  final VoidCallback onInsertAlignmentMarker;
  final VoidCallback onInsertCasesRow;
  final ValueChanged<String> onInsertSymbol;
  final void Function(String completion, int caretOffset) onAcceptCommandCompletion;
  final int commandCompletionHighlightedIndex;
  final Map<String, int> commandCompletionUsageCounts;
  final VoidCallback onFormatSource;
  final VoidCallback onJumpNextSlot;
  final VoidCallback onJumpPreviousSlot;
  final ValueChanged<TextSystemDocumentPosition> onPreviewSourceOffset;
  final ValueChanged<TextSystemDocumentRange> onPreviewSourceRange;
  final void Function(int rowIndex, int columnIndex) onStructureCellSelected;
  final VoidCallback onToggleNumbering;
  final VoidCallback onEditLabel;
  final VoidCallback onCopyReference;

  bool get _isEditing {
    final range = selectionState.range?.normalized();
    if (range == null) return false;
    return range.start.blockId == block.id || range.end.blockId == block.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final source = _ownedDisplayEquationSource(block);
    final note = _ownedObjectNote(block);
    final numbered = _ownedEquationIsNumbered(block);
    final numberLabel = numbered ? _ownedEquationNumberLabel(document, block) : null;
    final equationLabel = _ownedObjectLabel(block);
    final visible = TextSystemEditorMarkedTextLayout.visibleFragmentFor(
      block: block,
      blockIndex: fragment.blockIndex,
      sourceStart: fragment.visualTextStartOffset,
      sourceEnd: fragment.visualTextEndOffset,
      continuesFromPreviousPage: fragment.continuesFromPreviousPage,
    );

    final sourceStyle = TextSystemEditorMarkedTextLayout.displayEquationSourceTextStyleFor(context, style);
    final activeOffset = selectionState.selection?.focus.blockId == block.id && selectionState.selection?.focus.isTextOffset == true
        ? (selectionState.selection!.focus.offset - visible.layoutSourceStart).clamp(0, visible.visibleText.length).toInt()
        : null;
    final activeRange = selectionState.range?.normalized();
    final activeSourceRangeStart = activeRange != null &&
            !activeRange.isCollapsed &&
            activeRange.start.blockId == block.id &&
            activeRange.end.blockId == block.id &&
            activeRange.start.isTextOffset &&
            activeRange.end.isTextOffset
        ? (activeRange.start.offset - visible.layoutSourceStart).clamp(0, visible.visibleText.length).toInt()
        : null;
    final activeSourceRangeEnd = activeRange != null &&
            !activeRange.isCollapsed &&
            activeRange.start.blockId == block.id &&
            activeRange.end.blockId == block.id &&
            activeRange.start.isTextOffset &&
            activeRange.end.isTextOffset
        ? (activeRange.end.offset - visible.layoutSourceStart).clamp(0, visible.visibleText.length).toInt()
        : null;
    final sourceEditor = OwnedEquationAuthoringSurface(
      sourceText: visible.visibleText,
      sourceSpan: TextSystemEditorMarkedTextLayout.textSpanForVisibleFragment(
        context: context,
        visible: visible,
        baseStyle: sourceStyle,
        activeSourceOffset: activeOffset,
      ),
      sourceTextStyle: sourceStyle,
      previewTextStyle: style.copyWith(
        color: colorScheme.onSurface,
        fontSize: (style.fontSize ?? 16) * 1.00,
        fontWeight: FontWeight.w400,
        height: 1.20,
        letterSpacing: 0,
      ),
      textScaler: MediaQuery.textScalerOf(context),
      activeSourceOffset: activeOffset,
      activeSourceRangeStart: activeSourceRangeStart,
      activeSourceRangeEnd: activeSourceRangeEnd,
      numbered: numbered,
      numberLabel: numberLabel,
      equationLabel: equationLabel,
      onToggleNumbered: onToggleNumbering,
      onEditLabel: onEditLabel,
      onCopyReference: onCopyReference,
      onInsertFraction: onInsertFraction,
      onInsertSuperscript: onInsertSuperscript,
      onInsertSubscript: onInsertSubscript,
      onInsertText: onInsertText,
      onInsertDerivative: onInsertDerivative,
      onInsertMatrix: onInsertMatrix,
      onInsertAligned: onInsertAligned,
      onInsertCases: onInsertCases,
      onInsertMatrixRow: onInsertMatrixRow,
      onInsertMatrixColumn: onInsertMatrixColumn,
      onInsertAlignedLine: onInsertAlignedLine,
      onInsertAlignmentMarker: onInsertAlignmentMarker,
      onInsertCasesRow: onInsertCasesRow,
      onInsertSymbol: onInsertSymbol,
      onAcceptCommandCompletion: onAcceptCommandCompletion,
      commandCompletionUsageCounts: commandCompletionUsageCounts,
      highlightedCommandCompletionIndex: commandCompletionHighlightedIndex,
      onFormatSource: onFormatSource,
      onJumpNextSlot: onJumpNextSlot,
      onJumpPreviousSlot: onJumpPreviousSlot,
      onPreviewSourceOffset: (localOffset) {
        final safeOffset = localOffset.clamp(0, visible.visibleText.length).toInt();
        onPreviewSourceOffset(TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: fragment.blockIndex,
          offset: visible.layoutSourceStart + safeOffset,
        ));
      },
      onPreviewSourceRange: (localStart, localEnd) {
        final safeStart = localStart.clamp(0, visible.visibleText.length).toInt();
        final safeEnd = localEnd.clamp(safeStart, visible.visibleText.length).toInt();
        final start = TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: fragment.blockIndex,
          offset: visible.layoutSourceStart + safeStart,
        );
        final end = TextSystemDocumentPosition.text(
          blockId: block.id,
          blockIndex: fragment.blockIndex,
          offset: visible.layoutSourceStart + safeEnd,
        );
        onPreviewSourceRange(TextSystemDocumentRange(start: start, end: end));
      },
      onStructureCellSelected: (_, rowIndex, columnIndex) =>
          onStructureCellSelected(rowIndex, columnIndex),
    );

    final renderedEquation = _OwnedRenderedDisplayEquation(
      source: source.isEmpty ? r'E = mc^2' : source,
      style: style,
      muted: source.isEmpty,
      numbered: numbered,
      numberLabel: numberLabel,
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: _isEditing ? 0 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _isEditing ? sourceEditor : renderedEquation,
          ),
          if (note.isNotEmpty)
            Text(
              'Note. $note',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _OwnedEquationSourceCodeLine extends StatelessWidget {
  const _OwnedEquationSourceCodeLine({
    required this.textScaler,
    required this.text,
  });

  final TextScaler textScaler;
  final InlineSpan text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        border: Border(
          bottom: BorderSide(color: colorScheme.primary.withValues(alpha: 0.34)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.zero,
        child: RichText(
          textAlign: TextAlign.start,
          textScaler: textScaler,
          text: text,
          maxLines: null,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}

class _OwnedRenderedDisplayEquation extends StatelessWidget {
  const _OwnedRenderedDisplayEquation({
    required this.source,
    required this.style,
    required this.muted,
    required this.numbered,
    required this.numberLabel,
  });

  final String source;
  final TextStyle style;
  final bool muted;
  final bool numbered;
  final String? numberLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mathTextStyle = style.copyWith(
      color: muted ? colorScheme.onSurfaceVariant.withValues(alpha: 0.72) : colorScheme.onSurface,
      fontSize: (style.fontSize ?? 16) * 1.00,
      fontWeight: FontWeight.w400,
      height: 1.20,
      letterSpacing: 0,
    );
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 2),
                    child: Math.tex(
                      _ownedDisplayEquationSourceFromRaw(source),
                      mathStyle: MathStyle.display,
                      textStyle: mathTextStyle,
                      onErrorFallback: (error) => Text(
                        source,
                        textAlign: TextAlign.center,
                        style: mathTextStyle.copyWith(
                          fontFamily: 'monospace',
                          fontFamilyFallback: null,
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (numbered && numberLabel != null)
            Positioned(
              right: 0,
              child: Text(
                numberLabel!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}

class _OwnedTextFragment extends StatelessWidget {
  const _OwnedTextFragment({
    required this.block,
    required this.fragment,
    required this.style,
    this.activeInlineAtomSourceRange,
  });

  final TextSystemBlock block;
  final TextSystemPagedBlockFragment fragment;
  final TextStyle style;
  final TextSystemDocumentRange? activeInlineAtomSourceRange;


  TextSystemRange? _activeSourceTextRangeForBlock() {
    final range = activeInlineAtomSourceRange?.normalized();
    if (range == null || range.start.blockId != block.id || range.end.blockId != block.id) return null;
    return TextSystemRange(
      range.start.offset.clamp(0, block.text.length).toInt(),
      range.end.offset.clamp(0, block.text.length).toInt(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = TextSystemEditorMarkedTextLayout.visibleFragmentFor(
      block: block,
      blockIndex: fragment.blockIndex,
      sourceStart: fragment.visualTextStartOffset,
      sourceEnd: fragment.visualTextEndOffset,
      continuesFromPreviousPage: fragment.continuesFromPreviousPage,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final isDisplayEquation = TextSystemEditorMarkedTextLayout.isDisplayEquationBlock(block);
    final activeSourceTextRange = _activeSourceTextRangeForBlock();
    final text = RichText(
      textAlign: TextSystemEditorMarkedTextLayout.textAlignFor(block),
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSystemEditorMarkedTextLayout.textSpanForVisibleFragment(
        context: context,
        visible: visible,
        baseStyle: style,
        activeInlineAtomSourceRange: activeSourceTextRange,
      ),
      maxLines: null,
      overflow: TextOverflow.clip,
    );
    final marker = TextSystemEditorMarkedTextLayout.listMarkerFor(block);
    final listTextInset = TextSystemEditorMarkedTextLayout.listTextInsetFor(block);
    final content = marker.isEmpty
        ? text
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: TextSystemEditorMarkedTextLayout.listMarkerWidthFor(block),
                child: Text(
                  marker,
                  textAlign: TextAlign.right,
                  style: style.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: math.max(0, listTextInset - TextSystemEditorMarkedTextLayout.listMarkerWidthFor(block))),
              Expanded(child: text),
            ],
          );
    return Container(
      width: isDisplayEquation ? double.infinity : null,
      alignment: isDisplayEquation ? Alignment.center : Alignment.topLeft,
      padding: block.type == TextSystemBlockType.code
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : EdgeInsets.zero,
      decoration: block.type == TextSystemBlockType.code
          ? BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.42)),
            )
          : null,
      child: content,
    );
  }
}

class _OwnedObjectBlockPreview extends StatelessWidget {
  const _OwnedObjectBlockPreview({
    required this.document,
    required this.textController,
    required this.block,
  });

  final TextSystemDocument document;
  final TextSystemController textController;
  final TextSystemBlock block;

  @override
  Widget build(BuildContext context) {
    final kind = (block.metadata['kind'] as String?) ?? 'object';
    return switch (kind) {
      'figure' => _OwnedFigureBlockPreview(document: document, textController: textController, block: block),
      'table' => _OwnedTableBlockPreview(document: document, textController: textController, block: block),
      'equation' => _OwnedEquationBlockPreview(document: document, block: block),
      _ => _OwnedGenericObjectBlockPreview(block: block),
    };
  }
}

class _OwnedFigureBlockPreview extends StatelessWidget {
  const _OwnedFigureBlockPreview({
    required this.document,
    required this.textController,
    required this.block,
  });

  final TextSystemDocument document;
  final TextSystemController textController;
  final TextSystemBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ordinal = _ownedAcademicObjectOrdinal(document, block, kind: 'figure');
    final caption = _ownedObjectCaption(block);
    final label = _ownedObjectLabel(block);
    final source = _ownedObjectSource(block);
    final altText = _ownedObjectAltText(block);
    final noteParts = <String>[
      if (source.isNotEmpty) source,
      if (altText.isNotEmpty) altText,
      if (label.isNotEmpty) 'Label: $label',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: _OwnedFigureImagePreview(
                textController: textController,
                block: block,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption.isEmpty ? 'Figure $ordinal' : 'Figure $ordinal: $caption',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (noteParts.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Note. ${noteParts.join(' · ')}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnedFigureImagePreview extends StatelessWidget {
  const _OwnedFigureImagePreview({
    required this.textController,
    required this.block,
  });

  final TextSystemController textController;
  final TextSystemBlock block;

  bool _isNetworkImage(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  bool get _hasVisibleBounds {
    return block.metadata['imageVisibleLeft'] != null &&
        block.metadata['imageVisibleTop'] != null &&
        block.metadata['imageVisibleRight'] != null &&
        block.metadata['imageVisibleBottom'] != null;
  }

  void _ensureLocalImageMetadata(String imagePath) {
    if (_hasVisibleBounds) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final metadata = await _ownedImageMetadataForLocalPath(imagePath);
      if (metadata.isEmpty) return;
      _ownedUpdateBlockMetadata(
        textController: textController,
        blockId: block.id,
        metadataPatch: metadata,
        label: 'Update figure image metadata',
      );
    });
  }

  Future<void> _chooseImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return;
    final trimmedPath = path.trim();
    final imageMetadata = await _ownedImageMetadataForLocalPath(trimmedPath);
    _ownedUpdateBlockMetadata(
      textController: textController,
      blockId: block.id,
      metadataPatch: <String, Object?>{
        'imagePath': trimmedPath,
        ...imageMetadata,
      },
      label: 'Attach figure image',
    );
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _ownedObjectImagePath(block);
    final source = _ownedObjectSource(block);
    final fileName = _ownedFileName(imagePath);
    final localImageExists = _ownedLocalImageExists(imagePath);
    final sourceIsNetworkImage = source.isNotEmpty && _isNetworkImage(source);
    final placeholder = imagePath.isNotEmpty
        ? (fileName.isEmpty ? 'Image file not found' : '$fileName not found')
        : 'Attach image';

    Widget child;
    if (localImageExists) {
      _ensureLocalImageMetadata(imagePath);
      child = Image.file(
        File(imagePath),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _OwnedFigureEmptyPreview(label: placeholder, onPressed: _chooseImage),
      );
    } else if (sourceIsNetworkImage) {
      child = Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _OwnedFigureEmptyPreview(label: source, onPressed: _chooseImage),
        loadingBuilder: (context, loadedChild, progress) {
          if (progress == null) return loadedChild;
          return const _OwnedFigureEmptyPreview(label: 'Loading image…');
        },
      );
    } else {
      child = _OwnedFigureEmptyPreview(label: placeholder, onPressed: _chooseImage);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = OwnedContentObjectGeometry.centeredFigureImageSize(
          constraints: constraints,
          block: block,
        );
        return SizedBox(
          width: math.max(56.0, size.width),
          height: math.max(56.0, size.height),
          child: ClipRect(child: child),
        );
      },
    );
  }
}

class _OwnedFigureEmptyPreview extends StatelessWidget {
  const _OwnedFigureEmptyPreview({
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.add_photo_alternate_outlined, size: 20, color: colorScheme.primary),
        label: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}


class _OwnedTableBlockPreview extends StatelessWidget {
  const _OwnedTableBlockPreview({
    required this.document,
    required this.textController,
    required this.block,
  });

  final TextSystemDocument document;
  final TextSystemController textController;
  final TextSystemBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ordinal = _ownedAcademicObjectOrdinal(document, block, kind: 'table');
    final caption = _ownedObjectCaption(block);
    final note = _ownedObjectNote(block);
    final label = _ownedObjectLabel(block);
    final noteParts = <String>[
      if (note.isNotEmpty) note,
      if (label.isNotEmpty) 'Label: $label',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (caption.isNotEmpty) ...[
            Text(
              'Table $ordinal',
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              caption,
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Expanded(
            child: _OwnedDocumentTableSurface(
              textController: textController,
              block: block,
            ),
          ),
          if (noteParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Note. ${noteParts.join(' · ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnedDocumentTableSurface extends StatefulWidget {
  const _OwnedDocumentTableSurface({
    required this.textController,
    required this.block,
  });

  final TextSystemController textController;
  final TextSystemBlock block;

  @override
  State<_OwnedDocumentTableSurface> createState() => _OwnedDocumentTableSurfaceState();
}

class _OwnedDocumentTableSurfaceState extends State<_OwnedDocumentTableSurface> {
  var _selectedRow = 0;
  var _selectedColumn = 0;

  int get _rows => _ownedTableRows(widget.block);
  int get _columns => _ownedTableColumns(widget.block);
  int get _headerRows => _ownedTableHeaderRows(widget.block);
  List<List<String>> get _cells => _ownedTableCells(widget.block, rows: _rows, columns: _columns);

  @override
  void didUpdateWidget(covariant _OwnedDocumentTableSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedRow = _selectedRow.clamp(0, math.max(0, _rows - 1)).toInt();
    _selectedColumn = _selectedColumn.clamp(0, math.max(0, _columns - 1)).toInt();
  }

  void _selectCell(int row, int column) {
    setState(() {
      _selectedRow = row.clamp(0, math.max(0, _rows - 1)).toInt();
      _selectedColumn = column.clamp(0, math.max(0, _columns - 1)).toInt();
    });
  }

  void _replaceCells(List<List<String>> nextCells, {required String label}) {
    final safe = _ownedNormalizeTableCells(nextCells);
    final rows = safe.isEmpty ? 1 : safe.length;
    final columns = safe.fold<int>(0, (maxColumns, row) => math.max(maxColumns, row.length)).clamp(1, 26).toInt();
    final normalized = List<List<String>>.generate(
      rows,
      (row) => List<String>.generate(
        columns,
        (column) => row < safe.length && column < safe[row].length ? safe[row][column] : '',
      ),
    );
    _ownedUpdateBlockMetadata(
      textController: widget.textController,
      blockId: widget.block.id,
      metadataPatch: <String, Object?>{
        'rows': rows,
        'columns': columns,
        'cells': [for (final row in normalized) [for (final cell in row) cell]],
      },
      label: label,
    );
  }

  void _resizeTable({int? nextRows, int? nextColumns, String label = 'Resize table'}) {
    final cells = _cells;
    final targetRows = (nextRows ?? _rows).clamp(1, 99).toInt();
    final targetColumns = (nextColumns ?? _columns).clamp(1, 26).toInt();
    final resized = List<List<String>>.generate(
      targetRows,
      (row) => List<String>.generate(
        targetColumns,
        (column) => row < cells.length && column < cells[row].length ? cells[row][column] : '',
      ),
    );
    _replaceCells(resized, label: label);
  }

  void _insertRowBelow() {
    final cells = _cells.map((row) => row.toList()).toList();
    final insertAt = (_selectedRow + 1).clamp(0, cells.length).toInt();
    cells.insert(insertAt, List<String>.filled(_columns, ''));
    _replaceCells(cells, label: 'Insert table row');
    _selectCell(insertAt, _selectedColumn);
  }

  void _insertColumnRight() {
    final cells = _cells.map((row) => row.toList()).toList();
    final insertAt = (_selectedColumn + 1).clamp(0, _columns).toInt();
    for (final row in cells) {
      row.insert(insertAt, '');
    }
    _replaceCells(cells, label: 'Insert table column');
    _selectCell(_selectedRow, insertAt);
  }

  void _deleteSelectedRow() {
    if (_rows <= 1) return;
    final cells = _cells.map((row) => row.toList()).toList()..removeAt(_selectedRow);
    final nextSelected = _selectedRow.clamp(0, math.max(0, cells.length - 1)).toInt();
    _replaceCells(cells, label: 'Delete table row');
    _selectCell(nextSelected, _selectedColumn);
  }

  void _deleteSelectedColumn() {
    if (_columns <= 1) return;
    final cells = _cells.map((row) => row.toList()).toList();
    for (final row in cells) {
      if (_selectedColumn < row.length) row.removeAt(_selectedColumn);
    }
    final nextSelected = _selectedColumn.clamp(0, math.max(0, _columns - 2)).toInt();
    _replaceCells(cells, label: 'Delete table column');
    _selectCell(_selectedRow, nextSelected);
  }

  Future<void> _pasteSpreadsheetData() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.trim().isEmpty) return;
    final pasted = _ownedParseTableCells(text);
    if (pasted.isEmpty) return;
    final cells = _cells.map((row) => row.toList()).toList();
    final requiredRows = math.max(_rows, _selectedRow + pasted.length);
    final requiredColumns = math.max(_columns, _selectedColumn + pasted.fold<int>(0, (maxColumns, row) => math.max(maxColumns, row.length)));
    while (cells.length < requiredRows) {
      cells.add(List<String>.filled(_columns, ''));
    }
    for (final row in cells) {
      while (row.length < requiredColumns) row.add('');
    }
    for (var r = 0; r < pasted.length; r++) {
      for (var c = 0; c < pasted[r].length; c++) {
        cells[_selectedRow + r][_selectedColumn + c] = pasted[r][c];
      }
    }
    _replaceCells(cells, label: 'Paste spreadsheet data');
  }

  Widget _toolbarButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rows = _rows;
    final columns = _columns;
    final cells = _cells;
    final selectedAddress = '${_columnName(_selectedColumn)}${_selectedRow + 1}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 54,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
                  ),
                  child: Text(
                    selectedAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$rows × $columns',
                  style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                _toolbarButton(tooltip: 'Paste spreadsheet data', icon: Icons.content_paste_go_outlined, onPressed: () => _pasteSpreadsheetData()),
                _toolbarButton(tooltip: 'Insert row below', icon: Icons.table_rows_outlined, onPressed: _insertRowBelow),
                _toolbarButton(tooltip: 'Insert column right', icon: Icons.view_column_outlined, onPressed: _insertColumnRight),
                _toolbarButton(tooltip: 'Delete selected row', icon: Icons.delete_sweep_outlined, onPressed: rows > 1 ? _deleteSelectedRow : null),
                _toolbarButton(tooltip: 'Delete selected column', icon: Icons.remove_circle_outline, onPressed: columns > 1 ? _deleteSelectedColumn : null),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: _OwnedSpreadsheetTable(
                  textController: widget.textController,
                  block: widget.block,
                  rows: rows,
                  columns: columns,
                  headerRows: _headerRows,
                  cells: cells,
                  selectedRow: _selectedRow,
                  selectedColumn: _selectedColumn,
                  onCellSelected: _selectCell,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _columnName(int index) {
    var n = index + 1;
    final buffer = StringBuffer();
    while (n > 0) {
      n -= 1;
      buffer.writeCharCode(65 + (n % 26));
      n ~/= 26;
    }
    return buffer.toString().split('').reversed.join();
  }
}

class _OwnedSpreadsheetTable extends StatelessWidget {
  const _OwnedSpreadsheetTable({
    required this.textController,
    required this.block,
    required this.rows,
    required this.columns,
    required this.headerRows,
    required this.cells,
    required this.selectedRow,
    required this.selectedColumn,
    required this.onCellSelected,
  });

  final TextSystemController textController;
  final TextSystemBlock block;
  final int rows;
  final int columns;
  final int headerRows;
  final List<List<String>> cells;
  final int selectedRow;
  final int selectedColumn;
  final void Function(int row, int column) onCellSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Table(
      defaultColumnWidth: const FixedColumnWidth(104),
      border: TableBorder.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.85),
        width: 0.8,
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.50)),
          children: [
            _OwnedSpreadsheetAxisHeader(label: ''),
            for (var c = 0; c < columns; c++)
              _OwnedSpreadsheetAxisHeader(label: _OwnedDocumentTableSurfaceState._columnName(c)),
          ],
        ),
        for (var r = 0; r < rows; r++)
          TableRow(
            decoration: BoxDecoration(
              color: r < headerRows ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.28) : Colors.transparent,
            ),
            children: [
              _OwnedSpreadsheetAxisHeader(label: '${r + 1}'),
              for (var c = 0; c < columns; c++)
                _OwnedSpreadsheetCell(
                  textController: textController,
                  blockId: block.id,
                  row: r,
                  column: c,
                  rows: rows,
                  columns: columns,
                  value: c < cells[r].length ? cells[r][c] : '',
                  selected: r == selectedRow && c == selectedColumn,
                  header: r < headerRows,
                  onSelected: () => onCellSelected(r, c),
                ),
            ],
          ),
      ],
    );
  }
}

class _OwnedSpreadsheetAxisHeader extends StatelessWidget {
  const _OwnedSpreadsheetAxisHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      height: 28,
      child: Center(
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OwnedSpreadsheetCell extends StatefulWidget {
  const _OwnedSpreadsheetCell({
    required this.textController,
    required this.blockId,
    required this.row,
    required this.column,
    required this.rows,
    required this.columns,
    required this.value,
    required this.selected,
    required this.header,
    required this.onSelected,
  });

  final TextSystemController textController;
  final String blockId;
  final int row;
  final int column;
  final int rows;
  final int columns;
  final String value;
  final bool selected;
  final bool header;
  final VoidCallback onSelected;

  @override
  State<_OwnedSpreadsheetCell> createState() => _OwnedSpreadsheetCellState();
}

class _OwnedSpreadsheetCellState extends State<_OwnedSpreadsheetCell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode(debugLabel: 'OwnedSpreadsheetCell');
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _OwnedSpreadsheetCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _commit();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      widget.onSelected();
    } else {
      _commit();
    }
  }

  void _commit() {
    final block = widget.textController.document.blockById(widget.blockId);
    if (block == null) return;
    final cells = _ownedTableCells(block, rows: widget.rows, columns: widget.columns);
    if (widget.row >= cells.length || widget.column >= cells[widget.row].length) return;
    if (cells[widget.row][widget.column] == _controller.text) return;
    cells[widget.row][widget.column] = _controller.text;
    _ownedUpdateBlockMetadata(
      textController: widget.textController,
      blockId: widget.blockId,
      metadataPatch: <String, Object?>{
        'cells': [for (final row in cells) [for (final cell in row) cell]],
      },
      label: 'Edit table cell',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = widget.selected ? colorScheme.primary : Colors.transparent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.selected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        border: Border.all(color: borderColor, width: widget.selected ? 1.8 : 0),
      ),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: 1,
          textInputAction: TextInputAction.next,
          onTap: widget.onSelected,
          onSubmitted: (_) => _commit(),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: widget.header ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _OwnedEquationBlockPreview extends StatelessWidget {
  const _OwnedEquationBlockPreview({
    required this.document,
    required this.block,
  });

  final TextSystemDocument document;
  final TextSystemBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final latex = _ownedEquationLatex(block);
    final numbered = _ownedEquationIsNumbered(block);
    final ordinal = _ownedEquationOrdinal(document, block);
    final note = _ownedObjectNote(block);
    final expression = latex.isEmpty ? r'E = mc^2' : latex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 42),
                      child: Math.tex(
                        expression,
                        mathStyle: MathStyle.display,
                        textStyle: theme.textTheme.titleMedium?.copyWith(
                          color: latex.isEmpty
                              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.72)
                              : colorScheme.onSurface,
                          height: 1.35,
                        ),
                        onErrorFallback: (_) => Text(
                          expression,
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
                if (numbered)
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
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Note. $note',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnedGenericObjectBlockPreview extends StatelessWidget {
  const _OwnedGenericObjectBlockPreview({required this.block});

  final TextSystemBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = _ownedObjectCaption(block).isNotEmpty ? _ownedObjectCaption(block) : block.text.trim();
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            subtitle.isEmpty ? 'Object' : subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

void _ownedUpdateBlockMetadata({
  required TextSystemController textController,
  required String blockId,
  required Map<String, Object?> metadataPatch,
  required String label,
}) {
  final document = textController.document;
  final index = document.blocks.indexWhere((block) => block.id == blockId);
  if (index < 0) return;
  final current = document.blocks[index];
  final nextMetadata = Map<String, Object?>.unmodifiable(<String, Object?>{
    ...current.metadata,
    ...metadataPatch,
  });
  final nextBlocks = List<TextSystemBlock>.from(document.blocks);
  nextBlocks[index] = current.copyWith(metadata: nextMetadata);
  textController.replaceDocument(
    document.copyWith(
      blocks: List<TextSystemBlock>.unmodifiable(nextBlocks),
      updatedAt: DateTime.now(),
    ),
    label: label,
  );
}

String _ownedObjectCaption(TextSystemBlock block) {
  final caption = (block.metadata['caption'] as String?)?.trim();
  if (caption != null && caption.isNotEmpty) return caption;
  return block.text.trim();
}

String _ownedObjectLabel(TextSystemBlock block) {
  final label = (block.metadata['label'] as String?)?.trim();
  return label ?? '';
}

String _ownedObjectSource(TextSystemBlock block) {
  final source = (block.metadata['source'] as String?)?.trim();
  return source ?? '';
}

String _ownedObjectAltText(TextSystemBlock block) {
  final altText = (block.metadata['altText'] as String?)?.trim();
  return altText ?? '';
}

String _ownedObjectImagePath(TextSystemBlock block) {
  final imagePath = (block.metadata['imagePath'] as String?)?.trim();
  return imagePath ?? '';
}

String _ownedObjectNote(TextSystemBlock block) {
  final note = (block.metadata['note'] as String?)?.trim();
  return note ?? '';
}

String _ownedFigureSizeForBlock(TextSystemBlock block) {
  final size = block.metadata['figureSize'];
  if (size is String && const ['small', 'medium', 'large', 'fullWidth'].contains(size)) return size;
  return 'medium';
}

String _ownedEquationLatex(TextSystemBlock block) {
  final latex = block.metadata['latex'];
  final raw = latex is String && latex.trim().isNotEmpty ? latex.trim() : block.text.trim();
  return _ownedDisplayEquationSourceFromRaw(raw);
}

String _ownedDisplayEquationSource(TextSystemBlock block) {
  final text = block.text.trim();
  if (text.isNotEmpty) return _ownedDisplayEquationSourceFromRaw(text);
  final latex = block.metadata['latex'];
  if (latex is String && latex.trim().isNotEmpty) return _ownedDisplayEquationSourceFromRaw(latex.trim());
  return '';
}

String _ownedDisplayEquationSourceFromRaw(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith(r'\(') && trimmed.endsWith(r'\)') && trimmed.length >= 4) {
    return trimmed.substring(2, trimmed.length - 2).trim();
  }
  if (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]') && trimmed.length >= 4) {
    return trimmed.substring(2, trimmed.length - 2).trim();
  }
  if (trimmed.startsWith(r'$$') && trimmed.endsWith(r'$$') && trimmed.length >= 4) {
    return trimmed.substring(2, trimmed.length - 2).trim();
  }
  return trimmed;
}

bool _ownedEquationIsNumbered(TextSystemBlock block) {
  final presentation = block.metadata['presentation'] ?? block.metadata['equationPresentation'];
  return block.metadata['numbered'] == true || presentation == 'numbered';
}

int _ownedAcademicObjectOrdinal(TextSystemDocument document, TextSystemBlock block, {required String kind}) {
  var count = 0;
  for (final candidate in document.blocks) {
    if (candidate.type == TextSystemBlockType.custom && candidate.metadata['kind'] == kind) {
      count += 1;
    }
    if (candidate.id == block.id) return math.max(1, count);
  }
  return math.max(1, count);
}

bool _ownedIsEquationBlock(TextSystemBlock block) {
  final kind = block.metadata['kind'];
  return kind == 'displayEquation' || kind == 'equation';
}

int _ownedEquationOrdinal(TextSystemDocument document, TextSystemBlock block) {
  var count = 0;
  for (final candidate in document.blocks) {
    if (_ownedIsEquationBlock(candidate) && _ownedEquationIsNumbered(candidate)) {
      count += 1;
    }
    if (candidate.id == block.id) return math.max(1, count);
  }
  return math.max(1, count);
}

String _ownedEquationNumberLabel(TextSystemDocument document, TextSystemBlock block) {
  return '(${_ownedEquationOrdinal(document, block)})';
}

String _ownedEquationReferenceText(TextSystemDocument document, TextSystemBlock block) {
  if (_ownedEquationIsNumbered(block)) {
    return 'Equation ${_ownedEquationNumberLabel(document, block)}';
  }
  final label = _ownedObjectLabel(block);
  return label.isNotEmpty ? 'Equation $label' : 'Equation';
}

String _ownedFileName(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) return '';
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? normalized : parts.last;
}

bool _ownedLocalImageExists(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  try {
    return File(trimmed).existsSync();
  } catch (_) {
    return false;
  }
}

Future<Map<String, Object?>> _ownedImageMetadataForLocalPath(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return const <String, Object?>{};
  try {
    final file = File(trimmed);
    if (!file.existsSync()) return const <String, Object?>{};
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return const <String, Object?>{};
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) {
      image.dispose();
      return const <String, Object?>{};
    }

    final metadata = <String, Object?>{
      'imageWidth': width,
      'imageHeight': height,
      'imageAspectRatio': width / height,
    };

    final rawPixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (rawPixels != null) {
      final data = rawPixels.buffer.asUint8List();
      var minX = width;
      var minY = height;
      var maxX = -1;
      var maxY = -1;
      for (var y = 0; y < height; y++) {
        final rowOffset = y * width * 4;
        for (var x = 0; x < width; x++) {
          final alpha = data[rowOffset + x * 4 + 3];
          if (alpha <= 8) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      if (maxX >= minX && maxY >= minY) {
        metadata.addAll(<String, Object?>{
          'imageVisibleLeft': minX / width,
          'imageVisibleTop': minY / height,
          'imageVisibleRight': (maxX + 1) / width,
          'imageVisibleBottom': (maxY + 1) / height,
        });
      }
    }
    metadata.putIfAbsent('imageVisibleLeft', () => 0.0);
    metadata.putIfAbsent('imageVisibleTop', () => 0.0);
    metadata.putIfAbsent('imageVisibleRight', () => 1.0);
    metadata.putIfAbsent('imageVisibleBottom', () => 1.0);

    return metadata;
  } catch (_) {
    return const <String, Object?>{};
  }
}

int _ownedTableRows(TextSystemBlock block) {
  final rawRows = block.metadata['rows'];
  return rawRows is num ? rawRows.clamp(1, 50).toInt() : 3;
}

int _ownedTableColumns(TextSystemBlock block) {
  final rawColumns = block.metadata['columns'];
  return rawColumns is num ? rawColumns.clamp(1, 26).toInt() : 3;
}

int _ownedTableHeaderRows(TextSystemBlock block) {
  final rawHeaderRows = block.metadata['headerRows'];
  return rawHeaderRows is num ? rawHeaderRows.clamp(0, 3).toInt() : 1;
}

List<List<String>> _ownedTableCells(
  TextSystemBlock block, {
  required int rows,
  required int columns,
}) {
  final rawCells = block.metadata['cells'];
  final result = <List<String>>[];
  if (rawCells is List) {
    for (final row in rawCells.take(rows)) {
      if (row is List) {
        final values = row.take(columns).map((cell) => cell?.toString() ?? '').toList(growable: true);
        while (values.length < columns) values.add('');
        result.add(values);
      }
    }
  }
  while (result.length < rows) {
    result.add(List<String>.filled(columns, ''));
  }
  return result;
}


@immutable
class _OwnedAcademicFigureDraft {
  const _OwnedAcademicFigureDraft({
    required this.caption,
    required this.label,
    required this.source,
    required this.altText,
    required this.imagePath,
    required this.size,
  });

  final String caption;
  final String label;
  final String source;
  final String altText;
  final String imagePath;
  final String size;
}

@immutable
class _OwnedAcademicTableDraft {
  const _OwnedAcademicTableDraft({
    required this.caption,
    required this.label,
    required this.cells,
    required this.note,
    required this.headerRows,
  });

  final String caption;
  final String label;
  final List<List<String>> cells;
  final String note;
  final int headerRows;
}

@immutable
class _OwnedAcademicEquationDraft {
  const _OwnedAcademicEquationDraft({
    required this.latex,
    required this.label,
    required this.note,
    required this.numbered,
  });

  final String latex;
  final String label;
  final String note;
  final bool numbered;
}

Future<_OwnedAcademicFigureDraft?> _showOwnedAcademicFigureDraftDialog({
  required BuildContext context,
  required TextSystemDocument document,
}) {
  return showDialog<_OwnedAcademicFigureDraft>(
    context: context,
    builder: (context) => _OwnedAcademicFigureDraftDialog(document: document),
  );
}

Future<_OwnedAcademicTableDraft?> _showOwnedAcademicTableDraftDialog({
  required BuildContext context,
  required TextSystemDocument document,
}) {
  return showDialog<_OwnedAcademicTableDraft>(
    context: context,
    builder: (context) => _OwnedAcademicTableDraftDialog(document: document),
  );
}

Future<_OwnedAcademicEquationDraft?> _showOwnedAcademicEquationDraftDialog({
  required BuildContext context,
  required TextSystemDocument document,
}) {
  return showDialog<_OwnedAcademicEquationDraft>(
    context: context,
    builder: (context) => _OwnedAcademicEquationDraftDialog(document: document),
  );
}

TextSystemBlock _ownedAcademicFigureBlockFromDraft(_OwnedAcademicFigureDraft draft, {String? id}) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final caption = draft.caption.trim();
  final size = const ['small', 'medium', 'large', 'fullWidth'].contains(draft.size) ? draft.size : 'medium';
  return TextSystemBlock(
    id: id ?? 'figure-$now',
    type: TextSystemBlockType.custom,
    text: caption,
    metadata: <String, Object?>{
      'kind': 'figure',
      'styleId': TextSystemDocumentStyleSheet.custom,
      'caption': caption,
      'figureSize': size,
      'captionPosition': 'apa',
      if (draft.label.trim().isNotEmpty) 'label': draft.label.trim(),
      if (draft.source.trim().isNotEmpty) 'source': draft.source.trim(),
      if (draft.altText.trim().isNotEmpty) 'altText': draft.altText.trim(),
      if (draft.imagePath.trim().isNotEmpty) 'imagePath': draft.imagePath.trim(),
    },
  );
}

TextSystemBlock _ownedAcademicTableBlockFromDraft(_OwnedAcademicTableDraft draft, {String? id}) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final cells = _ownedNormalizeTableCells(draft.cells);
  final safeCells = cells.isEmpty ? List<List<String>>.generate(3, (_) => List<String>.filled(3, '')) : cells;
  final columns = safeCells.fold<int>(0, (maxColumns, row) => math.max(maxColumns, row.length));
  final caption = draft.caption.trim();
  return TextSystemBlock(
    id: id ?? 'table-$now',
    type: TextSystemBlockType.custom,
    text: caption,
    metadata: <String, Object?>{
      'kind': 'table',
      'styleId': TextSystemDocumentStyleSheet.custom,
      'caption': caption,
      'rows': safeCells.length,
      'columns': columns,
      'cells': [for (final row in safeCells) [for (final cell in row) cell]],
      'headerRows': draft.headerRows.clamp(0, 3).toInt(),
      'captionPosition': 'apa',
      if (draft.label.trim().isNotEmpty) 'label': draft.label.trim(),
      if (draft.note.trim().isNotEmpty) 'note': draft.note.trim(),
    },
  );
}

TextSystemBlock _ownedAcademicEquationBlockFromDraft(_OwnedAcademicEquationDraft draft, {String? id}) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final latex = draft.latex.trim().isEmpty ? r'E = mc^2' : draft.latex.trim();
  final sourceText = _ownedDisplayEquationSourceText(latex);
  return TextSystemBlock(
    id: id ?? 'equation-$now',
    type: TextSystemBlockType.paragraph,
    text: sourceText,
    metadata: <String, Object?>{
      'kind': 'displayEquation',
      'styleId': TextSystemDocumentStyleSheet.paragraph,
      'latex': latex,
      'numbered': draft.numbered,
      'presentation': draft.numbered ? 'numbered' : 'display',
      if (draft.label.trim().isNotEmpty) 'label': draft.label.trim(),
      if (draft.note.trim().isNotEmpty) 'note': draft.note.trim(),
    },
  );
}

String _ownedDisplayEquationSourceText(String latex) {
  final trimmed = latex.trim();
  if (trimmed.isEmpty) return r'\[\]';
  if (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]') && trimmed.length >= 4) {
    return trimmed;
  }
  if (trimmed.startsWith(r'$$') && trimmed.endsWith(r'$$') && trimmed.length >= 4) {
    return trimmed;
  }
  if (trimmed.startsWith(r'\(') && trimmed.endsWith(r'\)') && trimmed.length >= 4) {
    final inner = trimmed.substring(2, trimmed.length - 2).trim();
    return '\\[$inner\\]';
  }
  return '\\[$trimmed\\]';
}

int _ownedDisplayEquationInnerSourceStart(String text) {
  final trimmedLeft = text.length - text.trimLeft().length;
  final value = text.trimLeft();
  if (value.startsWith(r'\[') || value.startsWith(r'\(') || value.startsWith(r'$$')) {
    return trimmedLeft + 2;
  }
  return trimmedLeft;
}

int _ownedDisplayEquationInnerSourceEnd(String text) {
  final trimmedRight = text.trimRight();
  final trailing = text.length - trimmedRight.length;
  if (trimmedRight.endsWith(r'\]') || trimmedRight.endsWith(r'\)') || trimmedRight.endsWith(r'$$')) {
    return math.max(0, text.length - trailing - 2);
  }
  return text.length - trailing;
}

List<List<String>> _ownedNormalizeTableCells(List<List<String>> cells) {
  if (cells.isEmpty) return const <List<String>>[];
  final safeRows = cells.take(50).toList(growable: false);
  final columnCount = safeRows.fold<int>(0, (maxColumns, row) => math.max(maxColumns, row.length)).clamp(1, 26).toInt();
  return [
    for (final row in safeRows)
      [
        for (var i = 0; i < columnCount; i++)
          i < row.length ? row[i].trim() : '',
      ],
  ];
}

List<List<String>> _ownedParseTableCells(String raw) {
  final lines = raw
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    return List<List<String>>.generate(3, (_) => List<String>.filled(3, ''));
  }
  final parsed = <List<String>>[];
  for (final line in lines) {
    final separator = line.contains('\t')
        ? '\t'
        : line.contains(';')
            ? ';'
            : ',';
    parsed.add(line.split(separator).map((cell) => cell.trim()).toList());
  }
  return _ownedNormalizeTableCells(parsed);
}

String _ownedSerializeTableCells(List<List<String>> cells) {
  return cells.map((row) => row.join('\t')).join('\n');
}

int _ownedNextObjectOrdinal(TextSystemDocument document, String kind) {
  if (kind == 'equation') {
    return document.blocks.where(_ownedIsEquationBlock).length + 1;
  }
  return document.blocks.where((block) => block.type == TextSystemBlockType.custom && block.metadata['kind'] == kind).length + 1;
}

String _ownedAcademicLabelSuggestion({
  required TextSystemDocument document,
  required String kind,
  required String fallback,
  required String value,
}) {
  final prefix = switch (kind) {
    'table' => 'tab',
    'equation' => 'eq',
    _ => 'fig',
  };
  final base = _ownedSlug(value, fallback: fallback);
  var candidate = '$prefix:$base';
  var suffix = 2;
  while (_ownedDocumentHasLabel(document, candidate)) {
    candidate = '$prefix:$base-$suffix';
    suffix += 1;
  }
  return candidate;
}

bool _ownedDocumentHasLabel(TextSystemDocument document, String label) {
  final normalized = label.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  for (final block in document.blocks) {
    final candidate = _ownedObjectLabel(block).toLowerCase();
    if (candidate == normalized) return true;
  }
  return false;
}

String _ownedSlug(String value, {required String fallback}) {
  final trimmed = value.trim().toLowerCase();
  final slug = trimmed
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? fallback : slug;
}

class _OwnedAcademicFigureDraftDialog extends StatefulWidget {
  const _OwnedAcademicFigureDraftDialog({required this.document});

  final TextSystemDocument document;

  @override
  State<_OwnedAcademicFigureDraftDialog> createState() => _OwnedAcademicFigureDraftDialogState();
}

class _OwnedAcademicFigureDraftDialogState extends State<_OwnedAcademicFigureDraftDialog> {
  late final TextEditingController _captionController;
  late final TextEditingController _labelController;
  late final TextEditingController _sourceController;
  late final TextEditingController _altTextController;
  var _imagePath = '';
  var _size = 'medium';

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController();
    _labelController = TextEditingController();
    _sourceController = TextEditingController();
    _altTextController = TextEditingController();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _labelController.dispose();
    _sourceController.dispose();
    _altTextController.dispose();
    super.dispose();
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

  void _suggestLabel() {
    _labelController.text = _ownedAcademicLabelSuggestion(
      document: widget.document,
      kind: 'figure',
      fallback: "figure-${_ownedNextObjectOrdinal(widget.document, 'figure')}",
      value: _captionController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageName = _ownedFileName(_imagePath);
    final hasImage = _ownedLocalImageExists(_imagePath);
    return AlertDialog(
      title: const Text('Insert figure'),
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
                  labelText: 'Figure title / caption',
                  hintText: 'Short academic figure description',
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        height: 74,
                        child: hasImage
                            ? Image.file(File(_imagePath), fit: BoxFit.contain)
                            : const _OwnedFigureEmptyPreview(label: 'No image'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              hasImage ? imageName : 'Import image',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Stores the local image path in the figure metadata.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: _pickImage,
                                  icon: const Icon(Icons.image_outlined, size: 18),
                                  label: Text(hasImage ? 'Change image' : 'Choose image'),
                                ),
                                if (_imagePath.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () => setState(() => _imagePath = ''),
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
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'fig:mechanism',
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
              DropdownButtonFormField<String>(
                value: _size,
                decoration: const InputDecoration(labelText: 'Figure size'),
                items: const [
                  DropdownMenuItem(value: 'small', child: Text('Small')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'large', child: Text('Large')),
                  DropdownMenuItem(value: 'fullWidth', child: Text('Full width')),
                ],
                onChanged: (value) => setState(() => _size = value ?? _size),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sourceController,
                decoration: const InputDecoration(
                  labelText: 'Source / URL',
                  hintText: 'Optional source note or image URL',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _altTextController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Alt text / note',
                  hintText: 'Optional accessibility/export description',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _OwnedAcademicFigureDraft(
                caption: _captionController.text,
                label: _labelController.text,
                source: _sourceController.text,
                altText: _altTextController.text,
                imagePath: _imagePath,
                size: _size,
              ),
            );
          },
          child: const Text('Insert figure'),
        ),
      ],
    );
  }
}

class _OwnedAcademicTableDraftDialog extends StatefulWidget {
  const _OwnedAcademicTableDraftDialog({required this.document});

  final TextSystemDocument document;

  @override
  State<_OwnedAcademicTableDraftDialog> createState() => _OwnedAcademicTableDraftDialogState();
}

class _OwnedAcademicTableDraftDialogState extends State<_OwnedAcademicTableDraftDialog> {
  late final TextEditingController _captionController;
  late final TextEditingController _labelController;
  late final TextEditingController _cellsController;
  late final TextEditingController _noteController;
  var _headerRows = 1;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController();
    _labelController = TextEditingController();
    _cellsController = TextEditingController(
      text: _ownedSerializeTableCells(List<List<String>>.generate(3, (_) => List<String>.filled(3, ''))),
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _labelController.dispose();
    _cellsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _suggestLabel() {
    _labelController.text = _ownedAcademicLabelSuggestion(
      document: widget.document,
      kind: 'table',
      fallback: "table-${_ownedNextObjectOrdinal(widget.document, 'table')}",
      value: _captionController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insert table'),
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
                  labelText: 'Table title / caption',
                  hintText: 'Short academic table description',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'tab:summary',
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
              DropdownButtonFormField<int>(
                value: _headerRows,
                decoration: const InputDecoration(labelText: 'Header rows'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('No header row')),
                  DropdownMenuItem(value: 1, child: Text('First row is header')),
                  DropdownMenuItem(value: 2, child: Text('First two rows are headers')),
                ],
                onChanged: (value) => setState(() => _headerRows = value ?? _headerRows),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cellsController,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Cells',
                  hintText: 'Paste tab-, comma-, or semicolon-separated data. One row per line.',
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional table note/source',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _OwnedAcademicTableDraft(
                caption: _captionController.text,
                label: _labelController.text,
                cells: _ownedParseTableCells(_cellsController.text),
                note: _noteController.text,
                headerRows: _headerRows,
              ),
            );
          },
          child: const Text('Insert table'),
        ),
      ],
    );
  }
}

class _OwnedAcademicEquationDraftDialog extends StatefulWidget {
  const _OwnedAcademicEquationDraftDialog({required this.document});

  final TextSystemDocument document;

  @override
  State<_OwnedAcademicEquationDraftDialog> createState() => _OwnedAcademicEquationDraftDialogState();
}

class _OwnedAcademicEquationDraftDialogState extends State<_OwnedAcademicEquationDraftDialog> {
  late final TextEditingController _latexController;
  late final TextEditingController _labelController;
  late final TextEditingController _noteController;
  var _numbered = false;

  @override
  void initState() {
    super.initState();
    _latexController = TextEditingController(text: r'E = mc^2')..addListener(_handleLatexChanged);
    _labelController = TextEditingController();
    _noteController = TextEditingController();
  }

  void _handleLatexChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _latexController.removeListener(_handleLatexChanged);
    _latexController.dispose();
    _labelController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _suggestLabel() {
    _labelController.text = _ownedAcademicLabelSuggestion(
      document: widget.document,
      kind: 'equation',
      fallback: "equation-${_ownedNextObjectOrdinal(widget.document, 'equation')}",
      value: _latexController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AlertDialog(
      title: const Text('Insert display equation'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _latexController,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'LaTeX equation',
                  hintText: r'\frac{a}{b} = c',
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: Math.tex(
                      _latexController.text.trim().isEmpty ? r'E = mc^2' : _latexController.text.trim(),
                      mathStyle: MathStyle.display,
                      textStyle: theme.textTheme.titleMedium,
                      onErrorFallback: (_) => Text(
                        _latexController.text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.error,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _numbered,
                onChanged: (value) => setState(() => _numbered = value ?? false),
                title: const Text('Number this equation'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _labelController,
                      enabled: _numbered,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'eq:model',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _numbered ? _suggestLabel : null,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: const Text('Suggest'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional equation note',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _OwnedAcademicEquationDraft(
                latex: _latexController.text,
                label: _numbered ? _labelController.text : '',
                note: _noteController.text,
                numbered: _numbered,
              ),
            );
          },
          child: const Text('Insert equation'),
        ),
      ],
    );
  }
}

class _OwnedStructuralBreakPreview extends StatelessWidget {
  const _OwnedStructuralBreakPreview({required this.block});

  final TextSystemBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSection = _isSectionBreakBlock(block);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.22)),
        ),
        child: Text(
          isSection ? 'Section break' : 'Page break',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OwnedFootnotePreview extends StatelessWidget {
  const _OwnedFootnotePreview({
    required this.footnotes,
    required this.textController,
  });

  final List<TextSystemPagedFootnote> footnotes;
  final TextSystemController textController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.96),
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.72))),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final footnote in footnotes.take(4))
              _OwnedEditableFootnoteLine(
                key: ValueKey<String>('owned-footnote-${footnote.blockId}'),
                footnote: footnote,
                textController: textController,
              ),
            if (footnotes.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+${footnotes.length - 4} more footnotes',
                  style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OwnedEditableFootnoteLine extends StatefulWidget {
  const _OwnedEditableFootnoteLine({
    super.key,
    required this.footnote,
    required this.textController,
  });

  final TextSystemPagedFootnote footnote;
  final TextSystemController textController;

  @override
  State<_OwnedEditableFootnoteLine> createState() => _OwnedEditableFootnoteLineState();
}

class _OwnedEditableFootnoteLineState extends State<_OwnedEditableFootnoteLine> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.footnote.text);
    _focusNode = FocusNode(debugLabel: 'OwnedFootnoteEditor');
  }

  @override
  void didUpdateWidget(covariant _OwnedEditableFootnoteLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.footnote.blockId != widget.footnote.blockId) {
      _controller.text = widget.footnote.text;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      return;
    }
    if (!_focusNode.hasFocus && _controller.text != widget.footnote.text) {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontSize: 10,
      height: 1.18,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${widget.footnote.number}.',
                textAlign: TextAlign.right,
                style: style?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              style: style,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Footnote text',
                hintStyle: style?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.48)),
                contentPadding: const EdgeInsets.symmetric(vertical: 2),
              ),
              onChanged: (value) => widget.textController.updateBlockText(widget.footnote.blockId, value),
            ),
          ),
        ],
      ),
    );
  }
}

class _OwnedDocumentLayoutSnapshotBuilder {
  const _OwnedDocumentLayoutSnapshotBuilder._();

  static TextSystemEditorLayoutSnapshot build({
    required TextSystemDocument document,
    required TextSystemPagedBlockLayout layout,
    required double pageWidth,
    required double pageHeight,
    required double pageOuterHeight,
    required double pageGap,
    required EdgeInsets margins,
    required int revision,
  }) {
    final builder = TextSystemDocumentLayoutIndexBuilder(documentId: document.id);
    final stride = pageOuterHeight + pageGap;
    for (var pageIndex = 0; pageIndex < layout.pages.length; pageIndex++) {
      final page = layout.pages[pageIndex];
      final pageTop = pageIndex * stride + TextSystemOwnedDocumentEditorSurface._pageHeaderHeight + TextSystemOwnedDocumentEditorSurface._pageHeaderGap;
      final pageRect = Rect.fromLTWH(0, pageTop, pageWidth, pageHeight);
      builder.registerPage(
        pageIndex: pageIndex,
        globalRect: pageRect,
        metadata: <String, Object?>{
          'physicalPageNumber': page.pageNumber,
          'displayPageNumber': page.displayPageNumber,
        },
      );
      final contentOrigin = Offset(margins.left, pageTop + margins.top);
      for (final fragment in page.fragments) {
        final globalRect = fragment.rect.shift(contentOrigin);
        final kind = _layoutKindForFragment(document, fragment);
        if (kind == TextSystemDocumentLayoutFragmentKind.textRun) {
          builder.registerTextFragment(
            fragmentId: 'p$pageIndex:${fragment.blockId}:${fragment.visualTextStartOffset}:${fragment.visualTextEndOffset}',
            blockId: fragment.blockId,
            blockIndex: fragment.blockIndex,
            pageIndex: pageIndex,
            globalRect: globalRect,
            startOffset: fragment.visualTextStartOffset,
            endOffset: fragment.visualTextEndOffset,
            metadata: <String, Object?>{
              'blockType': fragment.blockType.name,
              'continuesFromPreviousPage': fragment.continuesFromPreviousPage,
              'continuesOnNextPage': fragment.continuesOnNextPage,
              'ownedPreview': true,
            },
          );
        } else {
          builder.registerObjectFragment(
            fragmentId: 'p$pageIndex:${fragment.blockId}:object',
            kind: kind,
            blockId: fragment.blockId,
            blockIndex: fragment.blockIndex,
            pageIndex: pageIndex,
            globalRect: globalRect,
            metadata: <String, Object?>{
              'blockType': fragment.blockType.name,
              'ownedPreview': true,
            },
          );
        }
      }
    }

    return TextSystemEditorLayoutSnapshot(
      document: document,
      layoutIndex: builder.build(),
      revision: revision,
      surfaceSize: Size(pageWidth, layout.pages.length * stride),
    );
  }

  static TextSystemDocumentLayoutFragmentKind _layoutKindForFragment(
    TextSystemDocument document,
    TextSystemPagedBlockFragment fragment,
  ) {
    if (fragment.blockType == TextSystemBlockType.divider) {
      final block = _blockForFragment(document, fragment);
      if (block?.metadata['kind'] == 'sectionBreak' || fragment.text == 'Section break') {
        return TextSystemDocumentLayoutFragmentKind.sectionBreak;
      }
      return TextSystemDocumentLayoutFragmentKind.pageBreak;
    }
    if (fragment.blockType == TextSystemBlockType.custom) {
      final block = _blockForFragment(document, fragment);
      final kind = block?.metadata['kind'];
      if (kind == 'equation') return TextSystemDocumentLayoutFragmentKind.textRun;
      if (kind == 'table') return TextSystemDocumentLayoutFragmentKind.table;
      if (kind == 'figure') return TextSystemDocumentLayoutFragmentKind.figure;
      return TextSystemDocumentLayoutFragmentKind.objectBlock;
    }
    return TextSystemDocumentLayoutFragmentKind.textRun;
  }

  static TextSystemBlock? _blockForFragment(
    TextSystemDocument document,
    TextSystemPagedBlockFragment fragment,
  ) {
    if (fragment.blockIndex >= 0 && fragment.blockIndex < document.blocks.length) {
      final candidate = document.blocks[fragment.blockIndex];
      if (candidate.id == fragment.blockId) return candidate;
    }
    return document.blockById(fragment.blockId);
  }
}

TextSystemDocument _documentWithOwnedListIndexes(TextSystemDocument document) {
  var changed = false;
  var orderedCounter = 0;
  String? activeGroupId;
  final blocks = <TextSystemBlock>[];

  for (final block in document.blocks) {
    if (block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true) {
      final rawGroupId = block.metadata['listGroupId'];
      final groupId = rawGroupId is String && rawGroupId.isNotEmpty ? rawGroupId : null;
      final sameGroup = groupId == null ? activeGroupId == null : activeGroupId == groupId;
      orderedCounter = sameGroup ? orderedCounter + 1 : 1;
      activeGroupId = groupId;
      if (block.metadata['index'] == orderedCounter) {
        blocks.add(block);
      } else {
        changed = true;
        blocks.add(block.copyWith(
          metadata: Map<String, Object?>.unmodifiable(<String, Object?>{
            ...block.metadata,
            'index': orderedCounter,
          }),
        ));
      }
      continue;
    }

    orderedCounter = 0;
    activeGroupId = null;
    if (block.type == TextSystemBlockType.listItem && block.metadata.containsKey('index')) {
      changed = true;
      final metadata = Map<String, Object?>.from(block.metadata)..remove('index');
      blocks.add(block.copyWith(metadata: Map<String, Object?>.unmodifiable(metadata)));
    } else {
      blocks.add(block);
    }
  }

  if (!changed) return document;
  return document.copyWith(blocks: List<TextSystemBlock>.unmodifiable(blocks));
}

String _sectionTitleForPage(TextSystemDocument document, TextSystemPagedBlockPage page) {
  if (document.blocks.isEmpty) {
    return document.title.trim().isEmpty ? 'Section' : document.title.trim();
  }
  final firstBlockIndex = page.fragments.isEmpty ? 0 : page.fragments.first.blockIndex;
  for (var i = firstBlockIndex.clamp(0, document.blocks.length - 1).toInt(); i >= 0; i--) {
    final block = document.blocks[i];
    if (block.type == TextSystemBlockType.heading && block.text.trim().isNotEmpty) {
      return block.text.trim();
    }
  }
  return document.title.trim().isEmpty ? 'Section' : document.title.trim();
}

String _objectKindForBlock(TextSystemBlock block) {
  if (_isPageBreakBlock(block)) return 'pageBreak';
  if (_isSectionBreakBlock(block)) return 'sectionBreak';
  final raw = block.metadata['kind'] ??
      block.metadata['objectKind'] ??
      block.metadata['academicObjectKind'] ??
      block.metadata['blockKind'] ??
      block.metadata['type'];
  final kind = raw?.toString().trim();
  if (kind == null || kind.isEmpty) return block.type == TextSystemBlockType.custom ? 'unknownObject' : 'object';
  if (kind == 'displayMath') return 'equation';
  return kind;
}

bool _isObjectBlock(TextSystemBlock block) {
  if (block.type != TextSystemBlockType.custom) return false;
  final kind = _objectKindForBlock(block);
  return kind != 'footnote' && kind != 'bibliography' && kind != 'equation' && kind != 'displayEquation';
}

bool _isOwnedAtomicBlock(TextSystemBlock block) {
  return _isObjectBlock(block) || _isPageBreakBlock(block) || _isSectionBreakBlock(block);
}

bool _isFootnoteBlock(TextSystemBlock block) {
  return block.type == TextSystemBlockType.custom && block.metadata['kind'] == 'footnote';
}

bool _isStructuralBreakBlock(TextSystemBlock block) {
  return _isPageBreakBlock(block) || _isSectionBreakBlock(block);
}

TextSystemDocumentLayoutFragmentKind _layoutKindForBlock(TextSystemBlock block) {
  if (_isPageBreakBlock(block)) return TextSystemDocumentLayoutFragmentKind.pageBreak;
  if (_isSectionBreakBlock(block)) return TextSystemDocumentLayoutFragmentKind.sectionBreak;
  final kind = _objectKindForBlock(block);
  if (kind == 'figure') return TextSystemDocumentLayoutFragmentKind.figure;
  if (kind == 'table') return TextSystemDocumentLayoutFragmentKind.table;
  if (kind == 'equation' || kind == 'displayEquation') return TextSystemDocumentLayoutFragmentKind.textRun;
  return TextSystemDocumentLayoutFragmentKind.objectBlock;
}

bool _isPageBreakBlock(TextSystemBlock block) {
  return block.type == TextSystemBlockType.divider && block.metadata['kind'] == 'pageBreak';
}

bool _isSectionBreakBlock(TextSystemBlock block) {
  return block.type == TextSystemBlockType.divider && block.metadata['kind'] == 'sectionBreak';
}

Future<String?> _showOwnedObjectCommentDialog({
  required BuildContext context,
  required String objectLabel,
}) {
  final textController = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Add object comment'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                objectLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Comment',
                  border: OutlineInputBorder(),
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
          FilledButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: const Text('Add'),
          ),
        ],
      );
    },
  ).whenComplete(textController.dispose);
}

class _OwnedEquationEnvironmentSpan {
  const _OwnedEquationEnvironmentSpan({
    required this.source,
    required this.environment,
    required this.beginStart,
    required this.contentStart,
    required this.contentEnd,
    required this.endEnd,
  });

  final String source;
  final String environment;
  final int beginStart;
  final int contentStart;
  final int contentEnd;
  final int endEnd;

  _OwnedEquationEnvironmentSpan copyWith({int? contentEnd, int? endEnd}) {
    return _OwnedEquationEnvironmentSpan(
      source: source,
      environment: environment,
      beginStart: beginStart,
      contentStart: contentStart,
      contentEnd: contentEnd ?? this.contentEnd,
      endEnd: endEnd ?? this.endEnd,
    );
  }
}

class _OwnedEquationRowSpan {
  const _OwnedEquationRowSpan({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;
}
