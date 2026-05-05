import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../commands/text_system_command.dart';
import '../commands/text_system_command_ids.dart';
import '../commands/text_system_command_registry.dart';
import 'text_system_surface_controller.dart';

/// Shared keyboard shortcut dispatcher for all text-system surfaces.
///
/// Phase 7A keeps this small but important: shortcuts dispatch stable command
/// ids through the command registry instead of being hardcoded separately in
/// every text field, note, or document widget.
class TextSystemKeyboardDispatcher extends StatelessWidget {
  const TextSystemKeyboardDispatcher({
    super.key,
    required this.surfaceController,
    required this.commandRegistry,
    required this.child,
    this.enabled = true,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !surfaceController.config.features.shortcuts) return child;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _execute(TextSystemCommandIds.bold),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _execute(TextSystemCommandIds.bold),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _execute(TextSystemCommandIds.italic),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _execute(TextSystemCommandIds.italic),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true, shift: true): () => _execute(TextSystemCommandIds.highlight),
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true): () => _execute(TextSystemCommandIds.highlight),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _execute(TextSystemCommandIds.link),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _execute(TextSystemCommandIds.link),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => _execute(TextSystemCommandIds.undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () => _execute(TextSystemCommandIds.undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => _execute(TextSystemCommandIds.redo),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): () => _execute(TextSystemCommandIds.redo),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => _execute(TextSystemCommandIds.redo),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _execute(TextSystemCommandIds.save),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => _execute(TextSystemCommandIds.save),
      },
      child: child,
    );
  }

  void _execute(String commandId) {
    commandRegistry.execute(
      commandId,
      TextSystemCommandContext(
        isEnabled: true,
        selectionLabel: surfaceController.selectionLabel,
      ),
    );
  }
}
