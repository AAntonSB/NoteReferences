import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';
import '../domain/reader_anchor.dart';
import '../domain/reader_sidecar_bridge.dart';

class ReaderSidecarPanel extends StatelessWidget {
  final ReaderSidecarBridgeState bridge;
  final VoidCallback? onClose;
  final Stream<List<NoteWithAnchor>>? notesStream;
  final ValueChanged<ReaderAnchor>? onCreateNote;
  final ValueChanged<ReaderAnchor>? onCreateTodo;
  final ValueChanged<ReaderAnchor>? onPlanWork;

  const ReaderSidecarPanel({
    super.key,
    required this.bridge,
    this.onClose,
    this.notesStream,
    this.onCreateNote,
    this.onCreateTodo,
    this.onPlanWork,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.view_sidebar_rounded, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Reader sidecar',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          bridge.currentAnchor.locationLabel,
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
                      tooltip: 'Close sidecar',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  _AnchorSummaryCard(anchor: bridge.currentAnchor),
                  const SizedBox(height: 12),
                  _ReaderNotesList(notesStream: notesStream),
                  const SizedBox(height: 12),
                  _ActionCard(
                    bridge: bridge,
                    onCreateNote: onCreateNote,
                    onCreateTodo: onCreateTodo,
                    onPlanWork: onPlanWork,
                  ),
                  const SizedBox(height: 18),
                  _VisibleAnchorsList(
                    anchors: bridge.visibleAnchors,
                    canCreateNote: bridge.canCreateNote,
                    onCreateNote: onCreateNote,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnchorSummaryCard extends StatelessWidget {
  final ReaderAnchor anchor;

  const _AnchorSummaryCard({required this.anchor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  anchor.isEpub ? Icons.menu_book_rounded : Icons.picture_as_pdf_rounded,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    anchor.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _BridgeChip(label: _readerDocumentKindLabel(anchor.documentKind)),
                _BridgeChip(label: anchor.granularity.label),
                _BridgeChip(label: anchor.locationLabel),
              ],
            ),
            if (anchor.sourceText != null) ...[
              const SizedBox(height: 12),
              Text(
                anchor.sourceText!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final ReaderSidecarBridgeState bridge;
  final ValueChanged<ReaderAnchor>? onCreateNote;
  final ValueChanged<ReaderAnchor>? onCreateTodo;
  final ValueChanged<ReaderAnchor>? onPlanWork;

  const _ActionCard({
    required this.bridge,
    required this.onCreateNote,
    required this.onCreateTodo,
    required this.onPlanWork,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final anchor = bridge.currentAnchor;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create from this location',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a source-linked note at the current reader location. TODOs and planning actions will use the same anchors in later phases.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: bridge.canCreateNote && onCreateNote != null ? () => onCreateNote!(anchor) : null,
                  icon: const Icon(Icons.sticky_note_2_rounded),
                  label: const Text('Note'),
                ),
                OutlinedButton.icon(
                  onPressed: bridge.canCreateTodo && onCreateTodo != null ? () => onCreateTodo!(anchor) : null,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('TODO'),
                ),
                OutlinedButton.icon(
                  onPressed: bridge.canPlanWork && onPlanWork != null ? () => onPlanWork!(anchor) : null,
                  icon: const Icon(Icons.event_note_rounded),
                  label: const Text('Plan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderNotesList extends StatelessWidget {
  final Stream<List<NoteWithAnchor>>? notesStream;

  const _ReaderNotesList({required this.notesStream});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stream = notesStream;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reader notes',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Notes created from EPUB section and paragraph anchors appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (stream == null)
              Text(
                'No note stream is connected yet.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              )
            else
              StreamBuilder<List<NoteWithAnchor>>(
                stream: stream,
                builder: (context, snapshot) {
                  final notes = snapshot.data ?? const <NoteWithAnchor>[];
                  if (snapshot.connectionState == ConnectionState.waiting && notes.isEmpty) {
                    return const LinearProgressIndicator(minHeight: 2);
                  }
                  if (notes.isEmpty) {
                    return Text(
                      'No EPUB reader notes yet.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    );
                  }

                  return Column(
                    children: [
                      for (final note in notes.take(5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.note.title ?? note.anchor.selectedText ?? 'Reader note',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                if (note.body.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    note.body.trim(),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (notes.length > 5)
                        Text(
                          '+${notes.length - 5} more notes',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _VisibleAnchorsList extends StatelessWidget {
  final List<ReaderAnchor> anchors;
  final bool canCreateNote;
  final ValueChanged<ReaderAnchor>? onCreateNote;

  const _VisibleAnchorsList({
    required this.anchors,
    required this.canCreateNote,
    required this.onCreateNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visible anchors',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          anchors.isEmpty
              ? 'Load a section to expose paragraph anchors.'
              : 'First visible EPUB paragraph anchors. Create a note directly from any paragraph anchor.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        if (anchors.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              'No paragraph anchors loaded yet.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          for (final anchor in anchors.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anchor.label,
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (anchor.sourceText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        anchor.sourceText!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: canCreateNote && onCreateNote != null
                            ? () => onCreateNote!(anchor)
                            : null,
                        icon: const Icon(Icons.sticky_note_2_rounded, size: 18),
                        label: const Text('Note here'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}


String _readerDocumentKindLabel(Object kind) {
  final raw = kind.toString().split('.').last.trim();
  switch (raw) {
    case 'pdf':
      return 'PDF';
    case 'epub':
      return 'EPUB';
    default:
      if (raw.isEmpty) {
        return 'Document';
      }
      return raw[0].toUpperCase() + raw.substring(1);
  }
}

class _BridgeChip extends StatelessWidget {
  final String label;

  const _BridgeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
