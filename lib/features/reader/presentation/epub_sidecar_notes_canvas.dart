import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';
import '../../pdf_reader/presentation/sidecar/note_creation_type.dart';
import '../../pdf_reader/presentation/sidecar/note_type_presentation.dart';
import '../../pdf_reader/presentation/sidecar/widgets/create_note_menu_item.dart';
import '../domain/epub_sidecar_placement.dart';
import '../domain/reader_anchor.dart';
import '../domain/reader_document_ref.dart';

class EpubSidecarNotesCanvas extends StatefulWidget {
  final NoteRepository noteRepository;
  final ReaderDocumentRef document;
  final int spineIndex;
  final String href;
  final String sectionTitle;
  final List<String> paragraphs;
  final VoidCallback? onClose;
  final ValueChanged<int>? onRequestJumpToParagraph;

  const EpubSidecarNotesCanvas({
    super.key,
    required this.noteRepository,
    required this.document,
    required this.spineIndex,
    required this.href,
    required this.sectionTitle,
    required this.paragraphs,
    this.onClose,
    this.onRequestJumpToParagraph,
  });

  @override
  State<EpubSidecarNotesCanvas> createState() => _EpubSidecarNotesCanvasState();
}

class _EpubSidecarNotesCanvasState extends State<EpubSidecarNotesCanvas> {
  final ScrollController _scrollController = ScrollController();

  String? _noteIdToFocus;
  String? _activeEditingNoteId;

  static const double _defaultNoteWidth = 0.46;
  static const double _minCanvasHeight = 720.0;
  static const double _paragraphBandHeight = 92.0;
  static const double _sectionHeaderHeight = 112.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  ReaderAnchor _anchorForParagraph(int? paragraphIndex) {
    if (paragraphIndex == null ||
        paragraphIndex < 0 ||
        paragraphIndex >= widget.paragraphs.length) {
      return ReaderAnchor.epubSection(
        document: widget.document,
        spineIndex: widget.spineIndex,
        href: widget.href,
        title: widget.sectionTitle,
        sourceText: widget.paragraphs.isEmpty ? null : widget.paragraphs.first,
      );
    }

    return ReaderAnchor.epubParagraph(
      document: widget.document,
      spineIndex: widget.spineIndex,
      href: widget.href,
      sectionTitle: widget.sectionTitle,
      paragraphIndex: paragraphIndex,
      sourceText: widget.paragraphs[paragraphIndex],
    );
  }

  int? _paragraphIndexForY(double localY, double canvasHeight) {
    if (widget.paragraphs.isEmpty) return null;
    final contentTop = _sectionHeaderHeight;
    final contentHeight = math.max(1.0, canvasHeight - contentTop - 24);
    final normalized = ((localY - contentTop) / contentHeight).clamp(0.0, 0.999999);
    return (normalized * widget.paragraphs.length).floor();
  }

  EpubSidecarPlacement _placementForTap({
    required Offset localPosition,
    required Size canvasSize,
  }) {
    final paragraphIndex = _paragraphIndexForY(localPosition.dy, canvasSize.height);
    return EpubSidecarPlacement(
      spineIndex: widget.spineIndex,
      href: widget.href,
      sectionTitle: widget.sectionTitle,
      paragraphIndex: paragraphIndex,
      x: (localPosition.dx / math.max(1.0, canvasSize.width)).clamp(0.0, 0.82).toDouble(),
      y: (localPosition.dy / math.max(1.0, canvasSize.height)).clamp(0.0, 0.92).toDouble(),
      width: _defaultNoteWidth,
    );
  }

