import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import 'pdf_sidecar_notes_canvas.dart';

class PdfReaderScreen extends StatefulWidget {
  final AppDatabase database;
  final String documentId;
  final String filePath;
  final String title;

  const PdfReaderScreen({
    super.key,
    required this.database,
    required this.documentId,
    required this.filePath,
    required this.title,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final pdfrx.PdfViewerController _controller = pdfrx.PdfViewerController();

  late final NoteRepository _noteRepository;

  int _currentPage = 1;
  int _pageCount = 1;

  double _currentZoomLevel = 1.0;
  Rect _pdfVisibleRect = Rect.zero;
  Size _pdfDocumentSize = Size.zero;

  String? _selectedText;

  double _pdfPaneFraction = 0.5;

  int _selectionRequestId = 0;

  static const double _dividerWidth = 8.0;
  static const double _minPaneWidth = 280.0;

  @override
  void initState() {
    super.initState();

    _noteRepository = NoteRepository(widget.database);
    _controller.addListener(_handleViewerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleViewerChanged);
    super.dispose();
  }

  void _handleViewerReady(
    pdfrx.PdfDocument document,
    pdfrx.PdfViewerController controller,
  ) {
    if (!mounted) return;

    setState(() {
      _pageCount = document.pages.isEmpty ? 1 : document.pages.length;
      _currentPage = controller.pageNumber ?? 1;
      _currentZoomLevel = controller.currentZoom;
      _pdfVisibleRect = controller.visibleRect;
      _pdfDocumentSize = controller.documentSize;
    });
  }

  void _handleViewerChanged() {
    if (!_controller.isReady || !mounted) {
      return;
    }

    final nextPage = _controller.pageNumber ?? _currentPage;
    final nextPageCount = _controller.pageCount <= 0 ? 1 : _controller.pageCount;
    final nextZoom = _controller.currentZoom;
    final nextVisibleRect = _controller.visibleRect;
    final nextDocumentSize = _controller.documentSize;

    final changed = nextPage != _currentPage ||
        nextPageCount != _pageCount ||
        nextZoom != _currentZoomLevel ||
        nextVisibleRect != _pdfVisibleRect ||
        nextDocumentSize != _pdfDocumentSize;

    if (!changed) {
      return;
    }

    setState(() {
      _currentPage = nextPage;
      _pageCount = nextPageCount;
      _currentZoomLevel = nextZoom;
      _pdfVisibleRect = nextVisibleRect;
      _pdfDocumentSize = nextDocumentSize;
    });
  }

  void _handlePageChanged(int? pageNumber) {
    if (!mounted) return;

    setState(() {
      _currentPage = pageNumber ?? 1;
      _selectedText = null;
      _selectionRequestId++;
    });
  }

  void _handleTextSelectionChange(pdfrx.PdfTextSelection textSelection) {
    final requestId = ++_selectionRequestId;

    if (!textSelection.hasSelectedText) {
      if (!mounted) return;

      setState(() {
        _selectedText = null;
      });

      return;
    }

    unawaited(
      textSelection.getSelectedText().then((selectedText) {
        if (!mounted || requestId != _selectionRequestId) {
          return;
        }

        final trimmed = selectedText.trim();

        setState(() {
          _selectedText = trimmed.isEmpty ? null : trimmed;
        });
      }).catchError((error) {
        debugPrint('Could not read selected PDF text: $error');
      }),
    );
  }

  Widget _buildPdfViewer() {
    return pdfrx.PdfViewer.file(
      widget.filePath,
      key: ValueKey(widget.filePath),
      controller: _controller,
      initialPageNumber: _currentPage,
      params: pdfrx.PdfViewerParams(
        margin: 8,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        pageAnchor: pdfrx.PdfPageAnchor.top,
        pageAnchorEnd: pdfrx.PdfPageAnchor.bottom,
        maxScale: 8,
        minScale: 0.1,
        scrollByMouseWheel: 0.18,
        enableKeyboardNavigation: true,
        textSelectionParams: pdfrx.PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: true,
          onTextSelectionChange: _handleTextSelectionChange,
        ),
        onViewerReady: _handleViewerReady,
        onPageChanged: _handlePageChanged,
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
          if (totalBytes == null || totalBytes <= 0) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          return Center(
            child: CircularProgressIndicator(
              value: bytesDownloaded / totalBytes,
            ),
          );
        },
        errorBannerBuilder: (context, error, stackTrace, documentRef) {
          return Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Could not open PDF',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSplitBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        if (totalWidth < (_minPaneWidth * 2 + _dividerWidth)) {
          return _buildPdfViewer();
        }

        final availableWidth = totalWidth - _dividerWidth;

        final minFraction = _minPaneWidth / availableWidth;
        final maxFraction = 1.0 - (_minPaneWidth / availableWidth);

        final safePdfPaneFraction = _pdfPaneFraction
            .clamp(
              minFraction,
              maxFraction,
            )
            .toDouble();

        final pdfPaneWidth = availableWidth * safePdfPaneFraction;
        final notesPaneWidth = availableWidth - pdfPaneWidth;

        return Row(
          children: [
            SizedBox(
              width: pdfPaneWidth,
              child: _buildPdfViewer(),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    final newPdfWidth = pdfPaneWidth + details.delta.dx;

                    _pdfPaneFraction = (newPdfWidth / availableWidth)
                        .clamp(
                          minFraction,
                          maxFraction,
                        )
                        .toDouble();
                  });
                },
                child: Container(
                  width: _dividerWidth,
                  color: Theme.of(context).colorScheme.outlineVariant,
                  child: Center(
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: notesPaneWidth,
              child: PdfSidecarNotesCanvas(
                noteRepository: _noteRepository,
                documentId: widget.documentId,
                currentPage: _currentPage,
                pageCount: _pageCount,
                selectedText: _selectedText,
                pdfVisibleRect: _pdfVisibleRect,
                pdfDocumentSize: _pdfDocumentSize,
              ),
            ),
          ],
        );
      },
    );
  }

  bool get _hasActiveSelection {
    return _selectedText != null && _selectedText!.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final visibleTop = _pdfVisibleRect == Rect.zero ? 0.0 : _pdfVisibleRect.top;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_hasActiveSelection)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Chip(
                  avatar: Icon(Icons.format_quote, size: 16),
                  label: Text('Selection active'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Page $_currentPage / $_pageCount | '
                'Y ${visibleTop.toStringAsFixed(0)} | '
                'Zoom ${_currentZoomLevel.toStringAsFixed(2)}',
              ),
            ),
          ),
        ],
      ),
      body: _buildSplitBody(),
    );
  }
}