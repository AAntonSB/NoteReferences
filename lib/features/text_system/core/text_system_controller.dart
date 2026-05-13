import 'package:flutter/foundation.dart';

import 'text_clipboard_fragment.dart';
import 'text_system_document_fragment.dart';
import 'text_system_document_fragment_edit.dart';
import 'text_system_document_fragment_ops.dart';
import 'text_system_document_mark_ops.dart';
import 'text_system_document_position.dart';
import 'text_system_document_range.dart';
import 'text_system_document_selection_mapper.dart';
import 'text_mark.dart';
import 'text_operation.dart';
import 'text_system_block.dart';
import 'text_system_document.dart';
import 'text_system_range.dart';
import 'text_transaction.dart';

class TextSystemSnapshot {
  TextSystemSnapshot({
    required this.document,
    required this.createdAt,
    this.label,
  });

  factory TextSystemSnapshot.fromJson(Map<String, Object?> json) {
    return TextSystemSnapshot(
      document: TextSystemDocument.fromJson(
        Map<String, Object?>.from(json['document'] as Map? ?? const <String, Object?>{}),
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      label: json['label'] as String?,
    );
  }

  final TextSystemDocument document;
  final DateTime createdAt;
  final String? label;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'document': document.toJson(),
      'createdAt': createdAt.toIso8601String(),
      if (label != null) 'label': label,
    };
  }
}

/// Controller for the reusable project-wide text engine.
///
/// It is UI-agnostic: tiny note fields, sidecar notes, normal documents, and
/// future premium writer shells can all drive the same transaction-safe model.
class TextSystemController extends ChangeNotifier {
  TextSystemController({required TextSystemDocument document}) : _document = document;

  TextSystemDocument _document;
  int _transactionSeed = 0;
  int _revision = 0;
  final List<TextTransaction> _undoStack = <TextTransaction>[];
  final List<TextTransaction> _redoStack = <TextTransaction>[];
  final List<TextTransaction> _transactionLog = <TextTransaction>[];
  final List<TextSystemSnapshot> _snapshots = <TextSystemSnapshot>[];
  static const Duration _textEditBatchWindow = Duration(milliseconds: 1800);
  DateTime? _lastTextEditAt;
  String? _lastTextEditBlockId;
  bool _startNewTextEditBatchOnNextInsertion = false;
  TextClipboardFragment? _internalClipboard;
  TextSystemDocumentFragment? _internalDocumentClipboard;

  TextSystemDocument get document => _document;
  int get revision => _revision;
  List<TextTransaction> get transactionLog => List.unmodifiable(_transactionLog);
  List<TextSystemSnapshot> get snapshots => List.unmodifiable(_snapshots);
  TextClipboardFragment? get internalClipboard => _internalClipboard;
  TextSystemDocumentFragment? get internalDocumentClipboard => _internalDocumentClipboard;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void replaceDocument(
    TextSystemDocument document, {
    String label = 'Replace document',
    TextTransactionOrigin origin = TextTransactionOrigin.system,
  }) {
    _commit(
      after: document.copyWith(updatedAt: DateTime.now()),
      label: label,
      operations: const <TextOperation>[
        TextOperation(type: TextOperationType.replaceDocument),
      ],
      origin: origin,
    );
  }

  void updateBlockText(String blockId, String text) {
    final block = _document.blockById(blockId);
    if (block == null || block.text == text) return;

    final nextBlock = block.copyWith(
      text: text,
      marks: _rebaseMarksForPlainTextReplace(
        oldText: block.text,
        newText: text,
        marks: block.marks,
      ),
    );

    _commitTextEdit(
      blockId: blockId,
      oldText: block.text,
      newText: text,
      after: _document.replaceBlock(nextBlock),
    );
  }

  TextSystemDocumentPosition? insertFootnoteAt(
    String blockId,
    int offset, {
    String initialText = '',
  }) {
    final blockIndex = _document.blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex < 0) return null;

    final block = _document.blocks[blockIndex];
    if (_isStructuralBreakBlock(block) || _isFootnoteBlock(block)) return null;

    final safeOffset = offset.clamp(0, block.text.length).toInt();
    final footnoteId = _nextGeneratedBlockId('footnote');
    final anchorText = '\uFFFC';
    final nextText = block.text.replaceRange(safeOffset, safeOffset, anchorText);
    final shiftedMarks = _rebaseMarksForPlainTextReplace(
      oldText: block.text,
      newText: nextText,
      marks: block.marks,
    );

    final nextAnchorBlock = block
        .copyWith(
          text: nextText,
          marks: _clampMarks(
            <TextMark>[
              ...shiftedMarks,
              TextMark(
                kind: TextMarkKind.link,
                range: TextSystemRange(safeOffset, safeOffset + anchorText.length),
                attributes: <String, String>{
                  'role': 'footnoteReference',
                  'footnoteId': footnoteId,
                  'number': '1',
                },
              ),
            ],
            nextText.length,
          ),
        )
        .normalizeMarks();

