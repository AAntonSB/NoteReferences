import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/text_system_block.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../persistence/in_memory_text_system_persistence_adapter.dart';
import '../persistence/text_system_autosave_controller.dart';
import '../persistence/text_system_save_state.dart';
import '../surfaces/text_system_surface_config.dart';

class TextSystemPersistenceLabScreen extends StatefulWidget {
  const TextSystemPersistenceLabScreen({super.key});

  @override
  State<TextSystemPersistenceLabScreen> createState() => _TextSystemPersistenceLabScreenState();
}

class _TextSystemPersistenceLabScreenState extends State<TextSystemPersistenceLabScreen> {
  static const String _blockId = 'paragraph-1';

  late final TextSystemController _controller;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;
  late final TextEditingController _textEditingController;

  bool _syncingFromTextSystem = false;

  final TextSystemSurfaceConfig _surfaceConfig = TextSystemSurfaceConfig.simpleDocument(
    id: 'phase-6-persistence-surface',
    label: 'Simple document surface contract',
  );

  @override
  void initState() {
    super.initState();
    final document = TextSystemDocument.singleParagraph(
      id: 'phase-6-persistence-doc',
      title: 'Phase 6 persistence safety',
      text:
          'This lab proves the text system can serialize, autosave, load, and round-trip a structured document without being tied to one app workflow.',
    );
    _controller = TextSystemController(document: document);
    _persistenceAdapter = InMemoryTextSystemPersistenceAdapter()..seed(document);
    _autosaveController = TextSystemAutosaveController(
      textController: _controller,
      persistenceAdapter: _persistenceAdapter,
    );
    _textEditingController = TextEditingController(text: _currentBlock.text);
    _controller.addListener(_syncFromTextSystem);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFromTextSystem);
    _textEditingController.dispose();
    _autosaveController.dispose();
    _controller.dispose();
    super.dispose();
  }

  TextSystemBlock get _currentBlock =>
      _controller.document.blockById(_blockId) ??
      const TextSystemBlock(id: _blockId, type: TextSystemBlockType.paragraph, text: '');

  String get _documentJson {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_controller.document.toJson());
  }

  String get _savedJson {
    const encoder = JsonEncoder.withIndent('  ');
    final raw = _persistenceAdapter.rawJsonFor(_controller.document.id);
    if (raw == null) return 'No saved document yet.';
    return encoder.convert(raw);
  }

  void _syncFromTextSystem() {
    final block = _currentBlock;
    if (_textEditingController.text == block.text) {
      if (mounted) setState(() {});
      return;
    }

    _syncingFromTextSystem = true;
    final selection = _textEditingController.selection;
    _textEditingController.text = block.text;
    if (selection.isValid) {
      final safeOffset = selection.baseOffset.clamp(0, block.text.length).toInt();
      _textEditingController.selection = TextSelection.collapsed(offset: safeOffset);
    }
    _syncingFromTextSystem = false;
    if (mounted) setState(() {});
  }

  void _handleTextChanged(String text) {
    if (_syncingFromTextSystem) return;
    _controller.updateBlockText(_blockId, text);
  }

  Future<void> _manualSave() async {
    await _autosaveController.saveNow(message: 'Manually saved.');
  }

  Future<void> _loadSaved() async {
    final loaded = await _autosaveController.load(_controller.document.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loaded == null ? 'No saved document found.' : 'Loaded saved document.')),
    );
  }

  void _roundTripCurrentDocument() {
    final roundTripped = TextSystemDocument.fromJson(_controller.document.toJson());
    _controller.replaceDocument(roundTripped, label: 'JSON round-trip current document');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Current document was serialized and restored from JSON.')),
    );
  }

  void _resetUnsavedDraft() {
    _controller.replaceDocument(
      TextSystemDocument.singleParagraph(
        id: 'phase-6-persistence-doc',
        title: 'Phase 6 persistence safety',
        text:
            'Unsaved reset draft. Edit this text, wait for autosave, then load the saved version or inspect the JSON panes.',
      ),
      label: 'Reset persistence lab draft',
    );
  }

  Future<void> _copyJson(String json) async {
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Text system persistence lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return AnimatedBuilder(
            animation: _autosaveController,
            builder: (context, _) {
              final saveState = _autosaveController.saveState;
              final currentJson = _documentJson;
              final savedJson = _savedJson;

              return ListView(
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
                          Icon(Icons.health_and_safety_rounded, color: colorScheme.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Phase 6: persistence and surface contracts', style: theme.textTheme.titleLarge),
                                const SizedBox(height: 6),
                                Text(
                                  'This lab validates the safety layer: stable JSON, in-memory persistence, autosave state, manual save/load, and a reusable surface configuration contract.',
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
                      final wide = constraints.maxWidth >= 1020;
                      final editorCard = _PersistenceEditorCard(
                        controller: _textEditingController,
                        saveState: saveState,
                        revision: _controller.revision,
                        transactionCount: _controller.transactionLog.length,
                        onChanged: _handleTextChanged,
                        onManualSave: _manualSave,
                        onLoadSaved: _loadSaved,
                        onRoundTrip: _roundTripCurrentDocument,
                        onReset: _resetUnsavedDraft,
                      );
                      final contractCard = _SurfaceContractCard(config: _surfaceConfig);

                      if (!wide) {
                        return Column(
                          children: [
                            editorCard,
                            const SizedBox(height: 16),
                            contractCard,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: editorCard),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: contractCard),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 1020;
                      final current = _JsonCard(
                        title: 'Current document JSON',
                        description: 'Live structured document state before or after autosave.',
                        json: currentJson,
                        onCopy: () => _copyJson(currentJson),
                      );
                      final saved = _JsonCard(
                        title: 'Saved JSON snapshot',
                        description: 'What the persistence adapter last stored.',
                        json: savedJson,
                        onCopy: () => _copyJson(savedJson),
                      );

                      if (!wide) {
                        return Column(
                          children: [
                            current,
                            const SizedBox(height: 16),
                            saved,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: current),
                          const SizedBox(width: 16),
                          Expanded(child: saved),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PersistenceEditorCard extends StatelessWidget {
  const _PersistenceEditorCard({
    required this.controller,
    required this.saveState,
    required this.revision,
    required this.transactionCount,
    required this.onChanged,
    required this.onManualSave,
    required this.onLoadSaved,
    required this.onRoundTrip,
    required this.onReset,
  });

  final TextEditingController controller;
  final TextSystemSaveState saveState;
  final int revision;
  final int transactionCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onManualSave;
  final VoidCallback onLoadSaved;
  final VoidCallback onRoundTrip;
  final VoidCallback onReset;

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
            Row(
              children: [
                Expanded(child: Text('Autosave draft surface', style: theme.textTheme.titleMedium)),
                _SaveStateChip(saveState: saveState),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Edit the text, watch the save state become dirty, then autosave. Manual save/load and JSON round-trip are available for safety testing.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 8,
              maxLines: 12,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Persistence test document',
                alignLabelWithHint: true,
              ),
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onManualSave,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save now'),
                ),
                OutlinedButton.icon(
                  onPressed: onLoadSaved,
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('Load saved'),
                ),
                OutlinedButton.icon(
                  onPressed: onRoundTrip,
                  icon: const Icon(Icons.sync_alt_rounded),
                  label: const Text('JSON round-trip'),
                ),
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset draft'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Revision $revision · $transactionCount transactions · ${saveState.message ?? 'No save activity yet.'}',
              style: theme.textTheme.bodySmall,
            ),
            if (saveState.lastSavedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last saved: ${_formatDate(saveState.lastSavedAt!)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaveStateChip extends StatelessWidget {
  const _SaveStateChip({required this.saveState});

  final TextSystemSaveState saveState;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    IconData icon;
    String label;
    Color background;
    Color foreground;

    switch (saveState.status) {
      case TextSystemSaveStatus.clean:
        icon = Icons.check_circle_outline_rounded;
        label = 'Clean';
        background = colorScheme.surfaceContainerHighest;
        foreground = colorScheme.onSurfaceVariant;
        break;
      case TextSystemSaveStatus.dirty:
        icon = Icons.edit_rounded;
        label = 'Unsaved';
        background = colorScheme.tertiaryContainer;
        foreground = colorScheme.onTertiaryContainer;
        break;
      case TextSystemSaveStatus.saving:
        icon = Icons.sync_rounded;
        label = 'Saving';
        background = colorScheme.secondaryContainer;
        foreground = colorScheme.onSecondaryContainer;
        break;
      case TextSystemSaveStatus.saved:
        icon = Icons.cloud_done_rounded;
        label = 'Saved';
        background = colorScheme.primaryContainer;
        foreground = colorScheme.onPrimaryContainer;
        break;
      case TextSystemSaveStatus.failed:
        icon = Icons.error_outline_rounded;
        label = 'Failed';
        background = colorScheme.errorContainer;
        foreground = colorScheme.onErrorContainer;
        break;
    }

    return Chip(
      avatar: Icon(icon, size: 18, color: foreground),
      label: Text(label),
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      side: BorderSide.none,
    );
  }
}

class _SurfaceContractCard extends StatelessWidget {
  const _SurfaceContractCard({required this.config});

  final TextSystemSurfaceConfig config;

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
            Text('Surface contract', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Phase 6 now defines how future text surfaces request features without becoming separate editors.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            _InfoRow(label: 'ID', value: config.id),
            _InfoRow(label: 'Label', value: config.label),
            _InfoRow(label: 'Kind', value: config.kind.name),
            _InfoRow(label: 'Mode', value: config.editorMode.name),
            const Divider(height: 24),
            _InfoRow(label: 'Formatting', value: '${config.features.inlineFormatting}'),
            _InfoRow(label: 'Rich clipboard', value: '${config.features.richClipboard}'),
            _InfoRow(label: 'Autosave', value: '${config.features.autosave}'),
            _InfoRow(label: 'Source view', value: '${config.features.sourceView}'),
            _InfoRow(label: 'Preview/export', value: '${config.features.preview} / ${config.features.export}'),
          ],
        ),
      ),
    );
  }
}

class _JsonCard extends StatelessWidget {
  const _JsonCard({
    required this.title,
    required this.description,
    required this.json,
    required this.onCopy,
  });

  final String title;
  final String description;
  final String json;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Copy JSON',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            Text(description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 220, maxHeight: 420),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  json,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

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
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) => value.toLocal().toString().split('.').first;
