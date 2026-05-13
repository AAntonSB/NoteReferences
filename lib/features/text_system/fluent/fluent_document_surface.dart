import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_fragment.dart';
import '../core/text_system_document_range.dart';
import '../core/text_system_controller.dart';
import '../persistence/text_system_autosave_controller.dart';
import '../references/actions/text_system_reference_actions.dart';
import 'fluent_document_buffer_mapper.dart';
import 'fluent_document_command_controller.dart';
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
    this.showToolbar = true,
    this.showFrame = true,
    this.readOnly = false,
    this.minLines = 16,
    this.maxLines,
    this.padding = const EdgeInsets.all(20),
    this.textStyle,
    this.onBufferChanged,
    this.commandController,
    this.referenceActionRepository,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController? autosaveController;
  final String placeholder;
  final bool showStatusBar;
  final bool showToolbar;
  final bool showFrame;
  final bool readOnly;
  final int minLines;
  final int? maxLines;
  final EdgeInsetsGeometry padding;
  final TextStyle? textStyle;
  final ValueChanged<FluentDocumentEditingController>? onBufferChanged;
  final FluentDocumentCommandController? commandController;
  final TextSystemReferenceActionRepository? referenceActionRepository;

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
      if (!mounted) return;
      _publishCommandState();
      widget.onBufferChanged?.call(_editingController);
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
    if (oldWidget.commandController != widget.commandController) {
      oldWidget.commandController?.detach();
      _publishCommandState();
    } else if (oldWidget.readOnly != widget.readOnly ||
        oldWidget.referenceActionRepository != widget.referenceActionRepository) {
      _publishCommandState();
    }
  }

  @override
  void dispose() {
    widget.commandController?.detach();
    widget.textController.removeListener(_handleTextSystemChanged);
    _editingController.removeListener(_handleEditingChanged);
    _editingController.dispose();
    _focusNode.dispose();
    super.dispose();
  }


  void _publishCommandState() {
    widget.commandController?.attach(
      hasExpandedSelection: _hasExpandedSelection,
      canUndo: widget.textController.canUndo,
      canRedo: widget.textController.canRedo,
      readOnly: widget.readOnly,
      currentParagraphStyle: _currentParagraphStyle,
      onBold: () => _toggleMarkForSelection(TextMarkKind.bold),
      onItalic: () => _toggleMarkForSelection(TextMarkKind.italic),
      onUnderline: () => _toggleMarkForSelection(TextMarkKind.underline),
      onHighlight: () => _toggleMarkForSelection(TextMarkKind.highlight),
      onCode: () => _toggleMarkForSelection(TextMarkKind.code),
      onLink: widget.referenceActionRepository == null
          ? () => _toggleMarkForSelection(TextMarkKind.link)
          : () => _openReferenceActionPicker(TextSystemReferenceActionType.link),
      onAddCitation: widget.referenceActionRepository == null
          ? null
          : () => _openReferenceActionPicker(TextSystemReferenceActionType.citation),
      onLinkSource: widget.referenceActionRepository == null
          ? null
          : () => _openReferenceActionPicker(TextSystemReferenceActionType.source),
      onLinkDocument: widget.referenceActionRepository == null
          ? null
          : () => _openReferenceActionPicker(TextSystemReferenceActionType.document),
      onLinkProject: widget.referenceActionRepository == null
          ? null
          : () => _openReferenceActionPicker(TextSystemReferenceActionType.project),
      onLinkTodo: widget.referenceActionRepository == null
          ? null
          : () => _openReferenceActionPicker(TextSystemReferenceActionType.todo),
      onAddReferenceLink: widget.referenceActionRepository == null
          ? null
          : () => _openReferenceActionPicker(TextSystemReferenceActionType.link),
      onCopy: () {
        _copySelection();
      },
      onCut: () {
        _cutSelection();
      },
      onPaste: () {
        _pasteAtSelection();
      },
      onUndo: _undo,
      onRedo: _redo,
      onApplyParagraphStyle: _applyParagraphStyle,
      onJumpToBlock: _jumpToBlock,
    );
  }


  void _jumpToBlock(String blockId) {
    final document = widget.textController.document;
    final index = document.blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;

    final offset = _editingController.bufferOffsetForDocumentPosition(
      TextSystemDocumentPosition(
        blockId: document.blocks[index].id,
        blockIndex: index,
        offset: 0,
      ),
    );
    _editingController.selection = TextSelection.collapsed(offset: offset);
    _focusNode.requestFocus();
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  void _handleTextSystemChanged() {
    if (_applyingUserEdit) return;
    _editingController.syncFromDocument(widget.textController.document);
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  void _handleEditingChanged() {
    if (_editingController.isSyncingFromDocument || _applyingUserEdit) return;
    final nextDocument = _editingController.documentFromCurrentBuffer();
    if (FluentDocumentBufferMapper.equivalentDocumentShape(
      widget.textController.document,
      nextDocument,
    )) {
      _publishCommandState();
      widget.onBufferChanged?.call(_editingController);
      return;
    }

    _applyingUserEdit = true;
    widget.textController.replaceDocument(
      nextDocument,
      label: 'Edit fluent document',
    );
    _editingController.acceptDocumentFromCurrentBuffer(widget.textController.document);
    _applyingUserEdit = false;
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  bool get _hasExpandedSelection =>
      _editingController.selection.isValid && !_editingController.selection.isCollapsed;

  FluentParagraphStyle get _currentParagraphStyle {
    final selection = _editingController.selection;
    final offset = selection.isValid ? selection.baseOffset : 0;
    final segment = _editingController.buffer.segmentForOffset(offset);
    if (segment == null) return FluentParagraphStyle.paragraph;

    return switch (segment.blockType) {
      TextSystemBlockType.heading => switch (segment.level ?? 2) {
          1 => FluentParagraphStyle.heading1,
          2 => FluentParagraphStyle.heading2,
          _ => FluentParagraphStyle.heading3,
        },
      TextSystemBlockType.listItem => segment.ordered
          ? FluentParagraphStyle.numbered
          : FluentParagraphStyle.bullet,
      TextSystemBlockType.todo => FluentParagraphStyle.todo,
      TextSystemBlockType.quote => FluentParagraphStyle.quote,
      TextSystemBlockType.code => FluentParagraphStyle.code,
      _ => FluentParagraphStyle.paragraph,
    };
  }

  void _applyParagraphStyle(FluentParagraphStyle style) {
    if (widget.readOnly) return;
    final selection = _editingController.selection;
    if (!selection.isValid) return;

    final range = selection.isCollapsed
        ? TextSystemDocumentRange.collapsed(
            _editingController.documentPositionForBufferOffset(selection.baseOffset),
          )
        : _editingController.documentRangeForSelection(selection);
    if (range == null) return;

    var startIndex = range.start.blockIndex;
    var endIndex = range.end.blockIndex;
    if (!range.isCollapsed && range.end.offset == 0 && endIndex > startIndex) {
      endIndex -= 1;
    }

    final document = widget.textController.document;
    if (document.blocks.isEmpty) return;
    startIndex = startIndex.clamp(0, document.blocks.length - 1).toInt();
    endIndex = endIndex.clamp(0, document.blocks.length - 1).toInt();
    if (endIndex < startIndex) endIndex = startIndex;

    final nextBlocks = <TextSystemBlock>[
      for (var i = 0; i < document.blocks.length; i++)
        if (i >= startIndex && i <= endIndex)
          _blockWithParagraphStyle(document.blocks[i], style)
        else
          document.blocks[i],
    ];

    final renumbered = _renumberOrderedListItems(nextBlocks);
    widget.textController.replaceDocument(
      document.copyWith(blocks: renumbered, updatedAt: DateTime.now()),
      label: 'Apply ${style.label}',
    );
    _editingController.syncFromDocument(widget.textController.document);
    final cursorOffset = _editingController.bufferOffsetForDocumentPosition(
      TextSystemDocumentPosition(
        blockId: widget.textController.document.blocks[endIndex].id,
        blockIndex: endIndex,
        offset: widget.textController.document.blocks[endIndex].text.length,
      ),
    );
    _editingController.selection = TextSelection.collapsed(offset: cursorOffset);
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  TextSystemBlock _blockWithParagraphStyle(TextSystemBlock block, FluentParagraphStyle style) {
    return switch (style) {
      FluentParagraphStyle.paragraph => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.paragraph,
          text: block.text,
          marks: block.marks,
        ).normalizeMarks(),
      FluentParagraphStyle.heading1 => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.heading,
          text: block.text,
          marks: block.marks,
          level: 1,
        ).normalizeMarks(),
      FluentParagraphStyle.heading2 => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.heading,
          text: block.text,
          marks: block.marks,
          level: 2,
        ).normalizeMarks(),
      FluentParagraphStyle.heading3 => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.heading,
          text: block.text,
          marks: block.marks,
          level: 3,
        ).normalizeMarks(),
      FluentParagraphStyle.bullet => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.listItem,
          text: block.text,
          marks: block.marks,
          metadata: const <String, Object?>{},
        ).normalizeMarks(),
      FluentParagraphStyle.numbered => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.listItem,
          text: block.text,
          marks: block.marks,
          metadata: const <String, Object?>{'ordered': true},
        ).normalizeMarks(),
      FluentParagraphStyle.quote => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.quote,
          text: block.text,
          marks: block.marks,
        ).normalizeMarks(),
      FluentParagraphStyle.todo => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.todo,
          text: block.text,
          marks: block.marks,
          checked: false,
        ).normalizeMarks(),
      FluentParagraphStyle.code => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.code,
          text: block.text,
          marks: block.marks,
        ).normalizeMarks(),
    };
  }

  List<TextSystemBlock> _renumberOrderedListItems(List<TextSystemBlock> blocks) {
    var orderedIndex = 1;
    return <TextSystemBlock>[
      for (final block in blocks)
        if (block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true)
          TextSystemBlock(
            id: block.id,
            type: block.type,
            text: block.text,
            marks: block.marks,
            metadata: <String, Object?>{'ordered': true, 'index': orderedIndex++},
          ).normalizeMarks()
        else
          block,
    ];
  }

  void _toggleMarkForSelection(TextMarkKind kind) {
    if (widget.readOnly) return;
    final range = _editingController.documentRangeForSelection();
    if (range == null || range.isCollapsed) return;
    widget.textController.toggleMarkForDocumentRange(range, kind);
    _editingController.syncFromDocument(widget.textController.document);
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  Future<void> _openReferenceActionPicker(TextSystemReferenceActionType actionType) async {
    if (widget.readOnly) return;
    final repository = widget.referenceActionRepository;
    if (repository == null) return;

    final range = _editingController.documentRangeForSelection();
    final selection = _editingController.selection;
    if (range == null || range.isCollapsed || !selection.isValid || selection.isCollapsed) {
      return;
    }

    final selectedText = selection.textInside(_editingController.text).trim();
    if (selectedText.isEmpty) return;

    final result = await showTextSystemReferenceActionPicker(
      context: context,
      selectedText: selectedText,
      repository: repository,
      initialActionType: actionType,
    );
    if (!mounted || result == null) return;

    widget.textController.applyMarkForDocumentRange(
      range,
      TextMarkKind.link,
      attributes: result.inlineMark.toTextMarkAttributes(),
      label: result.actionType.verbLabel,
    );

    final previousSelection = selection;
    _editingController.syncFromDocument(widget.textController.document);
    final safeBase = previousSelection.baseOffset.clamp(0, _editingController.text.length).toInt();
    final safeExtent = previousSelection.extentOffset.clamp(0, _editingController.text.length).toInt();
    _editingController.selection = TextSelection(baseOffset: safeBase, extentOffset: safeExtent);
    _focusNode.requestFocus();
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  void _handleReferenceShortcut() {
    if (widget.referenceActionRepository == null) {
      _toggleMarkForSelection(TextMarkKind.link);
      return;
    }
    _openReferenceActionPicker(TextSystemReferenceActionType.source);
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
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  Future<void> _cutSelection() async {
    if (widget.readOnly) return;
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
    if (widget.readOnly) return;
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
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  void _undo() {
    if (widget.readOnly) return;
    widget.textController.undo();
    _editingController.syncFromDocument(widget.textController.document);
    _publishCommandState();
    widget.onBufferChanged?.call(_editingController);
  }

  void _redo() {
    if (widget.readOnly) return;
    widget.textController.redo();
    _editingController.syncFromDocument(widget.textController.document);
    _publishCommandState();
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
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _handleReferenceShortcut,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _handleReferenceShortcut,
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
        final editorContent = Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showToolbar) ...[
                _FluentSelectionToolbar(
                  enabled: _hasExpandedSelection,
                  onBold: () => _toggleMarkForSelection(TextMarkKind.bold),
                  onItalic: () => _toggleMarkForSelection(TextMarkKind.italic),
                  onUnderline: () => _toggleMarkForSelection(TextMarkKind.underline),
                  onHighlight: () => _toggleMarkForSelection(TextMarkKind.highlight),
                  onCode: () => _toggleMarkForSelection(TextMarkKind.code),
                  onLink: widget.referenceActionRepository == null
                      ? () => _toggleMarkForSelection(TextMarkKind.link)
                      : () => _openReferenceActionPicker(TextSystemReferenceActionType.link),
                  onCopy: _hasExpandedSelection
                      ? () {
                          _copySelection();
                        }
                      : null,
                  onCut: _hasExpandedSelection && !widget.readOnly
                      ? () {
                          _cutSelection();
                        }
                      : null,
                  onPaste: widget.readOnly
                      ? null
                      : () {
                          _pasteAtSelection();
                        },
                  onUndo: widget.textController.canUndo && !widget.readOnly ? _undo : null,
                  onRedo: widget.textController.canRedo && !widget.readOnly ? _redo : null,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _editingController,
                focusNode: _focusNode,
                readOnly: widget.readOnly,
                minLines: widget.minLines,
                maxLines: widget.maxLines,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                inputFormatters: const <TextInputFormatter>[
                  FluentDocumentNaturalEditingFormatter(),
                ],
                style: widget.textStyle ?? theme.textTheme.bodyLarge,
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
        );

        return CallbackShortcuts(
          bindings: _shortcuts,
          child: widget.showFrame
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? colorScheme.primary.withValues(alpha: 0.55)
                          : colorScheme.outlineVariant.withValues(alpha: 0.75),
                    ),
                  ),
                  child: editorContent,
                )
              : editorContent,
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
          tooltip: 'Reference/link (Ctrl/Cmd+K)',
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
