import 'package:flutter/material.dart';

import '../commands/text_system_command_registry.dart';
import '../commands/text_system_shortcut_binding.dart';
import 'text_system_keyboard_dispatcher.dart';
import 'text_system_surface_controller.dart';
import 'text_system_surface_status_bar.dart';
import 'text_system_surface_toolbar.dart';

/// Shared frame for editable text-system surfaces.
///
/// Concrete surfaces decide how the editor body looks. The frame supplies the
/// common surface chrome: command toolbar, keyboard dispatch, and save/selection
/// status. This keeps inline fields, notes, and document surfaces from drifting
/// into separate implementations.
class TextSystemEditableSurfaceFrame extends StatelessWidget {
  const TextSystemEditableSurfaceFrame({
    super.key,
    required this.surfaceController,
    required this.commandRegistry,
    required this.editorBuilder,
    this.showToolbar = true,
    this.showStatusBar = true,
    this.compactToolbar = false,
    this.padding = const EdgeInsets.all(12),
    this.shortcutProfile,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;
  final Widget Function(BuildContext context, TextSystemSurfaceController controller) editorBuilder;
  final bool showToolbar;
  final bool showStatusBar;
  final bool compactToolbar;
  final EdgeInsetsGeometry padding;
  final TextSystemShortcutProfile? shortcutProfile;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable?>[
        surfaceController,
        surfaceController.autosaveController,
      ].whereType<Listenable>().toList()),
      builder: (context, _) {
        return TextSystemKeyboardDispatcher(
          surfaceController: surfaceController,
          commandRegistry: commandRegistry,
          shortcutProfile: shortcutProfile,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showToolbar) ...[
                    TextSystemSurfaceToolbar(
                      surfaceController: surfaceController,
                      commandRegistry: commandRegistry,
                      compact: compactToolbar,
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 10),
                  ],
                  editorBuilder(context, surfaceController),
                  if (showStatusBar) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    TextSystemSurfaceStatusBar(surfaceController: surfaceController),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
