import 'package:flutter/material.dart';

import '../text_system.dart';

const String _sourceBlockId = 'inline-source';
const String _targetBlockId = 'inline-target';

class TextSystemBasicSurfacesLabScreen extends StatefulWidget {
  const TextSystemBasicSurfacesLabScreen({super.key});

  @override
  State<TextSystemBasicSurfacesLabScreen> createState() =>
      _TextSystemBasicSurfacesLabScreenState();
}

class _TextSystemBasicSurfacesLabScreenState
    extends State<TextSystemBasicSurfacesLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;

  @override
  void initState() {
    super.initState();
    final document = TextSystemDocument(
      id: 'phase-7b-basic-surfaces-doc',
      title: 'Phase 7B basic surfaces',
      blocks: <TextSystemBlock>[
        TextSystemBlock.paragraph(
          id: _sourceBlockId,
          text: 'Inline source: select words, make them bold or highlighted, copy rich text.',
          marks: <TextMark>[
            TextMark(
              kind: TextMarkKind.bold,
              range: TextSystemRange(0, 13),
            ),
            TextMark(
              kind: TextMarkKind.highlight,
              range: TextSystemRange(46, 57),
            ),
          ],
        ),
        TextSystemBlock.paragraph(
          id: _targetBlockId,
          text: 'Inline target: paste rich text here and watch the read-only surface update.',
          marks: <TextMark>[
            TextMark(
              kind: TextMarkKind.italic,
              range: TextSystemRange(0, 13),
            ),
          ],
        ),
      ],
      metadata: <String, Object?>{'phase': '7B'},
    );

    _textController = TextSystemController(document: document);
    _persistenceAdapter = InMemoryTextSystemPersistenceAdapter()..seed(document);
    _autosaveController = TextSystemAutosaveController(
      textController: _textController,
      persistenceAdapter: _persistenceAdapter,
    );
  }

  @override
  void dispose() {
    _autosaveController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved Phase 7B surface lab.');
  }

  void _resetDemo() {
    _textController.replaceDocument(
      TextSystemDocument(
        id: 'phase-7b-basic-surfaces-doc',
        title: 'Phase 7B basic surfaces',
        blocks: <TextSystemBlock>[
          TextSystemBlock.paragraph(
            id: _sourceBlockId,
            text: 'Inline source: select words, make them bold or highlighted, copy rich text.',
            marks: <TextMark>[
              TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 13)),
              TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(46, 57)),
            ],
          ),
          TextSystemBlock.paragraph(
            id: _targetBlockId,
            text: 'Inline target: paste rich text here and watch the read-only surface update.',
            marks: <TextMark>[
              TextMark(kind: TextMarkKind.italic, range: TextSystemRange(0, 13)),
            ],
          ),
        ],
        metadata: <String, Object?>{'phase': '7B'},
      ),
      label: 'Reset Phase 7B demo',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Basic text surfaces lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reset demo text',
            onPressed: _resetDemo,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          IconButton(
            tooltip: 'Manual save',
            onPressed: _saveNow,
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.short_text_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 7B: inline + read-only surfaces', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This validates the first concrete lightweight surfaces. The inline surfaces provide compact editing; the read-only surface renders the same structured document without creating transactions.',
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
              final wide = constraints.maxWidth >= 1060;
              final editor = _InlineSurfaceDemoCard(
                textController: _textController,
                autosaveController: _autosaveController,
              );
              final preview = _ReadOnlySurfaceDemoCard(textController: _textController);

              if (!wide) {
                return Column(
                  children: [
                    editor,
                    const SizedBox(height: 16),
                    preview,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: editor),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: preview),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _SurfaceStateCard(
            textController: _textController,
            autosaveController: _autosaveController,
          ),
        ],
      ),
    );
  }
}

class _InlineSurfaceDemoCard extends StatelessWidget {
  const _InlineSurfaceDemoCard({
    required this.textController,
    required this.autosaveController,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController autosaveController;

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
            Text('InlineTextSurface', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Use these as compact rich-text fields. Select text and use the compact toolbar or shortcuts: Ctrl/Cmd+B, Ctrl/Cmd+I, Ctrl/Cmd+Shift+H, Ctrl/Cmd+Z.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Text('Source inline field', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            InlineTextSurface(
              textController: textController,
              autosaveController: autosaveController,
              blockId: _sourceBlockId,
              placeholder: 'Write a compact note...',
              showToolbar: true,
              showStatusBar: true,
            ),
            const SizedBox(height: 14),
            Text('Target inline field', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            InlineTextSurface(
              textController: textController,
              autosaveController: autosaveController,
              blockId: _targetBlockId,
              placeholder: 'Paste rich text here...',
              showToolbar: true,
              showStatusBar: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlySurfaceDemoCard extends StatelessWidget {
  const _ReadOnlySurfaceDemoCard({required this.textController});

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
            Text('ReadOnlyTextSurface', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This preview listens to the same text controller but does not expose editing controls. It proves that structured text can be displayed without mutating the document.',
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

class _SurfaceStateCard extends StatelessWidget {
  const _SurfaceStateCard({
    required this.textController,
    required this.autosaveController,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController autosaveController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[textController, autosaveController]),
      builder: (context, _) {
        final clipboard = textController.internalClipboard;
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cross-surface state', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _StateRow(label: 'Revision', value: '${textController.revision}'),
                _StateRow(label: 'Transactions', value: '${textController.transactionLog.length}'),
                _StateRow(label: 'Can undo', value: textController.canUndo ? 'yes' : 'no'),
                _StateRow(label: 'Can redo', value: textController.canRedo ? 'yes' : 'no'),
                _StateRow(
                  label: 'Autosave',
                  value: autosaveController.saveState.message ?? 'No save message',
                ),
                _StateRow(
                  label: 'Internal rich clipboard',
                  value: clipboard == null || clipboard.isEmpty
                      ? 'empty'
                      : '${clipboard.text.length} chars, ${clipboard.marks.length} marks',
                ),
              ],
            ),
          ),
        );
      },
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
