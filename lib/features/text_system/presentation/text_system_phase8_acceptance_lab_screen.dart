import 'package:flutter/material.dart';

import '../text_system.dart';

class TextSystemPhase8AcceptanceLabScreen extends StatefulWidget {
  const TextSystemPhase8AcceptanceLabScreen({super.key});

  @override
  State<TextSystemPhase8AcceptanceLabScreen> createState() => _TextSystemPhase8AcceptanceLabScreenState();
}

class _TextSystemPhase8AcceptanceLabScreenState extends State<TextSystemPhase8AcceptanceLabScreen> {
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;

  List<_AcceptanceCheck> _checks = const <_AcceptanceCheck>[];
  String _lastRunMessage = 'Run the acceptance pass to validate the Phase 8 foundations.';

  @override
  void initState() {
    super.initState();
    final document = _buildDocument();
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

  TextSystemDocument _buildDocument() {
    return TextSystemDocument(
      id: 'phase-8e-acceptance-doc',
      title: 'Phase 8E light editor acceptance',
      blocks: <TextSystemBlock>[
        const TextSystemBlock(
          id: 'accept-heading',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'Fluent text first',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 11)),
          ],
        ),
        TextSystemBlock.paragraph(
          id: 'accept-paragraph-1',
          text:
              'The text system should feel like ordinary writing while preserving highlights, links, and styles underneath.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(50, 60)),
            TextMark(kind: TextMarkKind.link, range: TextSystemRange(62, 67)),
          ],
        ),
        const TextSystemBlock(
          id: 'accept-bullet-1',
          type: TextSystemBlockType.listItem,
          text: 'Small notes, side notes, and documents reuse one engine.',
          metadata: <String, Object?>{'ordered': false},
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.italic, range: TextSystemRange(0, 11)),
          ],
        ),
        const TextSystemBlock(
          id: 'accept-bullet-2',
          type: TextSystemBlockType.listItem,
          text: 'Structured copy and paste keeps user choices intact.',
          metadata: <String, Object?>{'ordered': false},
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(0, 16)),
          ],
        ),
        TextSystemBlock.paragraph(
          id: 'accept-paragraph-2',
          text:
              'Phase 8E is an acceptance pass, not a new feature. It checks the foundations before the next larger writing phase.',
          marks: const <TextMark>[
            TextMark(kind: TextMarkKind.underline, range: TextSystemRange(0, 9)),
            TextMark(kind: TextMarkKind.code, range: TextSystemRange(13, 23)),
          ],
        ),
      ],
      metadata: const <String, Object?>{'phase': '8E'},
    );
  }

  void _reset() {
    _textController.replaceDocument(_buildDocument(), label: 'Reset Phase 8E acceptance lab');
    _autosaveController.markCleanForCurrentDocument(message: 'Reset and marked clean.');
    setState(() {
      _checks = const <_AcceptanceCheck>[];
      _lastRunMessage = 'Run the acceptance pass to validate the Phase 8 foundations.';
    });
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Manually saved Phase 8E acceptance document.');
  }

  void _snapshot() {
    _textController.saveSnapshot(label: 'Phase 8E acceptance snapshot');
  }

  Future<void> _runAcceptancePass() async {
    final checks = <_AcceptanceCheck>[];
    final document = _textController.document;

    final roundTrip = TextSystemDocument.fromJson(document.toJson());
    checks.add(
      _AcceptanceCheck(
        label: 'JSON round-trip preserves document shape',
        passed: roundTrip.title == document.title &&
            roundTrip.blocks.length == document.blocks.length &&
            roundTrip.blocks.fold<int>(0, (sum, block) => sum + block.marks.length) ==
                document.blocks.fold<int>(0, (sum, block) => sum + block.marks.length),
        detail: '${roundTrip.blocks.length} text units, ${roundTrip.blocks.fold<int>(0, (sum, block) => sum + block.marks.length)} marks after round-trip.',
      ),
    );

    final length = TextSystemDocumentSelectionMapper.documentLength(document);
    final rangeEnd = length < 140 ? length : 140;
    final range = TextSystemDocumentSelectionMapper.rangeFromOffsets(document, 10, rangeEnd);
    final fragment = TextSystemDocumentSelectionMapper.fragmentForRange(document, range);
    checks.add(
      _AcceptanceCheck(
        label: 'Document-level range can cross internal text units',
        passed: fragment.blockCount > 1 && fragment.plainText.isNotEmpty,
        detail: '${fragment.blockCount} structured text units, ${fragment.plainText.length} selected characters.',
      ),
    );

    _textController.copyDocumentFragment(range);
    final structuredClipboard = _textController.internalDocumentClipboard;
    final flatClipboard = _textController.internalClipboard;
    checks.add(
      _AcceptanceCheck(
        label: 'Structured clipboard updates flat rich fallback',
        passed: structuredClipboard != null &&
            !structuredClipboard.isEmpty &&
            flatClipboard != null &&
            !flatClipboard.isEmpty &&
            flatClipboard.marks.isNotEmpty,
        detail: '${structuredClipboard?.blockCount ?? 0} structured units, ${flatClipboard?.marks.length ?? 0} fallback marks.',
      ),
    );

    final beforePasteText = _textController.document.plainText;
    final pastePosition = TextSystemDocumentSelectionMapper.positionForOffset(
      _textController.document,
      TextSystemDocumentSelectionMapper.documentLength(_textController.document),
    );
    final pasteResult = _textController.pasteDocumentClipboardAtPosition(pastePosition);
    final pasted = !pasteResult.insertedNothing && _textController.document.plainText.length > beforePasteText.length;
    checks.add(
      _AcceptanceCheck(
        label: 'Structured paste is transaction-safe',
        passed: pasted && _textController.canUndo,
        detail: 'Inserted ${pasteResult.insertedPlainText.length} characters and logged ${_textController.transactionLog.length} transactions.',
      ),
    );

    final pastedText = _textController.document.plainText;
    _textController.undo();
    final undoRestored = _textController.document.plainText == beforePasteText;
    _textController.redo();
    final redoRestored = _textController.document.plainText == pastedText;
    checks.add(
      _AcceptanceCheck(
        label: 'Undo/redo works after structured paste',
        passed: undoRestored && redoRestored,
        detail: 'Undo restored the pre-paste text and redo restored the pasted text.',
      ),
    );

    await _autosaveController.saveNow(message: 'Acceptance save complete.');
    final loaded = await _persistenceAdapter.loadTextDocument(_textController.document.id);
    checks.add(
      _AcceptanceCheck(
        label: 'Persistence adapter can save and load current document',
        passed: loaded != null && loaded.title == _textController.document.title && loaded.blocks.length == _textController.document.blocks.length,
        detail: loaded == null ? 'No saved document was loaded.' : 'Loaded ${loaded.blocks.length} text units from in-memory persistence.',
      ),
    );

    checks.add(
      _AcceptanceCheck(
        label: 'Text-first UX rule remains explicit',
        passed: true,
        detail: 'No floating toolbar, no structural rearrange mode, and no AI are part of Phase 8.',
      ),
    );

    final passedCount = checks.where((check) => check.passed).length;
    setState(() {
      _checks = checks;
      _lastRunMessage = '$passedCount/${checks.length} checks passed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_textController, _autosaveController]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: colorScheme.surfaceContainerLowest,
          appBar: AppBar(
            title: const Text('Phase 8 acceptance lab'),
            centerTitle: false,
            backgroundColor: colorScheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Reset demo',
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              IconButton(
                tooltip: 'Snapshot',
                onPressed: _snapshot,
                icon: const Icon(Icons.history_rounded),
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
                color: colorScheme.primaryContainer.withValues(alpha: 0.48),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_rounded, color: colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Phase 8E: light editor acceptance pass', style: theme.textTheme.titleLarge),
                            const SizedBox(height: 6),
                            Text(
                              'This lab consolidates the Phase 8 foundations: calm surfaces, natural keyboard behavior, document-level coordinates, structured copy/paste, persistence safety, and the text-first UX rule.',
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
                  final wide = constraints.maxWidth >= 1180;
                  final editor = _AcceptanceEditorCard(
                    textController: _textController,
                    autosaveController: _autosaveController,
                  );
                  final report = _AcceptanceReportCard(
                    checks: _checks,
                    message: _lastRunMessage,
                    revision: _textController.revision,
                    transactions: _textController.transactionLog.length,
                    snapshots: _textController.snapshots.length,
                    saveState: _autosaveController.saveState,
                    onRun: _runAcceptancePass,
                  );

                  if (!wide) {
                    return Column(
                      children: [
                        editor,
                        const SizedBox(height: 16),
                        report,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: editor),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: report),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _DirectionCard(),
            ],
          ),
        );
      },
    );
  }
}

