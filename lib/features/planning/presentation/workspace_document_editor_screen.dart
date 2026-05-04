import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import '../data/study_planning_repository.dart';
import 'latex_document_tools.dart';
import 'workspace_document_exporter.dart';

class WorkspaceDocumentEditorScreen extends StatelessWidget {
  final StudyPlanningRepository planningRepository;
  final String documentId;

  const WorkspaceDocumentEditorScreen({
    super.key,
    required this.planningRepository,
    required this.documentId,
  });

  @override
  Widget build(BuildContext context) {
    return WorkspaceDocumentEditorSurface(
      planningRepository: planningRepository,
      documentId: documentId,
    );
  }
}

class WorkspaceDocumentEditorSurface extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final String documentId;
  final bool embedded;
  final bool compactChrome;
  final VoidCallback? onClose;

  const WorkspaceDocumentEditorSurface({
    super.key,
    required this.planningRepository,
    required this.documentId,
    this.embedded = false,
    this.compactChrome = false,
    this.onClose,
  });

  @override
  State<WorkspaceDocumentEditorSurface> createState() => _WorkspaceDocumentEditorSurfaceState();
}

class _WorkspaceDocumentEditorSurfaceState extends State<WorkspaceDocumentEditorSurface> {
  final _titleController = TextEditingController();
  final _tagsController = TextEditingController();
  final _languageController = TextEditingController();
  final _sourceUrlController = TextEditingController();
  final _bodyController = TextEditingController();
  final _bodyFocusNode = FocusNode(debugLabel: 'WorkspaceDocumentBody');

