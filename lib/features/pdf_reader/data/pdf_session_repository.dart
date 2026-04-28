import 'package:drift/drift.dart';

import '../../../infrastructure/database/app_database.dart';

class PdfSessionRepository {
  final AppDatabase database;

  PdfSessionRepository(this.database);

  Future<PdfSession?> getSession(String documentId) {
    return database.getPdfSession(documentId);
  }

  Future<void> saveSession({
    required String documentId,
    required String filePath,
    required int pageNumber,
    required double scrollX,
    required double scrollY,
    required double zoomLevel,
  }) {
    return database.upsertPdfSession(
      PdfSessionsCompanion(
        documentId: Value(documentId),
        filePath: Value(filePath),
        pageNumber: Value(pageNumber),
        scrollX: Value(scrollX),
        scrollY: Value(scrollY),
        zoomLevel: Value(zoomLevel),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}