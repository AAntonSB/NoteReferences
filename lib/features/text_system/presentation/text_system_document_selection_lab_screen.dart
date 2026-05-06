import 'dart:convert';

import 'package:flutter/material.dart';

import '../text_system.dart';

class TextSystemDocumentSelectionLabScreen extends StatefulWidget {
  const TextSystemDocumentSelectionLabScreen({super.key});

  @override
  State<TextSystemDocumentSelectionLabScreen> createState() => _TextSystemDocumentSelectionLabScreenState();
}

class _TextSystemDocumentSelectionLabScreenState extends State<TextSystemDocumentSelectionLabScreen> {
  late final TextSystemController _textController;
  int _startOffset = 12;
  int _endOffset = 132;

  @override
  void initState() {
    super.initState();
    _textController = TextSystemController(
      document: TextSystemDocument(
        id: 'phase-8c-document-selection-doc',
        title: 'Phase 8C fluent selection foundation',
        blocks: <TextSystemBlock>[
          TextSystemBlock(
            id: 'selection-heading',
            type: TextSystemBlockType.heading,
            level: 1,
            text: 'Fluent text, structured underneath',
            marks: const <TextMark>[
              TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 11)),
            ],
          ),
          TextSystemBlock.paragraph(
            id: 'selection-paragraph-1',
            text:
                'This lab proves a document-level range can start in one paragraph and end in another while preserving marks and text shape internally.',
            marks: const <TextMark>[
              TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(43, 63)),
              TextMark(kind: TextMarkKind.italic, range: TextSystemRange(91, 108)),
            ],
          ),
          const TextSystemBlock(
            id: 'selection-bullet-1',
            type: TextSystemBlockType.listItem,
            text: 'The user still thinks in fluent text.',
            metadata: <String, Object?>{'ordered': false},
            marks: <TextMark>[
              TextMark(kind: TextMarkKind.bold, range: TextSystemRange(4, 8)),
            ],
          ),
          const TextSystemBlock(
            id: 'selection-bullet-2',
            type: TextSystemBlockType.listItem,
            text: 'The engine maps the selection into internal text units.',
            metadata: <String, Object?>{'ordered': false},
            marks: <TextMark>[
              TextMark(kind: TextMarkKind.code, range: TextSystemRange(11, 15)),
            ],
          ),
          TextSystemBlock.paragraph(
            id: 'selection-paragraph-2',
            text: 'Phase 8C does not change the editor yet; it gives later surfaces the language they need.',
            marks: const <TextMark>[
              TextMark(kind: TextMarkKind.underline, range: TextSystemRange(0, 8)),
            ],
          ),
        ],
        metadata: const <String, Object?>{'phase': '8C'},
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _setRange(int start, int end) {
    final max = TextSystemDocumentSelectionMapper.documentLength(_textController.document);
    setState(() {
      _startOffset = start.clamp(0, max).toInt();
      _endOffset = end.clamp(0, max).toInt();
    });
  }