  Timer? _autosaveDebounce;
  String _kind = WorkspaceDocumentKind.working;
  _DocumentContentMode _contentMode = _DocumentContentMode.plain;
  LatexWorkspaceMode _latexMode = LatexWorkspaceMode.source;
  LatexCompileResult? _latexCompileResult;
  bool _isCompilingLatex = false;
  String? _loadedDocumentId;
  String? _lastSavedFingerprint;
  bool _isSaving = false;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_markDirtyAndScheduleSave);
    _tagsController.addListener(_markDirtyAndScheduleSave);
    _languageController.addListener(_markDirtyAndScheduleSave);
    _sourceUrlController.addListener(_markDirtyAndScheduleSave);
    _bodyController.addListener(_markDirtyAndScheduleSave);
  }

  @override
  void didUpdateWidget(covariant WorkspaceDocumentEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId) {
      _autosaveDebounce?.cancel();
      _loadedDocumentId = null;
      _lastSavedFingerprint = null;
      _isDirty = false;
    }
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    _titleController.removeListener(_markDirtyAndScheduleSave);
    _tagsController.removeListener(_markDirtyAndScheduleSave);
    _languageController.removeListener(_markDirtyAndScheduleSave);
    _sourceUrlController.removeListener(_markDirtyAndScheduleSave);
    _bodyController.removeListener(_markDirtyAndScheduleSave);
    _titleController.dispose();
    _tagsController.dispose();
    _languageController.dispose();
    _sourceUrlController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _loadDocument(WorkspaceDocument document) {
    if (_loadedDocumentId == document.id) return;
    _loadedDocumentId = document.id;
    _latexMode = LatexWorkspaceMode.source;
    _latexCompileResult = null;
    _titleController.text = document.title;
    _tagsController.text = document.tags.where((tag) => !tag.startsWith('mode:') && !tag.startsWith('pdf:')).join(', ');
    _languageController.text = document.language ?? '';
    _sourceUrlController.text = document.sourceUrl ?? '';
    _bodyController.text = document.body;
    _kind = document.kind;
    _contentMode = _contentModeFromTags(document.tags);
    _lastSavedFingerprint = _fingerprint();
    _isDirty = false;
  }

  String _fingerprint() {
    return [
      _titleController.text.trim(),
      _kind,
      _contentMode.name,
      _tagsController.text.trim(),
      _languageController.text.trim(),
      _sourceUrlController.text.trim(),
      _bodyController.text,
    ].join('\u{1f}');
  }

  void _markDirtyAndScheduleSave() {
    if (_loadedDocumentId == null) return;
    final nextFingerprint = _fingerprint();
    final dirty = nextFingerprint != _lastSavedFingerprint;
    if (_isDirty != dirty && mounted) setState(() => _isDirty = dirty);
    if (!dirty) return;
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(_save(showSnackBar: false));
    });
  }

  Future<void> _save({bool snapshot = false, bool showSnackBar = true}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _isSaving) return;
    _autosaveDebounce?.cancel();
    setState(() => _isSaving = true);
    await widget.planningRepository.updateDocument(
      documentId: widget.documentId,
      title: title,
      kind: _kind,
      body: _bodyController.text,
      tags: _saveTags(),
      language: _emptyToNull(_languageController.text),
      sourceUrl: _emptyToNull(_sourceUrlController.text),
      saveSnapshot: snapshot,
      snapshotLabel: snapshot ? 'Snapshot ${_formatDateTime(DateTime.now())}' : null,
    );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isDirty = false;
      _lastSavedFingerprint = _fingerprint();
    });
    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snapshot ? 'Saved document snapshot.' : 'Saved document.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _archive(WorkspaceDocument document) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text('Remove “${document.title}” from the library?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.planningRepository.archiveDocument(document.id);
    if (!mounted) return;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _setKind(String value) {
    setState(() => _kind = value);
    _markDirtyAndScheduleSave();
  }

  void _setContentMode(_DocumentContentMode value) {
    setState(() {
      _contentMode = value;
      if (value != _DocumentContentMode.latex) {
        _latexMode = LatexWorkspaceMode.source;
        _latexCompileResult = null;
      }
    });
    _markDirtyAndScheduleSave();
  }

  Future<void> _compileLatex() async {
    if (_contentMode != _DocumentContentMode.latex || _isCompilingLatex) return;
    await _save(showSnackBar: false);
    if (!mounted) return;
    setState(() => _isCompilingLatex = true);
    final result = await LatexCompilerService.compile(
      title: _titleController.text.trim(),
      source: _bodyController.text,
    );
    if (!mounted) return;
    setState(() {
      _isCompilingLatex = false;
      _latexCompileResult = result;
      _latexMode = result.success ? LatexWorkspaceMode.pdf : LatexWorkspaceMode.split;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? 'Compiled LaTeX PDF.' : 'LaTeX compile failed. See the PDF/log pane.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInspector(WorkspaceDocument document) {
    showDialog<void>(
      context: context,
      builder: (context) => _DocumentInspectorDialog(
        document: document,
        tagsController: _tagsController,
        languageController: _languageController,
        sourceUrlController: _sourceUrlController,
      ),
    );
  }

  String? _attachedPdfPath(List<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith('pdf:')) return tag.substring(4);
    }
    return null;
  }

  String? _currentAttachedPdfPath() {
    final document = widget.planningRepository.documentById(widget.documentId);
    return document == null ? null : _attachedPdfPath(document.tags);
  }

  List<String> _saveTags({String? attachedPdfPath}) {
    final tags = _splitTags(_tagsController.text);
    if (_contentMode != _DocumentContentMode.plain) tags.add('mode:${_contentMode.name}');
    final pdfPath = attachedPdfPath ?? _currentAttachedPdfPath();
    if (pdfPath != null && pdfPath.trim().isNotEmpty) tags.add('pdf:${pdfPath.trim()}');
    return tags;
  }

  Future<void> _exportPdf() async {
    await _save(showSnackBar: false);
    final path = await WorkspaceDocumentExporter.exportPlainTextPdf(
      title: _titleController.text,
      body: _bodyController.text,
      codeLike: _contentMode == _DocumentContentMode.latex,
    );
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported PDF to $path'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _exportSourceFile() async {
    await _save(showSnackBar: false);
    final extension = _contentMode == _DocumentContentMode.latex
        ? 'tex'
        : _contentMode == _DocumentContentMode.markdown
            ? 'md'
            : 'txt';
    final path = await WorkspaceDocumentExporter.exportTextFile(
      title: _titleController.text,
      body: _bodyController.text,
      extension: extension,
      dialogTitle: 'Export .$extension file',
    );
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported .$extension to $path'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _attachExportedPdf() async {
    final path = await WorkspaceDocumentExporter.pickPdfAttachment();
    if (path == null) return;
    await widget.planningRepository.updateDocument(
      documentId: widget.documentId,
      tags: _saveTags(attachedPdfPath: path),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Attached exported PDF: $path'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _copySourceLink() async {
    final link = _sourceUrlController.text.trim();
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No source link is stored on this document.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied source link.'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openAttachedPdf(WorkspaceDocument document) async {
    final path = _attachedPdfPath(document.tags);
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No exported PDF is attached yet.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
      } else {
        await Clipboard.setData(ClipboardData(text: path));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the PDF. Copied the file path instead.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.planningRepository,
      builder: (context, _) {
        final document = widget.planningRepository.documentById(widget.documentId);
        if (document == null) {
          final missingBody = const Center(child: Text('Document not found.'));
          if (widget.embedded) return missingBody;
          return Scaffold(appBar: AppBar(title: const Text('Document')), body: missingBody);
        }
        _loadDocument(document);

        final isLatex = _contentMode == _DocumentContentMode.latex;
        final content = Column(
          children: [
            _DocumentEditorToolbar(
              embedded: widget.embedded,
              compact: widget.compactChrome,
              isSaving: _isSaving,
              isDirty: _isDirty,
              kind: _kind,
              contentMode: _contentMode,
              document: document,
              onKindChanged: _setKind,
              onContentModeChanged: _setContentMode,
              onSave: () => _save(),
              onSnapshot: () => _save(snapshot: true),
              onArchive: () => _archive(document),
              onInspector: () => _showInspector(document),
              onExportPdf: _exportPdf,
              onExportSource: _exportSourceFile,
              onAttachPdf: _attachExportedPdf,
              onOpenAttachedPdf: () => _openAttachedPdf(document),
              onCopySourceLink: _copySourceLink,
              onClose: widget.onClose,
            ),
            if (isLatex)
              LatexModeBar(
                mode: _latexMode,
                onModeChanged: (mode) => setState(() => _latexMode = mode),
                onCompile: _compileLatex,
                isCompiling: _isCompilingLatex,
                compileResult: _latexCompileResult,
              ),
            Expanded(
              child: isLatex
                  ? _LatexDocumentSurface(
                      document: document,
                      titleController: _titleController,
                      bodyController: _bodyController,
                      bodyFocusNode: _bodyFocusNode,
                      embedded: widget.embedded,
                      compact: widget.compactChrome,
                      mode: _latexMode,
                      compileResult: _latexCompileResult,
                      isCompiling: _isCompilingLatex,
                      onCompile: _compileLatex,
                    )
                  : _DocumentWritingSurface(
                      document: document,
                      titleController: _titleController,
                      bodyController: _bodyController,
                      bodyFocusNode: _bodyFocusNode,
                      embedded: widget.embedded,
                      compact: widget.compactChrome,
                      contentMode: _contentMode,
                    ),
            ),
          ],
        );

        if (widget.embedded) return content;

        return Scaffold(
          appBar: AppBar(title: Text(document.title)),
          body: content,
        );
      },
    );
  }
}

