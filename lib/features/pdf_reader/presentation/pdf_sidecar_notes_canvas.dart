import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';
import '../domain/pdf_viewport_state.dart';
import '../../settings/data/app_settings_controller.dart';
import 'sidecar/note_creation_type.dart';
import 'sidecar/sidecar_external_create_request.dart';
import 'sidecar/sidecar_page_metrics.dart';
import 'sidecar/sidecar_reveal_note_request.dart';
import 'sidecar/sidecar_sync_models.dart';
import 'sidecar/widgets/floating_sidecar_header.dart';
import 'sidecar/widgets/notes_outline_panel.dart';
import 'sidecar/widgets/notes_page_canvas.dart';
import 'sidecar/widgets/sync_debug_overlay.dart';

class PdfSidecarNotesCanvas extends StatefulWidget {
  final NoteRepository noteRepository;
  final String documentId;
  final ValueListenable<PdfViewportState> viewportListenable;
  final String? selectedText;
  final List<PdfSourceRect> selectedSourceRects;
  final ValueListenable<SidecarExternalCreateRequest?>?
  externalCreateRequestListenable;
  final ValueListenable<SidecarRevealNoteRequest?>? revealNoteRequestListenable;
  final ValueListenable<int>? outlineSearchFocusRequestListenable;
  final bool initialOutlineOpen;
  final bool initialDebugEnabled;
  final ValueChanged<List<PdfSourceRect>>? onHoveredSourceRectsChanged;
  final ValueChanged<Offset>? onSidecarScrollDelta;
  final ValueChanged<double>? onRequestPdfJumpToDocumentY;
  final void Function({required bool outlineOpen, required bool debugEnabled})?
  onSidecarPreferencesChanged;
  final AppSettings appSettings;

  const PdfSidecarNotesCanvas({
    super.key,
    required this.noteRepository,
    required this.documentId,
    required this.viewportListenable,
    this.selectedText,
    this.selectedSourceRects = const [],
    this.externalCreateRequestListenable,
    this.revealNoteRequestListenable,
    this.outlineSearchFocusRequestListenable,
    this.initialOutlineOpen = false,
    this.initialDebugEnabled = false,
    this.onHoveredSourceRectsChanged,
    this.onSidecarScrollDelta,
    this.onRequestPdfJumpToDocumentY,
    this.onSidecarPreferencesChanged,
    required this.appSettings,
  });

  @override
  State<PdfSidecarNotesCanvas> createState() => _PdfSidecarNotesCanvasState();
}

class _PdfSidecarNotesCanvasState extends State<PdfSidecarNotesCanvas> {
  final ScrollController _scrollController = ScrollController();

  String? _noteIdToFocus;
  String? _activeEditingNoteId;
  String? _revealedNoteId;
  String? _pendingRevealScrollNoteId;
  DateTime? _manualRevealScrollUntil;

  bool _syncScheduled = false;
  late bool _debugEnabled;
  late bool _outlineOpen;
  bool _pointerInsideOutline = false;

  int? _lastHandledExternalCreateRequestId;
  int? _lastHandledRevealNoteRequestId;
  int? _lastHandledOutlineFocusRequest;

  Timer? _revealTimer;

  PdfViewportState _latestViewport = PdfViewportState.initial();
  List<SidecarPageMetrics> _latestPageMetrics = const [];
  SyncDebugState? _debugState;

  double _latestSidecarViewportHeight = 0;

  static const double _defaultNoteWidth = 0.28;
  static const double _fallbackPageHeight = 1200.0;
  static const double _syncAnchorViewportFraction = 0.5;

