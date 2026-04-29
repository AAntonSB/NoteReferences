import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../infrastructure/database/app_database.dart';

class PdfSourceRect {
  final int pageNumber;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PdfSourceRect({
    required this.pageNumber,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory PdfSourceRect.fromJson(Map<String, dynamic> json) {
    return PdfSourceRect(
      pageNumber: _readInt(json['pageNumber']) ?? 1,
      left: _readDouble(json['left']) ?? 0,
      top: _readDouble(json['top']) ?? 0,
      right: _readDouble(json['right']) ?? 0,
      bottom: _readDouble(json['bottom']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageNumber': pageNumber,
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    };
  }

  bool get isValid {
    return pageNumber > 0 &&
        right != left &&
        top != bottom &&
        left.isFinite &&
        top.isFinite &&
        right.isFinite &&
        bottom.isFinite;
  }

  static List<PdfSourceRect> listFromGeometryJson(String? geometryJson) {
    final geometry = _decodeGeometry(geometryJson);
    final rawRects = geometry['sourceRects'];

    if (rawRects is! List) {
      return const [];
    }

    return rawRects
        .whereType<Map>()
        .map((item) {
          return PdfSourceRect.fromJson(
            item.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
        })
        .where((rect) => rect.isValid)
        .toList();
  }

  static Map<String, dynamic> _decodeGeometry(String? geometryJson) {
    if (geometryJson == null || geometryJson.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(geometryJson);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return {};
    }

    return {};
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

class NoteMetadata {
  final List<String> tags;
  final String status;
  final String importance;
  final bool highlightEnabled;

  const NoteMetadata({
    this.tags = const [],
    this.status = 'none',
    this.importance = 'normal',
    this.highlightEnabled = false,
  });

  factory NoteMetadata.fromAnchor(NoteAnchor anchor) {
    final geometry = _decodeGeometry(anchor.geometryJson);
    final sourceRects = PdfSourceRect.listFromGeometryJson(anchor.geometryJson);
    final rawMetadata = geometry['metadata'];

    if (rawMetadata is! Map) {
      return NoteMetadata(
        highlightEnabled: sourceRects.isNotEmpty,
      );
    }

    final metadata = rawMetadata.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    final rawTags = metadata['tags'];
    final tags = rawTags is List
        ? rawTags
            .whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList()
        : const <String>[];

    return NoteMetadata(
      tags: tags,
      status: _readString(metadata['status']) ?? 'none',
      importance: _readString(metadata['importance']) ?? 'normal',
      highlightEnabled:
          _readBool(metadata['highlightEnabled']) ?? sourceRects.isNotEmpty,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tags': tags,
      'status': status,
      'importance': importance,
      'highlightEnabled': highlightEnabled,
    };
  }

  NoteMetadata copyWith({
    List<String>? tags,
    String? status,
    String? importance,
    bool? highlightEnabled,
  }) {
    return NoteMetadata(
      tags: tags ?? this.tags,
      status: status ?? this.status,
      importance: importance ?? this.importance,
      highlightEnabled: highlightEnabled ?? this.highlightEnabled,
    );
  }

  static Map<String, dynamic> _decodeGeometry(String? geometryJson) {
    if (geometryJson == null || geometryJson.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(geometryJson);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return {};
    }

    return {};
  }

  static String? _readString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return null;
  }

  static bool? _readBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return bool.tryParse(value);
    return null;
  }
}

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
        width: 0.42,
      );
    }

    try {
      final decoded = jsonDecode(anchor.geometryJson!) as Map<String, dynamic>;

      return SidecarNotePlacement(
        pageNumber: _readInt(decoded['pageNumber']) ?? fallbackPage,
        x: _readDouble(decoded['x']) ?? 0.08,
        y: _readDouble(decoded['y']) ?? 0.12,
        width: _readDouble(decoded['width']) ?? 0.42,
      );
    } catch (_) {
      return SidecarNotePlacement(
        pageNumber: fallbackPage,
        x: 0.08,
        y: 0.12,
        width: 0.42,
      );
    }
  }

