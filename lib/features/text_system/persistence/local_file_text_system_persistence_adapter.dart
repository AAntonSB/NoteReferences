import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/text_system_document.dart';
import 'text_system_persistence_adapter.dart';

/// Local JSON-backed persistence for TextSystem documents.
///
/// This is intentionally small and file-based: it gives Premium Writer real
/// save/load behavior now, while keeping the final storage boundary open for a
/// future SQLite/sync-backed document repository.
class LocalFileTextSystemPersistenceAdapter implements TextSystemPersistenceAdapter {
  const LocalFileTextSystemPersistenceAdapter({
    this.folderName = 'text_system_documents',
  });

  final String folderName;

  @override
  Future<TextSystemDocument?> loadTextDocument(String documentId) async {
    final file = await _fileForDocumentId(documentId);
    if (!await file.exists()) return null;

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;

    return TextSystemDocument.fromJson(
      decoded.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?)),
    );
  }

  @override
  Future<void> saveTextDocument(TextSystemDocument document) async {
    final file = await _fileForDocumentId(document.id);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(document.toJson()), flush: true);
  }

  Future<File> _fileForDocumentId(String documentId) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeId = _safeFileName(documentId);
    return File('${directory.path}${Platform.pathSeparator}$folderName${Platform.pathSeparator}$safeId.json');
  }

  static String _safeFileName(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'_+'), '_').trim();
    return safe.isEmpty ? 'document' : safe;
  }
}
