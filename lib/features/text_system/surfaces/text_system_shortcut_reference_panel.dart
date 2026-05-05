import 'package:flutter/material.dart';

import '../commands/text_system_command.dart';
import '../commands/text_system_command_registry.dart';
import '../commands/text_system_shortcut_binding.dart';

/// Small reusable reference panel that lists the active text-system shortcuts.
///
/// This is intentionally read-only. The future settings screen can reuse the
/// same shortcut profile data but add editing/rebinding controls.
class TextSystemShortcutReferencePanel extends StatelessWidget {
  const TextSystemShortcutReferencePanel({
    super.key,
    required this.commandRegistry,
    this.commandContext = const TextSystemCommandContext(isEnabled: true),
    this.shortcutProfile,
    this.compact = false,
  });

  final TextSystemCommandRegistry commandRegistry;
  final TextSystemCommandContext commandContext;
  final TextSystemShortcutProfile? shortcutProfile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = shortcutProfile ?? TextSystemShortcutProfile.defaults();
    final commands = commandRegistry.commands;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.keyboard_command_key_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(profile.label, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final command in commands)
              _ShortcutCommandRow(
                command: command,
                bindings: profile.bindingsForCommand(command.id),
                contextForCommand: commandContext,
                compact: compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutCommandRow extends StatelessWidget {
  const _ShortcutCommandRow({
    required this.command,
    required this.bindings,
    required this.contextForCommand,
    required this.compact,
  });

  final TextSystemCommand command;
  final List<TextSystemShortcutBinding> bindings;
  final TextSystemCommandContext contextForCommand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = command.availableIn(contextForCommand);
    final labels = bindings.map((binding) => binding.label).join(' / ');
    final shortcutLabel = labels.isEmpty ? command.defaultShortcutLabel ?? '—' : labels;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            command.icon ?? Icons.bolt_rounded,
            size: compact ? 18 : 20,
            color: available ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: available ? null : theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!compact)
                  Text(
                    available ? 'Available now' : 'Unavailable for the current selection/state',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  for (final part in shortcutLabel.split(' / '))
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(part, style: theme.textTheme.labelSmall),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
