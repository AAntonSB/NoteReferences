import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../text_system.dart';

class TextSystemPhase9DiagnosticsLabScreen extends StatefulWidget {
  const TextSystemPhase9DiagnosticsLabScreen({super.key});

  @override
  State<TextSystemPhase9DiagnosticsLabScreen> createState() =>
      _TextSystemPhase9DiagnosticsLabScreenState();
}

class _TextSystemPhase9DiagnosticsLabScreenState
    extends State<TextSystemPhase9DiagnosticsLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;
  FluentDocumentEditingController? _fluentController;
  String _latestReport = 'Run or copy diagnostics after interacting with the fluent editor.';

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
    _latestReport = _buildReport();
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
      id: 'phase-9f-diagnostics-document',
      title: 'Phase 9F diagnostic document',
      createdAt: now,
      updatedAt: now,
      metadata: const <String, Object?>{'phase': '9F', 'purpose': 'diagnostics'},
      blocks: <TextSystemBlock>[
        const TextSystemBlock(
          id: 'diag-heading',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'Fluent editor diagnostic document',
        ),
        TextSystemBlock.paragraph(
          id: 'diag-paragraph-1',
          text:
              'Select from this paragraph into the list below, then apply bold or highlight and copy/paste the result elsewhere.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 6)),
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(47, 63)),
          ],
        ),
        const TextSystemBlock(
          id: 'diag-bullet-1',
          type: TextSystemBlockType.listItem,
          text: 'First bullet item for cross-paragraph selection.',
        ),
        const TextSystemBlock(
          id: 'diag-bullet-2',
          type: TextSystemBlockType.listItem,
          text: 'Second bullet item. Try Enter, Backspace, copy, cut, paste, undo, and redo.',
        ),
        const TextSystemBlock(
          id: 'diag-number-1',
          type: TextSystemBlockType.listItem,
          text: 'Numbered item for ordered-list diagnostics.',
          metadata: <String, Object?>{'ordered': true, 'index': 1},
        ),
        const TextSystemBlock(
          id: 'diag-todo-1',
          type: TextSystemBlockType.todo,
          text: 'Todo row for marker-boundary diagnostics.',
          checked: false,
        ),
        TextSystemBlock(
          id: 'diag-quote-1',
          type: TextSystemBlockType.quote,
          text: 'The user should experience fluent text; structure stays underneath.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.italic, range: TextSystemRange(0, 8)),
          ],
        ),
        TextSystemBlock.paragraph(
          id: 'diag-paragraph-2',
          text:
              'After testing, press Copy report. Paste the generated report back into chat so we can diagnose failures together.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.underline, range: TextSystemRange(22, 33)),
          ],
        ),
      ],
    );
  }

  void _handleFluentControllerChanged(FluentDocumentEditingController controller) {
    setState(() {
      _fluentController = controller;
      _latestReport = _buildReport();
    });
  }

  void _refreshReport() {
    setState(() => _latestReport = _buildReport());
  }

  Future<void> _copyReport() async {
    final report = _buildReport();
    await Clipboard.setData(ClipboardData(text: report));
    setState(() => _latestReport = report);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phase 9 diagnostic report copied. Paste it back into chat.')),
    );
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved Phase 9 diagnostic document.');
    _refreshReport();
  }

  Future<void> _loadSaved() async {
    await _autosaveController.load(_textController.document.id);
    _refreshReport();
  }

  void _reset() {
    _textController.replaceDocument(_seedDocument(), label: 'Reset Phase 9 diagnostics');
    _refreshReport();
  }

  String _buildReport() {
    final report = _Phase9DiagnosticReportBuilder(
      textController: _textController,
      autosaveController: _autosaveController,
      persistenceAdapter: _persistenceAdapter,
      fluentController: _fluentController,
    );
    return report.build();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Phase 9 diagnostics lab'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh diagnostics',
            onPressed: _refreshReport,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Copy report for ChatGPT',
            onPressed: _copyReport,
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: 'Save now',
            onPressed: _saveNow,
            icon: const Icon(Icons.save_rounded),
          ),
          IconButton(
            tooltip: 'Load saved document',
            onPressed: _loadSaved,
            icon: const Icon(Icons.file_open_rounded),
          ),
          IconButton(
            tooltip: 'Reset diagnostic document',
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
                  Icon(Icons.health_and_safety_rounded, color: colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phase 9F: diagnostic report tool', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'Use the fluent editor normally, then click Copy report. The copied report includes validation checks, selection mapping, buffer segments, clipboard state, save state, and a compact document JSON payload you can paste back into chat.',
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
          _DiagnosticSummaryCard(
            textController: _textController,
            autosaveController: _autosaveController,
            fluentController: _fluentController,
            onCopyReport: _copyReport,
            onRefresh: _refreshReport,
          ),
          const SizedBox(height: 16),
          _ShareableReportCard(report: _latestReport, onCopyReport: _copyReport),
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
            Text('Fluent editor under test', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Manual script: select across paragraphs, apply formatting, copy/cut/paste, test Enter/Backspace in lists, undo/redo, save/load, then copy the report.',
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
            Text('Structured preview mirror', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This preview renders the structured model directly. If it diverges from the fluent editor, the report should help locate the sync issue.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            ReadOnlyTextSurface(textController: textController, showTitle: true),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticSummaryCard extends StatelessWidget {
  const _DiagnosticSummaryCard({
    required this.textController,
    required this.autosaveController,
    required this.fluentController,
    required this.onCopyReport,
    required this.onRefresh,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController autosaveController;
  final FluentDocumentEditingController? fluentController;
  final VoidCallback onCopyReport;
  final VoidCallback onRefresh;

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
        final checks = <TextSystemDiagnosticCheck>[
          ...TextSystemDocumentValidator.validateDocument(textController.document),
          ..._bufferChecks(fluentController),
          ...TextSystemDocumentValidator.validateDocumentFragment(
            textController.internalDocumentClipboard,
            idPrefix: 'structuredClipboard',
          ),
        ];
        final errors = TextSystemDocumentValidator.errorCount(checks);
        final warnings = TextSystemDocumentValidator.warningCount(checks);
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Live diagnostics', style: theme.textTheme.titleMedium)),
                    TextButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                    FilledButton.icon(
                      onPressed: onCopyReport,
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('Copy report'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MetricChip(label: 'Errors', value: '$errors'),
                    _MetricChip(label: 'Warnings', value: '$warnings'),
                    _MetricChip(label: 'Blocks', value: '${textController.document.blocks.length}'),
                    _MetricChip(label: 'Marks', value: '${_markCount(textController.document)}'),
                    _MetricChip(label: 'Revision', value: '${textController.revision}'),
                    _MetricChip(label: 'Transactions', value: '${textController.transactionLog.length}'),
                    _MetricChip(label: 'Buffer chars', value: '${fluentController?.text.length ?? 0}'),
                    _MetricChip(label: 'Segments', value: '${fluentController?.buffer.segments.length ?? 0}'),
                  ],
                ),
                const SizedBox(height: 16),
                _DiagnosticRows(
                  checks: checks.take(12).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShareableReportCard extends StatelessWidget {
  const _ShareableReportCard({required this.report, required this.onCopyReport});

  final String report;
  final VoidCallback onCopyReport;

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
                Expanded(child: Text('Shareable diagnostic output', style: theme.textTheme.titleMedium)),
                FilledButton.icon(
                  onPressed: onCopyReport,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy for chat'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paste this output into chat after reproducing an issue. It is intentionally plain text so downloads are not required.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 360),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  report,
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

class _DiagnosticRows extends StatelessWidget {
  const _DiagnosticRows({required this.checks});

  final List<TextSystemDiagnosticCheck> checks;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 64, child: _StatusPill(check: check)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(check.label, style: Theme.of(context).textTheme.labelLarge),
                      Text(check.message),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.check});

  final TextSystemDiagnosticCheck check;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (check.severity) {
      TextSystemDiagnosticSeverity.pass => colorScheme.primary,
      TextSystemDiagnosticSeverity.warning => colorScheme.tertiary,
      TextSystemDiagnosticSeverity.error => colorScheme.error,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          check.statusLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
  }
}

class _Phase9DiagnosticReportBuilder {
  const _Phase9DiagnosticReportBuilder({
    required this.textController,
    required this.autosaveController,
    required this.persistenceAdapter,
    required this.fluentController,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController autosaveController;
  final InMemoryTextSystemPersistenceAdapter persistenceAdapter;
  final FluentDocumentEditingController? fluentController;

  String build() {
    final document = textController.document;
    final checks = <TextSystemDiagnosticCheck>[
      ...TextSystemDocumentValidator.validateDocument(document),
      ..._bufferChecks(fluentController),
      ...TextSystemDocumentValidator.validateDocumentFragment(
        textController.internalDocumentClipboard,
        idPrefix: 'structuredClipboard',
      ),
    ];

    final buffer = fluentController?.buffer;
    final selection = fluentController?.selection;
    final range = fluentController?.documentRangeForSelection(selection);
    final rawJson = persistenceAdapter.rawJsonFor(document.id);
    final reportPayload = <String, Object?>{
      'version': 'phase9f-v1',
      'createdAt': DateTime.now().toIso8601String(),
      'summary': <String, Object?>{
        'errors': TextSystemDocumentValidator.errorCount(checks),
        'warnings': TextSystemDocumentValidator.warningCount(checks),
        'documentId': document.id,
        'title': document.title,
        'blocks': document.blocks.length,
        'marks': _markCount(document),
        'revision': textController.revision,
        'transactions': textController.transactionLog.length,
        'canUndo': textController.canUndo,
        'canRedo': textController.canRedo,
        'saveStatus': autosaveController.saveState.status.name,
        'saveMessage': autosaveController.saveState.message,
      },
      'fluentBuffer': buffer == null
          ? 'not attached'
          : <String, Object?>{
              'length': buffer.length,
              'segments': buffer.segments.length,
              'selection': selection == null
                  ? null
                  : <String, Object?>{
                      'isValid': selection.isValid,
                      'isCollapsed': selection.isCollapsed,
                      'start': selection.isValid ? selection.start : null,
                      'end': selection.isValid ? selection.end : null,
                      'selectedLength': selection.isValid ? (selection.end - selection.start).abs() : null,
                    },
              'documentRange': range == null
                  ? null
                  : <String, Object?>{
                      'description': TextSystemDocumentSelectionMapper.describeRange(document, range),
                      'json': range.toJson(),
                    },
              'segmentsDebug': buffer.debugSegments(),
            },
      'clipboard': <String, Object?>{
        'structured': _documentClipboardSummary(textController),
        'flat': _flatClipboardSummary(textController),
      },
      'checks': checks.map((check) => check.toJson()).toList(),
      'recentTransactions': textController.transactionLog.reversed.take(8).map((tx) {
        return <String, Object?>{
          'id': tx.id,
          'label': tx.label,
          'origin': tx.origin.name,
          'operations': tx.operations.map((op) => op.type.name).toList(),
        };
      }).toList(),
      'savedJsonPresent': rawJson != null,
      'documentJson': document.toJson(),
    };

    final bufferText = fluentController?.text;
    final visibleTextPreview = bufferText == null
        ? 'not attached'
        : bufferText.length > 2400
            ? '${bufferText.substring(0, 2400)}\n...[truncated ${bufferText.length - 2400} chars]'
            : bufferText;

    final out = StringBuffer()
      ..writeln('TEXTSYS PHASE 9 DIAGNOSTIC REPORT')
      ..writeln('Paste this whole report back into chat.')
      ..writeln('---')
      ..writeln('Visible text preview:')
      ..writeln(visibleTextPreview)
      ..writeln('---')
      ..writeln('Check lines:');
    for (final check in checks) {
      out.writeln(check.toReportLine());
    }
    out
      ..writeln('---')
      ..writeln('Machine-readable payload:')
      ..writeln(JsonEncoder.withIndent('  ').convert(reportPayload));
    return out.toString();
  }
}

List<TextSystemDiagnosticCheck> _bufferChecks(FluentDocumentEditingController? controller) {
  if (controller == null) {
    return const <TextSystemDiagnosticCheck>[
      TextSystemDiagnosticCheck(
        id: 'fluent.buffer.attached',
        label: 'Fluent buffer attached',
        severity: TextSystemDiagnosticSeverity.warning,
        message: 'The fluent editing controller has not reported a buffer yet.',
      ),
    ];
  }

  final buffer = controller.buffer;
  final checks = <TextSystemDiagnosticCheck>[
    TextSystemDiagnosticCheck(
      id: 'fluent.buffer.attached',
      label: 'Fluent buffer attached',
      severity: TextSystemDiagnosticSeverity.pass,
      message: 'Fluent editing controller is attached.',
    ),
  ];

  final segmentIssues = <Map<String, Object?>>[];
  for (var i = 0; i < buffer.segments.length; i++) {
    final segment = buffer.segments[i];
    final blockExists = buffer.document.blocks.any((block) => block.id == segment.blockId);
    final validBounds = segment.bufferStart >= 0 &&
        segment.bufferEnd >= segment.bufferStart &&
        segment.bufferEnd <= buffer.text.length &&
        segment.contentStart >= segment.bufferStart &&
        segment.contentEnd >= segment.contentStart &&
        segment.contentEnd <= segment.bufferEnd;
    final sorted = i == 0 || segment.bufferStart >= buffer.segments[i - 1].bufferEnd;
    if (!blockExists || !validBounds || !sorted) {
      segmentIssues.add(<String, Object?>{
        'index': i,
        'blockId': segment.blockId,
        'blockExists': blockExists,
        'validBounds': validBounds,
        'sorted': sorted,
        'segment': segment.toJson(),
      });
    }
  }

  checks.add(
    TextSystemDiagnosticCheck(
      id: 'fluent.buffer.segments',
      label: 'Buffer segments',
      severity: segmentIssues.isEmpty
          ? TextSystemDiagnosticSeverity.pass
          : TextSystemDiagnosticSeverity.error,
      message: segmentIssues.isEmpty
          ? '${buffer.segments.length} buffer segment(s) map cleanly to the document.'
          : 'One or more buffer segments are invalid.',
      details: segmentIssues.isEmpty ? const <String, Object?>{} : <String, Object?>{'issues': segmentIssues},
    ),
  );

  final selection = controller.selection;
  try {
    if (!selection.isValid) {
      checks.add(const TextSystemDiagnosticCheck(
        id: 'fluent.selection.valid',
        label: 'Selection mapping',
        severity: TextSystemDiagnosticSeverity.warning,
        message: 'Current Flutter selection is invalid.',
      ));
    } else {
      final range = controller.documentRangeForSelection(selection);
      checks.add(TextSystemDiagnosticCheck(
        id: 'fluent.selection.valid',
        label: 'Selection mapping',
        severity: TextSystemDiagnosticSeverity.pass,
        message: range == null
            ? 'Collapsed selection maps safely.'
            : TextSystemDocumentSelectionMapper.describeRange(controller.document, range),
      ));
    }
  } catch (error) {
    checks.add(TextSystemDiagnosticCheck(
      id: 'fluent.selection.valid',
      label: 'Selection mapping',
      severity: TextSystemDiagnosticSeverity.error,
      message: 'Selection mapping threw: $error',
    ));
  }

  return checks;
}

int _markCount(TextSystemDocument document) {
  return document.blocks.fold<int>(0, (count, block) => count + block.marks.length);
}

Map<String, Object?> _documentClipboardSummary(TextSystemController controller) {
  final clipboard = controller.internalDocumentClipboard;
  if (clipboard == null) return const <String, Object?>{'present': false};
  return <String, Object?>{
    'present': true,
    'blocks': clipboard.blocks.length,
    'marks': clipboard.markCount,
    'plainTextLength': clipboard.plainText.length,
  };
}

Map<String, Object?> _flatClipboardSummary(TextSystemController controller) {
  final clipboard = controller.internalClipboard;
  if (clipboard == null) return const <String, Object?>{'present': false};
  return <String, Object?>{
    'present': true,
    'textLength': clipboard.text.length,
    'marks': clipboard.marks.length,
  };
}
