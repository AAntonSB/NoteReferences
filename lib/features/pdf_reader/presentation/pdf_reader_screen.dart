import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import '../data/pdf_reader_session_state_store.dart';
import '../domain/pdf_viewport_state.dart';
import 'pdf_hover_highlight_overlay.dart';
import 'pdf_search_bar.dart';
import 'pdf_selection_action_overlay.dart';
import 'pdf_sidecar_notes_canvas.dart';
import 'sidecar/note_creation_type.dart';
import 'sidecar/sidecar_external_create_request.dart';
import 'sidecar/sidecar_reveal_note_request.dart';

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

  final ValueNotifier<PdfViewportState> _viewportNotifier =
      ValueNotifier<PdfViewportState>(PdfViewportState.initial());

  final ValueNotifier<List<PdfLinkedHighlightRegion>>
      _persistentHighlightRegionsNotifier =
      ValueNotifier<List<PdfLinkedHighlightRegion>>(const []);

  final ValueNotifier<List<PdfSourceRect>> _hoverHighlightRectsNotifier =
      ValueNotifier<List<PdfSourceRect>>(const []);

  final ValueNotifier<SidecarExternalCreateRequest?>
      _sidecarCreateRequestNotifier =
      ValueNotifier<SidecarExternalCreateRequest?>(null);

  final ValueNotifier<SidecarRevealNoteRequest?> _revealNoteRequestNotifier =
      ValueNotifier<SidecarRevealNoteRequest?>(null);

  final ValueNotifier<int> _outlineSearchFocusRequestNotifier =
      ValueNotifier<int>(0);

  final TextEditingController _pdfSearchController = TextEditingController();
  final FocusNode _pdfSearchFocusNode = FocusNode();
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'PdfReaderScreen');

  late final NoteRepository _noteRepository;
  late final PdfReaderSessionStateStore _sessionStore;

  pdfrx.PdfTextSearcher? _pdfTextSearcher;

  StreamSubscription<List<PdfLinkedHighlightRegion>>?
      _persistentHighlightsSubscription;
  Timer? _pdfSearchDebounce;
  Timer? _sessionSaveDebounce;

  PdfReaderSessionState? _restoredSession;

  String? _selectedText;
  List<PdfSourceRect> _selectedSourceRects = const [];

  double _pdfPaneFraction = 0.5;

  bool _pdfSearchOpen = false;
  bool _sessionLoaded = false;
  bool _didRestorePdfViewport = false;
  bool _latestOutlineOpen = false;
  bool _latestDebugEnabled = false;

  int _selectionRequestId = 0;
  int _sidecarCreateRequestId = 0;
  int _revealNoteRequestId = 0;

  static const double _dividerWidth = 8.0;
  static const double _minPaneWidth = 280.0;
  static const double _mouseWheelScrollRatio = 0.18;

  @override
  void initState() {
    super.initState();

    _noteRepository = NoteRepository(widget.database);
    _sessionStore = PdfReaderSessionStateStore();

    _controller.addListener(_publishViewportState);

    _persistentHighlightsSubscription = _noteRepository
        .watchPersistentHighlightRegionsForDocument(
          documentId: widget.documentId,
        )
        .listen((regions) {
      _persistentHighlightRegionsNotifier.value = List.unmodifiable(regions);
    });

    _loadReaderSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _screenFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _sessionSaveDebounce?.cancel();
    _pdfSearchDebounce?.cancel();
    unawaited(_saveReaderSessionNow());

    _persistentHighlightsSubscription?.cancel();

    _pdfTextSearcher?.removeListener(_handlePdfTextSearcherChanged);
    _pdfTextSearcher?.dispose();

    _controller.removeListener(_publishViewportState);

    _screenFocusNode.dispose();
    _pdfSearchFocusNode.dispose();
    _pdfSearchController.dispose();

    _viewportNotifier.dispose();
    _persistentHighlightRegionsNotifier.dispose();
    _hoverHighlightRectsNotifier.dispose();
    _sidecarCreateRequestNotifier.dispose();
    _revealNoteRequestNotifier.dispose();
    _outlineSearchFocusRequestNotifier.dispose();

    super.dispose();
  }

  Future<void> _loadReaderSession() async {
    final session = await _sessionStore.load(widget.documentId);

    if (!mounted) return;

    setState(() {
      _restoredSession = session;
      _pdfPaneFraction = session?.pdfPaneFraction ?? 0.5;
      _latestOutlineOpen = session?.outlineOpen ?? false;
      _latestDebugEnabled = session?.debugEnabled ?? false;
      _sessionLoaded = true;
    });
  }

  void _scheduleReaderSessionSave() {
    if (!_sessionLoaded) {
      return;
    }

    _sessionSaveDebounce?.cancel();
    _sessionSaveDebounce = Timer(
      const Duration(milliseconds: 550),
      () {
        unawaited(_saveReaderSessionNow());
      },
    );
  }

  Future<void> _saveReaderSessionNow() async {
    if (!_sessionLoaded || !_controller.isReady) {
      return;
    }

    final visibleRect = _controller.visibleRect;

    if (visibleRect == Rect.zero || visibleRect.height <= 0) {
      return;
    }

    final state = PdfReaderSessionState(
      documentId: widget.documentId,
      visibleTop: visibleRect.top,
      visibleCenterX: visibleRect.center.dx,
      zoom: _controller.currentZoom,
      pdfPaneFraction: _pdfPaneFraction,
      outlineOpen: _latestOutlineOpen,
      debugEnabled: _latestDebugEnabled,
      updatedAt: DateTime.now(),
    );

    await _sessionStore.save(state);
  }

  void _restorePdfViewportIfNeeded() {
    if (_didRestorePdfViewport ||
        !_sessionLoaded ||
        !_controller.isReady ||
        _restoredSession == null) {
      return;
    }

    final visibleRect = _controller.visibleRect;
    final documentSize = _controller.documentSize;

    if (visibleRect == Rect.zero ||
        visibleRect.height <= 0 ||
        documentSize.height <= 0) {
      return;
    }

    final session = _restoredSession!;
    _didRestorePdfViewport = true;

    final zoom = math.max(0.01, session.zoom);
    final maxTop = math.max(0.0, documentSize.height - visibleRect.height);
    final targetTop = session.visibleTop.clamp(0.0, maxTop).toDouble();

    final targetCenter = Offset(
      session.visibleCenterX <= 0 ? visibleRect.center.dx : session.visibleCenterX,
      targetTop + visibleRect.height / 2,
    );

    final matrix = _controller.calcMatrixFor(
      targetCenter,
      zoom: zoom,
    );

    unawaited(
      _controller.goTo(
        matrix,
        duration: Duration.zero,
      ),
    );
  }

  bool get _hasActivePdfSearchQuery {
    return _pdfSearchOpen && _pdfSearchController.text.trim().isNotEmpty;
  }

  void _ensurePdfTextSearcherReady() {
    if (_pdfTextSearcher != null) {
      return;
    }

    if (!_controller.isReady) {
      return;
    }

    final searcher = pdfrx.PdfTextSearcher(_controller);
    searcher.addListener(_handlePdfTextSearcherChanged);

    _pdfTextSearcher = searcher;
  }

  void _handlePdfTextSearcherChanged() {
    if (!mounted) return;
    setState(() {});
  }

  KeyEventResult _handleScreenKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrlF = event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlF) {
      _openPdfSearch();
      return KeyEventResult.handled;
    }

    final isCtrlShiftF = event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlShiftF) {
      _openNotesOutlineSearch();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _openPdfSearch() {
    _ensurePdfTextSearcherReady();

    if (!_pdfSearchOpen) {
      setState(() {
        _pdfSearchOpen = true;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _pdfSearchFocusNode.requestFocus();
      _pdfSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _pdfSearchController.text.length,
      );
    });
  }

  void _closePdfSearch() {
    _pdfSearchDebounce?.cancel();
    _pdfTextSearcher?.resetTextSearch();

    _pdfSearchController.clear();

    setState(() {
      _pdfSearchOpen = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _screenFocusNode.requestFocus();
    });
  }

  void _handlePdfSearchQueryChanged(String value) {
    _pdfSearchDebounce?.cancel();

    final query = value.trim();
    final searcher = _pdfTextSearcher;

    setState(() {});

    if (searcher == null) {
      return;
    }

    if (query.isEmpty) {
      searcher.resetTextSearch();
      return;
    }

    _pdfSearchDebounce = Timer(const Duration(milliseconds: 180), () {
      searcher.startTextSearch(
        query,
        caseInsensitive: true,
        goToFirstMatch: true,
        searchImmediately: true,
      );
    });
  }

  void _goToNextPdfSearchMatch() {
    final searcher = _pdfTextSearcher;

    if (searcher == null || searcher.matches.isEmpty) {
      return;
    }

    unawaited(searcher.goToNextMatch());
  }

  void _goToPreviousPdfSearchMatch() {
    final searcher = _pdfTextSearcher;

    if (searcher == null || searcher.matches.isEmpty) {
      return;
    }

    unawaited(searcher.goToPrevMatch());
  }

  void _openNotesOutlineSearch() {
    _outlineSearchFocusRequestNotifier.value =
        _outlineSearchFocusRequestNotifier.value + 1;
  }

  void _handleViewerReady(
    pdfrx.PdfDocument document,
    pdfrx.PdfViewerController controller,
  ) {
    _ensurePdfTextSearcherReady();
    _publishViewportState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restorePdfViewportIfNeeded();
    });

    if (_pdfSearchOpen && _pdfSearchController.text.trim().isNotEmpty) {
      _handlePdfSearchQueryChanged(_pdfSearchController.text);
    }
  }

  void _publishViewportState() {
    if (!mounted || !_controller.isReady) {
      return;
    }

    final next = _readViewportStateFromController();

    if (_viewportNotifier.value.isEquivalentTo(next)) {
      return;
    }

    _viewportNotifier.value = next;
    _scheduleReaderSessionSave();
  }

  PdfViewportState _readViewportStateFromController() {
    final pageCount = _controller.pageCount <= 0 ? 1 : _controller.pageCount;
    final currentPage =
        (_controller.pageNumber ?? 1).clamp(1, pageCount).toInt();

    final layout = _controller.layout;

    return PdfViewportState(
      isReady: _controller.isReady,
      currentPage: currentPage,
      pageCount: pageCount,
      zoom: _controller.currentZoom,
      visibleRect: _controller.visibleRect,
      documentSize: layout.documentSize,
      pageRects: List<Rect>.from(layout.pageLayouts),
    );
  }

  void _handlePageChanged(int? pageNumber) {
    if (!mounted) return;

    setState(() {
      _selectedText = null;
      _selectedSourceRects = const [];
      _selectionRequestId++;
    });

    _publishViewportState();
  }

  void _handleTextSelectionChange(pdfrx.PdfTextSelection textSelection) {
    final requestId = ++_selectionRequestId;

    if (!textSelection.hasSelectedText) {
      if (!mounted) return;

      setState(() {
        _selectedText = null;
        _selectedSourceRects = const [];
      });

      return;
    }

    unawaited(
      _readSelectedTextAndRects(textSelection).then((selectionData) {
        if (!mounted || requestId != _selectionRequestId) {
          return;
        }

        setState(() {
          _selectedText = selectionData.selectedText.isEmpty
              ? null
              : selectionData.selectedText;
          _selectedSourceRects = selectionData.sourceRects;
        });
      }).catchError((error) {
        debugPrint('Could not read selected PDF text: $error');
      }),
    );
  }

  Future<_SelectedPdfTextData> _readSelectedTextAndRects(
    pdfrx.PdfTextSelection textSelection,
  ) async {
    final selectedText = (await textSelection.getSelectedText()).trim();
    final ranges = await textSelection.getSelectedTextRanges();

    final sourceRects = <PdfSourceRect>[];

    for (final range in ranges) {
      final fragments = range.enumerateFragmentBoundingRects().toList();

      if (fragments.isEmpty) {
        final bounds = range.bounds;

        sourceRects.add(
          PdfSourceRect(
            pageNumber: range.pageNumber,
            left: bounds.left,
            top: bounds.top,
            right: bounds.right,
            bottom: bounds.bottom,
          ),
        );

        continue;
      }

      for (final fragment in fragments) {
        final bounds = fragment.bounds;

        sourceRects.add(
          PdfSourceRect(
            pageNumber: range.pageNumber,
            left: bounds.left,
            top: bounds.top,
            right: bounds.right,
            bottom: bounds.bottom,
          ),
        );
      }
    }

    return _SelectedPdfTextData(
      selectedText: selectedText,
      sourceRects: sourceRects.where((rect) => rect.isValid).toList(),
    );
  }

  void _handleHoveredSourceRectsChanged(List<PdfSourceRect> sourceRects) {
    if (_sourceRectListsEqual(
      _hoverHighlightRectsNotifier.value,
      sourceRects,
    )) {
      return;
    }

    _hoverHighlightRectsNotifier.value = List.unmodifiable(sourceRects);
  }

  bool _sourceRectListsEqual(
    List<PdfSourceRect> left,
    List<PdfSourceRect> right,
  ) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];

      if (a.pageNumber != b.pageNumber ||
          a.left != b.left ||
          a.top != b.top ||
          a.right != b.right ||
          a.bottom != b.bottom) {
        return false;
      }
    }

    return true;
  }

  void _handleSidecarScrollDelta(Offset scrollDelta) {
    if (!_controller.isReady || scrollDelta.dy == 0) {
      return;
    }

    final visibleRect = _controller.visibleRect;
    final documentSize = _controller.documentSize;

    if (visibleRect == Rect.zero ||
        visibleRect.height <= 0 ||
        documentSize.height <= 0) {
      return;
    }

    final zoom = math.max(_controller.currentZoom, 0.01);
    final documentDeltaY = (scrollDelta.dy * _mouseWheelScrollRatio) / zoom;

    final maxTop = math.max(0.0, documentSize.height - visibleRect.height);
    final nextTop = (visibleRect.top + documentDeltaY)
        .clamp(0.0, maxTop)
        .toDouble();

    if ((nextTop - visibleRect.top).abs() < 0.1) {
      return;
    }

    final nextCenter = Offset(
      visibleRect.center.dx,
      nextTop + visibleRect.height / 2,
    );

    final matrix = _controller.calcMatrixFor(
      nextCenter,
      zoom: _controller.currentZoom,
    );

    unawaited(
      _controller.goTo(
        matrix,
        duration: Duration.zero,
      ),
    );
  }

  void _handleRequestPdfJumpToDocumentY(double documentY) {
    if (!_controller.isReady) {
      return;
    }

    final visibleRect = _controller.visibleRect;
    final documentSize = _controller.documentSize;

    if (visibleRect == Rect.zero ||
        visibleRect.height <= 0 ||
        documentSize.height <= 0) {
      return;
    }

    final maxTop = math.max(0.0, documentSize.height - visibleRect.height);
    final targetTop = (documentY - visibleRect.height * 0.30)
        .clamp(0.0, maxTop)
        .toDouble();

    final targetCenter = Offset(
      visibleRect.center.dx,
      targetTop + visibleRect.height / 2,
    );

    final matrix = _controller.calcMatrixFor(
      targetCenter,
      zoom: _controller.currentZoom,
    );

    unawaited(
      _controller.goTo(
        matrix,
        duration: const Duration(milliseconds: 140),
      ),
    );
  }

  void _requestSidecarNoteFromSelection({
    required NoteCreationType creationType,
    required int pageNumber,
    required double normalizedY,
  }) {
    if (_selectedSourceRects.isEmpty) {
      return;
    }

    _sidecarCreateRequestNotifier.value = SidecarExternalCreateRequest(
      requestId: ++_sidecarCreateRequestId,
      creationType: creationType,
      pageNumber: pageNumber,
      normalizedY: normalizedY,
      selectedText: _selectedText,
      sourceRects: _selectedSourceRects,
    );
  }

  Future<void> _createPersistentHighlightFromSelection({
    required int pageNumber,
  }) async {
    if (_selectedSourceRects.isEmpty) {
      return;
    }

    await _noteRepository.createPersistentHighlight(
      documentId: widget.documentId,
      pageNumber: pageNumber,
      selectedText: _selectedText,
      sourceRects: _selectedSourceRects,
    );
  }

  void _handleLinkedHighlightActivated(String noteId) {
    _revealNoteRequestNotifier.value = SidecarRevealNoteRequest(
      requestId: ++_revealNoteRequestId,
      noteId: noteId,
    );
  }

  void _handleSidecarPreferencesChanged({
    required bool outlineOpen,
    required bool debugEnabled,
  }) {
    _latestOutlineOpen = outlineOpen;
    _latestDebugEnabled = debugEnabled;
    _scheduleReaderSessionSave();
  }

  Widget _buildPdfViewer() {
    final searcher = _pdfTextSearcher;

    return pdfrx.PdfViewer.file(
      widget.filePath,
      key: ValueKey(widget.filePath),
      controller: _controller,
      initialPageNumber: _viewportNotifier.value.currentPage,
      params: pdfrx.PdfViewerParams(
        margin: 8,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        pageAnchor: pdfrx.PdfPageAnchor.top,
        pageAnchorEnd: pdfrx.PdfPageAnchor.bottom,
        maxScale: 8,
        minScale: 0.1,
        scrollByMouseWheel: _mouseWheelScrollRatio,
        enableKeyboardNavigation: true,
        pagePaintCallbacks: _hasActivePdfSearchQuery && searcher != null
            ? [
                searcher.pageTextMatchPaintCallback,
              ]
            : const [],
        pageOverlaysBuilder: (context, pageRectInViewer, page) {
          return [
            PdfHoverHighlightOverlay(
              persistentRegionsListenable: _persistentHighlightRegionsNotifier,
              hoverSourceRectsListenable: _hoverHighlightRectsNotifier,
              pageRectInViewer: pageRectInViewer,
              page: page,
              onLinkedHighlightActivated: _handleLinkedHighlightActivated,
            ),
            PdfSelectionActionOverlay(
              selectedText: _selectedText,
              selectedSourceRects: _selectedSourceRects,
              pageRectInViewer: pageRectInViewer,
              page: page,
              onCreateNote: _requestSidecarNoteFromSelection,
              onCreateHighlight: _createPersistentHighlightFromSelection,
            ),
          ];
        },
        textSelectionParams: pdfrx.PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: true,
          onTextSelectionChange: _handleTextSelectionChange,
        ),
        onViewerReady: _handleViewerReady,
        onPageChanged: _handlePageChanged,
        onViewSizeChanged: (_, __, ___) {
          _publishViewportState();
          _restorePdfViewportIfNeeded();
        },
        onInteractionUpdate: (_) {
          _publishViewportState();
        },
        onInteractionEnd: (_) {
          _publishViewportState();
        },
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

  Widget _buildPdfPane() {
    final searcher = _pdfTextSearcher;

    return Stack(
      children: [
        Positioned.fill(
          child: _buildPdfViewer(),
        ),
        if (_pdfSearchOpen && searcher != null)
          Positioned(
            top: 12,
            left: 12,
            child: PdfSearchBar(
              controller: _pdfSearchController,
              focusNode: _pdfSearchFocusNode,
              textSearcher: searcher,
              onQueryChanged: _handlePdfSearchQueryChanged,
              onNext: _goToNextPdfSearchMatch,
              onPrevious: _goToPreviousPdfSearchMatch,
              onClose: _closePdfSearch,
            ),
          ),
      ],
    );
  }

  Widget _buildSplitBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        if (totalWidth < (_minPaneWidth * 2 + _dividerWidth)) {
          return _buildPdfPane();
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
              child: _buildPdfPane(),
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

                  _scheduleReaderSessionSave();

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _publishViewportState();
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
                viewportListenable: _viewportNotifier,
                selectedText: _selectedText,
                selectedSourceRects: _selectedSourceRects,
                externalCreateRequestListenable:
                    _sidecarCreateRequestNotifier,
                revealNoteRequestListenable: _revealNoteRequestNotifier,
                outlineSearchFocusRequestListenable:
                    _outlineSearchFocusRequestNotifier,
                initialOutlineOpen: _latestOutlineOpen,
                initialDebugEnabled: _latestDebugEnabled,
                onSidecarPreferencesChanged:
                    _handleSidecarPreferencesChanged,
                onHoveredSourceRectsChanged: _handleHoveredSourceRectsChanged,
                onSidecarScrollDelta: _handleSidecarScrollDelta,
                onRequestPdfJumpToDocumentY: _handleRequestPdfJumpToDocumentY,
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
    if (!_sessionLoaded) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Focus(
      focusNode: _screenFocusNode,
      autofocus: true,
      onKeyEvent: _handleScreenKeyEvent,
      child: Scaffold(
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
            ValueListenableBuilder<PdfViewportState>(
              valueListenable: _viewportNotifier,
              builder: (context, viewport, _) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      'Page ${viewport.safeCurrentPage} / ${viewport.safePageCount} | '
                      'Y ${viewport.visibleTop.toStringAsFixed(0)} | '
                      'Zoom ${viewport.zoom.toStringAsFixed(2)}',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: _buildSplitBody(),
      ),
    );
  }
}

class _SelectedPdfTextData {
  final String selectedText;
  final List<PdfSourceRect> sourceRects;

  const _SelectedPdfTextData({
    required this.selectedText,
    required this.sourceRects,
  });
}