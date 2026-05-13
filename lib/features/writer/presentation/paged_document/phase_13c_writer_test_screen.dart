import 'package:flutter/material.dart';

import 'paged_document_controller.dart';
import 'paged_document_editor.dart';

const String _phase13CTestText = '''
Phase 13C bidirectional reflow test document

This document is intentionally long enough to create multiple pages in the academic writer. The important behavior is not that text merely moves forward when a page overflows. That already existed in the earlier overlay. The important behavior in this phase is that text also moves backward when earlier pages become smaller.

Test one: go to page one and delete a large paragraph. Text from page two should pull back into page one.

Test two: switch page size from A4 to A5. The document should repaginate into more pages without losing the caret.

Test three: switch typography from Thesis to Draft. Wider line spacing should create more pages. Then switch back to Paper or Thesis. The document should collapse back into fewer pages.

Test four: click between pages. Nothing should be editable there. The page gap is not a text input. You can only write inside a physical page.

Academic writing tends to depend on a stable relation between physical page, margins, font size, line height, and document structure. That is why this editor uses point-based page dimensions rather than arbitrary UI card dimensions. The page is not only visual decoration. It is part of the document model.

The next architectural step after this phase is not to make manual page breaks with hidden whitespace. Manual page breaks should become explicit document blocks. That way page breaks can be exported, edited, removed, and reasoned about just like headings, citations, figures, or LaTeX blocks.

For now, Phase 13C keeps the implementation text-first and conservative. The canonical document is still a plain text source. Pages are layout slices over that source. This avoids the worst failure mode from a multi-page editor: having the content of each page become a separate document by accident.

Continue typing below to force more overflow. Then delete from the first page and verify that the text below moves upward naturally.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Donec nec lacus ut nisl mattis dictum. Cras sit amet sem vel lacus bibendum consequat. Integer dignissim, sapien eu pulvinar fermentum, leo lorem porttitor turpis, sed consequat sem enim a justo.

Vivamus hendrerit, velit non posuere commodo, lacus justo gravida eros, vitae rhoncus sem purus ac elit. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Mauris ac mauris ut sem pretium pulvinar.

Suspendisse vitae quam in sem volutpat vulputate. Integer sit amet leo sed purus vestibulum commodo. Etiam mattis risus sit amet mauris tincidunt, a aliquam eros molestie. Sed dictum metus quis tellus ultrices, sit amet sollicitudin risus semper.

Aliquam erat volutpat. Praesent aliquet, ipsum sed varius gravida, ante augue convallis sapien, ac faucibus mi nibh sed dolor. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae.

Curabitur vestibulum semper nisi, eu gravida velit convallis et. Ut facilisis tellus eu neque faucibus, nec luctus mi faucibus. Maecenas id venenatis tellus. Sed et massa sed ipsum posuere suscipit.

Aenean tincidunt magna vitae ipsum dictum, at gravida arcu luctus. Donec ut ipsum feugiat, porttitor enim sit amet, pulvinar lacus. Duis gravida, mi eu dapibus rhoncus, velit nisl pellentesque nibh, sit amet dictum neque orci vitae est.

Nam id elit ullamcorper, volutpat leo at, commodo erat. Morbi laoreet tortor ac ipsum tincidunt, eget venenatis urna dignissim. Integer sit amet leo vitae neque lacinia egestas.

Phasellus ultricies enim et magna blandit, id mattis libero interdum. Nunc pulvinar, nisl in tincidunt sodales, libero erat dictum est, sed commodo ligula risus nec neque.
''';

class Phase13CWriterTestScreen extends StatefulWidget {
  const Phase13CWriterTestScreen({
    super.key,
    this.screenTitle = 'Phase 13C — Bidirectional Reflow Lab',
    this.initialText = _phase13CTestText,
  });

  final String screenTitle;
  final String initialText;

  @override
  State<Phase13CWriterTestScreen> createState() =>
      _Phase13CWriterTestScreenState();
}

class _Phase13CWriterTestScreenState extends State<Phase13CWriterTestScreen> {
  late final PagedDocumentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PagedDocumentController(
      initialText: widget.initialText.trim(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _controller.setPlainText(widget.initialText.trim());
    _controller.focusDocumentEnd();
  }

  void _debugPrintPlainText() {
    final snapshot = _controller.debugSnapshot;
    debugPrint('Phase 13C pages: ${snapshot.pageCount}');
    debugPrint('Phase 13C ranges: ${snapshot.pageRanges.join(', ')}');
    debugPrint(_controller.plainTextWithPageBreaks);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Printed ${snapshot.pageCount} pages and ${snapshot.characterCount} characters to debug console.',
        ),
      ),
    );
  }

  void _showChecks() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Phase 13C checks'),
          content: const SingleChildScrollView(
            child: Text(
              '1. Delete a paragraph from page 1. Text from page 2 should pull upward.\n\n'
              '2. Change A4 → A5. Page count should increase.\n\n'
              '3. Change Draft → Thesis/Paper. Page count should decrease again.\n\n'
              '4. Click the gap between pages. You should not be able to type there.\n\n'
              '5. Hover a page badge to see the canonical source text range for that page.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.screenTitle),
        actions: <Widget>[
          IconButton(
            tooltip: 'Test checklist',
            onPressed: _showChecks,
            icon: const Icon(Icons.checklist_outlined),
          ),
          IconButton(
            tooltip: 'Reset test document',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_outlined),
          ),
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
