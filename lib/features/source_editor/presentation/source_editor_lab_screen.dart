import 'package:flutter/material.dart';

import '../core/source_document_controller.dart';
import '../core/source_editor_configuration.dart';
import '../parsers/plain_text_source_parser.dart';
import 'source_aware_editor.dart';

class SourceEditorLabScreen extends StatefulWidget {
  const SourceEditorLabScreen({super.key});

  @override
  State<SourceEditorLabScreen> createState() => _SourceEditorLabScreenState();
}

class _SourceEditorLabScreenState extends State<SourceEditorLabScreen> {
  late final SourceDocumentController _controller;
  SourceEditorConfiguration _configuration = const SourceEditorConfiguration();

  @override
  void initState() {
    super.initState();
    _controller = SourceDocumentController(
      source: '# Profile\n\nThis is the first source-aware editor kernel. Edit this paragraph visually, then switch to source.\n\n# Next phase\n\nThe next parser can be LaTeX-specific, but it should still emit the same block model and source edits.',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Source-aware editor lab'),
        actions: [
          IconButton(
            tooltip: 'Save snapshot',
            onPressed: () => _controller.saveSnapshot(label: 'Manual snapshot'),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SourceEditorToolbar(
              configuration: _configuration,
              onChanged: (next) => setState(() => _configuration = next),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SourceAwareEditor(
              controller: _controller,
              parser: const PlainTextSourceParser(),
              configuration: _configuration,
              onConfigurationChanged: (next) => setState(() => _configuration = next),
              outputPane: _OutputDebugPane(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutputDebugPane extends StatelessWidget {
  const _OutputDebugPane({required this.controller});

  final SourceDocumentController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.28),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Derived output placeholder', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Phase 1 keeps output generic. In Phase 5 this pane can be a compiled PDF, rendered Markdown, or any other derived artifact.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text('Source length: ${controller.source.length} characters'),
              Text('Snapshots: ${controller.snapshots.length}'),
            ],
          ),
        );
      },
    );
  }
}
