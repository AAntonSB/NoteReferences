import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../core/text_system_range.dart';

class TextEngineCoreLabScreen extends StatefulWidget {
  const TextEngineCoreLabScreen({super.key});

  @override
  State<TextEngineCoreLabScreen> createState() => _TextEngineCoreLabScreenState();
}

class _TextEngineCoreLabScreenState extends State<TextEngineCoreLabScreen> {
  late final TextSystemController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextSystemController(
      document: TextSystemDocument.singleParagraph(
        id: 'phase-6-core-doc',
        title: 'Phase 6 text engine core',
        text: 'This is the first project-wide text engine surface. Select text, apply bold or highlight, copy a rich fragment, paste it elsewhere, then undo and redo the transaction.',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Text engine core lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Save snapshot',
            onPressed: () => _controller.saveSnapshot(label: 'Manual core lab snapshot'),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer.withValues(alpha: 0.48),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.account_tree_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 6: reusable text engine', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This lab validates the core model before we build polished surfaces: structured text, inline marks, internal rich copy/paste, undo/redo, snapshots, and transaction logging.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _CoreTextEngineSurface(controller: _controller),
        ],
      ),
    );
  }
}

class _CoreTextEngineSurface extends StatefulWidget {
  const _CoreTextEngineSurface({required this.controller});

  final TextSystemController controller;

  @override
  State<_CoreTextEngineSurface> createState() => _CoreTextEngineSurfaceState();
}

class _CoreTextEngineSurfaceState extends State<_CoreTextEngineSurface> {
  static const String _blockId = 'paragraph-1';

  late final TextEditingController _textEditingController;
  bool _syncingFromTextEngine = false;

