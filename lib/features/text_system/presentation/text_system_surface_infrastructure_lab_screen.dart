import 'package:flutter/material.dart';

import '../commands/text_system_command.dart';
import '../commands/text_system_default_commands.dart';
import '../commands/text_system_command_registry.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../persistence/in_memory_text_system_persistence_adapter.dart';
import '../persistence/text_system_autosave_controller.dart';
import '../surfaces/text_system_editable_surface_frame.dart';
import '../surfaces/text_system_surface_config.dart';
import '../surfaces/text_system_surface_controller.dart';

class TextSystemSurfaceInfrastructureLabScreen extends StatefulWidget {
  const TextSystemSurfaceInfrastructureLabScreen({super.key});

  @override
  State<TextSystemSurfaceInfrastructureLabScreen> createState() =>
      _TextSystemSurfaceInfrastructureLabScreenState();
}

class _TextSystemSurfaceInfrastructureLabScreenState
    extends State<TextSystemSurfaceInfrastructureLabScreen> {
  static const String _blockId = 'paragraph-1';

  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;
  late final TextSystemSurfaceController _surfaceController;
  late final TextSystemCommandRegistry _commandRegistry;

  final TextSystemSurfaceConfig _surfaceConfig = TextSystemSurfaceConfig.simpleNote(
    id: 'phase-7a-shared-surface',
    label: 'Phase 7A shared surface controller',
  );

  @override
  void initState() {
    super.initState();
    final document = TextSystemDocument.singleParagraph(
      id: 'phase-7a-surface-doc',
      title: 'Phase 7A surface infrastructure',
      text:
          'This is not yet the final inline, note, document, or read-only surface. It is the shared frame they will reuse: selection bridge, command registry, toolbar, shortcuts, autosave handoff, and undo/redo wiring.',
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
      config: _surfaceConfig,
      blockId: _blockId,
    );
    _commandRegistry = TextSystemDefaultCommands.forSurface(_surfaceController);
  }

  @override
  void dispose() {
    _surfaceController.dispose();
    _autosaveController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Text surface infrastructure lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
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
                  Icon(Icons.dashboard_customize_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 7A: shared surface infrastructure', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'This validates the reusable layer that future surfaces will share. Phase 7B/7C/7D can now build concrete inline, note, document, and read-only surfaces without recoding commands, shortcuts, selection, autosave, or toolbar behavior.',
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
              final editor = _SurfaceFrameDemoCard(
                surfaceController: _surfaceController,
                commandRegistry: _commandRegistry,
              );
              final state = _SurfaceStateCard(
                surfaceController: _surfaceController,
                commandRegistry: _commandRegistry,
              );

              if (!wide) {
                return Column(
                  children: [
                    editor,
                    const SizedBox(height: 16),
                    state,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: editor),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: state),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _CommandRegistryCard(commandRegistry: _commandRegistry),
        ],
      ),
    );
  }
}

class _SurfaceFrameDemoCard extends StatelessWidget {
  const _SurfaceFrameDemoCard({
    required this.surfaceController,
    required this.commandRegistry,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;

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
            Text('Reusable editable surface frame', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Try selecting text, using the toolbar, pressing Ctrl/Cmd+B, Ctrl/Cmd+I, Ctrl/Cmd+Shift+H, Ctrl/Cmd+Z, or Ctrl/Cmd+S. The frame is intentionally generic; concrete surfaces will provide their own body styling later.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextSystemEditableSurfaceFrame(
              surfaceController: surfaceController,
              commandRegistry: commandRegistry,
              editorBuilder: (context, controller) {
                return TextField(
                  controller: controller.editingController,
                  focusNode: controller.focusNode,
                  readOnly: controller.isReadOnly,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Shared text-system surface body',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceStateCard extends StatelessWidget {
  const _SurfaceStateCard({
    required this.surfaceController,
    required this.commandRegistry,
  });

  final TextSystemSurfaceController surfaceController;
  final TextSystemCommandRegistry commandRegistry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        surfaceController,
        surfaceController.textController,
        if (surfaceController.autosaveController != null) surfaceController.autosaveController!,
      ]),
      builder: (context, _) {
        final config = surfaceController.config;
        final saveState = surfaceController.autosaveController?.saveState;

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Surface controller state', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _StateRow(label: 'Surface', value: config.label),
                _StateRow(label: 'Kind', value: config.kind.name),
                _StateRow(label: 'Mode', value: config.editorMode.name),
                _StateRow(label: 'Selection', value: surfaceController.selectionLabel),
                _StateRow(label: 'Revision', value: '${surfaceController.textController.revision}'),
                _StateRow(label: 'Transactions', value: '${surfaceController.textController.transactionLog.length}'),
                _StateRow(label: 'Save state', value: saveState?.message ?? 'No autosave controller'),
                const Divider(height: 24),
                Text('Enabled feature switches', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FeatureChip(label: 'inline formatting', enabled: config.features.inlineFormatting),
                    _FeatureChip(label: 'highlighting', enabled: config.features.highlighting),
                    _FeatureChip(label: 'rich clipboard', enabled: config.features.richClipboard),
                    _FeatureChip(label: 'undo/redo', enabled: config.features.undoRedo),
                    _FeatureChip(label: 'autosave', enabled: config.features.autosave),
                    _FeatureChip(label: 'shortcuts', enabled: config.features.shortcuts),
                    _FeatureChip(label: 'links reserved', enabled: config.features.links),
                    _FeatureChip(label: 'lists reserved', enabled: config.features.lists),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommandRegistryCard extends StatelessWidget {
  const _CommandRegistryCard({required this.commandRegistry});

  final TextSystemCommandRegistry commandRegistry;

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
            Text('Shared command registry', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'These are stable text-system command ids. The future settings page can rebind shortcuts against these ids without knowing which surface is currently active.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final command in commandRegistry.commands)
                  _CommandChip(command: command),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip({required this.command});

  final TextSystemCommand command;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(command.icon ?? Icons.bolt_rounded, size: 18),
      label: Text(command.defaultShortcutLabel == null
          ? command.id
          : '${command.id} · ${command.defaultShortcutLabel}'),
      onPressed: () {},
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.label, required this.value});

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
            width: 104,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(enabled ? Icons.check_rounded : Icons.remove_rounded, size: 18),
      label: Text(label),
    );
  }
}