  @override
  void initState() {
    super.initState();

    _debugEnabled = widget.initialDebugEnabled;
    _outlineOpen = false;
    _lastHandledOutlineFocusRequest =
        widget.outlineSearchFocusRequestListenable?.value;
    _latestViewport = widget.viewportListenable.value;

    widget.viewportListenable.addListener(_handleViewportChanged);

    widget.externalCreateRequestListenable?.addListener(
      _handleExternalCreateRequest,
    );
    widget.revealNoteRequestListenable?.addListener(_handleRevealNoteRequest);
    widget.outlineSearchFocusRequestListenable?.addListener(
      _handleOutlineSearchFocusRequest,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleSyncToPdf();
      _handleExternalCreateRequest();
      _handleRevealNoteRequest();
      _handleOutlineSearchFocusRequest();
    });
  }

  @override
  void didUpdateWidget(covariant PdfSidecarNotesCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.viewportListenable != widget.viewportListenable) {
      oldWidget.viewportListenable.removeListener(_handleViewportChanged);
      widget.viewportListenable.addListener(_handleViewportChanged);
      _latestViewport = widget.viewportListenable.value;
      _scheduleSyncToPdf();
    }

    if (oldWidget.externalCreateRequestListenable !=
        widget.externalCreateRequestListenable) {
      oldWidget.externalCreateRequestListenable?.removeListener(
        _handleExternalCreateRequest,
      );
      widget.externalCreateRequestListenable?.addListener(
        _handleExternalCreateRequest,
      );
    }

    if (oldWidget.revealNoteRequestListenable !=
        widget.revealNoteRequestListenable) {
      oldWidget.revealNoteRequestListenable?.removeListener(
        _handleRevealNoteRequest,
      );
      widget.revealNoteRequestListenable?.addListener(_handleRevealNoteRequest);
    }

    if (oldWidget.outlineSearchFocusRequestListenable !=
        widget.outlineSearchFocusRequestListenable) {
      oldWidget.outlineSearchFocusRequestListenable?.removeListener(
        _handleOutlineSearchFocusRequest,
      );
      widget.outlineSearchFocusRequestListenable?.addListener(
        _handleOutlineSearchFocusRequest,
      );
      _lastHandledOutlineFocusRequest =
          widget.outlineSearchFocusRequestListenable?.value;
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    widget.viewportListenable.removeListener(_handleViewportChanged);
    widget.externalCreateRequestListenable?.removeListener(
      _handleExternalCreateRequest,
    );
    widget.revealNoteRequestListenable?.removeListener(
      _handleRevealNoteRequest,
    );
    widget.outlineSearchFocusRequestListenable?.removeListener(
      _handleOutlineSearchFocusRequest,
    );
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasSelectedText {
    return widget.selectedText != null &&
        widget.selectedText!.trim().isNotEmpty;
  }

  void _handleViewportChanged() {
    final next = widget.viewportListenable.value;

    if (_latestViewport.isEquivalentTo(next)) {
      return;
    }

    _latestViewport = next;
    _scheduleSyncToPdf();
  }

  void _notifyPreferencesChanged() {
    widget.onSidecarPreferencesChanged?.call(
      outlineOpen: _outlineOpen,
      debugEnabled: _debugEnabled,
    );
  }

  void _handleOutlineSearchFocusRequest() {
    final value = widget.outlineSearchFocusRequestListenable?.value;

    if (value == null || value == _lastHandledOutlineFocusRequest) {
      return;
    }

    _lastHandledOutlineFocusRequest = value;

    if (!mounted) return;

    setState(() {
      _outlineOpen = true;
    });

    _notifyPreferencesChanged();
  }

  Future<void> _handleExternalCreateRequest() async {
    final request = widget.externalCreateRequestListenable?.value;

    if (request == null ||
        request.requestId == _lastHandledExternalCreateRequestId) {
      return;
    }

    _lastHandledExternalCreateRequestId = request.requestId;

    if (request.creationType == NoteCreationType.highlight) {
      return;
    }

    final note = await widget.noteRepository.createSidecarTextNote(
      documentId: widget.documentId,
      pageNumber: request.pageNumber,
      x: 0.08,
      y: request.normalizedY.clamp(0.02, 0.94).toDouble(),
      width: _defaultNoteWidth,
      noteType: request.creationType.id,
      selectedText: request.selectedText,
      sourceRects: request.sourceRects,
    );

    if (!mounted) return;

    setState(() {
      _noteIdToFocus = note.note.id;
      _activeEditingNoteId = note.note.id;
      _revealedNoteId = note.note.id;
    });

    _scheduleRevealClear();
  }

  void _handleRevealNoteRequest() {
    final request = widget.revealNoteRequestListenable?.value;

    if (request == null ||
        request.requestId == _lastHandledRevealNoteRequestId) {
      return;
    }

    _lastHandledRevealNoteRequestId = request.requestId;

    if (!mounted) return;

    setState(() {
      _noteIdToFocus = request.noteId;
      _revealedNoteId = request.noteId;
      _pendingRevealScrollNoteId = request.noteId;
      _outlineOpen = false;
    });

    _notifyPreferencesChanged();
    _scheduleRevealClear();
  }

  void _scheduleRevealClear() {
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;

      setState(() {
        _revealedNoteId = null;
      });
    });
  }

  Future<void> _createNoteAt({
    required int pageNumber,
    required Offset localPosition,
    required Size pageSize,
    required NoteCreationType creationType,
  }) async {
    if (pageSize.width <= 0 || pageSize.height <= 0) {
      return;
    }

    if (creationType == NoteCreationType.highlight) {
      await widget.noteRepository.createPersistentHighlight(
        documentId: widget.documentId,
        pageNumber: pageNumber,
        selectedText: widget.selectedText,
        sourceRects: widget.selectedSourceRects,
      );
      return;
    }

    final x = (localPosition.dx / pageSize.width).clamp(0.02, 0.92).toDouble();
    final y = (localPosition.dy / pageSize.height).clamp(0.02, 0.94).toDouble();

    final note = await widget.noteRepository.createSidecarTextNote(
      documentId: widget.documentId,
      pageNumber: pageNumber,
      x: x,
      y: y,
      width: _defaultNoteWidth,
      noteType: creationType.id,
      selectedText: widget.selectedText,
      sourceRects: widget.selectedSourceRects,
    );

    if (!mounted) return;

    setState(() {
      _noteIdToFocus = note.note.id;
      _activeEditingNoteId = note.note.id;
      _revealedNoteId = note.note.id;
    });

    _scheduleRevealClear();
  }

  void _handleEditingNoteChanged(String? noteId) {
    if (_activeEditingNoteId == noteId) {
      return;
    }

    setState(() {
      _activeEditingNoteId = noteId;
    });
  }

  void _selectOutlineNote(NoteWithAnchor note) {
    final placement = note.sidecarPlacement;

    SidecarPageMetrics? metric;
    for (final item in _latestPageMetrics) {
      if (item.pageNumber == placement.pageNumber) {
        metric = item;
        break;
      }
    }

    if (metric != null) {
      final documentY =
          metric.pdfPageRect.top +
          placement.y.clamp(0.0, 1.0).toDouble() * metric.pdfPageRect.height;

      widget.onRequestPdfJumpToDocumentY?.call(documentY);
    }

    setState(() {
      _revealedNoteId = note.note.id;
      _outlineOpen = false;
    });

    _notifyPreferencesChanged();
    _scheduleRevealClear();
  }

  Map<int, List<NoteWithAnchor>> _groupNotesByPage(
    List<NoteWithAnchor> notes,
    int pageCount,
  ) {
    final grouped = <int, List<NoteWithAnchor>>{};

    for (final note in notes) {
      final page = note.sidecarPlacement.pageNumber.clamp(1, pageCount).toInt();

      grouped.putIfAbsent(page, () => []);
      grouped[page]!.add(note);
    }

    for (final pageNotes in grouped.values) {
      pageNotes.sort((a, b) {
        final ay = a.sidecarPlacement.y;
        final by = b.sidecarPlacement.y;
        return ay.compareTo(by);
      });
    }

    return grouped;
  }

  List<SidecarPageMetrics> _buildSidecarPageMetrics({
    required PdfViewportState viewport,
    required double canvasWidth,
    required double viewportHeight,
  }) {
    final pageCount = viewport.safePageCount;
    final safeCanvasWidth = math.max(1.0, canvasWidth);

    if (!viewport.hasUsablePageLayout || viewport.pageRects.isEmpty) {
      return _buildFallbackPageMetrics(
        pageCount: pageCount,
        canvasWidth: safeCanvasWidth,
      );
    }

    final usableRects = viewport.pageRects.take(pageCount).toList();

    if (usableRects.isEmpty) {
      return _buildFallbackPageMetrics(
        pageCount: pageCount,
        canvasWidth: safeCanvasWidth,
      );
    }

    final visibleHeight = viewport.visibleRect.height;
    final viewportScale = visibleHeight <= 0 || viewportHeight <= 0
        ? 1.0
        : (viewportHeight / visibleHeight);
    final scale = viewportScale.isFinite && viewportScale > 0
        ? viewportScale
        : 1.0;

    // pdfrx exposes page layouts and the visible rect in document coordinates.
    // Those coordinates are intentionally stable, so using `pdfRect.height`
    // directly makes the sidecar ignore zoom. Convert document coordinates to
    // the current screen rhythm by scaling with viewportHeight / visibleHeight.
    // Also preserve the real inter-page gaps from the PDF layout. Without those
    // gaps, page labels drift from the PDF after a few pages and the debug view
    // no longer lines up with the rendered document.
    final documentOriginTop = usableRects.first.top;

    final metrics = <SidecarPageMetrics>[];

    for (var index = 0; index < usableRects.length; index++) {
      final pdfRect = usableRects[index];
      final sidecarTop = math.max(
        0.0,
        (pdfRect.top - documentOriginTop) * scale,
      );
      final sidecarHeight = math.max(1.0, pdfRect.height * scale);

      metrics.add(
        SidecarPageMetrics(
          pageNumber: index + 1,
          left: 0,
          top: sidecarTop,
          width: safeCanvasWidth,
          height: sidecarHeight,
          pdfPageRect: pdfRect,
        ),
      );
    }

    return metrics;
  }

  List<SidecarPageMetrics> _buildFallbackPageMetrics({
    required int pageCount,
    required double canvasWidth,
  }) {
    final metrics = <SidecarPageMetrics>[];
    final pageWidth = math.max(1.0, canvasWidth);

    var top = 0.0;

    for (var page = 1; page <= pageCount; page++) {
      metrics.add(
        SidecarPageMetrics(
          pageNumber: page,
          left: 0,
          top: top,
          width: pageWidth,
          height: _fallbackPageHeight,
          pdfPageRect: Rect.fromLTWH(0, top, pageWidth, _fallbackPageHeight),
        ),
      );

      top += _fallbackPageHeight;
    }

    return metrics;
  }

  void _schedulePendingRevealScroll(
    List<NoteWithAnchor> notes,
    List<SidecarPageMetrics> metrics,
  ) {
    final noteId = _pendingRevealScrollNoteId;
    if (noteId == null || notes.isEmpty || metrics.isEmpty) {
      return;
    }

    NoteWithAnchor? note;
    for (final candidate in notes) {
      if (candidate.note.id == noteId) {
        note = candidate;
        break;
      }
    }
    if (note == null) {
      return;
    }

    SidecarPageMetrics? metric;
    for (final candidate in metrics) {
      if (candidate.pageNumber == note.sidecarPlacement.pageNumber) {
        metric = candidate;
        break;
      }
    }
    if (metric == null) {
      return;
    }

    _pendingRevealScrollNoteId = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToSidecarNote(note!, metric!);
    });
  }

  void _scrollToSidecarNote(NoteWithAnchor note, SidecarPageMetrics metric) {
    if (!_scrollController.hasClients) {
      _pendingRevealScrollNoteId = note.note.id;
      return;
    }

    final placement = note.sidecarPlacement;
    final y = metric.top + placement.y.clamp(0.0, 1.0).toDouble() * metric.height;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final viewportHeight = math.max(1.0, _latestSidecarViewportHeight);
    final targetOffset = (y - viewportHeight * 0.28).clamp(0.0, maxExtent).toDouble();

    _manualRevealScrollUntil = DateTime.now().add(const Duration(milliseconds: 1200));
    unawaited(
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );

    final sourceRects = note.sourceRects;
    if (sourceRects.isNotEmpty) {
      final rect = sourceRects.firstWhere(
        (candidate) => candidate.pageNumber == metric.pageNumber,
        orElse: () => sourceRects.first,
      );
      final sourceY = math.min(rect.top, rect.bottom)
          .clamp(0.0, math.max(1.0, metric.pdfPageRect.height))
          .toDouble();
      widget.onRequestPdfJumpToDocumentY?.call(metric.pdfPageRect.top + sourceY);
      return;
    }

    widget.onRequestPdfJumpToDocumentY?.call(
      metric.pdfPageRect.top + placement.y.clamp(0.0, 1.0).toDouble() * metric.pdfPageRect.height,
    );
  }

  void _scheduleSyncToPdf() {
    if (_syncScheduled) {
      return;
    }

    _syncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;

      if (!mounted) return;

      _syncToPdfPosition();
    });
  }

  void _syncToPdfPosition() {
    final manualRevealScrollUntil = _manualRevealScrollUntil;
    if (manualRevealScrollUntil != null &&
        DateTime.now().isBefore(manualRevealScrollUntil)) {
      return;
    }

    if (!_scrollController.hasClients || _latestPageMetrics.isEmpty) {
      return;
    }

    final viewport = _latestViewport;

    if (!viewport.hasUsablePageLayout || _latestSidecarViewportHeight <= 0) {
      _syncToCurrentPageFallback(viewport);
      return;
    }

    final syncTarget = _calculateContinuousSyncTarget(
      viewport: viewport,
      metrics: _latestPageMetrics,
      sidecarViewportHeight: _latestSidecarViewportHeight,
    );

    if (syncTarget == null) {
      _syncToCurrentPageFallback(viewport);
      return;
    }

    final maxExtent = _scrollController.position.maxScrollExtent;

    final targetOffset = syncTarget.targetOffset
        .clamp(0.0, maxExtent)
        .toDouble();

    final actualBefore = _scrollController.offset;
    final correctionBeforeJump = targetOffset - actualBefore;

    if (correctionBeforeJump.abs() >= 0.25) {
      _scrollController.jumpTo(targetOffset);
    }

    final actualAfter = _scrollController.offset;

    _updateDebugState(
      SyncDebugState(
        mode: syncTarget.mode,
        pageNumber: syncTarget.pageNumber,
        pdfAnchorY: syncTarget.pdfAnchorY,
        pdfSegmentTop: syncTarget.pdfSegmentTop,
        pdfSegmentHeight: syncTarget.pdfSegmentHeight,
        segmentProgress: syncTarget.segmentProgress,
        sidecarAnchorY: syncTarget.sidecarAnchorY,
        targetOffset: targetOffset,
        actualBefore: actualBefore,
        actualAfter: actualAfter,
        correctionBeforeJump: correctionBeforeJump,
      ),
    );
  }

  ContinuousSyncTarget? _calculateContinuousSyncTarget({
    required PdfViewportState viewport,
    required List<SidecarPageMetrics> metrics,
    required double sidecarViewportHeight,
  }) {
    if (viewport.pageRects.isEmpty || metrics.isEmpty) {
      return null;
    }

    final visibleRect = viewport.visibleRect;

    if (visibleRect == Rect.zero || visibleRect.height <= 0) {
      return null;
    }

    final pdfAnchorY =
        visibleRect.top + visibleRect.height * _syncAnchorViewportFraction;

    final mapped = _mapPdfDocumentYToSidecarY(
      pdfY: pdfAnchorY,
      viewport: viewport,
      metrics: metrics,
    );

    if (mapped == null) {
      return null;
    }

    final targetOffset =
        mapped.sidecarY - sidecarViewportHeight * _syncAnchorViewportFraction;

    return ContinuousSyncTarget(
      mode: mapped.mode,
      pageNumber: mapped.pageNumber,
      pdfAnchorY: pdfAnchorY,
      pdfSegmentTop: mapped.pdfSegmentTop,
      pdfSegmentHeight: mapped.pdfSegmentHeight,
      segmentProgress: mapped.segmentProgress,
      sidecarAnchorY: mapped.sidecarY,
      targetOffset: targetOffset,
    );
  }

  MappedSidecarY? _mapPdfDocumentYToSidecarY({
    required double pdfY,
    required PdfViewportState viewport,
    required List<SidecarPageMetrics> metrics,
  }) {
    final count = math.min(viewport.pageRects.length, metrics.length);

    if (count <= 0) {
      return null;
    }

    final pageRects = viewport.pageRects.take(count).toList();
    final sidecarMetrics = metrics.take(count).toList();
    final firstPdfPage = pageRects.first;
    final firstSidecarPage = sidecarMetrics.first;

    if (pdfY <= firstPdfPage.top) {
      return MappedSidecarY(
        mode: 'continuous-before-first',
        pageNumber: firstSidecarPage.pageNumber,
        pdfSegmentTop: firstPdfPage.top,
        pdfSegmentHeight: firstPdfPage.height,
        segmentProgress: 0,
        sidecarY: firstSidecarPage.top,
      );
    }

    for (var index = 0; index < count; index++) {
      final pdfPage = pageRects[index];
      final sidecarPage = sidecarMetrics[index];

      if (pdfY >= pdfPage.top && pdfY <= pdfPage.bottom) {
        final progress = pdfPage.height <= 0
            ? 0.0
            : ((pdfY - pdfPage.top) / pdfPage.height)
                  .clamp(0.0, 1.0)
                  .toDouble();

        return MappedSidecarY(
          mode: 'continuous-page',
          pageNumber: sidecarPage.pageNumber,
          pdfSegmentTop: pdfPage.top,
          pdfSegmentHeight: pdfPage.height,
          segmentProgress: progress,
          sidecarY: sidecarPage.top + progress * sidecarPage.height,
        );
      }

      final hasNext = index + 1 < count;

      if (hasNext) {
        final nextPdfPage = pageRects[index + 1];
        final nextSidecarPage = sidecarMetrics[index + 1];

        final pdfGapTop = pdfPage.bottom;
        final pdfGapBottom = nextPdfPage.top;

        if (pdfY > pdfGapTop && pdfY < pdfGapBottom) {
          final pdfGapHeight = pdfGapBottom - pdfGapTop;

          final progress = pdfGapHeight <= 0
              ? 1.0
              : ((pdfY - pdfGapTop) / pdfGapHeight).clamp(0.0, 1.0).toDouble();

          return MappedSidecarY(
            mode: 'continuous-gap',
            pageNumber: nextSidecarPage.pageNumber,
            pdfSegmentTop: pdfGapTop,
            pdfSegmentHeight: pdfGapHeight,
            segmentProgress: progress,
            sidecarY: _lerpDouble(
              sidecarPage.bottom,
              nextSidecarPage.top,
              progress,
            ),
          );
        }
      }
    }

    final lastPdfPage = pageRects.last;
    final lastSidecarPage = sidecarMetrics.last;

    if (pdfY >= lastPdfPage.bottom) {
      return MappedSidecarY(
        mode: 'continuous-after-last',
        pageNumber: lastSidecarPage.pageNumber,
        pdfSegmentTop: lastPdfPage.top,
        pdfSegmentHeight: lastPdfPage.height,
        segmentProgress: 1,
        sidecarY: lastSidecarPage.bottom,
      );
    }

    return null;
  }

  double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }

  void _syncToCurrentPageFallback(PdfViewportState viewport) {
    if (!_scrollController.hasClients || _latestPageMetrics.isEmpty) {
      return;
    }

    final currentPage = viewport.safeCurrentPage;

    final metric = _latestPageMetrics.firstWhere(
      (metric) => metric.pageNumber == currentPage,
      orElse: () => _latestPageMetrics.first,
    );

    final maxExtent = _scrollController.position.maxScrollExtent;

    final targetOffset = metric.top.clamp(0.0, maxExtent).toDouble();
    final actualBefore = _scrollController.offset;
    final correctionBeforeJump = targetOffset - actualBefore;

    if (correctionBeforeJump.abs() >= 0.25) {
      _scrollController.jumpTo(targetOffset);
    }

    _updateDebugState(
      SyncDebugState(
        mode: 'page-fallback',
        pageNumber: currentPage,
        pdfAnchorY: viewport.visibleTop,
        pdfSegmentTop: metric.pdfPageRect.top,
        pdfSegmentHeight: metric.pdfPageRect.height,
        segmentProgress: 0.0,
        sidecarAnchorY: metric.top,
        targetOffset: targetOffset,
        actualBefore: actualBefore,
        actualAfter: _scrollController.offset,
        correctionBeforeJump: correctionBeforeJump,
      ),
    );
  }

  void _updateDebugState(SyncDebugState next) {
    if (!_debugEnabled) {
      _debugState = next;
      return;
    }

    if (_debugState == next) {
      return;
    }

    setState(() {
      _debugState = next;
    });
  }

  double _totalSidecarHeight(List<SidecarPageMetrics> metrics) {
    if (metrics.isEmpty) {
      return 0;
    }

    final last = metrics.last;
    return last.bottom;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            (!_outlineOpen || !_pointerInsideOutline)) {
          widget.onSidecarScrollDelta?.call(event.scrollDelta);
        }
      },
      child: ValueListenableBuilder<PdfViewportState>(
        valueListenable: widget.viewportListenable,
        builder: (context, viewport, _) {
          _latestViewport = viewport;

          return StreamBuilder<List<NoteWithAnchor>>(
            stream: widget.noteRepository.watchSidecarNotesForDocument(
              documentId: widget.documentId,
            ),
            builder: (context, snapshot) {
              final notes = snapshot.data ?? [];
              final notesByPage = _groupNotesByPage(
                notes,
                viewport.safePageCount,
              );

              return Container(
                color: Theme.of(context).colorScheme.surface,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _latestSidecarViewportHeight = constraints.maxHeight;

                          final metrics = _buildSidecarPageMetrics(
                            viewport: viewport,
                            canvasWidth: constraints.maxWidth,
                            viewportHeight: constraints.maxHeight,
                          );

                          _latestPageMetrics = metrics;
                          _scheduleSyncToPdf();
                          _schedulePendingRevealScroll(notes, metrics);

                          final totalHeight = _totalSidecarHeight(metrics);

                          return Stack(
                            children: [
                              Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: SizedBox(
                                    height: totalHeight,
                                    width: constraints.maxWidth,
                                    child: Stack(
                                      children: [
                                        for (final metric in metrics)
                                          Positioned(
                                            left: metric.left,
                                            top: metric.top,
                                            width: metric.width,
                                            height: metric.height,
                                            child: NotesPageCanvas(
                                              pageNumber: metric.pageNumber,
                                              isCurrentPage:
                                                  metric.pageNumber ==
                                                  viewport.safeCurrentPage,
                                              debugEnabled: _debugEnabled,
                                              pageHeight: metric.height,
                                              pdfPageRect: metric.pdfPageRect,
                                              hasSelectedText: _hasSelectedText,
                                              activeEditingNoteId:
                                                  _activeEditingNoteId,
                                              revealedNoteId: _revealedNoteId,
                                              notes:
                                                  notesByPage[metric
                                                      .pageNumber] ??
                                                  const [],
                                              showOnboardingTip:
                                                  notes.isEmpty &&
                                                  metric.pageNumber ==
                                                      viewport.safeCurrentPage,
                                              appSettings: widget.appSettings,
                                              noteIdToFocus: _noteIdToFocus,
                                              onFocusConsumed: () {
                                                if (!mounted) return;

                                                setState(() {
                                                  _noteIdToFocus = null;
                                                });
                                              },
                                              onEditingNoteChanged:
                                                  _handleEditingNoteChanged,
                                              onRequestPdfJumpToDocumentY: widget
                                                  .onRequestPdfJumpToDocumentY,
                                              onCreateNote:
                                                  ({
                                                    required creationType,
                                                    required localPosition,
                                                    required size,
                                                  }) {
                                                    _createNoteAt(
                                                      pageNumber:
                                                          metric.pageNumber,
                                                      localPosition:
                                                          localPosition,
                                                      pageSize: size,
                                                      creationType:
                                                          creationType,
                                                    );
                                                  },
                                              onUpdateNote:
                                                  ({
                                                    required noteId,
                                                    required blockId,
                                                    required text,
                                                  }) {
                                                    widget.noteRepository
                                                        .updateTextBlock(
                                                          noteId: noteId,
                                                          blockId: blockId,
                                                          body: text,
                                                        );
                                                  },
                                              onUpdateNoteType:
                                                  ({
                                                    required noteId,
                                                    required noteType,
                                                  }) {
                                                    widget.noteRepository
                                                        .updateNoteType(
                                                          noteId: noteId,
                                                          noteType: noteType,
                                                        );
                                                  },
                                              onUpdateTodoCompleted:
                                                  ({
                                                    required todoId,
                                                    required isCompleted,
                                                  }) {
                                                    widget.noteRepository
                                                        .updateTodoCompleted(
                                                          todoId: todoId,
                                                          isCompleted:
                                                              isCompleted,
                                                        );
                                                  },
                                              onUpdateMetadata:
                                                  ({
                                                    required anchorId,
                                                    required metadata,
                                                  }) {
                                                    widget.noteRepository
                                                        .updateNoteMetadata(
                                                          anchorId: anchorId,
                                                          metadata: metadata,
                                                        );
                                                  },
                                              onMoveNote:
                                                  ({
                                                    required anchorId,
                                                    required pageNumber,
                                                    required x,
                                                    required y,
                                                    required width,
                                                  }) {
                                                    widget.noteRepository
                                                        .moveSidecarNote(
                                                          anchorId: anchorId,
                                                          pageNumber:
                                                              pageNumber,
                                                          x: x,
                                                          y: y,
                                                          width: width,
                                                        );
                                                  },
                                              onHoverSourceRectsChanged: widget
                                                  .onHoveredSourceRectsChanged,
                                              onArchiveIfEmpty:
                                                  ({
                                                    required noteId,
                                                    required blockId,
                                                  }) {
                                                    widget.noteRepository
                                                        .archiveNoteIfEmpty(
                                                          noteId: noteId,
                                                          blockId: blockId,
                                                        );
                                                  },
                                              onArchive: widget
                                                  .noteRepository
                                                  .archiveNote,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (_debugEnabled && _debugState != null)
                                Positioned(
                                  right: 16,
                                  bottom: 16,
                                  child: SyncDebugOverlay(state: _debugState!),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 8,
                      child: FloatingSidecarHeader(
                        currentPage: viewport.safeCurrentPage,
                        pageCount: viewport.safePageCount,
                        hasSelectedText: _hasSelectedText,
                        syncMode: viewport.hasUsablePageLayout
                            ? 'Continuous sync'
                            : 'Page fallback',
                        debugEnabled: _debugEnabled,
                        outlineOpen: _outlineOpen,
                        onToggleDebug: () {
                          setState(() {
                            _debugEnabled = !_debugEnabled;
                          });
                          _notifyPreferencesChanged();
                        },
                        onToggleOutline: () {
                          setState(() {
                            _outlineOpen = !_outlineOpen;
                          });
                          _notifyPreferencesChanged();
                        },
                      ),
                    ),
                    if (_outlineOpen)
                      Positioned(
                        top: 58,
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: NotesOutlinePanel(
                          notes: notes,
                          searchFocusRequestListenable:
                              widget.outlineSearchFocusRequestListenable,
                          onPointerEnterPanel: () {
                            if (_pointerInsideOutline) return;
                            setState(() {
                              _pointerInsideOutline = true;
                            });
                          },
                          onPointerExitPanel: () {
                            if (!_pointerInsideOutline) return;
                            setState(() {
                              _pointerInsideOutline = false;
                            });
                          },
                          onClose: () {
                            setState(() {
                              _outlineOpen = false;
                              _pointerInsideOutline = false;
                            });
                            _notifyPreferencesChanged();
                          },
                          onSelectNote: _selectOutlineNote,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