  @override
  void initState() {
    super.initState();
    _textEditingController = TextEditingController(text: _currentBlock.text);
    _textEditingController.addListener(_handleSelectionChanged);
    widget.controller.addListener(_syncFromTextEngine);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromTextEngine);
    _textEditingController.removeListener(_handleSelectionChanged);
    _textEditingController.dispose();
    super.dispose();
  }

  TextSystemBlock get _currentBlock =>
      widget.controller.document.blockById(_blockId) ??
      const TextSystemBlock(id: _blockId, type: TextSystemBlockType.paragraph, text: '');

  TextSystemRange? get _selectedRange {
    final selection = _textEditingController.selection;
    if (!selection.isValid || selection.isCollapsed) return null;
    final start = selection.start < selection.end ? selection.start : selection.end;
    final end = selection.start < selection.end ? selection.end : selection.start;
    return TextSystemRange(start, end).clamp(_textEditingController.text.length);
  }

  void _handleSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _syncFromTextEngine() {
    final block = _currentBlock;
    if (_textEditingController.text == block.text) {
      if (mounted) setState(() {});
      return;
    }

    _syncingFromTextEngine = true;
    final selection = _textEditingController.selection;
    _textEditingController.text = block.text;
    if (selection.isValid) {
      final safeOffset = selection.baseOffset.clamp(0, block.text.length).toInt();
      _textEditingController.selection = TextSelection.collapsed(offset: safeOffset);
    }
    _syncingFromTextEngine = false;
    if (mounted) setState(() {});
  }

  void _handleTextChanged(String text) {
    if (_syncingFromTextEngine) return;
    widget.controller.updateBlockText(_blockId, text);
  }

  void _toggleMark(TextMarkKind kind) {
    final range = _selectedRange;
    if (range == null || range.isCollapsed) return;
    widget.controller.toggleMark(_blockId, range, kind);
  }

  Future<void> _copyRichFragment() async {
    final range = _selectedRange;
    if (range == null || range.isCollapsed) return;
    final fragment = widget.controller.copyFragment(_blockId, range);
    await Clipboard.setData(ClipboardData(text: fragment.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied rich fragment: ${fragment.text.length} chars, ${fragment.marks.length} marks.',
        ),
      ),
    );
  }

  void _pasteRichFragment() {
    final selection = _textEditingController.selection;
    final offset = selection.isValid ? selection.baseOffset : _currentBlock.text.length;
    widget.controller.pasteInternalClipboard(_blockId, offset.clamp(0, _currentBlock.text.length).toInt());
  }

  void _reset() {
    widget.controller.replaceDocument(
      TextSystemDocument.singleParagraph(
        id: 'phase-6-core-doc',
        title: 'Phase 6 text engine core',
        text: 'Reset surface. Select a word, apply bold or highlight, copy it as a rich fragment, paste it after this sentence, then undo.',
      ),
      label: 'Reset core lab document',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final block = _currentBlock;
        final selectedRange = _selectedRange;
        final clipboard = widget.controller.internalClipboard;

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final editor = _EditorCard(
              textEditingController: _textEditingController,
              onChanged: _handleTextChanged,
              onToggleBold: selectedRange == null ? null : () => _toggleMark(TextMarkKind.bold),
              onToggleItalic: selectedRange == null ? null : () => _toggleMark(TextMarkKind.italic),
              onToggleHighlight: selectedRange == null
                  ? null
                  : () => _toggleMark(TextMarkKind.highlight),
              onCopyRich: selectedRange == null ? null : _copyRichFragment,
              onPasteRich: clipboard == null ? null : _pasteRichFragment,
              onUndo: widget.controller.canUndo ? widget.controller.undo : null,
              onRedo: widget.controller.canRedo ? widget.controller.redo : null,
              onReset: _reset,
              selectedRange: selectedRange,
            );

            final inspector = _InspectorCard(
              block: block,
              selectedRange: selectedRange,
              copiedText: clipboard?.text,
              copiedMarks: clipboard?.marks.length ?? 0,
              transactions: widget.controller.transactionLog.length,
              snapshots: widget.controller.snapshots.length,
              canUndo: widget.controller.canUndo,
              canRedo: widget.controller.canRedo,
            );

            if (!wide) {
              return Column(
                children: [
                  editor,
                  const SizedBox(height: 16),
                  _PreviewCard(block: block),
                  const SizedBox(height: 16),
                  inspector,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      editor,
                      const SizedBox(height: 16),
                      _PreviewCard(block: block),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: inspector),
              ],
            );
          },
        );
      },
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({
    required this.textEditingController,
    required this.onChanged,
    required this.onReset,
    this.onToggleBold,
    this.onToggleItalic,
    this.onToggleHighlight,
    this.onCopyRich,
    this.onPasteRich,
    this.onUndo,
    this.onRedo,
    this.selectedRange,
  });

  final TextEditingController textEditingController;
  final ValueChanged<String> onChanged;
  final VoidCallback? onToggleBold;
  final VoidCallback? onToggleItalic;
  final VoidCallback? onToggleHighlight;
  final VoidCallback? onCopyRich;
  final VoidCallback? onPasteRich;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onReset;
  final TextSystemRange? selectedRange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Native text-engine editor', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        selectedRange == null
                            ? 'Select text to apply marks or copy a rich fragment.'
                            : 'Selection: ${selectedRange!.start}–${selectedRange!.end}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Undo',
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Redo',
                  onPressed: onRedo,
                  icon: const Icon(Icons.redo_rounded),
                ),
                IconButton(
                  tooltip: 'Reset lab document',
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onToggleBold,
                  icon: const Icon(Icons.format_bold_rounded),
                  label: const Text('Bold'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onToggleItalic,
                  icon: const Icon(Icons.format_italic_rounded),
                  label: const Text('Italic'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onToggleHighlight,
                  icon: const Icon(Icons.border_color_rounded),
                  label: const Text('Highlight'),
                ),
                OutlinedButton.icon(
                  onPressed: onCopyRich,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy rich'),
                ),
                OutlinedButton.icon(
                  onPressed: onPasteRich,
                  icon: const Icon(Icons.content_paste_go_rounded),
                  label: const Text('Paste rich'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: textEditingController,
              minLines: 8,
              maxLines: 12,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Editable text',
                alignLabelWithHint: true,
              ),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.block});

  final TextSystemBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Structured rich preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'This is rendered from the text-system document model, not from the raw TextField widget.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                  children: _buildPreviewSpans(context, block),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _buildPreviewSpans(BuildContext context, TextSystemBlock block) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = block.text;
    if (text.isEmpty) return <TextSpan>[const TextSpan(text: 'Empty document')];

    final boundaries = <int>{0, text.length};
    for (final mark in block.marks) {
      boundaries.add(mark.range.start.clamp(0, text.length).toInt());
      boundaries.add(mark.range.end.clamp(0, text.length).toInt());
    }
    final ordered = boundaries.toList()..sort();
    final spans = <TextSpan>[];

    for (var index = 0; index < ordered.length - 1; index++) {
      final start = ordered[index];
      final end = ordered[index + 1];
      if (start == end) continue;
      final segment = TextSystemRange(start, end);
      final activeMarks = block.marks.where((mark) => mark.range.containsRange(segment));
      var style = theme.textTheme.bodyLarge?.copyWith(height: 1.55);
      for (final mark in activeMarks) {
        switch (mark.kind) {
          case TextMarkKind.bold:
            style = style?.copyWith(fontWeight: FontWeight.w700);
            break;
          case TextMarkKind.italic:
            style = style?.copyWith(fontStyle: FontStyle.italic);
            break;
          case TextMarkKind.underline:
            style = style?.copyWith(decoration: TextDecoration.underline);
            break;
          case TextMarkKind.strikethrough:
            style = style?.copyWith(decoration: TextDecoration.lineThrough);
            break;
          case TextMarkKind.highlight:
            style = style?.copyWith(
              backgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.85),
            );
            break;
          case TextMarkKind.code:
            style = style?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: colorScheme.surfaceContainerHighest,
            );
            break;
          case TextMarkKind.link:
            style = style?.copyWith(
              color: colorScheme.primary,
              decoration: TextDecoration.underline,
            );
            break;
        }
      }
      spans.add(TextSpan(text: text.substring(start, end), style: style));
    }

    return spans;
  }
}

