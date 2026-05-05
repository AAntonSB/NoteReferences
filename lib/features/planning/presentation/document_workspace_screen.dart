import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';
import 'workspace_document_editor_screen.dart';

enum DocumentWorkspaceMode { focus, split, triple }

class DocumentWorkspaceScreen extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final String? initialDocumentId;
  final String? projectId;

  const DocumentWorkspaceScreen({
    super.key,
    required this.planningRepository,
    this.initialDocumentId,
    this.projectId,
  });

  @override
  State<DocumentWorkspaceScreen> createState() => _DocumentWorkspaceScreenState();
}

class _DocumentWorkspaceScreenState extends State<DocumentWorkspaceScreen> {
  DocumentWorkspaceMode _mode = DocumentWorkspaceMode.focus;
  String? _primaryDocumentId;
  String? _secondaryDocumentId;
  String? _tertiaryDocumentId;

  @override
  void initState() {
    super.initState();
    _primaryDocumentId = widget.initialDocumentId;
  }

  List<WorkspaceDocument> _visibleDocuments() {
    final docs = widget.projectId == null
        ? widget.planningRepository.documents
        : widget.planningRepository.documentsForProject(widget.projectId!);
    return List<WorkspaceDocument>.of(docs)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  WorkspaceDocument? _documentById(String? id) {
    if (id == null) return null;
    return widget.planningRepository.documentById(id);
  }

  void _normalizeSelection(List<WorkspaceDocument> documents) {
    if (documents.isEmpty) {
      _primaryDocumentId = null;
      _secondaryDocumentId = null;
      _tertiaryDocumentId = null;
      return;
    }

    bool exists(String? id) => id != null && documents.any((document) => document.id == id);
    if (!exists(_primaryDocumentId)) _primaryDocumentId = documents.first.id;
    if (!exists(_secondaryDocumentId)) _secondaryDocumentId = null;
    if (!exists(_tertiaryDocumentId)) _tertiaryDocumentId = null;

    if (_mode == DocumentWorkspaceMode.split || _mode == DocumentWorkspaceMode.triple) {
      _secondaryDocumentId ??= _firstOtherDocumentId(documents, {_primaryDocumentId}) ?? documents.first.id;
    }
    if (_mode == DocumentWorkspaceMode.triple) {
      _tertiaryDocumentId ??= _firstOtherDocumentId(documents, {_primaryDocumentId, _secondaryDocumentId}) ?? documents.first.id;
    }
  }

  String? _firstOtherDocumentId(List<WorkspaceDocument> documents, Set<String?> usedIds) {
    for (final document in documents) {
      if (!usedIds.contains(document.id)) return document.id;
    }
    return null;
  }

  Future<void> _createDocument({int targetPane = 0, String? defaultTitle, String? defaultKind, String? defaultBody}) async {
    final draft = await showDialog<_DocumentDraft>(
      context: context,
      builder: (context) => _QuickDocumentDialog(
        title: defaultTitle,
        kind: defaultKind ?? WorkspaceDocumentKind.working,
        body: defaultBody,
      ),
    );
    if (draft == null) return;

    final projectIds = widget.projectId == null ? const <String>[] : <String>[widget.projectId!];
    final tags = <String>[
      ...draft.tags,
      if (draft.contentMode != _DocumentContentMode.plain) 'mode:${draft.contentMode.name}',
    ];
    final document = await widget.planningRepository.createDocument(
      title: draft.title,
      kind: draft.kind,
      body: draft.body,
      tags: tags,
      language: draft.language,
      sourceUrl: draft.sourceUrl,
      projectIds: projectIds,
    );
    if (!mounted) return;
    setState(() {
      _assignDocumentToPane(targetPane, document.id);
      if (targetPane == 1 && _mode == DocumentWorkspaceMode.focus) _mode = DocumentWorkspaceMode.split;
      if (targetPane == 2) _mode = DocumentWorkspaceMode.triple;
    });
  }

  Future<void> _createWorkspaceSet() async {
    final documents = _visibleDocuments();
    final draft = await showDialog<_WorkspaceSetDraft>(
      context: context,
      builder: (context) => _WorkspaceSetDialog(documents: documents),
    );
    if (draft == null) return;

    final projectIds = widget.projectId == null ? const <String>[] : <String>[widget.projectId!];
    final setTag = 'set:${draft.name}';

    final source = await widget.planningRepository.createDocument(
      title: draft.sourceTitle,
      kind: WorkspaceDocumentKind.source,
      body: draft.sourceBody,
      tags: <String>[setTag, 'source', 'job ad'],
      projectIds: projectIds,
    );

    final referenceId = draft.referenceDocumentId == null
        ? (await widget.planningRepository.createDocument(
          title: draft.referenceTitle,
          kind: WorkspaceDocumentKind.working,
          body: draft.referenceBody,
          tags: <String>[
            setTag,
            'reference',
            if (draft.referenceContentMode != _DocumentContentMode.plain) 'mode:${draft.referenceContentMode.name}',
          ],
          sourceUrl: draft.referenceSourceUrl,
          projectIds: projectIds,
        ))
            .id
        : draft.referenceDocumentId!;

    final draftDocument = await widget.planningRepository.createDocument(
      title: draft.draftTitle,
      kind: WorkspaceDocumentKind.working,
      body: '',
      tags: <String>[setTag, 'draft', 'personal letter'],
      projectIds: projectIds,
    );

    if (!mounted) return;
    setState(() {
      _mode = DocumentWorkspaceMode.triple;
      _primaryDocumentId = source.id;
      _secondaryDocumentId = referenceId;
      _tertiaryDocumentId = draftDocument.id;
    });
  }

  void _assignDocumentToPane(int pane, String documentId) {
    switch (pane) {
      case 1:
        _secondaryDocumentId = documentId;
        break;
      case 2:
        _tertiaryDocumentId = documentId;
        break;
      case 0:
      default:
        _primaryDocumentId = documentId;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.planningRepository,
      builder: (context, _) {
        final documents = _visibleDocuments();
        _normalizeSelection(documents);
        final primaryDocument = _documentById(_primaryDocumentId);
        final secondaryDocument = _documentById(_secondaryDocumentId);
        final tertiaryDocument = _documentById(_tertiaryDocumentId);
        final project = widget.projectId == null ? null : widget.planningRepository.projectById(widget.projectId!);

        return Scaffold(
          appBar: AppBar(
            title: Text(project == null ? 'Document workspace' : project.title),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: _createWorkspaceSet,
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('New set'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonalIcon(
                  onPressed: () => _createDocument(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New document'),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _DocumentWorkspaceHeader(
                documents: documents,
                mode: _mode,
                primaryDocumentId: primaryDocument?.id,
                secondaryDocumentId: secondaryDocument?.id,
                tertiaryDocumentId: tertiaryDocument?.id,
                onModeChanged: (mode) => setState(() => _mode = mode),
                onPrimaryChanged: (id) => setState(() => _primaryDocumentId = id),
                onSecondaryChanged: (id) => setState(() => _secondaryDocumentId = id),
                onTertiaryChanged: (id) => setState(() => _tertiaryDocumentId = id),
                onCreatePrimary: () => _createDocument(targetPane: 0),
                onCreateSecondary: () => _createDocument(targetPane: 1),
                onCreateTertiary: () => _createDocument(targetPane: 2),
              ),
              const Divider(height: 1),
              Expanded(
                child: documents.isEmpty
                    ? _EmptyDocumentWorkspace(
                        projectTitle: project?.title,
                        onCreateDocument: () => _createDocument(),
                        onCreateSet: _createWorkspaceSet,
                      )
                    : _DocumentWorkspaceBody(
                        planningRepository: widget.planningRepository,
                        mode: _mode,
                        primaryDocument: primaryDocument,
                        secondaryDocument: secondaryDocument,
                        tertiaryDocument: tertiaryDocument,
                        onCreatePrimary: () => _createDocument(targetPane: 0),
                        onCreateSecondary: () => _createDocument(targetPane: 1),
                        onCreateTertiary: () => _createDocument(targetPane: 2),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentWorkspaceHeader extends StatelessWidget {
  final List<WorkspaceDocument> documents;
  final DocumentWorkspaceMode mode;
  final String? primaryDocumentId;
  final String? secondaryDocumentId;
  final String? tertiaryDocumentId;
  final ValueChanged<DocumentWorkspaceMode> onModeChanged;
  final ValueChanged<String> onPrimaryChanged;
  final ValueChanged<String> onSecondaryChanged;
  final ValueChanged<String> onTertiaryChanged;
  final VoidCallback onCreatePrimary;
  final VoidCallback onCreateSecondary;
  final VoidCallback onCreateTertiary;

  const _DocumentWorkspaceHeader({
    required this.documents,
    required this.mode,
    required this.primaryDocumentId,
    required this.secondaryDocumentId,
    required this.tertiaryDocumentId,
    required this.onModeChanged,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
    required this.onTertiaryChanged,
    required this.onCreatePrimary,
    required this.onCreateSecondary,
    required this.onCreateTertiary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            SegmentedButton<DocumentWorkspaceMode>(
              segments: const [
                ButtonSegment(
                  value: DocumentWorkspaceMode.focus,
                  icon: Icon(Icons.article_outlined),
                  label: Text('Focus'),
                ),
                ButtonSegment(
                  value: DocumentWorkspaceMode.split,
                  icon: Icon(Icons.view_column_outlined),
                  label: Text('Split'),
                ),
                ButtonSegment(
                  value: DocumentWorkspaceMode.triple,
                  icon: Icon(Icons.view_week_outlined),
                  label: Text('Triple'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => onModeChanged(selection.first),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DocumentSelector(
                label: mode == DocumentWorkspaceMode.focus ? 'Document' : 'Source',
                documents: documents,
                selectedDocumentId: primaryDocumentId,
                onChanged: onPrimaryChanged,
                onCreate: onCreatePrimary,
              ),
            ),
            if (mode == DocumentWorkspaceMode.split || mode == DocumentWorkspaceMode.triple) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _DocumentSelector(
                  label: mode == DocumentWorkspaceMode.triple ? 'Reference' : 'Pane 2',
                  documents: documents,
                  selectedDocumentId: secondaryDocumentId,
                  onChanged: onSecondaryChanged,
                  onCreate: onCreateSecondary,
                ),
              ),
            ],
            if (mode == DocumentWorkspaceMode.triple) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _DocumentSelector(
                  label: 'Draft',
                  documents: documents,
                  selectedDocumentId: tertiaryDocumentId,
                  onChanged: onTertiaryChanged,
                  onCreate: onCreateTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DocumentSelector extends StatelessWidget {
  final String label;
  final List<WorkspaceDocument> documents;
  final String? selectedDocumentId;
  final ValueChanged<String> onChanged;
  final VoidCallback onCreate;

  const _DocumentSelector({
    required this.label,
    required this.documents,
    required this.selectedDocumentId,
    required this.onChanged,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create'),
      );
    }

    return DropdownButtonFormField<String>(
      value: selectedDocumentId,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        for (final document in documents)
          DropdownMenuItem(
            value: document.id,
            child: Text(document.title, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _DocumentWorkspaceBody extends StatelessWidget {
  final StudyPlanningRepository planningRepository;
  final DocumentWorkspaceMode mode;
  final WorkspaceDocument? primaryDocument;
  final WorkspaceDocument? secondaryDocument;
  final WorkspaceDocument? tertiaryDocument;
  final VoidCallback onCreatePrimary;
  final VoidCallback onCreateSecondary;
  final VoidCallback onCreateTertiary;

  const _DocumentWorkspaceBody({
    required this.planningRepository,
    required this.mode,
    required this.primaryDocument,
    required this.secondaryDocument,
    required this.tertiaryDocument,
    required this.onCreatePrimary,
    required this.onCreateSecondary,
    required this.onCreateTertiary,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == DocumentWorkspaceMode.focus) {
      return _WorkspacePane(
        planningRepository: planningRepository,
        document: primaryDocument,
        onCreateDocument: onCreatePrimary,
      );
    }

    final panes = <Widget>[
      _WorkspacePane(
        planningRepository: planningRepository,
        document: primaryDocument,
        onCreateDocument: onCreatePrimary,
      ),
      _WorkspacePane(
        planningRepository: planningRepository,
        document: secondaryDocument,
        onCreateDocument: onCreateSecondary,
        emptyTitle: 'Open pane 2',
      ),
      if (mode == DocumentWorkspaceMode.triple)
        _WorkspacePane(
          planningRepository: planningRepository,
          document: tertiaryDocument,
          onCreateDocument: onCreateTertiary,
          emptyTitle: 'Open pane 3',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final minPaneWidth = mode == DocumentWorkspaceMode.triple ? 420.0 : 520.0;
        final minWidth = minPaneWidth * panes.length;
        final content = SizedBox(
          width: constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth,
          child: Row(
            children: [
              for (var index = 0; index < panes.length; index++) ...[
                Expanded(child: panes[index]),
                if (index != panes.length - 1) const VerticalDivider(width: 1),
              ],
            ],
          ),
        );

        if (constraints.maxWidth < minWidth) {
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: content),
          );
        }
        return content;
      },
    );
  }
}

class _WorkspacePane extends StatelessWidget {
  final StudyPlanningRepository planningRepository;
  final WorkspaceDocument? document;
  final VoidCallback onCreateDocument;
  final String emptyTitle;

  const _WorkspacePane({
    required this.planningRepository,
    required this.document,
    required this.onCreateDocument,
    this.emptyTitle = 'Open a document',
  });

  @override
  Widget build(BuildContext context) {
    final activeDocument = document;
    if (activeDocument == null) {
      return _EmptyDocumentWorkspace(
        title: emptyTitle,
        message: 'Create a document or choose one from the selector above.',
        onCreateDocument: onCreateDocument,
      );
    }
    return WorkspaceDocumentEditorSurface(
      planningRepository: planningRepository,
      documentId: activeDocument.id,
      embedded: true,
      compactChrome: true,
    );
  }
}

class _EmptyDocumentWorkspace extends StatelessWidget {
  final String? projectTitle;
  final String title;
  final String message;
  final VoidCallback onCreateDocument;
  final VoidCallback? onCreateSet;

  const _EmptyDocumentWorkspace({
    this.projectTitle,
    this.title = 'No documents yet',
    this.message = 'Create a document to start writing, paste source material, build a template, or collect links.',
    required this.onCreateDocument,
    this.onCreateSet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_document, size: 52, color: theme.colorScheme.primary),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  projectTitle == null ? message : '$message\n\nThis document will be attached to “$projectTitle”.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onCreateDocument,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create document'),
                    ),
                    if (onCreateSet != null)
                      OutlinedButton.icon(
                        onPressed: onCreateSet,
                        icon: const Icon(Icons.view_week_outlined),
                        label: const Text('Create set'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickDocumentDialog extends StatefulWidget {
  final String? title;
  final String kind;
  final String? body;

  const _QuickDocumentDialog({
    this.title,
    required this.kind,
    this.body,
  });

  @override
  State<_QuickDocumentDialog> createState() => _QuickDocumentDialogState();
}

class _QuickDocumentDialogState extends State<_QuickDocumentDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _tagsController;
  late final TextEditingController _languageController;
  late final TextEditingController _sourceUrlController;
  late final TextEditingController _bodyController;
  late String _kind;
  _DocumentContentMode _contentMode = _DocumentContentMode.plain;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title ?? 'Untitled document');
    _tagsController = TextEditingController();
    _languageController = TextEditingController();
    _sourceUrlController = TextEditingController();
    _bodyController = TextEditingController(text: widget.body ?? '');
    _kind = widget.kind;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    _languageController.dispose();
    _sourceUrlController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      _DocumentDraft(
        title: title,
        kind: _kind,
        body: _bodyController.text,
        tags: _splitTags(_tagsController.text),
        language: _emptyToNull(_languageController.text),
        sourceUrl: _emptyToNull(_sourceUrlController.text),
        contentMode: _contentMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create document'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _kind,
                      decoration: const InputDecoration(labelText: 'Behavior', border: OutlineInputBorder()),
                      items: [
                        for (final kind in WorkspaceDocumentKind.values)
                          DropdownMenuItem(value: kind, child: Text(WorkspaceDocumentKind.label(kind))),
                      ],
                      onChanged: (value) => setState(() => _kind = value ?? WorkspaceDocumentKind.working),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<_DocumentContentMode>(
                      value: _contentMode,
                      decoration: const InputDecoration(labelText: 'Text mode', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: _DocumentContentMode.plain, child: Text('Plain text')),
                        DropdownMenuItem(value: _DocumentContentMode.markdown, child: Text('Markdown')),
                        DropdownMenuItem(value: _DocumentContentMode.latex, child: Text('LaTeX text')),
                      ],
                      onChanged: (value) => setState(() => _contentMode = value ?? _DocumentContentMode.plain),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagsController,
                      decoration: const InputDecoration(labelText: 'Tags', hintText: 'CV, job ad, English...', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _languageController,
                      decoration: const InputDecoration(labelText: 'Language / version', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sourceUrlController,
                decoration: const InputDecoration(labelText: 'Source link', hintText: 'Overleaf, Google Docs, job ad URL...', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Initial text',
                  hintText: 'Optional. Paste a job ad or start writing immediately.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _WorkspaceSetDialog extends StatefulWidget {
  final List<WorkspaceDocument> documents;

  const _WorkspaceSetDialog({required this.documents});

  @override
  State<_WorkspaceSetDialog> createState() => _WorkspaceSetDialogState();
}

class _WorkspaceSetDialogState extends State<_WorkspaceSetDialog> {
  final _nameController = TextEditingController();
  final _sourceBodyController = TextEditingController();
  final _referenceSourceUrlController = TextEditingController();
  bool _referenceIsLatex = true;
  static const String _createBlankReference = '__create_blank_reference__';
  String _referenceDocumentId = _createBlankReference;

  @override
  void dispose() {
    _nameController.dispose();
    _sourceBodyController.dispose();
    _referenceSourceUrlController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _WorkspaceSetDraft(
        name: name,
        sourceTitle: 'Job ad — $name',
        sourceBody: _sourceBodyController.text,
        referenceTitle: 'CV / reference — $name',
        referenceBody: _referenceIsLatex ? _defaultCvLatexTemplate(name) : '',
        referenceSourceUrl: _emptyToNull(_referenceSourceUrlController.text),
        referenceContentMode: _referenceIsLatex ? _DocumentContentMode.latex : _DocumentContentMode.plain,
        draftTitle: 'Personal letter — $name',
        referenceDocumentId: _referenceDocumentId == _createBlankReference ? null : _referenceDocumentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create workspace set'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Creates a three-pane workspace: source material, reference document, and draft. For job search this becomes job ad, CV/reference, and personal letter.'),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Set name', hintText: 'Ministry of Finance application', border: OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _referenceDocumentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reference document', helperText: 'Optional. Pick an existing CV/template or let the app create a blank reference document.', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String>(value: _createBlankReference, child: Text('Create blank reference document')),
                  for (final document in widget.documents)
                    DropdownMenuItem<String>(value: document.id, child: Text(document.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _referenceDocumentId = value ?? _createBlankReference),
              ),
              if (_referenceDocumentId == _createBlankReference) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _referenceSourceUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Reference source link',
                    hintText: 'Optional Overleaf link, Google Docs link, or source URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _referenceIsLatex,
                  onChanged: (value) => setState(() => _referenceIsLatex = value),
                  title: const Text('Create reference as LaTeX text'),
                  subtitle: const Text('Useful for CVs that are compiled in Overleaf.'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _sourceBodyController,
                minLines: 8,
                maxLines: 14,
                decoration: const InputDecoration(labelText: 'Source text', hintText: 'Optional. Paste the job ad, assignment brief, or source material here.', alignLabelWithHint: true, border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create set')),
      ],
    );
  }
}

class _DocumentDraft {
  final String title;
  final String kind;
  final String body;
  final List<String> tags;
  final String? language;
  final String? sourceUrl;
  final _DocumentContentMode contentMode;

  const _DocumentDraft({
    required this.title,
    required this.kind,
    required this.body,
    required this.tags,
    required this.language,
    required this.sourceUrl,
    required this.contentMode,
  });
}

class _WorkspaceSetDraft {
  final String name;
  final String sourceTitle;
  final String sourceBody;
  final String referenceTitle;
  final String referenceBody;
  final String? referenceSourceUrl;
  final _DocumentContentMode referenceContentMode;
  final String draftTitle;
  final String? referenceDocumentId;

  const _WorkspaceSetDraft({
    required this.name,
    required this.sourceTitle,
    required this.sourceBody,
    required this.referenceTitle,
    required this.referenceBody,
    required this.referenceSourceUrl,
    required this.referenceContentMode,
    required this.draftTitle,
    required this.referenceDocumentId,
  });
}


String _defaultCvLatexTemplate(String name) {
  final safeName = name.trim().isEmpty ? 'Application' : name.trim();
  return r'''% CV / reference source for @name
% This template intentionally uses the source-aware CV macros supported by the editor.
\section*{Profile}
Write a concise profile tailored to @name.

\section*{Technical Skills}
\skillrow{Core}{Add your strongest role-relevant skills here}
\skillrow{Tools}{Add tools, frameworks, methods, or domain knowledge}

\section*{Professional Experience}
\role
{Role title}
{Dates}
{Organization}
{Location}
{\begin{itemize}
\item Add one quantified, job-relevant contribution.
\item Add one collaboration, responsibility, or impact bullet.
\end{itemize}}

\section*{Education}
\education
{Degree or programme}
{Dates}
{Institution}
{Location}
{Relevant coursework, thesis, or distinction}

\section*{Projects}
\project
{Project name}
{Context / technology}
{Describe why this project is relevant to the target role.}
'''.replaceAll('@name', safeName);
}


enum _DocumentContentMode { plain, markdown, latex }

List<String> _splitTags(String value) => value
    .split(',')
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toList(growable: false);

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
