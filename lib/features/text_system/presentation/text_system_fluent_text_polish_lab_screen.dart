import 'package:flutter/material.dart';

import '../text_system.dart';

const String _inlineBlockId = 'phase-8a-inline';
const String _noteBlockId = 'phase-8a-note';

class TextSystemFluentTextPolishLabScreen extends StatefulWidget {
  const TextSystemFluentTextPolishLabScreen({super.key});

  @override
  State<TextSystemFluentTextPolishLabScreen> createState() => _TextSystemFluentTextPolishLabScreenState();
}

class _TextSystemFluentTextPolishLabScreenState extends State<TextSystemFluentTextPolishLabScreen> {
  late final TextSystemController _inlineController;
  late final TextSystemController _noteController;
  late final TextSystemController _documentController;
  late final InMemoryTextSystemPersistenceAdapter _inlinePersistence;
  late final InMemoryTextSystemPersistenceAdapter _notePersistence;
  late final InMemoryTextSystemPersistenceAdapter _documentPersistence;
  late final TextSystemAutosaveController _inlineAutosave;
  late final TextSystemAutosaveController _noteAutosave;
  late final TextSystemAutosaveController _documentAutosave;

  @override
  void initState() {
    super.initState();
    final inlineDocument = TextSystemDocument(
      id: 'phase-8a-inline-doc',
      title: 'Inline fluent text',
      blocks: <TextSystemBlock>[
        TextSystemBlock.paragraph(
          id: _inlineBlockId,
          text: 'A quieter inline field.',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(2, 9)),
          ],
        ),
      ],
    );
    final noteDocument = TextSystemDocument(
      id: 'phase-8a-note-doc',
      title: 'Simple note polish',
      blocks: <TextSystemBlock>[
        TextSystemBlock.paragraph(
          id: _noteBlockId,
          text:
              'A simple note should feel like a place to write, not like a nested form field. Select text and use the toolbar or shortcuts.',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(33, 49)),
          ],
        ),
      ],
    );
    final document = _initialDocument();

    _inlineController = TextSystemController(document: inlineDocument);
    _noteController = TextSystemController(document: noteDocument);
    _documentController = TextSystemController(document: document);

    _inlinePersistence = InMemoryTextSystemPersistenceAdapter()..seed(inlineDocument);
    _notePersistence = InMemoryTextSystemPersistenceAdapter()..seed(noteDocument);
    _documentPersistence = InMemoryTextSystemPersistenceAdapter()..seed(document);

    _inlineAutosave = TextSystemAutosaveController(
      textController: _inlineController,
      persistenceAdapter: _inlinePersistence,
    );
    _noteAutosave = TextSystemAutosaveController(
      textController: _noteController,
      persistenceAdapter: _notePersistence,
    );
    _documentAutosave = TextSystemAutosaveController(
      textController: _documentController,
      persistenceAdapter: _documentPersistence,
    );
  }

  TextSystemDocument _initialDocument() {
    final now = DateTime.now();
    return TextSystemDocument(
      id: 'phase-8a-document-doc',
      title: 'Fluent text, structured internally',
      createdAt: now,
      updatedAt: now,
      metadata: const <String, Object?>{'phase': '8A'},
      blocks: <TextSystemBlock>[
        const TextSystemBlock(
          id: 'phase-8a-heading',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'The document should read as one text',
        ),
        TextSystemBlock.paragraph(
          id: 'phase-8a-paragraph-1',
          text:
              'The model still uses structured paragraphs internally, but the surface should not look like a stack of managed objects.',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(21, 43)),
          ],
        ),
        const TextSystemBlock(
          id: 'phase-8a-list-1',
          type: TextSystemBlockType.listItem,
          text: 'Lists render as part of the text flow.',
          metadata: <String, Object?>{'ordered': false},
        ),
        const TextSystemBlock(
          id: 'phase-8a-list-2',
          type: TextSystemBlockType.listItem,
          text: 'Controls stay available through configuration, but hidden by default.',
          metadata: <String, Object?>{'ordered': false},
        ),
        const TextSystemBlock(
          id: 'phase-8a-paragraph-2',
          type: TextSystemBlockType.paragraph,
          text: 'This patch is about calmer visual treatment, not new document mechanics.',
        ),
      ],
    );
  }

  @override
  void dispose() {
    _inlineAutosave.dispose();
    _noteAutosave.dispose();
    _documentAutosave.dispose();
    _inlineController.dispose();
    _noteController.dispose();
    _documentController.dispose();
    super.dispose();
  }

  Future<void> _saveAll() async {
    await Future.wait(<Future<void>>[
      _inlineAutosave.saveNow(message: 'Inline text saved.'),
      _noteAutosave.saveNow(message: 'Simple note saved.'),
      _documentAutosave.saveNow(message: 'Document saved.'),
    ]);
  }

  void _resetDocument() {
    _documentController.replaceDocument(_initialDocument(), label: 'Reset Phase 8A document');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Fluent text polish lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reset document demo',
            onPressed: _resetDocument,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          IconButton(
            tooltip: 'Save all',
            onPressed: _saveAll,
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer.withValues(alpha: 0.42),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.edit_note_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 8A: fluent text surface polish', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This pass keeps the structured model internal while making the surfaces feel calmer and more text-first: quieter frames, less nested input chrome, clearer save state, and a document surface that reads as one text.',
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
              final left = _LightSurfaceColumn(
                inlineController: _inlineController,
                inlineAutosave: _inlineAutosave,
                noteController: _noteController,
                noteAutosave: _noteAutosave,
              );
              final right = _DocumentSurfaceColumn(
                textController: _documentController,
                autosaveController: _documentAutosave,
              );

              if (!wide) {
                return Column(
                  children: [
                    left,
                    const SizedBox(height: 16),
                    right,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: left),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LightSurfaceColumn extends StatelessWidget {
  const _LightSurfaceColumn({
    required this.inlineController,
    required this.inlineAutosave,
    required this.noteController,
    required this.noteAutosave,
  });

  final TextSystemController inlineController;
  final TextSystemAutosaveController inlineAutosave;
  final TextSystemController noteController;
  final TextSystemAutosaveController noteAutosave;

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
            Text('Light surfaces', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Inline and simple-note surfaces should feel lightweight. They still share formatting, shortcuts, autosave, and rich clipboard behavior.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('Inline', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            InlineTextSurface(
              textController: inlineController,
              autosaveController: inlineAutosave,
              blockId: _inlineBlockId,
              placeholder: 'Short text...',
              showToolbar: true,
              showStatusBar: true,
            ),
            const SizedBox(height: 18),
            Text('Simple note', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SimpleNoteSurface(
              textController: noteController,
              autosaveController: noteAutosave,
              blockId: _noteBlockId,
              title: 'Observation',
              subtitle: 'Compact note surface with calmer input chrome.',
              minLines: 6,
              maxLines: 10,
            ),
            const SizedBox(height: 18),
            Text('Read-only note preview', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            ReadOnlyTextSurface(
              textController: noteController,
              showTitle: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentSurfaceColumn extends StatelessWidget {
  const _DocumentSurfaceColumn({
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
            Text('Document surface', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'The document is still structured internally, but the default visual treatment should read as one continuous piece of text rather than a list of editable objects.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            DocumentTextSurface(
              textController: textController,
              autosaveController: autosaveController,
              maxBlockLines: 12,
            ),
            const SizedBox(height: 18),
            Text('Read-only document preview', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            ReadOnlyTextSurface(
              textController: textController,
              showTitle: true,
              frameStyle: TextSystemSurfaceFrameStyle.plain,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}
