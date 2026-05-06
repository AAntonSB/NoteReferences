import 'package:flutter/material.dart';

import '../commands/text_system_command_registry.dart';
import '../commands/text_system_shortcut_binding.dart';
import 'text_system_keyboard_dispatcher.dart';
import 'text_system_surface_controller.dart';
import 'text_system_surface_status_bar.dart';
import 'text_system_surface_toolbar.dart';

/// Visual treatment for a reusable text-system surface.
///
/// The text system may be structured internally, but normal writing surfaces
/// should not feel like stacks of managed objects. Use [plain] inside fluent
/// document text, [subtle] for light notes/inline fields, and [outlined] for
/// explicit lab/demo cards or isolated editor panels.
enum TextSystemSurfaceFrameStyle {
  outlined,
  subtle,
  plain,
}

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
    this.frameStyle = TextSystemSurfaceFrameStyle.outlined,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;
  final Widget Function(BuildContext context, TextSystemSurfaceController controller) editorBuilder;
  final bool showToolbar;
  final bool showStatusBar;
  final bool compactToolbar;
  final EdgeInsetsGeometry padding;
  final TextSystemShortcutProfile? shortcutProfile;
  final TextSystemSurfaceFrameStyle frameStyle;

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
          child: _SurfaceFrameDecoration(
            frameStyle: frameStyle,
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
                    _QuietDivider(frameStyle: frameStyle),
                    const SizedBox(height: 10),
                  ],
                  editorBuilder(context, surfaceController),
                  if (showStatusBar) ...[
                    const SizedBox(height: 10),
                    _QuietDivider(frameStyle: frameStyle),
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

class _SurfaceFrameDecoration extends StatelessWidget {
  const _SurfaceFrameDecoration({
    required this.frameStyle,
    required this.child,
  });

  final TextSystemSurfaceFrameStyle frameStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (frameStyle == TextSystemSurfaceFrameStyle.plain) {
      return child;
    }

    final outlined = frameStyle == TextSystemSurfaceFrameStyle.outlined;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: outlined ? colorScheme.surface : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(outlined ? 18 : 14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: outlined ? 0.78 : 0.38),
        ),
      ),
      child: child,
    );
  }
}

class _QuietDivider extends StatelessWidget {
  const _QuietDivider({required this.frameStyle});

  final TextSystemSurfaceFrameStyle frameStyle;

  @override
  Widget build(BuildContext context) {
    if (frameStyle == TextSystemSurfaceFrameStyle.plain) {
      return const SizedBox.shrink();
    }
    return Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.72));
  }
}
