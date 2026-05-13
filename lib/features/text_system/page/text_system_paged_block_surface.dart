import 'dart:async';
import 'dart:math' as math;

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
import '../styles/text_system_document_style.dart';
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
    this.editable = true,
    this.scrollController,
    this.referenceActionRepository,
  });

  final TextSystemController textController;
  final TextSystemDocument document;
  final TextSystemPageSetup pageSetup;
  final double pageMaxWidth;
  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture>? onPageFurnitureChanged;
  final bool focusMode;
  final bool showMarginGuides;
  final bool editable;
  final ScrollController? scrollController;
  final TextSystemReferenceActionRepository? referenceActionRepository;

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

  TextSystemBlock? get _activeBlock {
    final blockId = _activeBlockId ?? _activeCaretAnchor?.blockId;
    if (blockId == null) return null;
    return widget.document.blockById(blockId);
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

    widget.textController.toggleMarkForDocumentRange(documentRange, kind);

    if (documentSelection.isSingleBlock) {
      final block = widget.document.blockById(documentSelection.base.blockId);
      if (block != null) {
        _requestSelectionRestore(
          TextSystemPagedSelectionAnchor(
            blockId: block.id,
            baseOffset: documentSelection.base.textOffset,
            extentOffset: documentSelection.extent.textOffset,
          ).clampToBlock(block),
        );
      }
    } else {
      _runSelectionStateUpdate(() {
        _surfaceDocumentSelection = documentSelection;
        _activeCaretAnchor = documentSelection.extent;
        _activeBlockId = documentSelection.extent.blockId;
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
        content: Text('Select text first, then choose a reference action.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createReferenceForActiveSelection(TextSystemReferenceActionType actionType) async {
    final repository = widget.referenceActionRepository;
    if (repository == null) return;

    final activeField = _surfaceDocumentSelection == null ? _usableActiveTextField : null;
    final fieldSelectionAnchor = activeField?.currentSelectionAnchor;
    final fieldDocumentRange = activeField?.documentRangeForToolbarSelection();

    final documentRange = fieldDocumentRange ?? _activeDocumentRange;
    final documentSelection = fieldSelectionAnchor == null
        ? _activeDocumentSelection
        : TextSystemPagedDocumentSelection.fromAnchor(fieldSelectionAnchor);

    if (documentRange == null || documentRange.isCollapsed || documentSelection == null) {
      _showReferenceSelectionRequiredMessage();
      return;
    }

    final selectedText = widget.textController.plainTextForDocumentRange(documentRange).trim();
    if (selectedText.isEmpty) {
      _showReferenceSelectionRequiredMessage();
      return;
    }

    final result = await showTextSystemReferenceActionPicker(
      context: context,
      selectedText: selectedText,
      repository: repository,
      initialActionType: actionType,
    );
    if (!mounted || result == null) return;

    widget.textController.applyMarkForDocumentRange(
      documentRange,
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

    if (documentSelection.isSingleBlock) {
      final block = widget.textController.document.blockById(documentSelection.base.blockId);
      if (block != null) {
        _requestSelectionRestore(
          TextSystemPagedSelectionAnchor(
            blockId: block.id,
            baseOffset: documentSelection.base.textOffset,
            extentOffset: documentSelection.extent.textOffset,
          ).clampToBlock(block),
        );
      }
    } else {
      _runSelectionStateUpdate(() {
        _surfaceDocumentSelection = documentSelection;
        _activeCaretAnchor = documentSelection.extent;
        _activeBlockId = documentSelection.extent.blockId;
      });
    }
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
    final block = _activeBlock;
    if (block == null || _isStructuralBreakBlock(block)) return;

    final selectionAnchor = (_activeSelectionAnchor ??
            TextSystemPagedSelectionAnchor.collapsed(
              blockId: block.id,
              textOffset: _activeCaretAnchor?.textOffset ?? block.text.length,
            ))
        .clampToBlock(block);

    final target = widget.textController.insertPageBreakAt(
      block.id,
      selectionAnchor.caretOffset,
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
    final block = _activeBlock;
    if (block == null || _isStructuralBreakBlock(block)) return;

    final selectionAnchor = (_activeSelectionAnchor ??
            TextSystemPagedSelectionAnchor.collapsed(
              blockId: block.id,
              textOffset: _activeCaretAnchor?.textOffset ?? block.text.length,
            ))
        .clampToBlock(block);

    final target = widget.textController.insertSectionBreakAt(
      block.id,
      selectionAnchor.caretOffset,
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
    final block = _activeBlock;
    if (block == null || _isStructuralBreakBlock(block) || _isFootnoteBlock(block)) return;

    final selectionAnchor = (_activeSelectionAnchor ??
            TextSystemPagedSelectionAnchor.collapsed(
              blockId: block.id,
              textOffset: _activeCaretAnchor?.textOffset ?? block.text.length,
            ))
        .clampToBlock(block);

    final target = widget.textController.insertFootnoteAt(
      block.id,
      selectionAnchor.caretOffset,
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
                      onReferenceAction: _canOpenReferenceActionMenu ? _createReferenceForActiveSelection : null,
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
    required this.onReferenceAction,
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
  final ValueChanged<TextSystemReferenceActionType>? onReferenceAction;
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
                  _PagedReferenceActionButton(onReferenceAction: onReferenceAction),
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
          ? 'Create a citation/source link from selected text'
          : 'Select text inside a block to create a citation or source link',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dimensionLabel = '${pageSetup.pageWidthMm.toStringAsFixed(0)} × ${pageSetup.pageHeightMm.toStringAsFixed(0)} mm';

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

    final decorated = switch (fragment.blockType) {
      TextSystemBlockType.quote => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colorScheme.primary.withValues(alpha: 0.35), width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: listAwareTextChild,
          ),
        ),
      TextSystemBlockType.code => DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: listAwareTextChild,
          ),
        ),
      _ => listAwareTextChild,
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
        if (_isFootnoteReferenceMark(mark)) {
          result = result.copyWith(
            color: Colors.blueAccent,
            fontSize: (result.fontSize ?? 14) * 0.66,
            fontWeight: FontWeight.w700,
            height: 0.95,
          );
        } else {
          decorations.add(TextDecoration.underline);
          result = result.copyWith(color: Colors.blueAccent);
        }
        break;
    }
  }

  if (decorations.isNotEmpty) {
    result = result.copyWith(decoration: TextDecoration.combine(decorations));
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

  @override
  State<_PagedEditableBlockField> createState() => _PagedEditableBlockFieldState();
}

class _PagedEditableBlockFieldState extends State<_PagedEditableBlockField> {
  late final _PagedMarkedTextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _selectionSyncTimer;
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

  @override
  void dispose() {
    widget.onActiveFieldChanged(null);
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
        onPointerDown: (_) => _scheduleActiveSelectionNotification(),
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
