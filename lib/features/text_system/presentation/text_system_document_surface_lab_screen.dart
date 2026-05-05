import 'package:flutter/material.dart';

import '../text_system.dart';

class TextSystemDocumentSurfaceLabScreen extends StatefulWidget {
  const TextSystemDocumentSurfaceLabScreen({super.key});

  @override
  State<TextSystemDocumentSurfaceLabScreen> createState() => _TextSystemDocumentSurfaceLabScreenState();
}

class _TextSystemDocumentSurfaceLabScreenState extends State<TextSystemDocumentSurfaceLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;

  @override
  void initState() {
    super.initState();
    final document = _initialDocument();
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

  TextSystemDocument _initialDocument() {
    final now = DateTime.now();
    return TextSystemDocument(
      id: 'phase-7d-document-surface-doc',
      title: 'Phase 7D document surface',
      createdAt: now,
      updatedAt: now,
      metadata: const <String, Object?>{'phase': '7D'},
      blocks: <TextSystemBlock>[
        TextSystemBlock(
          id: 'doc-heading-1',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'A reusable regular document surface',
        ),
        TextSystemBlock.paragraph(
          id: 'doc-paragraph-1',
          text:
              'This is still the light text-system layer. It gives normal documents a document-shaped surface without becoming the premium writer yet.',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(18, 35)),
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(96, 112)),
          ],
        ),
        const TextSystemBlock(
          id: 'doc-list-1',
          type: TextSystemBlockType.listItem,
          text: 'Basic list blocks render and can be edited.',
          metadata: <String, Object?>{'ordered': false},
        ),
        const TextSystemBlock(
          id: 'doc-list-2',
          type: TextSystemBlockType.listItem,
          text: 'Numbered list blocks are reserved through metadata.',
          metadata: <String, Object?>{'ordered': true, 'index': 1},
        ),
      ],
    );
  }

  void _resetDemo() {
    _textController.replaceDocument(_initialDocument(), label: 'Reset Phase 7D demo');
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved Phase 7D document lab.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Document text surface lab'),
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
                  Icon(Icons.article_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 7D: DocumentTextSurface', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This validates the first regular document-shaped surface: title editing, multiple blocks, document spacing, block conversion, basic headings/lists, rich formatting, autosave, and read-only rendering.',
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
              final wide = constraints.maxWidth >= 1160;
              final editor = _DocumentSurfaceCard(
                textController: _textController,
                autosaveController: _autosaveController,
              );
              final preview = _DocumentPreviewCard(textController: _textController);

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
          _DocumentStateCard(
            textController: _textController,
            autosaveController: _autosaveController,
          ),
        ],
      ),
    );
  }
}

class _DocumentSurfaceCard extends StatelessWidget {
  const _DocumentSurfaceCard({
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
            Text('DocumentTextSurface', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Use this for regular documents and longer notes. Try changing block types, moving blocks, applying rich marks, and copying rich text into another block.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            DocumentTextSurface(
              textController: textController,
              autosaveController: autosaveController,
              maxBlockLines: 10,
            ),
          ],
        ),
      ),
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
            Text('Read-only document preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'The same structured document is rendered without editing controls. This is the bridge from editable document text to previews/snippets/revision views.',
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

class _DocumentStateCard extends StatelessWidget {
  const _DocumentStateCard({
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
        final document = textController.document;
        final clipboard = textController.internalClipboard;
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Document state', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _StateRow(label: 'Title', value: document.title),
                _StateRow(label: 'Blocks', value: '${document.blocks.length}'),
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
                _StateRow(
                  label: 'Block types',
                  value: document.blocks.map((block) => block.type.name).join(', '),
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
