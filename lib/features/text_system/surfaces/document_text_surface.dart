import 'package:flutter/material.dart';

import '../commands/text_system_command_registry.dart';
import '../commands/text_system_default_commands.dart';
import '../core/text_system_block.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../persistence/text_system_autosave_controller.dart';
import 'text_system_editable_surface_frame.dart';
import 'text_system_surface_config.dart';
import 'text_system_surface_controller.dart';

/// Basic document-shaped surface for regular text documents and longer notes.
///
/// This is intentionally still the light text-system layer, not the future
/// premium writer. It provides document spacing, title editing, block-level
/// type controls, basic headings/lists/quotes/todos, and per-block rich text
/// editing through the shared Phase 7A infrastructure.
class DocumentTextSurface extends StatefulWidget {
  const DocumentTextSurface({
    super.key,
    required this.textController,
    this.autosaveController,
    this.config,
    this.showTitle = true,
    this.showDocumentToolbar = true,
    this.showBlockToolbars = true,
    this.showStatusBars = true,
    this.enabled = true,
    this.placeholder = 'Write here...',
    this.maxBlockLines = 12,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController? autosaveController;
  final TextSystemSurfaceConfig? config;
  final bool showTitle;
  final bool showDocumentToolbar;
  final bool showBlockToolbars;
  final bool showStatusBars;
  final bool enabled;
  final String placeholder;
  final int maxBlockLines;

  @override
  State<DocumentTextSurface> createState() => _DocumentTextSurfaceState();
}

class _DocumentTextSurfaceState extends State<DocumentTextSurface> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;

  TextSystemSurfaceConfig get _config => widget.config ??
      TextSystemSurfaceConfig.simpleDocument(
        id: 'document-${widget.textController.document.id}',
        label: widget.textController.document.title,
      );

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.textController.document.title);
    _titleFocusNode = FocusNode();
    widget.textController.addListener(_syncTitleFromDocument);
  }

  @override
  void didUpdateWidget(covariant DocumentTextSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_syncTitleFromDocument);
      widget.textController.addListener(_syncTitleFromDocument);
      _syncTitleFromDocument();
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_syncTitleFromDocument);
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  void _syncTitleFromDocument() {
    final title = widget.textController.document.title;
    if (_titleController.text != title && !_titleFocusNode.hasFocus) {
      _titleController.text = title;
    }
  }

  void _updateTitle(String title) {
    if (title == widget.textController.document.title) return;
    widget.textController.replaceDocument(
      widget.textController.document.copyWith(title: title),
      label: 'Edit document title',
    );
  }

  void _appendBlock(TextSystemBlockType type) {
    final document = widget.textController.document;
    final nextIndex = document.blocks.length + 1;
    final block = _defaultBlockFor(type, index: nextIndex);
    widget.textController.replaceDocument(
      document.copyWith(blocks: <TextSystemBlock>[...document.blocks, block]),
      label: 'Add ${_blockTypeLabel(type).toLowerCase()}',
    );
  }

  void _convertBlock(String blockId, TextSystemBlockType type, {int? level}) {
    final document = widget.textController.document;
    final blocks = <TextSystemBlock>[
      for (final block in document.blocks)
        if (block.id == blockId)
          _convertedBlock(block, type, level: level)
        else
          block,
    ];

    widget.textController.replaceDocument(
      document.copyWith(blocks: _renumberOrderedListBlocks(blocks)),
      label: 'Convert block to ${_blockTypeLabel(type).toLowerCase()}',
    );
  }

  void _removeBlock(String blockId) {
    final document = widget.textController.document;
    if (document.blocks.length <= 1) return;
    widget.textController.replaceDocument(
      document.copyWith(
        blocks: _renumberOrderedListBlocks(
          document.blocks.where((block) => block.id != blockId).toList(),
        ),
      ),
      label: 'Remove document block',
    );
  }

  void _moveBlock(String blockId, int delta) {
    final document = widget.textController.document;
    final index = document.blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= document.blocks.length) return;

    final blocks = [...document.blocks];
    final block = blocks.removeAt(index);
    blocks.insert(nextIndex, block);
    widget.textController.replaceDocument(
      document.copyWith(blocks: _renumberOrderedListBlocks(blocks)),
      label: delta < 0 ? 'Move block up' : 'Move block down',
    );
  }

  TextSystemBlock _defaultBlockFor(TextSystemBlockType type, {required int index}) {
    final id = 'doc-block-${DateTime.now().microsecondsSinceEpoch}-$index';
    return switch (type) {
      TextSystemBlockType.heading => TextSystemBlock(
          id: id,
          type: TextSystemBlockType.heading,
          level: 2,
          text: 'New heading',
        ),
      TextSystemBlockType.listItem => TextSystemBlock(
          id: id,
          type: TextSystemBlockType.listItem,
          text: 'New list item',
          metadata: const <String, Object?>{'ordered': false},
        ),
      TextSystemBlockType.todo => TextSystemBlock(
          id: id,
          type: TextSystemBlockType.todo,
          text: 'New task',
          checked: false,
        ),
      TextSystemBlockType.quote => TextSystemBlock(
          id: id,
          type: TextSystemBlockType.quote,
          text: 'New quote',
        ),
      _ => TextSystemBlock.paragraph(id: id, text: ''),
    };
  }

  TextSystemBlock _convertedBlock(TextSystemBlock block, TextSystemBlockType type, {int? level}) {
    return switch (type) {
      TextSystemBlockType.heading => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.heading,
          text: block.text,
          marks: block.marks,
          level: level ?? 2,
        ),
      TextSystemBlockType.listItem => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.listItem,
          text: block.text,
          marks: block.marks,
          metadata: <String, Object?>{'ordered': level == -1},
        ),
      TextSystemBlockType.todo => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.todo,
          text: block.text,
          marks: block.marks,
          checked: block.checked ?? false,
        ),
      TextSystemBlockType.quote => TextSystemBlock(
          id: block.id,
          type: TextSystemBlockType.quote,
          text: block.text,
          marks: block.marks,
        ),
      _ => TextSystemBlock.paragraph(
          id: block.id,
          text: block.text,
          marks: block.marks,
        ),
    };
  }

  List<TextSystemBlock> _renumberOrderedListBlocks(List<TextSystemBlock> blocks) {
    var orderedIndex = 1;
    return <TextSystemBlock>[
      for (final block in blocks)
        if (block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true)
          block.copyWith(
            metadata: <String, Object?>{
              ...block.metadata,
              'index': orderedIndex++,
            },
          )
        else
          block,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable?>[
        widget.textController,
        widget.autosaveController,
      ].whereType<Listenable>().toList()),
      builder: (context, _) {
        final document = widget.textController.document;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showTitle) ...[
                  TextField(
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    enabled: widget.enabled,
                    textInputAction: TextInputAction.done,
                    onChanged: _updateTitle,
                    style: theme.textTheme.headlineSmall,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Untitled document',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 14),
                ],
                if (widget.showDocumentToolbar) ...[
                  _DocumentToolbar(
                    onAddParagraph: () => _appendBlock(TextSystemBlockType.paragraph),
                    onAddHeading: () => _appendBlock(TextSystemBlockType.heading),
                    onAddListItem: () => _appendBlock(TextSystemBlockType.listItem),
                    onAddTodo: () => _appendBlock(TextSystemBlockType.todo),
                    onSave: widget.autosaveController == null
                        ? null
                        : () => widget.autosaveController!.saveNow(
                              message: 'Manually saved document surface.',
                            ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (document.blocks.isEmpty)
                  _EmptyDocumentCard(onAddParagraph: () => _appendBlock(TextSystemBlockType.paragraph))
                else
                  for (final block in document.blocks)
                    Padding(
                      key: ValueKey<String>('document-surface-${block.id}'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DocumentBlockEditor(
                        block: block,
                        textController: widget.textController,
                        autosaveController: widget.autosaveController,
                        config: _config,
                        enabled: widget.enabled,
                        placeholder: widget.placeholder,
                        showBlockToolbar: widget.showBlockToolbars,
                        showStatusBar: widget.showStatusBars,
                        maxLines: widget.maxBlockLines,
                        onParagraph: () => _convertBlock(block.id, TextSystemBlockType.paragraph),
                        onHeading1: () => _convertBlock(block.id, TextSystemBlockType.heading, level: 1),
                        onHeading2: () => _convertBlock(block.id, TextSystemBlockType.heading, level: 2),
                        onHeading3: () => _convertBlock(block.id, TextSystemBlockType.heading, level: 3),
                        onBullet: () => _convertBlock(block.id, TextSystemBlockType.listItem),
                        onNumbered: () => _convertBlock(block.id, TextSystemBlockType.listItem, level: -1),
                        onQuote: () => _convertBlock(block.id, TextSystemBlockType.quote),
                        onTodo: () => _convertBlock(block.id, TextSystemBlockType.todo),
                        onMoveUp: () => _moveBlock(block.id, -1),
                        onMoveDown: () => _moveBlock(block.id, 1),
                        onRemove: document.blocks.length <= 1 ? null : () => _removeBlock(block.id),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DocumentToolbar extends StatelessWidget {
  const _DocumentToolbar({
    required this.onAddParagraph,
    required this.onAddHeading,
    required this.onAddListItem,
    required this.onAddTodo,
    this.onSave,
  });

  final VoidCallback onAddParagraph;
  final VoidCallback onAddHeading;
  final VoidCallback onAddListItem;
  final VoidCallback onAddTodo;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: onAddParagraph,
          icon: const Icon(Icons.short_text_rounded),
          label: const Text('Paragraph'),
        ),
        FilledButton.tonalIcon(
          onPressed: onAddHeading,
          icon: const Icon(Icons.title_rounded),
          label: const Text('Heading'),
        ),
        FilledButton.tonalIcon(
          onPressed: onAddListItem,
          icon: const Icon(Icons.format_list_bulleted_rounded),
          label: const Text('List item'),
        ),
        FilledButton.tonalIcon(
          onPressed: onAddTodo,
          icon: const Icon(Icons.check_box_outlined),
          label: const Text('Todo'),
        ),
        if (onSave != null)
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save'),
          ),
      ],
    );
  }
}

class _DocumentBlockEditor extends StatefulWidget {
  const _DocumentBlockEditor({
    required this.block,
    required this.textController,
    required this.config,
    this.autosaveController,
    required this.enabled,
    required this.placeholder,
    required this.showBlockToolbar,
    required this.showStatusBar,
    required this.maxLines,
    required this.onParagraph,
    required this.onHeading1,
    required this.onHeading2,
    required this.onHeading3,
    required this.onBullet,
    required this.onNumbered,
    required this.onQuote,
    required this.onTodo,
    required this.onMoveUp,
    required this.onMoveDown,
    this.onRemove,
  });

  final TextSystemBlock block;
  final TextSystemController textController;
  final TextSystemAutosaveController? autosaveController;
  final TextSystemSurfaceConfig config;
  final bool enabled;
  final String placeholder;
  final bool showBlockToolbar;
  final bool showStatusBar;
  final int maxLines;
  final VoidCallback onParagraph;
  final VoidCallback onHeading1;
  final VoidCallback onHeading2;
  final VoidCallback onHeading3;
  final VoidCallback onBullet;
  final VoidCallback onNumbered;
  final VoidCallback onQuote;
  final VoidCallback onTodo;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback? onRemove;

  @override
  State<_DocumentBlockEditor> createState() => _DocumentBlockEditorState();
}

class _DocumentBlockEditorState extends State<_DocumentBlockEditor> {
  late TextSystemSurfaceController _surfaceController;
  late TextSystemCommandRegistry _commandRegistry;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant _DocumentBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController ||
        oldWidget.autosaveController != widget.autosaveController ||
        oldWidget.block.id != widget.block.id) {
      _surfaceController.dispose();
      _createController();
    }
  }

  @override
  void dispose() {
    _surfaceController.dispose();
    super.dispose();
  }

  void _createController() {
    _surfaceController = TextSystemSurfaceController(
      textController: widget.textController,
      autosaveController: widget.autosaveController,
      config: widget.config,
      blockId: widget.block.id,
    );
    _commandRegistry = TextSystemDefaultCommands.forSurface(_surfaceController);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextSystemEditableSurfaceFrame(
      surfaceController: _surfaceController,
      commandRegistry: _commandRegistry,
      showToolbar: true,
      showStatusBar: widget.showStatusBar,
      compactToolbar: true,
      padding: const EdgeInsets.all(12),
      editorBuilder: (context, controller) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showBlockToolbar) ...[
              _BlockTypeToolbar(
                block: widget.block,
                onParagraph: widget.onParagraph,
                onHeading1: widget.onHeading1,
                onHeading2: widget.onHeading2,
                onHeading3: widget.onHeading3,
                onBullet: widget.onBullet,
                onNumbered: widget.onNumbered,
                onQuote: widget.onQuote,
                onTodo: widget.onTodo,
                onMoveUp: widget.onMoveUp,
                onMoveDown: widget.onMoveDown,
                onRemove: widget.onRemove,
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: controller.editingController,
              focusNode: controller.focusNode,
              enabled: widget.enabled,
              readOnly: controller.isReadOnly || !widget.enabled,
              minLines: _minLinesFor(widget.block),
              maxLines: widget.maxLines,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              style: _textStyleFor(theme, widget.block),
              decoration: InputDecoration(
                prefixIcon: _prefixFor(widget.block, theme),
                hintText: widget.placeholder,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.4),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ],
        );
      },
    );
  }

  static int _minLinesFor(TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.heading => 1,
      TextSystemBlockType.listItem => 1,
      TextSystemBlockType.todo => 1,
      _ => 2,
    };
  }

  static TextStyle? _textStyleFor(ThemeData theme, TextSystemBlock block) {
    return switch (block.type) {
      TextSystemBlockType.heading => switch (block.level ?? 2) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          _ => theme.textTheme.titleMedium,
        },
      TextSystemBlockType.quote => theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
      _ => theme.textTheme.bodyLarge,
    };
  }

  static Widget? _prefixFor(TextSystemBlock block, ThemeData theme) {
    if (block.type == TextSystemBlockType.listItem) {
      final ordered = block.metadata['ordered'] == true;
      final index = block.metadata['index'];
      return SizedBox(
        width: 42,
        child: Center(
          child: Text(
            ordered ? '${index is int ? index : 1}.' : '•',
            style: theme.textTheme.titleMedium,
          ),
        ),
      );
    }
    if (block.type == TextSystemBlockType.todo) {
      return Icon(
        block.checked == true ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
      );
    }
    if (block.type == TextSystemBlockType.quote) {
      return const Icon(Icons.format_quote_rounded);
    }
    return null;
  }
}

