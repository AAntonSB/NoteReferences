import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/epub_library_document.dart';
import 'epub_library_repository.dart';
import 'epub_metadata_extractor.dart';

class EpubImportService {
  final EpubLibraryRepository repository;
  final EpubMetadataExtractor metadataExtractor;

  const EpubImportService({
    required this.repository,
    required this.metadataExtractor,
  });

  Future<EpubLibraryDocument> importEpub(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    final documentId = sha256.convert(bytes).toString();

    final appDir = await getApplicationDocumentsDirectory();
    final epubCacheDir = Directory(p.join(appDir.path, 'epub_cache'));
    if (!await epubCacheDir.exists()) {
      await epubCacheDir.create(recursive: true);
    }

    final cachedFile = File(p.join(epubCacheDir.path, '$documentId.epub'));
    if (!await cachedFile.exists()) {
      await sourceFile.copy(cachedFile.path);
    }

    final metadata = await metadataExtractor.extract(cachedFile);
    final fileStat = await cachedFile.stat();
    final fallbackName = p.basenameWithoutExtension(sourceFile.path);

    final document = EpubLibraryDocument(
      documentId: documentId,
      filePath: cachedFile.path,
      originalFileName: p.basename(sourceFile.path),
      title: metadata.title?.trim().isNotEmpty == true ? metadata.title!.trim() : fallbackName,
      authors: metadata.authors,
      language: metadata.language,
      publisher: metadata.publisher,
      identifier: metadata.identifier,
      description: metadata.description,
      spineItemCount: metadata.spineItemCount,
      tocEntryCount: metadata.tocEntryCount,
      hasPageMap: metadata.hasPageMap,
      addedAt: DateTime.now(),
      fileLastModifiedAt: fileStat.modified,
      metadataLastReadAt: DateTime.now(),
    );

    await repository.upsertDocument(document);
    return document;
  }
}
