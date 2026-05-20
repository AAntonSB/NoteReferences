import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import '../../home/presentation/study_home_screen.dart';
import '../../planning/data/study_planning_repository.dart';
import '../../planning/domain/study_material_source.dart';
import '../../planning/presentation/dev_todo_drawer.dart';
import '../../planning/presentation/document_workspace_screen.dart';
import '../../planning/presentation/project_quick_access_sheet.dart';
import '../../planning/presentation/session_handoff_dialog.dart';
import '../../planning/presentation/workspace_document_editor_screen.dart';
import '../../settings/data/app_settings_controller.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../reader/domain/source_reader_workspace_layout.dart';
import '../../reader/presentation/source_reader_split_layout.dart';
import '../../reader/presentation/source_reader_workspace_selector.dart';
import '../../library/data/pdf_metadata_extractor.dart';
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

class PdfReaderScreen extends StatefulWidget {
  final AppDatabase database;
  final String documentId;
  final String filePath;
  final String title;
  final StudyPlanningRepository? planningRepository;

  const PdfReaderScreen({
    super.key,
    required this.database,
    required this.documentId,
    required this.filePath,
    required this.title,
    this.planningRepository,
    this.initialPageNumber,
    this.initialSourceRects = const <PdfSourceRect>[],
    this.initialSidecarNoteId,
    this.initialOpenLabel,
  });

  final int? initialPageNumber;
  final List<PdfSourceRect> initialSourceRects;
  final String? initialSidecarNoteId;
  final String? initialOpenLabel;

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
  late final StudyPlanningRepository _planningRepository;
  late final bool _ownsPlanningRepository;

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

  SourceReaderWorkspaceLayout _workspaceLayout = SourceReaderWorkspaceLayout.sidecar;
  String? _activeWorkspaceDocumentId;
  PdfReaderTool _activeTool = PdfReaderTool.cursor;
  int _activeHighlightColorValue = kDefaultPdfHighlightColorValue;

  bool _pdfSearchOpen = false;
  bool _sessionLoaded = false;
  bool _planningLoaded = false;
  bool _didRestorePdfViewport = false;
  bool _didApplyInitialLocator = false;
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
    _ownsPlanningRepository = widget.planningRepository == null;
    _planningRepository = widget.planningRepository ?? StudyPlanningRepository();

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
    unawaited(_loadPlanningRepository());

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
    if (_ownsPlanningRepository) {
      _planningRepository.dispose();
    }

