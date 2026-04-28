import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PdfCacheService {
  Future<Directory> _cacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory(p.join(appDir.path, 'pdf_cache'));

    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }

    return pdfDir;
  }

  Future<String> documentIdForFile(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  Future<File> cachePdf(File sourceFile, String documentId) async {
    final cacheDir = await _cacheDirectory();
    final cachedPath = p.join(cacheDir.path, '$documentId.pdf');
    final cachedFile = File(cachedPath);

    if (!await cachedFile.exists()) {
      await sourceFile.copy(cachedPath);
    }

    return cachedFile;
  }
}