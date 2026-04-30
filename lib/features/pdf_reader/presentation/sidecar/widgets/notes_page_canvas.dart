import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../notes/data/note_repository.dart';
import '../note_creation_type.dart';
import '../painters/notebook_line_painter.dart';
import 'create_note_menu_item.dart';
import 'margin_note_card.dart';
import 'page_label.dart';

class NotesPageCanvas extends StatelessWidget {
  final int pageNumber;
  final bool isCurrentPage;
  final bool debugEnabled;
  final double pageHeight;
  final Rect pdfPageRect;
  final bool hasSelectedText;
  final String? activeEditingNoteId;
  final String? revealedNoteId;
  final List<NoteWithAnchor> notes;
  final String? noteIdToFocus;
  final VoidCallback onFocusConsumed;
  final ValueChanged<String?> onEditingNoteChanged;
  final ValueChanged<double>? onRequestPdfJumpToDocumentY;
  final void Function({
    required NoteCreationType creationType,
    required Offset localPosition,
    required Size size,
  })
  onCreateNote;
  final void Function({
    required String noteId,
    required String blockId,
    required String text,
  })
  onUpdateNote;
  final void Function({required String noteId, required String noteType})
  onUpdateNoteType;
  final void Function({required String todoId, required bool isCompleted})
  onUpdateTodoCompleted;
  final void Function({
    required String anchorId,
    required NoteMetadata metadata,
  })
  onUpdateMetadata;
  final void Function({
    required String anchorId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
  })
  onMoveNote;
  final ValueChanged<List<PdfSourceRect>>? onHoverSourceRectsChanged;
  final void Function({required String noteId, required String blockId})
  onArchiveIfEmpty;
  final void Function(String noteId) onArchive;

  const NotesPageCanvas({
    super.key,
    required this.pageNumber,
    required this.isCurrentPage,
    required this.debugEnabled,
    required this.pageHeight,
    required this.pdfPageRect,
    required this.hasSelectedText,
    required this.activeEditingNoteId,
    required this.revealedNoteId,
    required this.notes,
    required this.noteIdToFocus,
    required this.onFocusConsumed,
    required this.onEditingNoteChanged,
    required this.onCreateNote,
    required this.onUpdateNote,
    required this.onUpdateNoteType,
    required this.onUpdateTodoCompleted,
    required this.onUpdateMetadata,
    required this.onMoveNote,
    required this.onArchiveIfEmpty,
    required this.onArchive,
    this.onRequestPdfJumpToDocumentY,
    this.onHoverSourceRectsChanged,
  });

