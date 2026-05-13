import 'package:flutter/material.dart';

import 'paged_document_controller.dart';
import 'paged_document_editor.dart';

class Phase13ABWriterDemoScreen extends StatefulWidget {
  const Phase13ABWriterDemoScreen({super.key});

  @override
  State<Phase13ABWriterDemoScreen> createState() =>
      _Phase13ABWriterDemoScreenState();
}

class _Phase13ABWriterDemoScreenState extends State<Phase13ABWriterDemoScreen> {
  late final PagedDocumentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PagedDocumentController(
      initialText: 'Untitled academic document\n\nStart writing here.',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _debugPrintPlainText() {
    debugPrint(_controller.plainTextWithPageBreaks);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Document text printed to debug console.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phase 13A/13B — Paged Academic Writer'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Debug print document',
            onPressed: _debugPrintPlainText,
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: PagedDocumentEditor(
        controller: _controller,
        autofocus: true,
      ),
    );
  }
}
