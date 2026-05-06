import 'package:flutter/material.dart';

import '../persistence/text_system_save_state.dart';
import 'text_system_surface_controller.dart';

class TextSystemSurfaceStatusBar extends StatelessWidget {
  const TextSystemSurfaceStatusBar({
    super.key,
    required this.surfaceController,
    this.showSelection = true,
  });

  final TextSystemSurfaceController surfaceController;
  final bool showSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saveState = surfaceController.autosaveController?.saveState;
    final saveLabel = _saveLabel(saveState);
    final saveIcon = _saveIcon(saveState?.status);
    final saveColor = _saveColor(theme, saveState?.status);

    return DefaultTextStyle.merge(
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(saveIcon, size: 15, color: saveColor),
              const SizedBox(width: 6),
              Text(saveLabel, overflow: TextOverflow.ellipsis),
            ],
          ),
          Text('Revision ${surfaceController.textController.revision}'),
          if (showSelection) Text(surfaceController.selectionLabel, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  static String _saveLabel(TextSystemSaveState? saveState) {
    if (saveState == null) return 'Local editing';
    final lastSavedAt = saveState.lastSavedAt;
    final lastSavedSuffix = lastSavedAt == null ? '' : ' at ${_formatClock(lastSavedAt)}';
    return switch (saveState.status) {
      TextSystemSaveStatus.clean => saveState.message ?? 'No changes yet',
      TextSystemSaveStatus.dirty => saveState.message ?? 'Unsaved changes',
      TextSystemSaveStatus.saving => 'Saving…',
      TextSystemSaveStatus.saved => saveState.message ?? 'Saved$lastSavedSuffix',
      TextSystemSaveStatus.failed => saveState.message ?? 'Save failed',
    };
  }

  static IconData _saveIcon(TextSystemSaveStatus? status) {
    return switch (status) {
      TextSystemSaveStatus.dirty => Icons.circle_rounded,
      TextSystemSaveStatus.saving => Icons.sync_rounded,
      TextSystemSaveStatus.saved => Icons.check_circle_rounded,
      TextSystemSaveStatus.failed => Icons.error_rounded,
      TextSystemSaveStatus.clean || null => Icons.check_rounded,
    };
  }

  static Color _saveColor(ThemeData theme, TextSystemSaveStatus? status) {
    return switch (status) {
      TextSystemSaveStatus.dirty => theme.colorScheme.tertiary,
      TextSystemSaveStatus.saving => theme.colorScheme.primary,
      TextSystemSaveStatus.saved => theme.colorScheme.primary,
      TextSystemSaveStatus.failed => theme.colorScheme.error,
      TextSystemSaveStatus.clean || null => theme.colorScheme.onSurfaceVariant,
    };
  }

  static String _formatClock(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