  void _copyCurrentRange() {
    final range = TextSystemDocumentSelectionMapper.rangeFromOffsets(
      _textController.document,
      _startOffset,
      _endOffset,
    );
    final fragment = _textController.copyDocumentFragment(range);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${fragment.blockCount} structured text units, ${fragment.plainText.length} characters.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: _textController,
      builder: (context, _) {
        final document = _textController.document;
        final totalLength = TextSystemDocumentSelectionMapper.documentLength(document);
        final range = TextSystemDocumentSelectionMapper.rangeFromOffsets(document, _startOffset, _endOffset);
        final offsets = TextSystemDocumentSelectionMapper.offsetRangeForRange(document, range);
        final selectedText = TextSystemDocumentSelectionMapper.plainTextForRange(document, range);
        final fragment = TextSystemDocumentSelectionMapper.fragmentForRange(document, range);
        final copiedFragment = _textController.internalDocumentClipboard;

        return Scaffold(
          backgroundColor: colorScheme.surfaceContainerLowest,
          appBar: AppBar(
            title: const Text('Fluent document selection lab'),
            centerTitle: false,
            backgroundColor: colorScheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Copy structured range',
                onPressed: offsets.isCollapsed ? null : _copyCurrentRange,
                icon: const Icon(Icons.copy_all_rounded),
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
                      Icon(Icons.text_fields_rounded, color: colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Phase 8C: fluent document selection foundation', style: theme.textTheme.titleLarge),
                            const SizedBox(height: 6),
                            Text(
                              'This does not replace the current editor surface. It defines the internal document-level positions and ranges needed for future cross-paragraph selection, copy, paste, and formatting while the user continues to experience fluent text.',
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
                  final wide = constraints.maxWidth >= 1100;
                  final preview = _DocumentPreviewCard(textController: _textController);
                  final controls = _SelectionControlsCard(
                    totalLength: totalLength,
                    startOffset: offsets.start,
                    endOffset: offsets.end,
                    document: document,
                    range: range,
                    selectedText: selectedText,
                    fragment: fragment,
                    onRangeChanged: _setRange,
                    onCopy: _copyCurrentRange,
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
                      Expanded(flex: 2, child: preview),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: controls),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _CopiedFragmentCard(fragment: copiedFragment),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentPreviewCard extends StatelessWidget {
  const _DocumentPreviewCard({required this.textController});

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
            Text('Structured source document', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Rendered read-only so we can reason about ranges without changing the editing surface.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
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

class _SelectionControlsCard extends StatelessWidget {
  const _SelectionControlsCard({
    required this.totalLength,
    required this.startOffset,
    required this.endOffset,
    required this.document,
    required this.range,
    required this.selectedText,
    required this.fragment,
    required this.onRangeChanged,
    required this.onCopy,
  });

  final int totalLength;
  final int startOffset;
  final int endOffset;
  final TextSystemDocument document;
  final TextSystemDocumentRange range;
  final String selectedText;
  final TextSystemDocumentFragment fragment;
  final void Function(int start, int end) onRangeChanged;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final max = totalLength == 0 ? 1.0 : totalLength.toDouble();
    final safeStart = startOffset.clamp(0, totalLength).toDouble();
    final safeEnd = endOffset.clamp(0, totalLength).toDouble();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Document-level range', style: theme.textTheme.titleMedium)),
                FilledButton.tonalIcon(
                  onPressed: selectedText.isEmpty ? null : onCopy,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy range'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The slider represents one continuous document string. The engine maps that fluent range back into headings, paragraphs, and list items internally.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            RangeSlider(
              min: 0,
              max: max,
              divisions: totalLength == 0 ? null : totalLength,
              values: RangeValues(safeStart, safeEnd),
              labels: RangeLabels('$startOffset', '$endOffset'),
              onChanged: totalLength == 0
                  ? null
                  : (values) => onRangeChanged(values.start.round(), values.end.round()),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onRangeChanged(0, totalLength),
                  child: const Text('Whole document'),
                ),
                OutlinedButton(
                  onPressed: () => onRangeChanged(10, 120),
                  child: const Text('Across heading/paragraph'),
                ),
                OutlinedButton(
                  onPressed: () => onRangeChanged(145, 235),
                  child: const Text('Across list items'),
                ),
                OutlinedButton(
                  onPressed: () => onRangeChanged(0, 0),
                  child: const Text('Collapse'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RangeRow(label: 'Absolute offsets', value: '$startOffset → $endOffset'),
                    _RangeRow(label: 'Start', value: TextSystemDocumentSelectionMapper.describePosition(document, range.start)),
                    _RangeRow(label: 'End', value: TextSystemDocumentSelectionMapper.describePosition(document, range.end)),
                    _RangeRow(label: 'Fragment', value: '${fragment.blockCount} text units, ${fragment.markCount} marks'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Selected text', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SelectableText(
              selectedText.isEmpty ? 'No selection.' : selectedText,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Structured fragment JSON'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    JsonEncoder.withIndent('  ').convert(fragment.toJson()),
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CopiedFragmentCard extends StatelessWidget {
  const _CopiedFragmentCard({required this.fragment});

  final TextSystemDocumentFragment? fragment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = fragment != null && !fragment!.isEmpty;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Internal structured clipboard', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              active
                  ? 'The controller now has a structured document fragment and a flattened rich clipboard fallback.'
                  : 'Copy a range to populate the structured internal clipboard.',
              style: theme.textTheme.bodyMedium,
            ),
            if (active) ...[
              const SizedBox(height: 12),
              _RangeRow(label: 'Text units', value: '${fragment!.blockCount}'),
              _RangeRow(label: 'Marks', value: '${fragment!.markCount}'),
              _RangeRow(label: 'Plain text length', value: '${fragment!.plainText.length}'),
              const SizedBox(height: 10),
              SelectableText(fragment!.plainText),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({required this.label, required this.value});

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
            width: 150,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
