import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class PdfDocuments extends Table {
  TextColumn get documentId => text()();

  TextColumn get filePath => text()();

  TextColumn get originalFileName => text()();

  TextColumn get name => text()();

  TextColumn get authors => text().nullable()();

  TextColumn get subject => text().nullable()();

  TextColumn get fieldOfStudy => text().nullable()();

  TextColumn get isbn => text().nullable()();

  TextColumn get doi => text().nullable()();

  TextColumn get issn => text().nullable()();

  TextColumn get arxivId => text().nullable()();

  TextColumn get journal => text().nullable()();

  TextColumn get publisher => text().nullable()();

  TextColumn get keywords => text().nullable()();

  DateTimeColumn get addedAt => dateTime()();

  DateTimeColumn get fileLastModifiedAt => dateTime().nullable()();

  DateTimeColumn get metadataLastEditedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {documentId};
}

class PdfSessions extends Table {
  TextColumn get documentId => text()();

  IntColumn get pageNumber => integer().withDefault(const Constant(1))();

  RealColumn get scrollX => real().withDefault(const Constant(0))();

  RealColumn get scrollY => real().withDefault(const Constant(0))();

  RealColumn get zoomLevel => real().withDefault(const Constant(1.0))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {documentId};
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().unique()();
}

class DocumentTags extends Table {
  TextColumn get documentId => text()();

  IntColumn get tagId => integer()();

  @override
  Set<Column> get primaryKey => {documentId, tagId};
}

/// Generic note object.
///
/// A note is intentionally abstract.
/// It may or may not be attached to a PDF/document/page/text selection.
class Notes extends Table {
  TextColumn get id => text()();

  /// Nullable because future notes may be free-standing project notes.
  TextColumn get documentId => text().nullable()();

  TextColumn get parentNoteId => text().nullable()();

  TextColumn get title => text().nullable()();

  /// Examples:
  /// note, question, summary, task, flashcard, citationNote
  TextColumn get noteType => text().withDefault(const Constant('note'))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Content blocks inside a note.
///
/// For now we only use:
/// blockType = text
/// contentText = user's note text
///
/// Later this can support images, drawings, citations, code, tables, etc.
class NoteBlocks extends Table {
  TextColumn get id => text()();

  TextColumn get noteId => text()();

  /// Examples:
  /// text, heading, quote, image, inkDrawing, math, code, table, citation
  TextColumn get blockType => text().withDefault(const Constant('text'))();

  TextColumn get contentText => text().nullable()();

  /// Reserved for structured future block data.
  TextColumn get contentJson => text().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Optional anchors that say what a note refers to.
///
/// A note can have zero, one, or many anchors.
/// This lets us support general notes, document notes, page notes,
/// selected-text notes, region notes, image notes, equation notes, etc.
class NoteAnchors extends Table {
  TextColumn get id => text()();

  TextColumn get noteId => text()();

  TextColumn get documentId => text().nullable()();

  /// Examples:
  /// document, page, textSelection, region, highlight, image, equation, table
  TextColumn get anchorType => text()();

  IntColumn get pageNumber => integer().nullable()();

  TextColumn get selectedText => text().nullable()();

  TextColumn get textBefore => text().nullable()();

  TextColumn get textAfter => text().nullable()();

  /// JSON-encoded PDF-space geometry.
  ///
  /// Example future shape:
  /// [
  ///   {"pageNumber": 3, "x": 72.4, "y": 412.8, "width": 315.2, "height": 14.1}
  /// ]
  TextColumn get geometryJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    PdfDocuments,
    PdfSessions,
    Tags,
    DocumentTags,
    Notes,
    NoteBlocks,
    NoteAnchors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : super(
          driftDatabase(
            name: 'note_references',
          ),
        );

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 3) {
          await migrator.createTable(notes);
          await migrator.createTable(noteBlocks);
          await migrator.createTable(noteAnchors);
        }
      },
    );
  }

  Future<List<PdfDocument>> getAllDocuments() {
    return select(pdfDocuments).get();
  }

  Stream<List<PdfDocument>> watchAllDocuments() {
    return select(pdfDocuments).watch();
  }

  Future<void> upsertDocument(PdfDocumentsCompanion document) {
    return into(pdfDocuments).insertOnConflictUpdate(document);
  }

  Future<PdfSession?> getPdfSession(String documentId) {
    return (select(pdfSessions)
          ..where((table) => table.documentId.equals(documentId)))
        .getSingleOrNull();
  }

  Future<void> upsertPdfSession(PdfSessionsCompanion session) {
    return into(pdfSessions).insertOnConflictUpdate(session);
  }
}