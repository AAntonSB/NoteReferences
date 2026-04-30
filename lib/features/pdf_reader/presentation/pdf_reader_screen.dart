import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import '../data/pdf_reader_session_state_store.dart';
import '../domain/pdf_viewport_state.dart';
import 'pdf_hover_highlight_overlay.dart';
import 'pdf_document_notes_panel.dart';
import 'pdf_reader_toolbar.dart';
import 'pdf_search_bar.dart';
import 'pdf_selection_action_overlay.dart';
import 'pdf_todo_panel.dart';
import 'pdf_sidecar_notes_canvas.dart';
import 'sidecar/note_creation_type.dart';
import 'sidecar/sidecar_external_create_request.dart';
import 'sidecar/sidecar_reveal_note_request.dart';

enum PdfReaderWorkspaceLayout { reader, sidecar, document, synthesis }

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
  _sidecarCreateRequestNotifier = ValueNotifier<SidecarExternalCreateRequest?>(
    null,
  );

  final ValueNotifier<SidecarRevealNoteRequest?> _revealNoteRequestNotifier =
      ValueNotifier<SidecarRevealNoteRequest?>(null);
  final ValueNotifier<PdfCopiedReference?> _copiedPdfReferenceNotifier =
      ValueNotifier<PdfCopiedReference?>(null);

  final ValueNotifier<DocumentNoteReferenceInsertionRequest?>
  _documentNoteReferenceInsertionRequestNotifier =
      ValueNotifier<DocumentNoteReferenceInsertionRequest?>(null);

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
  OverlayEntry? _todosOverlayEntry;

  PdfReaderSessionState? _restoredSession;

  String? _selectedText;
  List<PdfSourceRect> _selectedSourceRects = const [];

  double _pdfPaneFraction = 0.5;

  PdfReaderWorkspaceLayout _workspaceLayout = PdfReaderWorkspaceLayout.sidecar;
  PdfReaderTool _activeTool = PdfReaderTool.cursor;
  int _activeHighlightColorValue = kDefaultPdfHighlightColorValue;

  bool _pdfSearchOpen = false;
  bool _sessionLoaded = false;
  bool _didRestorePdfViewport = false;
  bool _latestOutlineOpen = false;
  bool _latestDebugEnabled = false;

  int _selectionRequestId = 0;
  int _sidecarCreateRequestId = 0;
  int _revealNoteRequestId = 0;
  int _documentNoteReferenceInsertionRequestId = 0;

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
          _persistentHighlightRegionsNotifier.value = List.unmodifiable(
            regions,
          );
        });

    _loadReaderSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _screenFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _closeTodosPanel();
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
    _copiedPdfReferenceNotifier.dispose();
    _documentNoteReferenceInsertionRequestNotifier.dispose();
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
    _sessionSaveDebounce = Timer(const Duration(milliseconds: 550), () {
      unawaited(_saveReaderSessionNow());
    });
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
      session.visibleCenterX <= 0
          ? visibleRect.center.dx
          : session.visibleCenterX,
      targetTop + visibleRect.height / 2,
    );

    final matrix = _controller.calcMatrixFor(targetCenter, zoom: zoom);

    unawaited(
      _controller.goTo(matrix, duration: Duration.zero).whenComplete(() {
        if (!mounted) {
          return;
        }

        _publishViewportStateForNextFrames();
      }),
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

  KeyEventResult _handleScreenKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrlC =
        event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isControlPressed;

    if (isCtrlC && _hasActiveSelection) {
      unawaited(_copyPdfSelectionAsReference());
      return KeyEventResult.handled;
    }

    final isCtrlF =
        event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed;

    if (isCtrlF) {
      _openPdfSearch();
      return KeyEventResult.handled;
    }

    final isCtrlShiftF =
        event.logicalKey == LogicalKeyboardKey.keyF &&
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
    if (_workspaceLayout == PdfReaderWorkspaceLayout.reader ||
        _workspaceLayout == PdfReaderWorkspaceLayout.document) {
      setState(() {
        _workspaceLayout = PdfReaderWorkspaceLayout.sidecar;
      });
    }

    _outlineSearchFocusRequestNotifier.value =
        _outlineSearchFocusRequestNotifier.value + 1;
  }

  void _handleReaderToolChanged(PdfReaderTool tool) {
    if (_activeTool == tool) {
      return;
    }

    setState(() {
      _activeTool = tool;
    });

    if (tool == PdfReaderTool.eraser) {
      _showSnackBar('Eraser active: tap a highlight to remove it');
    }
  }

  void _handleHighlightColorChanged(int colorValue) {
    setState(() {
      _activeHighlightColorValue = colorValue;
      _activeTool = PdfReaderTool.highlight;
    });
  }

  void _activateToolForSelection(NoteCreationType creationType) {
    if (creationType == NoteCreationType.highlight) {
      _handleReaderToolChanged(PdfReaderTool.highlight);
      return;
    }

    if (creationType == NoteCreationType.citation) {
      _handleReaderToolChanged(PdfReaderTool.citation);
      return;
    }

    _handleReaderToolChanged(PdfReaderTool.note);
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

  void _publishViewportStateForNextFrames({int frameCount = 3}) {
    if (frameCount <= 0) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _publishViewportState();
      _publishViewportStateForNextFrames(frameCount: frameCount - 1);
    });
  }

  PdfViewportState _readViewportStateFromController() {
    final pageCount = _controller.pageCount <= 0 ? 1 : _controller.pageCount;
    final currentPage = (_controller.pageNumber ?? 1)
        .clamp(1, pageCount)
        .toInt();

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
      _readSelectedTextAndRects(textSelection)
          .then((selectionData) {
            if (!mounted || requestId != _selectionRequestId) {
              return;
            }

            setState(() {
              _selectedText = selectionData.selectedText.isEmpty
                  ? null
                  : selectionData.selectedText;
              _selectedSourceRects = selectionData.sourceRects;
            });
          })
          .catchError((error) {
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

    unawaited(_controller.goTo(matrix, duration: Duration.zero));
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
      _controller.goTo(matrix, duration: const Duration(milliseconds: 140)),
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
      highlightColorValue: _activeHighlightColorValue,
      highlightOpacity: kDefaultPdfHighlightOpacity,
    );
  }

  PdfCopiedReference? _currentPdfSelectionReference() {
    final selectedText = _selectedText?.trim();
    final sourceRects = _selectedSourceRects
        .where((rect) => rect.isValid)
        .toList(growable: false);

    if (selectedText == null || selectedText.isEmpty || sourceRects.isEmpty) {
      return null;
    }

    return PdfCopiedReference(
      documentId: widget.documentId,
      pageNumber: sourceRects.first.pageNumber,
      selectedText: selectedText,
      sourceRects: sourceRects,
      copiedAt: DateTime.now(),
    );
  }

  Future<void> _copyPdfSelectionAsReference() async {
    final reference = _currentPdfSelectionReference();

    if (reference == null) {
      return;
    }

    _copiedPdfReferenceNotifier.value = reference;

    await Clipboard.setData(ClipboardData(text: reference.selectedText));

    if (!mounted) {
      return;
    }

    _showSnackBar('Copied PDF text as a reference');
  }

  void _insertCurrentSelectionIntoDocumentNote({required int pageNumber}) {
    final reference = _currentPdfSelectionReference();

    if (reference == null) {
      _showSnackBar('Select PDF text first');
      return;
    }

    if (_workspaceLayout != PdfReaderWorkspaceLayout.synthesis) {
      setState(() {
        _workspaceLayout = PdfReaderWorkspaceLayout.document;
      });
    }

    _copiedPdfReferenceNotifier.value = reference;
    _documentNoteReferenceInsertionRequestNotifier.value =
        DocumentNoteReferenceInsertionRequest(
          requestId: ++_documentNoteReferenceInsertionRequestId,
          reference: reference,
        );
  }

  Future<void> _createTodoFromSelection({required int pageNumber}) async {
    final reference = _currentPdfSelectionReference();

    if (reference == null) {
      _showSnackBar('Select PDF text first');
      return;
    }

    await _noteRepository.createPdfTextSelectionTodo(
      documentId: widget.documentId,
      pageNumber: pageNumber,
      selectedText: reference.selectedText,
      sourceRects: reference.sourceRects,
    );

    if (!mounted) return;

    _showSnackBar('TODO created from PDF selection');
  }

  void _openTodosPanel([BuildContext? anchorContext]) {
    if (_todosOverlayEntry != null) {
      _closeTodosPanel();
      return;
    }

    final overlay = Overlay.of(context);
    final overlayRenderObject = overlay.context.findRenderObject();

    if (overlayRenderObject is! RenderBox) {
      return;
    }

    final overlaySize = overlayRenderObject.size;
    final anchorRenderObject = anchorContext?.findRenderObject();

    final Rect anchorRect;
    if (anchorRenderObject is RenderBox) {
      final anchorOffset = anchorRenderObject.localToGlobal(
        Offset.zero,
        ancestor: overlayRenderObject,
      );
      anchorRect = anchorOffset & anchorRenderObject.size;
    } else {
      anchorRect = Rect.fromLTWH(
        overlaySize.width - 72,
        kToolbarHeight / 2,
        44,
        44,
      );
    }

    const margin = 12.0;
    const gap = 8.0;
    final panelWidth = math.min(720.0, overlaySize.width - margin * 2);
    final panelHeight = math.min(
      680.0,
      overlaySize.height - anchorRect.bottom - margin - gap,
    );
    final left = (anchorRect.right - panelWidth)
        .clamp(margin, overlaySize.width - panelWidth - margin)
        .toDouble();
    final top = (anchorRect.bottom + gap)
        .clamp(margin, overlaySize.height - panelHeight - margin)
        .toDouble();
    final arrowCenterX = (anchorRect.center.dx - left)
        .clamp(18.0, panelWidth - 18.0)
        .toDouble();

    _todosOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeTodosPanel,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: panelWidth,
              height: panelHeight,
              child: Material(
                color: Colors.transparent,
                child: _TodoDropdownSurface(
                  arrowCenterX: arrowCenterX,
                  child: PdfTodoPanel(
                    noteRepository: _noteRepository,
                    currentDocumentId: widget.documentId,
                    onClose: _closeTodosPanel,
                    onJumpToTodo: (todo) {
                      _closeTodosPanel();
                      _jumpToTodoSource(todo);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_todosOverlayEntry!);
  }

  void _closeTodosPanel() {
    _todosOverlayEntry?.remove();
    _todosOverlayEntry = null;
  }

  void _jumpToTodoSource(TodoItem todo) {
    final documentId = todo.note.documentId;
    if (documentId != widget.documentId) {
      _showSnackBar('Open ${todo.pdfLabel} to jump to this TODO source');
      return;
    }

    final sourceRects = todo.sourceRects;
    final pageNumber =
        todo.pageNumber ??
        (sourceRects.isEmpty
            ? _viewportNotifier.value.safeCurrentPage
            : sourceRects.first.pageNumber);

    _jumpToPdfSource(pageNumber: pageNumber, sourceRects: sourceRects);
  }

  void _jumpToDocumentNoteReference(DocumentNotePdfReference reference) {
    _jumpToPdfSource(
      pageNumber: reference.pageNumber,
      sourceRects: reference.sourceRects,
    );
  }

  void _jumpToPdfSource({
    required int pageNumber,
    required List<PdfSourceRect> sourceRects,
  }) {
    if (!_controller.isReady) {
      return;
    }

    final safePageNumber = pageNumber.clamp(1, _controller.pageCount).toInt();
    final layouts = _controller.layout.pageLayouts;

    if (layouts.isEmpty || safePageNumber > layouts.length) {
      return;
    }

    final visibleRect = _controller.visibleRect;
    final documentSize = _controller.documentSize;
    final pageRect = layouts[safePageNumber - 1];

    if (visibleRect == Rect.zero ||
        visibleRect.height <= 0 ||
        documentSize.height <= 0) {
      return;
    }

    final targetY = sourceRects.isEmpty
        ? pageRect.top
        : pageRect.top + pageRect.height * 0.20;

    final maxTop = math.max(0.0, documentSize.height - visibleRect.height);
    final targetTop = (targetY - visibleRect.height * 0.25)
        .clamp(0.0, maxTop)
        .toDouble();

    final targetCenter = Offset(
      pageRect.center.dx,
      targetTop + visibleRect.height / 2,
    );

    final matrix = _controller.calcMatrixFor(
      targetCenter,
      zoom: _controller.currentZoom,
    );

    unawaited(
      _controller.goTo(matrix, duration: const Duration(milliseconds: 180)),
    );

    _hoverHighlightRectsNotifier.value = List.unmodifiable(sourceRects);

    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      if (_sourceRectListsEqual(
        _hoverHighlightRectsNotifier.value,
        sourceRects,
      )) {
        _hoverHighlightRectsNotifier.value = const [];
      }
    });
  }

  void _handlePersistentHighlightActivated(PdfLinkedHighlightRegion region) {
    if (_activeTool == PdfReaderTool.eraser) {
      unawaited(_deletePersistentHighlight(region));
      return;
    }

    if (region.noteType == kTodoNoteType) {
      _openTodosPanel();
      return;
    }

    if (region.hasSidecarNote) {
      _revealSidecarNote(region.noteId);
      return;
    }

    _showPersistentHighlightActions(region);
  }

  void _handlePersistentHighlightLongPressed(PdfLinkedHighlightRegion region) {
    _showPersistentHighlightActions(region);
  }

  void _revealSidecarNote(String noteId) {
    _revealNoteRequestNotifier.value = SidecarRevealNoteRequest(
      requestId: ++_revealNoteRequestId,
      noteId: noteId,
    );
  }

  Future<void> _showPersistentHighlightActions(
    PdfLinkedHighlightRegion region,
  ) async {
    if (!mounted) {
      return;
    }

    final selectedText = region.selectedText?.trim();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: const Text('Reveal linked note'),
                subtitle: region.hasSidecarNote
                    ? null
                    : const Text(
                        'This highlight is not linked to a sidecar note',
                      ),
                enabled: region.hasSidecarNote,
                onTap: () {
                  Navigator.of(context).pop();
                  _revealSidecarNote(region.noteId);
                },
              ),
              if (region.noteType == kTodoNoteType)
                ListTile(
                  leading: const Icon(Icons.task_alt),
                  title: const Text('Open TODOs'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openTodosPanel();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy highlighted text'),
                enabled: selectedText != null && selectedText.isNotEmpty,
                onTap: () async {
                  Navigator.of(context).pop();

                  if (selectedText == null || selectedText.isEmpty) {
                    return;
                  }

                  await Clipboard.setData(ClipboardData(text: selectedText));

                  _showSnackBar('Highlighted text copied');
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _HighlightColorPickerRow(
                  selectedColorValue: region.highlightColorValue,
                  onColorSelected: (colorValue) {
                    Navigator.of(context).pop();
                    unawaited(
                      _updatePersistentHighlightColor(
                        region: region,
                        colorValue: colorValue,
                      ),
                    );
                  },
                ),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text(
                  region.hasSidecarNote
                      ? 'Remove highlight from note'
                      : 'Delete highlight',
                  style: TextStyle(color: colorScheme.error),
                ),
                subtitle: region.hasSidecarNote
                    ? const Text(
                        'The note stays; only the PDF highlight is hidden',
                      )
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_deletePersistentHighlight(region));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updatePersistentHighlightColor({
    required PdfLinkedHighlightRegion region,
    required int colorValue,
  }) async {
    await _noteRepository.updatePersistentHighlightStyle(
      region: region,
      highlightColorValue: colorValue,
      highlightOpacity: region.highlightOpacity,
      highlightStyle: region.highlightStyle,
    );

    if (!mounted) {
      return;
    }

    _showSnackBar('Highlight color updated');
  }

  Future<void> _deletePersistentHighlight(
    PdfLinkedHighlightRegion region,
  ) async {
    await _noteRepository.removePersistentHighlightRegion(region);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          region.hasSidecarNote
              ? 'Highlight removed from note'
              : 'Highlight deleted',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(_noteRepository.restorePersistentHighlightRegion(region));
          },
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            ? [searcher.pageTextMatchPaintCallback]
            : const [],
        pageOverlaysBuilder: (context, pageRectInViewer, page) {
          return [
            PdfHoverHighlightOverlay(
              persistentRegionsListenable: _persistentHighlightRegionsNotifier,
              hoverSourceRectsListenable: _hoverHighlightRectsNotifier,
              pageRectInViewer: pageRectInViewer,
              page: page,
              eraseMode: _activeTool == PdfReaderTool.eraser,
              onHighlightActivated: _handlePersistentHighlightActivated,
              onHighlightLongPressed: _handlePersistentHighlightLongPressed,
            ),
            PdfSelectionActionOverlay(
              selectedText: _selectedText,
              selectedSourceRects: _selectedSourceRects,
              pageRectInViewer: pageRectInViewer,
              page: page,
              activeTool: _activeTool,
              activeHighlightColorValue: _activeHighlightColorValue,
              onCreateNote:
                  ({
                    required NoteCreationType creationType,
                    required int pageNumber,
                    required double normalizedY,
                  }) {
                    _activateToolForSelection(creationType);
                    _requestSidecarNoteFromSelection(
                      creationType: creationType,
                      pageNumber: pageNumber,
                      normalizedY: normalizedY,
                    );
                  },
              onCreateHighlight: _createPersistentHighlightFromSelection,
              onAddToDocumentNote: _insertCurrentSelectionIntoDocumentNote,
              onCreateTodo: _createTodoFromSelection,
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
        onViewSizeChanged: (oldSize, newSize, pageLayouts) {
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
            return const Center(child: CircularProgressIndicator());
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
                      Text(error.toString(), textAlign: TextAlign.center),
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

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _publishViewportStateForNextFrames();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(child: _buildPdfViewer()),
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
      ),
    );
  }

  Widget _buildWorkspaceSelector() {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SegmentedButton<PdfReaderWorkspaceLayout>(
          segments: const [
            ButtonSegment<PdfReaderWorkspaceLayout>(
              value: PdfReaderWorkspaceLayout.reader,
              icon: Icon(Icons.picture_as_pdf_outlined),
              label: Text('Reader'),
            ),
            ButtonSegment<PdfReaderWorkspaceLayout>(
              value: PdfReaderWorkspaceLayout.sidecar,
              icon: Icon(Icons.view_sidebar_outlined),
              label: Text('Sidecar'),
            ),
            ButtonSegment<PdfReaderWorkspaceLayout>(
              value: PdfReaderWorkspaceLayout.document,
              icon: Icon(Icons.article_outlined),
              label: Text('Document'),
            ),
            ButtonSegment<PdfReaderWorkspaceLayout>(
              value: PdfReaderWorkspaceLayout.synthesis,
              icon: Icon(Icons.view_column_outlined),
              label: Text('Synthesis'),
            ),
          ],
          selected: {_workspaceLayout},
          onSelectionChanged: (selection) {
            setState(() {
              _workspaceLayout = selection.first;
            });

            _scheduleReaderSessionSave();

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _publishViewportState();
            });
          },
        ),
      ),
    );
  }

  Widget _buildSidecarPane() {
    return PdfSidecarNotesCanvas(
      noteRepository: _noteRepository,
      documentId: widget.documentId,
      viewportListenable: _viewportNotifier,
      selectedText: _selectedText,
      selectedSourceRects: _selectedSourceRects,
      externalCreateRequestListenable: _sidecarCreateRequestNotifier,
      revealNoteRequestListenable: _revealNoteRequestNotifier,
      outlineSearchFocusRequestListenable: _outlineSearchFocusRequestNotifier,
      initialOutlineOpen: _latestOutlineOpen,
      initialDebugEnabled: _latestDebugEnabled,
      onSidecarPreferencesChanged: _handleSidecarPreferencesChanged,
      onHoveredSourceRectsChanged: _handleHoveredSourceRectsChanged,
      onSidecarScrollDelta: _handleSidecarScrollDelta,
      onRequestPdfJumpToDocumentY: _handleRequestPdfJumpToDocumentY,
    );
  }

  Widget _buildDocumentPane() {
    return PdfDocumentNotesPanel(
      noteRepository: _noteRepository,
      documentId: widget.documentId,
      documentTitle: widget.title,
      selectedText: _selectedText,
      selectedSourceRects: _selectedSourceRects,
      copiedReferenceListenable: _copiedPdfReferenceNotifier,
      externalReferenceInsertionListenable:
          _documentNoteReferenceInsertionRequestNotifier,
      onJumpToReference: _jumpToDocumentNoteReference,
    );
  }

  Widget _buildVerticalDivider({GestureDragUpdateCallback? onDragUpdate}) {
    final theme = Theme.of(context);

    final divider = Container(
      width: _dividerWidth,
      color: theme.colorScheme.outlineVariant,
      child: Center(
        child: Container(width: 2, color: theme.colorScheme.outline),
      ),
    );

    if (onDragUpdate == null) {
      return divider;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: onDragUpdate,
        child: divider,
      ),
    );
  }

  Widget _buildWorkspaceBody() {
    return switch (_workspaceLayout) {
      PdfReaderWorkspaceLayout.reader => _buildPdfPane(),
      PdfReaderWorkspaceLayout.sidecar => _buildTwoPaneBody(
        notesPaneBuilder: _buildSidecarPane,
      ),
      PdfReaderWorkspaceLayout.document => _buildTwoPaneBody(
        notesPaneBuilder: _buildDocumentPane,
      ),
      PdfReaderWorkspaceLayout.synthesis => _buildSynthesisBody(),
    };
  }

  Widget _buildTwoPaneBody({required Widget Function() notesPaneBuilder}) {
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
            .clamp(minFraction, maxFraction)
            .toDouble();

        final pdfPaneWidth = availableWidth * safePdfPaneFraction;
        final notesPaneWidth = availableWidth - pdfPaneWidth;

        return Row(
          children: [
            SizedBox(width: pdfPaneWidth, child: _buildPdfPane()),
            _buildVerticalDivider(
              onDragUpdate: (details) {
                setState(() {
                  final newPdfWidth = pdfPaneWidth + details.delta.dx;

                  _pdfPaneFraction = (newPdfWidth / availableWidth)
                      .clamp(minFraction, maxFraction)
                      .toDouble();
                });

                _scheduleReaderSessionSave();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _publishViewportState();
                });
              },
            ),
            SizedBox(width: notesPaneWidth, child: notesPaneBuilder()),
          ],
        );
      },
    );
  }

  Widget _buildSynthesisBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        if (totalWidth < (_minPaneWidth * 3 + _dividerWidth * 2)) {
          return _buildTwoPaneBody(notesPaneBuilder: _buildDocumentPane);
        }

        return Row(
          children: [
            Expanded(flex: 5, child: _buildPdfPane()),
            _buildVerticalDivider(),
            Expanded(flex: 3, child: _buildSidecarPane()),
            _buildVerticalDivider(),
            Expanded(flex: 4, child: _buildDocumentPane()),
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
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
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
            StreamBuilder<List<TodoItem>>(
              stream: _noteRepository.watchTodos(includeCompleted: false),
              builder: (context, snapshot) {
                return PdfReaderToolbar(
                  activeTool: _activeTool,
                  activeHighlightColorValue: _activeHighlightColorValue,
                  hasActiveSelection: _hasActiveSelection,
                  activeTodoCount: snapshot.data?.length ?? 0,
                  onToolChanged: _handleReaderToolChanged,
                  onHighlightColorChanged: _handleHighlightColorChanged,
                  onOpenPdfSearch: _openPdfSearch,
                  onOpenNotesOutlineSearch: _openNotesOutlineSearch,
                  onOpenTodos: (buttonContext) =>
                      _openTodosPanel(buttonContext),
                );
              },
            ),
            ValueListenableBuilder<PdfViewportState>(
              valueListenable: _viewportNotifier,
              builder: (context, viewport, _) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      'Page ${viewport.safeCurrentPage} / ${viewport.safePageCount} | '
                      'Zoom ${viewport.zoom.toStringAsFixed(2)}',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            _buildWorkspaceSelector(),
            Expanded(child: _buildWorkspaceBody()),
          ],
        ),
      ),
    );
  }
}

class _HighlightColorPickerRow extends StatelessWidget {
  final int selectedColorValue;
  final ValueChanged<int> onColorSelected;

  const _HighlightColorPickerRow({
    required this.selectedColorValue,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Highlight color', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in pdfHighlightColorOptions)
              ChoiceChip(
                selected: option.colorValue == selectedColorValue,
                label: Text(option.label),
                avatar: CircleAvatar(radius: 7, backgroundColor: option.color),
                onSelected: (_) => onColorSelected(option.colorValue),
              ),
          ],
        ),
      ],
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

class _TodoDropdownSurface extends StatelessWidget {
  final double arrowCenterX;
  final Widget child;

  const _TodoDropdownSurface({required this.arrowCenterX, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -7,
          left: arrowCenterX - 8,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  left: BorderSide(color: theme.colorScheme.outlineVariant),
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}
