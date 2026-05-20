import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

class ExtractedPdfMetadata {
  final String? title;
  final String? authors;
  final String? subject;
  final String? keywords;
  final DateTime? creationDate;
  final DateTime? modificationDate;
  final int? pageCount;

  const ExtractedPdfMetadata({
    required this.title,
    required this.authors,
    required this.subject,
    required this.keywords,
    required this.creationDate,
    required this.modificationDate,
    this.pageCount,
  });
}

class PdfMetadataExtractor {
  Future<ExtractedPdfMetadata> extract(File file) async {
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);

    try {
      final info = document.documentInformation;

      return ExtractedPdfMetadata(
        title: _emptyToNull(info.title),
        authors: _emptyToNull(info.author),
        subject: _emptyToNull(info.subject),
        keywords: _emptyToNull(info.keywords),
        creationDate: info.creationDate,
        modificationDate: info.modificationDate,
        pageCount: document.pages.count,
      );
    } finally {
      document.dispose();
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}