  String toJsonString({
    List<PdfSourceRect> sourceRects = const [],
    NoteMetadata? metadata,
  }) {
    return jsonEncode({
      'placementType': 'sidecar',
      'pageNumber': pageNumber,
      'x': x,
      'y': y,
      'width': width,
      if (sourceRects.isNotEmpty)
        'sourceRects': [
          for (final rect in sourceRects) rect.toJson(),
        ],
      if (metadata != null) 'metadata': metadata.toJson(),
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

  String get noteType => note.noteType;

  SidecarNotePlacement get sidecarPlacement {
    return SidecarNotePlacement.fromAnchor(anchor);
  }

  List<PdfSourceRect> get sourceRects {
    return PdfSourceRect.listFromGeometryJson(anchor.geometryJson);
  }

  NoteMetadata get metadata {
    return NoteMetadata.fromAnchor(anchor);
  }
}

class PdfLinkedHighlightRegion {
  final String noteId;
  final String anchorId;
  final String anchorType;
  final String noteType;
  final bool hasSidecarNote;
  final List<PdfSourceRect> sourceRects;

  const PdfLinkedHighlightRegion({
    required this.noteId,
    required this.anchorId,
    required this.anchorType,
    required this.noteType,
    required this.hasSidecarNote,
    required this.sourceRects,
  });
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

  Stream<List<PdfLinkedHighlightRegion>> watchPersistentHighlightRegionsForDocument({
    required String documentId,
  }) {
    final query = database.select(database.noteAnchors).join([
      innerJoin(
        database.notes,
        database.notes.id.equalsExp(database.noteAnchors.noteId),
      ),
    ]);

    query.where(
      database.noteAnchors.documentId.equals(documentId) &
          database.notes.isArchived.equals(false),
    );

    return query.watch().map((rows) {
      final regions = <PdfLinkedHighlightRegion>[];

      for (final row in rows) {
        final anchor = row.readTable(database.noteAnchors);
        final note = row.readTable(database.notes);
        final sourceRects = PdfSourceRect.listFromGeometryJson(
          anchor.geometryJson,
        );

        if (sourceRects.isEmpty) {
          continue;
        }

        if (anchor.anchorType == 'pdfHighlight') {
          regions.add(
            PdfLinkedHighlightRegion(
              noteId: note.id,
              anchorId: anchor.id,
              anchorType: anchor.anchorType,
              noteType: note.noteType,
              hasSidecarNote: false,
              sourceRects: sourceRects,
            ),
          );
          continue;
        }

        if (anchor.anchorType == 'sidecarPosition') {
          final metadata = NoteMetadata.fromAnchor(anchor);

          if (metadata.highlightEnabled || note.noteType == 'citation') {
            regions.add(
              PdfLinkedHighlightRegion(
                noteId: note.id,
                anchorId: anchor.id,
                anchorType: anchor.anchorType,
                noteType: note.noteType,
                hasSidecarNote: true,
                sourceRects: sourceRects,
              ),
            );
          }
        }
      }

      return regions;
    });
  }

  Stream<List<PdfSourceRect>> watchPersistentHighlightRectsForDocument({
    required String documentId,
  }) {
    return watchPersistentHighlightRegionsForDocument(
      documentId: documentId,
    ).map((regions) {
      return [
        for (final region in regions) ...region.sourceRects,
      ];
    });
  }

  Future<NoteWithAnchor> createSidecarTextNote({
    required String documentId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
    String noteType = 'note',
    String? selectedText,
    List<PdfSourceRect> sourceRects = const [],
  }) async {
    final now = DateTime.now();

    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final anchorId = _uuid.v4();

    final cleanSelectedText = _cleanOptionalText(selectedText);
    final cleanSourceRects = sourceRects.where((rect) => rect.isValid).toList();

    final placement = SidecarNotePlacement(
      pageNumber: pageNumber,
      x: x.clamp(0.0, 1.0).toDouble(),
      y: y.clamp(0.0, 1.0).toDouble(),
      width: width.clamp(0.15, 1.0).toDouble(),
    );

    final metadata = NoteMetadata(
      highlightEnabled: cleanSourceRects.isNotEmpty,
    );

    await database.transaction(() async {
      await database.into(database.notes).insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              noteType: Value(_normalizeNoteType(noteType)),
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
              geometryJson: Value(
                placement.toJsonString(
                  sourceRects: cleanSourceRects,
                  metadata: metadata,
                ),
              ),
              createdAt: now,
            ),
          );
    });

    return _getSidecarNote(noteId);
  }

  Future<void> createPersistentHighlight({
    required String documentId,
    required int pageNumber,
    required String? selectedText,
    required List<PdfSourceRect> sourceRects,
  }) async {
    final cleanSourceRects = sourceRects.where((rect) => rect.isValid).toList();

    if (cleanSourceRects.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final noteId = _uuid.v4();
    final anchorId = _uuid.v4();

    await database.transaction(() async {
      await database.into(database.notes).insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              noteType: const Value('highlight'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database.into(database.noteAnchors).insert(
            NoteAnchorsCompanion.insert(
              id: anchorId,
              noteId: noteId,
              documentId: Value(documentId),
              anchorType: 'pdfHighlight',
              pageNumber: Value(pageNumber),
              selectedText: Value(_cleanOptionalText(selectedText)),
              geometryJson: Value(
                jsonEncode({
                  'sourceRects': [
                    for (final rect in cleanSourceRects) rect.toJson(),
                  ],
                  'metadata': const NoteMetadata(
                    highlightEnabled: true,
                  ).toJson(),
                }),
              ),
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

  Future<void> updateNoteType({
    required String noteId,
    required String noteType,
  }) async {
    await (database.update(database.notes)
          ..where((table) => table.id.equals(noteId)))
        .write(
      NotesCompanion(
        noteType: Value(_normalizeNoteType(noteType)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateNoteMetadata({
    required String anchorId,
    required NoteMetadata metadata,
  }) async {
    final existingAnchor = await (database.select(database.noteAnchors)
          ..where((table) => table.id.equals(anchorId)))
        .getSingleOrNull();

    if (existingAnchor == null) {
      return;
    }

    final geometry = _decodeGeometry(existingAnchor.geometryJson);
    geometry['metadata'] = metadata.toJson();

    await (database.update(database.noteAnchors)
          ..where((table) => table.id.equals(anchorId)))
        .write(
      NoteAnchorsCompanion(
        geometryJson: Value(jsonEncode(geometry)),
      ),
    );

    await (database.update(database.notes)
          ..where((table) => table.id.equals(existingAnchor.noteId)))
        .write(
      NotesCompanion(
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> moveSidecarNote({
    required String anchorId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
  }) async {
    final existingAnchor = await (database.select(database.noteAnchors)
          ..where((table) => table.id.equals(anchorId)))
        .getSingleOrNull();

    final geometry = _decodeGeometry(existingAnchor?.geometryJson);

    geometry['placementType'] = 'sidecar';
    geometry['pageNumber'] = pageNumber;
    geometry['x'] = x.clamp(0.0, 1.0).toDouble();
    geometry['y'] = y.clamp(0.0, 1.0).toDouble();
    geometry['width'] = width.clamp(0.15, 1.0).toDouble();

    await (database.update(database.noteAnchors)
          ..where((table) => table.id.equals(anchorId)))
        .write(
      NoteAnchorsCompanion(
        pageNumber: Value(pageNumber),
        geometryJson: Value(jsonEncode(geometry)),
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

  String _normalizeNoteType(String value) {
    final normalized = value.trim();

    switch (normalized) {
      case 'question':
      case 'summary':
      case 'definition':
      case 'task':
      case 'citation':
      case 'highlight':
      case 'note':
        return normalized;
      default:
        return 'note';
    }
  }

  String? _cleanOptionalText(String? value) {
    if (value == null) return null;

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic> _decodeGeometry(String? geometryJson) {
    if (geometryJson == null || geometryJson.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(geometryJson);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return {};
    }

    return {};
  }
}