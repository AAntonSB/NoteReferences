import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:super_editor/super_editor.dart';

import '../../notes/data/note_repository.dart';
import '../../tags/data/tag_repository.dart';

const String _kMathBlockType = 'documentMathBlock';
const String _kDocumentTodoBlockType = 'documentTodoBlock';
const String _kPdfReferenceScheme = 'pdfref';
const String _kKnowledgeTagScheme = 'knowledgetag';

final RegExp _knowledgeTagRegex = RegExp(r'(^|\s)#([^\s#.,;:!?()\[\]{}<>]+)');

Set<String> _extractKnowledgeTagNames(String source) {
  final names = <String>{};
  for (final match in _knowledgeTagRegex.allMatches(source)) {
    final name = match.group(2)?.trim();
    if (name == null || name.isEmpty) continue;
    names.add(name);
  }
  return names;
}

void _applyKnowledgeTagAttributions(AttributedText attributedText) {
  _clearKnowledgeTagAttributions(attributedText);

  final text = attributedText.toPlainText();
  for (final match in _knowledgeTagRegex.allMatches(text)) {
    final prefix = match.group(1) ?? '';
    final tagName = match.group(2)?.trim();
    if (tagName == null || tagName.isEmpty) continue;

    final start = match.start + prefix.length;
    final end = match.end;
    if (start < 0 || end <= start || end > text.length) continue;

    attributedText.addAttribution(
      LinkAttribution.fromUri(
        Uri.parse('$_kKnowledgeTagScheme:${Uri.encodeComponent(tagName)}'),
      ),
      SpanRange(start, end - 1),
    );
  }
}

void _clearKnowledgeTagAttributions(AttributedText attributedText) {
  final removals = <_KnowledgeTagAttributionRemoval>[];

  for (final span in attributedText.computeAttributionSpans()) {
    for (final attribution in span.attributions) {
      if (attribution is LinkAttribution &&
          attribution.uri?.scheme == _kKnowledgeTagScheme) {
        removals.add(
          _KnowledgeTagAttributionRemoval(
            attribution: attribution,
            start: span.start,
            end: span.end,
          ),
        );
      }
    }
  }

  for (final removal in removals) {
    attributedText.removeAttribution(
      removal.attribution,
      SpanRange(removal.start, removal.end),
    );
  }
}

class _KnowledgeTagAttributionRemoval {
  final LinkAttribution attribution;
  final int start;
  final int end;

  const _KnowledgeTagAttributionRemoval({
    required this.attribution,
    required this.start,
    required this.end,
  });
}

void _applyKnowledgeTagAttributionsToDocument(MutableDocument document) {
  for (final node in document) {
    if (node is! ParagraphNode) continue;
    _applyKnowledgeTagAttributions(node.text);
  }
}

String _normalizeDocumentTodoPriority(String? value) {
  switch (value?.trim()) {
    case kTodoPriorityLow:
      return kTodoPriorityLow;
    case kTodoPriorityHigh:
      return kTodoPriorityHigh;
    case kTodoPriorityMedium:
    default:
      return kTodoPriorityMedium;
  }
}

Color _documentTodoPriorityColor(String priority) {
  return Color(TodoItem.colorForPriority(priority));
}

class PdfCopiedReference {
  final String documentId;
  final int pageNumber;
  final String selectedText;
  final List<PdfSourceRect> sourceRects;
  final DateTime copiedAt;

  const PdfCopiedReference({
    required this.documentId,
    required this.pageNumber,
    required this.selectedText,
    required this.sourceRects,
    required this.copiedAt,
  });

  bool get isValid {
    return documentId.trim().isNotEmpty &&
        pageNumber > 0 &&
        selectedText.trim().isNotEmpty &&
        sourceRects.any((rect) => rect.isValid);
  }
}

class DocumentNoteReferenceInsertionRequest {
  final int requestId;
  final PdfCopiedReference reference;

  const DocumentNoteReferenceInsertionRequest({
    required this.requestId,
    required this.reference,
  });
}

class PdfDocumentNotesPanel extends StatefulWidget {
  final NoteRepository noteRepository;
  final String documentId;
  final String documentTitle;
  final String? selectedText;
  final List<PdfSourceRect> selectedSourceRects;
  final ValueListenable<PdfCopiedReference?> copiedReferenceListenable;
  final ValueListenable<DocumentNoteReferenceInsertionRequest?>?
  externalReferenceInsertionListenable;
  final ValueChanged<DocumentNotePdfReference> onJumpToReference;

  const PdfDocumentNotesPanel({
    super.key,
    required this.noteRepository,
    required this.documentId,
    required this.documentTitle,
    required this.selectedText,
    required this.selectedSourceRects,
    required this.copiedReferenceListenable,
    required this.onJumpToReference,
    this.externalReferenceInsertionListenable,
  });

  @override
  State<PdfDocumentNotesPanel> createState() => _PdfDocumentNotesPanelState();
}

class _PdfDocumentNotesPanelState extends State<PdfDocumentNotesPanel> {
  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, _SuperDocumentEditingSession> _sessions = {};
  final Map<String, Timer> _saveDebounceByNoteId = {};
  final Map<String, String> _lastSavedFingerprintByNoteId = {};
  final Map<String, String> _lastObservedFingerprintByNoteId = {};
  Timer? _autosavePollTimer;
  late final TagRepository _tagRepository;

  List<StructuredDocumentNote> _latestNotes = const [];
  List<TodoItem> _latestTodos = const [];
  bool _todoSyncScheduled = false;
  String? _selectedNoteId;
  bool _creatingNote = false;
  int? _lastExternalInsertionRequestId;

  bool get _hasPdfSelection {
    final selectedText = widget.selectedText?.trim();
    return selectedText != null &&
        selectedText.isNotEmpty &&
        widget.selectedSourceRects.any((rect) => rect.isValid);
  }

  @override
  void initState() {
    super.initState();
    _tagRepository = TagRepository(database: widget.noteRepository.database);
    _startStructuredDocumentAutosavePolling();
    widget.externalReferenceInsertionListenable?.addListener(
      _handleExternalReferenceInsertion,
    );
    unawaited(_ensureInitialDocumentNote());
  }

  @override
  void didUpdateWidget(covariant PdfDocumentNotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.documentId != widget.documentId) {
      _selectedNoteId = null;
      _latestNotes = const [];
      _latestTodos = const [];
      _todoSyncScheduled = false;
      _lastExternalInsertionRequestId = null;
      _disposeEditorState();
      unawaited(_ensureInitialDocumentNote());
    }

