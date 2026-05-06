import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/text_mark.dart';
import '../core/text_system_document_fragment.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_controller.dart';
import '../persistence/text_system_autosave_controller.dart';
import 'fluent_document_buffer_mapper.dart';
import 'fluent_document_editing_controller.dart';
import 'fluent_document_natural_editing_formatter.dart';

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
  String? _lastStructuredClipboardPlainText;

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

  bool get _hasExpandedSelection =>
      _editingController.selection.isValid && !_editingController.selection.isCollapsed;

  void _toggleMarkForSelection(TextMarkKind kind) {
    final range = _editingController.documentRangeForSelection();
    if (range == null || range.isCollapsed) return;
    widget.textController.toggleMarkForDocumentRange(range, kind);
    _editingController.syncFromDocument(widget.textController.document);
    widget.onBufferChanged?.call(_editingController);
  }

  TextSystemDocumentRange? _rangeForCurrentSelection({bool allowCollapsed = true}) {
    final selection = _editingController.selection;
    if (!selection.isValid) return null;
    if (selection.isCollapsed) {
      if (!allowCollapsed) return null;
      final position = _editingController.documentPositionForBufferOffset(selection.baseOffset);
      return TextSystemDocumentRange.collapsed(position);
    }
    return _editingController.documentRangeForSelection(selection);
  }

  Future<void> _copySelection() async {
    final range = _rangeForCurrentSelection(allowCollapsed: false);
    if (range == null || range.isCollapsed) return;

    final fragment = widget.textController.copyDocumentFragment(range);
    final selection = _editingController.selection;
    final selectedVisibleText = selection.isValid && !selection.isCollapsed
        ? selection.textInside(_editingController.text)
        : fragment.plainText;

    await Clipboard.setData(ClipboardData(text: selectedVisibleText));
    _lastStructuredClipboardPlainText = selectedVisibleText;
    widget.onBufferChanged?.call(_editingController);
  }

  Future<void> _cutSelection() async {
    final range = _rangeForCurrentSelection(allowCollapsed: false);
    if (range == null || range.isCollapsed) return;

    await _copySelection();
    final result = widget.textController.replaceDocumentRangeWithFragment(
      range,
      TextSystemDocumentFragment.empty(),
      label: 'Cut fluent selection',
    );
    _syncAfterStructuredEdit(result.insertedRange);
  }

  Future<void> _pasteAtSelection() async {
    final range = _rangeForCurrentSelection();
    if (range == null) return;

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final plainText = clipboardData?.text;
    final documentClipboard = widget.textController.internalDocumentClipboard;
    final matchesLastStructuredCopy = _lastStructuredClipboardPlainText != null &&
        plainText == _lastStructuredClipboardPlainText;
    final matchesFlatDocumentClipboard = documentClipboard != null &&
        plainText == documentClipboard.plainText;
    final canUseStructuredClipboard = documentClipboard != null &&
        !documentClipboard.isEmpty &&
        (plainText == null || matchesLastStructuredCopy || matchesFlatDocumentClipboard);

    if (canUseStructuredClipboard) {
      final result = widget.textController.replaceDocumentRangeWithFragment(
        range,
        documentClipboard,
        label: 'Paste fluent structured selection',
      );
      _syncAfterStructuredEdit(result.insertedRange);
      return;
    }

    if (plainText == null || plainText.isEmpty) return;

    final result = widget.textController.replaceDocumentRangeWithFragment(
      range,
      TextSystemDocumentFragment.fromPlainText(plainText, idPrefix: 'fluent-plain-paste'),
      label: 'Paste fluent plain text',
    );
    _syncAfterStructuredEdit(result.insertedRange);
  }

  void _syncAfterStructuredEdit(TextSystemDocumentRange insertedRange) {
    _editingController.syncFromDocument(widget.textController.document);
    final cursorOffset = _editingController.bufferOffsetForDocumentPosition(insertedRange.end);
    _editingController.selection = TextSelection.collapsed(offset: cursorOffset);
    widget.onBufferChanged?.call(_editingController);
  }

  void _undo() {
    widget.textController.undo();
    _editingController.syncFromDocument(widget.textController.document);
    widget.onBufferChanged?.call(_editingController);
  }

  void _redo() {
    widget.textController.redo();
    _editingController.syncFromDocument(widget.textController.document);
    widget.onBufferChanged?.call(_editingController);
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _toggleMarkForSelection(TextMarkKind.bold),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _toggleMarkForSelection(TextMarkKind.bold),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _toggleMarkForSelection(TextMarkKind.italic),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _toggleMarkForSelection(TextMarkKind.italic),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _toggleMarkForSelection(TextMarkKind.underline),
        const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _toggleMarkForSelection(TextMarkKind.underline),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true, shift: true): () => _toggleMarkForSelection(TextMarkKind.highlight),
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true): () => _toggleMarkForSelection(TextMarkKind.highlight),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _toggleMarkForSelection(TextMarkKind.link),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _toggleMarkForSelection(TextMarkKind.link),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () { _copySelection(); },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () { _copySelection(); },
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () { _cutSelection(); },
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () { _cutSelection(); },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () { _pasteAtSelection(); },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () { _pasteAtSelection(); },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): _redo,
      };

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
        return CallbackShortcuts(
          bindings: _shortcuts,
          child: DecoratedBox(
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
                  _FluentSelectionToolbar(
                    enabled: _hasExpandedSelection,
                    onBold: () => _toggleMarkForSelection(TextMarkKind.bold),
                    onItalic: () => _toggleMarkForSelection(TextMarkKind.italic),
                    onUnderline: () => _toggleMarkForSelection(TextMarkKind.underline),
                    onHighlight: () => _toggleMarkForSelection(TextMarkKind.highlight),
                    onCode: () => _toggleMarkForSelection(TextMarkKind.code),
                    onLink: () => _toggleMarkForSelection(TextMarkKind.link),
                    onCopy: _hasExpandedSelection ? () { _copySelection(); } : null,
                    onCut: _hasExpandedSelection ? () { _cutSelection(); } : null,
                    onPaste: () { _pasteAtSelection(); },
                    onUndo: widget.textController.canUndo ? _undo : null,
                    onRedo: widget.textController.canRedo ? _redo : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                  controller: _editingController,
                  focusNode: _focusNode,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  inputFormatters: const <TextInputFormatter>[
                    FluentDocumentNaturalEditingFormatter(),
                  ],
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

class _FluentSelectionToolbar extends StatelessWidget {
  const _FluentSelectionToolbar({
    required this.enabled,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onHighlight,
    required this.onCode,
    required this.onLink,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.onUndo,
    required this.onRedo,
  });

  final bool enabled;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onHighlight;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          enabled ? 'Format selection' : 'Select text to format',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        _ToolbarIconButton(
          tooltip: 'Bold (Ctrl/Cmd+B)',
          icon: Icons.format_bold_rounded,
          onPressed: enabled ? onBold : null,
        ),
        _ToolbarIconButton(
          tooltip: 'Italic (Ctrl/Cmd+I)',
          icon: Icons.format_italic_rounded,
          onPressed: enabled ? onItalic : null,
        ),
        _ToolbarIconButton(
          tooltip: 'Underline (Ctrl/Cmd+U)',
          icon: Icons.format_underlined_rounded,
          onPressed: enabled ? onUnderline : null,
        ),
        _ToolbarIconButton(
          tooltip: 'Highlight (Ctrl/Cmd+Shift+H)',
          icon: Icons.border_color_rounded,
          onPressed: enabled ? onHighlight : null,
        ),
        _ToolbarIconButton(
          tooltip: 'Inline code',
          icon: Icons.code_rounded,
          onPressed: enabled ? onCode : null,
        ),
        _ToolbarIconButton(
          tooltip: 'Link marker (Ctrl/Cmd+K)',
          icon: Icons.link_rounded,
          onPressed: enabled ? onLink : null,
        ),
        const SizedBox(width: 6),
        _ToolbarIconButton(
          tooltip: 'Copy structured selection (Ctrl/Cmd+C)',
          icon: Icons.copy_rounded,
          onPressed: onCopy,
        ),
        _ToolbarIconButton(
          tooltip: 'Cut structured selection (Ctrl/Cmd+X)',
          icon: Icons.content_cut_rounded,
          onPressed: onCut,
        ),
        _ToolbarIconButton(
          tooltip: 'Paste structured/plain text (Ctrl/Cmd+V)',
          icon: Icons.content_paste_rounded,
          onPressed: onPaste,
        ),
        const SizedBox(width: 6),
        _ToolbarIconButton(
          tooltip: 'Undo',
          icon: Icons.undo_rounded,
          onPressed: onUndo,
        ),
        _ToolbarIconButton(
          tooltip: 'Redo',
          icon: Icons.redo_rounded,
          onPressed: onRedo,
        ),
      ],
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
