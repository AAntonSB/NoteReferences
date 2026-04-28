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

@DriftDatabase(
  tables: [
    PdfDocuments,
    PdfSessions,
    Tags,
    DocumentTags,
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
  int get schemaVersion => 2;

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