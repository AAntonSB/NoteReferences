import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import 'pdf_notes_panel.dart';

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
  final PdfViewerController _controller = PdfViewerController();

  late final NoteRepository _noteRepository;

  Timer? _positionTimer;

  int _currentPage = 1;
  Offset _currentScrollOffset = Offset.zero;
  double _currentZoomLevel = 1.0;

  String? _selectedText;

  double _pdfPaneFraction = 0.5;

  static const double _dividerWidth = 8.0;
  static const double _minPaneWidth = 240.0;

  @override
  void initState() {
    super.initState();

    _noteRepository = NoteRepository(widget.database);

    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _capturePosition(),
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _capturePosition() {
    final scrollOffset = _controller.scrollOffset;
    final zoomLevel = _controller.zoomLevel;

    if (scrollOffset == _currentScrollOffset && zoomLevel == _currentZoomLevel) {
      return;
    }

    setState(() {
      _currentScrollOffset = scrollOffset;
      _currentZoomLevel = zoomLevel;
    });

    debugPrint(
      'document=${widget.documentId}, '
      'page=$_currentPage, '
      'scrollX=${scrollOffset.dx}, '
      'scrollY=${scrollOffset.dy}, '
      'zoom=$zoomLevel',
    );
  }

  Widget _buildPdfViewer() {
    return SfPdfViewer.file(
      File(widget.filePath),
      controller: _controller,
      pageLayoutMode: PdfPageLayoutMode.continuous,
      scrollDirection: PdfScrollDirection.vertical,
      onPageChanged: (details) {
        setState(() {
          _currentPage = details.newPageNumber;
          _selectedText = null;
        });
      },
      onTextSelectionChanged: (details) {
        setState(() {
          _selectedText = details.selectedText;
        });
      },
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
              child: PdfNotesPanel(
                noteRepository: _noteRepository,
                documentId: widget.documentId,
                currentPage: _currentPage,
                selectedText: _selectedText,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Page $_currentPage | '
                'Y ${_currentScrollOffset.dy.toStringAsFixed(0)} | '
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