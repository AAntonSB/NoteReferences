import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import '../../pdf_reader/presentation/pdf_reader_screen.dart';
import 'epub_reader_screen.dart';
import '../../planning/data/study_planning_repository.dart';
import '../domain/reader_document_ref.dart';
import '../domain/reader_initial_locator.dart';

class ReaderScreen extends StatelessWidget {
  final AppDatabase database;
  final ReaderDocumentRef document;
  final StudyPlanningRepository? planningRepository;
  final ReaderInitialLocator initialLocator;

  const ReaderScreen({
    super.key,
    required this.database,
    required this.document,
    this.planningRepository,
    this.initialLocator = ReaderInitialLocator.empty,
  });

  factory ReaderScreen.epub({
    Key? key,
    required AppDatabase database,
    required String documentId,
    required String filePath,
    required String title,
    StudyPlanningRepository? planningRepository,
    String? sourceLabel,
  }) {
    return ReaderScreen(
      key: key,
      database: database,
      document: ReaderDocumentRef.epub(
        documentId: documentId,
        filePath: filePath,
        title: title,
        sourceLabel: sourceLabel,
      ),
      planningRepository: planningRepository,
    );
  }

  factory ReaderScreen.pdf({
    Key? key,
    required AppDatabase database,
    required String documentId,
    required String filePath,
    required String title,
    StudyPlanningRepository? planningRepository,
    int? initialPageNumber,
    List<PdfSourceRect> initialSourceRects = const <PdfSourceRect>[],
    String? initialSidecarNoteId,
    String? initialOpenLabel,
  }) {
    return ReaderScreen(
      key: key,
      database: database,
      document: ReaderDocumentRef.pdf(
        documentId: documentId,
        filePath: filePath,
        title: title,
      ),
      planningRepository: planningRepository,
      initialLocator: ReaderInitialLocator(
        pageNumber: initialPageNumber,
        pdfSourceRects: initialSourceRects,
        sidecarNoteId: initialSidecarNoteId,
        openLabel: initialOpenLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (document.kind) {
      case ReaderDocumentKind.pdf:
        return PdfReaderScreen(
          database: database,
          documentId: document.documentId,
          filePath: document.filePath,
          title: document.title,
          planningRepository: planningRepository,
          initialPageNumber: initialLocator.pageNumber,
          initialSourceRects: initialLocator.pdfSourceRects,
          initialSidecarNoteId: initialLocator.sidecarNoteId,
          initialOpenLabel: initialLocator.openLabel,
        );
      case ReaderDocumentKind.epub:
        return EpubReaderScreen(database: database, document: document);
    }
  }
}


String _readerDocumentKindLabel(ReaderDocumentKind kind) {
  switch (kind) {
    case ReaderDocumentKind.pdf:
      return 'PDF';
    case ReaderDocumentKind.epub:
      return 'EPUB';
  }
}

class _UnsupportedReaderDocumentScreen extends StatelessWidget {
  final ReaderDocumentRef document;

  const _UnsupportedReaderDocumentScreen({required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${_readerDocumentKindLabel(document.kind)} reader shell',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    document.kind == ReaderDocumentKind.epub
                        ? 'This EPUB has been imported and metadata is available in the library. The dedicated EPUB rendering surface comes next, where reading positions, annotations, and planning actions will attach to this reader document.'
                        : 'The shared reader route is ready. This document type still needs its own rendering surface before reading, annotation, and planning actions can be enabled.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