class _DocumentEditorToolbar extends StatelessWidget {
  final bool embedded;
  final bool compact;
  final bool isSaving;
  final bool isDirty;
  final String kind;
  final _DocumentContentMode contentMode;
  final WorkspaceDocument document;
  final ValueChanged<String> onKindChanged;
  final ValueChanged<_DocumentContentMode> onContentModeChanged;
  final VoidCallback onSave;
  final VoidCallback onSnapshot;
  final VoidCallback onArchive;
  final VoidCallback onInspector;
  final VoidCallback onExportPdf;
  final VoidCallback onExportSource;
  final VoidCallback onAttachPdf;
  final VoidCallback onOpenAttachedPdf;
  final VoidCallback onCopySourceLink;
  final VoidCallback? onClose;

  const _DocumentEditorToolbar({
    required this.embedded,
    required this.compact,
    required this.isSaving,
    required this.isDirty,
    required this.kind,
    required this.contentMode,
    required this.document,
    required this.onKindChanged,
    required this.onContentModeChanged,
    required this.onSave,
    required this.onSnapshot,
    required this.onArchive,
    required this.onInspector,
    required this.onExportPdf,
    required this.onExportSource,
    required this.onAttachPdf,
    required this.onOpenAttachedPdf,
    required this.onCopySourceLink,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = isSaving
        ? 'Saving'
        : isDirty
            ? 'Unsaved'
            : 'Saved';
    return Material(
      color: theme.colorScheme.surface,
      elevation: embedded ? 0 : 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 14, compact ? 6 : 8, compact ? 6 : 14, compact ? 6 : 8),
        child: Row(
          children: [
            Icon(_iconForKind(kind), size: compact ? 18 : 21, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                document.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Tooltip(
              message: statusLabel,
              child: Icon(
                isSaving
                    ? Icons.sync_rounded
                    : isDirty
                        ? Icons.circle_outlined
                        : Icons.check_circle_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(statusLabel, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: 'Document actions',
              onSelected: (value) {
                switch (value) {
                  case 'save':
                    onSave();
                    break;
                  case 'snapshot':
                    onSnapshot();
                    break;
                  case 'inspector':
                    onInspector();
                    break;
                  case 'exportPdf':
                    onExportPdf();
                    break;
                  case 'exportSource':
                    onExportSource();
                    break;
                  case 'attachPdf':
                    onAttachPdf();
                    break;
                  case 'openPdf':
                    onOpenAttachedPdf();
                    break;
                  case 'copyLink':
                    onCopySourceLink();
                    break;
                  case 'remove':
                    onArchive();
                    break;
                  default:
                    if (value.startsWith('kind:')) onKindChanged(value.substring(5));
                    if (value.startsWith('mode:')) onContentModeChanged(_contentModeFromName(value.substring(5)));
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'save', child: ListTile(leading: Icon(Icons.save_outlined), title: Text('Save'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'snapshot', child: ListTile(leading: Icon(Icons.history_rounded), title: Text('Save snapshot'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'inspector', child: ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('Details & versions'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'exportPdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Export PDF'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'exportSource', child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Export text / LaTeX'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'attachPdf', child: ListTile(leading: Icon(Icons.attach_file_rounded), title: Text('Attach exported PDF'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'openPdf', child: ListTile(leading: Icon(Icons.open_in_new_rounded), title: Text('Open attached PDF'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'copyLink', child: ListTile(leading: Icon(Icons.link_rounded), title: Text('Copy source link'), contentPadding: EdgeInsets.zero)),
                const PopupMenuDivider(),
                for (final value in WorkspaceDocumentKind.values)
                  PopupMenuItem(
                    value: 'kind:$value',
                    child: ListTile(
                      leading: Icon(value == WorkspaceDocumentKind.normalize(kind) ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                      title: Text(WorkspaceDocumentKind.label(value)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuDivider(),
                for (final value in _DocumentContentMode.values)
                  PopupMenuItem(
                    value: 'mode:${value.name}',
                    child: ListTile(
                      leading: Icon(value == contentMode ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                      title: Text(value.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'remove', child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Remove document'), contentPadding: EdgeInsets.zero)),
              ],
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Close document',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _DocumentWritingSurface extends StatelessWidget {
  final WorkspaceDocument document;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final FocusNode bodyFocusNode;
  final bool embedded;
  final bool compact;
  final _DocumentContentMode contentMode;

  const _DocumentWritingSurface({
    required this.document,
    required this.titleController,
    required this.bodyController,
    required this.bodyFocusNode,
    required this.embedded,
    required this.compact,
    required this.contentMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCodeLike = contentMode == _DocumentContentMode.latex;
    final bodyStyle = (isCodeLike ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)?.copyWith(
      height: isCodeLike ? 1.35 : 1.55,
      fontSize: isCodeLike ? 14.5 : (compact ? 15.0 : 16.2),
      fontFamily: isCodeLike ? 'Consolas' : null,
      color: theme.colorScheme.onSurface,
    );

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = embedded ? 14.0 : 32.0;
          final vertical = embedded ? 14.0 : 28.0;
          final pagePadding = embedded ? 26.0 : 48.0;
          final maxWidth = embedded ? math.min(constraints.maxWidth, 680.0) : 820.0;
          final minPageHeight = embedded ? math.max(680.0, constraints.maxHeight - (vertical * 2)) : 960.0;
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(embedded ? 12 : 18),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(180)),
                      boxShadow: [
                        if (!embedded)
                          BoxShadow(
                            color: Colors.black.withAlpha(14),
                            blurRadius: 26,
                            offset: const Offset(0, 14),
                          ),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minPageHeight),
                      child: Padding(
                        padding: EdgeInsets.all(pagePadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (document.sourceUrl != null && document.sourceUrl!.trim().isNotEmpty) ...[
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withAlpha(85),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.primary.withAlpha(55)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(Icons.link_rounded, size: 16, color: theme.colorScheme.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          document.sourceUrl!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextField(
                              controller: titleController,
                            textInputAction: TextInputAction.next,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.25,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Untitled document',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _TinyDocumentChip(label: WorkspaceDocumentKind.label(document.kind)),
                                _TinyDocumentChip(label: contentMode.label),
                                _TinyDocumentChip(label: _wordCountLabel(bodyController.text)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          TextField(
                            controller: bodyController,
                            focusNode: bodyFocusNode,
                            keyboardType: TextInputType.multiline,
                            minLines: embedded ? 24 : 32,
                            maxLines: null,
                            style: bodyStyle,
                            decoration: InputDecoration(
                              hintText: _bodyHintForKind(document.kind, contentMode),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}


class _LatexDocumentSurface extends StatelessWidget {
  final WorkspaceDocument document;
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final FocusNode bodyFocusNode;
  final bool embedded;
  final bool compact;
  final LatexWorkspaceMode mode;
  final LatexCompileResult? compileResult;
  final bool isCompiling;
  final VoidCallback onCompile;

  const _LatexDocumentSurface({
    required this.document,
    required this.titleController,
    required this.bodyController,
    required this.bodyFocusNode,
    required this.embedded,
    required this.compact,
    required this.mode,
    required this.compileResult,
    required this.isCompiling,
    required this.onCompile,
  });

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case LatexWorkspaceMode.preview:
        return _latexPreview();
      case LatexWorkspaceMode.split:
        return LayoutBuilder(
          builder: (context, constraints) {
            const minPaneWidth = 460.0;
            final content = SizedBox(
              width: constraints.maxWidth < minPaneWidth * 2 ? minPaneWidth * 2 : constraints.maxWidth,
              child: Row(
                children: [
                  Expanded(child: _sourceEditor()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _latexPreview()),
                ],
              ),
            );
            if (constraints.maxWidth < minPaneWidth * 2) {
              return Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: content),
              );
            }
            return content;
          },
        );
      case LatexWorkspaceMode.pdf:
        return LatexCompiledPdfPreview(
          result: compileResult,
          isCompiling: isCompiling,
          onCompile: onCompile,
        );
      case LatexWorkspaceMode.source:
        return _sourceEditor();
    }
  }

  Widget _sourceEditor() {
    return _DocumentWritingSurface(
      document: document,
      titleController: titleController,
      bodyController: bodyController,
      bodyFocusNode: bodyFocusNode,
      embedded: embedded,
      compact: compact,
      contentMode: _DocumentContentMode.latex,
    );
  }

  Widget _latexPreview() {
    return AnimatedBuilder(
      animation: bodyController,
      builder: (context, _) => LatexPseudoPreview(
        source: bodyController.text,
        title: titleController.text,
        embedded: embedded,
      ),
    );
  }
}

class _TinyDocumentChip extends StatelessWidget {
  final String label;

  const _TinyDocumentChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

class _DocumentInspectorDialog extends StatelessWidget {
  final WorkspaceDocument document;
  final TextEditingController tagsController;
  final TextEditingController languageController;
  final TextEditingController sourceUrlController;

  const _DocumentInspectorDialog({
    required this.document,
    required this.tagsController,
    required this.languageController,
    required this.sourceUrlController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Document details'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(labelText: 'Tags', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: languageController,
                      decoration: const InputDecoration(labelText: 'Language / version', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: sourceUrlController,
                      decoration: const InputDecoration(labelText: 'Source link', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Snapshots', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (document.versions.isEmpty)
                const Text('No snapshots yet.')
              else
                for (final version in document.versions.reversed.take(12))
                  Card(
                    elevation: 0,
                    color: version.id == document.currentVersionId ? theme.colorScheme.primaryContainer.withAlpha(120) : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                    child: ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: Text(version.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_formatDateTime(version.createdAt)),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

enum _DocumentContentMode { plain, markdown, latex }

extension _DocumentContentModeLabel on _DocumentContentMode {
  String get label => _contentModeLabel(this);
}

String _contentModeLabel(_DocumentContentMode mode) {
  switch (mode) {
    case _DocumentContentMode.markdown:
      return 'Markdown';
    case _DocumentContentMode.latex:
      return 'LaTeX text';
    case _DocumentContentMode.plain:
    default:
      return 'Plain text';
  }
}

_DocumentContentMode _contentModeFromName(String? value) {
  switch (value) {
    case 'markdown':
      return _DocumentContentMode.markdown;
    case 'latex':
      return _DocumentContentMode.latex;
    case 'plain':
    default:
      return _DocumentContentMode.plain;
  }
}

_DocumentContentMode _contentModeFromTags(List<String> tags) {
  for (final tag in tags) {
    if (tag.startsWith('mode:')) return _contentModeFromName(tag.substring(5));
  }
  return _DocumentContentMode.plain;
}

IconData _iconForKind(String kind) {
  switch (WorkspaceDocumentKind.normalize(kind)) {
    case WorkspaceDocumentKind.source:
      return Icons.article_outlined;
    case WorkspaceDocumentKind.template:
      return Icons.copy_all_outlined;
    case WorkspaceDocumentKind.link:
      return Icons.link_rounded;
    case WorkspaceDocumentKind.collection:
      return Icons.folder_open_rounded;
    case WorkspaceDocumentKind.working:
    default:
      return Icons.description_outlined;
  }
}

List<String> _splitTags(String value) => value
    .split(',')
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toList(growable: true);

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _wordCountLabel(String text) {
  final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).where((word) => word.trim().isNotEmpty).length;
  return words == 1 ? '1 word' : '$words words';
}

String _bodyHintForKind(String kind, _DocumentContentMode mode) {
  if (mode == _DocumentContentMode.latex) {
    return r'Paste or write LaTeX here. For now this is stored and edited as text; compilation/export can be wired in later.';
  }
  if (mode == _DocumentContentMode.markdown) {
    return 'Write Markdown here. Export/preview can be added later.';
  }
  switch (WorkspaceDocumentKind.normalize(kind)) {
    case WorkspaceDocumentKind.source:
      return 'Paste the source material here: a job ad, assignment brief, article excerpt, lecture instructions, or other reference text.';
    case WorkspaceDocumentKind.template:
      return 'Write the reusable structure here. You can duplicate or copy from this later.';
    case WorkspaceDocumentKind.link:
      return 'Add notes about what this link is for, what to remember, or how it connects to the project.';
    case WorkspaceDocumentKind.collection:
      return 'Describe what belongs in this collection and how the documents relate.';
    case WorkspaceDocumentKind.working:
    default:
      return 'Start writing…';
  }
}
