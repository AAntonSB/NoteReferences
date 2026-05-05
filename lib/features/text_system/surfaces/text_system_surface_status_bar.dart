import 'package:flutter/material.dart';

import '../persistence/text_system_save_state.dart';
import 'text_system_surface_controller.dart';

class TextSystemSurfaceStatusBar extends StatelessWidget {
  const TextSystemSurfaceStatusBar({
    super.key,
    required this.surfaceController,
  });

  final TextSystemSurfaceController surfaceController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saveState = surfaceController.autosaveController?.saveState;
    final saveLabel = saveState?.message ?? 'No persistence adapter';
    final saveIcon = switch (saveState?.status) {
      TextSystemSaveStatus.dirty => Icons.circle_rounded,
      TextSystemSaveStatus.saving => Icons.sync_rounded,
      TextSystemSaveStatus.saved => Icons.check_circle_rounded,
      TextSystemSaveStatus.failed => Icons.error_rounded,
      TextSystemSaveStatus.clean || null => Icons.check_rounded,
    };

    return DefaultTextStyle.merge(
      style: theme.textTheme.bodySmall,
      child: Row(
        children: [
          Icon(saveIcon, size: 16),
          const SizedBox(width: 6),
          Flexible(child: Text(saveLabel, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Text('rev ${surfaceController.textController.revision}'),
          const SizedBox(width: 12),
          Flexible(child: Text(surfaceController.selectionLabel, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
