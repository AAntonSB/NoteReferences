import 'package:flutter/material.dart';

import '../commands/text_system_default_commands.dart';
import '../commands/text_system_command_registry.dart';
import '../core/text_system_controller.dart';
import '../persistence/text_system_autosave_controller.dart';
import 'text_system_editable_surface_frame.dart';
import 'text_system_surface_config.dart';
import 'text_system_surface_controller.dart';

/// Smallest editable text-system surface.
///
/// Intended for todo titles, small comments, captions, side labels, and other
/// compact places where the app needs rich text behavior without a document UI.
class InlineTextSurface extends StatefulWidget {
  const InlineTextSurface({
    super.key,
    required this.textController,
    required this.blockId,
    this.autosaveController,
    this.config,
    this.placeholder,
    this.showToolbar = false,
    this.showStatusBar = false,
    this.enabled = true,
    this.maxLines = 1,
    this.onSubmitted,
  });

  final TextSystemController textController;
  final String blockId;
  final TextSystemAutosaveController? autosaveController;
  final TextSystemSurfaceConfig? config;
  final String? placeholder;
  final bool showToolbar;
  final bool showStatusBar;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;

  @override
  State<InlineTextSurface> createState() => _InlineTextSurfaceState();
}

class _InlineTextSurfaceState extends State<InlineTextSurface> {
  late TextSystemSurfaceController _surfaceController;
  late TextSystemCommandRegistry _commandRegistry;

  TextSystemSurfaceConfig get _config => widget.config ??
      TextSystemSurfaceConfig.inline(
        id: 'inline-${widget.blockId}',
        label: 'Inline text',
      );

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant InlineTextSurface oldWidget) {
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
    return TextSystemEditableSurfaceFrame(
      surfaceController: _surfaceController,
      commandRegistry: _commandRegistry,
      showToolbar: widget.showToolbar,
      showStatusBar: widget.showStatusBar,
      compactToolbar: true,
      padding: widget.showToolbar || widget.showStatusBar
          ? const EdgeInsets.all(10)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      editorBuilder: (context, controller) {
        return TextField(
          controller: controller.editingController,
          focusNode: controller.focusNode,
          enabled: widget.enabled,
          readOnly: controller.isReadOnly || !widget.enabled,
          minLines: widget.maxLines == 1 ? 1 : null,
          maxLines: widget.maxLines,
          textInputAction: widget.maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: widget.placeholder,
          ),
        );
      },
    );
  }
}
