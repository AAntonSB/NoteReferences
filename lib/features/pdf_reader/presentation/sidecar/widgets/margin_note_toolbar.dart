import 'package:flutter/material.dart';

import '../note_creation_type.dart';
import '../note_type_presentation.dart';

class MarginNoteToolbar extends StatelessWidget {
  final NoteTypePresentation presentation;
  final String currentType;
  final bool showActions;
  final ValueChanged<String> onTypeChanged;
  final bool showMoveHandle;
  final VoidCallback onArchive;
  final VoidCallback onEditDetails;
  final VoidCallback? onDragStart;
  final ValueChanged<Offset>? onDragDelta;
  final VoidCallback? onDragEnd;

  const MarginNoteToolbar({
    super.key,
    required this.presentation,
    required this.currentType,
    required this.showActions,
    required this.onTypeChanged,
    this.showMoveHandle = true,
    required this.onArchive,
    required this.onEditDetails,
    this.onDragStart,
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
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 10),
              Text('Delete note'),
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

    return AnimatedOpacity(
      opacity: showActions ? 1 : 0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !showActions,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMoveHandle)
              SizedBox(
                width: 74,
                child: MouseRegion(
                  cursor: onDragDelta == null
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.move,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => onDragStart?.call(),
                    onPanUpdate: (details) {
                      onDragDelta?.call(details.delta);
                    },
                    onPanEnd: (_) {
                      onDragEnd?.call();
                    },
                    onPanCancel: () {
                      onDragEnd?.call();
                    },
                    child: Container(
                      height: 22,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 7, right: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.72,
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.42,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.drag_indicator,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.76),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Move',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (showMoveHandle) const SizedBox(width: 4),
            _HoverIconButton(
              tooltip: 'Delete note',
              icon: Icons.delete_outline,
              color: theme.colorScheme.error,
              onTap: onArchive,
            ),
            _HoverIconButton(
              tooltip: 'More actions',
              icon: Icons.more_horiz,
              color: theme.colorScheme.onSurfaceVariant,
              onTapDown: (details) {
                _showOptionsMenu(context, details.globalPosition);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onTapDown;

  const _HoverIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    this.onTap,
    this.onTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onTapDown: onTapDown,
          child: Container(
            width: 24,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
              ),
            ),
            child: Icon(icon, size: 15, color: color.withValues(alpha: 0.82)),
          ),
        ),
      ),
    );
  }
}
