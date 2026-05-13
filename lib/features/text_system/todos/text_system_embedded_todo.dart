import 'package:flutter/foundation.dart';

import '../../notes/data/note_repository.dart';
import '../core/text_system_block.dart';

/// TextSystem-side metadata for a TODO block that is backed by the app's
/// existing TODO/note store.
///
/// The document owns the visual block. The TODO system owns task state such as
/// title, completion, priority, deadline, and future project/source links.
class TextSystemEmbeddedTodoMetadata {
  const TextSystemEmbeddedTodoMetadata({
    required this.todoId,
    required this.sourceDocumentId,
    required this.sourceBlockId,
    this.priority = kTodoPriorityMedium,
    this.deadline,
  });

  static const String embeddedFlagKey = 'embeddedTodo';
  static const String todoIdKey = 'todoId';
  static const String sourceDocumentIdKey = 'todoSourceDocumentId';
  static const String sourceBlockIdKey = 'todoSourceBlockId';
  static const String priorityKey = 'todoPriority';
  static const String deadlineKey = 'todoDeadline';
  static const String sourceKindKey = 'todoSourceKind';
  static const String sourceKindTextSystemDocument = 'textSystemDocument';

  final String todoId;
  final String sourceDocumentId;
  final String sourceBlockId;
  final String priority;
  final DateTime? deadline;

  bool get isValid => todoId.trim().isNotEmpty;

  Map<String, Object?> toBlockMetadata({
    Map<String, Object?> base = const <String, Object?>{},
  }) {
    return <String, Object?>{
      ...base,
      embeddedFlagKey: true,
      todoIdKey: todoId,
      sourceDocumentIdKey: sourceDocumentId,
      sourceBlockIdKey: sourceBlockId,
      sourceKindKey: sourceKindTextSystemDocument,
      priorityKey: priority,
      if (deadline != null) deadlineKey: deadline!.toIso8601String(),
    };
  }

  factory TextSystemEmbeddedTodoMetadata.fromBlock(TextSystemBlock block) {
    return TextSystemEmbeddedTodoMetadata.fromMetadata(block.metadata);
  }

  factory TextSystemEmbeddedTodoMetadata.fromMetadata(Map<String, Object?> metadata) {
    return TextSystemEmbeddedTodoMetadata(
      todoId: _stringValue(metadata[todoIdKey]) ?? '',
      sourceDocumentId: _stringValue(metadata[sourceDocumentIdKey]) ?? '',
      sourceBlockId: _stringValue(metadata[sourceBlockIdKey]) ?? '',
      priority: _normalizePriority(_stringValue(metadata[priorityKey])),
      deadline: _dateValue(metadata[deadlineKey]),
    );
  }

  static bool isEmbeddedTodoBlock(TextSystemBlock block) {
    return block.type == TextSystemBlockType.todo &&
        block.metadata[embeddedFlagKey] == true &&
        (_stringValue(block.metadata[todoIdKey])?.isNotEmpty ?? false);
  }

  static TextSystemBlock createBlock({
    required String blockId,
    required String documentId,
    required String todoId,
    required String title,
    String priority = kTodoPriorityMedium,
    DateTime? deadline,
    bool isCompleted = false,
    Map<String, Object?> baseMetadata = const <String, Object?>{},
  }) {
    final metadata = TextSystemEmbeddedTodoMetadata(
      todoId: todoId,
      sourceDocumentId: documentId,
      sourceBlockId: blockId,
      priority: _normalizePriority(priority),
      deadline: deadline,
    );

    return TextSystemBlock(
      id: blockId,
      type: TextSystemBlockType.todo,
      text: _cleanTitle(title),
      checked: isCompleted,
      metadata: Map<String, Object?>.unmodifiable(
        metadata.toBlockMetadata(base: baseMetadata),
      ),
    );
  }
}

@immutable
class TextSystemEmbeddedTodoSnapshot {
  const TextSystemEmbeddedTodoSnapshot({
    required this.blockId,
    required this.todoId,
    required this.title,
    required this.isCompleted,
    required this.priority,
    this.deadline,
  });

  final String blockId;
  final String todoId;
  final String title;
  final bool isCompleted;
  final String priority;
  final DateTime? deadline;

  factory TextSystemEmbeddedTodoSnapshot.fromBlock(TextSystemBlock block) {
    final metadata = TextSystemEmbeddedTodoMetadata.fromBlock(block);
    return TextSystemEmbeddedTodoSnapshot(
      blockId: block.id,
      todoId: metadata.todoId,
      title: _cleanTitle(block.text),
      isCompleted: block.checked == true,
      priority: _normalizePriority(metadata.priority),
      deadline: metadata.deadline,
    );
  }

  bool sameTodoState(TextSystemEmbeddedTodoSnapshot other) {
    return todoId == other.todoId &&
        title == other.title &&
        isCompleted == other.isCompleted &&
        priority == other.priority &&
        _sameDate(deadline, other.deadline);
  }

  @override
  bool operator ==(Object other) {
    return other is TextSystemEmbeddedTodoSnapshot &&
        blockId == other.blockId &&
        todoId == other.todoId &&
        title == other.title &&
        isCompleted == other.isCompleted &&
        priority == other.priority &&
        _sameDate(deadline, other.deadline);
  }

  @override
  int get hashCode => Object.hash(
        blockId,
        todoId,
        title,
        isCompleted,
        priority,
        deadline?.millisecondsSinceEpoch,
      );
}

class TextSystemEmbeddedTodoRepository {
  const TextSystemEmbeddedTodoRepository({required NoteRepository noteRepository})
      : _noteRepository = noteRepository;

  final NoteRepository _noteRepository;

  Future<String> createTodoForDocumentBlock({
    required String documentId,
    required String blockId,
    required String title,
    String priority = kTodoPriorityMedium,
    DateTime? deadline,
  }) async {
    return _noteRepository.createDocumentNoteTodo(
      documentId: documentId,
      documentNoteId: documentId,
      documentNodeId: blockId,
      title: _cleanTitle(title),
      priority: _normalizePriority(priority),
      deadline: deadline,
    );
  }

  Future<void> syncSnapshot(TextSystemEmbeddedTodoSnapshot snapshot) async {
    if (snapshot.todoId.trim().isEmpty) return;

    await _noteRepository.updateTodoTitle(
      todoId: snapshot.todoId,
      title: snapshot.title,
    );
    await _noteRepository.updateTodoCompleted(
      todoId: snapshot.todoId,
      isCompleted: snapshot.isCompleted,
    );
    await _noteRepository.updateTodoPriority(
      todoId: snapshot.todoId,
      priority: snapshot.priority,
    );
    await _noteRepository.updateTodoDeadline(
      todoId: snapshot.todoId,
      deadline: snapshot.deadline,
    );
  }
}

String _cleanTitle(String value) {
  final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.isEmpty ? 'New TODO' : clean;
}

String _normalizePriority(String? value) {
  switch (value) {
    case kTodoPriorityLow:
    case kTodoPriorityHigh:
      return value!;
    case kTodoPriorityMedium:
    default:
      return kTodoPriorityMedium;
  }
}

String? _stringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

DateTime? _dateValue(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

bool _sameDate(DateTime? left, DateTime? right) {
  return left?.millisecondsSinceEpoch == right?.millisecondsSinceEpoch;
}
