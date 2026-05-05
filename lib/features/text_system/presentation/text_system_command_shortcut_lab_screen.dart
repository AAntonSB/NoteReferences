import 'package:flutter/material.dart';

import '../text_system.dart';

const String _commandLabBlockId = 'phase-7e-command-lab-block';

class TextSystemCommandShortcutLabScreen extends StatefulWidget {
  const TextSystemCommandShortcutLabScreen({super.key});

  @override
  State<TextSystemCommandShortcutLabScreen> createState() =>
      _TextSystemCommandShortcutLabScreenState();
}

class _TextSystemCommandShortcutLabScreenState
    extends State<TextSystemCommandShortcutLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;
  late final TextSystemSurfaceController _surfaceController;
  late final TextSystemCommandRegistry _commandRegistry;
  late final TextSystemShortcutProfile _shortcutProfile;

  @override
  void initState() {
    super.initState();
    final document = TextSystemDocument(
      id: 'phase-7e-command-shortcut-doc',
      title: 'Phase 7E command and shortcut hardening',
      blocks: <TextSystemBlock>[
        TextSystemBlock.paragraph(
          id: _commandLabBlockId,
          text:
              'Select text here and test shared commands. Try bold, italic, underline, highlight, link marker, rich copy/paste, undo, redo, and manual save shortcuts.',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 11)),
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(82, 91)),
          ],
        ),
      ],
      metadata: <String, Object?>{'phase': '7E'},
    );

    _textController = TextSystemController(document: document);
    _persistenceAdapter = InMemoryTextSystemPersistenceAdapter()..seed(document);
    _autosaveController = TextSystemAutosaveController(
      textController: _textController,
      persistenceAdapter: _persistenceAdapter,
    );
    _surfaceController = TextSystemSurfaceController(
      textController: _textController,
      autosaveController: _autosaveController,
      config: TextSystemSurfaceConfig.simpleNote(
        id: 'phase-7e-command-surface',
        label: 'Command/shortcut lab surface',
      ),
      blockId: _commandLabBlockId,
    );
    _commandRegistry = TextSystemDefaultCommands.forSurface(_surfaceController);
    _shortcutProfile = TextSystemShortcutProfile.defaults();
  }

  @override
  void dispose() {
    _surfaceController.dispose();
    _autosaveController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _resetDemo() {
    _textController.replaceDocument(
      TextSystemDocument(
        id: 'phase-7e-command-shortcut-doc',
        title: 'Phase 7E command and shortcut hardening',
        blocks: <TextSystemBlock>[
          TextSystemBlock.paragraph(
            id: _commandLabBlockId,
            text:
                'Select text here and test shared commands. Try bold, italic, underline, highlight, link marker, rich copy/paste, undo, redo, and manual save shortcuts.',
            marks: <TextMark>[
              TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 11)),
              TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(82, 91)),
            ],
          ),
        ],
        metadata: <String, Object?>{'phase': '7E'},
      ),
      label: 'Reset Phase 7E demo',
    );
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved from Phase 7E lab.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Command and shortcut lab'),
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
                  Icon(Icons.keyboard_command_key_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 7E: command and shortcut hardening', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This validates that editable surfaces use shared command ids, a reusable shortcut profile, command availability rules, autosave hooks, undo/redo, and internal rich clipboard actions.',
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
              final editor = _CommandEditorCard(
                surfaceController: _surfaceController,
                commandRegistry: _commandRegistry,
                shortcutProfile: _shortcutProfile,
              );
              final reference = _ShortcutReferenceCard(
                surfaceController: _surfaceController,
                commandRegistry: _commandRegistry,
                shortcutProfile: _shortcutProfile,
              );

              if (!wide) {
                return Column(
                  children: [
                    editor,
                    const SizedBox(height: 16),
                    reference,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: editor),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: reference),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _Phase7AcceptanceCard(
            textController: _textController,
            autosaveController: _autosaveController,
          ),
        ],
      ),
    );
  }
}

class _CommandEditorCard extends StatelessWidget {
  const _CommandEditorCard({
    required this.surfaceController,
    required this.commandRegistry,
    required this.shortcutProfile,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;
  final TextSystemShortcutProfile shortcutProfile;

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
            Text('Shared editable command surface', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Select text to enable formatting commands. The toolbar and keyboard dispatcher both execute the same command registry.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextSystemEditableSurfaceFrame(
              surfaceController: surfaceController,
              commandRegistry: commandRegistry,
              shortcutProfile: shortcutProfile,
              showToolbar: true,
              showStatusBar: true,
              compactToolbar: false,
              editorBuilder: (context, controller) {
                return TextField(
                  controller: controller.editingController,
                  focusNode: controller.focusNode,
                  minLines: 5,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Select text and use shared commands...',
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: surfaceController.textController,
              builder: (context, _) {
                return ReadOnlyTextSurface(
                  textController: surfaceController.textController,
                  showTitle: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutReferenceCard extends StatelessWidget {
  const _ShortcutReferenceCard({
    required this.surfaceController,
    required this.commandRegistry,
    required this.shortcutProfile,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;
  final TextSystemShortcutProfile shortcutProfile;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[surfaceController, surfaceController.textController]),
      builder: (context, _) {
        return TextSystemShortcutReferencePanel(
          commandRegistry: commandRegistry,
          shortcutProfile: shortcutProfile,
          commandContext: TextSystemCommandContext(
            isEnabled: true,
            selectionLabel: surfaceController.selectionLabel,
          ),
        );
      },
    );
  }
}

class _Phase7AcceptanceCard extends StatelessWidget {
  const _Phase7AcceptanceCard({
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
                Text('Phase 7 acceptance pass', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                _CheckRow(text: 'Shared command ids drive toolbar and keyboard behavior.'),
                _CheckRow(text: 'Shortcuts are centralized in a reusable profile for future settings rebinding.'),
                _CheckRow(text: 'Formatting commands respect selection/state availability.'),
                _CheckRow(text: 'Undo/redo, save, copy, and paste are text-system commands, not surface-local hacks.'),
                _CheckRow(text: 'Link support remains a placeholder mark, leaving room for internal links later.'),
                const SizedBox(height: 12),
                _StateRow(label: 'Revision', value: '${textController.revision}'),
                _StateRow(label: 'Transactions', value: '${textController.transactionLog.length}'),
                _StateRow(label: 'Can undo', value: textController.canUndo ? 'yes' : 'no'),
                _StateRow(label: 'Can redo', value: textController.canRedo ? 'yes' : 'no'),
                _StateRow(label: 'Autosave', value: autosaveController.saveState.message ?? 'No save message'),
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

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
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
