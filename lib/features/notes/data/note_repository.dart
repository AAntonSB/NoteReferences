import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../infrastructure/database/app_database.dart';

class NoteWithAnchor {
  final Note note;
  final NoteBlock? firstBlock;
  final NoteAnchor anchor;

  const NoteWithAnchor({
    required this.note,
    required this.firstBlock,
    required this.anchor,
  });

  String get body => firstBlock?.contentText ?? '';
}

class NoteRepository {
  final AppDatabase database;
  final Uuid _uuid = const Uuid();

  NoteRepository(this.database);

  Stream<List<NoteWithAnchor>> watchNotesForPage({
    required String documentId,
    required int pageNumber,
  }) {
    final query = database.select(database.noteAnchors).join([
      innerJoin(
        database.notes,
        database.notes.id.equalsExp(database.noteAnchors.noteId),
      ),
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
    ]);

    query.where(
      database.noteAnchors.documentId.equals(documentId) &
          database.noteAnchors.pageNumber.equals(pageNumber) &
          database.notes.isArchived.equals(false),
    );

    query.orderBy([
      OrderingTerm.asc(database.noteAnchors.createdAt),
      OrderingTerm.asc(database.noteBlocks.sortOrder),
    ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return NoteWithAnchor(
          anchor: row.readTable(database.noteAnchors),
          note: row.readTable(database.notes),
          firstBlock: row.readTableOrNull(database.noteBlocks),
        );
      }).toList();
    });
  }

  Future<void> createTextNoteForPage({
    required String documentId,
    required int pageNumber,
    required String body,
    String? selectedText,
    String? textBefore,
    String? textAfter,
    String? geometryJson,
  }) async {
    final trimmedBody = body.trim();

    if (trimmedBody.isEmpty) {
      return;
    }

    final now = DateTime.now();

    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final anchorId = _uuid.v4();

    final cleanSelectedText = _cleanOptionalText(selectedText);
    final cleanTextBefore = _cleanOptionalText(textBefore);
    final cleanTextAfter = _cleanOptionalText(textAfter);

    final anchorType = cleanSelectedText == null ? 'page' : 'textSelection';

    await database.transaction(() async {
      await database.into(database.notes).insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              noteType: const Value('note'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database.into(database.noteBlocks).insert(
            NoteBlocksCompanion.insert(
              id: blockId,
              noteId: blockId == noteId ? noteId : noteId,
              blockType: const Value('text'),
              contentText: Value(trimmedBody),
              sortOrder: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database.into(database.noteAnchors).insert(
            NoteAnchorsCompanion.insert(
              id: anchorId,
              noteId: noteId,
              documentId: Value(documentId),
              anchorType: anchorType,
              pageNumber: Value(pageNumber),
              selectedText: Value(cleanSelectedText),
              textBefore: Value(cleanTextBefore),
              textAfter: Value(cleanTextAfter),
              geometryJson: Value(_cleanOptionalText(geometryJson)),
              createdAt: now,
            ),
          );
    });
  }

  Future<void> updateTextBlock({
    required String noteId,
    required String blockId,
    required String body,
  }) async {
    final trimmedBody = body.trim();
    final now = DateTime.now();

    await database.transaction(() async {
      await (database.update(database.noteBlocks)
            ..where((table) => table.id.equals(blockId)))
          .write(
        NoteBlocksCompanion(
          contentText: Value(trimmedBody),
          updatedAt: Value(now),
        ),
      );

      await (database.update(database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(
        NotesCompanion(
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> archiveNote(String noteId) async {
    await (database.update(database.notes)
          ..where((table) => table.id.equals(noteId)))
        .write(
      NotesCompanion(
        isArchived: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  String? _cleanOptionalText(String? value) {
    if (value == null) return null;

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}