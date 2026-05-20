import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/epub_library_document.dart';

class EpubLibraryRepository {
  Future<List<EpubLibraryDocument>> loadDocuments() async {
    final indexFile = await _indexFile();
    if (!await indexFile.exists()) return const <EpubLibraryDocument>[];
    try {
      final raw = jsonDecode(await indexFile.readAsString());
      if (raw is! List) return const <EpubLibraryDocument>[];
      final documents = raw
          .whereType<Map>()
          .map((json) => EpubLibraryDocument.fromJson(json.cast<String, Object?>()))
          .where((document) => document.documentId.isNotEmpty && document.filePath.isNotEmpty)
          .toList();
      documents.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return documents;
    } catch (_) {
      return const <EpubLibraryDocument>[];
    }
  }

  Future<void> upsertDocument(EpubLibraryDocument document) async {
    final documents = await loadDocuments();
    final next = <EpubLibraryDocument>[];
    var replaced = false;
    for (final existing in documents) {
      if (existing.documentId == document.documentId) {
        next.add(document);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(document);
    next.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    await _write(next);
  }

  Future<void> deleteDocument(String documentId) async {
    final documents = await loadDocuments();
    await _write(documents.where((document) => document.documentId != documentId).toList(growable: false));
  }

  Future<File> _indexFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(appDir.path, 'reader_library'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return File(p.join(directory.path, 'epub_documents.json'));
  }

  Future<void> _write(List<EpubLibraryDocument> documents) async {
    final indexFile = await _indexFile();
    final encoded = const JsonEncoder.withIndent('  ').convert(
      documents.map((document) => document.toJson()).toList(growable: false),
    );
    await indexFile.writeAsString(encoded);
  }
}
