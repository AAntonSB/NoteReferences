import 'package:flutter/material.dart';

import '../text_system.dart';

class TextSystemNaturalKeyboardLabScreen extends StatefulWidget {
  const TextSystemNaturalKeyboardLabScreen({super.key});

  @override
  State<TextSystemNaturalKeyboardLabScreen> createState() => _TextSystemNaturalKeyboardLabScreenState();
}

class _TextSystemNaturalKeyboardLabScreenState extends State<TextSystemNaturalKeyboardLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;

  @override
  void initState() {
    super.initState();
    final document = _demoDocument();
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

  void _resetDemo() {
    _textController.replaceDocument(
      _demoDocument(),
      label: 'Reset natural keyboard lab',
    );
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved natural keyboard lab.');
  }

  static TextSystemDocument _demoDocument() {
    return TextSystemDocument(
      id: 'phase-8b-natural-keyboard-doc',
      title: 'Natural keyboard behavior',
      blocks: <TextSystemBlock>[
        const TextSystemBlock(
          id: 'keyboard-heading',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'Text-first keyboard behavior',
        ),
        TextSystemBlock.paragraph(
          id: 'keyboard-paragraph-1',
          text: 'Put the cursor in this paragraph and press Enter. The document should split naturally without exposing internal structure.',
        ),
        const TextSystemBlock(
          id: 'keyboard-bullet-1',
          type: TextSystemBlockType.listItem,
          text: 'Bullet item: press Enter at the end to continue the list.',
          metadata: <String, Object?>{'ordered': false},
        ),
        const TextSystemBlock(
          id: 'keyboard-bullet-2',
          type: TextSystemBlockType.listItem,
          text: 'Clear this item and press Enter to exit the list.',
          metadata: <String, Object?>{'ordered': false},
        ),
        const TextSystemBlock(
          id: 'keyboard-numbered-1',
          type: TextSystemBlockType.listItem,
          text: 'Numbered item: press Enter and check renumbering.',
          metadata: <String, Object?>{'ordered': true, 'index': 1},
        ),
        const TextSystemBlock(
          id: 'keyboard-numbered-2',
          type: TextSystemBlockType.listItem,
          text: 'Second numbered item.',
          metadata: <String, Object?>{'ordered': true, 'index': 2},
        ),
        const TextSystemBlock(
          id: 'keyboard-todo-1',
          type: TextSystemBlockType.todo,
          text: 'Todo item: Enter creates another todo; empty Enter exits.',
          checked: false,
        ),
        const TextSystemBlock(
          id: 'keyboard-quote-1',
          type: TextSystemBlockType.quote,
          text: 'Quote item: Enter continues quote; empty Enter exits.',
        ),
      ],
      metadata: const <String, Object?>{'phase': '8B'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Natural keyboard lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reset demo',
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
            color: colorScheme.primaryContainer.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.keyboard_return_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 8B: natural text transitions', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This lab checks whether Enter and Backspace feel like ordinary text editing while the structured document model updates underneath.',
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
              final wide = constraints.maxWidth >= 1080;
              final editor = DocumentTextSurface(
                textController: _textController,
                autosaveController: _autosaveController,
                showBlockToolbars: false,
                showStatusBars: true,
              );
              final preview = _KeyboardPreviewCard(textController: _textController);

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
          _KeyboardStateCard(
            textController: _textController,
            autosaveController: _autosaveController,
          ),
        ],
      ),
    );
  }
}

class _KeyboardPreviewCard extends StatelessWidget {
  const _KeyboardPreviewCard({required this.textController});

  final TextSystemController textController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Read-only preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'This confirms that paragraph/list transitions are reflected in the shared structured model.',
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

class _KeyboardStateCard extends StatelessWidget {
  const _KeyboardStateCard({
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
        final orderedItems = document.blocks.where(
          (block) => block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true,
        );
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Keyboard behavior state', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                _StateRow(label: 'Text units', value: '${document.blocks.length}'),
                _StateRow(label: 'Revision', value: '${textController.revision}'),
                _StateRow(label: 'Transactions', value: '${textController.transactionLog.length}'),
                _StateRow(label: 'Autosave', value: autosaveController.saveState.message ?? 'No save message'),
                _StateRow(
                  label: 'Ordered item indexes',
                  value: orderedItems
                      .map((block) => block.metadata['index']?.toString() ?? '?')
                      .join(', '),
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
          SizedBox(width: 170, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}
