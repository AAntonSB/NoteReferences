import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../notes/data/note_repository.dart';
import '../note_type_presentation.dart';

class NotesOutlinePanel extends StatefulWidget {
  final List<NoteWithAnchor> notes;
  final ValueChanged<NoteWithAnchor> onSelectNote;
  final VoidCallback onClose;
  final VoidCallback? onPointerEnterPanel;
  final VoidCallback? onPointerExitPanel;
  final ValueListenable<int>? searchFocusRequestListenable;

  const NotesOutlinePanel({
    super.key,
    required this.notes,
    required this.onSelectNote,
    required this.onClose,
    this.onPointerEnterPanel,
    this.onPointerExitPanel,
    this.searchFocusRequestListenable,
  });

  @override
  State<NotesOutlinePanel> createState() => _NotesOutlinePanelState();
}

class _NotesOutlinePanelState extends State<NotesOutlinePanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _typeFilterScrollController = ScrollController();
  final ScrollController _notesScrollController = ScrollController();

  String _query = '';
  String _typeFilter = 'all';
  int? _lastHandledFocusRequest;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });

    widget.searchFocusRequestListenable?.addListener(_handleSearchFocusRequest);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleSearchFocusRequest();
    });
  }

  @override
  void didUpdateWidget(covariant NotesOutlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.searchFocusRequestListenable !=
        widget.searchFocusRequestListenable) {
      oldWidget.searchFocusRequestListenable?.removeListener(
        _handleSearchFocusRequest,
      );
      widget.searchFocusRequestListenable?.addListener(
        _handleSearchFocusRequest,
      );
    }
  }

  @override
  void dispose() {
    widget.searchFocusRequestListenable?.removeListener(
      _handleSearchFocusRequest,
    );
    _typeFilterScrollController.dispose();
    _notesScrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusRequest() {
    final value = widget.searchFocusRequestListenable?.value;

    if (value == null || value == _lastHandledFocusRequest) {
      return;
    }

    _lastHandledFocusRequest = value;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  List<NoteWithAnchor> _filteredNotes() {
    final visibleNotes =
        widget.notes.where((note) => note.noteType != 'highlight').toList()
          ..sort((a, b) {
            final pageCompare = a.sidecarPlacement.pageNumber.compareTo(
              b.sidecarPlacement.pageNumber,
            );

            if (pageCompare != 0) return pageCompare;

            return a.sidecarPlacement.y.compareTo(b.sidecarPlacement.y);
          });

    return visibleNotes.where((note) {
      if (_typeFilter != 'all' && note.noteType != _typeFilter) {
        return false;
      }

      if (_query.isEmpty) {
        return true;
      }

      final metadata = note.metadata;
      final selectedText = note.anchor.selectedText ?? '';

      final haystack = [
        note.body,
        selectedText,
        note.noteType,
        metadata.status,
        metadata.importance,
        metadata.tags.join(' '),
        'page ${note.sidecarPlacement.pageNumber}',
        'p ${note.sidecarPlacement.pageNumber}',
      ].join(' ').toLowerCase();

      return haystack.contains(_query);
    }).toList();
  }

  List<String> _availableTypes() {
    final types =
        widget.notes
            .where((note) => note.noteType != 'highlight')
            .map((note) => note.noteType)
            .toSet()
            .toList()
          ..sort();

    return types;
  }

  void _handleSearchSubmitted(String _) {
    final filtered = _filteredNotes();

    if (filtered.isEmpty) {
      return;
    }

    widget.onSelectNote(filtered.first);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredNotes = _filteredNotes();
    final availableTypes = _availableTypes();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final panelWidth = availableWidth < 360.0 ? availableWidth : 360.0;

        return Align(
          alignment: Alignment.centerRight,
          child: MouseRegion(
            onEnter: (_) => widget.onPointerEnterPanel?.call(),
            onExit: (_) => widget.onPointerExitPanel?.call(),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              color: theme.colorScheme.surface,
              child: SizedBox(
                width: panelWidth,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 680),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                        child: Row(
                          children: [
                            const Icon(Icons.view_sidebar_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Notes outline',
                              style: theme.textTheme.titleSmall,
                            ),
                            const Spacer(),
                            Text(
                              '${filteredNotes.length}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onSubmitted: _handleSearchSubmitted,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: _searchController.clear,
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                            hintText: 'Search notes, quotes, tags...',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (availableTypes.isNotEmpty)
                        SizedBox(
                          height: 40,
                          child: ListView(
                            controller: _typeFilterScrollController,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: const Text('All'),
                                  selected: _typeFilter == 'all',
                                  onSelected: (_) {
                                    setState(() {
                                      _typeFilter = 'all';
                                    });
                                  },
                                ),
                              ),
                              for (final type in availableTypes)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(
                                      NoteTypePresentation.fromType(
                                        type,
                                        theme,
                                      ).label,
                                    ),
                                    selected: _typeFilter == type,
                                    onSelected: (_) {
                                      setState(() {
                                        _typeFilter = type;
                                      });
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const Divider(height: 1),
                      if (filteredNotes.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              _query.isEmpty
                                  ? 'No notes yet.'
                                  : 'No matching notes.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Scrollbar(
                            controller: _notesScrollController,
                            thumbVisibility: true,
                            child: ListView.separated(
                              controller: _notesScrollController,
                              primary: false,
                              padding: const EdgeInsets.all(8),
                              itemCount: filteredNotes.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final note = filteredNotes[index];
                                return _OutlineNoteTile(
                                  note: note,
                                  onTap: () => widget.onSelectNote(note),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OutlineNoteTile extends StatelessWidget {
  final NoteWithAnchor note;
  final VoidCallback onTap;

  const _OutlineNoteTile({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = NoteTypePresentation.fromType(note.noteType, theme);
    final metadata = note.metadata;
    final body = note.body.trim();
    final quote = note.anchor.selectedText?.trim();

    final snippet = body.isNotEmpty
        ? body
        : quote != null && quote.isNotEmpty
        ? '“$quote”'
        : 'Empty note';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 48,
              decoration: BoxDecoration(
                color: presentation.accentColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        presentation.icon,
                        size: 14,
                        color: presentation.accentColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        presentation.label,
                        style: theme.textTheme.labelSmall,
                      ),
                      const Spacer(),
                      Text(
                        'p. ${note.sidecarPlacement.pageNumber}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snippet,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (metadata.tags.isNotEmpty ||
                      metadata.status != 'none' ||
                      metadata.importance != 'normal') ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (metadata.status != 'none')
                          _MiniBadge(label: metadata.status),
                        if (metadata.importance != 'normal')
                          _MiniBadge(label: metadata.importance),
                        for (final tag in metadata.tags.take(4))
                          _MiniBadge(label: tag),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;

  const _MiniBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
