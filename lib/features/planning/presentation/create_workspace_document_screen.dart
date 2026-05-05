import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';
import 'document_workspace_screen.dart';

class CreateWorkspaceDocumentScreen extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final StudyProject? project;

  const CreateWorkspaceDocumentScreen({
    super.key,
    required this.planningRepository,
    this.project,
  });

  @override
  State<CreateWorkspaceDocumentScreen> createState() => _CreateWorkspaceDocumentScreenState();
}

class _CreateWorkspaceDocumentScreenState extends State<CreateWorkspaceDocumentScreen> {
  final _titleController = TextEditingController();
  final _tagsController = TextEditingController();
  final _languageController = TextEditingController();
  final _sourceUrlController = TextEditingController();
  final _bodyController = TextEditingController();
  String _kind = WorkspaceDocumentKind.working;
  _DocumentContentMode _contentMode = _DocumentContentMode.plain;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    _languageController.dispose();
    _sourceUrlController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the document a title.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final document = await widget.planningRepository.createDocument(
      title: title,
      kind: _kind,
      body: _bodyController.text,
      tags: _saveTags(_splitTags(_tagsController.text), _contentMode),
      language: _emptyToNull(_languageController.text),
      sourceUrl: _emptyToNull(_sourceUrlController.text),
      projectIds: widget.project == null ? const <String>[] : <String>[widget.project!.id],
    );

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DocumentWorkspaceScreen(
          planningRepository: widget.planningRepository,
          initialDocumentId: document.id,
          projectId: widget.project?.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = widget.project;

    return Scaffold(
      appBar: AppBar(
        title: Text(project == null ? 'Create document' : 'Create document for ${project.title}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: const Text('Create'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Documents are the generic workspace primitive: job ads, CVs, personal letters, study notes, templates, pasted sources, and links can all be documents.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Job ad — Ministry of Finance, CV — English, Chapter 4 notes...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _kind,
                  decoration: const InputDecoration(
                    labelText: 'Document behavior',
                    border: OutlineInputBorder(),
                  ),
                  items: WorkspaceDocumentKind.values
                      .map(
                        (kind) => DropdownMenuItem(
                          value: kind,
                          child: Text(WorkspaceDocumentKind.label(kind)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _kind = value ?? WorkspaceDocumentKind.working),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<_DocumentContentMode>(
                  value: _contentMode,
                  decoration: const InputDecoration(
                    labelText: 'Text mode',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: _DocumentContentMode.plain, child: Text('Plain text')),
                    DropdownMenuItem(value: _DocumentContentMode.markdown, child: Text('Markdown')),
                    DropdownMenuItem(value: _DocumentContentMode.latex, child: Text('LaTeX source-aware')),
                  ],
                  onChanged: (value) => setState(() => _contentMode = value ?? _DocumentContentMode.plain),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'CV, English, job ad, macro, template...',
              helperText: 'Comma-separated. Tags describe meaning; document behavior describes how it opens.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _languageController,
                  decoration: const InputDecoration(
                    labelText: 'Language / version label',
                    hintText: 'English, Danish, v2...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _sourceUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Source link',
                    hintText: 'Overleaf, Google Docs, job ad URL...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bodyController,
            minLines: 12,
            maxLines: 24,
            decoration: const InputDecoration(
              labelText: 'Document body',
              hintText: 'Paste a job ad, start a personal letter, write LaTeX source, or leave blank.',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}


enum _DocumentContentMode { plain, markdown, latex }

List<String> _saveTags(List<String> tags, _DocumentContentMode mode) {
  final next = <String>[...tags];
  if (mode != _DocumentContentMode.plain) next.add('mode:${mode.name}');
  return next;
}

List<String> _splitTags(String value) => value
    .split(',')
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toList(growable: false);

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
