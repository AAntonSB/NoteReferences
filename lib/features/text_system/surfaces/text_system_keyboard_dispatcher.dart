import 'package:flutter/widgets.dart';

import '../commands/text_system_command.dart';
import '../commands/text_system_command_registry.dart';
import '../commands/text_system_shortcut_binding.dart';
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
    this.shortcutProfile,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;
  final Widget child;
  final bool enabled;
  final TextSystemShortcutProfile? shortcutProfile;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !surfaceController.config.features.shortcuts) return child;

    final profile = shortcutProfile ?? TextSystemShortcutProfile.defaults();
    return CallbackShortcuts(
      bindings: profile.toCallbackMap(_execute),
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
