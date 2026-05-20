import 'package:flutter/foundation.dart';

import '../../notes/data/note_repository.dart';

@immutable
class ReaderInitialLocator {
  final int? pageNumber;
  final List<PdfSourceRect> pdfSourceRects;
  final String? sidecarNoteId;
  final String? openLabel;

  const ReaderInitialLocator({
    this.pageNumber,
    this.pdfSourceRects = const <PdfSourceRect>[],
    this.sidecarNoteId,
    this.openLabel,
  });

  static const ReaderInitialLocator empty = ReaderInitialLocator();
}