    if (oldWidget.externalReferenceInsertionListenable !=
        widget.externalReferenceInsertionListenable) {
      oldWidget.externalReferenceInsertionListenable?.removeListener(
        _handleExternalReferenceInsertion,
      );
      widget.externalReferenceInsertionListenable?.addListener(
        _handleExternalReferenceInsertion,
      );
    }
  }

  @override
  void dispose() {
    widget.externalReferenceInsertionListenable?.removeListener(
      _handleExternalReferenceInsertion,
    );
    _disposeEditorState();
    super.dispose();
  }

  void _disposeEditorState() {
    _autosavePollTimer?.cancel();
    _autosavePollTimer = null;

    for (final noteId in _sessions.keys.toList()) {
      unawaited(_saveStructuredDocumentNow(noteId, force: true));
    }

    for (final timer in _saveDebounceByNoteId.values) {
      timer.cancel();
    }
    for (final controller in _titleControllers.values) {
      controller.dispose();
    }
    for (final session in _sessions.values) {
      session.dispose();
    }
    _saveDebounceByNoteId.clear();
    _titleControllers.clear();
    _sessions.clear();
  }

  Future<void> _ensureInitialDocumentNote() async {
    await widget.noteRepository.ensureDefaultDocumentNote(
      documentId: widget.documentId,
      documentTitle: widget.documentTitle,
    );
  }

  void _handleExternalReferenceInsertion() {
    final request = widget.externalReferenceInsertionListenable?.value;
    if (request == null ||
        request.requestId == _lastExternalInsertionRequestId ||
        !request.reference.isValid) {
      return;
    }

    _lastExternalInsertionRequestId = request.requestId;
    unawaited(_insertCopiedReference(request.reference));
  }

  String? _effectiveSelectedNoteId() {
    final selectedId = _selectedNoteId;
    if (selectedId != null &&
        _latestNotes.any((note) => note.note.id == selectedId)) {
      return selectedId;
    }

    if (_latestNotes.isNotEmpty) {
      return _latestNotes.first.note.id;
    }

    return selectedId;
  }

  StructuredDocumentNote? _effectiveSelectedNote() {
    final id = _effectiveSelectedNoteId();
    if (id == null) return null;

    for (final note in _latestNotes) {
      if (note.note.id == id) return note;
    }

    return null;
  }

  Future<String> _ensureEditableNoteId() async {
    final existingId = _effectiveSelectedNoteId();
    if (existingId != null) return existingId;

    final note = await widget.noteRepository.ensureDefaultDocumentNote(
      documentId: widget.documentId,
      documentTitle: widget.documentTitle,
    );

    if (mounted) {
      setState(() {
        _selectedNoteId = note.note.id;
      });
    }

    return note.note.id;
  }

  Future<void> _createDocumentNote() async {
    if (_creatingNote) return;

    setState(() {
      _creatingNote = true;
    });

    try {
      final note = await widget.noteRepository.createDocumentNote(
        documentId: widget.documentId,
        title: 'Reading note ${_latestNotes.length + 1}',
      );

      if (!mounted) return;

      setState(() {
        _selectedNoteId = note.note.id;
      });
    } finally {
      if (mounted) {
        setState(() {
          _creatingNote = false;
        });
      }
    }
  }

  Future<void> _insertCurrentSelectionAsReference() async {
    final selectedText = widget.selectedText?.trim();
    final sourceRects = widget.selectedSourceRects
        .where((rect) => rect.isValid)
        .toList(growable: false);

    if (selectedText == null || selectedText.isEmpty || sourceRects.isEmpty) {
      return;
    }

    await _insertCopiedReference(
      PdfCopiedReference(
        documentId: widget.documentId,
        pageNumber: sourceRects.first.pageNumber,
        selectedText: selectedText,
        sourceRects: sourceRects,
        copiedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _insertCopiedReference(PdfCopiedReference reference) async {
    if (!reference.isValid) return;

    final noteId = await _ensureEditableNoteId();
    final session = _sessionForNoteId(noteId);

    final referenceId = _newReferenceId();
    final cleanSelectedText = _normalizePdfReferenceText(
      reference.selectedText,
    );
    final documentReference = DocumentNotePdfReference(
      documentId: reference.documentId,
      pageNumber: reference.pageNumber,
      selectedText: cleanSelectedText,
      sourceRects: reference.sourceRects.where((rect) => rect.isValid).toList(),
      citationLabel: 'p. ${reference.pageNumber}',
    );

    session.references[referenceId] = documentReference;

    final node = _paragraphNodeWithPdfReference(
      text: '“${documentReference.selectedText}” ',
      referenceLabel: documentReference.citationLabel,
      referenceId: referenceId,
    );

    _insertNodeNearSelection(session, node);
    await _saveStructuredDocumentNow(noteId);
    session.focusNode.requestFocus();
  }

  void _insertMathBlock(String noteId) {
    final session = _sessionForNoteId(noteId);
    final node = _MathBlockNode(
      id: Editor.createNodeId(),
      latex: r'\int_a^b f(x)\,dx',
    );

    _insertNodeNearSelection(session, node);
    _scheduleStructuredDocumentSave(noteId);
    session.focusNode.requestFocus();
  }

  Future<void> _insertTodoBlock(String noteId) async {
    final session = _sessionForNoteId(noteId);
    final nodeId = Editor.createNodeId();
    final todoId = await widget.noteRepository.createDocumentNoteTodo(
      documentId: widget.documentId,
      documentNoteId: noteId,
      documentNodeId: nodeId,
      title: 'New TODO',
    );

    final node = _TodoBlockNode(
      id: nodeId,
      todoId: todoId,
      title: 'New TODO',
      priority: kTodoPriorityMedium,
      isCompleted: false,
    );

    _insertNodeNearSelection(session, node);
    await _saveStructuredDocumentNow(noteId);
    session.focusNode.requestFocus();
  }

  ParagraphNode _paragraphNodeWithPdfReference({
    required String text,
    required String referenceLabel,
    required String referenceId,
  }) {
    final visibleReference = '[$referenceLabel]';
    final fullText = '$text$visibleReference';
    final attributedText = AttributedText(fullText);
    attributedText.addAttribution(
      LinkAttribution.fromUri(Uri.parse('$_kPdfReferenceScheme:$referenceId')),
      SpanRange(fullText.length - visibleReference.length, fullText.length - 1),
    );

    _applyKnowledgeTagAttributions(attributedText);
    return ParagraphNode(id: Editor.createNodeId(), text: attributedText);
  }

  void _insertNodeNearSelection(
    _SuperDocumentEditingSession session,
    DocumentNode node,
  ) {
    final selection = session.composer.selection;
    if (selection == null) {
      session.document.add(node);
      _selectEndOfNode(session, node);
      return;
    }

    final selectedNode = session.document.getNodeById(selection.extent.nodeId);
    final selectedNodeIndex = selectedNode == null
        ? -1
        : session.document.getNodeIndexById(selectedNode.id);

    if (selectedNodeIndex < 0 ||
        selectedNodeIndex >= session.document.nodeCount - 1) {
      session.document.add(node);
    } else {
      session.document.insertNodeAt(selectedNodeIndex + 1, node);
    }

    _selectEndOfNode(session, node);
  }

  void _selectEndOfNode(
    _SuperDocumentEditingSession session,
    DocumentNode node,
  ) {
    session.composer.setSelectionWithReason(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: node.id,
          nodePosition: node.endPosition,
        ),
      ),
    );
  }

  TextEditingController _titleControllerFor(StructuredDocumentNote note) {
    return _titleControllers.putIfAbsent(
      note.note.id,
      () => TextEditingController(text: note.displayTitle),
    );
  }

  _SuperDocumentEditingSession _sessionFor(StructuredDocumentNote note) {
    return _sessions.putIfAbsent(note.note.id, () {
      final session = _SuperDocumentEditingSession.fromNote(
        note,
        onDocumentChanged: () => _scheduleStructuredDocumentSave(note.note.id),
      );
      return session;
    });
  }

  _SuperDocumentEditingSession _sessionForNoteId(String noteId) {
    final existing = _sessions[noteId];
    if (existing != null) return existing;

    final note = _latestNotes
        .where((candidate) => candidate.note.id == noteId)
        .cast<StructuredDocumentNote?>()
        .firstOrNull;

    if (note != null) {
      return _sessionFor(note);
    }

    final session = _SuperDocumentEditingSession.empty(
      onDocumentChanged: () => _scheduleStructuredDocumentSave(noteId),
    );
    _sessions[noteId] = session;
    _rememberStructuredDocumentFingerprint(noteId, session);
    return session;
  }

  void _startStructuredDocumentAutosavePolling() {
    _autosavePollTimer?.cancel();
    _autosavePollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _pollStructuredDocumentAutosave();
    });
  }

  void _pollStructuredDocumentAutosave() {
    if (!mounted || _sessions.isEmpty) return;

    for (final entry in _sessions.entries) {
      final noteId = entry.key;
      final session = entry.value;

      if (!session.focusNode.hasFocus) {
        continue;
      }

      final fingerprint = _structuredDocumentFingerprint(session);
      final previous = _lastObservedFingerprintByNoteId[noteId];

      if (previous == fingerprint) {
        continue;
      }

      _lastObservedFingerprintByNoteId[noteId] = fingerprint;
      _scheduleStructuredDocumentSave(noteId);
    }
  }

  void _rememberStructuredDocumentFingerprint(
    String noteId,
    _SuperDocumentEditingSession session,
  ) {
    final fingerprint = _structuredDocumentFingerprint(session);
    _lastObservedFingerprintByNoteId[noteId] = fingerprint;
    _lastSavedFingerprintByNoteId[noteId] = fingerprint;
  }

  String _structuredDocumentFingerprint(_SuperDocumentEditingSession session) {
    _applyKnowledgeTagAttributionsToDocument(session.document);

    _applyKnowledgeTagAttributionsToDocument(session.document);

    final payload = _StructuredDocumentCodec.encode(
      document: session.document,
      references: session.references,
    );

    return '${payload.plainText.hashCode}:${payload.jsonText.hashCode}:'
        '${payload.plainText.length}:${payload.jsonText.length}';
  }

  void _scheduleStructuredDocumentSave(String noteId) {
    _saveDebounceByNoteId[noteId]?.cancel();
    _saveDebounceByNoteId[noteId] = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_saveStructuredDocumentNow(noteId)),
    );
  }

  Future<void> _saveStructuredDocumentNow(
    String noteId, {
    bool force = false,
  }) async {
    _saveDebounceByNoteId[noteId]?.cancel();
    _saveDebounceByNoteId.remove(noteId);

    final session = _sessions[noteId];
    if (session == null) return;

    final payload = _StructuredDocumentCodec.encode(
      document: session.document,
      references: session.references,
    );
    final fingerprint =
        '${payload.plainText.hashCode}:${payload.jsonText.hashCode}:'
        '${payload.plainText.length}:${payload.jsonText.length}';

    if (!force && _lastSavedFingerprintByNoteId[noteId] == fingerprint) {
      return;
    }

    await widget.noteRepository.updateStructuredDocumentNote(
      noteId: noteId,
      text: payload.plainText,
      contentJson: payload.jsonText,
    );

    await _tagRepository.syncKnowledgeTagsForTarget(
      targetType: kTagTargetDocumentNote,
      targetId: noteId,
      documentId: widget.documentId,
      tagNames: _extractKnowledgeTagNames(payload.plainText),
    );

    _lastSavedFingerprintByNoteId[noteId] = fingerprint;
    _lastObservedFingerprintByNoteId[noteId] = fingerprint;
  }

  String _newReferenceId() {
    return 'ref_${DateTime.now().microsecondsSinceEpoch}';
  }

  String _normalizePdfReferenceText(String value) {
    final text = value
        .replaceAll('\u00a0', ' ')
        .replaceAll('\u200b', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r'\s*([–—])\s*'), (match) {
          return ' ${match.group(1)} ';
        })
        .replaceAllMapped(RegExp(r'([,.;:!?])(?=\S)'), (match) {
          return '${match.group(1)} ';
        })
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (match) {
          return '${match.group(1)} ${match.group(2)}';
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return text.isEmpty ? value.trim() : text;
  }

  void _scheduleTodoBlockSync(List<TodoItem> todos) {
    _latestTodos = todos;

    if (_todoSyncScheduled) {
      return;
    }

    _todoSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _todoSyncScheduled = false;
      _syncTodoBlocksFromRepository(_latestTodos);
    });
  }

  void _syncTodoBlocksFromRepository(List<TodoItem> todos) {
    if (_sessions.isEmpty || todos.isEmpty) {
      return;
    }

    final documentTodos = <String, TodoItem>{
      for (final todo in todos)
        if (todo.sourceType == kTodoSourceDocumentNote) todo.id: todo,
    };

    if (documentTodos.isEmpty) {
      return;
    }

    for (final sessionEntry in _sessions.entries) {
      final session = sessionEntry.value;
      final nodes = [for (final node in session.document) node];

      for (final node in nodes) {
        if (node is! _TodoBlockNode) {
          continue;
        }

        final todo = documentTodos[node.todoId];
        if (todo == null) {
          continue;
        }

        final nextPriority = _normalizeDocumentTodoPriority(todo.priority);
        final hasChanges =
            node.title != todo.title ||
            node.priority != nextPriority ||
            node.isCompleted != todo.isCompleted ||
            node.deadline != todo.deadline;

        if (!hasChanges) {
          continue;
        }

        session.document.replaceNodeById(
          node.id,
          node.copyTodoBlockWith(
            title: todo.title,
            priority: nextPriority,
            isCompleted: todo.isCompleted,
            deadline: todo.deadline,
            clearDeadline: todo.deadline == null,
          ),
        );
      }
    }
  }

  Future<void> _openKnowledgeTagPicker(String noteId) async {
    final selectedTagName = await showDialog<String>(
      context: context,
      builder: (context) {
        return _KnowledgeTagPickerDialog(tagRepository: _tagRepository);
      },
    );

    if (selectedTagName == null || selectedTagName.trim().isEmpty) return;
    await _insertKnowledgeTagNearSelection(noteId, selectedTagName);
  }

  Future<void> _insertKnowledgeTagNearSelection(
    String noteId,
    String tagName,
  ) async {
    final tag = await _tagRepository.findOrCreateKnowledgeTag(tagName);
    final session = _sessionForNoteId(noteId);

    final text = '#${tag.name} ';
    final attributedText = AttributedText(text);
    _applyKnowledgeTagAttributions(attributedText);

    _insertNodeNearSelection(
      session,
      ParagraphNode(id: Editor.createNodeId(), text: attributedText),
    );

    _scheduleStructuredDocumentSave(noteId);
  }

  Future<void> _openKnowledgeMap({
    required List<StructuredDocumentNote> documentNotes,
    required ValueChanged<String> onOpenDocumentNote,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return _KnowledgeMapDialog(
          tagRepository: _tagRepository,
          documentId: widget.documentId,
          documentNotes: documentNotes,
          onOpenDocumentNote: onOpenDocumentNote,
        );
      },
    );
  }

  Future<void> _openKnowledgeTagBacklinks({
    required String tagName,
    required List<StructuredDocumentNote> documentNotes,
    required ValueChanged<String> onOpenDocumentNote,
  }) async {
    final normalizedTagName = tagName.trim().replaceFirst(RegExp(r'^#'), '');
    if (normalizedTagName.isEmpty || !mounted) return;

    final tag = await _tagRepository.findOrCreateKnowledgeTag(
      normalizedTagName,
    );
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return _KnowledgeTagBacklinksDialog(
          tag: tag,
          tagRepository: _tagRepository,
          documentId: widget.documentId,
          documentNotes: documentNotes,
          onOpenDocumentNote: onOpenDocumentNote,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TodoItem>>(
      stream: widget.noteRepository.watchTodos(
        documentId: widget.documentId,
        includeCompleted: true,
      ),
      builder: (context, todoSnapshot) {
        final todos = todoSnapshot.data ?? _latestTodos;
        _scheduleTodoBlockSync(todos);

        return StreamBuilder<List<StructuredDocumentNote>>(
          stream: widget.noteRepository.watchDocumentNotesForDocument(
            documentId: widget.documentId,
          ),
          builder: (context, snapshot) {
            final notes = snapshot.data ?? _latestNotes;
            _latestNotes = notes;

            if (_selectedNoteId == null && notes.isNotEmpty) {
              _selectedNoteId = notes.first.note.id;
            }

            final selectedNote = _effectiveSelectedNote();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DocumentNotesHeader(
                  notes: notes,
                  selectedNoteId: _effectiveSelectedNoteId(),
                  creatingNote: _creatingNote,
                  onSelectedNoteChanged: (noteId) {
                    final previousNoteId = _selectedNoteId;
                    if (previousNoteId != null) {
                      unawaited(
                        _saveStructuredDocumentNow(previousNoteId, force: true),
                      );
                    }

                    setState(() {
                      _selectedNoteId = noteId;
                    });
                  },
                  onCreateNote: _createDocumentNote,
                ),
                const Divider(height: 1),
                Expanded(
                  child: selectedNote == null
                      ? _EmptyDocumentNoteState(
                          onCreateNote: _createDocumentNote,
                        )
                      : _SuperDocumentEditor(
                          key: ValueKey(selectedNote.note.id),
                          note: selectedNote,
                          titleController: _titleControllerFor(selectedNote),
                          session: _sessionFor(selectedNote),
                          noteRepository: widget.noteRepository,
                          tagRepository: _tagRepository,
                          documentId: widget.documentId,
                          documentNotes: notes,
                          hasPdfSelection: _hasPdfSelection,
                          copiedReferenceListenable:
                              widget.copiedReferenceListenable,
                          onTitleChanged: (title) {
                            unawaited(
                              widget.noteRepository.updateDocumentNoteTitle(
                                noteId: selectedNote.note.id,
                                title: title,
                              ),
                            );
                          },
                          onAddMath: () {
                            _insertMathBlock(selectedNote.note.id);
                          },
                          onAddTodo: () {
                            unawaited(_insertTodoBlock(selectedNote.note.id));
                          },
                          onInsertKnowledgeTag: () {
                            unawaited(
                              _openKnowledgeTagPicker(selectedNote.note.id),
                            );
                          },
                          onInsertSelectionReference: () =>
                              unawaited(_insertCurrentSelectionAsReference()),
                          onPasteCopiedReference: () {
                            final copiedReference =
                                widget.copiedReferenceListenable.value;
                            if (copiedReference != null) {
                              unawaited(
                                _insertCopiedReference(copiedReference),
                              );
                            }
                          },
                          onOpenKnowledgeMap: () {
                            unawaited(
                              _openKnowledgeMap(
                                documentNotes: notes,
                                onOpenDocumentNote: (noteId) {
                                  setState(() {
                                    _selectedNoteId = noteId;
                                  });
                                },
                              ),
                            );
                          },
                          onJumpToReference: widget.onJumpToReference,
                          onKnowledgeTagTap: (tagName) {
                            unawaited(
                              _openKnowledgeTagBacklinks(
                                tagName: tagName,
                                documentNotes: notes,
                                onOpenDocumentNote: (noteId) {
                                  setState(() {
                                    _selectedNoteId = noteId;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

@immutable
class _MathBlockNode extends BlockNode {
  _MathBlockNode({required this.id, required this.latex, super.metadata}) {
    initAddToMetadata({
      'documentNodeType': _kMathBlockType,
      NodeMetadata.blockType: const NamedAttribution('mathBlock'),
    });
  }

  @override
  final String id;

  final String latex;

  _MathBlockNode copyMathBlockWith({
    String? id,
    String? latex,
    Map<String, dynamic>? metadata,
  }) {
    return _MathBlockNode(
      id: id ?? this.id,
      latex: latex ?? this.latex,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String? copyContent(dynamic selection) {
    if (selection is! UpstreamDownstreamNodeSelection) {
      throw Exception(
        'Math blocks can only copy content from an UpstreamDownstreamNodeSelection.',
      );
    }

    return !selection.isCollapsed ? '\$\$\n${latex.trim()}\n\$\$' : null;
  }

  @override
  bool hasEquivalentContent(DocumentNode other) {
    return other is _MathBlockNode && other.latex == latex;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return _MathBlockNode(
      id: id,
      latex: latex,
      metadata: {...Map<String, dynamic>.from(metadata), ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return _MathBlockNode(id: id, latex: latex, metadata: newMetadata);
  }

  _MathBlockNode copy() {
    return _MathBlockNode(
      id: id,
      latex: latex,
      metadata: Map<String, dynamic>.from(metadata),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _MathBlockNode &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            latex == other.latex;
  }

  @override
  int get hashCode => Object.hash(id, latex);
}

@immutable
class _TodoBlockNode extends BlockNode {
  _TodoBlockNode({
    required this.id,
    required this.todoId,
    required this.title,
    required this.priority,
    required this.isCompleted,
    this.deadline,
    super.metadata,
  }) {
    initAddToMetadata({
      'documentNodeType': _kDocumentTodoBlockType,
      NodeMetadata.blockType: const NamedAttribution('todoBlock'),
    });
  }

  @override
  final String id;

  final String todoId;
  final String title;
  final String priority;
  final bool isCompleted;
  final DateTime? deadline;

  _TodoBlockNode copyTodoBlockWith({
    String? id,
    String? todoId,
    String? title,
    String? priority,
    bool? isCompleted,
    DateTime? deadline,
    bool clearDeadline = false,
    Map<String, dynamic>? metadata,
  }) {
    return _TodoBlockNode(
      id: id ?? this.id,
      todoId: todoId ?? this.todoId,
      title: title ?? this.title,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      deadline: clearDeadline ? null : deadline ?? this.deadline,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String? copyContent(dynamic selection) {
    if (selection is! UpstreamDownstreamNodeSelection) {
      throw Exception(
        'TODO blocks can only copy content from an UpstreamDownstreamNodeSelection.',
      );
    }

    return !selection.isCollapsed
        ? '${isCompleted ? '[x]' : '[ ]'} ${title.trim()}'
        : null;
  }

  @override
  bool hasEquivalentContent(DocumentNode other) {
    return other is _TodoBlockNode &&
        other.todoId == todoId &&
        other.title == title &&
        other.priority == priority &&
        other.isCompleted == isCompleted &&
        other.deadline == deadline;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return _TodoBlockNode(
      id: id,
      todoId: todoId,
      title: title,
      priority: priority,
      isCompleted: isCompleted,
      deadline: deadline,
      metadata: {...Map<String, dynamic>.from(metadata), ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return _TodoBlockNode(
      id: id,
      todoId: todoId,
      title: title,
      priority: priority,
      isCompleted: isCompleted,
      deadline: deadline,
      metadata: newMetadata,
    );
  }

  _TodoBlockNode copy() {
    return _TodoBlockNode(
      id: id,
      todoId: todoId,
      title: title,
      priority: priority,
      isCompleted: isCompleted,
      deadline: deadline,
      metadata: Map<String, dynamic>.from(metadata),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _TodoBlockNode &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            todoId == other.todoId &&
            title == other.title &&
            priority == other.priority &&
            isCompleted == other.isCompleted &&
            deadline == other.deadline;
  }

  @override
  int get hashCode =>
      Object.hash(id, todoId, title, priority, isCompleted, deadline);
}

class _SuperDocumentEditingSession {
  final MutableDocument document;
  final MutableDocumentComposer composer;
  final Editor editor;
  final FocusNode focusNode;
  final Map<String, DocumentNotePdfReference> references;
  final VoidCallback onDocumentChanged;
  late final DocumentChangeListener _documentChangeListener;

  _SuperDocumentEditingSession._({
    required this.document,
    required this.composer,
    required this.editor,
    required this.focusNode,
    required this.references,
    required this.onDocumentChanged,
  }) {
    _documentChangeListener = (_) => onDocumentChanged();
    document.addListener(_documentChangeListener);
  }

  factory _SuperDocumentEditingSession.fromNote(
    StructuredDocumentNote note, {
    required VoidCallback onDocumentChanged,
  }) {
    final decoded = _StructuredDocumentCodec.decode(note);
    final document = MutableDocument(nodes: decoded.nodes);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    return _SuperDocumentEditingSession._(
      document: document,
      composer: composer,
      editor: editor,
      focusNode: FocusNode(debugLabel: 'document-note-${note.note.id}'),
      references: decoded.references,
      onDocumentChanged: onDocumentChanged,
    );
  }

  factory _SuperDocumentEditingSession.empty({
    required VoidCallback onDocumentChanged,
  }) {
    final document = MutableDocument(
      nodes: [
        ParagraphNode(id: Editor.createNodeId(), text: AttributedText('')),
      ],
    );
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );

    return _SuperDocumentEditingSession._(
      document: document,
      composer: composer,
      editor: editor,
      focusNode: FocusNode(debugLabel: 'document-note-empty'),
      references: <String, DocumentNotePdfReference>{},
      onDocumentChanged: onDocumentChanged,
    );
  }

  void dispose() {
    document.removeListener(_documentChangeListener);
    editor.dispose();
    composer.dispose();
    document.dispose();
    focusNode.dispose();
  }
}

class _DecodedStructuredDocument {
  final List<DocumentNode> nodes;
  final Map<String, DocumentNotePdfReference> references;

  const _DecodedStructuredDocument({
    required this.nodes,
    required this.references,
  });
}

class _EncodedStructuredDocument {
  final String plainText;
  final String jsonText;

  const _EncodedStructuredDocument({
    required this.plainText,
    required this.jsonText,
  });
}

class _StructuredDocumentCodec {
  static _DecodedStructuredDocument decode(StructuredDocumentNote note) {
    final references = Map<String, DocumentNotePdfReference>.from(
      note.pdfReferences,
    );

    final jsonText = note.structuredBlock?.jsonText.trim() ?? '';
    if (jsonText.isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map) {
          final rawNodes = decoded['nodes'];
          if (rawNodes is List) {
            final nodes = _nodesFromStructuredJson(rawNodes, references);
            if (nodes.isNotEmpty) {
              return _DecodedStructuredDocument(
                nodes: nodes,
                references: references,
              );
            }
          }
        }
      } catch (_) {
        // Fall through to legacy text parsing.
      }
    }

    final nodes = _nodesFromLegacyText(note.documentText, references);
    return _DecodedStructuredDocument(
      nodes: nodes.isEmpty
          ? [ParagraphNode(id: Editor.createNodeId(), text: AttributedText(''))]
          : nodes,
      references: references,
    );
  }

  static _EncodedStructuredDocument encode({
    required MutableDocument document,
    required Map<String, DocumentNotePdfReference> references,
  }) {
    final jsonNodes = <Map<String, dynamic>>[];
    final activeReferences = <String, DocumentNotePdfReference>{};
    final plainParts = <String>[];

    for (final node in document) {
      if (node is _TodoBlockNode) {
        jsonNodes.add({
          'type': 'todoBlock',
          'todoId': node.todoId,
          'title': node.title,
          'priority': node.priority,
          'isCompleted': node.isCompleted,
          if (node.deadline != null)
            'deadline': node.deadline!.toIso8601String(),
        });

        final cleanTitle = node.title.trim();
        if (cleanTitle.isNotEmpty) {
          plainParts.add('${node.isCompleted ? '[x]' : '[ ]'} $cleanTitle');
        }
        continue;
      }

      if (node is _MathBlockNode) {
        final latex = node.latex.trim();
        jsonNodes.add({'type': 'mathBlock', 'latex': node.latex});
        if (latex.isNotEmpty) {
          plainParts.add('\$\$\n$latex\n\$\$');
        }
        continue;
      }

      if (node is! ParagraphNode) continue;

      final text = node.text.toPlainText();
      final referenceRanges = <Map<String, dynamic>>[];
      for (final span in node.text.computeAttributionSpans()) {
        for (final attribution in span.attributions) {
          if (attribution is! LinkAttribution) continue;
          if (attribution.uri?.scheme != _kPdfReferenceScheme) continue;

          final referenceId = attribution.uri?.path;
          if (referenceId == null || referenceId.isEmpty) continue;

          final reference = references[referenceId];
          if (reference == null) continue;

          activeReferences[referenceId] = reference;
          referenceRanges.add({
            'id': referenceId,
            'start': span.start,
            'end': span.end + 1,
          });
        }
      }

      jsonNodes.add({
        'type': 'paragraph',
        'text': text,
        if (referenceRanges.isNotEmpty) 'references': referenceRanges,
      });

      if (text.trim().isNotEmpty) {
        plainParts.add(text);
      }
    }

    final jsonText = jsonEncode({
      'version': 2,
      'editor': 'superEditorSpike',
      'nodes': jsonNodes,
      'references': {
        for (final entry in activeReferences.entries)
          entry.key: entry.value.toJson(),
      },
    });

    return _EncodedStructuredDocument(
      plainText: plainParts.join('\n\n'),
      jsonText: jsonText,
    );
  }

  static List<DocumentNode> _nodesFromStructuredJson(
    List<dynamic> rawNodes,
    Map<String, DocumentNotePdfReference> references,
  ) {
    final nodes = <DocumentNode>[];
    for (final rawNode in rawNodes) {
      if (rawNode is! Map) continue;
      final node = rawNode.map((key, value) => MapEntry(key.toString(), value));
      final type = node['type'] as String?;
      final text = node['text'] as String? ?? '';

      if (type == 'todoBlock') {
        final rawDeadline = node['deadline']?.toString();
        nodes.add(
          _TodoBlockNode(
            id: Editor.createNodeId(),
            todoId: node['todoId']?.toString() ?? '',
            title: node['title']?.toString() ?? text,
            priority: _normalizeDocumentTodoPriority(
              node['priority']?.toString(),
            ),
            isCompleted: node['isCompleted'] == true,
            deadline: rawDeadline == null
                ? null
                : DateTime.tryParse(rawDeadline),
          ),
        );
        continue;
      }

      if (type == 'mathBlock') {
        final latex = (node['latex'] as String?) ?? text;
        nodes.add(_MathBlockNode(id: Editor.createNodeId(), latex: latex));
        continue;
      }

      final attributedText = AttributedText(text);
      final rawRanges = node['references'];
      if (rawRanges is List) {
        for (final rawRange in rawRanges) {
          if (rawRange is! Map) continue;
          final range = rawRange.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final referenceId = range['id']?.toString();
          final start = _readInt(range['start']);
          final end = _readInt(range['end']);
          if (referenceId == null ||
              !references.containsKey(referenceId) ||
              start == null ||
              end == null ||
              start < 0 ||
              end <= start ||
              end > text.length) {
            continue;
          }
          attributedText.addAttribution(
            LinkAttribution.fromUri(
              Uri.parse('$_kPdfReferenceScheme:$referenceId'),
            ),
            SpanRange(start, end - 1),
          );
        }
      }

      _applyKnowledgeTagAttributions(attributedText);
      nodes.add(ParagraphNode(id: Editor.createNodeId(), text: attributedText));
    }

    return nodes;
  }

  static List<DocumentNode> _nodesFromLegacyText(
    String source,
    Map<String, DocumentNotePdfReference> references,
  ) {
    final nodes = <DocumentNode>[];
    final mathRegex = RegExp(r'\$\$([\s\S]*?)\$\$');
    var cursor = 0;

    for (final match in mathRegex.allMatches(source)) {
      if (match.start > cursor) {
        nodes.addAll(
          _paragraphNodesFromLegacyText(
            source.substring(cursor, match.start),
            references,
          ),
        );
      }

      final latex = match.group(1)?.trim() ?? '';
      if (latex.isNotEmpty) {
        nodes.add(_MathBlockNode(id: Editor.createNodeId(), latex: latex));
      }

      cursor = match.end;
    }

    if (cursor < source.length) {
      nodes.addAll(
        _paragraphNodesFromLegacyText(source.substring(cursor), references),
      );
    }

    return nodes;
  }

  static List<DocumentNode> _paragraphNodesFromLegacyText(
    String source,
    Map<String, DocumentNotePdfReference> references,
  ) {
    final nodes = <DocumentNode>[];
    final paragraphs = source
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty);

    for (final paragraph in paragraphs) {
      nodes.add(_paragraphNodeFromLegacyParagraph(paragraph, references));
    }

    return nodes;
  }

  static ParagraphNode _paragraphNodeFromLegacyParagraph(
    String source,
    Map<String, DocumentNotePdfReference> references,
  ) {
    final refRegex = RegExp(r'\[([^\]]+)\]\(pdfref:([^)]+)\)');
    final buffer = StringBuffer();
    final referenceRanges = <({String id, int start, int end})>[];
    var cursor = 0;

    for (final match in refRegex.allMatches(source)) {
      if (match.start > cursor) {
        buffer.write(source.substring(cursor, match.start));
      }

      final label = match.group(1) ?? 'source';
      final refId = match.group(2) ?? '';
      final visibleLabel = '[$label]';
      final start = buffer.length;
      buffer.write(visibleLabel);
      final end = buffer.length;
      if (references.containsKey(refId)) {
        referenceRanges.add((id: refId, start: start, end: end));
      }

      cursor = match.end;
    }

    if (cursor < source.length) {
      buffer.write(source.substring(cursor));
    }

    final text = buffer.toString();
    final attributedText = AttributedText(text);
    for (final range in referenceRanges) {
      attributedText.addAttribution(
        LinkAttribution.fromUri(Uri.parse('$_kPdfReferenceScheme:${range.id}')),
        SpanRange(range.start, range.end - 1),
      );
    }

    _applyKnowledgeTagAttributions(attributedText);
    return ParagraphNode(id: Editor.createNodeId(), text: attributedText);
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _DocumentNotesHeader extends StatelessWidget {
  final List<StructuredDocumentNote> notes;
  final String? selectedNoteId;
  final bool creatingNote;
  final ValueChanged<String?> onSelectedNoteChanged;
  final VoidCallback onCreateNote;

  const _DocumentNotesHeader({
    required this.notes,
    required this.selectedNoteId,
    required this.creatingNote,
    required this.onSelectedNoteChanged,
    required this.onCreateNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Icon(
            Icons.article_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: notes.any((note) => note.note.id == selectedNoteId)
                    ? selectedNoteId
                    : null,
                hint: const Text('Document note'),
                items: [
                  for (final note in notes)
                    DropdownMenuItem<String>(
                      value: note.note.id,
                      child: Text(
                        note.displayTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onSelectedNoteChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'New document note',
            onPressed: creatingNote ? null : onCreateNote,
            icon: creatingNote
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _EmptyDocumentNoteState extends StatelessWidget {
  final VoidCallback onCreateNote;

  const _EmptyDocumentNoteState({required this.onCreateNote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('Create a document note', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Use this mode for continuous reading notes with PDF references.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateNote,
              icon: const Icon(Icons.add),
              label: const Text('New document note'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuperDocumentEditor extends StatelessWidget {
  final StructuredDocumentNote note;
  final TextEditingController titleController;
  final _SuperDocumentEditingSession session;
  final NoteRepository noteRepository;
  final TagRepository tagRepository;
  final String documentId;
  final List<StructuredDocumentNote> documentNotes;
  final bool hasPdfSelection;
  final ValueListenable<PdfCopiedReference?> copiedReferenceListenable;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onAddMath;
  final VoidCallback onAddTodo;
  final VoidCallback onInsertKnowledgeTag;
  final VoidCallback onInsertSelectionReference;
  final VoidCallback onPasteCopiedReference;
  final VoidCallback onOpenKnowledgeMap;
  final ValueChanged<DocumentNotePdfReference> onJumpToReference;
  final ValueChanged<String> onKnowledgeTagTap;

  const _SuperDocumentEditor({
    super.key,
    required this.note,
    required this.titleController,
    required this.session,
    required this.noteRepository,
    required this.tagRepository,
    required this.documentId,
    required this.documentNotes,
    required this.hasPdfSelection,
    required this.copiedReferenceListenable,
    required this.onTitleChanged,
    required this.onAddMath,
    required this.onAddTodo,
    required this.onInsertKnowledgeTag,
    required this.onInsertSelectionReference,
    required this.onPasteCopiedReference,
    required this.onOpenKnowledgeMap,
    required this.onJumpToReference,
    required this.onKnowledgeTagTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: titleController,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Untitled reading note',
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintStyle: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            onChanged: onTitleChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _DocumentNoteActionBar(
            hasPdfSelection: hasPdfSelection,
            copiedReferenceListenable: copiedReferenceListenable,
            onAddMath: onAddMath,
            onAddTodo: onAddTodo,
            onInsertKnowledgeTag: onInsertKnowledgeTag,
            onInsertSelectionReference: onInsertSelectionReference,
            onPasteCopiedReference: onPasteCopiedReference,
            onOpenKnowledgeMap: onOpenKnowledgeMap,
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: Container(
            color: theme.colorScheme.surfaceContainerLowest,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                child: SuperEditor(
                  // ignore: deprecated_member_use
                  document: session.document,
                  // ignore: deprecated_member_use
                  composer: session.composer,
                  editor: session.editor,
                  focusNode: session.focusNode,
                  stylesheet: _documentNoteStylesheet(theme),
                  contentTapDelegateFactories: [
                    (editContext) => _PdfReferenceTapDelegate(
                      document: session.document,
                      references: session.references,
                      onJumpToReference: onJumpToReference,
                      onKnowledgeTagTap: onKnowledgeTagTap,
                    ),
                    superEditorLaunchLinkTapHandlerFactory,
                  ],
                  componentBuilders: [
                    _TodoBlockComponentBuilder(
                      document: session.document,
                      noteRepository: noteRepository,
                      onTodoChanged: session.onDocumentChanged,
                    ),
                    _MathBlockComponentBuilder(
                      document: session.document,
                      onMathChanged: session.onDocumentChanged,
                    ),
                    ...defaultComponentBuilders,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Stylesheet _documentNoteStylesheet(ThemeData theme) {
  final baseTextStyle =
      theme.textTheme.bodyLarge?.copyWith(
        height: 1.5,
        letterSpacing: 0.05,
        color: theme.colorScheme.onSurface,
      ) ??
      TextStyle(fontSize: 16, height: 1.5, color: theme.colorScheme.onSurface);

  return Stylesheet(
    documentPadding: EdgeInsets.zero,
    inlineTextStyler: (attributions, existingStyle) {
      var style = defaultStylesheet.inlineTextStyler(
        attributions,
        existingStyle,
      );

      final hasKnowledgeTag = attributions.any(
        (attribution) =>
            attribution is LinkAttribution &&
            attribution.uri?.scheme == _kKnowledgeTagScheme,
      );

      if (hasKnowledgeTag) {
        final color = theme.colorScheme.primary;
        style = style.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: color.withValues(alpha: 0.55),
          decorationThickness: 1.3,
        );
      }

      return style;
    },
    inlineWidgetBuilders: defaultStylesheet.inlineWidgetBuilders,
    selectedTextColorStrategy: defaultStylesheet.selectedTextColorStrategy,
    rules: [
      StyleRule(BlockSelector.all, (document, node) {
        return {
          Styles.maxWidth: double.infinity,
          Styles.padding: const CascadingPadding.symmetric(
            horizontal: 0,
            vertical: 4,
          ),
          Styles.textAlign: TextAlign.start,
          Styles.textStyle: baseTextStyle,
        };
      }),
      StyleRule(BlockSelector.all.first(), (document, node) {
        return {Styles.padding: const CascadingPadding.only(top: 0)};
      }),
      StyleRule(BlockSelector.all.last(), (document, node) {
        return {Styles.padding: const CascadingPadding.only(bottom: 48)};
      }),
    ],
  );
}

class _TodoBlockComponentBuilder implements ComponentBuilder {
  final MutableDocument document;
  final NoteRepository noteRepository;
  final VoidCallback onTodoChanged;

  const _TodoBlockComponentBuilder({
    required this.document,
    required this.noteRepository,
    required this.onTodoChanged,
  });

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! _TodoBlockNode) return null;

    return _TodoBlockComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      todoId: node.todoId,
      title: node.title,
      priority: node.priority,
      isCompleted: node.isCompleted,
      deadline: node.deadline,
      selectionColor: _documentTodoPriorityColor(
        node.priority,
      ).withValues(alpha: 0.16),
      caretColor: _documentTodoPriorityColor(node.priority),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! _TodoBlockComponentViewModel) return null;

    void replaceNode(_TodoBlockNode nextNode) {
      document.replaceNodeById(nextNode.id, nextNode);
      onTodoChanged();
    }

    return _TodoBlockComponent(
      componentKey: componentContext.componentKey,
      nodeId: componentViewModel.nodeId,
      todoId: componentViewModel.todoId,
      title: componentViewModel.title,
      priority: componentViewModel.priority,
      isCompleted: componentViewModel.isCompleted,
      deadline: componentViewModel.deadline,
      selection:
          componentViewModel.selection?.nodeSelection
              as UpstreamDownstreamNodeSelection?,
      selectionColor: componentViewModel.selectionColor,
      opacity: componentViewModel.opacity,
      onTitleChanged: (title) {
        final node = document.getNodeById(componentViewModel.nodeId);
        if (node is! _TodoBlockNode || node.title == title) return;

        replaceNode(node.copyTodoBlockWith(title: title));
        unawaited(
          noteRepository.updateTodoTitle(todoId: node.todoId, title: title),
        );
      },
      onCompletedChanged: (isCompleted) {
        final node = document.getNodeById(componentViewModel.nodeId);
        if (node is! _TodoBlockNode || node.isCompleted == isCompleted) return;

        replaceNode(node.copyTodoBlockWith(isCompleted: isCompleted));
        unawaited(
          noteRepository.updateTodoCompleted(
            todoId: node.todoId,
            isCompleted: isCompleted,
          ),
        );
      },
      onPriorityChanged: (priority) {
        final node = document.getNodeById(componentViewModel.nodeId);
        if (node is! _TodoBlockNode || node.priority == priority) return;

        final normalizedPriority = _normalizeDocumentTodoPriority(priority);
        replaceNode(node.copyTodoBlockWith(priority: normalizedPriority));
        unawaited(
          noteRepository.updateTodoPriority(
            todoId: node.todoId,
            priority: normalizedPriority,
          ),
        );
      },
    );
  }
}

class _TodoBlockComponentViewModel extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  _TodoBlockComponentViewModel({
    required super.nodeId,
    super.createdAt,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    super.opacity = 1.0,
    required this.todoId,
    required this.title,
    required this.priority,
    required this.isCompleted,
    this.deadline,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
    this.caret,
    required this.caretColor,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  String todoId;
  String title;
  String priority;
  bool isCompleted;
  DateTime? deadline;
  UpstreamDownstreamNodePosition? caret;
  Color caretColor;

  @override
  _TodoBlockComponentViewModel copy() {
    return _TodoBlockComponentViewModel(
      nodeId: nodeId,
      createdAt: createdAt,
      maxWidth: maxWidth,
      padding: padding,
      opacity: opacity,
      todoId: todoId,
      title: title,
      priority: priority,
      isCompleted: isCompleted,
      deadline: deadline,
      selection: selection,
      selectionColor: selectionColor,
      caret: caret,
      caretColor: caretColor,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        super == other &&
            other is _TodoBlockComponentViewModel &&
            runtimeType == other.runtimeType &&
            nodeId == other.nodeId &&
            createdAt == other.createdAt &&
            todoId == other.todoId &&
            title == other.title &&
            priority == other.priority &&
            isCompleted == other.isCompleted &&
            deadline == other.deadline &&
            selection == other.selection &&
            selectionColor == other.selectionColor &&
            caret == other.caret &&
            caretColor == other.caretColor;
  }

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    nodeId,
    createdAt,
    todoId,
    title,
    priority,
    isCompleted,
    deadline,
    selection,
    selectionColor,
    caret,
    caretColor,
  );
}

class _TodoBlockComponent extends StatefulWidget {
  final GlobalKey componentKey;
  final String nodeId;
  final String todoId;
  final String title;
  final String priority;
  final bool isCompleted;
  final DateTime? deadline;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;
  final double opacity;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<bool> onCompletedChanged;
  final ValueChanged<String> onPriorityChanged;

  const _TodoBlockComponent({
    required this.componentKey,
    required this.nodeId,
    required this.todoId,
    required this.title,
    required this.priority,
    required this.isCompleted,
    required this.deadline,
    required this.selection,
    required this.selectionColor,
    required this.opacity,
    required this.onTitleChanged,
    required this.onCompletedChanged,
    required this.onPriorityChanged,
  });

  @override
  State<_TodoBlockComponent> createState() => _TodoBlockComponentState();
}

class _TodoBlockComponentState extends State<_TodoBlockComponent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.title);
  }

  @override
  void didUpdateWidget(covariant _TodoBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.title != widget.title && _controller.text != widget.title) {
      _controller.value = TextEditingValue(
        text: widget.title,
        selection: TextSelection.collapsed(offset: widget.title.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _priorityLabel {
    switch (widget.priority) {
      case kTodoPriorityLow:
        return 'Low';
      case kTodoPriorityHigh:
        return 'High';
      case kTodoPriorityMedium:
      default:
        return 'Med';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priority = _normalizeDocumentTodoPriority(widget.priority);
    final priorityColor = _documentTodoPriorityColor(priority);
    final isSelected =
        widget.selection != null && !widget.selection!.isCollapsed;

    return BoxComponent(
      key: widget.componentKey,
      opacity: widget.opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected
                ? widget.selectionColor
                : priorityColor.withValues(
                    alpha: widget.isCompleted ? 0.05 : 0.11,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: priorityColor.withValues(
                alpha: widget.isCompleted ? 0.24 : 0.55,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
            child: Row(
              children: [
                Checkbox(
                  value: widget.isCompleted,
                  onChanged: (value) {
                    widget.onCompletedChanged(value ?? false);
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: null,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      decoration: widget.isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: widget.isCompleted
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'TODO',
                    ),
                    onChanged: widget.onTitleChanged,
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Priority',
                  initialValue: priority,
                  onSelected: widget.onPriorityChanged,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: kTodoPriorityLow,
                      child: Text('Low priority'),
                    ),
                    PopupMenuItem(
                      value: kTodoPriorityMedium,
                      child: Text('Medium priority'),
                    ),
                    PopupMenuItem(
                      value: kTodoPriorityHigh,
                      child: Text('High priority'),
                    ),
                  ],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        _priorityLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: priorityColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MathBlockComponentBuilder implements ComponentBuilder {
  final MutableDocument document;
  final VoidCallback onMathChanged;

  const _MathBlockComponentBuilder({
    required this.document,
    required this.onMathChanged,
  });

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! _MathBlockNode) return null;

    return _MathBlockComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      latex: node.latex,
      selectionColor: Colors.blue.withValues(alpha: 0.12),
      caretColor: Colors.blue,
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! _MathBlockComponentViewModel) return null;

    return _MathBlockComponent(
      componentKey: componentContext.componentKey,
      nodeId: componentViewModel.nodeId,
      latex: componentViewModel.latex,
      selection:
          componentViewModel.selection?.nodeSelection
              as UpstreamDownstreamNodeSelection?,
      selectionColor: componentViewModel.selectionColor,
      opacity: componentViewModel.opacity,
      onLatexChanged: (latex) {
        final node = document.getNodeById(componentViewModel.nodeId);
        if (node is! _MathBlockNode || node.latex == latex) return;

        document.replaceNodeById(node.id, node.copyMathBlockWith(latex: latex));
        onMathChanged();
      },
    );
  }
}

class _MathBlockComponentViewModel extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  _MathBlockComponentViewModel({
    required super.nodeId,
    super.createdAt,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    super.opacity = 1.0,
    required this.latex,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
    this.caret,
    required this.caretColor,
  }) {
    super.selection = selection;
    super.selectionColor = selectionColor;
  }

  String latex;
  UpstreamDownstreamNodePosition? caret;
  Color caretColor;

  @override
  _MathBlockComponentViewModel copy() {
    return _MathBlockComponentViewModel(
      nodeId: nodeId,
      createdAt: createdAt,
      maxWidth: maxWidth,
      padding: padding,
      opacity: opacity,
      latex: latex,
      selection: selection,
      selectionColor: selectionColor,
      caret: caret,
      caretColor: caretColor,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        super == other &&
            other is _MathBlockComponentViewModel &&
            runtimeType == other.runtimeType &&
            nodeId == other.nodeId &&
            createdAt == other.createdAt &&
            latex == other.latex &&
            selection == other.selection &&
            selectionColor == other.selectionColor &&
            caret == other.caret &&
            caretColor == other.caretColor;
  }

  @override
  int get hashCode => Object.hash(
    super.hashCode,
    nodeId,
    createdAt,
    latex,
    selection,
    selectionColor,
    caret,
    caretColor,
  );
}

class _MathBlockComponent extends StatefulWidget {
  final GlobalKey componentKey;
  final String nodeId;
  final String latex;
  final UpstreamDownstreamNodeSelection? selection;
  final Color selectionColor;
  final double opacity;
  final ValueChanged<String> onLatexChanged;

  const _MathBlockComponent({
    required this.componentKey,
    required this.nodeId,
    required this.latex,
    required this.selection,
    required this.selectionColor,
    required this.opacity,
    required this.onLatexChanged,
  });

  @override
  State<_MathBlockComponent> createState() => _MathBlockComponentState();
}

class _MathBlockComponentState extends State<_MathBlockComponent> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.latex);
    _focusNode = FocusNode(debugLabel: 'document-note-math-${widget.nodeId}')
      ..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _MathBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.latex != widget.latex && _controller.text != widget.latex) {
      _controller.value = TextEditingValue(
        text: widget.latex,
        selection: TextSelection.collapsed(offset: widget.latex.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus && _isEditing && mounted) {
      setState(() {
        _isEditing = false;
      });
    }
  }

  void _enterEditMode() {
    if (!_isEditing) {
      setState(() {
        _isEditing = true;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BoxComponent(
      key: widget.componentKey,
      opacity: widget.opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _isEditing
            ? _buildLatexEditor(theme)
            : _buildRenderedMath(theme),
      ),
    );
  }

  Widget _buildLatexEditor(ThemeData theme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 560),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              height: 1.4,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration.collapsed(
              hintText: r'\frac{1}{1+r}',
              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onTapOutside: (_) => _focusNode.unfocus(),
            onChanged: widget.onLatexChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildRenderedMath(ThemeData theme) {
    final latex = widget.latex.trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _enterEditMode,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          child: latex.isEmpty
              ? Text(
                  'Enter equation',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : _LatexMathPreview(latex: latex),
        ),
      ),
    );
  }
}

class _LatexMathPreview extends StatelessWidget {
  final String latex;

  const _LatexMathPreview({required this.latex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    try {
      return Math.tex(
        latex,
        textStyle: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      );
    } catch (_) {
      return Text(
        latex,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.error,
        ),
      );
    }
  }
}

class _KnowledgeTagPickerDialog extends StatefulWidget {
  final TagRepository tagRepository;

  const _KnowledgeTagPickerDialog({required this.tagRepository});

  @override
  State<_KnowledgeTagPickerDialog> createState() =>
      _KnowledgeTagPickerDialogState();
}

class _KnowledgeTagPickerDialogState extends State<_KnowledgeTagPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<AppTag>> _tagsFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tagsFuture = widget.tagRepository.getTags(scope: kTagScopeKnowledge);
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().replaceFirst(RegExp(r'^#'), '');
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedQuery = _query.toLowerCase();

    return AlertDialog(
      title: const Text('Insert knowledge tag'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<AppTag>>(
          future: _tagsFuture,
          builder: (context, snapshot) {
            final tags = snapshot.data ?? const <AppTag>[];
            final filtered = normalizedQuery.isEmpty
                ? tags
                : tags
                      .where(
                        (tag) =>
                            tag.name.toLowerCase().contains(normalizedQuery),
                      )
                      .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tag_outlined),
                    hintText: 'Search or create a tag...',
                  ),
                  onSubmitted: (value) {
                    final normalized = _normalizePickerTagName(value);
                    if (normalized != null) {
                      Navigator.of(context).pop(normalized);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (normalizedQuery.isNotEmpty &&
                            !tags.any(
                              (tag) =>
                                  tag.name.toLowerCase() ==
                                  normalizedQuery.toLowerCase(),
                            ))
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 15,
                              backgroundColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.12),
                              child: Icon(
                                Icons.add,
                                size: 17,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            title: Text('Create #$normalizedQuery'),
                            subtitle: const Text('Create and insert this tag'),
                            onTap: () =>
                                Navigator.of(context).pop(normalizedQuery),
                          ),
                        for (final tag in filtered)
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 15,
                              backgroundColor: Color(
                                tag.colorValue,
                              ).withValues(alpha: 0.12),
                              child: Icon(
                                Icons.tag,
                                size: 17,
                                color: Color(tag.colorValue),
                              ),
                            ),
                            title: Text('#${tag.name}'),
                            subtitle: tag.description == null
                                ? null
                                : Text(
                                    tag.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => Navigator.of(context).pop(tag.name),
                          ),
                        if (filtered.isEmpty && normalizedQuery.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'No knowledge tags yet. Type a name to create one.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String? _normalizePickerTagName(String value) {
    final normalized = value
        .trim()
        .replaceFirst(RegExp(r'^#'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();

    return normalized.isEmpty ? null : normalized;
  }
}

class _KnowledgeMapDialog extends StatefulWidget {
  final TagRepository tagRepository;
  final String documentId;
  final List<StructuredDocumentNote> documentNotes;
  final ValueChanged<String> onOpenDocumentNote;

  const _KnowledgeMapDialog({
    required this.tagRepository,
    required this.documentId,
    required this.documentNotes,
    required this.onOpenDocumentNote,
  });

  @override
  State<_KnowledgeMapDialog> createState() => _KnowledgeMapDialogState();
}

class _KnowledgeMapDialogState extends State<_KnowledgeMapDialog> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<_KnowledgeMapTagEntry>> _entriesFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_KnowledgeMapTagEntry>> _loadEntries() async {
    final tags = await widget.tagRepository.getTags(scope: kTagScopeKnowledge);
    final entries = <_KnowledgeMapTagEntry>[];

    for (final tag in tags) {
      final assignments = await widget.tagRepository.getAssignmentsForTag(
        tagId: tag.id,
        targetType: kTagTargetDocumentNote,
        documentId: widget.documentId,
      );
      if (assignments.isEmpty) continue;

      entries.add(_KnowledgeMapTagEntry(tag: tag, assignments: assignments));
    }

    entries.sort((a, b) {
      final countCompare = b.assignments.length.compareTo(a.assignments.length);
      if (countCompare != 0) return countCompare;
      return a.tag.name.compareTo(b.tag.name);
    });

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      title: Row(
        children: [
          Icon(Icons.hub_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Knowledge map')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: FutureBuilder<List<_KnowledgeMapTagEntry>>(
          future: _entriesFuture,
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const <_KnowledgeMapTagEntry>[];

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (entries.isEmpty) {
              return const _KnowledgeMapEmptyState(
                message:
                    'No knowledge tags in this PDF yet. Type #tag in a document note to create one.',
              );
            }

            final filteredEntries = _filterEntries(entries);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tags from document notes in this PDF. Click a tag to inspect backlinks.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search tags...',
                  ),
                ),
                const SizedBox(height: 12),
                if (filteredEntries.isEmpty)
                  const _KnowledgeMapEmptyState(
                    message: 'No tags match the current search.',
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredEntries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        final color = Color(entry.tag.colorValue);

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 15,
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(Icons.tag, size: 17, color: color),
                          ),
                          title: Text('#${entry.tag.name}'),
                          subtitle: Text(
                            '${entry.assignments.length} backlink${entry.assignments.length == 1 ? '' : 's'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).maybePop();
                            showDialog<void>(
                              context: context,
                              builder: (context) {
                                return _KnowledgeTagBacklinksDialog(
                                  tag: entry.tag,
                                  tagRepository: widget.tagRepository,
                                  documentId: widget.documentId,
                                  documentNotes: widget.documentNotes,
                                  onOpenDocumentNote: widget.onOpenDocumentNote,
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_KnowledgeMapTagEntry> _filterEntries(
    List<_KnowledgeMapTagEntry> entries,
  ) {
    if (_query.isEmpty) return entries;

    return entries.where((entry) {
      return entry.tag.name.toLowerCase().contains(_query) ||
          (entry.tag.description?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }
}

class _KnowledgeMapTagEntry {
  final AppTag tag;
  final List<TagAssignment> assignments;

  const _KnowledgeMapTagEntry({required this.tag, required this.assignments});
}

class _KnowledgeMapEmptyState extends StatelessWidget {
  final String message;

  const _KnowledgeMapEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 180,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _KnowledgeTagBacklinksDialog extends StatelessWidget {
  final AppTag tag;
  final TagRepository tagRepository;
  final String documentId;
  final List<StructuredDocumentNote> documentNotes;
  final ValueChanged<String> onOpenDocumentNote;

  const _KnowledgeTagBacklinksDialog({
    required this.tag,
    required this.tagRepository,
    required this.documentId,
    required this.documentNotes,
    required this.onOpenDocumentNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(tag.colorValue);
    final notesById = {for (final note in documentNotes) note.note.id: note};

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
      title: Row(
        children: [
          CircleAvatar(radius: 7, backgroundColor: color),
          const SizedBox(width: 10),
          Expanded(child: Text('#${tag.name}')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<TagAssignment>>(
          future: tagRepository.getAssignmentsForTag(
            tagId: tag.id,
            targetType: kTagTargetDocumentNote,
            documentId: documentId,
          ),
          builder: (context, snapshot) {
            final assignments = snapshot.data ?? const <TagAssignment>[];

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (assignments.isEmpty) {
              return Text(
                'No document-note backlinks found for this tag yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${assignments.length} document-note backlink${assignments.length == 1 ? '' : 's'} in this PDF. Click a row to open that note.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: assignments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final assignment = assignments[index];
                      final note = notesById[assignment.targetId];

                      final canOpen = note != null;

                      return ListTile(
                        dense: true,
                        enabled: canOpen,
                        leading: CircleAvatar(
                          radius: 15,
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Icon(
                            Icons.article_outlined,
                            size: 17,
                            color: color,
                          ),
                        ),
                        title: Text(
                          note?.displayTitle ?? 'Document note',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _snippetForKnowledgeTag(note, tag.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_forward, size: 18),
                        onTap: canOpen
                            ? () {
                                Navigator.of(context).maybePop();
                                onOpenDocumentNote(note.note.id);
                              }
                            : null,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _snippetForKnowledgeTag(StructuredDocumentNote? note, String tagName) {
    if (note == null) return 'Tag assignment stored in this PDF.';

    final text = note.documentText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return 'Empty document note.';

    final needle = '#$tagName'.toLowerCase();
    final lower = text.toLowerCase();
    final index = lower.indexOf(needle);

    if (index < 0) {
      return text.length <= 180 ? text : '${text.substring(0, 180)}…';
    }

    final start = (index - 70).clamp(0, text.length).toInt();
    final end = (index + needle.length + 90).clamp(0, text.length).toInt();
    final prefix = start == 0 ? '' : '…';
    final suffix = end == text.length ? '' : '…';

    return '$prefix${text.substring(start, end)}$suffix';
  }
}

class _DocumentNoteActionBar extends StatelessWidget {
  final bool hasPdfSelection;
  final ValueListenable<PdfCopiedReference?> copiedReferenceListenable;
  final VoidCallback onAddMath;
  final VoidCallback onAddTodo;
  final VoidCallback onInsertKnowledgeTag;
  final VoidCallback onInsertSelectionReference;
  final VoidCallback onPasteCopiedReference;
  final VoidCallback onOpenKnowledgeMap;

  const _DocumentNoteActionBar({
    required this.hasPdfSelection,
    required this.copiedReferenceListenable,
    required this.onAddMath,
    required this.onAddTodo,
    required this.onInsertKnowledgeTag,
    required this.onInsertSelectionReference,
    required this.onPasteCopiedReference,
    required this.onOpenKnowledgeMap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _EditorToolButton(
          icon: Icons.functions,
          label: 'Math',
          tooltip: 'Insert a LaTeX math block',
          onPressed: onAddMath,
        ),
        const SizedBox(width: 8),
        _EditorToolButton(
          icon: Icons.check_box_outlined,
          label: 'TODO',
          tooltip: 'Insert a TODO linked to this document note',
          onPressed: onAddTodo,
        ),
        const SizedBox(width: 8),
        _EditorToolButton(
          icon: Icons.tag_outlined,
          label: 'Tag',
          tooltip: 'Insert a knowledge tag near the current cursor',
          onPressed: onInsertKnowledgeTag,
        ),
        const SizedBox(width: 8),
        _EditorToolButton(
          icon: Icons.hub_outlined,
          label: 'Map',
          tooltip: 'Open the knowledge-tag map for this PDF',
          onPressed: onOpenKnowledgeMap,
        ),
        const SizedBox(width: 8),
        _EditorToolButton(
          icon: Icons.format_quote,
          label: 'Quote selection',
          tooltip: hasPdfSelection
              ? 'Insert the current PDF selection with a page reference'
              : 'Select text in the PDF to insert a referenced quote',
          onPressed: hasPdfSelection ? onInsertSelectionReference : null,
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<PdfCopiedReference?>(
          valueListenable: copiedReferenceListenable,
          builder: (context, copiedReference, child) {
            return _EditorToolButton(
              icon: Icons.content_paste,
              label: 'Paste ref',
              tooltip: copiedReference == null
                  ? 'Copy text from the PDF first'
                  : 'Paste the last copied PDF quote/reference',
              onPressed: copiedReference == null
                  ? null
                  : onPasteCopiedReference,
            );
          },
        ),
        const Spacer(),
        Tooltip(
          message:
              'Text is edited directly. PDF references remain clickable. Math blocks render by default and can be clicked to edit LaTeX.',
          child: Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EditorToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  const _EditorToolButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}

class _PdfReferenceTapDelegate extends ContentTapDelegate {
  final Document document;
  final Map<String, DocumentNotePdfReference> references;
  final ValueChanged<DocumentNotePdfReference> onJumpToReference;
  final ValueChanged<String> onKnowledgeTagTap;

  _PdfReferenceTapDelegate({
    required this.document,
    required this.references,
    required this.onJumpToReference,
    required this.onKnowledgeTagTap,
  });

  @override
  MouseCursor? mouseCursorForContentHover(DocumentPosition hoverPosition) {
    return _referenceAt(hoverPosition) == null &&
            _knowledgeTagAt(hoverPosition) == null
        ? null
        : SystemMouseCursors.click;
  }

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final tapPosition = details.documentLayout.getDocumentPositionAtOffset(
      details.layoutOffset,
    );
    if (tapPosition == null) {
      return TapHandlingInstruction.continueHandling;
    }

    final reference = _referenceAt(tapPosition);
    if (reference != null) {
      onJumpToReference(reference);
      return TapHandlingInstruction.halt;
    }

    final knowledgeTag = _knowledgeTagAt(tapPosition);
    if (knowledgeTag != null) {
      onKnowledgeTagTap(knowledgeTag);
      return TapHandlingInstruction.halt;
    }

    return TapHandlingInstruction.continueHandling;
  }

  @override
  TapHandlingInstruction onDoubleTap(DocumentTapDetails details) {
    return TapHandlingInstruction.continueHandling;
  }

  @override
  TapHandlingInstruction onTripleTap(DocumentTapDetails details) {
    return TapHandlingInstruction.continueHandling;
  }

  String? _knowledgeTagAt(DocumentPosition position) {
    final node = document.getNodeById(position.nodeId);
    if (node is! ParagraphNode) return null;
    final nodePosition = position.nodePosition;
    if (nodePosition is! TextNodePosition) return null;

    final text = node.text.toPlainText();
    if (text.isEmpty) return null;

    final offset = nodePosition.offset.clamp(0, text.length - 1).toInt();
    for (final match in _knowledgeTagRegex.allMatches(text)) {
      final prefix = match.group(1) ?? '';
      final tagName = match.group(2)?.trim();
      if (tagName == null || tagName.isEmpty) continue;

      final start = match.start + prefix.length;
      final end = match.end;

      if (offset >= start && offset < end) {
        return tagName;
      }
    }

    return null;
  }

  DocumentNotePdfReference? _referenceAt(DocumentPosition position) {
    final node = document.getNodeById(position.nodeId);
    if (node is! ParagraphNode) return null;
    final nodePosition = position.nodePosition;
    if (nodePosition is! TextNodePosition) return null;
    final textLength = node.text.toPlainText().length;
    if (textLength == 0) return null;

    final offset = nodePosition.offset.clamp(0, textLength - 1).toInt();
    final attributions = node.text.spans.getAllAttributionsAt(offset);
    for (final attribution in attributions) {
      if (attribution is LinkAttribution &&
          attribution.uri?.scheme == _kPdfReferenceScheme) {
        return references[attribution.uri?.path];
      }
    }

    return null;
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