  Future<void> _showCreateMenu({
    required BuildContext context,
    required Offset globalPosition,
    required Offset localPosition,
    required Size size,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    const menuWidth = 300.0;
    const menuHeight = 500.0;

    final maxLeft = math.max(8.0, overlay.size.width - menuWidth - 8.0);
    final left = (globalPosition.dx - menuWidth).clamp(8.0, maxLeft).toDouble();

    final maxTop = math.max(8.0, overlay.size.height - menuHeight);
    final top = globalPosition.dy.clamp(8.0, maxTop).toDouble();

    final selected = await showMenu<NoteCreationType>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlay.size.width - left - menuWidth,
        overlay.size.height - top,
      ),
      items: [
        PopupMenuItem<NoteCreationType>(
          enabled: false,
          height: 36,
          child: Text(
            hasSelectedText ? 'Create from selection' : 'Create note',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const PopupMenuDivider(),
        for (final type in _creationOptions(hasSelectedText: hasSelectedText))
          PopupMenuItem<NoteCreationType>(
            value: type,
            height: 64,
            child: CreateNoteMenuItem(type: type),
          ),
      ],
    );

    if (selected == null) {
      return;
    }

    onCreateNote(
      creationType: selected,
      localPosition: localPosition,
      size: size,
    );
  }

  List<NoteCreationType> _creationOptions({required bool hasSelectedText}) {
    if (hasSelectedText) {
      return const [
        NoteCreationType.note,
        NoteCreationType.citation,
        NoteCreationType.highlight,
        NoteCreationType.question,
        NoteCreationType.definition,
        NoteCreationType.summary,
        NoteCreationType.task,
      ];
    }

    return const [
      NoteCreationType.note,
      NoteCreationType.question,
      NoteCreationType.summary,
      NoteCreationType.definition,
      NoteCreationType.task,
      NoteCreationType.citation,
    ];
  }

  void _finishActiveNoteIfNeeded() {
    if (activeEditingNoteId == null) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    onEditingNoteChanged(null);
  }

  bool get _hasActiveEditingNote => activeEditingNoteId != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final size = Size(width, pageHeight);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (_hasActiveEditingNote) {
              _finishActiveNoteIfNeeded();
              return;
            }

            onCreateNote(
              creationType: NoteCreationType.note,
              localPosition: details.localPosition,
              size: size,
            );
          },
          onSecondaryTapUp: (details) {
            if (_hasActiveEditingNote) {
              _finishActiveNoteIfNeeded();
              return;
            }

            _showCreateMenu(
              context: context,
              globalPosition: details.globalPosition,
              localPosition: details.localPosition,
              size: size,
            );
          },
          child: Container(
            height: pageHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: debugEnabled && isCurrentPage
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.surface,
              border: Border.all(
                color: debugEnabled
                    ? isCurrentPage
                          ? theme.colorScheme.primary.withValues(alpha: 0.50)
                          : theme.colorScheme.outlineVariant
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.12),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                if (debugEnabled)
                  Positioned(
                    left: 16,
                    top: 12,
                    child: PageLabel(
                      pageNumber: pageNumber,
                      isCurrentPage: isCurrentPage,
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: CustomPaint(
                      painter: NotebookLinePainter(
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
                    pdfPageRect: pdfPageRect,
                    autofocus: item.note.id == noteIdToFocus,
                    isRevealed: item.note.id == revealedNoteId,
                    onFocusConsumed: onFocusConsumed,
                    onEditingNoteChanged: onEditingNoteChanged,
                    onRequestPdfJumpToDocumentY: onRequestPdfJumpToDocumentY,
                    onUpdateNote: onUpdateNote,
                    onUpdateNoteType: onUpdateNoteType,
                    onUpdateTodoCompleted: onUpdateTodoCompleted,
                    onUpdateMetadata: onUpdateMetadata,
                    onMoveNote: onMoveNote,
                    onHoverSourceRectsChanged: onHoverSourceRectsChanged,
                    onArchiveIfEmpty: onArchiveIfEmpty,
                    onArchive: onArchive,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PositionedNote extends StatefulWidget {
  final NoteWithAnchor item;
  final double canvasWidth;
  final double pageHeight;
  final Rect pdfPageRect;
  final bool autofocus;
  final bool isRevealed;
  final VoidCallback onFocusConsumed;
  final ValueChanged<String?> onEditingNoteChanged;
  final ValueChanged<double>? onRequestPdfJumpToDocumentY;
  final void Function({
    required String noteId,
    required String blockId,
    required String text,
  })
  onUpdateNote;
  final void Function({required String noteId, required String noteType})
  onUpdateNoteType;
  final void Function({required String todoId, required bool isCompleted})
  onUpdateTodoCompleted;
  final void Function({
    required String anchorId,
    required NoteMetadata metadata,
  })
  onUpdateMetadata;
  final void Function({
    required String anchorId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
  })
  onMoveNote;
  final ValueChanged<List<PdfSourceRect>>? onHoverSourceRectsChanged;
  final void Function({required String noteId, required String blockId})
  onArchiveIfEmpty;
  final void Function(String noteId) onArchive;

  const _PositionedNote({
    required this.item,
    required this.canvasWidth,
    required this.pageHeight,
    required this.pdfPageRect,
    required this.autofocus,
    required this.isRevealed,
    required this.onFocusConsumed,
    required this.onEditingNoteChanged,
    required this.onUpdateNote,
    required this.onUpdateNoteType,
    required this.onUpdateTodoCompleted,
    required this.onUpdateMetadata,
    required this.onMoveNote,
    required this.onArchiveIfEmpty,
    required this.onArchive,
    this.onRequestPdfJumpToDocumentY,
    this.onHoverSourceRectsChanged,
  });

  @override
  State<_PositionedNote> createState() => _PositionedNoteState();
}

class _PositionedNoteState extends State<_PositionedNote> {
  double? _dragLeft;
  double? _dragTop;

  @override
  void didUpdateWidget(covariant _PositionedNote oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.item.anchor.geometryJson != widget.item.anchor.geometryJson) {
      _dragLeft = null;
      _dragTop = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.canvasWidth <= 8 || widget.pageHeight <= 8) {
      return const SizedBox.shrink();
    }

    final placement = widget.item.sidecarPlacement;

    final availableWidth = math.max(1.0, widget.canvasWidth - 8);
    final preferredWidth = placement.width * widget.canvasWidth;

    final minWidth = math.min(160.0, availableWidth);
    final maxWidth = math.max(minWidth, math.min(420.0, availableWidth));

    final noteWidth = preferredWidth.clamp(minWidth, maxWidth).toDouble();

    final rawLeft = placement.x * widget.canvasWidth;
    final maxLeft = math.max(4.0, widget.canvasWidth - noteWidth - 4);
    final baseLeft = maxLeft <= 4.0
        ? 4.0
        : rawLeft.clamp(4.0, maxLeft).toDouble();

    final rawTop = placement.y * widget.pageHeight;
    final maxTop = math.max(8.0, widget.pageHeight - 80.0);
    final baseTop = maxTop <= 8.0 ? 8.0 : rawTop.clamp(8.0, maxTop).toDouble();

    final left = _dragLeft ?? baseLeft;
    final top = _dragTop ?? baseTop;

    final blockId = widget.item.firstBlock?.id;

    if (blockId == null) {
      return const SizedBox.shrink();
    }

    void updateDragPosition(Offset delta) {
      setState(() {
        final nextLeft = ((_dragLeft ?? left) + delta.dx)
            .clamp(4.0, maxLeft)
            .toDouble();

        final nextTop = ((_dragTop ?? top) + delta.dy)
            .clamp(8.0, maxTop)
            .toDouble();

        _dragLeft = nextLeft;
        _dragTop = nextTop;
      });
    }

    void persistDragPosition() {
      final finalLeft = _dragLeft ?? left;
      final finalTop = _dragTop ?? top;

      widget.onMoveNote(
        anchorId: widget.item.anchor.id,
        pageNumber: placement.pageNumber,
        x: (finalLeft / widget.canvasWidth).clamp(0.0, 1.0).toDouble(),
        y: (finalTop / widget.pageHeight).clamp(0.0, 1.0).toDouble(),
        width: (noteWidth / widget.canvasWidth).clamp(0.15, 1.0).toDouble(),
      );
    }

    void jumpToSource() {
      final sourceRects = widget.item.sourceRects;
      double localPageY;

      if (sourceRects.isNotEmpty) {
        final source = sourceRects.first;
        localPageY = source.top
            .clamp(0.0, math.max(1.0, widget.pdfPageRect.height))
            .toDouble();
      } else {
        localPageY =
            placement.y.clamp(0.0, 1.0).toDouble() * widget.pdfPageRect.height;
      }

      widget.onRequestPdfJumpToDocumentY?.call(
        widget.pdfPageRect.top + localPageY,
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: noteWidth,
      child: MarginNoteCard(
        key: ValueKey(widget.item.note.id),
        item: widget.item,
        autofocus: widget.autofocus,
        isRevealed: widget.isRevealed,
        onFocusConsumed: widget.onFocusConsumed,
        onJumpToSource: widget.item.sourceRects.isEmpty ? null : jumpToSource,
        onEditingChanged: (isEditing) {
          widget.onEditingNoteChanged(isEditing ? widget.item.note.id : null);
        },
        onHoverChanged: (isHovered) {
          widget.onHoverSourceRectsChanged?.call(
            isHovered ? widget.item.sourceRects : const [],
          );
        },
        onDragDelta: updateDragPosition,
        onDragEnd: persistDragPosition,
        onChanged: (text) {
          widget.onUpdateNote(
            noteId: widget.item.note.id,
            blockId: blockId,
            text: text,
          );
        },
        onTypeChanged: (noteType) {
          widget.onUpdateNoteType(
            noteId: widget.item.note.id,
            noteType: noteType,
          );
        },
        onTodoCompletedChanged: (isCompleted) {
          widget.onUpdateTodoCompleted(
            todoId: widget.item.note.id,
            isCompleted: isCompleted,
          );
        },
        onMetadataChanged: (metadata) {
          widget.onUpdateMetadata(
            anchorId: widget.item.anchor.id,
            metadata: metadata,
          );
        },
        onArchiveIfEmpty: () {
          widget.onArchiveIfEmpty(
            noteId: widget.item.note.id,
            blockId: blockId,
          );
        },
        onArchive: () {
          widget.onArchive(widget.item.note.id);
        },
      ),
    );
  }
}