  Future<void> _showCreateMenu({
    required BuildContext context,
    required Offset globalPosition,
    required Offset localPosition,
    required Size canvasSize,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    const menuWidth = 244.0;
    const menuHeight = 270.0;
    final left = globalPosition.dx.clamp(8.0, math.max(8.0, overlay.size.width - menuWidth - 8)).toDouble();
    final top = globalPosition.dy.clamp(8.0, math.max(8.0, overlay.size.height - menuHeight - 8)).toDouble();

    final selected = await showMenu<NoteCreationType>(
      context: context,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlay.size.width - left - menuWidth,
        overlay.size.height - top,
      ),
      color: Theme.of(context).colorScheme.surface,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      items: const [
        PopupMenuItem<NoteCreationType>(
          enabled: false,
          height: 34,
          child: _EpubCreateMenuHeader(),
        ),
        PopupMenuItem<NoteCreationType>(
          value: NoteCreationType.note,
          height: 46,
          child: CreateNoteMenuItem(type: NoteCreationType.note),
        ),
        PopupMenuItem<NoteCreationType>(
          value: NoteCreationType.question,
          height: 46,
          child: CreateNoteMenuItem(type: NoteCreationType.question),
        ),
        PopupMenuItem<NoteCreationType>(
          value: NoteCreationType.task,
          height: 46,
          child: CreateNoteMenuItem(type: NoteCreationType.task),
        ),
        PopupMenuItem<NoteCreationType>(
          value: NoteCreationType.citation,
          height: 46,
          child: CreateNoteMenuItem(type: NoteCreationType.citation),
        ),
      ],
    );

    if (selected == null) return;
    await _createNote(
      creationType: selected,
      placement: _placementForTap(localPosition: localPosition, canvasSize: canvasSize),
    );
  }

