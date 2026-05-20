import 'package:flutter/material.dart';

import '../domain/source_reader_workspace_layout.dart';

class SourceReaderWorkspaceSelector extends StatelessWidget {
  final SourceReaderWorkspaceLayout selected;
  final ValueChanged<SourceReaderWorkspaceLayout> onChanged;
  final Widget? trailing;
  final IconData readerIcon;
  final String readerLabel;

  const SourceReaderWorkspaceSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.trailing,
    this.readerIcon = Icons.menu_book_outlined,
    this.readerLabel = 'Reader',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<SourceReaderWorkspaceLayout>(
                  segments: [
                    ButtonSegment<SourceReaderWorkspaceLayout>(
                      value: SourceReaderWorkspaceLayout.reader,
                      icon: Icon(readerIcon),
                      label: Text(readerLabel),
                    ),
                    const ButtonSegment<SourceReaderWorkspaceLayout>(
                      value: SourceReaderWorkspaceLayout.sidecar,
                      icon: Icon(Icons.view_sidebar_outlined),
                      label: Text('Sidecar'),
                    ),
                    const ButtonSegment<SourceReaderWorkspaceLayout>(
                      value: SourceReaderWorkspaceLayout.document,
                      icon: Icon(Icons.article_outlined),
                      label: Text('Document'),
                    ),
                    const ButtonSegment<SourceReaderWorkspaceLayout>(
                      value: SourceReaderWorkspaceLayout.workspaceDocument,
                      icon: Icon(Icons.edit_document),
                      label: Text('Writing'),
                    ),
                    const ButtonSegment<SourceReaderWorkspaceLayout>(
                      value: SourceReaderWorkspaceLayout.synthesis,
                      icon: Icon(Icons.view_column_outlined),
                      label: Text('Synthesis'),
                    ),
                  ],
                  selected: {selected},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    onChanged(selection.first);
                  },
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
