import 'package:flutter/material.dart';

import '../note_creation_type.dart';
import '../note_type_presentation.dart';

class MarginNoteToolbar extends StatelessWidget {
  final NoteTypePresentation presentation;
  final String currentType;
  final bool showActions;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onArchive;
  final VoidCallback onEditDetails;
  final ValueChanged<Offset>? onDragDelta;
  final VoidCallback? onDragEnd;

  const MarginNoteToolbar({
    super.key,
    required this.presentation,
    required this.currentType,
    required this.showActions,
    required this.onTypeChanged,
    required this.onArchive,
    required this.onEditDetails,
    this.onDragDelta,
    this.onDragEnd,
  });

  Future<void> _showOptionsMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text(
            'Note options',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'details',
          height: 48,
          child: Row(
            children: [
              Icon(Icons.tune, size: 18),
              SizedBox(width: 10),
              Text('Details & metadata'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text(
            'Convert type',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        for (final type in NoteCreationType.values.where(
          (type) => type != NoteCreationType.highlight,
        ))
          PopupMenuItem<String>(
            value: 'type:${type.id}',
            height: 48,
            child: Row(
              children: [
                Icon(
                  currentType == type.id ? Icons.check : type.icon,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(type.label),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'archive',
          height: 48,
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 18),
              SizedBox(width: 10),
              Text('Archive'),
            ],
          ),
        ),
      ],
    );

    if (selected == null) return;

    if (selected == 'details') {
      onEditDetails();
      return;
    }

    if (selected.startsWith('type:')) {
      onTypeChanged(selected.substring('type:'.length));
      return;
    }

    if (selected == 'archive') {
      onArchive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 22,
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: showActions && onDragDelta != null ? 1 : 0,
            duration: const Duration(milliseconds: 100),
            child: IgnorePointer(
              ignoring: !showActions || onDragDelta == null,
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    onDragDelta?.call(details.delta);
                  },
                  onPanEnd: (_) {
                    onDragEnd?.call();
                  },
                  onPanCancel: () {
                    onDragEnd?.call();
                  },
                  child: SizedBox(
                    width: 18,
                    height: 22,
                    child: Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Icon(
            presentation.icon,
            size: 14,
            color: presentation.accentColor,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              presentation.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.0,
              ),
            ),
          ),
          const Spacer(),
          AnimatedOpacity(
            opacity: showActions ? 1 : 0,
            duration: const Duration(milliseconds: 100),
            child: IgnorePointer(
              ignoring: !showActions,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  _showOptionsMenu(context, details.globalPosition);
                },
                child: SizedBox(
                  width: 24,
                  height: 22,
                  child: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}