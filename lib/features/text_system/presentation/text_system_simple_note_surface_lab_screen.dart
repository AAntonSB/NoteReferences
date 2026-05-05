import 'package:flutter/material.dart';

import '../text_system.dart';

const String _noteABlockId = 'simple-note-a';
const String _noteBBlockId = 'simple-note-b';

class TextSystemSimpleNoteSurfaceLabScreen extends StatefulWidget {
  const TextSystemSimpleNoteSurfaceLabScreen({super.key});

  @override
  State<TextSystemSimpleNoteSurfaceLabScreen> createState() =>
      _TextSystemSimpleNoteSurfaceLabScreenState();
}

class _TextSystemSimpleNoteSurfaceLabScreenState
    extends State<TextSystemSimpleNoteSurfaceLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;

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
    return TextSystemDocument(
      id: 'phase-7c-simple-note-doc',
      title: 'Phase 7C simple notes',
      blocks: <TextSystemBlock>[
        TextSystemBlock.paragraph(
          id: _noteABlockId,
          text: 'Sidecar note example:\n\nSelect this important phrase, highlight it, then copy rich text into the second note.',
          marks: <TextMark>[
            TextMark(
              kind: TextMarkKind.bold,
              range: TextSystemRange(0, 12),
            ),
            TextMark(
              kind: TextMarkKind.highlight,
              range: TextSystemRange(35, 51),
            ),
          ],
        ),
        TextSystemBlock.paragraph(
          id: _noteBBlockId,
          text: 'Project note example:\n\nPaste rich text here. Formatting should survive because both note surfaces use the same text-system clipboard.',
          marks: <TextMark>[
            TextMark(
              kind: TextMarkKind.italic,
              range: TextSystemRange(0, 12),
            ),
          ],
        ),
      ],
      metadata: <String, Object?>{'phase': '7C'},
    );
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved Phase 7C note lab.');
  }

  void _resetDemo() {
    _textController.replaceDocument(_seedDocument(), label: 'Reset Phase 7C demo');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Simple note surface lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reset demo notes',
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
            color: colorScheme.secondaryContainer.withValues(alpha: 0.55),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_rounded, color: colorScheme.secondary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 7C: SimpleNoteSurface', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This validates the reusable light note surface: multi-line note editing, compact toolbar, shared shortcuts, rich internal copy/paste, undo/redo, and autosave hooks.',
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
              final notes = _EditableNotesCard(
                textController: _textController,
                autosaveController: _autosaveController,
              );
              final preview = _NotePreviewCard(textController: _textController);

              if (!wide) {
                return Column(
                  children: [
                    notes,
                    const SizedBox(height: 16),
                    preview,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: notes),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: preview),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _NoteUseCasesCard(),
          const SizedBox(height: 16),
          _NoteStateCard(
            textController: _textController,
            autosaveController: _autosaveController,
          ),
        ],
      ),
    );
  }
}

class _EditableNotesCard extends StatelessWidget {
  const _EditableNotesCard({
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
            Text('Editable note surfaces', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'These are not document editors. They are compact, reusable note editors for places like sidecar notes, observations, comments, and lightweight project notes.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            SimpleNoteSurface(
              textController: textController,
              autosaveController: autosaveController,
              blockId: _noteABlockId,
              title: 'Sidecar note',
              subtitle: 'Small note next to another object in the app.',
              placeholder: 'Write a sidecar note...',
              minLines: 5,
              maxLines: 9,
            ),
            const SizedBox(height: 14),
            SimpleNoteSurface(
              textController: textController,
              autosaveController: autosaveController,
              blockId: _noteBBlockId,
              title: 'Project note',
              subtitle: 'A slightly larger note that still does not need full document chrome.',
              placeholder: 'Write a project note...',
              minLines: 6,
              maxLines: 12,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotePreviewCard extends StatelessWidget {
  const _NotePreviewCard({required this.textController});

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
            Text('Read-only note preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'The same structured note content can be rendered elsewhere without making another editable field.',
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

class _NoteUseCasesCard extends StatelessWidget {
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
            Text('What this surface is for', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            const _UseCaseRow(
              icon: Icons.splitscreen_rounded,
              title: 'Sidecar notes',
              description: 'Notes attached to PDFs, tasks, documents, cards, or workspace objects.',
            ),
            const _UseCaseRow(
              icon: Icons.task_alt_rounded,
              title: 'Light project notes',
              description: 'Small pieces of reusable rich text that do not need the premium writer.',
            ),
            const _UseCaseRow(
              icon: Icons.content_paste_go_rounded,
              title: 'Rich text transfer',
              description: 'Bold, italic, and highlight marks can move through the internal text-system clipboard.',
            ),
          ],
        ),
      ),
    );
  }
}

class _UseCaseRow extends StatelessWidget {
  const _UseCaseRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteStateCard extends StatelessWidget {
  const _NoteStateCard({
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
        final noteA = textController.document.blockById(_noteABlockId);
        final noteB = textController.document.blockById(_noteBBlockId);

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Simple note system state', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _StateRow(label: 'Revision', value: '${textController.revision}'),
                _StateRow(label: 'Transactions', value: '${textController.transactionLog.length}'),
                _StateRow(label: 'Can undo', value: textController.canUndo ? 'yes' : 'no'),
                _StateRow(label: 'Can redo', value: textController.canRedo ? 'yes' : 'no'),
                _StateRow(
                  label: 'Autosave',
                  value: autosaveController.saveState.message ?? 'No save message',
                ),
                _StateRow(label: 'Sidecar note marks', value: '${noteA?.marks.length ?? 0}'),
                _StateRow(label: 'Project note marks', value: '${noteB?.marks.length ?? 0}'),
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
