import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';
import '../../text_system/core/text_mark.dart';
import '../../text_system/core/text_system_block.dart';
import '../../text_system/core/text_system_controller.dart';
import '../../text_system/core/text_system_document.dart';
import '../../text_system/core/text_system_range.dart';
import '../../text_system/editor/text_system_owned_document_editor_surface.dart';
import '../../text_system/editor/text_system_owned_editor_command_controller.dart';
import '../../text_system/page/text_system_page_furniture.dart';
import '../../text_system/page/text_system_page_setup.dart';
import '../../text_system/references/actions/text_system_reference_actions.dart';
import 'pdf_document_notes_panel.dart'
    show PdfCopiedReference, DocumentNoteReferenceInsertionRequest;

/// TextSystem-backed PDF document notes panel.
///
/// The old PDF document-notes pane used a dedicated SuperEditor spike. This
/// panel adapts the same note repository rows to the project-wide owned editor
/// so the PDF reader and the TextSystem environment exercise the same writing
/// engine before the first beta.
class PdfOwnedDocumentNotesPanel extends StatefulWidget {
  const PdfOwnedDocumentNotesPanel({
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

  final NoteRepository noteRepository;
  final String documentId;
  final String documentTitle;
  final String? selectedText;
  final List<PdfSourceRect> selectedSourceRects;
  final ValueListenable<PdfCopiedReference?> copiedReferenceListenable;
  final ValueListenable<DocumentNoteReferenceInsertionRequest?>?
      externalReferenceInsertionListenable;
  final ValueChanged<DocumentNotePdfReference> onJumpToReference;

  @override
  State<PdfOwnedDocumentNotesPanel> createState() =>
      _PdfOwnedDocumentNotesPanelState();
}

class _PdfOwnedDocumentNotesPanelState
    extends State<PdfOwnedDocumentNotesPanel> {
  final Map<String, _OwnedDocumentNoteSession> _sessions = {};
  final Map<String, Timer> _saveDebounceByNoteId = {};
  final Map<String, String> _lastSavedFingerprintByNoteId = {};

  List<StructuredDocumentNote> _latestNotes = const [];
  String? _selectedNoteId;
  bool _creatingNote = false;
  int? _lastExternalInsertionRequestId;

  static const Duration _saveDebounce = Duration(milliseconds: 650);

  static const TextSystemPageSetup _pdfReadingNotePageSetup =
      TextSystemPageSetup(
    size: TextSystemPageSize.a4(),
    orientation: TextSystemPageOrientation.portrait,
    margins: TextSystemPageMargins(
      topMm: 14,
      rightMm: 15,
      bottomMm: 16,
      leftMm: 15,
    ),
    typography: TextSystemPageTypography.screen,
    lineSpacing: 1.45,
    defaultFontSize: 16,
    showPageNumbers: false,
  );

  static const TextSystemPageFurniture _pdfReadingNoteFurniture =
      TextSystemPageFurniture(
    pageNumbers: TextSystemPageNumbering.defaults(),
    headerMode: TextSystemPageHeaderMode.none,
    headerFooter: TextSystemHeaderFooterSettings(
      enabled: false,
      differentFirstPage: false,
      primaryHeader: TextSystemHeaderFooterZone.empty(),
      primaryFooter: TextSystemHeaderFooterZone.empty(),
      firstPageHeader: TextSystemHeaderFooterZone.empty(),
      firstPageFooter: TextSystemHeaderFooterZone.empty(),
    ),
  );

  bool get _hasPdfSelection {
    final selectedText = widget.selectedText?.trim();
    return selectedText != null &&
        selectedText.isNotEmpty &&
        widget.selectedSourceRects.any((rect) => rect.isValid);
  }

  @override
  void initState() {
    super.initState();
    widget.externalReferenceInsertionListenable?.addListener(
      _handleExternalReferenceInsertion,
    );
    unawaited(_ensureInitialDocumentNote());
  }

  @override
  void didUpdateWidget(covariant PdfOwnedDocumentNotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.documentId != widget.documentId) {
      _selectedNoteId = null;
      _latestNotes = const [];
      _lastExternalInsertionRequestId = null;
      _disposeSessions(forceSave: true);
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
    _disposeSessions(forceSave: true);
    super.dispose();
  }

  void _disposeSessions({required bool forceSave}) {
    for (final timer in _saveDebounceByNoteId.values) {
      timer.cancel();
    }
    _saveDebounceByNoteId.clear();

    if (forceSave) {
      for (final noteId in _sessions.keys.toList()) {
        unawaited(_saveDocumentNow(noteId, force: true));
      }
    }

    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    _lastSavedFingerprintByNoteId.clear();
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
    if (_latestNotes.isNotEmpty) return _latestNotes.first.note.id;
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

    if (!_latestNotes.any((existing) => existing.note.id == note.note.id)) {
      _latestNotes = <StructuredDocumentNote>[note, ..._latestNotes];
    }
    _sessionFor(note);

    if (mounted) {
      setState(() => _selectedNoteId = note.note.id);
    }

    return note.note.id;
  }

  _OwnedDocumentNoteSession _sessionFor(StructuredDocumentNote note) {
    return _sessions.putIfAbsent(note.note.id, () {
      final decoded = _OwnedDocumentNoteCodec.decode(note);
      final session = _OwnedDocumentNoteSession(
        noteId: note.note.id,
        titleController: TextEditingController(text: note.displayTitle),
        textController: TextSystemController(document: decoded.document),
        commandController: TextSystemOwnedEditorCommandController(),
        scrollController: ScrollController(),
        referenceActionRepository: TextSystemMemoryReferenceActionRepository(),
        references: decoded.references,
      );

      session.textController.addListener(() {
        _scheduleDocumentSave(note.note.id);
      });
      _lastSavedFingerprintByNoteId[note.note.id] =
          _fingerprintForSession(session);
      return session;
    });
  }

  void _syncSessionTitleFromRepository(
    StructuredDocumentNote note,
    _OwnedDocumentNoteSession session,
  ) {
    final title = note.displayTitle;
    if (session.titleController.text == title) return;
    session.titleController.value = TextEditingValue(
      text: title,
      selection: TextSelection.collapsed(offset: title.length),
    );
  }

  Future<void> _createDocumentNote() async {
    if (_creatingNote) return;
    setState(() => _creatingNote = true);

    try {
      final note = await widget.noteRepository.createDocumentNote(
        documentId: widget.documentId,
        title: 'Reading note ${_latestNotes.length + 1}',
      );
      if (!mounted) return;
      setState(() => _selectedNoteId = note.note.id);
    } finally {
      if (mounted) setState(() => _creatingNote = false);
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
    if (session == null) return;

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

    final citationLabel = '[${documentReference.citationLabel}]';
    final text = '“${documentReference.selectedText}” $citationLabel';
    final labelStart = math.max(0, text.length - citationLabel.length);
    final referenceBlock = TextSystemBlock.paragraph(
      id: 'pdf-reference-${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      marks: <TextMark>[
        TextMark(
          kind: TextMarkKind.link,
          range: TextSystemRange(labelStart, text.length),
          attributes: _inlineReferenceAttributes(
            referenceId: referenceId,
            reference: documentReference,
          ),
        ),
      ],
    );

    final blocks = session.textController.document.blocks.toList();
    if (blocks.length == 1 && blocks.first.text.trim().isEmpty) {
      blocks
        ..clear()
        ..add(referenceBlock)
        ..add(_emptyParagraphBlock());
    } else {
      blocks
        ..add(referenceBlock)
        ..add(_emptyParagraphBlock());
    }

    session.textController.replaceDocument(
      session.textController.document.copyWith(
        blocks: List<TextSystemBlock>.unmodifiable(blocks),
        updatedAt: DateTime.now(),
      ),
      label: 'Insert PDF reference',
    );
    await _saveDocumentNow(noteId, force: true);
  }

  _OwnedDocumentNoteSession? _sessionForNoteId(String noteId) {
    final existing = _sessions[noteId];
    if (existing != null) return existing;

    for (final note in _latestNotes) {
      if (note.note.id == noteId) return _sessionFor(note);
    }

    return null;
  }

  void _scheduleDocumentSave(String noteId) {
    _saveDebounceByNoteId[noteId]?.cancel();
    _saveDebounceByNoteId[noteId] = Timer(
      _saveDebounce,
      () => unawaited(_saveDocumentNow(noteId)),
    );
  }

  Future<void> _saveDocumentNow(String noteId, {bool force = false}) async {
    _saveDebounceByNoteId[noteId]?.cancel();
    _saveDebounceByNoteId.remove(noteId);

    final session = _sessions[noteId];
    if (session == null) return;

    final encoded = _OwnedDocumentNoteCodec.encode(
      document: session.textController.document,
      references: session.references,
    );
    final fingerprint = _fingerprintForEncoded(encoded);
    if (!force && _lastSavedFingerprintByNoteId[noteId] == fingerprint) {
      return;
    }

    await widget.noteRepository.updateStructuredDocumentNote(
      noteId: noteId,
      text: encoded.plainText,
      contentJson: encoded.jsonText,
    );
    _lastSavedFingerprintByNoteId[noteId] = fingerprint;
  }

  String _fingerprintForSession(_OwnedDocumentNoteSession session) {
    return _fingerprintForEncoded(
      _OwnedDocumentNoteCodec.encode(
        document: session.textController.document,
        references: session.references,
      ),
    );
  }

  String _fingerprintForEncoded(_EncodedOwnedDocumentNote encoded) {
    return '${encoded.plainText.hashCode}:${encoded.jsonText.hashCode}:'
        '${encoded.plainText.length}:${encoded.jsonText.length}';
  }

  void _openReferenceTarget(
    _OwnedDocumentNoteSession session,
    TextSystemInlineReferenceMark inlineReference,
  ) {
    final pdfReferenceId =
        inlineReference.metadata['pdfReferenceId']?.toString().trim();
    final reference = session.references[pdfReferenceId] ??
        session.references[inlineReference.id] ??
        session.references[inlineReference.targetId];
    if (reference == null) return;
    widget.onJumpToReference(reference);
  }

  String _newReferenceId() => 'pdf_ref_${DateTime.now().microsecondsSinceEpoch}';

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

  @override
  Widget build(BuildContext context) {
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
        final selectedNoteId = _effectiveSelectedNoteId();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OwnedDocumentNotesHeader(
              notes: notes,
              selectedNoteId: selectedNoteId,
              creatingNote: _creatingNote,
              onSelectedNoteChanged: (noteId) {
                final previousNoteId = _selectedNoteId;
                if (previousNoteId != null) {
                  unawaited(_saveDocumentNow(previousNoteId, force: true));
                }
                setState(() => _selectedNoteId = noteId);
              },
              onCreateNote: _createDocumentNote,
            ),
            const Divider(height: 1),
            Expanded(
              child: selectedNote == null
                  ? _EmptyOwnedDocumentNoteState(onCreateNote: _createDocumentNote)
                  : _buildSelectedNoteEditor(selectedNote),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSelectedNoteEditor(StructuredDocumentNote selectedNote) {
    final session = _sessionFor(selectedNote);
    _syncSessionTitleFromRepository(selectedNote, session);

    return _OwnedDocumentNoteEditor(
      key: ValueKey(selectedNote.note.id),
      session: session,
      hasPdfSelection: _hasPdfSelection,
      copiedReferenceListenable: widget.copiedReferenceListenable,
      onTitleChanged: (title) {
        unawaited(
          widget.noteRepository.updateDocumentNoteTitle(
            noteId: selectedNote.note.id,
            title: title,
          ),
        );
      },
      onInsertSelectionReference: () =>
          unawaited(_insertCurrentSelectionAsReference()),
      onPasteCopiedReference: () {
        final copiedReference = widget.copiedReferenceListenable.value;
        if (copiedReference != null) {
          unawaited(_insertCopiedReference(copiedReference));
        }
      },
      onOpenReferenceTarget: (inlineReference) =>
          _openReferenceTarget(session, inlineReference),
    );
  }
}

class _OwnedDocumentNoteEditor extends StatelessWidget {
  const _OwnedDocumentNoteEditor({
    super.key,
    required this.session,
    required this.hasPdfSelection,
    required this.copiedReferenceListenable,
    required this.onTitleChanged,
    required this.onInsertSelectionReference,
    required this.onPasteCopiedReference,
    required this.onOpenReferenceTarget,
  });

  final _OwnedDocumentNoteSession session;
  final bool hasPdfSelection;
  final ValueListenable<PdfCopiedReference?> copiedReferenceListenable;
  final ValueChanged<String> onTitleChanged;
  final VoidCallback onInsertSelectionReference;
  final VoidCallback onPasteCopiedReference;
  final ValueChanged<TextSystemInlineReferenceMark> onOpenReferenceTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: session.titleController,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Untitled reading note',
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintStyle: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                          color: colorScheme.onSurface,
                        ),
                        onChanged: onTitleChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _OwnedDocumentNoteStatusPill(
                      label: 'Owned editor',
                      icon: Icons.edit_note_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _OwnedDocumentNoteActionBar(
                  commandController: session.commandController,
                  hasPdfSelection: hasPdfSelection,
                  copiedReferenceListenable: copiedReferenceListenable,
                  onInsertSelectionReference: onInsertSelectionReference,
                  onPasteCopiedReference: onPasteCopiedReference,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
            ),
            child: AnimatedBuilder(
              animation: session.textController,
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final pageMaxWidth = math.min(
                      760.0,
                      math.max(420.0, constraints.maxWidth - 44.0),
                    );

                    return TextSystemOwnedDocumentEditorSurface(
                      textController: session.textController,
                      document: session.textController.document,
                      pageSetup: _PdfOwnedDocumentNotesPanelState
                          ._pdfReadingNotePageSetup,
                      pageFurniture: _PdfOwnedDocumentNotesPanelState
                          ._pdfReadingNoteFurniture,
                      pageMaxWidth: pageMaxWidth,
                      pageZoom: 1.0,
                      focusMode: true,
                      showMarginGuides: false,
                      showDebugBanner: false,
                      showPageHeader: false,
                      pageGap: 28,
                      verticalPadding: 18,
                      horizontalPadding: 20,
                      scrollController: session.scrollController,
                      commandController: session.commandController,
                      referenceActionRepository: session.referenceActionRepository,
                      onOpenReferenceTarget: onOpenReferenceTarget,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}


class _OwnedDocumentNoteStatusPill extends StatelessWidget {
  const _OwnedDocumentNoteStatusPill({
    required this.label,
    required this.icon,
    this.prominent = false,
  });

  final String label;
  final IconData icon;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = prominent
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);
    final foreground = prominent
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: prominent
              ? colorScheme.primary.withValues(alpha: 0.18)
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedDocumentNoteActionBar extends StatelessWidget {
  const _OwnedDocumentNoteActionBar({
    required this.commandController,
    required this.hasPdfSelection,
    required this.copiedReferenceListenable,
    required this.onInsertSelectionReference,
    required this.onPasteCopiedReference,
  });

  final TextSystemOwnedEditorCommandController commandController;
  final bool hasPdfSelection;
  final ValueListenable<PdfCopiedReference?> copiedReferenceListenable;
  final VoidCallback onInsertSelectionReference;
  final VoidCallback onPasteCopiedReference;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: commandController,
      builder: (context, _) {
        return ValueListenableBuilder<PdfCopiedReference?>(
          valueListenable: copiedReferenceListenable,
          builder: (context, copiedReference, _) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _toolbarButton(
                  context,
                  tooltip: 'Undo',
                  icon: Icons.undo_rounded,
                  onPressed: commandController.canUndo
                      ? commandController.undo
                      : null,
                ),
                _toolbarButton(
                  context,
                  tooltip: 'Redo',
                  icon: Icons.redo_rounded,
                  onPressed: commandController.canRedo
                      ? commandController.redo
                      : null,
                ),
                _verticalDivider(context),
                _toolbarButton(
                  context,
                  tooltip: 'Bold',
                  icon: Icons.format_bold_rounded,
                  selected: commandController.boldActive,
                  onPressed: commandController.canToggleBold
                      ? commandController.toggleBold
                      : null,
                ),
                _toolbarButton(
                  context,
                  tooltip: 'Italic',
                  icon: Icons.format_italic_rounded,
                  selected: commandController.italicActive,
                  onPressed: commandController.canToggleItalic
                      ? commandController.toggleItalic
                      : null,
                ),
                _toolbarButton(
                  context,
                  tooltip: 'Highlight',
                  icon: Icons.border_color_outlined,
                  selected: commandController.highlightActive,
                  onPressed: commandController.canToggleHighlight
                      ? commandController.toggleHighlight
                      : null,
                ),
                _verticalDivider(context),
                FilledButton.tonalIcon(
                  onPressed:
                      hasPdfSelection ? onInsertSelectionReference : null,
                  icon: const Icon(Icons.add_link_rounded, size: 18),
                  label: const Text('PDF selection'),
                ),
                OutlinedButton.icon(
                  onPressed: copiedReference?.isValid == true
                      ? onPasteCopiedReference
                      : null,
                  icon: const Icon(Icons.content_paste_go_rounded, size: 18),
                  label: const Text('Paste source'),
                ),
                if (!hasPdfSelection && copiedReference?.isValid != true)
                  const _OwnedDocumentNoteStatusPill(
                    label: 'Select PDF text to cite',
                    icon: Icons.swipe_rounded,
                  ),
                if (hasPdfSelection)
                  const _OwnedDocumentNoteStatusPill(
                    label: 'PDF selection ready',
                    icon: Icons.check_circle_outline_rounded,
                    prominent: true,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _toolbarButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        isSelected: selected,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          foregroundColor: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          disabledBackgroundColor:
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        ),
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }

  Widget _verticalDivider(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _OwnedDocumentNotesHeader extends StatelessWidget {
  const _OwnedDocumentNotesHeader({
    required this.notes,
    required this.selectedNoteId,
    required this.creatingNote,
    required this.onSelectedNoteChanged,
    required this.onCreateNote,
  });

  final List<StructuredDocumentNote> notes;
  final String? selectedNoteId;
  final bool creatingNote;
  final ValueChanged<String?> onSelectedNoteChanged;
  final VoidCallback onCreateNote;

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

class _EmptyOwnedDocumentNoteState extends StatelessWidget {
  const _EmptyOwnedDocumentNoteState({required this.onCreateNote});

  final VoidCallback onCreateNote;

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
              'Use the owned TextSystem editor for continuous reading notes with PDF references.',
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

class _OwnedDocumentNoteSession {
  _OwnedDocumentNoteSession({
    required this.noteId,
    required this.titleController,
    required this.textController,
    required this.commandController,
    required this.scrollController,
    required this.referenceActionRepository,
    required this.references,
  });

  final String noteId;
  final TextEditingController titleController;
  final TextSystemController textController;
  final TextSystemOwnedEditorCommandController commandController;
  final ScrollController scrollController;
  final TextSystemReferenceActionRepository referenceActionRepository;
  final Map<String, DocumentNotePdfReference> references;

  void dispose() {
    titleController.dispose();
    commandController.dispose();
    scrollController.dispose();
    textController.dispose();
  }
}

class _DecodedOwnedDocumentNote {
  const _DecodedOwnedDocumentNote({
    required this.document,
    required this.references,
  });

  final TextSystemDocument document;
  final Map<String, DocumentNotePdfReference> references;
}

class _EncodedOwnedDocumentNote {
  const _EncodedOwnedDocumentNote({
    required this.plainText,
    required this.jsonText,
  });

  final String plainText;
  final String jsonText;
}

class _OwnedDocumentNoteCodec {
  static _DecodedOwnedDocumentNote decode(StructuredDocumentNote note) {
    final references = Map<String, DocumentNotePdfReference>.from(
      note.pdfReferences,
    );
    final jsonText = note.structuredBlock?.jsonText.trim() ?? '';

    if (jsonText.isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is Map) {
          final normalized = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );

          final rawReferences = normalized['references'];
          if (rawReferences is Map) {
            references.addAll(_referencesFromJson(rawReferences));
          }

          final rawDocument = normalized['textSystemDocument'] ??
              normalized['document'];
          if (rawDocument is Map) {
            final document = TextSystemDocument.fromJson(
              rawDocument.map((key, value) => MapEntry(key.toString(), value)),
            );
            return _DecodedOwnedDocumentNote(
              document: _ensureEditableDocument(document, note.displayTitle),
              references: references,
            );
          }

          final rawNodes = normalized['nodes'];
          if (rawNodes is List) {
            final document = _documentFromStructuredNodes(
              note: note,
              nodes: rawNodes,
              references: references,
            );
            return _DecodedOwnedDocumentNote(
              document: document,
              references: references,
            );
          }
        }
      } catch (_) {
        // Fall through to legacy plain-text import.
      }
    }

    return _DecodedOwnedDocumentNote(
      document: _documentFromLegacyText(note),
      references: references,
    );
  }

  static _EncodedOwnedDocumentNote encode({
    required TextSystemDocument document,
    required Map<String, DocumentNotePdfReference> references,
  }) {
    final activeReferences = _activeReferencesForDocument(
      document: document,
      references: references,
    );
    final jsonText = jsonEncode({
      'version': 3,
      'editor': 'textSystemOwnedPdfReader',
      'textSystemDocument': document.toJson(),
      'references': {
        for (final entry in activeReferences.entries)
          entry.key: entry.value.toJson(),
      },
    });

    return _EncodedOwnedDocumentNote(
      plainText: _plainTextForDocument(document),
      jsonText: jsonText,
    );
  }

  static Map<String, DocumentNotePdfReference> _referencesFromJson(
    Map<dynamic, dynamic> rawReferences,
  ) {
    final output = <String, DocumentNotePdfReference>{};
    for (final entry in rawReferences.entries) {
      final value = entry.value;
      if (value is Map) {
        output[entry.key.toString()] = DocumentNotePdfReference.fromJson(
          value.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    return output;
  }

  static TextSystemDocument _documentFromStructuredNodes({
    required StructuredDocumentNote note,
    required List<dynamic> nodes,
    required Map<String, DocumentNotePdfReference> references,
  }) {
    final blocks = <TextSystemBlock>[];
    var index = 0;

    for (final rawNode in nodes) {
      if (rawNode is! Map) continue;
      final node = rawNode.map((key, value) => MapEntry(key.toString(), value));
      final type = node['type']?.toString() ?? 'paragraph';
      final text = node['text']?.toString() ?? '';

      if (type == 'mathBlock') {
        final latex = (node['latex']?.toString() ?? text).trim();
        blocks.add(
          TextSystemBlock(
            id: 'equation-${++index}',
            type: TextSystemBlockType.custom,
            text: latex,
            metadata: <String, Object?>{
              'kind': 'equation',
              'latex': latex,
              'numbered': false,
              'presentation': 'display',
            },
          ),
        );
        continue;
      }

      if (type == 'todoBlock') {
        blocks.add(
          TextSystemBlock(
            id: 'todo-${++index}',
            type: TextSystemBlockType.todo,
            text: node['title']?.toString() ?? text,
            checked: node['isCompleted'] == true,
            metadata: <String, Object?>{
              if (node['todoId'] != null) 'todoId': node['todoId'].toString(),
              if (node['priority'] != null)
                'priority': node['priority'].toString(),
            },
          ),
        );
        continue;
      }

      final marks = <TextMark>[];
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
          final reference = referenceId == null ? null : references[referenceId];
          if (referenceId == null ||
              reference == null ||
              start == null ||
              end == null ||
              start < 0 ||
              end <= start ||
              end > text.length) {
            continue;
          }
          marks.add(
            TextMark(
              kind: TextMarkKind.link,
              range: TextSystemRange(start, end),
              attributes: _inlineReferenceAttributes(
                referenceId: referenceId,
                reference: reference,
              ),
            ),
          );
        }
      }

      blocks.add(
        TextSystemBlock.paragraph(
          id: 'paragraph-${++index}',
          text: text,
          marks: marks,
        ),
      );
    }

    return _ensureEditableDocument(
      TextSystemDocument(
        id: note.note.id,
        title: note.displayTitle,
        blocks: blocks,
        createdAt: note.note.createdAt,
        updatedAt: note.note.updatedAt,
      ),
      note.displayTitle,
    );
  }

  static TextSystemDocument _documentFromLegacyText(StructuredDocumentNote note) {
    final blocks = <TextSystemBlock>[];
    final source = note.documentText.trim();
    if (source.isEmpty) {
      return TextSystemDocument.singleParagraph(
        id: note.note.id,
        title: note.displayTitle,
        text: '',
      );
    }

    final mathRegex = RegExp(r'\$\$([\s\S]*?)\$\$');
    var cursor = 0;
    var index = 0;

    void addParagraphs(String value) {
      final paragraphs = value
          .split(RegExp(r'\n\s*\n'))
          .map((paragraph) => paragraph.trim())
          .where((paragraph) => paragraph.isNotEmpty);
      for (final paragraph in paragraphs) {
        blocks.add(
          TextSystemBlock.paragraph(
            id: 'paragraph-${++index}',
            text: paragraph,
          ),
        );
      }
    }

    for (final match in mathRegex.allMatches(source)) {
      if (match.start > cursor) {
        addParagraphs(source.substring(cursor, match.start));
      }
      final latex = match.group(1)?.trim() ?? '';
      if (latex.isNotEmpty) {
        blocks.add(
          TextSystemBlock(
            id: 'equation-${++index}',
            type: TextSystemBlockType.custom,
            text: latex,
            metadata: <String, Object?>{
              'kind': 'equation',
              'latex': latex,
              'numbered': false,
              'presentation': 'display',
            },
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < source.length) {
      addParagraphs(source.substring(cursor));
    }

    return _ensureEditableDocument(
      TextSystemDocument(
        id: note.note.id,
        title: note.displayTitle,
        blocks: blocks,
        createdAt: note.note.createdAt,
        updatedAt: note.note.updatedAt,
      ),
      note.displayTitle,
    );
  }

  static TextSystemDocument _ensureEditableDocument(
    TextSystemDocument document,
    String fallbackTitle,
  ) {
    final blocks = document.blocks.isEmpty
        ? <TextSystemBlock>[_emptyParagraphBlock()]
        : document.blocks;
    return document.copyWith(
      title: document.title.trim().isEmpty ? fallbackTitle : document.title,
      blocks: List<TextSystemBlock>.unmodifiable(blocks),
    );
  }

  static Map<String, DocumentNotePdfReference> _activeReferencesForDocument({
    required TextSystemDocument document,
    required Map<String, DocumentNotePdfReference> references,
  }) {
    final activeIds = <String>{};
    for (final block in document.blocks) {
      for (final mark in block.marks) {
        if (mark.kind != TextMarkKind.link) continue;
        final inlineReference =
            TextSystemInlineReferenceMark.tryFromTextMarkAttributes(
          mark.attributes,
        );
        final metadataReferenceId =
            inlineReference?.metadata['pdfReferenceId']?.toString();
        final attrReferenceId = mark.attributes['pdfReferenceId'];
        final referenceId = metadataReferenceId ?? attrReferenceId ?? inlineReference?.id;
        if (referenceId != null && referenceId.trim().isNotEmpty) {
          activeIds.add(referenceId.trim());
        }
      }
    }

    if (activeIds.isEmpty) return references;

    return <String, DocumentNotePdfReference>{
      for (final id in activeIds)
        if (references[id] != null) id: references[id]!,
    };
  }

  static String _plainTextForDocument(TextSystemDocument document) {
    final parts = <String>[];
    for (final block in document.blocks) {
      if (block.type == TextSystemBlockType.custom &&
          block.metadata['kind'] == 'equation') {
        final latex = (block.metadata['latex'] as String?)?.trim() ??
            block.text.trim();
        if (latex.isNotEmpty) parts.add('\$\$\n$latex\n\$\$');
        continue;
      }

      final text = block.text.trim();
      if (text.isEmpty) continue;

      if (block.type == TextSystemBlockType.todo) {
        parts.add('${block.checked == true ? '[x]' : '[ ]'} $text');
      } else {
        parts.add(text);
      }
    }
    return parts.join('\n\n');
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

TextSystemBlock _emptyParagraphBlock() {
  return TextSystemBlock.paragraph(
    id: 'paragraph-${DateTime.now().microsecondsSinceEpoch}',
    text: '',
  );
}

Map<String, String> _inlineReferenceAttributes({
  required String referenceId,
  required DocumentNotePdfReference reference,
}) {
  final inlineReference = TextSystemInlineReferenceMark(
    id: referenceId,
    kind: TextSystemReferenceTargetKind.source,
    targetId: reference.documentId,
    label: reference.citationLabel,
    createdAt: DateTime.now(),
    metadata: <String, Object?>{
      'pdfReferenceId': referenceId,
      'documentId': reference.documentId,
      'pageNumber': reference.pageNumber,
      'excerpt': reference.selectedText,
      'sourceRects': [
        for (final rect in reference.sourceRects.where((rect) => rect.isValid))
          rect.toJson(),
      ],
    },
  );

  return <String, String>{
    TextSystemInlineReferenceMark.inlineAttributeKey:
        jsonEncode(inlineReference.toJson()),
    TextSystemInlineReferenceMark.inlineReferenceIdKey: referenceId,
    TextSystemInlineReferenceMark.inlineReferenceKindKey:
        TextSystemReferenceTargetKind.source.id,
    TextSystemInlineReferenceMark.inlineReferenceTargetIdKey:
        reference.documentId,
    'referenceId': referenceId,
    'pdfReferenceId': referenceId,
    'targetId': reference.documentId,
    'label': reference.citationLabel,
  };
}
