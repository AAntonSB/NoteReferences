import 'package:flutter/material.dart';

import '../commands/text_system_command.dart';
import '../commands/text_system_command_ids.dart';
import '../commands/text_system_command_registry.dart';
import 'text_system_surface_controller.dart';

class TextSystemSurfaceToolbar extends StatelessWidget {
  const TextSystemSurfaceToolbar({
    super.key,
    required this.surfaceController,
    required this.commandRegistry,
    this.compact = false,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final commands = <String>[
      if (surfaceController.config.features.inlineFormatting) TextSystemCommandIds.bold,
      if (surfaceController.config.features.inlineFormatting) TextSystemCommandIds.italic,
      if (surfaceController.config.features.highlighting) TextSystemCommandIds.highlight,
      TextSystemCommandIds.link,
      if (surfaceController.config.features.richClipboard) TextSystemCommandIds.copyRich,
      if (surfaceController.config.features.richClipboard) TextSystemCommandIds.pasteRich,
      if (surfaceController.config.features.undoRedo) TextSystemCommandIds.undo,
      if (surfaceController.config.features.undoRedo) TextSystemCommandIds.redo,
      if (surfaceController.autosaveController != null) TextSystemCommandIds.save,
    ];

    final contextForCommands = TextSystemCommandContext(
      isEnabled: true,
      selectionLabel: surfaceController.selectionLabel,
    );

    return Wrap(
      spacing: compact ? 4 : 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final id in commands)
          if (commandRegistry.byId(id) != null)
            _ToolbarCommandButton(
              command: commandRegistry.byId(id)!,
              contextForCommand: contextForCommands,
              compact: compact,
            ),
      ],
    );
  }
}

class _ToolbarCommandButton extends StatelessWidget {
  const _ToolbarCommandButton({
    required this.command,
    required this.contextForCommand,
    required this.compact,
  });

  final TextSystemCommand command;
  final TextSystemCommandContext contextForCommand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final available = command.availableIn(contextForCommand);
    final tooltip = command.defaultShortcutLabel == null
        ? command.label
        : '${command.label} (${command.defaultShortcutLabel})';

    if (compact) {
      return IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: available ? command.execute : null,
        icon: Icon(command.icon ?? Icons.bolt_rounded),
      );
    }

    return FilledButton.tonalIcon(
      onPressed: available ? command.execute : null,
      icon: Icon(command.icon ?? Icons.bolt_rounded),
      label: Text(command.label),
    );
  }
}
