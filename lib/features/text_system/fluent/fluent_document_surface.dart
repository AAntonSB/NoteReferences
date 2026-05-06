import 'package:flutter/material.dart';

import '../core/text_system_controller.dart';
import '../persistence/text_system_autosave_controller.dart';
import 'fluent_document_buffer_mapper.dart';
import 'fluent_document_editing_controller.dart';

/// Experimental continuous document editor.
///
/// Unlike the transitional row-based document surface, this uses one Flutter
/// text editing controller for the whole visible document. That gives the user
/// one normal text selection across paragraphs while the engine maps the buffer
/// back to the structured [TextSystemDocument].
class FluentDocumentSurface extends StatefulWidget {
  const FluentDocumentSurface({
    super.key,
    required this.textController,
    this.autosaveController,
    this.placeholder = 'Start writing…',
    this.showStatusBar = true,
    this.minLines = 16,
    this.maxLines,
    this.padding = const EdgeInsets.all(20),
    this.onBufferChanged,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController? autosaveController;
  final String placeholder;
  final bool showStatusBar;
  final int minLines;
  final int? maxLines;
  final EdgeInsetsGeometry padding;
  final ValueChanged<FluentDocumentEditingController>? onBufferChanged;

  @override
  State<FluentDocumentSurface> createState() => _FluentDocumentSurfaceState();
}

class _FluentDocumentSurfaceState extends State<FluentDocumentSurface> {
  late final FocusNode _focusNode;
  late FluentDocumentEditingController _editingController;
  bool _applyingUserEdit = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'FluentDocumentSurface');
    _editingController = FluentDocumentEditingController(document: widget.textController.document);
    _editingController.addListener(_handleEditingChanged);
    widget.textController.addListener(_handleTextSystemChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBufferChanged?.call(_editingController);
    });
  }

  @override
  void didUpdateWidget(covariant FluentDocumentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_handleTextSystemChanged);
      widget.textController.addListener(_handleTextSystemChanged);
      _editingController.syncFromDocument(widget.textController.document);
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_handleTextSystemChanged);
    _editingController.removeListener(_handleEditingChanged);
    _editingController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextSystemChanged() {
    if (_applyingUserEdit) return;
    _editingController.syncFromDocument(widget.textController.document);
    widget.onBufferChanged?.call(_editingController);
  }

  void _handleEditingChanged() {
    if (_editingController.isSyncingFromDocument || _applyingUserEdit) return;
    final nextDocument = _editingController.documentFromCurrentBuffer();
    if (FluentDocumentBufferMapper.equivalentDocumentShape(
      widget.textController.document,
      nextDocument,
    )) {
      return;
    }

    _applyingUserEdit = true;
    widget.textController.replaceDocument(
      nextDocument,
      label: 'Edit fluent document',
    );
    _editingController.acceptDocumentFromCurrentBuffer(widget.textController.document);
    _applyingUserEdit = false;
    widget.onBufferChanged?.call(_editingController);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.textController,
        if (widget.autosaveController != null) widget.autosaveController!,
        _focusNode,
      ]),
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? colorScheme.primary.withValues(alpha: 0.55)
                  : colorScheme.outlineVariant.withValues(alpha: 0.75),
            ),
          ),
          child: Padding(
            padding: widget.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _editingController,
                  focusNode: _focusNode,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: widget.placeholder,
                    isCollapsed: true,
                  ),
                ),
                if (widget.showStatusBar && widget.autosaveController != null) ...[
                  const SizedBox(height: 14),
                  Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
                  const SizedBox(height: 10),
                  _FluentSurfaceStatusLine(
                    revision: widget.textController.revision,
                    saveMessage: widget.autosaveController?.saveState.message,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
class _FluentSurfaceStatusLine extends StatelessWidget {
  const _FluentSurfaceStatusLine({
    required this.revision,
    required this.saveMessage,
  });

  final int revision;
  final String? saveMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTextStyle.merge(
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(saveMessage ?? 'Local fluent editing'),
            ],
          ),
          Text('Revision $revision'),
          const Text('One continuous editor surface'),
        ],
      ),
    );
  }
}