    final footnoteBlock = TextSystemBlock(
      id: _nextGeneratedBlockId('footnote-block'),
      type: TextSystemBlockType.custom,
      text: initialText,
      metadata: <String, Object?>{
        'kind': 'footnote',
        'footnoteId': footnoteId,
        'anchorBlockId': block.id,
        'anchorOffset': safeOffset,
      },
    );

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < _document.blocks.length; i++) ...[
        if (i == blockIndex) nextAnchorBlock else _document.blocks[i],
        if (i == blockIndex) footnoteBlock,
      ],
    ];

    final nextDocument = _renumberFootnotes(
      _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
    );

    _commit(
      after: nextDocument,
      label: 'Insert footnote',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.replaceDocument,
          blockId: blockId,
          range: TextSystemRange.collapsed(safeOffset),
          text: footnoteId,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return TextSystemDocumentPosition(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: safeOffset + anchorText.length,
    );
  }

  void removeFootnote(String footnoteId) {
    final nextBlocks = <TextSystemBlock>[];

    for (final block in _document.blocks) {
      if (_isFootnoteBlock(block) && block.metadata['footnoteId'] == footnoteId) {
        continue;
      }

      final nextMarks = <TextMark>[];
      var nextText = block.text;
      var removedAnchor = false;

      for (final mark in block.marks) {
        if (_isFootnoteReferenceMark(mark) && mark.attributes['footnoteId'] == footnoteId) {
          nextText = nextText.replaceRange(mark.range.start, mark.range.end, '');
          removedAnchor = true;
        } else {
          nextMarks.add(mark);
        }
      }

      if (removedAnchor) {
        nextBlocks.add(
          block
              .copyWith(
                text: nextText,
                marks: _clampMarks(
                  _rebaseMarksForPlainTextReplace(
                    oldText: block.text,
                    newText: nextText,
                    marks: nextMarks,
                  ),
                  nextText.length,
                ),
              )
              .normalizeMarks(),
        );
      } else {
        nextBlocks.add(block);
      }
    }

    final nextDocument = _renumberFootnotes(
      _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
    );

    _commit(
      after: nextDocument,
      label: 'Delete footnote',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.replaceDocument,
          text: footnoteId,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );
  }

  void toggleMark(String blockId, TextSystemRange range, TextMarkKind kind) {
    final block = _document.blockById(blockId);
    if (block == null) return;

    final safeRange = range.clamp(block.text.length);
    if (safeRange.isCollapsed) return;

    final marks = List<TextMark>.from(block.marks);
    final existingIndex = marks.indexWhere(
      (mark) => mark.kind == kind && mark.range == safeRange,
    );

    var label = 'Apply ${kind.name}';
    if (existingIndex >= 0) {
      marks.removeAt(existingIndex);
      label = 'Remove ${kind.name}';
    } else {
      marks.add(TextMark(kind: kind, range: safeRange));
    }

    final nextBlock = block.copyWith(marks: _clampMarks(marks, block.text.length));
    _commit(
      after: _document.replaceBlock(nextBlock),
      label: label,
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.toggleMark,
          blockId: blockId,
          range: safeRange,
          markKind: kind,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );
  }


  void toggleMarkForDocumentRange(TextSystemDocumentRange range, TextMarkKind kind) {
    final normalized = range.normalized();
    if (normalized.isCollapsed) return;

    final nextDocument = TextSystemDocumentMarkOps.toggleMark(
      document: _document,
      range: normalized,
      kind: kind,
    );

    _commit(
      after: nextDocument,
      label: 'Toggle ${kind.name} in selection',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.toggleDocumentMark,
          documentRange: normalized,
          markKind: kind,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );
  }


  void applyMarkForDocumentRange(
    TextSystemDocumentRange range,
    TextMarkKind kind, {
    Map<String, String> attributes = const <String, String>{},
    String? label,
    TextSystemDocument Function(TextSystemDocument document)? transformAfterApply,
  }) {
    final normalized = range.normalized();
    if (normalized.isCollapsed) return;

    var nextDocument = TextSystemDocumentMarkOps.applyMark(
      document: _document,
      range: normalized,
      kind: kind,
      attributes: attributes,
    );
    if (transformAfterApply != null) {
      nextDocument = transformAfterApply(nextDocument);
    }

    _commit(
      after: nextDocument,
      label: label ?? 'Apply ${kind.name} to selection',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.toggleDocumentMark,
          documentRange: normalized,
          markKind: kind,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );
  }

  TextSystemDocumentFragmentEditResult insertMarkedPlainTextAtDocumentPosition({
    required TextSystemDocumentPosition position,
    required String text,
    required List<TextMark> marks,
    String label = 'Insert marked text',
    TextSystemDocument Function(TextSystemDocument document)? transformAfterInsert,
  }) {
    if (text.isEmpty) {
      final collapsed = TextSystemDocumentRange.collapsed(position);
      return TextSystemDocumentFragmentEditResult(
        document: _document,
        replacementRange: collapsed,
        insertedRange: collapsed,
        affectedBlockIds: const <String>[],
        insertedPlainText: '',
      );
    }

    final safeMarks = marks
        .map((mark) => mark.clamp(text.length))
        .where((mark) => !mark.isEmpty)
        .toList(growable: false);
    final fragment = TextSystemDocumentFragment(
      blocks: <TextSystemBlock>[
        TextSystemBlock.paragraph(
          id: 'marked-${_revision + 1}-${DateTime.now().microsecondsSinceEpoch}',
          text: text,
          marks: safeMarks,
        ),
      ],
      metadata: const <String, Object?>{
        'source': 'markedPlainText',
      },
    );
    final insertionRange = TextSystemDocumentRange.collapsed(position);
    final result = TextSystemDocumentFragmentOps.replaceRangeWithFragment(
      document: _document,
      range: insertionRange,
      fragment: fragment,
      idPrefix: 'marked-${_revision + 1}',
    );
    final nextDocument = transformAfterInsert == null
        ? result.document
        : transformAfterInsert(result.document);

    _commit(
      after: nextDocument,
      label: label,
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.insertDocumentFragment,
          documentRange: insertionRange,
          documentFragment: fragment,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return TextSystemDocumentFragmentEditResult(
      document: nextDocument,
      replacementRange: result.replacementRange,
      insertedRange: result.insertedRange,
      affectedBlockIds: result.affectedBlockIds,
      insertedPlainText: result.insertedPlainText,
    );
  }


  TextSystemDocumentFragment copyDocumentFragmentByOffsets(int start, int end) {
    final range = TextSystemDocumentSelectionMapper.rangeFromOffsets(_document, start, end);
    return copyDocumentFragment(range);
  }

  TextSystemDocumentFragmentEditResult replaceDocumentRangeWithFragment(
    TextSystemDocumentRange range,
    TextSystemDocumentFragment fragment, {
    String label = 'Paste structured text',
  }) {
    final result = TextSystemDocumentFragmentOps.replaceRangeWithFragment(
      document: _document,
      range: range,
      fragment: fragment,
      idPrefix: 'paste-${_revision + 1}',
    );

    _commit(
      after: result.document,
      label: label,
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.insertDocumentFragment,
          documentRange: range.normalized(),
          documentFragment: fragment,
        ),
      ],
      origin: TextTransactionOrigin.paste,
    );
    return result;
  }

  TextSystemDocumentFragmentEditResult pasteDocumentClipboardAtRange(TextSystemDocumentRange range) {
    final fragment = _internalDocumentClipboard;
    if (fragment == null || fragment.isEmpty) {
      final collapsed = range.normalized();
      return TextSystemDocumentFragmentEditResult(
        document: _document,
        replacementRange: collapsed,
        insertedRange: collapsed,
        affectedBlockIds: const <String>[],
        insertedPlainText: '',
      );
    }
    return replaceDocumentRangeWithFragment(range, fragment);
  }

  TextSystemDocumentFragmentEditResult deleteDocumentRange(
    TextSystemDocumentRange range, {
    String label = 'Delete selection',
  }) {
    final normalized = range.normalized();
    if (normalized.isCollapsed) {
      return TextSystemDocumentFragmentEditResult(
        document: _document,
        replacementRange: normalized,
        insertedRange: normalized,
        affectedBlockIds: const <String>[],
        insertedPlainText: '',
      );
    }

    return replaceDocumentRangeWithFragment(
      normalized,
      TextSystemDocumentFragment.empty(),
      label: label,
    );
  }

  TextSystemDocumentFragmentEditResult replaceDocumentRangeWithPlainText(
    TextSystemDocumentRange range,
    String text, {
    String label = 'Replace selection',
  }) {
    final normalized = range.normalized();
    final fragment = TextSystemDocumentFragment.fromPlainText(
      text,
      idPrefix: 'plain-${_revision + 1}',
    );
    return replaceDocumentRangeWithFragment(
      normalized,
      fragment,
      label: label,
    );
  }

  TextSystemDocumentFragment cutDocumentRange(TextSystemDocumentRange range) {
    final normalized = range.normalized();
    final fragment = copyDocumentFragment(normalized);
    deleteDocumentRange(normalized, label: 'Cut selection');
    return fragment;
  }

  String plainTextForDocumentRange(TextSystemDocumentRange range) {
    return TextSystemDocumentSelectionMapper.plainTextForRange(_document, range);
  }

  TextSystemDocumentFragmentEditResult pasteDocumentClipboardAtPosition(TextSystemDocumentPosition position) {
    return pasteDocumentClipboardAtRange(TextSystemDocumentRange.collapsed(position));
  }

  TextSystemDocumentFragment copyDocumentFragment(TextSystemDocumentRange range) {
    final fragment = TextSystemDocumentSelectionMapper.fragmentForRange(_document, range);
    _internalDocumentClipboard = fragment;
    _internalClipboard = fragment.toFlatClipboardFragment();
    notifyListeners();
    return fragment;
  }

  TextClipboardFragment copyFragment(String blockId, TextSystemRange range) {
    final block = _document.blockById(blockId);
    if (block == null) {
      return const TextClipboardFragment(text: '');
    }

    final safeRange = range.clamp(block.text.length);
    if (safeRange.isCollapsed) {
      return const TextClipboardFragment(text: '');
    }

    final text = block.text.substring(safeRange.start, safeRange.end);
    final marks = <TextMark>[];
    for (final mark in block.marks) {
      final intersection = mark.range.intersection(safeRange);
      if (intersection == null) continue;
      marks.add(mark.copyWith(range: intersection.relativeTo(safeRange.start)));
    }

    final fragment = TextClipboardFragment(
      text: text,
      marks: marks,
      metadata: <String, Object?>{'sourceBlockId': blockId},
    );
    _internalClipboard = fragment;
    notifyListeners();
    return fragment;
  }

  void pasteInternalClipboard(String blockId, int offset) {
    final fragment = _internalClipboard;
    if (fragment == null || fragment.isEmpty) return;
    insertFragment(blockId, TextSystemRange.collapsed(offset), fragment);
  }

  void insertFragment(
    String blockId,
    TextSystemRange range,
    TextClipboardFragment fragment,
  ) {
    final block = _document.blockById(blockId);
    if (block == null || fragment.isEmpty) return;

    final safeRange = range.clamp(block.text.length);
    final before = block.text.substring(0, safeRange.start);
    final after = block.text.substring(safeRange.end);
    final nextText = '$before${fragment.text}$after';
    final replacedLength = safeRange.length;
    final insertedLength = fragment.text.length;
    final delta = insertedLength - replacedLength;

    final nextMarks = <TextMark>[];
    for (final mark in block.marks) {
      if (mark.range.end <= safeRange.start) {
        nextMarks.add(mark);
      } else if (mark.range.start >= safeRange.end) {
        nextMarks.add(mark.copyWith(range: mark.range.shift(delta)));
      } else if (mark.range.start < safeRange.start && mark.range.end > safeRange.end) {
        nextMarks.add(
          mark.copyWith(
            range: TextSystemRange(mark.range.start, mark.range.end + delta),
          ),
        );
      }
    }

    nextMarks.addAll(
      fragment.marks.map(
        (mark) => mark.copyWith(range: mark.range.shift(safeRange.start)),
      ),
    );

    final nextBlock = block.copyWith(
      text: nextText,
      marks: _clampMarks(nextMarks, nextText.length),
    );

    _commit(
      after: _document.replaceBlock(nextBlock),
      label: 'Paste rich text',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.insertFragment,
          blockId: blockId,
          range: safeRange,
          fragment: fragment,
        ),
      ],
      origin: TextTransactionOrigin.paste,
    );
  }


  TextSystemDocumentPosition? splitBlockAt(String blockId, int offset) {
    final blockIndex = _document.blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex < 0) return null;

    final block = _document.blocks[blockIndex];
    final safeOffset = offset.clamp(0, block.text.length).toInt();
    final beforeText = block.text.substring(0, safeOffset);
    final afterText = block.text.substring(safeOffset);
    final nextBlockId = _nextGeneratedBlockId('split');

    final currentType = block.type;
    final nextType = currentType == TextSystemBlockType.heading
        ? TextSystemBlockType.paragraph
        : currentType;

    final beforeMarks = _marksForSplitPart(
      marks: block.marks,
      start: 0,
      end: safeOffset,
    );
    final afterMarks = _marksForSplitPart(
      marks: block.marks,
      start: safeOffset,
      end: block.text.length,
    );

    final beforeBlock = block.copyWith(
      text: beforeText,
      marks: beforeMarks,
    ).normalizeMarks();

    final afterBlock = TextSystemBlock(
      id: nextBlockId,
      type: nextType,
      text: afterText,
      marks: afterMarks,
      level: nextType == TextSystemBlockType.heading ? block.level : null,
      checked: nextType == TextSystemBlockType.todo ? false : null,
      metadata: nextType == TextSystemBlockType.listItem || nextType == TextSystemBlockType.todo
          ? Map<String, Object?>.unmodifiable(_listMetadataForSplit(block, nextType))
          : const <String, Object?>{},
    ).normalizeMarks();

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < _document.blocks.length; i++) ...[
        if (i == blockIndex) beforeBlock else _document.blocks[i],
        if (i == blockIndex) afterBlock,
      ],
    ];

    _commit(
      after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: 'Split block',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.splitBlock,
          blockId: blockId,
          range: TextSystemRange.collapsed(safeOffset),
          text: nextBlockId,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return TextSystemDocumentPosition(
      blockId: nextBlockId,
      blockIndex: blockIndex + 1,
      offset: 0,
    );
  }

  TextSystemDocumentPosition? mergeBlockWithPrevious(String blockId) {
    final blockIndex = _document.blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex <= 0) return null;

    final currentBlock = _document.blocks[blockIndex];
    final previousBlock = _document.blocks[blockIndex - 1];

    if (!_canMergeBlocks(previousBlock, currentBlock)) {
      return null;
    }

    final previousLength = previousBlock.text.length;
    final mergedText = '${previousBlock.text}${currentBlock.text}';
    final mergedMarks = <TextMark>[
      ...previousBlock.marks,
      ...currentBlock.marks.map(
        (mark) => mark.copyWith(range: mark.range.shift(previousLength)),
      ),
    ];

    final mergedBlock = previousBlock.copyWith(
      text: mergedText,
      marks: _clampMarks(mergedMarks, mergedText.length),
    );

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < _document.blocks.length; i++)
        if (i == blockIndex - 1)
          mergedBlock
        else if (i != blockIndex)
          _document.blocks[i],
    ];

    _commit(
      after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: 'Merge blocks',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.mergeBlocks,
          blockId: blockId,
          range: TextSystemRange.collapsed(0),
          text: previousBlock.id,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return TextSystemDocumentPosition(
      blockId: previousBlock.id,
      blockIndex: blockIndex - 1,
      offset: previousLength,
    );
  }

  void updateBlockType(
    String blockId,
    TextSystemBlockType type, {
    int? level,
    bool? checked,
    Map<String, Object?>? metadata,
  }) {
    final block = _document.blockById(blockId);
    if (block == null) return;

    final nextBlock = _blockConvertedToType(
      block,
      type,
      level: level,
      checked: checked,
      metadata: metadata,
    );

    if (_blocksEquivalent(nextBlock, block)) return;

    _commit(
      after: _document.replaceBlock(nextBlock),
      label: 'Change block style',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.replaceBlockType,
          blockId: blockId,
          text: type.name,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );
  }

  /// Converts a contiguous list-like group in one transaction.
  ///
  /// This is intentionally separate from [updateBlockType]. A normal style
  /// conversion can still target one block, while list/todo conversions from the
  /// real-page toolbar can preserve the user's mental model that a list is one
  /// object containing items.
  void updateListGroupBlockType(
    String blockId,
    TextSystemBlockType type, {
    int? level,
    bool? checked,
    Map<String, Object?>? metadata,
  }) {
    final blockIndex = _document.blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex < 0) return;

    final sourceBlock = _document.blocks[blockIndex];
    final groupRange = _listGroupRangeFor(blockIndex);
    final targetGroupId = _isListLikeType(type)
        ? (_listGroupIdFor(sourceBlock) ?? _newListGroupId())
        : null;

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < _document.blocks.length; i++)
        if (i >= groupRange.start && i < groupRange.end)
          _blockConvertedToType(
            _document.blocks[i],
            type,
            level: level,
            checked: type == TextSystemBlockType.todo
                ? (_document.blocks[i].checked ?? checked ?? false)
                : checked,
            metadata: _metadataForListGroupConversion(
              source: _document.blocks[i],
              targetType: type,
              requestedMetadata: metadata,
              groupId: targetGroupId,
            ),
          )
        else
          _document.blocks[i],
    ];

    if (_blockListsEquivalent(nextBlocks, _document.blocks)) return;

    _commit(
      after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: _isListLikeType(type) ? 'Change list group style' : 'Change block group style',
      operations: <TextOperation>[
        for (var i = groupRange.start; i < groupRange.end; i++)
          TextOperation(
            type: TextOperationType.replaceBlockType,
            blockId: _document.blocks[i].id,
            text: type.name,
          ),
      ],
      origin: TextTransactionOrigin.user,
    );
  }

  void toggleTodoChecked(String blockId) {
    final block = _document.blockById(blockId);
    if (block == null || block.type != TextSystemBlockType.todo) return;

    final nextBlock = _blockConvertedToType(
      block,
      TextSystemBlockType.todo,
      checked: !(block.checked ?? false),
      metadata: block.metadata,
    );

    if (_blocksEquivalent(nextBlock, block)) return;

    _commit(
      after: _document.replaceBlock(nextBlock),
      label: 'Toggle todo',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.replaceBlockType,
          blockId: blockId,
          text: 'todo:${nextBlock.checked == true ? 'checked' : 'unchecked'}',
        ),
      ],
      origin: TextTransactionOrigin.user,
    );
  }



  /// Inserts a complete block at a caret position.
  ///
  /// This is used by higher-level systems such as embedded app TODOs, figures,
  /// and future table/caption blocks. The inserted block is kept as a real
  /// document block rather than an inline mark.
  TextSystemDocumentPosition? insertBlockAtPosition(
    String blockId,
    int offset,
    TextSystemBlock insertedBlock, {
    String label = 'Insert block',
  }) {
    final blockIndex = _document.blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex < 0) return null;

    final block = _document.blocks[blockIndex];
    if (_isStructuralBreakBlock(block)) return null;

    final safeOffset = offset.clamp(0, block.text.length).toInt();
    final nextBlocks = <TextSystemBlock>[];
    late final TextSystemDocumentPosition targetPosition;

    for (var i = 0; i < _document.blocks.length; i++) {
      if (i != blockIndex) {
        nextBlocks.add(_document.blocks[i]);
        continue;
      }

      if (safeOffset <= 0) {
        nextBlocks.add(insertedBlock);
        nextBlocks.add(block);
        targetPosition = TextSystemDocumentPosition(
          blockId: insertedBlock.id,
          blockIndex: nextBlocks.length - 2,
          offset: insertedBlock.text.length,
        );
        continue;
      }

      if (safeOffset >= block.text.length) {
        nextBlocks.add(block);
        nextBlocks.add(insertedBlock);
        targetPosition = TextSystemDocumentPosition(
          blockId: insertedBlock.id,
          blockIndex: nextBlocks.length - 1,
          offset: insertedBlock.text.length,
        );
        continue;
      }

      final beforeText = block.text.substring(0, safeOffset);
      final afterText = block.text.substring(safeOffset);
      final afterBlockId = _nextGeneratedBlockId('after-inserted-block');
      final afterType = block.type == TextSystemBlockType.heading
          ? TextSystemBlockType.paragraph
          : block.type;

      final beforeBlock = block.copyWith(
        text: beforeText,
        marks: _marksForSplitPart(
          marks: block.marks,
          start: 0,
          end: safeOffset,
        ),
      ).normalizeMarks();

      final afterBlock = TextSystemBlock(
        id: afterBlockId,
        type: afterType,
        text: afterText,
        marks: _marksForSplitPart(
          marks: block.marks,
          start: safeOffset,
          end: block.text.length,
        ),
        level: afterType == TextSystemBlockType.heading ? block.level : null,
        checked: afterType == TextSystemBlockType.todo ? block.checked : null,
        metadata: afterType == TextSystemBlockType.listItem || afterType == TextSystemBlockType.todo
            ? Map<String, Object?>.unmodifiable(block.metadata)
            : const <String, Object?>{},
      ).normalizeMarks();

      nextBlocks.add(beforeBlock);
      nextBlocks.add(insertedBlock);
      nextBlocks.add(afterBlock);
      targetPosition = TextSystemDocumentPosition(
        blockId: insertedBlock.id,
        blockIndex: nextBlocks.length - 2,
        offset: insertedBlock.text.length,
      );
    }

    _commit(
      after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: label,
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.replaceDocument,
          blockId: blockId,
          range: TextSystemRange.collapsed(safeOffset),
          text: insertedBlock.id,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return targetPosition;
  }


  /// Inserts a structural page-break block at the requested text position.
  ///
  /// The command is caret-position aware:
  /// - at block start: inserts the page break before the current block;
  /// - in the middle: splits the block and inserts the page break between the
  ///   two resulting blocks;
  /// - at block end: inserts the page break after the block and creates an
  ///   empty paragraph after it when there is no following block.
  ///
  /// The returned position is the best caret target after the break.
  TextSystemDocumentPosition? insertPageBreakAt(String blockId, int offset) {
    final blockIndex = _document.blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex < 0) return null;

    final block = _document.blocks[blockIndex];
    if (_isStructuralBreakBlock(block)) return null;

    final safeOffset = offset.clamp(0, block.text.length).toInt();
    late final TextSystemBlock pageBreakBlock;
    final nextBlocks = <TextSystemBlock>[];
    late final TextSystemDocumentPosition targetPosition;

    for (var i = 0; i < _document.blocks.length; i++) {
      if (i != blockIndex) {
        nextBlocks.add(_document.blocks[i]);
        continue;
      }

      if (safeOffset <= 0) {
        pageBreakBlock = _newPageBreakBlock();
        nextBlocks.add(pageBreakBlock);
        nextBlocks.add(block);
        targetPosition = TextSystemDocumentPosition(
          blockId: block.id,
          blockIndex: nextBlocks.length - 1,
          offset: 0,
        );
        continue;
      }

      if (safeOffset >= block.text.length) {
        pageBreakBlock = _newPageBreakBlock();
        nextBlocks.add(block);
        nextBlocks.add(pageBreakBlock);

        if (blockIndex + 1 < _document.blocks.length) {
          final followingBlock = _document.blocks[blockIndex + 1];
          targetPosition = TextSystemDocumentPosition(
            blockId: followingBlock.id,
            blockIndex: nextBlocks.length,
            offset: 0,
          );
        } else {
          final paragraph = TextSystemBlock.paragraph(
            id: _nextGeneratedBlockId('after-page-break'),
            text: '',
          );
          nextBlocks.add(paragraph);
          targetPosition = TextSystemDocumentPosition(
            blockId: paragraph.id,
            blockIndex: nextBlocks.length - 1,
            offset: 0,
          );
        }
        continue;
      }

      pageBreakBlock = _newPageBreakBlock(
        mergeAdjacentOnDelete: true,
        splitSourceBlockId: block.id,
      );

      final beforeText = block.text.substring(0, safeOffset);
      final afterText = block.text.substring(safeOffset);
      final afterBlockId = _nextGeneratedBlockId('after-page-break');
      final afterType = block.type == TextSystemBlockType.heading
          ? TextSystemBlockType.paragraph
          : block.type;

      final beforeBlock = block.copyWith(
        text: beforeText,
        marks: _marksForSplitPart(
          marks: block.marks,
          start: 0,
          end: safeOffset,
        ),
      ).normalizeMarks();

      final afterBlock = TextSystemBlock(
        id: afterBlockId,
        type: afterType,
        text: afterText,
        marks: _marksForSplitPart(
          marks: block.marks,
          start: safeOffset,
          end: block.text.length,
        ),
        level: afterType == TextSystemBlockType.heading ? block.level : null,
        checked: afterType == TextSystemBlockType.todo ? block.checked : null,
        metadata: const <String, Object?>{},
      ).normalizeMarks();

      nextBlocks.add(beforeBlock);
      nextBlocks.add(pageBreakBlock);
      nextBlocks.add(afterBlock);
      targetPosition = TextSystemDocumentPosition(
        blockId: afterBlock.id,
        blockIndex: nextBlocks.length - 1,
        offset: 0,
      );
    }

    _commit(
      after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: 'Insert page break',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.insertPageBreak,
          blockId: blockId,
          range: TextSystemRange.collapsed(safeOffset),
          text: pageBreakBlock.id,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return targetPosition;
  }


  /// Inserts a next-page section break at the requested text position.
  ///
  /// A section break is structural page layout metadata, not blank lines. It
  /// starts the following content on a new page and can carry section-level
  /// page numbering/setup metadata.
  TextSystemDocumentPosition? insertSectionBreakAt(
    String blockId,
    int offset, {
    bool restartPageNumbering = true,
    int pageNumberStartAt = 1,
  }) {
    final blockIndex = _document.blocks.indexWhere((block) => block.id == blockId);
    if (blockIndex < 0) return null;

    final block = _document.blocks[blockIndex];
    if (_isStructuralBreakBlock(block)) return null;

    final safeOffset = offset.clamp(0, block.text.length).toInt();
    late final TextSystemBlock sectionBreakBlock;
    final nextBlocks = <TextSystemBlock>[];
    late final TextSystemDocumentPosition targetPosition;

    for (var i = 0; i < _document.blocks.length; i++) {
      if (i != blockIndex) {
        nextBlocks.add(_document.blocks[i]);
        continue;
      }

      if (safeOffset <= 0) {
        sectionBreakBlock = _newSectionBreakBlock(
          restartPageNumbering: restartPageNumbering,
          pageNumberStartAt: pageNumberStartAt,
        );
        nextBlocks.add(sectionBreakBlock);
        nextBlocks.add(block);
        targetPosition = TextSystemDocumentPosition(
          blockId: block.id,
          blockIndex: nextBlocks.length - 1,
          offset: 0,
        );
        continue;
      }

      if (safeOffset >= block.text.length) {
        sectionBreakBlock = _newSectionBreakBlock(
          restartPageNumbering: restartPageNumbering,
          pageNumberStartAt: pageNumberStartAt,
        );
        nextBlocks.add(block);
        nextBlocks.add(sectionBreakBlock);

        if (blockIndex + 1 < _document.blocks.length) {
          final followingBlock = _document.blocks[blockIndex + 1];
          targetPosition = TextSystemDocumentPosition(
            blockId: followingBlock.id,
            blockIndex: nextBlocks.length,
            offset: 0,
          );
        } else {
          final paragraph = TextSystemBlock.paragraph(
            id: _nextGeneratedBlockId('after-section-break'),
            text: '',
          );
          nextBlocks.add(paragraph);
          targetPosition = TextSystemDocumentPosition(
            blockId: paragraph.id,
            blockIndex: nextBlocks.length - 1,
            offset: 0,
          );
        }
        continue;
      }

      sectionBreakBlock = _newSectionBreakBlock(
        restartPageNumbering: restartPageNumbering,
        pageNumberStartAt: pageNumberStartAt,
        mergeAdjacentOnDelete: true,
        splitSourceBlockId: block.id,
      );

      final beforeText = block.text.substring(0, safeOffset);
      final afterText = block.text.substring(safeOffset);
      final afterBlockId = _nextGeneratedBlockId('after-section-break');
      final afterType = block.type == TextSystemBlockType.heading
          ? TextSystemBlockType.paragraph
          : block.type;

      final beforeBlock = block.copyWith(
        text: beforeText,
        marks: _marksForSplitPart(
          marks: block.marks,
          start: 0,
          end: safeOffset,
        ),
      ).normalizeMarks();

      final afterBlock = TextSystemBlock(
        id: afterBlockId,
        type: afterType,
        text: afterText,
        marks: _marksForSplitPart(
          marks: block.marks,
          start: safeOffset,
          end: block.text.length,
        ),
        level: afterType == TextSystemBlockType.heading ? block.level : null,
        checked: afterType == TextSystemBlockType.todo ? block.checked : null,
        metadata: afterType == TextSystemBlockType.listItem
            ? Map<String, Object?>.unmodifiable(block.metadata)
            : const <String, Object?>{},
      ).normalizeMarks();

      nextBlocks.add(beforeBlock);
      nextBlocks.add(sectionBreakBlock);
      nextBlocks.add(afterBlock);
      targetPosition = TextSystemDocumentPosition(
        blockId: afterBlock.id,
        blockIndex: nextBlocks.length - 1,
        offset: 0,
      );
    }

    _commit(
      after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: 'Insert section break',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.insertPageBreak,
          blockId: blockId,
          range: TextSystemRange.collapsed(safeOffset),
          text: sectionBreakBlock.id,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return targetPosition;
  }

  TextSystemDocumentPosition? removeSectionBreak(String blockId) {
    final index = _document.blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return null;
    final block = _document.blocks[index];
    if (!_isSectionBreakBlock(block)) return null;
    return _removeSectionBreakAt(index);
  }

  TextSystemDocumentPosition? removePageBreak(String blockId) {
    final index = _document.blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return null;
    return _removePageBreakAt(index);
  }

  TextSystemDocumentPosition? removePageBreakBefore(String blockId) {
    final index = _document.blocks.indexWhere((block) => block.id == blockId);
    if (index <= 0) return null;
    return _removePageBreakAt(index - 1, preferredNextBlockId: blockId);
  }

  TextSystemDocumentPosition? _removePageBreakAt(
    int index, {
    String? preferredNextBlockId,
  }) {
    if (index < 0 || index >= _document.blocks.length) return null;

    final pageBreakBlock = _document.blocks[index];
    if (!_isPageBreakBlock(pageBreakBlock)) return null;

    final shouldMergeAdjacent = pageBreakBlock.metadata['mergeAdjacentOnDelete'] == true;
    final previousBlock = index > 0 ? _document.blocks[index - 1] : null;
    final nextBlock = index + 1 < _document.blocks.length ? _document.blocks[index + 1] : null;

    if (shouldMergeAdjacent &&
        previousBlock != null &&
        nextBlock != null &&
        _canMergeBlocks(previousBlock, nextBlock)) {
      final mergeOffset = previousBlock.text.length;
      final mergedText = '${previousBlock.text}${nextBlock.text}';
      final mergedMarks = <TextMark>[
        ...previousBlock.marks,
        ...nextBlock.marks.map(
          (mark) => mark.copyWith(range: mark.range.shift(mergeOffset)),
        ),
      ];

      final mergedBlock = previousBlock
          .copyWith(
            text: mergedText,
            marks: _clampMarks(mergedMarks, mergedText.length),
          )
          .normalizeMarks();

      final nextBlocks = <TextSystemBlock>[
        for (var i = 0; i < _document.blocks.length; i++)
          if (i == index - 1)
            mergedBlock
          else if (i != index && i != index + 1)
            _document.blocks[i],
      ];

      _commit(
        after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
        label: 'Delete page break and merge split block',
        operations: <TextOperation>[
          TextOperation(
            type: TextOperationType.deleteBlock,
            blockId: pageBreakBlock.id,
          ),
          TextOperation(
            type: TextOperationType.mergeBlocks,
            blockId: nextBlock.id,
            range: TextSystemRange.collapsed(0),
            text: previousBlock.id,
          ),
        ],
        origin: TextTransactionOrigin.user,
      );

      return TextSystemDocumentPosition(
        blockId: previousBlock.id,
        blockIndex: index - 1,
        offset: mergeOffset,
      );
    }

    return _removeBlockAt(
      index,
      label: 'Delete page break',
      operationType: TextOperationType.deleteBlock,
    );
  }


  TextSystemDocumentPosition? _removeSectionBreakAt(int index) {
    if (index < 0 || index >= _document.blocks.length) return null;

    final sectionBreakBlock = _document.blocks[index];
    if (!_isSectionBreakBlock(sectionBreakBlock)) return null;

    final shouldMergeAdjacent = sectionBreakBlock.metadata['mergeAdjacentOnDelete'] == true;
    final previousBlock = index > 0 ? _document.blocks[index - 1] : null;
    final nextBlock = index + 1 < _document.blocks.length ? _document.blocks[index + 1] : null;

    if (shouldMergeAdjacent &&
        previousBlock != null &&
        nextBlock != null &&
        _canMergeBlocks(previousBlock, nextBlock)) {
      final mergeOffset = previousBlock.text.length;
      final mergedText = '${previousBlock.text}${nextBlock.text}';
      final mergedMarks = <TextMark>[
        ...previousBlock.marks,
        ...nextBlock.marks.map(
          (mark) => mark.copyWith(range: mark.range.shift(mergeOffset)),
        ),
      ];

      final mergedBlock = previousBlock
          .copyWith(
            text: mergedText,
            marks: _clampMarks(mergedMarks, mergedText.length),
          )
          .normalizeMarks();

      final nextBlocks = <TextSystemBlock>[
        for (var i = 0; i < _document.blocks.length; i++)
          if (i == index - 1)
            mergedBlock
          else if (i != index && i != index + 1)
            _document.blocks[i],
      ];

      _commit(
        after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
        label: 'Delete section break and merge split block',
        operations: <TextOperation>[
          TextOperation(
            type: TextOperationType.deleteBlock,
            blockId: sectionBreakBlock.id,
          ),
          TextOperation(
            type: TextOperationType.mergeBlocks,
            blockId: nextBlock.id,
            range: TextSystemRange.collapsed(0),
            text: previousBlock.id,
          ),
        ],
        origin: TextTransactionOrigin.user,
      );

      return TextSystemDocumentPosition(
        blockId: previousBlock.id,
        blockIndex: index - 1,
        offset: mergeOffset,
      );
    }

    return _removeBlockAt(
      index,
      label: 'Delete section break',
      operationType: TextOperationType.deleteBlock,
    );
  }

  TextSystemDocumentPosition? _removeBlockAt(
    int index, {
    required String label,
    required TextOperationType operationType,
  }) {
    if (index < 0 || index >= _document.blocks.length) return null;
    final removed = _document.blocks[index];

    final fallbackParagraph = TextSystemBlock.paragraph(
      id: _nextGeneratedBlockId('empty'),
      text: '',
    );

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < _document.blocks.length; i++)
        if (i != index) _document.blocks[i],
    ];

    if (nextBlocks.isEmpty) {
      nextBlocks.add(fallbackParagraph);
    }

    final targetIndex = index < nextBlocks.length ? index : nextBlocks.length - 1;
    final targetBlock = nextBlocks[targetIndex];
    final targetOffset = targetIndex < index ? targetBlock.text.length : 0;

    _commit(
      after: _document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      label: label,
      operations: <TextOperation>[
        TextOperation(
          type: operationType,
          blockId: removed.id,
        ),
      ],
      origin: TextTransactionOrigin.user,
    );

    return TextSystemDocumentPosition(
      blockId: targetBlock.id,
      blockIndex: targetIndex,
      offset: targetOffset,
    );
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _resetTextEditBatchState();
    final transaction = _undoStack.removeLast();
    _redoStack.add(transaction);
    _document = transaction.before;
    _revision++;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _resetTextEditBatchState();
    final transaction = _redoStack.removeLast();
    _undoStack.add(transaction);
    _document = transaction.after;
    _revision++;
    notifyListeners();
  }

  void saveSnapshot({String? label}) {
    _snapshots.add(
      TextSystemSnapshot(
        document: _document,
        createdAt: DateTime.now(),
        label: label,
      ),
    );
    notifyListeners();
  }

  void restoreSnapshot(TextSystemSnapshot snapshot) {
    replaceDocument(
      snapshot.document,
      label: 'Restore snapshot',
      origin: TextTransactionOrigin.system,
    );
  }

  void _commitTextEdit({
    required String blockId,
    required String oldText,
    required String newText,
    required TextSystemDocument after,
  }) {
    if (identical(after, _document) || _documentsEquivalent(after, _document)) return;

    final now = DateTime.now();
    final operations = <TextOperation>[
      TextOperation(
        type: TextOperationType.replaceBlockText,
        blockId: blockId,
        text: newText,
      ),
    ];

    if (_canMergeTextEditIntoUndoHead(
      blockId: blockId,
      oldText: oldText,
      newText: newText,
      now: now,
    )) {
      final previous = _undoStack.removeLast();
      final merged = TextTransaction(
        id: previous.id,
        label: previous.label,
        before: previous.before,
        after: after,
        operations: operations,
        origin: previous.origin,
        createdAt: previous.createdAt,
      );

      _undoStack.add(merged);
      _replaceTransactionLogEntry(previous.id, merged);
      _document = after;
      _revision++;
      _redoStack.clear();
      _lastTextEditAt = now;
      _lastTextEditBlockId = blockId;
      _startNewTextEditBatchOnNextInsertion = _textEditShouldBreakAfter(oldText, newText);
      notifyListeners();
      return;
    }

    _commit(
      after: after,
      label: 'Edit text',
      operations: operations,
      origin: TextTransactionOrigin.user,
    );

    _lastTextEditAt = now;
    _lastTextEditBlockId = blockId;
    _startNewTextEditBatchOnNextInsertion = _textEditShouldBreakAfter(oldText, newText);
  }

  bool _canMergeTextEditIntoUndoHead({
    required String blockId,
    required String oldText,
    required String newText,
    required DateTime now,
  }) {
    if (_undoStack.isEmpty) return false;
    if (_lastTextEditBlockId != blockId || _lastTextEditAt == null) return false;
    if (now.difference(_lastTextEditAt!) > _textEditBatchWindow) return false;
    if (!_isSmallPlainTextEdit(oldText, newText)) return false;
    if (_startNewTextEditBatchOnNextInsertion && _isPlainTextInsertion(oldText, newText)) {
      return false;
    }

    final previous = _undoStack.last;
    if (previous.origin != TextTransactionOrigin.user ||
        previous.operations.length != 1 ||
        previous.operations.first.type != TextOperationType.replaceBlockText ||
        previous.operations.first.blockId != blockId ||
        !_documentsEquivalent(previous.after, _document)) {
      return false;
    }

    return true;
  }

  bool _isSmallPlainTextEdit(String oldText, String newText) {
    final prefix = _sharedPrefixLength(oldText, newText);
    final suffix = _sharedSuffixLength(oldText, newText, prefix);
    final removedLength = oldText.length - prefix - suffix;
    final insertedLength = newText.length - prefix - suffix;

    if (removedLength == 0 && insertedLength == 0) return false;

    return removedLength <= 8 && insertedLength <= 8;
  }

  bool _isPlainTextInsertion(String oldText, String newText) {
    final prefix = _sharedPrefixLength(oldText, newText);
    final suffix = _sharedSuffixLength(oldText, newText, prefix);
    final removedLength = oldText.length - prefix - suffix;
    final insertedLength = newText.length - prefix - suffix;
    return removedLength == 0 && insertedLength > 0;
  }

  bool _textEditShouldBreakAfter(String oldText, String newText) {
    if (!_isPlainTextInsertion(oldText, newText)) return false;

    final prefix = _sharedPrefixLength(oldText, newText);
    final suffix = _sharedSuffixLength(oldText, newText, prefix);
    final inserted = newText.substring(prefix, newText.length - suffix);
    if (inserted.isEmpty) return false;

    return inserted.runes.any(_isTypingUndoBoundaryRune);
  }

  bool _isTypingUndoBoundaryRune(int rune) {
    if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D) return true;
    const punctuation = <int>{
      0x2E, // .
      0x2C, // ,
      0x3B, // ;
      0x3A, // :
      0x21, // !
      0x3F, // ?
      0x29, // closing parenthesis
      0x5D, // closing bracket
      0x7D, // closing brace
    };
    return punctuation.contains(rune);
  }

  int _sharedPrefixLength(String left, String right) {
    var index = 0;
    while (index < left.length &&
        index < right.length &&
        left.codeUnitAt(index) == right.codeUnitAt(index)) {
      index++;
    }
    return index;
  }

  int _sharedSuffixLength(String left, String right, int prefixLength) {
    var suffix = 0;
    while (suffix < left.length - prefixLength &&
        suffix < right.length - prefixLength &&
        left.codeUnitAt(left.length - suffix - 1) ==
            right.codeUnitAt(right.length - suffix - 1)) {
      suffix++;
    }
    return suffix;
  }

  void _replaceTransactionLogEntry(String transactionId, TextTransaction transaction) {
    for (var i = _transactionLog.length - 1; i >= 0; i--) {
      if (_transactionLog[i].id == transactionId) {
        _transactionLog[i] = transaction;
        return;
      }
    }
    _transactionLog.add(transaction);
  }

  void _resetTextEditBatchState() {
    _lastTextEditAt = null;
    _lastTextEditBlockId = null;
    _startNewTextEditBatchOnNextInsertion = false;
  }

  void _commit({
    required TextSystemDocument after,
    required String label,
    required List<TextOperation> operations,
    required TextTransactionOrigin origin,
  }) {
    if (identical(after, _document) || _documentsEquivalent(after, _document)) return;

    final transaction = TextTransaction(
      id: 'tx-${++_transactionSeed}',
      label: label,
      before: _document,
      after: after,
      operations: operations,
      origin: origin,
    );

    _resetTextEditBatchState();
    _document = after;
    _revision++;
    _undoStack.add(transaction);
    _redoStack.clear();
    _transactionLog.add(transaction);
    notifyListeners();
  }





  TextSystemBlock _newPageBreakBlock({
    bool mergeAdjacentOnDelete = false,
    String? splitSourceBlockId,
  }) {
    final metadata = <String, Object?>{
      'kind': 'pageBreak',
      if (mergeAdjacentOnDelete) 'mergeAdjacentOnDelete': true,
      if (mergeAdjacentOnDelete) 'createdBy': 'splitBlockAtCaret',
      if (splitSourceBlockId != null) 'splitSourceBlockId': splitSourceBlockId,
    };

    return TextSystemBlock(
      id: _nextGeneratedBlockId('page-break'),
      type: TextSystemBlockType.divider,
      text: '',
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  bool _isFootnoteBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.custom && block.metadata['kind'] == 'footnote';
  }

  bool _isFootnoteReferenceMark(TextMark mark) {
    return mark.kind == TextMarkKind.link && mark.attributes['role'] == 'footnoteReference';
  }

  TextSystemDocument _renumberFootnotes(TextSystemDocument document) {
    final footnoteIdsByOrder = <String>[];
    final numbersByFootnoteId = <String, int>{};

    for (final block in document.blocks) {
      if (_isFootnoteBlock(block)) continue;
      for (final mark in block.marks) {
        if (!_isFootnoteReferenceMark(mark)) continue;
        final footnoteId = mark.attributes['footnoteId'];
        if (footnoteId == null || numbersByFootnoteId.containsKey(footnoteId)) continue;
        footnoteIdsByOrder.add(footnoteId);
        numbersByFootnoteId[footnoteId] = footnoteIdsByOrder.length;
      }
    }

    var changed = false;
    final nextBlocks = <TextSystemBlock>[];

    for (final block in document.blocks) {
      if (_isFootnoteBlock(block)) {
        final footnoteId = block.metadata['footnoteId'] as String?;
        final number = footnoteId == null ? null : numbersByFootnoteId[footnoteId];
        final nextMetadata = <String, Object?>{
          ...block.metadata,
          if (number != null) 'number': number,
        };
        final nextBlock = block.copyWith(metadata: Map<String, Object?>.unmodifiable(nextMetadata));
        changed = changed || !_metadataEquals(block.metadata, nextBlock.metadata);
        nextBlocks.add(nextBlock);
        continue;
      }

      final nextMarks = <TextMark>[];
      for (final mark in block.marks) {
        if (!_isFootnoteReferenceMark(mark)) {
          nextMarks.add(mark);
          continue;
        }

        final footnoteId = mark.attributes['footnoteId'];
        final number = footnoteId == null ? null : numbersByFootnoteId[footnoteId];
        final nextAttributes = <String, String>{
          ...mark.attributes,
          if (number != null) 'number': '$number',
        };
        final nextMark = mark.copyWith(attributes: Map<String, String>.unmodifiable(nextAttributes));
        changed = changed || mark.attributes['number'] != nextMark.attributes['number'];
        nextMarks.add(nextMark);
      }

      final nextBlock = block.copyWith(marks: nextMarks).normalizeMarks();
      nextBlocks.add(nextBlock);
    }

    return changed ? document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()) : document;
  }

  TextSystemBlock _newSectionBreakBlock({
    bool restartPageNumbering = true,
    int pageNumberStartAt = 1,
    bool mergeAdjacentOnDelete = false,
    String? splitSourceBlockId,
  }) {
    final safeStartAt = pageNumberStartAt < 1 ? 1 : pageNumberStartAt;
    final metadata = <String, Object?>{
      'kind': 'sectionBreak',
      'sectionBreakType': 'nextPage',
      'sectionId': _nextGeneratedBlockId('section'),
      'pageSetupMode': 'inherit',
      'restartPageNumbering': restartPageNumbering,
      'pageNumberStartAt': safeStartAt,
      if (mergeAdjacentOnDelete) 'mergeAdjacentOnDelete': true,
      if (mergeAdjacentOnDelete) 'createdBy': 'splitBlockAtCaret',
      if (splitSourceBlockId != null) 'splitSourceBlockId': splitSourceBlockId,
    };

    return TextSystemBlock(
      id: _nextGeneratedBlockId('section-break'),
      type: TextSystemBlockType.divider,
      text: '',
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
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

  TextSystemBlock _blockConvertedToType(
    TextSystemBlock block,
    TextSystemBlockType type, {
    int? level,
    bool? checked,
    Map<String, Object?>? metadata,
  }) {
    final nextLevel = type == TextSystemBlockType.heading ? (level ?? block.level ?? 1) : null;
    final nextChecked = type == TextSystemBlockType.todo ? (checked ?? block.checked ?? false) : null;
    final nextMetadata = switch (type) {
      TextSystemBlockType.listItem || TextSystemBlockType.todo => Map<String, Object?>.unmodifiable(
          metadata ?? _metadataForListGroupConversion(
            source: block,
            targetType: type,
            requestedMetadata: null,
            groupId: _listGroupIdFor(block) ?? _newListGroupId(),
          ),
        ),
      TextSystemBlockType.divider || TextSystemBlockType.custom =>
        Map<String, Object?>.unmodifiable(metadata ?? block.metadata),
      _ => metadata == null
          ? const <String, Object?>{}
          : Map<String, Object?>.unmodifiable(metadata),
    };

    return TextSystemBlock(
      id: block.id,
      type: type,
      text: block.text,
      marks: block.marks,
      level: nextLevel,
      checked: nextChecked,
      metadata: nextMetadata,
    ).normalizeMarks();
  }

  Map<String, Object?> _metadataForListGroupConversion({
    required TextSystemBlock source,
    required TextSystemBlockType targetType,
    required Map<String, Object?>? requestedMetadata,
    required String? groupId,
  }) {
    if (!_isListLikeType(targetType)) {
      return const <String, Object?>{};
    }

    final requested = requestedMetadata ?? const <String, Object?>{};
    final resolvedGroupId = groupId ?? _listGroupIdFor(source) ?? _newListGroupId();
    final ordered = requested['ordered'] == true ||
        (requested['ordered'] == null && source.type == TextSystemBlockType.listItem && source.metadata['ordered'] == true);
    final listKind = switch (targetType) {
      TextSystemBlockType.todo => 'todo',
      TextSystemBlockType.listItem => ordered ? 'numbered' : 'bullet',
      _ => 'list',
    };

    return <String, Object?>{
      ...requested,
      'listGroupId': resolvedGroupId,
      'listKind': listKind,
      if (targetType == TextSystemBlockType.listItem) 'ordered': ordered,
    };
  }

  Map<String, Object?> _listMetadataForSplit(TextSystemBlock block, TextSystemBlockType nextType) {
    if (!_isListLikeType(nextType)) return const <String, Object?>{};
    return _metadataForListGroupConversion(
      source: block,
      targetType: nextType,
      requestedMetadata: block.metadata,
      groupId: _listGroupIdFor(block) ?? _newListGroupId(),
    );
  }

  bool _isListLikeType(TextSystemBlockType type) {
    return type == TextSystemBlockType.listItem || type == TextSystemBlockType.todo;
  }

  bool _isListLikeBlock(TextSystemBlock block) => _isListLikeType(block.type);

  String? _listGroupIdFor(TextSystemBlock block) {
    final id = block.metadata['listGroupId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  String _newListGroupId() {
    return _nextGeneratedBlockId('list-group');
  }

  TextSystemRange _listGroupRangeFor(int blockIndex) {
    final block = _document.blocks[blockIndex];
    if (!_isListLikeBlock(block)) {
      return TextSystemRange(blockIndex, blockIndex + 1);
    }

    final groupId = _listGroupIdFor(block);
    var start = blockIndex;
    var end = blockIndex + 1;

    bool belongsToGroup(TextSystemBlock candidate) {
      if (!_isListLikeBlock(candidate)) return false;
      if (groupId != null) return _listGroupIdFor(candidate) == groupId;
      return true;
    }

    while (start > 0 && belongsToGroup(_document.blocks[start - 1])) {
      start--;
    }
    while (end < _document.blocks.length && belongsToGroup(_document.blocks[end])) {
      end++;
    }

    return TextSystemRange(start, end);
  }

  bool _canMergeListLikeBlocks(TextSystemBlock previous, TextSystemBlock current) {
    final previousGroupId = _listGroupIdFor(previous);
    final currentGroupId = _listGroupIdFor(current);
    if (previousGroupId != null || currentGroupId != null) {
      return previousGroupId != null && previousGroupId == currentGroupId;
    }

    if (previous.type != current.type) return false;
    if (previous.type == TextSystemBlockType.listItem) {
      return previous.metadata['ordered'] == current.metadata['ordered'];
    }
    return previous.type == TextSystemBlockType.todo;
  }

  bool _documentsEquivalent(TextSystemDocument left, TextSystemDocument right) {
    if (identical(left, right)) return true;
    if (left.id != right.id || left.title != right.title) return false;
    if (!_metadataEquals(left.metadata, right.metadata)) return false;
    return _blockListsEquivalent(left.blocks, right.blocks);
  }

  bool _blockListsEquivalent(List<TextSystemBlock> left, List<TextSystemBlock> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_blocksEquivalent(left[i], right[i])) return false;
    }
    return true;
  }

  bool _blocksEquivalent(TextSystemBlock left, TextSystemBlock right) {
    if (identical(left, right)) return true;
    if (left.id != right.id ||
        left.type != right.type ||
        left.text != right.text ||
        left.level != right.level ||
        left.checked != right.checked ||
        !_metadataEquals(left.metadata, right.metadata) ||
        left.marks.length != right.marks.length) {
      return false;
    }

    for (var i = 0; i < left.marks.length; i++) {
      if (left.marks[i] != right.marks[i]) return false;
    }
    return true;
  }

  bool _metadataEquals(Map<String, Object?> left, Map<String, Object?> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  String _nextGeneratedBlockId(String prefix) {
    return '$prefix-${_revision + 1}-${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _canMergeBlocks(TextSystemBlock previous, TextSystemBlock current) {
    return switch ((previous.type, current.type)) {
      (TextSystemBlockType.paragraph, TextSystemBlockType.paragraph) => true,
      (TextSystemBlockType.heading, TextSystemBlockType.heading) => previous.level == current.level,
      (TextSystemBlockType.quote, TextSystemBlockType.quote) => true,
      (TextSystemBlockType.code, TextSystemBlockType.code) => true,
      (TextSystemBlockType.listItem, TextSystemBlockType.listItem) =>
        _canMergeListLikeBlocks(previous, current),
      (TextSystemBlockType.todo, TextSystemBlockType.todo) =>
        _canMergeListLikeBlocks(previous, current),
      (TextSystemBlockType.paragraph, TextSystemBlockType.heading) => true,
      (TextSystemBlockType.heading, TextSystemBlockType.paragraph) => true,
      _ => false,
    };
  }

  List<TextMark> _marksForSplitPart({
    required List<TextMark> marks,
    required int start,
    required int end,
  }) {
    if (end <= start) return const <TextMark>[];
    final range = TextSystemRange(start, end);
    final nextMarks = <TextMark>[];
    for (final mark in marks) {
      final intersection = mark.range.intersection(range);
      if (intersection == null || intersection.isCollapsed) continue;
      nextMarks.add(mark.copyWith(range: intersection.relativeTo(start)));
    }
    return _clampMarks(nextMarks, end - start);
  }

  List<TextMark> _rebaseMarksForPlainTextReplace({
    required String oldText,
    required String newText,
    required List<TextMark> marks,
  }) {
    if (oldText == newText) return _clampMarks(marks, newText.length);

    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            newText.codeUnitAt(newText.length - suffix - 1)) {
      suffix++;
    }

    final removedRange = TextSystemRange(prefix, oldText.length - suffix);
    final insertedLength = newText.length - prefix - suffix;
    final insertedEnd = prefix + insertedLength;
    final delta = newText.length - oldText.length;
    final nextMarks = <TextMark>[];

    for (final mark in marks) {
      if (mark.range.end <= removedRange.start) {
        nextMarks.add(mark);
      } else if (mark.range.start >= removedRange.end) {
        nextMarks.add(mark.copyWith(range: mark.range.shift(delta)));
      } else if (mark.range.start < removedRange.start &&
          mark.range.end > removedRange.end) {
        nextMarks.add(
          mark.copyWith(
            range: TextSystemRange(mark.range.start, mark.range.end + delta),
          ),
        );
      } else if (mark.range.start < removedRange.start) {
        nextMarks.add(
          mark.copyWith(range: TextSystemRange(mark.range.start, removedRange.start)),
        );
      } else if (mark.range.end > removedRange.end) {
        nextMarks.add(
          mark.copyWith(range: TextSystemRange(insertedEnd, mark.range.end + delta)),
        );
      }
    }

    return _clampMarks(nextMarks, newText.length);
  }

  List<TextMark> _clampMarks(List<TextMark> marks, int textLength) {
    return marks
        .map((mark) => mark.clamp(textLength))
        .where((mark) => !mark.isEmpty)
        .toList()
      ..sort((a, b) {
        final startCompare = a.range.start.compareTo(b.range.start);
        if (startCompare != 0) return startCompare;
        return a.range.end.compareTo(b.range.end);
      });
  }

}
