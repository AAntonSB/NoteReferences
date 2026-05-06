import 'package:flutter/material.dart';

import '../commands/text_system_command_registry.dart';
import '../commands/text_system_default_commands.dart';
import '../core/text_system_controller.dart';
import '../persistence/text_system_autosave_controller.dart';
import 'text_system_editable_surface_frame.dart';
import 'text_system_surface_config.dart';
import 'text_system_surface_controller.dart';

/// Lightweight multi-line note surface for the project-wide text system.
///
/// This is the surface for sidecar notes, quick notes, small project notes,
/// observations, comments, and other places where the app needs a comfortable
/// note editor without the full document/premium-writer shell.
class SimpleNoteSurface extends StatefulWidget {
  const SimpleNoteSurface({
    super.key,
    required this.textController,
    required this.blockId,
    this.autosaveController,
    this.config,
    this.title,
    this.subtitle,
    this.placeholder,
    this.showHeader = true,
    this.showToolbar = true,
    this.showStatusBar = true,
    this.enabled = true,
    this.minLines = 5,
    this.maxLines = 12,
  });

  final TextSystemController textController;
  final String blockId;
  final TextSystemAutosaveController? autosaveController;
  final TextSystemSurfaceConfig? config;
  final String? title;
  final String? subtitle;
  final String? placeholder;
  final bool showHeader;
  final bool showToolbar;
  final bool showStatusBar;
  final bool enabled;
  final int minLines;
  final int maxLines;

  @override
  State<SimpleNoteSurface> createState() => _SimpleNoteSurfaceState();
}

class _SimpleNoteSurfaceState extends State<SimpleNoteSurface> {
  late TextSystemSurfaceController _surfaceController;
  late TextSystemCommandRegistry _commandRegistry;

  TextSystemSurfaceConfig get _config => widget.config ??
      TextSystemSurfaceConfig.simpleNote(
        id: 'simple-note-${widget.blockId}',
        label: widget.title ?? 'Simple note',
      );

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant SimpleNoteSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController ||
        oldWidget.autosaveController != widget.autosaveController ||
        oldWidget.blockId != widget.blockId ||
        oldWidget.config != widget.config) {
      _surfaceController.dispose();
      _createController();
    }
  }

  void _createController() {
    _surfaceController = TextSystemSurfaceController(
      textController: widget.textController,
      autosaveController: widget.autosaveController,
      config: _config,
      blockId: widget.blockId,
    );
    _commandRegistry = TextSystemDefaultCommands.forSurface(_surfaceController);
  }

  @override
  void dispose() {
    _surfaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextSystemEditableSurfaceFrame(
      surfaceController: _surfaceController,
      commandRegistry: _commandRegistry,
      showToolbar: widget.showToolbar,
      showStatusBar: widget.showStatusBar,
      compactToolbar: true,
      padding: const EdgeInsets.all(16),
      frameStyle: TextSystemSurfaceFrameStyle.subtle,
      editorBuilder: (context, controller) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showHeader &&
                ((widget.title != null && widget.title!.isNotEmpty) ||
                    (widget.subtitle != null && widget.subtitle!.isNotEmpty))) ...[
              if (widget.title != null && widget.title!.isNotEmpty)
                Text(widget.title!, style: theme.textTheme.titleSmall),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(widget.subtitle!, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
            ],
            TextField(
              controller: controller.editingController,
              focusNode: controller.focusNode,
              enabled: widget.enabled,
              readOnly: controller.isReadOnly || !widget.enabled,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.placeholder ?? 'Write a note...',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        );
      },
    );
  }
}
