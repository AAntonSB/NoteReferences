import 'package:flutter/foundation.dart';

enum ReaderDocumentKind { pdf, epub }

extension ReaderDocumentKindPresentation on ReaderDocumentKind {
  String get label {
    switch (this) {
      case ReaderDocumentKind.pdf:
        return 'PDF';
      case ReaderDocumentKind.epub:
        return 'EPUB';
    }
  }
}


ReaderDocumentKind? readerDocumentKindFromFilePath(String filePath) {
  final normalized = filePath.trim().toLowerCase();
  if (normalized.endsWith('.pdf')) return ReaderDocumentKind.pdf;
  if (normalized.endsWith('.epub')) return ReaderDocumentKind.epub;
  return null;
}

@immutable
class ReaderDocumentRef {
  final ReaderDocumentKind kind;
  final String documentId;
  final String filePath;
  final String title;
  final String? sourceLabel;

  const ReaderDocumentRef({
    required this.kind,
    required this.documentId,
    required this.filePath,
    required this.title,
    this.sourceLabel,
  });

  const ReaderDocumentRef.pdf({
    required String documentId,
    required String filePath,
    required String title,
    String? sourceLabel,
  }) : this(
          kind: ReaderDocumentKind.pdf,
          documentId: documentId,
          filePath: filePath,
          title: title,
          sourceLabel: sourceLabel,
        );

  const ReaderDocumentRef.epub({
    required String documentId,
    required String filePath,
    required String title,
    String? sourceLabel,
  }) : this(
          kind: ReaderDocumentKind.epub,
          documentId: documentId,
          filePath: filePath,
          title: title,
          sourceLabel: sourceLabel,
        );

  factory ReaderDocumentRef.fromFilePath({
    required String documentId,
    required String filePath,
    required String title,
    String? sourceLabel,
  }) {
    final kind = readerDocumentKindFromFilePath(filePath);
    if (kind == null) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'Unsupported reader document type.',
      );
    }
    return ReaderDocumentRef(
      kind: kind,
      documentId: documentId,
      filePath: filePath,
      title: title,
      sourceLabel: sourceLabel,
    );
  }
}
