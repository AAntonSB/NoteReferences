import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_range.dart';
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
class TextSystemPagedBlockCommandController {
  _TextSystemPagedBlockSurfaceState? _state;

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
  }

  void _detach(_TextSystemPagedBlockSurfaceState state) {
    if (identical(_state, state)) {
      _state = null;
    }
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

  Future<void> runReferenceAction(TextSystemReferenceActionType actionType) async {
    await _state?._createReferenceForActiveSelection(actionType);
  }
}

/// Experimental real-page surface for Phase 14O.
///
/// This surface is intentionally separate from the fluent editor. It renders
/// the same [TextSystemDocument] as block fragments inside physical page content
/// boxes. Phase 14O adds directly editable header and footer zones with
/// layout tokens.
class TextSystemPagedBlockSurface extends StatefulWidget {
  const TextSystemPagedBlockSurface({
    super.key,
    required this.textController,
    required this.document,
    required this.pageSetup,
    required this.pageMaxWidth,
    this.pageFurniture = const TextSystemPageFurniture.defaults(),
    this.onPageFurnitureChanged,
    required this.focusMode,
    this.showMarginGuides = true,
    this.showMarginMarkers = false,
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
  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture>? onPageFurnitureChanged;
  final bool focusMode;
  final bool showMarginGuides;
  final bool showMarginMarkers;
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
  bool _documentSelectionMode = false;
  String? _activeBlockId;
  _PagedEditableBlockFieldState? _activeTextField;
  bool _headerFooterEditMode = false;
  TextSystemHeaderFooterZoneKind? _headerFooterEditTarget;
  Map<String, TextSystemEmbeddedTodoSnapshot> _embeddedTodoSnapshots = const {};
  final Map<String, TextSystemEmbeddedTodoSnapshot> _pendingEmbeddedTodoSync = <String, TextSystemEmbeddedTodoSnapshot>{};
  Timer? _embeddedTodoSyncTimer;

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

    final phase = SchedulerBinding.instance.schedulerPhase;
    final isUnsafeBuildPhase = phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks;

    if (isUnsafeBuildPhase) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(update);
      });
      return;
    }

    setState(update);
  }

  void _setDocumentSelectionMode(bool enabled) {
    if (!mounted || _documentSelectionMode == enabled) return;

    _runSelectionStateUpdate(() {
      _documentSelectionMode = enabled;
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
      return;
    }
    _runSelectionStateUpdate(() {
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
    if (identical(_activeTextField, field)) {
      if (field != null) {
        final anchor = field.currentSelectionAnchor;
        if (anchor != null && _activeSelectionAnchor != anchor) {
          _setActiveSelectionAnchor(anchor);
        }
      }
      return;
    }

    _runSelectionStateUpdate(() {
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
      _activeSelectionAnchor = anchor;
      _activeCaretAnchor = anchor.caretAnchor;
      _activeBlockId = anchor.blockId;
      _restoreSelectionAnchor = anchor;
      _restoreCaretAnchor = anchor.caretAnchor;
    });
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
    final selection = _activeDocumentSelection;
    if (selection == null) return 'No active selection';
    return selection.labelFor(widget.document);
  }

  bool get _canCopySelection {
    if (_surfaceDocumentSelection != null && !_surfaceDocumentSelection!.isCollapsed) {
      return _activeDocumentRange != null;
    }

    final field = _usableActiveTextField;
    if (field != null) return field.hasNonCollapsedSelection;

    final range = _activeDocumentRange;
    return range != null && !range.isCollapsed;
  }

  bool get _canCutSelection {
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
  ) {
    if (!widget.editable) return;

    final anchor = _documentPositionForPagePoint(page, localPosition, margins);
    if (anchor == null) return;

    _surfaceSelectionDragBase = anchor;

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
  ) {
    if (!widget.editable) return;

    final base = _surfaceSelectionDragBase;
    if (base == null) return;

    final rawExtent = _documentPositionForPagePoint(page, localPosition, margins);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = widget.focusMode ? 30.0 : 58.0;
          final availableWidth = math.max(320.0, constraints.maxWidth - horizontalPadding * 2);
          final physicalWidth = widget.pageMaxWidth * (widget.pageSetup.pageWidthMm / TextSystemPagedBlockSurface._a4PortraitReferenceWidthMm);
          final pageWidth = math.min(physicalWidth, availableWidth);
          final pageHeight = pageWidth * widget.pageSetup.heightToWidthRatio;
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
          final navigation = _navigationForLayout(layout);

          return Scrollbar(
            controller: widget.scrollController,
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: widget.focusMode ? 30 : 58,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    ),
                    const SizedBox(height: 18),
                    for (final page in layout.pages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: TextSystemPagedBlockSurface._pageGap),
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
                          editable: widget.editable,
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
                          onOpenReferenceTarget: widget.onOpenReferenceTarget,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeStyle = activeBlock == null ? null : _PagedBlockToolbarStyle.fromBlock(activeBlock!, styleSheet);
    final typography = pageSetup.typography;
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
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
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
    required this.editable,
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
  final bool editable;
  final Map<String, _PagedFragmentNavigation> navigation;
  final TextSystemPagedCaretAnchor? restoreCaretAnchor;
  final TextSystemPagedSelectionAnchor? restoreSelectionAnchor;
  final TextSystemPagedDocumentSelection? surfaceDocumentSelection;
  final bool documentSelectionMode;
  final void Function(TextSystemPagedBlockPage page, Offset localPosition, EdgeInsets margins) onSurfaceSelectionPointerDown;
  final void Function(TextSystemPagedBlockPage page, Offset localPosition, EdgeInsets margins) onSurfaceSelectionPointerMove;
  final VoidCallback onSurfaceSelectionPointerEnd;
  final ValueChanged<TextSystemPagedCaretAnchor> onActiveCaretChanged;
  final ValueChanged<TextSystemPagedSelectionAnchor> onActiveSelectionChanged;
  final ValueChanged<_PagedEditableBlockFieldState?> onActiveFieldChanged;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRequestSelectionRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRestoreSelectionConsumed;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dimensionLabel = '${pageSetup.pageWidthMm.toStringAsFixed(0)} × ${pageSetup.pageHeightMm.toStringAsFixed(0)} mm';
    final marginMarkers = showMarginMarkers ? _marginMarkersForPage() : const <_PageMarginMarkerData>[];

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
              onPointerDown: (event) => onSurfaceSelectionPointerDown(page, event.localPosition, margins),
              onPointerMove: (event) => onSurfaceSelectionPointerMove(page, event.localPosition, margins),
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
                        navigation: navigation[_fragmentKey(fragment)] ?? const _PagedFragmentNavigation(),
                        restoreCaretAnchor: restoreCaretAnchor,
                        restoreSelectionAnchor: restoreSelectionAnchor,
                        onActiveCaretChanged: onActiveCaretChanged,
                        onActiveSelectionChanged: onActiveSelectionChanged,
                        onActiveFieldChanged: onActiveFieldChanged,
                        onRequestCaretRestore: onRequestCaretRestore,
                        onRequestSelectionRestore: onRequestSelectionRestore,
                        onRestoreSelectionConsumed: onRestoreSelectionConsumed,
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
                        onPointerDown: (event) => onSurfaceSelectionPointerDown(page, event.localPosition, margins),
                        onPointerMove: (event) => onSurfaceSelectionPointerMove(page, event.localPosition, margins),
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

    return Tooltip(
      waitDuration: const Duration(milliseconds: 900),
      message: marker.tooltip,
      child: DecoratedBox(
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
    required this.navigation,
    required this.restoreCaretAnchor,
    required this.restoreSelectionAnchor,
    required this.onActiveCaretChanged,
    required this.onActiveSelectionChanged,
    required this.onActiveFieldChanged,
    required this.onRequestCaretRestore,
    required this.onRequestSelectionRestore,
    required this.onRestoreSelectionConsumed,
    this.onOpenReferenceTarget,
  });

  final TextSystemController textController;
  final TextSystemBlock? block;
  final TextSystemPagedBlockFragment fragment;
  final TextSystemPageSetup pageSetup;
  final bool editable;
  final _PagedFragmentNavigation navigation;
  final TextSystemPagedCaretAnchor? restoreCaretAnchor;
  final TextSystemPagedSelectionAnchor? restoreSelectionAnchor;
  final ValueChanged<TextSystemPagedCaretAnchor> onActiveCaretChanged;
  final ValueChanged<TextSystemPagedSelectionAnchor> onActiveSelectionChanged;
  final ValueChanged<_PagedEditableBlockFieldState?> onActiveFieldChanged;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRequestSelectionRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRestoreSelectionConsumed;
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedBlock = block ?? TextSystemBlock.paragraph(id: fragment.blockId, text: fragment.text);

    if (_isPageBreakBlock(resolvedBlock)) {
      return _PageBreakBlockChip(
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
      );
    }

    if (_isSectionBreakBlock(resolvedBlock)) {
      return _SectionBreakBlockChip(
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
            restoreCaretAnchor: restoreCaretAnchor,
            restoreSelectionAnchor: restoreSelectionAnchor,
            onActiveCaretChanged: onActiveCaretChanged,
            onActiveSelectionChanged: onActiveSelectionChanged,
            onActiveFieldChanged: onActiveFieldChanged,
            onRequestCaretRestore: onRequestCaretRestore,
            onRequestSelectionRestore: onRequestSelectionRestore,
            onRestoreSelectionConsumed: onRestoreSelectionConsumed,
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

    return Stack(
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
    return TextSpan(
      style: effectiveStyle,
      children: _markedSpansForRange(
        text: text,
        block: _block,
        globalStart: safeStart,
        globalEnd: safeEnd,
        baseStyle: effectiveStyle,
      ),
    );
  }
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
    spans.add(
      TextSpan(
        text: footnoteMark == null
            ? segmentText
            : _academicFootnoteNumber(
                int.tryParse(footnoteMark.attributes['number'] ?? '') ?? 0,
              ),
        style: _styleWithMarks(baseStyle, coveringMarks),
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
    required this.restoreCaretAnchor,
    required this.restoreSelectionAnchor,
    required this.onActiveCaretChanged,
    required this.onActiveSelectionChanged,
    required this.onActiveFieldChanged,
    required this.onRequestCaretRestore,
    required this.onRequestSelectionRestore,
    required this.onRestoreSelectionConsumed,
    this.onOpenReferenceTarget,
  });

  final TextSystemBlock block;
  final TextSystemPagedBlockFragment fragment;
  final TextSystemController textController;
  final TextStyle style;
  final _PagedFragmentNavigation navigation;
  final TextSystemPagedCaretAnchor? restoreCaretAnchor;
  final TextSystemPagedSelectionAnchor? restoreSelectionAnchor;
  final ValueChanged<TextSystemPagedCaretAnchor> onActiveCaretChanged;
  final ValueChanged<TextSystemPagedSelectionAnchor> onActiveSelectionChanged;
  final ValueChanged<_PagedEditableBlockFieldState?> onActiveFieldChanged;
  final ValueChanged<TextSystemPagedCaretAnchor> onRequestCaretRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRequestSelectionRestore;
  final ValueChanged<TextSystemPagedSelectionAnchor> onRestoreSelectionConsumed;
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
      _notifyActiveSelection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _notifyActiveSelection();
      });
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

    if (anchor == last) return;

    _lastReportedSelectionAnchor = anchor;
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

    if ((key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) && _isCollapsedAtLocalStart) {
      return _moveToAnchor(widget.navigation.previousAnchor);
    }

    if ((key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) && _isCollapsedAtLocalEnd) {
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: colorScheme.primary.withValues(alpha: 0.28)),
            ),
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
