import 'package:flutter/material.dart';

import '../text_system.dart';

class TextSystemStructuredClipboardLabScreen extends StatefulWidget {
  const TextSystemStructuredClipboardLabScreen({super.key});

  @override
  State<TextSystemStructuredClipboardLabScreen> createState() => _TextSystemStructuredClipboardLabScreenState();
}

class _TextSystemStructuredClipboardLabScreenState extends State<TextSystemStructuredClipboardLabScreen> {
  late final TextSystemController _textController;
  int _copyStart = 18;
  int _copyEnd = 148;
  int _pasteOffset = 233;
  TextSystemDocumentFragmentEditResult? _lastPaste;

  @override
  void initState() {
    super.initState();
    _textController = TextSystemController(document: _buildDocument());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  TextSystemDocument _buildDocument() {
    return TextSystemDocument(
      id: 'phase-8d-structured-clipboard-doc',
      title: 'Phase 8D structured copy/paste foundation',
      blocks: <TextSystemBlock>[
        const TextSystemBlock(
          id: 'clipboard-heading',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'Fluent text can move safely',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 11)),
          ],
        ),
        TextSystemBlock.paragraph(
          id: 'clipboard-paragraph-1',
          text:
              'Copy a document-level range that crosses this paragraph, the list below, and part of the final paragraph. Marks should survive as structured text.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(7, 27)),
            TextMark(kind: TextMarkKind.italic, range: TextSystemRange(92, 104)),
          ],
        ),
        const TextSystemBlock(
          id: 'clipboard-bullet-1',
          type: TextSystemBlockType.listItem,
          text: 'Bold text should stay bold after structured paste.',
          metadata: <String, Object?>{'ordered': false},
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 9)),
          ],
        ),
        const TextSystemBlock(
          id: 'clipboard-bullet-2',
          type: TextSystemBlockType.listItem,
          text: 'Highlighted choices should also stay visible.',
          metadata: <String, Object?>{'ordered': false},
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(0, 19)),
          ],
        ),
        TextSystemBlock.paragraph(
          id: 'clipboard-paragraph-2',
          text:
              'Paste the copied fragment into this paragraph. The operation should use fluent document offsets, while the engine updates internal text units.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.underline, range: TextSystemRange(0, 5)),
            TextMark(kind: TextMarkKind.code, range: TextSystemRange(93, 110)),
          ],
        ),
      ],
      metadata: const <String, Object?>{'phase': '8D'},
    );
  }

  void _reset() {
    setState(() {
      _copyStart = 18;
      _copyEnd = 148;
      _pasteOffset = 233;
      _lastPaste = null;
    });
    _textController.replaceDocument(
      _buildDocument(),
      label: 'Reset Phase 8D lab',
    );
  }

  void _copyRange() {
    final fragment = _textController.copyDocumentFragmentByOffsets(_copyStart, _copyEnd);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${fragment.blockCount} structured text units.')),
    );
  }

  void _pasteAtOffset() {
    final position = TextSystemDocumentSelectionMapper.positionForOffset(_textController.document, _pasteOffset);
    final result = _textController.pasteDocumentClipboardAtPosition(position);
    setState(() => _lastPaste = result);
    if (result.insertedPlainText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to paste. Copy a range first.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pasted ${result.insertedPlainText.length} characters as structured text.')),
    );
  }

  void _replaceRangeWithClipboard() {
    final range = TextSystemDocumentSelectionMapper.rangeFromOffsets(_textController.document, _copyStart, _copyEnd);
    final result = _textController.pasteDocumentClipboardAtRange(range);
    setState(() => _lastPaste = result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: _textController,
      builder: (context, _) {
        final document = _textController.document;
        final length = TextSystemDocumentSelectionMapper.documentLength(document);
        final copyRange = TextSystemDocumentSelectionMapper.rangeFromOffsets(document, _copyStart, _copyEnd);
        final copyOffsets = TextSystemDocumentSelectionMapper.offsetRangeForRange(document, copyRange);
        final copiedPreview = TextSystemDocumentSelectionMapper.plainTextForRange(document, copyRange);
        final copiedFragment = _textController.internalDocumentClipboard;

        return Scaffold(
          backgroundColor: colorScheme.surfaceContainerLowest,
          appBar: AppBar(
            title: const Text('Structured copy/paste lab'),
            centerTitle: false,
            backgroundColor: colorScheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Reset demo',
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              IconButton(
                tooltip: 'Undo',
                onPressed: _textController.canUndo ? _textController.undo : null,
                icon: const Icon(Icons.undo_rounded),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: _textController.canRedo ? _textController.redo : null,
                icon: const Icon(Icons.redo_rounded),
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
                      Icon(Icons.content_paste_go_rounded, color: colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Phase 8D: cross-paragraph structured copy/paste', style: theme.textTheme.titleLarge),
                            const SizedBox(height: 6),
                            Text(
                              'This validates internal document-fragment copy/paste. The user model remains fluent text; the engine maps ranges across paragraphs, lists, and headings into structured fragments underneath.',
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1120;
                  final preview = _DocumentCard(textController: _textController);
                  final controls = _ClipboardControlsCard(
                    totalLength: length,
                    copyStart: _copyStart,
                    copyEnd: _copyEnd,
                    pasteOffset: _pasteOffset,
                    copiedPreview: copiedPreview,
                    copiedFragment: copiedFragment,
                    copyDescription: TextSystemDocumentSelectionMapper.describeRange(document, copyRange),
                    copyLength: copyOffsets.length,
                    onCopyStartChanged: (value) => setState(() => _copyStart = value),
                    onCopyEndChanged: (value) => setState(() => _copyEnd = value),
                    onPasteOffsetChanged: (value) => setState(() => _pasteOffset = value),
                    onCopy: copyOffsets.isCollapsed ? null : _copyRange,
                    onPaste: _pasteAtOffset,
                    onReplace: copiedFragment == null || copiedFragment.isEmpty ? null : _replaceRangeWithClipboard,
                  );

                  if (!wide) {
                    return Column(
                      children: [
                        preview,
                        const SizedBox(height: 16),
                        controls,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: preview),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: controls),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _ResultCard(
                textController: _textController,
                lastPaste: _lastPaste,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.textController});

  final TextSystemController textController;

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
            Text('Document preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ReadOnlyTextSurface(
              textController: textController,
              showTitle: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipboardControlsCard extends StatelessWidget {
  const _ClipboardControlsCard({
    required this.totalLength,
    required this.copyStart,
    required this.copyEnd,
    required this.pasteOffset,
    required this.copiedPreview,
    required this.copyDescription,
    required this.copyLength,
    required this.onCopyStartChanged,
    required this.onCopyEndChanged,
    required this.onPasteOffsetChanged,
    required this.onCopy,
    required this.onPaste,
    required this.onReplace,
    this.copiedFragment,
  });

  final int totalLength;
  final int copyStart;
  final int copyEnd;
  final int pasteOffset;
  final String copiedPreview;
  final String copyDescription;
  final int copyLength;
  final ValueChanged<int> onCopyStartChanged;
  final ValueChanged<int> onCopyEndChanged;
  final ValueChanged<int> onPasteOffsetChanged;
  final VoidCallback? onCopy;
  final VoidCallback onPaste;
  final VoidCallback? onReplace;
  final TextSystemDocumentFragment? copiedFragment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeTotal = totalLength == 0 ? 1 : totalLength;
    final normalizedStart = copyStart.clamp(0, totalLength).toInt();
    final normalizedEnd = copyEnd.clamp(0, totalLength).toInt();
    final normalizedPaste = pasteOffset.clamp(0, totalLength).toInt();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Structured clipboard controls', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Use offsets to simulate a future fluent selection that can span multiple internal text units.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _SliderField(
              label: 'Copy start: $normalizedStart',
              value: normalizedStart,
              max: safeTotal,
              onChanged: onCopyStartChanged,
            ),
            _SliderField(
              label: 'Copy end: $normalizedEnd',
              value: normalizedEnd,
              max: safeTotal,
              onChanged: onCopyEndChanged,
            ),
            _SliderField(
              label: 'Paste offset: $normalizedPaste',
              value: normalizedPaste,
              max: safeTotal,
              onChanged: onPasteOffsetChanged,
            ),
            const SizedBox(height: 10),
            Text(copyDescription, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('Selected $copyLength characters', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(copiedPreview.isEmpty ? 'No selected text.' : copiedPreview),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy range'),
                ),
                OutlinedButton.icon(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste_go_rounded),
                  label: const Text('Paste at offset'),
                ),
                OutlinedButton.icon(
                  onPressed: onReplace,
                  icon: const Icon(Icons.find_replace_rounded),
                  label: const Text('Replace range'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              copiedFragment == null || copiedFragment!.isEmpty
                  ? 'Structured clipboard: empty'
                  : 'Structured clipboard: ${copiedFragment!.blockCount} units, ${copiedFragment!.markCount} marks',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        Slider(
          value: value.clamp(0, max).toDouble(),
          min: 0,
          max: max.toDouble(),
          divisions: max,
          label: '$value',
          onChanged: (value) => onChanged(value.round()),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.textController,
    required this.lastPaste,
  });

  final TextSystemController textController;
  final TextSystemDocumentFragmentEditResult? lastPaste;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clipboard = textController.internalDocumentClipboard;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Operation state', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _StateRow(label: 'Revision', value: '${textController.revision}'),
            _StateRow(label: 'Transactions', value: '${textController.transactionLog.length}'),
            _StateRow(label: 'Can undo', value: textController.canUndo ? 'yes' : 'no'),
            _StateRow(label: 'Can redo', value: textController.canRedo ? 'yes' : 'no'),
            _StateRow(
              label: 'Document clipboard',
              value: clipboard == null || clipboard.isEmpty
                  ? 'empty'
                  : '${clipboard.blockCount} units, ${clipboard.markCount} marks, ${clipboard.plainText.length} chars',
            ),
            _StateRow(
              label: 'Last paste',
              value: lastPaste == null
                  ? 'none'
                  : '${lastPaste!.insertedPlainText.length} chars; affected ${lastPaste!.affectedBlockIds.length} text units',
            ),
          ],
        ),
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