class _InspectorCard extends StatelessWidget {
  const _InspectorCard({
    required this.block,
    required this.transactions,
    required this.snapshots,
    required this.canUndo,
    required this.canRedo,
    required this.copiedMarks,
    this.selectedRange,
    this.copiedText,
  });

  final TextSystemBlock block;
  final TextSystemRange? selectedRange;
  final String? copiedText;
  final int copiedMarks;
  final int transactions;
  final int snapshots;
  final bool canUndo;
  final bool canRedo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Engine inspector', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _InspectorRow(label: 'Text length', value: '${block.text.length} chars'),
            _InspectorRow(label: 'Marks', value: '${block.marks.length}'),
            _InspectorRow(
              label: 'Selection',
              value: selectedRange == null ? 'none' : '${selectedRange!.start}–${selectedRange!.end}',
            ),
            _InspectorRow(label: 'Transactions', value: '$transactions'),
            _InspectorRow(label: 'Snapshots', value: '$snapshots'),
            _InspectorRow(label: 'Undo/redo', value: '$canUndo / $canRedo'),
            _InspectorRow(
              label: 'Internal clipboard',
              value: copiedText == null ? 'empty' : '${copiedText!.length} chars, $copiedMarks marks',
            ),
            const SizedBox(height: 16),
            Text('Marks', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (block.marks.isEmpty)
              Text('No marks yet.', style: theme.textTheme.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mark in block.marks)
                    Chip(
                      label: Text('${mark.kind.name} ${mark.range.start}–${mark.range.end}'),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  const _InspectorRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 122,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