class _BlockTypeToolbar extends StatelessWidget {
  const _BlockTypeToolbar({
    required this.block,
    required this.onParagraph,
    required this.onHeading1,
    required this.onHeading2,
    required this.onHeading3,
    required this.onBullet,
    required this.onNumbered,
    required this.onQuote,
    required this.onTodo,
    required this.onMoveUp,
    required this.onMoveDown,
    this.onRemove,
  });

  final TextSystemBlock block;
  final VoidCallback onParagraph;
  final VoidCallback onHeading1;
  final VoidCallback onHeading2;
  final VoidCallback onHeading3;
  final VoidCallback onBullet;
  final VoidCallback onNumbered;
  final VoidCallback onQuote;
  final VoidCallback onTodo;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _MiniBlockButton(
          label: 'P',
          tooltip: 'Paragraph',
          selected: block.type == TextSystemBlockType.paragraph,
          onPressed: onParagraph,
        ),
        _MiniBlockButton(
          label: 'H1',
          tooltip: 'Heading 1',
          selected: block.type == TextSystemBlockType.heading && block.level == 1,
          onPressed: onHeading1,
        ),
        _MiniBlockButton(
          label: 'H2',
          tooltip: 'Heading 2',
          selected: block.type == TextSystemBlockType.heading && (block.level ?? 2) == 2,
          onPressed: onHeading2,
        ),
        _MiniBlockButton(
          label: 'H3',
          tooltip: 'Heading 3',
          selected: block.type == TextSystemBlockType.heading && block.level == 3,
          onPressed: onHeading3,
        ),
        _MiniIconBlockButton(
          icon: Icons.format_list_bulleted_rounded,
          tooltip: 'Bullet list item',
          selected: block.type == TextSystemBlockType.listItem && block.metadata['ordered'] != true,
          onPressed: onBullet,
        ),
        _MiniIconBlockButton(
          icon: Icons.format_list_numbered_rounded,
          tooltip: 'Numbered list item',
          selected: block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true,
          onPressed: onNumbered,
        ),
        _MiniIconBlockButton(
          icon: Icons.format_quote_rounded,
          tooltip: 'Quote',
          selected: block.type == TextSystemBlockType.quote,
          onPressed: onQuote,
        ),
        _MiniIconBlockButton(
          icon: Icons.check_box_outlined,
          tooltip: 'Todo',
          selected: block.type == TextSystemBlockType.todo,
          onPressed: onTodo,
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          tooltip: 'Move up',
          onPressed: onMoveUp,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Move down',
          onPressed: onMoveDown,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Remove block',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _MiniBlockButton extends StatelessWidget {
  const _MiniBlockButton({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    final button = selected
        ? FilledButton.tonal(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
    return Tooltip(message: tooltip, child: button);
  }
}

class _MiniIconBlockButton extends StatelessWidget {
  const _MiniIconBlockButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? IconButton.filledTonal(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon))
        : IconButton.outlined(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
  }
}

class _EmptyDocumentCard extends StatelessWidget {
  const _EmptyDocumentCard({required this.onAddParagraph});

  final VoidCallback onAddParagraph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          const Icon(Icons.article_outlined),
          const SizedBox(height: 8),
          Text('No blocks yet.', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onAddParagraph,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add first paragraph'),
          ),
        ],
      ),
    );
  }
}

String _blockTypeLabel(TextSystemBlockType type) {
  return switch (type) {
    TextSystemBlockType.heading => 'Heading',
    TextSystemBlockType.listItem => 'List item',
    TextSystemBlockType.todo => 'Todo',
    TextSystemBlockType.quote => 'Quote',
    TextSystemBlockType.code => 'Code',
    TextSystemBlockType.divider => 'Divider',
    TextSystemBlockType.custom => 'Custom block',
    TextSystemBlockType.paragraph => 'Paragraph',
  };
}
