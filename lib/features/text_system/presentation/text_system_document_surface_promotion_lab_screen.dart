import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../text_system.dart';

class TextSystemDocumentSurfacePromotionLabScreen extends StatefulWidget {
  const TextSystemDocumentSurfacePromotionLabScreen({super.key});

  @override
  State<TextSystemDocumentSurfacePromotionLabScreen> createState() =>
      _TextSystemDocumentSurfacePromotionLabScreenState();
}

class _TextSystemDocumentSurfacePromotionLabScreenState
    extends State<TextSystemDocumentSurfacePromotionLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;

  TextSystemDocumentSurfaceMode _mode = TextSystemDocumentSurfaceMode.fluent;
  bool _readOnly = false;
  bool _showStatusBar = true;
  bool _showTitle = true;
  int _minLines = 16;
  int? _maxLines;
  bool _compactPadding = false;
  FluentDocumentBuffer? _lastBuffer;

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
      id: 'phase-10de-document-surface-acceptance',
      title: 'Phase 10D-E document surface acceptance',
      createdAt: now,
      updatedAt: now,
      metadata: <String, Object?>{'phase': '10D-E'},
      blocks: <TextSystemBlock>[
        const TextSystemBlock(
          id: 'heading-1',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'Document surface acceptance',
        ),
        TextSystemBlock.paragraph(
          id: 'paragraph-1',
          text:
              'TextSystemDocumentSurface is now the stable app-facing document editor API. Fluent mode is the default path for serious writing.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 25)),
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(54, 64)),
          ],
        ),
        const TextSystemBlock(
          id: 'bullet-1',
          type: TextSystemBlockType.listItem,
          text: 'Fluent mode gives one continuous editor and cross-paragraph selection.',
        ),
        const TextSystemBlock(
          id: 'bullet-2',
          type: TextSystemBlockType.listItem,
          text: 'Basic mode remains available only as fallback and comparison.',
        ),
        const TextSystemBlock(
          id: 'numbered-1',
          type: TextSystemBlockType.listItem,
          text: 'Use this lab to toggle config options and copy a diagnostic report.',
          metadata: <String, Object?>{'ordered': true, 'index': 1},
        ),
        TextSystemBlock.paragraph(
          id: 'paragraph-2',
          text:
              'Try selecting across lines, formatting, copy/paste, read-only mode, undo/redo, and save. The read-only mirror should stay consistent.',
        ),
      ],
    );
  }

  TextSystemDocumentSurfaceConfig get _config => TextSystemDocumentSurfaceConfig(
        mode: _mode,
        placeholder: 'Configured document surface...',
        showStatusBar: _showStatusBar,
        showTitle: _showTitle,
        readOnly: _readOnly,
        minLines: _minLines,
        maxLines: _maxLines,
        padding: _compactPadding ? const EdgeInsets.all(10) : const EdgeInsets.all(20),
      );

  void _reset() {
    _lastBuffer = null;
    _textController.replaceDocument(_seedDocument(), label: 'Reset Phase 10D-E lab');
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Saved Phase 10D-E acceptance lab.');
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _buildReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phase 10D-E report copied.')),
    );
  }

  String _buildReport() {
    final documentChecks = TextSystemDocumentValidator.validateDocument(_textController.document);
    final fragmentChecks = TextSystemDocumentValidator.validateDocumentFragment(
      _textController.internalDocumentClipboard,
      idPrefix: 'documentClipboard',
    );
    final buffer = _lastBuffer ?? FluentDocumentBufferMapper.fromDocument(_textController.document);
    final allChecks = <TextSystemDiagnosticCheck>[...documentChecks, ...fragmentChecks];

    final payload = <String, Object?>{
      'phase': '10D-E',
      'surface': 'TextSystemDocumentSurface',
      'config': _config.toDebugJson(),
      'document': _textController.document.toJson(),
      'revision': _textController.revision,
      'transactions': _textController.transactionLog.length,
      'canUndo': _textController.canUndo,
      'canRedo': _textController.canRedo,
      'saveState': <String, Object?>{
        'status': _autosaveController.saveState.status.name,
        'message': _autosaveController.saveState.message,
        'lastSavedAt': _autosaveController.saveState.lastSavedAt?.toIso8601String(),
        'lastAttemptedAt': _autosaveController.saveState.lastAttemptedAt?.toIso8601String(),
      },
      'buffer': <String, Object?>{
        'textLength': buffer.text.length,
        'segments': buffer.segments.length,
        'debugSegments': buffer.debugSegments(),
      },
      'clipboard': <String, Object?>{
        'structuredBlocks': _textController.internalDocumentClipboard?.blocks.length,
        'structuredPlainTextLength': _textController.internalDocumentClipboard?.plainText.length,
        'flatTextLength': _textController.internalClipboard?.text.length,
        'flatMarks': _textController.internalClipboard?.marks.length,
      },
      'checks': allChecks.map((check) => check.toJson()).toList(),
      'errors': TextSystemDocumentValidator.errorCount(allChecks),
      'warnings': TextSystemDocumentValidator.warningCount(allChecks),
    };

    return 'PHASE 10D-E TEXT SYSTEM REPORT\n${const JsonEncoder.withIndent('  ').convert(payload)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Document surface acceptance lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reset',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          IconButton(
            tooltip: 'Save now',
            onPressed: _saveNow,
            icon: const Icon(Icons.save_rounded),
          ),
          IconButton(
            tooltip: 'Copy report',
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_rounded),
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
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Phase 10D-E: stabilization and acceptance', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'This validates the production-facing document editor API. Fluent mode should be the serious writing path; basic mode is retained as fallback/comparison only.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ConfigPanel(
            mode: _mode,
            readOnly: _readOnly,
            showStatusBar: _showStatusBar,
            showTitle: _showTitle,
            minLines: _minLines,
            maxLines: _maxLines,
            compactPadding: _compactPadding,
            onModeChanged: (value) => setState(() => _mode = value),
            onReadOnlyChanged: (value) => setState(() => _readOnly = value),
            onShowStatusBarChanged: (value) => setState(() => _showStatusBar = value),
            onShowTitleChanged: (value) => setState(() => _showTitle = value),
            onMinLinesChanged: (value) => setState(() => _minLines = value.round()),
            onMaxLinesChanged: (value) => setState(() => _maxLines = value),
            onCompactPaddingChanged: (value) => setState(() => _compactPadding = value),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              final editor = _Panel(
                title: 'TextSystemDocumentSurface',
                child: TextSystemDocumentSurface(
                  textController: _textController,
                  autosaveController: _autosaveController,
                  config: _config,
                  onFluentBufferChanged: (controller) {
                    setState(() => _lastBuffer = controller.buffer);
                  },
                ),
              );

              final preview = _Panel(
                title: 'Read-only mirror',
                child: ReadOnlyTextSurface(
                  textController: _textController,
                  showTitle: true,
                ),
              );

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
          _Diagnostics(
            config: _config,
            controller: _textController,
            autosaveController: _autosaveController,
            lastBuffer: _lastBuffer,
          ),
          const SizedBox(height: 16),
          _ChecklistCard(onCopyReport: _copyReport),
        ],
      ),
    );
  }
}