  Future<void> _createNote({
    required NoteCreationType creationType,
    required EpubSidecarPlacement placement,
  }) async {
    final normalizedPlacement = placement.copyWith(
      spineIndex: widget.spineIndex,
      href: widget.href,
      sectionTitle: widget.sectionTitle,
    );
    final anchor = _anchorForParagraph(normalizedPlacement.paragraphIndex);
    try {
      final created = await widget.noteRepository.createReaderAnchoredTextNote(
        documentId: widget.document.documentId,
        anchorType: anchor.granularity == ReaderAnchorGranularity.paragraph
            ? kReaderAnchorTypeEpubParagraph
            : kReaderAnchorTypeEpubSection,
        geometryJson: normalizedPlacement.toJsonString(anchor: anchor),
        title: anchor.sourceText ?? anchor.label,
        body: '',
        selectedText: anchor.sourceText,
        noteType: creationType.id,
      );

      if (!mounted) return;
      setState(() {
        _noteIdToFocus = created.note.id;
        _activeEditingNoteId = created.note.id;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create EPUB sidecar note: $error')),
      );
    }
  }

  Future<void> _moveNote({
    required String anchorId,
    required EpubSidecarPlacement placement,
  }) {
    return widget.noteRepository.moveReaderSidecarNote(
      anchorId: anchorId,
      spineIndex: widget.spineIndex,
      href: widget.href,
      sectionTitle: widget.sectionTitle,
      paragraphIndex: placement.paragraphIndex,
      x: placement.x,
      y: placement.y,
      width: placement.width,
    );
  }

  double _canvasHeightFor(int paragraphCount) {
    return math.max(
      _minCanvasHeight,
      _sectionHeaderHeight + math.max(1, paragraphCount) * _paragraphBandHeight + 180,
    ).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          _EpubSidecarTopBar(
            sectionTitle: widget.sectionTitle,
            spineIndex: widget.spineIndex,
            paragraphCount: widget.paragraphs.length,
            onClose: widget.onClose,
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<NoteWithAnchor>>(
              stream: widget.noteRepository.watchReaderAnchoredNotesForDocument(
                documentId: widget.document.documentId,
              ),
              builder: (context, snapshot) {
                final notes = (snapshot.data ?? const <NoteWithAnchor>[]).where((item) {
                  final placement = EpubSidecarPlacement.fromGeometryJson(item.anchor.geometryJson);
                  return placement != null && placement.matchesSection(widget.spineIndex);
                }).toList();

                final canvasHeight = _canvasHeightFor(widget.paragraphs.length);

                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 40),
                    child: _EpubSidecarSectionCanvas(
                      canvasHeight: canvasHeight,
                      paragraphCount: widget.paragraphs.length,
                      sectionTitle: widget.sectionTitle,
                      notes: notes,
                      noteIdToFocus: _noteIdToFocus,
                      activeEditingNoteId: _activeEditingNoteId,
                      onFocusConsumed: () => setState(() => _noteIdToFocus = null),
                      onEditingNoteChanged: (id) => setState(() => _activeEditingNoteId = id),
                      onCreateNote: _createNote,
                      onShowCreateMenu: _showCreateMenu,
                      onMoveNote: _moveNote,
                      onJumpToParagraph: widget.onRequestJumpToParagraph,
                      noteRepository: widget.noteRepository,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EpubCreateMenuHeader extends StatelessWidget {
  const _EpubCreateMenuHeader();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Add to EPUB sidecar',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
    );
  }
}

class _EpubSidecarTopBar extends StatelessWidget {
  final String sectionTitle;
  final int spineIndex;
  final int paragraphCount;
  final VoidCallback? onClose;

  const _EpubSidecarTopBar({
    required this.sectionTitle,
    required this.spineIndex,
    required this.paragraphCount,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
        child: Row(
          children: [
            Icon(Icons.sticky_note_2_outlined, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'EPUB sidecar',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Section ${spineIndex + 1} · $paragraphCount paragraph anchors',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Hide sidecar',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _EpubSidecarSectionCanvas extends StatelessWidget {
  final double canvasHeight;
  final int paragraphCount;
  final String sectionTitle;
  final List<NoteWithAnchor> notes;
  final String? noteIdToFocus;
  final String? activeEditingNoteId;
  final VoidCallback onFocusConsumed;
  final ValueChanged<String?> onEditingNoteChanged;
  final Future<void> Function({
    required NoteCreationType creationType,
    required EpubSidecarPlacement placement,
  }) onCreateNote;
  final Future<void> Function({
    required BuildContext context,
    required Offset globalPosition,
    required Offset localPosition,
    required Size canvasSize,
  }) onShowCreateMenu;
  final Future<void> Function({
    required String anchorId,
    required EpubSidecarPlacement placement,
  }) onMoveNote;
  final ValueChanged<int>? onJumpToParagraph;
  final NoteRepository noteRepository;

  const _EpubSidecarSectionCanvas({
    required this.canvasHeight,
    required this.paragraphCount,
    required this.sectionTitle,
    required this.notes,
    required this.noteIdToFocus,
    required this.activeEditingNoteId,
    required this.onFocusConsumed,
    required this.onEditingNoteChanged,
    required this.onCreateNote,
    required this.onShowCreateMenu,
    required this.onMoveNote,
    required this.onJumpToParagraph,
    required this.noteRepository,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasWidth = constraints.maxWidth;
        final canvasSize = Size(canvasWidth, canvasHeight);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (activeEditingNoteId != null) {
              FocusManager.instance.primaryFocus?.unfocus();
              onEditingNoteChanged(null);
              return;
            }
            final placement = _placementForTap(details.localPosition, canvasSize);
            onCreateNote(creationType: NoteCreationType.note, placement: placement);
          },
          onSecondaryTapUp: (details) {
            if (activeEditingNoteId != null) {
              FocusManager.instance.primaryFocus?.unfocus();
              onEditingNoteChanged(null);
              return;
            }
            onShowCreateMenu(
              context: context,
              globalPosition: details.globalPosition,
              localPosition: details.localPosition,
              canvasSize: canvasSize,
            );
          },
          child: Container(
            height: canvasHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              border: Border(
                left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _EpubParagraphGuideLayer(
                    paragraphCount: paragraphCount,
                    sectionTitle: sectionTitle,
                  ),
                ),
                if (notes.isEmpty)
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 24,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.edit_note_rounded, color: colorScheme.primary, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Click the EPUB sidecar to add a margin note. Notes are placed spatially against this reader section, not in a generic list.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final item in notes)
                  _PositionedEpubNote(
                    key: ValueKey(item.note.id),
                    item: item,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    autofocus: item.note.id == noteIdToFocus,
                    onFocusConsumed: onFocusConsumed,
                    onEditingNoteChanged: onEditingNoteChanged,
                    onMoveNote: onMoveNote,
                    onJumpToParagraph: onJumpToParagraph,
                    noteRepository: noteRepository,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  EpubSidecarPlacement _placementForTap(Offset position, Size size) {
    int? paragraphIndex;
    if (paragraphCount > 0) {
      final contentTop = _EpubSidecarNotesCanvasState._sectionHeaderHeight;
      final contentHeight = math.max(1.0, size.height - contentTop - 24);
      final normalized = ((position.dy - contentTop) / contentHeight).clamp(0.0, 0.999999);
      paragraphIndex = (normalized * paragraphCount).floor();
    }

    return EpubSidecarPlacement(
      spineIndex: 0,
      paragraphIndex: paragraphIndex,
      x: (position.dx / math.max(1.0, size.width)).clamp(0.0, 0.82).toDouble(),
      y: (position.dy / math.max(1.0, size.height)).clamp(0.0, 0.92).toDouble(),
      width: _EpubSidecarNotesCanvasState._defaultNoteWidth,
    );
  }
}

class _EpubParagraphGuideLayer extends StatelessWidget {
  final int paragraphCount;
  final String sectionTitle;

  const _EpubParagraphGuideLayer({
    required this.paragraphCount,
    required this.sectionTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final contentTop = _EpubSidecarNotesCanvasState._sectionHeaderHeight;
        final contentHeight = math.max(1.0, height - contentTop - 24);

        return Stack(
          children: [
            Positioned(
              top: 18,
              left: 18,
              right: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sectionTitle.trim().isEmpty ? 'Reader section' : sectionTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    paragraphCount == 0
                        ? 'Section-level margin canvas'
                        : 'Paragraph-relative margin canvas · ${paragraphCount} anchors',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (paragraphCount > 0)
              for (var index = 0; index < paragraphCount; index++)
                Positioned(
                  top: contentTop + (contentHeight / paragraphCount) * index,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: math.max(32, contentHeight / paragraphCount),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: index == 0 ? 0.38 : 0.24),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, top: 6),
                      child: Text(
                        '¶ ${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.52),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _PositionedEpubNote extends StatefulWidget {
  final NoteWithAnchor item;
  final double canvasWidth;
  final double canvasHeight;
  final bool autofocus;
  final VoidCallback onFocusConsumed;
  final ValueChanged<String?> onEditingNoteChanged;
  final Future<void> Function({
    required String anchorId,
    required EpubSidecarPlacement placement,
  }) onMoveNote;
  final ValueChanged<int>? onJumpToParagraph;
  final NoteRepository noteRepository;

  const _PositionedEpubNote({
    super.key,
    required this.item,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.autofocus,
    required this.onFocusConsumed,
    required this.onEditingNoteChanged,
    required this.onMoveNote,
    required this.onJumpToParagraph,
    required this.noteRepository,
  });

  @override
  State<_PositionedEpubNote> createState() => _PositionedEpubNoteState();
}

class _PositionedEpubNoteState extends State<_PositionedEpubNote> {
  double? _dragLeft;
  double? _dragTop;

  @override
  void didUpdateWidget(covariant _PositionedEpubNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.anchor.geometryJson != widget.item.anchor.geometryJson) {
      _dragLeft = null;
      _dragTop = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placement = EpubSidecarPlacement.fromGeometryJson(widget.item.anchor.geometryJson);
    if (placement == null || widget.canvasWidth <= 8 || widget.canvasHeight <= 8) {
      return const SizedBox.shrink();
    }

    final preferredWidth = placement.width * widget.canvasWidth;
    final minWidth = math.min(112.0, widget.canvasWidth - 8);
    final maxWidth = math.max(minWidth, math.min(360.0, widget.canvasWidth - 8));
    final noteWidth = preferredWidth.clamp(minWidth, maxWidth).toDouble();

    final maxLeft = math.max(4.0, widget.canvasWidth - noteWidth - 4);
    final baseLeft = (placement.x * widget.canvasWidth).clamp(4.0, maxLeft).toDouble();
    final maxTop = math.max(8.0, widget.canvasHeight - 96.0);
    final baseTop = (placement.y * widget.canvasHeight).clamp(8.0, maxTop).toDouble();

    final left = _dragLeft ?? baseLeft;
    final top = _dragTop ?? baseTop;

    void updateDrag(Offset delta) {
      setState(() {
        _dragLeft = ((_dragLeft ?? left) + delta.dx).clamp(4.0, maxLeft).toDouble();
        _dragTop = ((_dragTop ?? top) + delta.dy).clamp(8.0, maxTop).toDouble();
      });
    }

    void persistDrag() {
      final finalLeft = _dragLeft ?? left;
      final finalTop = _dragTop ?? top;
      widget.onMoveNote(
        anchorId: widget.item.anchor.id,
        placement: placement.copyWith(
          x: (finalLeft / widget.canvasWidth).clamp(0.0, 1.0).toDouble(),
          y: (finalTop / widget.canvasHeight).clamp(0.0, 1.0).toDouble(),
          width: (noteWidth / widget.canvasWidth).clamp(0.18, 1.0).toDouble(),
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: noteWidth,
      child: _EpubSidecarNoteCard(
        item: widget.item,
        autofocus: widget.autofocus,
        onFocusConsumed: widget.onFocusConsumed,
        onEditingChanged: (editing) => widget.onEditingNoteChanged(editing ? widget.item.note.id : null),
        onDragDelta: updateDrag,
        onDragEnd: persistDrag,
        onJumpToSource: placement.paragraphIndex == null || widget.onJumpToParagraph == null
            ? null
            : () => widget.onJumpToParagraph!(placement.paragraphIndex!),
        noteRepository: widget.noteRepository,
      ),
    );
  }
}

class _EpubSidecarNoteCard extends StatefulWidget {
  final NoteWithAnchor item;
  final bool autofocus;
  final VoidCallback onFocusConsumed;
  final ValueChanged<bool> onEditingChanged;
  final ValueChanged<Offset> onDragDelta;
  final VoidCallback onDragEnd;
  final VoidCallback? onJumpToSource;
  final NoteRepository noteRepository;

  const _EpubSidecarNoteCard({
    required this.item,
    required this.autofocus,
    required this.onFocusConsumed,
    required this.onEditingChanged,
    required this.onDragDelta,
    required this.onDragEnd,
    required this.noteRepository,
    this.onJumpToSource,
  });

  @override
  State<_EpubSidecarNoteCard> createState() => _EpubSidecarNoteCardState();
}

class _EpubSidecarNoteCardState extends State<_EpubSidecarNoteCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;
  bool _editing = false;
  bool _hovered = false;
  bool _dragging = false;

  static const Duration _autosaveDelay = Duration(milliseconds: 650);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.body);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    _editing = widget.autofocus || widget.item.body.trim().isEmpty;

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enterEditing();
        widget.onFocusConsumed();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _EpubSidecarNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.note.id != widget.item.note.id) {
      _controller.text = widget.item.body;
      _editing = widget.item.body.trim().isEmpty;
    } else if (!_focusNode.hasFocus && oldWidget.item.body != widget.item.body) {
      _controller.text = widget.item.body;
    }

    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enterEditing();
        widget.onFocusConsumed();
      });
    }
  }

  @override
  void dispose() {
    _flush();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _editing) {
      _exitEditing();
    }
  }

  void _enterEditing() {
    if (!_editing) {
      setState(() => _editing = true);
    }
    widget.onEditingChanged(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  void _exitEditing() {
    _flush();
    widget.onEditingChanged(false);
    if (_controller.text.trim().isEmpty) {
      final blockId = widget.item.firstBlock?.id;
      if (blockId != null) {
        widget.noteRepository.archiveNoteIfEmpty(noteId: widget.item.note.id, blockId: blockId);
      }
      return;
    }
    if (mounted) setState(() => _editing = false);
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, () => _persistText(value));
  }

  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    _persistText(_controller.text);
  }

  Future<void> _persistText(String value) async {
    final blockId = widget.item.firstBlock?.id;
    if (blockId == null) return;
    await widget.noteRepository.updateTextBlock(
      noteId: widget.item.note.id,
      blockId: blockId,
      body: value,
    );
  }

  Future<void> _changeType(NoteCreationType type) async {
    await widget.noteRepository.updateNoteType(
      noteId: widget.item.note.id,
      noteType: type.id,
    );
  }

  Future<void> _archive() async {
    await widget.noteRepository.archiveNote(widget.item.note.id);
  }

  bool get _isTodo => widget.item.noteType == kTodoNoteType;

  bool get _todoCompleted {
    final json = widget.item.firstBlock?.contentJson;
    if (json == null || json.isEmpty) return false;
    return json.contains('"isCompleted":true') || json.contains('"isCompleted": true');
  }

  Future<void> _setTodoCompleted(bool value) {
    return widget.noteRepository.updateTodoCompleted(
      todoId: widget.item.note.id,
      isCompleted: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = NoteTypePresentation.fromType(widget.item.noteType, theme);
    final showChrome = _hovered || _editing || _dragging;
    final selectedText = widget.item.anchor.selectedText?.trim();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: showChrome
              ? colorScheme.surface.withValues(alpha: 0.97)
              : colorScheme.surface.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showChrome ? colorScheme.outlineVariant : Colors.transparent,
          ),
          boxShadow: showChrome
              ? [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => setState(() => _dragging = true),
              onPanUpdate: (details) => widget.onDragDelta(details.delta),
              onPanEnd: (_) {
                setState(() => _dragging = false);
                widget.onDragEnd();
              },
              onPanCancel: () {
                setState(() => _dragging = false);
                widget.onDragEnd();
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  width: showChrome ? 6 : 4,
                  constraints: const BoxConstraints(minHeight: 56),
                  decoration: BoxDecoration(
                    color: presentation.accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                onTap: _enterEditing,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showChrome)
                        Row(
                          children: [
                            Icon(presentation.icon, size: 15, color: presentation.accentColor),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                presentation.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (widget.onJumpToSource != null)
                              IconButton(
                                tooltip: 'Jump to paragraph',
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                onPressed: widget.onJumpToSource,
                                icon: const Icon(Icons.my_location_rounded),
                              ),
                            PopupMenuButton<NoteCreationType>(
                              tooltip: 'Change note type',
                              iconSize: 16,
                              onSelected: _changeType,
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: NoteCreationType.note, child: CreateNoteMenuItem(type: NoteCreationType.note)),
                                PopupMenuItem(value: NoteCreationType.question, child: CreateNoteMenuItem(type: NoteCreationType.question)),
                                PopupMenuItem(value: NoteCreationType.task, child: CreateNoteMenuItem(type: NoteCreationType.task)),
                                PopupMenuItem(value: NoteCreationType.citation, child: CreateNoteMenuItem(type: NoteCreationType.citation)),
                              ],
                            ),
                            IconButton(
                              tooltip: 'Archive note',
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              onPressed: _archive,
                              icon: const Icon(Icons.archive_outlined),
                            ),
                          ],
                        ),
                      if (selectedText != null && selectedText.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            selectedText,
                            maxLines: showChrome ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                      if (_isTodo)
                        Row(
                          children: [
                            Checkbox(
                              value: _todoCompleted,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) => _setTodoCompleted(value ?? false),
                            ),
                            Text('TODO', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900)),
                          ],
                        ),
                      if (_editing)
                        TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: null,
                          autofocus: widget.autofocus,
                          onChanged: _onTextChanged,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Type here...',
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.25),
                        )
                      else
                        Text(
                          widget.item.body.trim().isEmpty ? 'Empty note' : widget.item.body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.25,
                            color: widget.item.body.trim().isEmpty
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSurface,
                            fontStyle: widget.item.body.trim().isEmpty ? FontStyle.italic : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
