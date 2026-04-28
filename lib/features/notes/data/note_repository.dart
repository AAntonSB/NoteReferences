import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../infrastructure/database/app_database.dart';

class SidecarNotePlacement {
  final int pageNumber;
  final double x;
  final double y;
  final double width;

  const SidecarNotePlacement({
    required this.pageNumber,
    required this.x,
    required this.y,
    required this.width,
  });

  factory SidecarNotePlacement.fromAnchor(NoteAnchor anchor) {
    final fallbackPage = anchor.pageNumber ?? 1;

    if (anchor.geometryJson == null || anchor.geometryJson!.trim().isEmpty) {
      return SidecarNotePlacement(
        pageNumber: fallbackPage,
        x: 0.08,
        y: 0.12,
        width: 0.78,
      );
    }

    try {
      final decoded = jsonDecode(anchor.geometryJson!) as Map<String, dynamic>;

      return SidecarNotePlacement(
        pageNumber: _readInt(decoded['pageNumber']) ?? fallbackPage,
        x: _readDouble(decoded['x']) ?? 0.08,
        y: _readDouble(decoded['y']) ?? 0.12,
        width: _readDouble(decoded['width']) ?? 0.78,
      );
    } catch (_) {
      return SidecarNotePlacement(
        pageNumber: fallbackPage,
        x: 0.08,
        y: 0.12,
        width: 0.78,
      );
    }
  }

  String toJsonString() {
    return jsonEncode({
      'placementType': 'sidecar',
      'pageNumber': pageNumber,
      'x': x,
      'y': y,
      'width': width,
    });
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

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

  SidecarNotePlacement get sidecarPlacement {
    return SidecarNotePlacement.fromAnchor(anchor);
  }
}

class NoteRepository {
  final AppDatabase database;
  final Uuid _uuid = const Uuid();

  NoteRepository(this.database);

  Stream<List<NoteWithAnchor>> watchSidecarNotesForDocument({
    required String documentId,
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
          database.noteAnchors.anchorType.equals('sidecarPosition') &
          database.notes.isArchived.equals(false),
    );

    query.orderBy([
      OrderingTerm.asc(database.noteAnchors.pageNumber),
      OrderingTerm.asc(database.noteAnchors.createdAt),
      OrderingTerm.asc(database.noteBlocks.sortOrder),
    ]);

    return query.watch().map((rows) {
      final items = <NoteWithAnchor>[];

      for (final row in rows) {
        items.add(
          NoteWithAnchor(
            anchor: row.readTable(database.noteAnchors),
            note: row.readTable(database.notes),
            firstBlock: row.readTableOrNull(database.noteBlocks),
          ),
        );
      }

      return items;
    });
  }

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

  Future<NoteWithAnchor> createSidecarTextNote({
    required String documentId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
    String? selectedText,
  }) async {
    final now = DateTime.now();

    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final anchorId = _uuid.v4();

    final cleanSelectedText = _cleanOptionalText(selectedText);

    final placement = SidecarNotePlacement(
      pageNumber: pageNumber,
      x: x.clamp(0.0, 1.0).toDouble(),
      y: y.clamp(0.0, 1.0).toDouble(),
      width: width.clamp(0.15, 1.0).toDouble(),
    );

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
              noteId: noteId,
              blockType: const Value('text'),
              contentText: const Value(''),
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
              anchorType: 'sidecarPosition',
              pageNumber: Value(pageNumber),
              selectedText: Value(cleanSelectedText),
              geometryJson: Value(placement.toJsonString()),
              createdAt: now,
            ),
          );
    });

    return _getSidecarNote(noteId);
  }

  Future<void> updateTextBlock({
    required String noteId,
    required String blockId,
    required String body,
  }) async {
    final now = DateTime.now();

    await database.transaction(() async {
      await (database.update(database.noteBlocks)
            ..where((table) => table.id.equals(blockId)))
          .write(
        NoteBlocksCompanion(
          contentText: Value(body),
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

  Future<void> moveSidecarNote({
    required String anchorId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
  }) async {
    final placement = SidecarNotePlacement(
      pageNumber: pageNumber,
      x: x.clamp(0.0, 1.0).toDouble(),
      y: y.clamp(0.0, 1.0).toDouble(),
      width: width.clamp(0.15, 1.0).toDouble(),
    );

    await (database.update(database.noteAnchors)
          ..where((table) => table.id.equals(anchorId)))
        .write(
      NoteAnchorsCompanion(
        pageNumber: Value(pageNumber),
        geometryJson: Value(placement.toJsonString()),
      ),
    );
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

  Future<void> archiveNoteIfEmpty({
    required String noteId,
    required String blockId,
  }) async {
    final block = await (database.select(database.noteBlocks)
          ..where((table) => table.id.equals(blockId)))
        .getSingleOrNull();

    final text = block?.contentText?.trim() ?? '';

    if (text.isEmpty) {
      await archiveNote(noteId);
    }
  }

  Future<NoteWithAnchor> _getSidecarNote(String noteId) async {
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
      database.noteAnchors.noteId.equals(noteId) &
          database.noteAnchors.anchorType.equals('sidecarPosition') &
          database.notes.isArchived.equals(false),
    );

    final row = await query.getSingle();

    return NoteWithAnchor(
      anchor: row.readTable(database.noteAnchors),
      note: row.readTable(database.notes),
      firstBlock: row.readTableOrNull(database.noteBlocks),
    );
  }

  String? _cleanOptionalText(String? value) {
    if (value == null) return null;

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}