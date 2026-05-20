import 'package:flutter/foundation.dart';

import 'reader_document_ref.dart';

enum ReaderAnchorGranularity {
  document,
  page,
  section,
  paragraph,
  textRange,
}

extension ReaderAnchorGranularityPresentation on ReaderAnchorGranularity {
  String get label {
    switch (this) {
      case ReaderAnchorGranularity.document:
        return 'Document';
      case ReaderAnchorGranularity.page:
        return 'Page';
      case ReaderAnchorGranularity.section:
        return 'Section';
      case ReaderAnchorGranularity.paragraph:
        return 'Paragraph';
      case ReaderAnchorGranularity.textRange:
        return 'Text range';
    }
  }
}

@immutable
class ReaderAnchor {
  final ReaderDocumentKind documentKind;
  final String documentId;
  final String documentPath;
  final String documentTitle;
  final ReaderAnchorGranularity granularity;
  final String label;

  /// Zero-based PDF page index. Use [pageNumber] for user-facing display.
  final int? pdfPageIndex;

  /// Zero-based EPUB spine index. This is the reader's stable section index.
  final int? epubSpineIndex;
  final String? epubHref;
  final String? sectionTitle;

  /// Zero-based paragraph index within an EPUB spine item.
  final int? paragraphIndex;

  /// Optional character offsets inside [sourceText] or the paragraph body.
  final int? startOffset;
  final int? endOffset;

  /// Short preview used by sidecar, TODO and planning surfaces.
  final String? sourceText;

  const ReaderAnchor({
    required this.documentKind,
    required this.documentId,
    required this.documentPath,
    required this.documentTitle,
    required this.granularity,
    required this.label,
    this.pdfPageIndex,
    this.epubSpineIndex,
    this.epubHref,
    this.sectionTitle,
    this.paragraphIndex,
    this.startOffset,
    this.endOffset,
    this.sourceText,
  });

  factory ReaderAnchor.document(ReaderDocumentRef document) {
    return ReaderAnchor(
      documentKind: document.kind,
      documentId: document.documentId,
      documentPath: document.filePath,
      documentTitle: document.title,
      granularity: ReaderAnchorGranularity.document,
      label: document.title,
    );
  }

  factory ReaderAnchor.pdfPage({
    required ReaderDocumentRef document,
    required int pageIndex,
    String? sourceText,
  }) {
    return ReaderAnchor(
      documentKind: ReaderDocumentKind.pdf,
      documentId: document.documentId,
      documentPath: document.filePath,
      documentTitle: document.title,
      granularity: ReaderAnchorGranularity.page,
      label: 'Page ${pageIndex + 1}',
      pdfPageIndex: pageIndex < 0 ? 0 : pageIndex,
      sourceText: _previewText(sourceText),
    );
  }

  factory ReaderAnchor.epubSection({
    required ReaderDocumentRef document,
    required int spineIndex,
    required String href,
    required String title,
    String? sourceText,
  }) {
    final safeIndex = spineIndex < 0 ? 0 : spineIndex;
    final safeTitle = title.trim().isEmpty ? 'Section ${safeIndex + 1}' : title.trim();
    return ReaderAnchor(
      documentKind: ReaderDocumentKind.epub,
      documentId: document.documentId,
      documentPath: document.filePath,
      documentTitle: document.title,
      granularity: ReaderAnchorGranularity.section,
      label: 'Section ${safeIndex + 1}: $safeTitle',
      epubSpineIndex: safeIndex,
      epubHref: href,
      sectionTitle: safeTitle,
      sourceText: _previewText(sourceText),
    );
  }

  factory ReaderAnchor.epubParagraph({
    required ReaderDocumentRef document,
    required int spineIndex,
    required String href,
    required String sectionTitle,
    required int paragraphIndex,
    String? sourceText,
  }) {
    final safeSpineIndex = spineIndex < 0 ? 0 : spineIndex;
    final safeParagraphIndex = paragraphIndex < 0 ? 0 : paragraphIndex;
    final safeTitle = sectionTitle.trim().isEmpty ? 'Section ${safeSpineIndex + 1}' : sectionTitle.trim();
    return ReaderAnchor(
      documentKind: ReaderDocumentKind.epub,
      documentId: document.documentId,
      documentPath: document.filePath,
      documentTitle: document.title,
      granularity: ReaderAnchorGranularity.paragraph,
      label: 'Section ${safeSpineIndex + 1}, paragraph ${safeParagraphIndex + 1}',
      epubSpineIndex: safeSpineIndex,
      epubHref: href,
      sectionTitle: safeTitle,
      paragraphIndex: safeParagraphIndex,
      sourceText: _previewText(sourceText),
    );
  }

  bool get isPdf => documentKind == ReaderDocumentKind.pdf;
  bool get isEpub => documentKind == ReaderDocumentKind.epub;

  int? get pageNumber => pdfPageIndex == null ? null : pdfPageIndex! + 1;

  String get locationLabel {
    if (isPdf && pageNumber != null) return 'PDF page $pageNumber';
    if (isEpub && epubSpineIndex != null) {
      final paragraph = paragraphIndex == null ? '' : ', paragraph ${paragraphIndex! + 1}';
      return 'EPUB section ${epubSpineIndex! + 1}$paragraph';
    }
    return granularity.label;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentKind': documentKind.name,
      'documentId': documentId,
      'documentPath': documentPath,
      'documentTitle': documentTitle,
      'granularity': granularity.name,
      'label': label,
      'pdfPageIndex': pdfPageIndex,
      'epubSpineIndex': epubSpineIndex,
      'epubHref': epubHref,
      'sectionTitle': sectionTitle,
      'paragraphIndex': paragraphIndex,
      'startOffset': startOffset,
      'endOffset': endOffset,
      'sourceText': sourceText,
    };
  }

  factory ReaderAnchor.fromJson(Map<String, Object?> json) {
    int? intValue(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    String stringValue(Object? value, String fallback) {
      if (value is String && value.trim().isNotEmpty) return value;
      return fallback;
    }

    T enumValue<T extends Enum>(List<T> values, Object? value, T fallback) {
      if (value is String) {
        for (final item in values) {
          if (item.name == value) return item;
        }
      }
      return fallback;
    }

    final kind = enumValue(
      ReaderDocumentKind.values,
      json['documentKind'],
      ReaderDocumentKind.pdf,
    );
    final granularity = enumValue(
      ReaderAnchorGranularity.values,
      json['granularity'],
      ReaderAnchorGranularity.document,
    );

    return ReaderAnchor(
      documentKind: kind,
      documentId: stringValue(json['documentId'], ''),
      documentPath: stringValue(json['documentPath'], ''),
      documentTitle: stringValue(json['documentTitle'], 'Reader document'),
      granularity: granularity,
      label: stringValue(json['label'], granularity.label),
      pdfPageIndex: intValue(json['pdfPageIndex']),
      epubSpineIndex: intValue(json['epubSpineIndex']),
      epubHref: json['epubHref'] as String?,
      sectionTitle: json['sectionTitle'] as String?,
      paragraphIndex: intValue(json['paragraphIndex']),
      startOffset: intValue(json['startOffset']),
      endOffset: intValue(json['endOffset']),
      sourceText: json['sourceText'] as String?,
    );
  }

  static String? _previewText(String? value) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length <= 220) return normalized;
    return '${normalized.substring(0, 217).trimRight()}…';
  }
}