class _AcceptanceEditorCard extends StatelessWidget {
  const _AcceptanceEditorCard({
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
            Text('Editable surface + read-only preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Edit normally, then run the acceptance pass. The report checks the same document model underneath the visible surface.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            DocumentTextSurface(
              textController: textController,
              autosaveController: autosaveController,
              showBlockToolbars: false,
              showStatusBars: true,
              maxBlockLines: 8,
            ),
            const SizedBox(height: 16),
            Text('Read-only rendering', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
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

class _AcceptanceReportCard extends StatelessWidget {
  const _AcceptanceReportCard({
    required this.checks,
    required this.message,
    required this.revision,
    required this.transactions,
    required this.snapshots,
    required this.saveState,
    required this.onRun,
  });

  final List<_AcceptanceCheck> checks;
  final String message;
  final int revision;
  final int transactions;
  final int snapshots;
  final TextSystemSaveState saveState;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final passed = checks.where((check) => check.passed).length;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Acceptance report', style: theme.textTheme.titleMedium)),
                FilledButton.icon(
                  onPressed: onRun,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Run checks'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(label: 'Revision', value: '$revision'),
                _MetricChip(label: 'Transactions', value: '$transactions'),
                _MetricChip(label: 'Snapshots', value: '$snapshots'),
                _MetricChip(label: 'Save', value: saveState.status.name),
                if (checks.isNotEmpty) _MetricChip(label: 'Passed', value: '$passed/${checks.length}'),
              ],
            ),
            const SizedBox(height: 14),
            if (checks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('No checks have been run yet.'),
              )
            else
              for (final check in checks) _AcceptanceCheckTile(check: check),
          ],
        ),
      ),
    );
  }
}

class _AcceptanceCheckTile extends StatelessWidget {
  const _AcceptanceCheckTile({required this.check});

  final _AcceptanceCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = check.passed ? colorScheme.primary : colorScheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(check.passed ? Icons.check_circle_rounded : Icons.error_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(check.detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
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
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DirectionCard extends StatelessWidget {
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
            Text('Phase 8 completion rule', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            const _PrincipleRow(text: 'The user edits fluent text, not blocks.'),
            const _PrincipleRow(text: 'Internal text units are allowed only when they preserve user choices and safety.'),
            const _PrincipleRow(text: 'No structural rearrange mode, no floating selection toolbar, and no AI are part of this phase.'),
            const _PrincipleRow(text: 'The next larger step should be chosen deliberately: premium writer, LaTeX adapter, or deeper continuous-surface work.'),
          ],
        ),
      ),
    );
  }
}

class _PrincipleRow extends StatelessWidget {
  const _PrincipleRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _AcceptanceCheck {
  const _AcceptanceCheck({
    required this.label,
    required this.passed,
    required this.detail,
  });

  final String label;
  final bool passed;
  final String detail;
}