class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.mode,
    required this.readOnly,
    required this.showStatusBar,
    required this.showTitle,
    required this.minLines,
    required this.maxLines,
    required this.compactPadding,
    required this.onModeChanged,
    required this.onReadOnlyChanged,
    required this.onShowStatusBarChanged,
    required this.onShowTitleChanged,
    required this.onMinLinesChanged,
    required this.onMaxLinesChanged,
    required this.onCompactPaddingChanged,
  });

  final TextSystemDocumentSurfaceMode mode;
  final bool readOnly;
  final bool showStatusBar;
  final bool showTitle;
  final int minLines;
  final int? maxLines;
  final bool compactPadding;
  final ValueChanged<TextSystemDocumentSurfaceMode> onModeChanged;
  final ValueChanged<bool> onReadOnlyChanged;
  final ValueChanged<bool> onShowStatusBarChanged;
  final ValueChanged<bool> onShowTitleChanged;
  final ValueChanged<double> onMinLinesChanged;
  final ValueChanged<int?> onMaxLinesChanged;
  final ValueChanged<bool> onCompactPaddingChanged;

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
            Text('Configuration', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<TextSystemDocumentSurfaceMode>(
                  segments: const [
                    ButtonSegment(
                      value: TextSystemDocumentSurfaceMode.fluent,
                      label: Text('Fluent default'),
                      icon: Icon(Icons.article_rounded),
                    ),
                    ButtonSegment(
                      value: TextSystemDocumentSurfaceMode.basic,
                      label: Text('Basic fallback'),
                      icon: Icon(Icons.view_stream_rounded),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (value) => onModeChanged(value.first),
                ),
                FilterChip(label: const Text('Read only'), selected: readOnly, onSelected: onReadOnlyChanged),
                FilterChip(label: const Text('Status bar'), selected: showStatusBar, onSelected: onShowStatusBarChanged),
                FilterChip(label: const Text('Title in basic mode'), selected: showTitle, onSelected: onShowTitleChanged),
                FilterChip(label: const Text('Compact padding'), selected: compactPadding, onSelected: onCompactPaddingChanged),
                ChoiceChip(label: const Text('Max lines: none'), selected: maxLines == null, onSelected: (_) => onMaxLinesChanged(null)),
                ChoiceChip(label: const Text('Max lines: 10'), selected: maxLines == 10, onSelected: (_) => onMaxLinesChanged(10)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 120, child: Text('Min lines')),
                Expanded(
                  child: Slider(
                    min: 6,
                    max: 28,
                    divisions: 22,
                    value: minLines.toDouble(),
                    label: '$minLines',
                    onChanged: onMinLinesChanged,
                  ),
                ),
                SizedBox(width: 40, child: Text('$minLines')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics({
    required this.config,
    required this.controller,
    required this.autosaveController,
    required this.lastBuffer,
  });

  final TextSystemDocumentSurfaceConfig config;
  final TextSystemController controller;
  final TextSystemAutosaveController autosaveController;
  final FluentDocumentBuffer? lastBuffer;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, autosaveController]),
      builder: (context, _) {
        final checks = TextSystemDocumentValidator.validateDocument(controller.document);
        final errors = TextSystemDocumentValidator.errorCount(checks);
        final warnings = TextSystemDocumentValidator.warningCount(checks);
        final buffer = lastBuffer ?? FluentDocumentBufferMapper.fromDocument(controller.document);

        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _Row(label: 'Mode', value: config.mode.name),
                _Row(label: 'Read only', value: config.readOnly ? 'yes' : 'no'),
                _Row(label: 'Text units', value: '${controller.document.blocks.length}'),
                _Row(label: 'Buffer', value: '${buffer.text.length} chars / ${buffer.segments.length} segments'),
                _Row(label: 'Validation', value: '$errors errors / $warnings warnings'),
                _Row(label: 'Revision', value: '${controller.revision}'),
                _Row(label: 'Transactions', value: '${controller.transactionLog.length}'),
                _Row(label: 'Undo/redo', value: '${controller.canUndo ? 'can undo' : 'no undo'} / ${controller.canRedo ? 'can redo' : 'no redo'}'),
                _Row(label: 'Save state', value: autosaveController.saveState.message ?? autosaveController.saveState.status.name),
                _Row(
                  label: 'Clipboard',
                  value: controller.internalDocumentClipboard == null
                      ? 'no structured clipboard'
                      : '${controller.internalDocumentClipboard!.blocks.length} structured units',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.onCopyReport});

  final VoidCallback onCopyReport;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Acceptance checklist', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            const _Bullet('Select across multiple lines in fluent mode.'),
            const _Bullet('Apply bold/highlight to a cross-line selection.'),
            const _Bullet('Copy/cut/paste within the fluent surface.'),
            const _Bullet('Toggle read-only and confirm typing is blocked.'),
            const _Bullet('Switch to basic fallback and back to fluent.'),
            const _Bullet('Confirm the read-only mirror stays consistent.'),
            const _Bullet('Save, undo, redo, then copy the report if something looks wrong.'),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onCopyReport,
              icon: const Icon(Icons.copy_all_rounded),
              label: const Text('Copy diagnostic report'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 132, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
