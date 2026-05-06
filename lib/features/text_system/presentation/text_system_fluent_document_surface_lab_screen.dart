import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../text_system.dart';

class TextSystemFluentDocumentSurfaceLabScreen extends StatefulWidget {
  const TextSystemFluentDocumentSurfaceLabScreen({super.key});

  @override
  State<TextSystemFluentDocumentSurfaceLabScreen> createState() =>
      _TextSystemFluentDocumentSurfaceLabScreenState();
}

class _TextSystemFluentDocumentSurfaceLabScreenState
    extends State<TextSystemFluentDocumentSurfaceLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;
  FluentDocumentEditingController? _fluentController;

  @override
  void initState() {
    super.initState();
    final document = _seedDocument();
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

  TextSystemDocument _seedDocument() {
    final now = DateTime.now();
    return TextSystemDocument(
      id: 'phase-9b-fluent-document',
      title: 'Phase 9B styled fluent document',
      createdAt: now,
      updatedAt: now,
      metadata: const <String, Object?>{'phase': '9B'},
      blocks: <TextSystemBlock>[
        TextSystemBlock(
          id: 'heading-1',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'Styled fluent document surface',
        ),
        TextSystemBlock.paragraph(
          id: 'paragraph-1',
          text:
              'This editor is one continuous Flutter text surface with visible rich styling. Try selecting from bold text into the highlighted phrase and across the list below.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(93, 102)),
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(117, 135)),
          ],
        ),
        TextSystemBlock(
          id: 'bullet-1',
          type: TextSystemBlockType.listItem,
          text: 'Bullet markers are styled but still part of the visible buffer for this phase.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.italic, range: TextSystemRange(0, 14)),
          ],
        ),
        const TextSystemBlock(
          id: 'bullet-2',
          type: TextSystemBlockType.listItem,
          text: 'The engine maps visible buffer offsets back to structure.',
        ),
        const TextSystemBlock(
          id: 'number-1',
          type: TextSystemBlockType.listItem,
          text: 'Ordered list markers are visible text in this first styled spike.',
          metadata: <String, Object?>{'ordered': true, 'index': 1},
        ),
        const TextSystemBlock(
          id: 'todo-1',
          type: TextSystemBlockType.todo,
          text: 'Todo markers also render inside the one fluent text surface.',
          checked: false,
        ),
        TextSystemBlock(
          id: 'quote-1',
          type: TextSystemBlockType.quote,
          text: 'Quotes use a calmer italic style without turning into separate cards.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.link, range: TextSystemRange(0, 6)),
          ],
        ),
        TextSystemBlock(
          id: 'code-1',
          type: TextSystemBlockType.code,
          text: 'final editor = FluentDocumentSurface();',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.code, range: TextSystemRange(0, 38)),
          ],
        ),
        TextSystemBlock.paragraph(
          id: 'paragraph-2',
          text:
              'The document model is still the source of truth. The continuous buffer is a projection that lets the user edit fluent text.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.underline, range: TextSystemRange(0, 18)),
          ],
        ),
      ],
    );
  }

  void _handleFluentControllerChanged(FluentDocumentEditingController controller) {
    setState(() => _fluentController = controller);
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved fluent document lab.');
  }

  Future<void> _copyBufferText() async {
    final controller = _fluentController;
    if (controller == null) return;
    await Clipboard.setData(ClipboardData(text: controller.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Visible fluent buffer copied as plain text.')),
    );
  }

  void _reset() {
    _textController.replaceDocument(
      _seedDocument(),
      label: 'Reset fluent document lab',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Fluent document surface lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Copy visible buffer text',
            onPressed: _copyBufferText,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: 'Save now',
            onPressed: _saveNow,
            icon: const Icon(Icons.save_rounded),
          ),
          IconButton(
            tooltip: 'Reset lab',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.primaryContainer.withValues(alpha: 0.55),
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
                        Text('Phase 9B: styled continuous editing', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'The editor remains one continuous text surface, but the buffer now paints headings, list/todo markers, quotes, code, links, highlight, and inline marks. Styling must not break fluent selection.',
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
              final editor = _EditorCard(
                textController: _textController,
                autosaveController: _autosaveController,
                onBufferChanged: _handleFluentControllerChanged,
              );
              final preview = _PreviewCard(textController: _textController);
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
          _DebugCard(
            textController: _textController,
            autosaveController: _autosaveController,
            fluentController: _fluentController,
          ),
        ],
      ),
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({
    required this.textController,
    required this.autosaveController,
    required this.onBufferChanged,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController autosaveController;
  final ValueChanged<FluentDocumentEditingController> onBufferChanged;

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
            Text('FluentDocumentSurface', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Try selecting across styled headings, paragraphs, list items, todo text, quote text, and code. The document should still behave like one editor, not several rows.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FluentDocumentSurface(
              textController: textController,
              autosaveController: autosaveController,
              minLines: 18,
              onBufferChanged: onBufferChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.textController});

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
            Text('Structured preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This read-only surface renders the same structured document so the styled fluent buffer can be compared against the canonical renderer.',
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

class _DebugCard extends StatelessWidget {
  const _DebugCard({
    required this.textController,
    required this.autosaveController,
    required this.fluentController,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController autosaveController;
  final FluentDocumentEditingController? fluentController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        textController,
        autosaveController,
        if (fluentController != null) fluentController!,
      ]),
      builder: (context, _) {
        final controller = fluentController;
        final selection = controller?.selection;
        final buffer = controller?.buffer;
        final selectionDescription = selection == null || buffer == null
            ? 'not attached yet'
            : selection.isValid
                ? '${selection.start}-${selection.end} (${selection.isCollapsed ? 'cursor' : '${(selection.end - selection.start).abs()} chars selected'})'
                : 'invalid selection';

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fluent buffer diagnostics', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _DebugRow(label: 'Revision', value: '${textController.revision}'),
                _DebugRow(label: 'Transactions', value: '${textController.transactionLog.length}'),
                _DebugRow(label: 'Blocks', value: '${textController.document.blocks.length}'),
                _DebugRow(label: 'Visible buffer length', value: '${controller?.text.length ?? 0}'),
                _DebugRow(label: 'Selection', value: selectionDescription),
                _DebugRow(label: 'Save state', value: autosaveController.saveState.message ?? autosaveController.saveState.status.name),
                const SizedBox(height: 12),
                Text('Buffer segments', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                if (buffer == null)
                  const Text('Open the editor to attach buffer diagnostics.')
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      buffer.debugSegments().map((segment) => segment.toString()).join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
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

class _DebugRow extends StatelessWidget {
  const _DebugRow({required this.label, required this.value});

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
            width: 180,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
