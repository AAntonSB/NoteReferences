import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';

class PdfNotesPanel extends StatefulWidget {
  final NoteRepository noteRepository;
  final String documentId;
  final int currentPage;
  final String? selectedText;

  const PdfNotesPanel({
    super.key,
    required this.noteRepository,
    required this.documentId,
    required this.currentPage,
    this.selectedText,
  });

  @override
  State<PdfNotesPanel> createState() => _PdfNotesPanelState();
}

class _PdfNotesPanelState extends State<PdfNotesPanel> {
  final TextEditingController _controller = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final body = _controller.text.trim();

    if (body.isEmpty || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.noteRepository.createTextNoteForPage(
        documentId: widget.documentId,
        pageNumber: widget.currentPage,
        body: body,
        selectedText: widget.selectedText,
      );

      _controller.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note saved.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save note: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime value) {
    final date = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedText = widget.selectedText?.trim();
    final hasSelection = selectedText != null && selectedText.isNotEmpty;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _PanelHeader(currentPage: widget.currentPage),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (hasSelection)
                  _SelectedTextCard(
                    selectedText: selectedText,
                  ),
                _CreateNoteCard(
                  controller: _controller,
                  isSaving: _isSaving,
                  hasSelection: hasSelection,
                  onSave: _saveNote,
                ),
                const SizedBox(height: 16),
                Text(
                  'Notes on page ${widget.currentPage}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<NoteWithAnchor>>(
                  stream: widget.noteRepository.watchNotesForPage(
                    documentId: widget.documentId,
                    pageNumber: widget.currentPage,
                  ),
                  builder: (context, snapshot) {
                    final notes = snapshot.data ?? [];

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (notes.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(
                          'No notes for this page yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        for (final note in notes)
                          _NoteCard(
                            item: note,
                            formattedDate: _formatDateTime(note.note.createdAt),
                            onArchive: () {
                              widget.noteRepository.archiveNote(note.note.id);
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final int currentPage;

  const _PanelHeader({
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.notes),
          const SizedBox(width: 8),
          Text(
            'Notes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          Text(
            'Page $currentPage',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _SelectedTextCard extends StatelessWidget {
  final String selectedText;

  const _SelectedTextCard({
    required this.selectedText,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected text',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              selectedText,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateNoteCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isSaving;
  final bool hasSelection;
  final VoidCallback onSave;

  const _CreateNoteCard({
    required this.controller,
    required this.isSaving,
    required this.hasSelection,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasSelection
                  ? 'Add note linked to selected text'
                  : 'Add note for current page',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Write a note...',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(isSaving ? 'Saving' : 'Save note'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final NoteWithAnchor item;
  final String formattedDate;
  final VoidCallback onArchive;

  const _NoteCard({
    required this.item,
    required this.formattedDate,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final selectedText = item.anchor.selectedText?.trim();
    final hasSelectedText = selectedText != null && selectedText.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasSelectedText) ...[
              Text(
                'Linked text',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '“$selectedText”',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 20),
            ],
            Text(item.body),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  formattedDate,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Archive note',
                  onPressed: onArchive,
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}