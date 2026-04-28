import 'dart:async';

import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';

class PdfSidecarNotesCanvas extends StatefulWidget {
  final NoteRepository noteRepository;
  final String documentId;
  final int currentPage;
  final int pageCount;
  final String? selectedText;

  /// pdfrx document-layout visible rectangle.
  ///
  /// This is better than only syncing by page number because the sidecar can
  /// follow the viewer's actual visible document position.
  final Rect pdfVisibleRect;

  /// pdfrx document-layout size.
  final Size pdfDocumentSize;

  const PdfSidecarNotesCanvas({
    super.key,
    required this.noteRepository,
    required this.documentId,
    required this.currentPage,
    required this.pageCount,
    required this.pdfVisibleRect,
    required this.pdfDocumentSize,
    this.selectedText,
  });

  @override
  State<PdfSidecarNotesCanvas> createState() => _PdfSidecarNotesCanvasState();
}

class _PdfSidecarNotesCanvasState extends State<PdfSidecarNotesCanvas> {
  final ScrollController _scrollController = ScrollController();

  String? _noteIdToFocus;

  static const double _virtualPageHeight = 1200.0;
  static const double _pageGap = 24.0;
  static const double _defaultNoteWidth = 0.78;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncToPdfPosition();
    });
  }

  @override
  void didUpdateWidget(covariant PdfSidecarNotesCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);

    final pdfStateChanged = oldWidget.pdfVisibleRect != widget.pdfVisibleRect ||
        oldWidget.pdfDocumentSize != widget.pdfDocumentSize ||
        oldWidget.currentPage != widget.currentPage ||
        oldWidget.pageCount != widget.pageCount;

    if (pdfStateChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncToPdfPosition();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int get _safePageCount {
    return widget.pageCount <= 0 ? 1 : widget.pageCount;
  }

  int get _safeCurrentPage {
    return widget.currentPage.clamp(1, _safePageCount);
  }

  double _pageOffset(int pageNumber) {
    return (pageNumber - 1) * (_virtualPageHeight + _pageGap);
  }

  bool get _hasUsablePdfScrollState {
    return widget.pdfDocumentSize.height > 0 &&
        widget.pdfVisibleRect.height > 0 &&
        widget.pdfDocumentSize.height > widget.pdfVisibleRect.height;
  }

  void _syncToPdfPosition() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (!_hasUsablePdfScrollState) {
      _jumpToCurrentPage();
      return;
    }

    final pdfScrollableHeight =
        widget.pdfDocumentSize.height - widget.pdfVisibleRect.height;

    if (pdfScrollableHeight <= 0) {
      _jumpToCurrentPage();
      return;
    }

    final pdfProgress = (widget.pdfVisibleRect.top / pdfScrollableHeight)
        .clamp(0.0, 1.0)
        .toDouble();

    final maxSidecarExtent = _scrollController.position.maxScrollExtent;
    final target = (pdfProgress * maxSidecarExtent)
        .clamp(0.0, maxSidecarExtent)
        .toDouble();

    final current = _scrollController.offset;

    if ((current - target).abs() < 1.0) {
      return;
    }

    _scrollController.jumpTo(target);
  }

  void _jumpToCurrentPage() {
    if (!_scrollController.hasClients) {
      return;
    }

    final target = _pageOffset(_safeCurrentPage);
    final maxExtent = _scrollController.position.maxScrollExtent;
    final safeTarget = target.clamp(0.0, maxExtent).toDouble();

    if ((_scrollController.offset - safeTarget).abs() < 1.0) {
      return;
    }

    _scrollController.jumpTo(safeTarget);
  }

  Future<void> _createNoteAt({
    required int pageNumber,
    required Offset localPosition,
    required Size pageSize,
  }) async {
    final x = (localPosition.dx / pageSize.width).clamp(0.02, 0.92).toDouble();
    final y =
        (localPosition.dy / pageSize.height).clamp(0.02, 0.94).toDouble();

    final note = await widget.noteRepository.createSidecarTextNote(
      documentId: widget.documentId,
      pageNumber: pageNumber,
      x: x,
      y: y,
      width: _defaultNoteWidth,
      selectedText: widget.selectedText,
    );

    if (!mounted) return;

    setState(() {
      _noteIdToFocus = note.note.id;
    });
  }

  Map<int, List<NoteWithAnchor>> _groupNotesByPage(
    List<NoteWithAnchor> notes,
  ) {
    final grouped = <int, List<NoteWithAnchor>>{};

    for (final note in notes) {
      final page = note.sidecarPlacement.pageNumber.clamp(1, _safePageCount);

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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NoteWithAnchor>>(
      stream: widget.noteRepository.watchSidecarNotesForDocument(
        documentId: widget.documentId,
      ),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? [];
        final notesByPage = _groupNotesByPage(notes);

        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              _SidecarHeader(
                currentPage: _safeCurrentPage,
                pageCount: _safePageCount,
                hasSelectedText: widget.selectedText != null &&
                    widget.selectedText!.trim().isNotEmpty,
                syncMode: _hasUsablePdfScrollState
                    ? 'PDFium scroll sync'
                    : 'Page sync',
              ),
              const Divider(height: 1),
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          for (var page = 1; page <= _safePageCount; page++)
                            _NotesPageCanvas(
                              pageNumber: page,
                              isCurrentPage: page == _safeCurrentPage,
                              pageHeight: _virtualPageHeight,
                              notes: notesByPage[page] ?? const [],
                              noteIdToFocus: _noteIdToFocus,
                              onFocusConsumed: () {
                                if (!mounted) return;

                                setState(() {
                                  _noteIdToFocus = null;
                                });
                              },
                              onCreateNote: (localPosition, size) {
                                _createNoteAt(
                                  pageNumber: page,
                                  localPosition: localPosition,
                                  pageSize: size,
                                );
                              },
                              onUpdateNote: ({
                                required noteId,
                                required blockId,
                                required text,
                              }) {
                                widget.noteRepository.updateTextBlock(
                                  noteId: noteId,
                                  blockId: blockId,
                                  body: text,
                                );
                              },
                              onArchiveIfEmpty: ({
                                required noteId,
                                required blockId,
                              }) {
                                widget.noteRepository.archiveNoteIfEmpty(
                                  noteId: noteId,
                                  blockId: blockId,
                                );
                              },
                              onArchive: widget.noteRepository.archiveNote,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SidecarHeader extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final bool hasSelectedText;
  final String syncMode;

  const _SidecarHeader({
    required this.currentPage,
    required this.pageCount,
    required this.hasSelectedText,
    required this.syncMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.edit_note),
          const SizedBox(width: 8),
          Text(
            'Notes canvas',
            style: theme.textTheme.titleMedium,
          ),
          const Spacer(),
          if (hasSelectedText) ...[
            Icon(
              Icons.format_quote,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Selection active',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
          ],
          Text(
            syncMode,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Page $currentPage / $pageCount',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NotesPageCanvas extends StatelessWidget {
  final int pageNumber;
  final bool isCurrentPage;
  final double pageHeight;
  final List<NoteWithAnchor> notes;
  final String? noteIdToFocus;
  final VoidCallback onFocusConsumed;
  final void Function(Offset localPosition, Size size) onCreateNote;
  final void Function({
    required String noteId,
    required String blockId,
    required String text,
  }) onUpdateNote;
  final void Function({
    required String noteId,
    required String blockId,
  }) onArchiveIfEmpty;
  final void Function(String noteId) onArchive;

  const _NotesPageCanvas({
    required this.pageNumber,
    required this.isCurrentPage,
    required this.pageHeight,
    required this.notes,
    required this.noteIdToFocus,
    required this.onFocusConsumed,
    required this.onCreateNote,
    required this.onUpdateNote,
    required this.onArchiveIfEmpty,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: _PdfSidecarDefaults.pageGap),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              onCreateNote(
                details.localPosition,
                Size(width, pageHeight),
              );
            },
            child: Container(
              height: pageHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isCurrentPage
                    ? theme.colorScheme.surfaceContainerHighest
                    : theme.colorScheme.surfaceContainerLow,
                border: Border.all(
                  color: isCurrentPage
                      ? theme.colorScheme.primary.withOpacity(0.50)
                      : theme.colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 16,
                    top: 12,
                    child: _PageLabel(
                      pageNumber: pageNumber,
                      isCurrentPage: isCurrentPage,
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: CustomPaint(
                        painter: _NotebookLinePainter(
                          lineColor: theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  for (final item in notes)
                    _PositionedNote(
                      item: item,
                      canvasWidth: width,
                      pageHeight: pageHeight,
                      autofocus: item.note.id == noteIdToFocus,
                      onFocusConsumed: onFocusConsumed,
                      onUpdateNote: onUpdateNote,
                      onArchiveIfEmpty: onArchiveIfEmpty,
                      onArchive: onArchive,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PositionedNote extends StatelessWidget {
  final NoteWithAnchor item;
  final double canvasWidth;
  final double pageHeight;
  final bool autofocus;
  final VoidCallback onFocusConsumed;
  final void Function({
    required String noteId,
    required String blockId,
    required String text,
  }) onUpdateNote;
  final void Function({
    required String noteId,
    required String blockId,
  }) onArchiveIfEmpty;
  final void Function(String noteId) onArchive;

  const _PositionedNote({
    required this.item,
    required this.canvasWidth,
    required this.pageHeight,
    required this.autofocus,
    required this.onFocusConsumed,
    required this.onUpdateNote,
    required this.onArchiveIfEmpty,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final placement = item.sidecarPlacement;

    final rawLeft = placement.x * canvasWidth;
    final rawTop = placement.y * pageHeight;
    final rawWidth = placement.width * canvasWidth;

    final noteWidth = rawWidth.clamp(180.0, canvasWidth - 24).toDouble();
    final left = rawLeft.clamp(12.0, canvasWidth - noteWidth - 12).toDouble();
    final top = rawTop.clamp(48.0, pageHeight - 120).toDouble();

    final blockId = item.firstBlock?.id;

    if (blockId == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: left,
      top: top,
      width: noteWidth,
      child: InlineSidecarNoteCard(
        key: ValueKey(item.note.id),
        item: item,
        autofocus: autofocus,
        onFocusConsumed: onFocusConsumed,
        onChanged: (text) {
          onUpdateNote(
            noteId: item.note.id,
            blockId: blockId,
            text: text,
          );
        },
        onArchiveIfEmpty: () {
          onArchiveIfEmpty(
            noteId: item.note.id,
            blockId: blockId,
          );
        },
        onArchive: () {
          onArchive(item.note.id);
        },
      ),
    );
  }
}

class InlineSidecarNoteCard extends StatefulWidget {
  final NoteWithAnchor item;
  final bool autofocus;
  final VoidCallback onFocusConsumed;
  final ValueChanged<String> onChanged;
  final VoidCallback onArchiveIfEmpty;
  final VoidCallback onArchive;

  const InlineSidecarNoteCard({
    super.key,
    required this.item,
    required this.autofocus,
    required this.onFocusConsumed,
    required this.onChanged,
    required this.onArchiveIfEmpty,
    required this.onArchive,
  });

  @override
  State<InlineSidecarNoteCard> createState() => _InlineSidecarNoteCardState();
}

class _InlineSidecarNoteCardState extends State<InlineSidecarNoteCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  Timer? _debounce;

  static const Duration _autosaveDelay = Duration(milliseconds: 650);

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.item.body);
    _focusNode = FocusNode();

    _focusNode.addListener(_handleFocusChange);

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _focusNode.requestFocus();
        widget.onFocusConsumed();
      });
    }
  }

  @override
  void didUpdateWidget(covariant InlineSidecarNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.item.note.id != widget.item.note.id) {
      _controller.text = widget.item.body;
    }

    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _focusNode.requestFocus();
        widget.onFocusConsumed();
      });
    }
  }

  @override
  void dispose() {
    _flushPendingSave();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _flushPendingSave();

      if (_controller.text.trim().isEmpty) {
        widget.onArchiveIfEmpty();
      }
    }
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(_autosaveDelay, () {
      widget.onChanged(value);
    });
  }

  void _flushPendingSave() {
    _debounce?.cancel();
    _debounce = null;

    widget.onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedText = widget.item.anchor.selectedText?.trim();
    final hasSelectedText = selectedText != null && selectedText.isNotEmpty;

    return Material(
      elevation: _focusNode.hasFocus ? 5 : 2,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _focusNode.hasFocus
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 72,
            maxHeight: 420,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasSelectedText)
                  _LinkedSelectionPreview(selectedText: selectedText),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: null,
                        onChanged: _onTextChanged,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Type here...',
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Note options',
                      onSelected: (value) {
                        if (value == 'archive') {
                          widget.onArchive();
                        }
                      },
                      itemBuilder: (context) {
                        return const [
                          PopupMenuItem(
                            value: 'archive',
                            child: Text('Archive note'),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkedSelectionPreview extends StatelessWidget {
  final String selectedText;

  const _LinkedSelectionPreview({
    required this.selectedText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '“$selectedText”',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _PageLabel extends StatelessWidget {
  final int pageNumber;
  final bool isCurrentPage;

  const _PageLabel({
    required this.pageNumber,
    required this.isCurrentPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentPage
            ? theme.colorScheme.primary
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        'Page $pageNumber',
        style: theme.textTheme.labelSmall?.copyWith(
          color: isCurrentPage
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _NotebookLinePainter extends CustomPainter {
  final Color lineColor;

  const _NotebookLinePainter({
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor.withOpacity(0.35)
      ..strokeWidth = 1;

    const spacing = 40.0;

    for (double y = 80; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookLinePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}

class _PdfSidecarDefaults {
  static const double pageGap = 24.0;
}