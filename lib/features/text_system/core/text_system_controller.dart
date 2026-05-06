import 'package:flutter/foundation.dart';

import 'text_clipboard_fragment.dart';
import 'text_system_document_fragment.dart';
import 'text_system_document_fragment_edit.dart';
import 'text_system_document_fragment_ops.dart';
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

    _commit(
      after: _document.replaceBlock(nextBlock),
      label: 'Edit text',
      operations: <TextOperation>[
        TextOperation(
          type: TextOperationType.replaceBlockText,
          blockId: blockId,
          text: text,
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

  void undo() {
    if (_undoStack.isEmpty) return;
    final transaction = _undoStack.removeLast();
    _redoStack.add(transaction);
    _document = transaction.before;
    _revision++;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
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

  void _commit({
    required TextSystemDocument after,
    required String label,
    required List<TextOperation> operations,
    required TextTransactionOrigin origin,
  }) {
    if (identical(after, _document)) return;

    final transaction = TextTransaction(
      id: 'tx-${++_transactionSeed}',
      label: label,
      before: _document,
      after: after,
      operations: operations,
      origin: origin,
    );

    _document = after;
    _revision++;
    _undoStack.add(transaction);
    _redoStack.clear();
    _transactionLog.add(transaction);
    notifyListeners();
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