    super.dispose();
  }

  Future<void> _loadReaderSession() async {
    final session = await _sessionStore.load(widget.documentId);

    if (!mounted) return;

    setState(() {
      _restoredSession = session;
      _pdfPaneFraction = session?.pdfPaneFraction ?? 0.5;
      _latestOutlineOpen = false;
      _latestDebugEnabled = session?.debugEnabled ?? false;
      _sessionLoaded = true;
    });
  }

  Future<void> _loadPlanningRepository() async {
    if (!_planningRepository.isLoaded) {
      await _planningRepository.load();
    }
    if (!mounted) return;
    setState(() => _planningLoaded = true);
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

  bool get _hasInitialOpenLocator {
    final pageNumber = widget.initialPageNumber;
    final sidecarNoteId = widget.initialSidecarNoteId?.trim();
    return (pageNumber != null && pageNumber > 0) ||
        (sidecarNoteId != null && sidecarNoteId.isNotEmpty);
  }

  void _applyInitialOpenLocatorIfNeeded({int attemptsLeft = 8}) {
    if (_didApplyInitialLocator || !_hasInitialOpenLocator || !mounted) {
      return;
    }

    if (!_controller.isReady ||
        _controller.visibleRect == Rect.zero ||
        _controller.visibleRect.height <= 0 ||
        _controller.layout.pageLayouts.isEmpty) {
      if (attemptsLeft <= 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialOpenLocatorIfNeeded(attemptsLeft: attemptsLeft - 1);
      });
      return;
    }

    _didApplyInitialLocator = true;

    final pageNumber = widget.initialPageNumber;
    if (pageNumber != null && pageNumber > 0) {
      _jumpToPdfSource(
        pageNumber: pageNumber,
        sourceRects: widget.initialSourceRects,
      );
    }

    final sidecarNoteId = widget.initialSidecarNoteId?.trim();
    if (sidecarNoteId != null && sidecarNoteId.isNotEmpty) {
      if (_workspaceLayout != SourceReaderWorkspaceLayout.sidecar) {
        setState(() => _workspaceLayout = SourceReaderWorkspaceLayout.sidecar);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealSidecarNote(sidecarNoteId, pageNumber: pageNumber);
      });
    }

    final label = widget.initialOpenLabel?.trim();
    if (label != null && label.isNotEmpty) {
      _showSnackBar('Opened source target: $label');
    }
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
    if (_workspaceLayout != SourceReaderWorkspaceLayout.sidecar &&
        _workspaceLayout != SourceReaderWorkspaceLayout.synthesis) {
      setState(() {
        _workspaceLayout = SourceReaderWorkspaceLayout.sidecar;
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
      if (_hasInitialOpenLocator) {
        _applyInitialOpenLocatorIfNeeded();
      } else {
        _restorePdfViewportIfNeeded();
      }
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

    if (_workspaceLayout != SourceReaderWorkspaceLayout.synthesis) {
      setState(() {
        _workspaceLayout = SourceReaderWorkspaceLayout.document;
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
                    onConvertToProjectTask: _convertPdfTodoToProjectTask,
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

  Future<void> _convertPdfTodoToProjectTask(TodoItem todo) async {
    if (!_planningRepository.isLoaded) {
      await _planningRepository.load();
      if (!mounted) return;
      setState(() => _planningLoaded = true);
    }

    final project = _planningRepository.projectForPdf(widget.documentId);
    if (project == null) {
      _showSnackBar('Assign this PDF to a project before converting TODOs into project tasks.');
      return;
    }

    final dueDate = _dateOnly(todo.deadline ?? DateTime.now().add(const Duration(days: 1)));
    await _planningRepository.createPlan(
      projectId: project.id,
      title: todo.title.trim().isEmpty ? 'PDF TODO' : todo.title.trim(),
      unitType: 'task',
      planKind: StudyPlanKind.singleTask,
      startDate: dueDate,
      weekendsOff: false,
      taskDate: dueDate,
      deadline: dueDate,
    );

    if (!mounted) return;
    _showSnackBar('Added “${todo.title}” to ${project.title} as a project task.');
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

    final rectsForPage = sourceRects
        .where((rect) => rect.pageNumber == safePageNumber)
        .toList(growable: false);

    final targetY = rectsForPage.isEmpty
        ? pageRect.top
        : pageRect.top +
            ((rectsForPage
                        .map((rect) => math.min(rect.top, rect.bottom))
                        .reduce(math.min) +
                    rectsForPage
                        .map((rect) => math.max(rect.top, rect.bottom))
                        .reduce(math.max)) /
                2)
                .clamp(0.0, pageRect.height)
                .toDouble();

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

  void _revealSidecarNote(String noteId, {int? pageNumber}) {
    _revealNoteRequestNotifier.value = SidecarRevealNoteRequest(
      requestId: ++_revealNoteRequestId,
      noteId: noteId,
      pageNumber: pageNumber,
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

  Future<void> _openProjectsPanel(BuildContext _) async {
    if (!_planningRepository.isLoaded) {
      await _planningRepository.load();
      if (!mounted) return;
      setState(() => _planningLoaded = true);
    }

    if (!mounted) return;
    await showProjectQuickAccessSheet(
      context: context,
      planningRepository: _planningRepository,
      sourceLabel: widget.title,
      database: widget.database,
      initialMaterialSource: await _currentPdfMaterialSource(),
    );
  }

  Future<StudyMaterialSource> _currentPdfMaterialSource() async {
    int? pageCount;
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        pageCount = (await PdfMetadataExtractor().extract(file)).pageCount;
      }
    } catch (_) {
      pageCount = null;
    }

    return StudyMaterialSource(
      type: StudyMaterialSourceType.currentFile,
      title: widget.title,
      libraryDocumentId: widget.documentId,
      filePath: widget.filePath,
      pageCount: pageCount,
      startPage: pageCount == null ? null : 1,
      endPage: pageCount,
      notes: pageCount == null ? null : '$pageCount PDF pages detected',
    );
  }

  Future<void> _openCalendarOverview() async {
    await showStudyCalendarModal(
      context: context,
      planningRepository: _planningRepository,
      noteRepository: _noteRepository,
      onOpenTodo: _openTodoSourceFromCalendar,
    );
  }

  Future<void> _openTodayBriefing() async {
    await showTodayBriefingModal(
      context: context,
      database: widget.database,
      planningRepository: _planningRepository,
    );
  }

  Future<void> _openDevTodos() async {
    await showDevTodoDrawer(
      context: context,
      planningRepository: _planningRepository,
    );
  }

  Future<void> _openTodoSourceFromCalendar(TodoItem todo) async {
    final documentId = todo.note.documentId;
    if (documentId == null || documentId.trim().isEmpty) {
      _showSnackBar('This todo is not linked to a PDF yet.');
      return;
    }

    final documents = await widget.database.getAllDocuments();
    PdfDocument? document;
    for (final candidate in documents) {
      if (candidate.documentId == documentId) {
        document = candidate;
        break;
      }
    }

    if (!mounted) return;
    if (document == null) {
      _showSnackBar('Could not find the linked document.');
      return;
    }

    if (document.documentId == widget.documentId) {
      _showSnackBar('This todo is linked to the PDF you already have open.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfReaderScreen(
          database: widget.database,
          documentId: document!.documentId,
          filePath: document!.filePath,
          title: document!.name,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _endAssignedProjectSession() async {
    if (!_planningRepository.isLoaded) {
      await _planningRepository.load();
      if (!mounted) return;
      setState(() => _planningLoaded = true);
    }

    final project = _planningRepository.projectForPdf(widget.documentId);
    if (project == null) {
      _showSnackBar('Assign this PDF to a project before ending a project session.');
      return;
    }

    final items = await showDialog<List<String>>(
      context: context,
      builder: (_) => EndSessionDialog(projectTitle: project.title),
    );
    if (items == null || items.isEmpty) return;

    await _planningRepository.addSessionHandoffItems(
      projectId: project.id,
      itemTexts: items,
    );

    if (!mounted) return;
    _showSnackBar('Saved ${items.length} next-session ${items.length == 1 ? 'item' : 'items'} for ${project.title}.');
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const SettingsScreen(),
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
      initialPageNumber: widget.initialPageNumber ?? _viewportNotifier.value.currentPage,
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
    return SourceReaderWorkspaceSelector(
      selected: _workspaceLayout,
      readerIcon: Icons.picture_as_pdf_outlined,
      onChanged: (layout) {
        setState(() {
          _workspaceLayout = layout;
        });

        _scheduleReaderSessionSave();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _publishViewportState();
        });
      },
      trailing: FilledButton.tonalIcon(
        onPressed: () => _openProjectsPanel(context),
        icon: const Icon(Icons.dashboard_customize_outlined),
        label: const Text('Projects'),
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
      initialOutlineOpen: false,
      initialDebugEnabled: _latestDebugEnabled,
      onSidecarPreferencesChanged: _handleSidecarPreferencesChanged,
      onHoveredSourceRectsChanged: _handleHoveredSourceRectsChanged,
      onSidecarScrollDelta: _handleSidecarScrollDelta,
      onRequestPdfJumpToDocumentY: _handleRequestPdfJumpToDocumentY,
      appSettings: AppSettingsScope.of(context).settings,
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

  Widget _buildWorkspaceDocumentPane() {
    if (!_planningLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return AnimatedBuilder(
      animation: _planningRepository,
      builder: (context, _) {
        final project = _planningRepository.projectForPdf(widget.documentId);
        if (project == null) {
          return _WorkspaceDocumentEmptyPane(
            title: 'No project assigned',
            message: 'Assign this PDF to a project to write project documents beside it.',
            actionLabel: 'Open projects',
            onAction: () => _openProjectsPanel(context),
          );
        }

        final documents = _planningRepository.documentsForProject(project.id);
        WorkspaceDocument? selectedDocument;
        for (final document in documents) {
          if (document.id == _activeWorkspaceDocumentId) {
            selectedDocument = document;
            break;
          }
        }
        selectedDocument ??= documents.isEmpty ? null : documents.first;

        if (selectedDocument == null) {
          return _WorkspaceDocumentEmptyPane(
            title: 'No project documents yet',
            message: 'Create a writing document for notes, drafts, job ads, summaries, or templates. It will stay attached to “${project.title}”.',
            actionLabel: 'Create document',
            onAction: () => _createWorkspaceDocumentForProject(project),
          );
        }

        final activeDocument = selectedDocument;

        return Column(
          children: [
            _WorkspaceDocumentPaneHeader(
              projectTitle: project.title,
              documents: documents,
              selectedDocumentId: activeDocument.id,
              onDocumentChanged: (documentId) {
                setState(() => _activeWorkspaceDocumentId = documentId);
              },
              onCreateDocument: () => _createWorkspaceDocumentForProject(project),
              onOpenWorkspace: () => _openDocumentWorkspace(
                projectId: project.id,
                initialDocumentId: activeDocument.id,
              ),
            ),
            Expanded(
              child: WorkspaceDocumentEditorSurface(
                planningRepository: _planningRepository,
                documentId: activeDocument.id,
                embedded: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createWorkspaceDocumentForProject(StudyProject project) async {
    final document = await _planningRepository.createDocument(
      title: 'Notes for ${widget.title}',
      kind: WorkspaceDocumentKind.working,
      body: '',
      tags: const <String>['notes'],
      projectIds: <String>[project.id],
    );
    if (!mounted) return;
    setState(() {
      _activeWorkspaceDocumentId = document.id;
      _workspaceLayout = SourceReaderWorkspaceLayout.workspaceDocument;
    });
  }

  Future<void> _openDocumentWorkspace({String? projectId, String? initialDocumentId}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DocumentWorkspaceScreen(
          planningRepository: _planningRepository,
          projectId: projectId,
          initialDocumentId: initialDocumentId,
        ),
      ),
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

  Widget _buildAssignedProjectHeader() {
    if (!_planningLoaded) return const SizedBox.shrink();
    final project = _planningRepository.projectForPdf(widget.documentId);
    if (project == null) return const SizedBox.shrink();

    final today = _dateOnly(DateTime.now());
    final requirements = _planningRepository
        .requirementsForRange(rangeStart: today, rangeEnd: today, now: DateTime.now())
        .where((requirement) => requirement.project?.id == project.id)
        .toList(growable: false);
    final handoffCount = _planningRepository.activeHandoffEntries(projectId: project.id).length;

    return _ReaderProjectContextHeader(
      projectTitle: project.title,
      requirements: requirements,
      handoffCount: handoffCount,
      onOpenProject: () => _openProjectsPanel(context),
      onOpenCalendar: _openCalendarOverview,
      onEndSession: _endAssignedProjectSession,
    );
  }

  Widget _buildWorkspaceBody() {
    return switch (_workspaceLayout) {
      SourceReaderWorkspaceLayout.reader => _buildPdfPane(),
      SourceReaderWorkspaceLayout.sidecar => _buildTwoPaneBody(
        notesPaneBuilder: _buildSidecarPane,
      ),
      SourceReaderWorkspaceLayout.document => _buildTwoPaneBody(
        notesPaneBuilder: _buildDocumentPane,
      ),
      SourceReaderWorkspaceLayout.workspaceDocument => _buildTwoPaneBody(
        notesPaneBuilder: _buildWorkspaceDocumentPane,
      ),
      SourceReaderWorkspaceLayout.synthesis => _buildSynthesisBody(),
    };
  }

  Widget _buildTwoPaneBody({required Widget Function() notesPaneBuilder}) {
    return SourceReaderTwoPaneLayout(
      readerBuilder: _buildPdfPane,
      paneBuilder: notesPaneBuilder,
      paneFraction: _pdfPaneFraction,
      minPaneWidth: _minPaneWidth,
      dividerWidth: _dividerWidth,
      onPaneFractionChanged: (fraction) {
        setState(() => _pdfPaneFraction = fraction);
        _scheduleReaderSessionSave();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _publishViewportState();
        });
      },
      onPaneFractionChangeCommitted: () {
        _scheduleReaderSessionSave();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _publishViewportState();
        });
      },
    );
  }

  Widget _buildSynthesisBody() {
    return SourceReaderSynthesisLayout(
      readerBuilder: _buildPdfPane,
      sidecarBuilder: _buildSidecarPane,
      synthesisBuilder: _buildDocumentPane,
      fallbackBuilder: () => _buildTwoPaneBody(notesPaneBuilder: _buildDocumentPane),
      minPaneWidth: _minPaneWidth,
      dividerWidth: _dividerWidth,
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
            IconButton(
              tooltip: 'Dev todos',
              onPressed: _planningLoaded ? _openDevTodos : null,
              icon: const Icon(Icons.bug_report_outlined),
            ),
            StreamBuilder<List<TodoItem>>(
              stream: _noteRepository.watchTodos(includeCompleted: false),
              builder: (context, snapshot) {
                return AnimatedBuilder(
                  animation: _planningRepository,
                  builder: (context, _) {
                    return PdfReaderToolbar(
                      activeTool: _activeTool,
                      activeHighlightColorValue: _activeHighlightColorValue,
                      hasActiveSelection: _hasActiveSelection,
                      activeTodoCount: snapshot.data?.length ?? 0,
                      activeProjectCount: _planningLoaded
                          ? _planningRepository.projects.length
                          : 0,
                      nextSessionCount: _planningLoaded
                          ? _planningRepository.activeHandoffEntries().length
                          : 0,
                      assignedProjectTitle: _planningLoaded
                          ? _planningRepository.projectForPdf(widget.documentId)?.title
                          : null,
                      onToolChanged: _handleReaderToolChanged,
                      onHighlightColorChanged: _handleHighlightColorChanged,
                      onOpenPdfSearch: _openPdfSearch,
                      onOpenNotesOutlineSearch: _openNotesOutlineSearch,
                      onOpenTodos: (buttonContext) =>
                          _openTodosPanel(buttonContext),
                      onOpenProjects: _openProjectsPanel,
                      onOpenCalendar: _openCalendarOverview,
                      onOpenToday: _openTodayBriefing,
                      onEndSession: _endAssignedProjectSession,
                      onOpenSettings: _openSettings,
                    );
                  },
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
            AnimatedBuilder(
              animation: _planningRepository,
              builder: (context, _) => _buildAssignedProjectHeader(),
            ),
            Expanded(child: _buildWorkspaceBody()),
          ],
        ),
      ),
    );
  }
}


class _WorkspaceDocumentPaneHeader extends StatelessWidget {
  final String projectTitle;
  final List<WorkspaceDocument> documents;
  final String selectedDocumentId;
  final ValueChanged<String> onDocumentChanged;
  final VoidCallback onCreateDocument;
  final VoidCallback onOpenWorkspace;

  const _WorkspaceDocumentPaneHeader({
    required this.projectTitle,
    required this.documents,
    required this.selectedDocumentId,
    required this.onDocumentChanged,
    required this.onCreateDocument,
    required this.onOpenWorkspace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(Icons.folder_copy_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    projectTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedDocumentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Open project document',
                      border: OutlineInputBorder(),
                    ),
                    items: documents
                        .map(
                          (document) => DropdownMenuItem(
                            value: document.id,
                            child: Text(document.title, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onDocumentChanged(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onOpenWorkspace,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Workspace'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onCreateDocument,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceDocumentEmptyPane extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _WorkspaceDocumentEmptyPane({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_document, size: 44, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(actionLabel),
                ),
              ],
            ),
          ),
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

class _ReaderProjectContextHeader extends StatelessWidget {
  final String projectTitle;
  final List<StudyPlanRequirement> requirements;
  final int handoffCount;
  final VoidCallback onOpenProject;
  final VoidCallback onOpenCalendar;
  final VoidCallback onEndSession;

  const _ReaderProjectContextHeader({
    required this.projectTitle,
    required this.requirements,
    required this.handoffCount,
    required this.onOpenProject,
    required this.onOpenCalendar,
    required this.onEndSession,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleRequirements = requirements.take(2).toList(growable: false);

    return Material(
      color: colorScheme.primaryContainer.withAlpha(72),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.primary.withAlpha(70)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.dashboard_customize_rounded, color: colorScheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onOpenProject,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                      child: Text(
                        projectTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (visibleRequirements.isEmpty)
                    Text(
                      'No project work scheduled for today',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    for (final requirement in visibleRequirements)
                      _ReaderContextChip(
                        icon: _readerRequirementIcon(requirement),
                        label: '${requirement.plan.title} · ${requirement.rangeLabel}',
                      ),
                  if (requirements.length > visibleRequirements.length)
                    _ReaderContextChip(
                      icon: Icons.more_horiz_rounded,
                      label: '+${requirements.length - visibleRequirements.length} more today',
                    ),
                  if (handoffCount > 0)
                    _ReaderContextChip(
                      icon: Icons.psychology_alt_rounded,
                      label: '$handoffCount next-session ${handoffCount == 1 ? 'note' : 'notes'}',
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: onOpenCalendar,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Calendar'),
            ),
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              onPressed: onEndSession,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('End session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderContextChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReaderContextChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

IconData _readerRequirementIcon(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) return Icons.flag_rounded;
  if (requirement.plan.isSingleTask) return Icons.task_alt_rounded;
  if (requirement.plan.isChecklist) return Icons.fact_check_rounded;
  if (requirement.plan.isRecurring) return Icons.repeat_rounded;
  return Icons.route_rounded;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
