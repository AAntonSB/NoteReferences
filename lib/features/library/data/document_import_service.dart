import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/database/app_database.dart';
import 'pdf_metadata_extractor.dart';

class DocumentImportService {
  final AppDatabase database;
  final PdfMetadataExtractor metadataExtractor;

  DocumentImportService({
    required this.database,
    required this.metadataExtractor,
  });

  Future<PdfDocument> importPdf(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    final documentId = sha256.convert(bytes).toString();

    final appDir = await getApplicationDocumentsDirectory();
    final pdfCacheDir = Directory(p.join(appDir.path, 'pdf_cache'));

    if (!await pdfCacheDir.exists()) {
      await pdfCacheDir.create(recursive: true);
    }

    final cachedFile = File(p.join(pdfCacheDir.path, '$documentId.pdf'));

    if (!await cachedFile.exists()) {
      await sourceFile.copy(cachedFile.path);
    }

    final metadata = await metadataExtractor.extract(cachedFile);
    final fileStat = await cachedFile.stat();

    final fallbackName = p.basenameWithoutExtension(sourceFile.path);
    final displayName = metadata.title ?? fallbackName;

    await database.upsertDocument(
      PdfDocumentsCompanion(
        documentId: Value(documentId),
        filePath: Value(cachedFile.path),
        originalFileName: Value(p.basename(sourceFile.path)),
        name: Value(displayName),
        authors: Value(metadata.authors),
        subject: Value(metadata.subject),
        keywords: Value(metadata.keywords),
        addedAt: Value(DateTime.now()),
        fileLastModifiedAt: Value(fileStat.modified),
        metadataLastEditedAt: Value(DateTime.now()),
      ),
    );

    final document = await (database.select(database.pdfDocuments)
          ..where((table) => table.documentId.equals(documentId)))
        .getSingle();

    return document;
  }
}