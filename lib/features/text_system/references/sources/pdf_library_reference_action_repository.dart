import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../infrastructure/database/app_database.dart';
import '../actions/text_system_reference_action_models.dart';
import '../actions/text_system_reference_action_repository.dart';
import 'text_system_source_locator.dart';

/// Production-oriented reference repository backed by the app PDF library.
///
/// It exposes imported PDFs and PDF-attached notes/highlights as citation/source
/// targets while keeping manual targets in memory for the current editor session.
class TextSystemPdfLibraryReferenceActionRepository
    extends TextSystemReferenceActionRepository {
  TextSystemPdfLibraryReferenceActionRepository({
    required AppDatabase database,
    List<TextSystemReferenceTarget> seedTargets = const <TextSystemReferenceTarget>[],
  })  : _database = database,
        _sessionTargets = TextSystemMemoryReferenceActionRepository(
          seedTargets: seedTargets,
        );

  final AppDatabase _database;
  final TextSystemMemoryReferenceActionRepository _sessionTargets;

  @override
  Future<List<TextSystemReferenceTarget>> searchTargets({
    required String query,
    required Set<TextSystemReferenceTargetKind> kinds,
    int limit = 12,
  }) async {
    final targets = <TextSystemReferenceTarget>[];
    targets.addAll(await _sessionTargets.searchTargets(query: query, kinds: kinds, limit: limit));
    targets.addAll(await _pdfDocumentTargets(query: query, kinds: kinds));
    targets.addAll(await _pdfNoteTargets(query: query, kinds: kinds));
    targets.addAll(await _todoTargets(query: query, kinds: kinds));
    return _dedupeAndSort(targets).take(limit).toList(growable: false);
  }

  @override
  Future<List<TextSystemReferenceTarget>> recentTargets({
    required Set<TextSystemReferenceTargetKind> kinds,
    int limit = 6,
  }) async {
    final targets = <TextSystemReferenceTarget>[];
    targets.addAll(await _sessionTargets.recentTargets(kinds: kinds, limit: limit));
    targets.addAll(await _pdfDocumentTargets(query: '', kinds: kinds));
    targets.addAll(await _pdfNoteTargets(query: '', kinds: kinds));
    targets.addAll(await _todoTargets(query: '', kinds: kinds));
    return _dedupeAndSort(targets).take(limit).toList(growable: false);
  }

  @override
  Future<TextSystemReferenceTarget> createTarget(
    TextSystemReferenceActionDraft draft,
  ) {
    return _sessionTargets.createTarget(draft);
  }

  @override
  Future<TextSystemReferenceTarget?> resolveTarget(String targetId) async {
    final session = await _sessionTargets.resolveTarget(targetId);
    if (session != null) return session;

    final pdfDocumentId = _documentIdFromTargetId(targetId);
    if (pdfDocumentId != null) {
      final document = await _findPdfDocument(pdfDocumentId);
      if (document != null) {
        final kind = targetId.startsWith('source_pdf_')
            ? TextSystemReferenceTargetKind.source
            : TextSystemReferenceTargetKind.citation;
        final workState = await _workStateForDocument(document.documentId);
        return _targetForPdfDocument(document, kind: kind, workState: workState);
      }
    }

    final locatorParts = _pdfLocatorTargetParts(targetId);
    if (locatorParts != null) {
      final target = await _pdfLocatorTargetByAnchorId(
        anchorId: locatorParts.sourceId,
        kind: locatorParts.kind,
      );
      if (target != null) return target;
    }

    if (targetId.startsWith('todo_')) {
      return _todoTargetById(targetId.substring('todo_'.length));
    }

    return null;
  }

  Future<List<TextSystemReferenceTarget>> _pdfDocumentTargets({
    required String query,
    required Set<TextSystemReferenceTargetKind> kinds,
  }) async {
    final desiredKinds = _sourceBackedKinds(kinds);
    if (desiredKinds.isEmpty) return const <TextSystemReferenceTarget>[];

    final documents = await _database.getAllDocuments();
    final output = <TextSystemReferenceTarget>[];
    for (final document in documents) {
      if (!_matchesDocument(document, query)) continue;
      final workState = await _workStateForDocument(document.documentId);
      for (final kind in desiredKinds) {
        output.add(_targetForPdfDocument(document, kind: kind, workState: workState));
      }
    }
    return output;
  }

  Future<List<TextSystemReferenceTarget>> _pdfNoteTargets({
    required String query,
    required Set<TextSystemReferenceTargetKind> kinds,
  }) async {
    final desiredKinds = _sourceBackedKinds(kinds);
    if (desiredKinds.isEmpty) return const <TextSystemReferenceTarget>[];

    final queryStatement = _database.select(_database.noteAnchors).join([
      innerJoin(
        _database.notes,
        _database.notes.id.equalsExp(_database.noteAnchors.noteId),
      ),
      leftOuterJoin(
        _database.noteBlocks,
        _database.noteBlocks.noteId.equalsExp(_database.notes.id),
      ),
      leftOuterJoin(
        _database.pdfDocuments,
        _database.pdfDocuments.documentId.equalsExp(_database.noteAnchors.documentId),
      ),
    ]);
    queryStatement.where(_database.notes.isArchived.equals(false));
    final rows = await queryStatement.get();

    final output = <TextSystemReferenceTarget>[];
    final seenAnchors = <String>{};

    for (final row in rows) {
      final anchor = row.readTable(_database.noteAnchors);
      if (anchor.documentId == null || anchor.documentId!.trim().isEmpty) {
        continue;
      }
      if (!seenAnchors.add(anchor.id)) continue;

      final note = row.readTable(_database.notes);
      final block = row.readTableOrNull(_database.noteBlocks);
      final document = row.readTableOrNull(_database.pdfDocuments);
      if (!_isUsefulPdfLocatorAnchor(anchor.anchorType, note.noteType)) continue;

      final locator = _sourceLocatorForNoteAnchor(
        note: note,
        block: block,
        anchor: anchor,
        document: document,
      );
      if (!_matchesLocator(locator, query, extra: <String?>[note.title, block?.contentText])) {
        continue;
      }

      for (final kind in desiredKinds) {
        output.add(
          _targetForPdfLocator(
            locator,
            kind: kind,
            noteTitle: note.title,
            blockText: block?.contentText,
            document: document,
            updatedAt: note.updatedAt,
          ),
        );
      }
    }

    return output;
  }

  Future<List<TextSystemReferenceTarget>> _todoTargets({
    required String query,
    required Set<TextSystemReferenceTargetKind> kinds,
  }) async {
    if (kinds.isNotEmpty && !kinds.contains(TextSystemReferenceTargetKind.todo)) {
      return const <TextSystemReferenceTarget>[];
    }

    final queryStatement = _database.select(_database.notes).join([
      leftOuterJoin(
        _database.noteBlocks,
        _database.noteBlocks.noteId.equalsExp(_database.notes.id),
      ),
      leftOuterJoin(
        _database.noteAnchors,
        _database.noteAnchors.noteId.equalsExp(_database.notes.id),
      ),
      leftOuterJoin(
        _database.pdfDocuments,
        _database.pdfDocuments.documentId.equalsExp(_database.noteAnchors.documentId),
      ),
    ]);
    queryStatement.where(
      _database.notes.noteType.equals('todo') &
          _database.notes.isArchived.equals(false),
    );
    final rows = await queryStatement.get();

    final targets = <TextSystemReferenceTarget>[];
    final seenNotes = <String>{};
    for (final row in rows) {
      final note = row.readTable(_database.notes);
      if (!seenNotes.add(note.id)) continue;
      final block = row.readTableOrNull(_database.noteBlocks);
      final anchor = row.readTableOrNull(_database.noteAnchors);
      final document = row.readTableOrNull(_database.pdfDocuments);
      final target = _targetForTodo(
        note: note,
        block: block,
        anchor: anchor,
        document: document,
      );
      if (!_matchesTodoTarget(target, query)) continue;
      targets.add(target);
    }
    return targets;
  }

  Future<TextSystemReferenceTarget?> _todoTargetById(String todoId) async {
    final queryStatement = _database.select(_database.notes).join([
      leftOuterJoin(
        _database.noteBlocks,
        _database.noteBlocks.noteId.equalsExp(_database.notes.id),
      ),
      leftOuterJoin(
        _database.noteAnchors,
        _database.noteAnchors.noteId.equalsExp(_database.notes.id),
      ),
      leftOuterJoin(
        _database.pdfDocuments,
        _database.pdfDocuments.documentId.equalsExp(_database.noteAnchors.documentId),
      ),
    ]);
    queryStatement.where(
      _database.notes.id.equals(todoId) &
          _database.notes.noteType.equals('todo') &
          _database.notes.isArchived.equals(false),
    );
    final rows = await queryStatement.get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return _targetForTodo(
      note: row.readTable(_database.notes),
      block: row.readTableOrNull(_database.noteBlocks),
      anchor: row.readTableOrNull(_database.noteAnchors),
      document: row.readTableOrNull(_database.pdfDocuments),
    );
  }

  Future<TextSystemReferenceTarget?> _pdfLocatorTargetByAnchorId({
    required String anchorId,
    required TextSystemReferenceTargetKind kind,
  }) async {
    final queryStatement = _database.select(_database.noteAnchors).join([
      innerJoin(
        _database.notes,
        _database.notes.id.equalsExp(_database.noteAnchors.noteId),
      ),
      leftOuterJoin(
        _database.noteBlocks,
        _database.noteBlocks.noteId.equalsExp(_database.notes.id),
      ),
      leftOuterJoin(
        _database.pdfDocuments,
        _database.pdfDocuments.documentId.equalsExp(_database.noteAnchors.documentId),
      ),
    ]);
    queryStatement.where(
      (_database.noteAnchors.id.equals(anchorId) |
              _database.notes.id.equals(anchorId)) &
          _database.notes.isArchived.equals(false),
    );

    final rows = await queryStatement.get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    final note = row.readTable(_database.notes);
    final anchor = row.readTable(_database.noteAnchors);
    final block = row.readTableOrNull(_database.noteBlocks);
    final document = row.readTableOrNull(_database.pdfDocuments);
    if (anchor.documentId == null || anchor.documentId!.trim().isEmpty) {
      return null;
    }
    if (!_isUsefulPdfLocatorAnchor(anchor.anchorType, note.noteType)) {
      return null;
    }

    final locator = _sourceLocatorForNoteAnchor(
      note: note,
      block: block,
      anchor: anchor,
      document: document,
    );
    return _targetForPdfLocator(
      locator,
      kind: kind,
      noteTitle: note.title,
      blockText: block?.contentText,
      document: document,
      updatedAt: note.updatedAt,
    );
  }

  Future<_PdfSourceWorkState> _workStateForDocument(String documentId) async {
    final queryStatement = _database.select(_database.notes).join([
      leftOuterJoin(
        _database.noteBlocks,
        _database.noteBlocks.noteId.equalsExp(_database.notes.id),
      ),
      leftOuterJoin(
        _database.noteAnchors,
        _database.noteAnchors.noteId.equalsExp(_database.notes.id),
      ),
    ]);
    queryStatement.where(
      _database.notes.documentId.equals(documentId) &
          _database.notes.isArchived.equals(false),
    );
    final rows = await queryStatement.get();

    var sidecarNoteCount = 0;
    var highlightCount = 0;
    var openTodoCount = 0;
    final seenSidecarAnchors = <String>{};
    final seenHighlightAnchors = <String>{};
    final seenTodoNotes = <String>{};

    for (final row in rows) {
      final note = row.readTable(_database.notes);
      final block = row.readTableOrNull(_database.noteBlocks);
      final anchor = row.readTableOrNull(_database.noteAnchors);

      if (anchor?.anchorType == 'sidecarPosition' && seenSidecarAnchors.add(anchor!.id)) {
        sidecarNoteCount++;
      }
      if ((anchor?.anchorType == 'pdfHighlight' || note.noteType == 'highlight') &&
          anchor != null &&
          seenHighlightAnchors.add(anchor.id)) {
        highlightCount++;
      }
      if (note.noteType == 'todo' && seenTodoNotes.add(note.id)) {
        final metadata = _mapFromJsonString(block?.contentJson);
        final isCompleted = _boolValue(metadata['isCompleted']) ?? false;
        if (!isCompleted) openTodoCount++;
      }
    }

    return _PdfSourceWorkState(
      sidecarNoteCount: sidecarNoteCount,
      highlightCount: highlightCount,
      openTodoCount: openTodoCount,
    );
  }

  TextSystemReferenceTarget _targetForPdfDocument(
    PdfDocument document, {
    required TextSystemReferenceTargetKind kind,
    required _PdfSourceWorkState workState,
  }) {
    final locator = TextSystemSourceLocator(
      sourceKind: 'pdf',
      sourceId: document.documentId,
      sourceTitle: document.name,
      pdfDocumentId: document.documentId,
      pdfPath: document.filePath,
      workState: workState.toJson(),
      createdFrom: 'pdfLibrary',
    );
    final metadata = <String, Object?>{
      ...locator.toReferenceMetadata(),
      'title': document.name,
      if (_authorsFromString(document.authors).isNotEmpty)
        'authors': _authorsFromString(document.authors),
      if (_stringValue(document.journal) != null) 'containerTitle': document.journal,
      if (_stringValue(document.publisher) != null) 'publisher': document.publisher,
      if (_stringValue(document.doi) != null) 'doi': document.doi,
      if (_stringValue(document.subject) != null) 'subject': document.subject,
      if (_stringValue(document.fieldOfStudy) != null) 'fieldOfStudy': document.fieldOfStudy,
      if (_stringValue(document.keywords) != null) 'keywords': document.keywords,
    };

    return TextSystemReferenceTarget(
      id: '${kind.id}_pdf_${document.documentId}',
      kind: kind,
      title: document.name,
      subtitle: _pdfDocumentSubtitle(document, workState),
      uri: Uri(scheme: 'pdf', path: document.documentId),
      citationKey: _citationKeyForPdf(document),
      createdAt: document.addedAt,
      updatedAt: document.metadataLastEditedAt ?? document.fileLastModifiedAt ?? document.addedAt,
      metadata: metadata,
    );
  }

  TextSystemSourceLocator _sourceLocatorForNoteAnchor({
    required Note note,
    required NoteBlock? block,
    required NoteAnchor anchor,
    required PdfDocument? document,
  }) {
    final sourceRects = _sourceRectsFromGeometry(anchor.geometryJson);
    final pageNumber = anchor.pageNumber ??
        (sourceRects.isNotEmpty ? sourceRects.first.pageNumber : null);
    final sourceKind = switch (anchor.anchorType) {
      'pdfHighlight' => 'pdfHighlight',
      'sidecarPosition' => 'pdfSidecarNote',
      'todoPdfTextSelection' || 'todoPdfFreeform' => 'pdfTodo',
      _ => 'pdfNote',
    };

    return TextSystemSourceLocator(
      sourceKind: sourceKind,
      sourceId: anchor.id,
      sourceTitle: document?.name ?? anchor.documentId,
      pdfDocumentId: anchor.documentId,
      pdfPath: document?.filePath,
      pageNumber: pageNumber,
      pageLabel: pageNumber == null ? null : 'p. $pageNumber',
      sidecarNoteId: anchor.anchorType == 'sidecarPosition' ? note.id : null,
      anchorId: anchor.id,
      highlightId: anchor.anchorType == 'pdfHighlight' ? note.id : null,
      excerpt: _cleanExcerpt(anchor.selectedText ?? block?.contentText),
      sourceRects: sourceRects,
      createdFrom: 'pdfNotes',
    );
  }

  TextSystemReferenceTarget _targetForPdfLocator(
    TextSystemSourceLocator locator, {
    required TextSystemReferenceTargetKind kind,
    required String? noteTitle,
    required String? blockText,
    required PdfDocument? document,
    required DateTime updatedAt,
  }) {
    final excerpt = _cleanExcerpt(locator.excerpt ?? noteTitle ?? blockText);
    final title = excerpt ?? locator.compactLabel;
    final sourceTitle = _cleanExcerpt(document?.name ?? locator.sourceTitle ?? locator.compactLabel) ?? title;
    final authors = _authorsFromString(document?.authors);
    final subtitleParts = <String>[
      _sourceKindLabel(locator.sourceKind),
      if (locator.sourceTitle != null && locator.sourceTitle!.trim().isNotEmpty)
        locator.sourceTitle!.trim(),
      if (locator.pageLabel != null) locator.pageLabel!,
    ];

    final metadata = <String, Object?>{
      ...locator.toReferenceMetadata(),
      'title': sourceTitle,
      if (authors.isNotEmpty) 'authors': authors,
      if (excerpt != null) 'excerpt': excerpt,
      if (_stringValue(document?.journal) != null) 'containerTitle': document!.journal,
      if (_stringValue(document?.publisher) != null) 'publisher': document!.publisher,
      if (_stringValue(document?.doi) != null) 'doi': document!.doi,
      if (_stringValue(document?.subject) != null) 'subject': document!.subject,
      if (_stringValue(document?.fieldOfStudy) != null) 'fieldOfStudy': document!.fieldOfStudy,
      if (_stringValue(document?.keywords) != null) 'keywords': document!.keywords,
      if (locator.effectivePageNumber != null) 'locator': '${locator.effectivePageNumber}',
    };

    final query = <String, String>{};
    final pageNumber = locator.effectivePageNumber;
    if (pageNumber != null) query['page'] = '$pageNumber';
    if (locator.anchorId != null) query['anchorId'] = locator.anchorId!;
    if (locator.sidecarNoteId != null) query['noteId'] = locator.sidecarNoteId!;

    return TextSystemReferenceTarget(
      id: '${kind.id}_${locator.sourceKind}_${locator.sourceId}',
      kind: kind,
      title: title,
      subtitle: subtitleParts.join(' · '),
      uri: Uri(
        scheme: 'pdf',
        path: locator.effectivePdfDocumentId ?? locator.sourceId,
        queryParameters: query.isEmpty ? null : query,
      ),
      citationKey: _citationKeyFromLabel(title, locator.effectivePageNumber),
      createdAt: updatedAt,
      updatedAt: updatedAt,
      metadata: metadata,
    );
  }

  TextSystemReferenceTarget _targetForTodo({
    required Note note,
    required NoteBlock? block,
    required NoteAnchor? anchor,
    required PdfDocument? document,
  }) {
    final metadataJson = _mapFromJsonString(block?.contentJson);
    final title = _cleanExcerpt(note.title ?? block?.contentText ?? anchor?.selectedText) ?? 'TODO';
    final isCompleted = _boolValue(metadataJson['isCompleted']) ?? false;
    final priority = _stringValue(metadataJson['priority']) ?? 'medium';
    final deadline = _dateValue(metadataJson['deadline']);

    TextSystemSourceLocator? locator;
    if (anchor != null && document != null) {
      locator = _sourceLocatorForNoteAnchor(
        note: note,
        block: block,
        anchor: anchor,
        document: document,
      );
    }

    final metadata = <String, Object?>{
      'todoId': note.id,
      'title': title,
      'isCompleted': isCompleted,
      'priority': priority,
      if (deadline != null) 'deadline': deadline.toIso8601String(),
      if (locator != null) ...locator.toReferenceMetadata(),
    };

    final subtitleParts = <String>[
      isCompleted ? 'Completed TODO' : 'Open TODO',
      'Priority: $priority',
      if (deadline != null) 'Due ${deadline.toLocal().toIso8601String().split('T').first}',
      if (document != null) document.name,
      if (locator?.pageLabel != null) locator!.pageLabel!,
    ];

    return TextSystemReferenceTarget(
      id: 'todo_${note.id}',
      kind: TextSystemReferenceTargetKind.todo,
      title: title,
      subtitle: subtitleParts.join(' · '),
      uri: Uri(scheme: 'todo', path: note.id),
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      metadata: metadata,
    );
  }

  Future<PdfDocument?> _findPdfDocument(String documentId) {
    return (_database.select(_database.pdfDocuments)
          ..where((table) => table.documentId.equals(documentId))
          ..limit(1))
        .getSingleOrNull();
  }

  static List<TextSystemReferenceTargetKind> _sourceBackedKinds(
    Set<TextSystemReferenceTargetKind> kinds,
  ) {
    final output = <TextSystemReferenceTargetKind>[];
    if (kinds.isEmpty || kinds.contains(TextSystemReferenceTargetKind.citation)) {
      output.add(TextSystemReferenceTargetKind.citation);
    }
    if (kinds.isEmpty || kinds.contains(TextSystemReferenceTargetKind.source)) {
      output.add(TextSystemReferenceTargetKind.source);
    }
    return output;
  }

  static bool _matchesDocument(PdfDocument document, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final haystack = <String?>[
      document.name,
      document.originalFileName,
      document.authors,
      document.subject,
      document.fieldOfStudy,
      document.doi,
      document.arxivId,
      document.journal,
      document.publisher,
      document.keywords,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(normalized);
  }

  static bool _matchesLocator(
    TextSystemSourceLocator locator,
    String query, {
    List<String?> extra = const <String?>[],
  }) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final haystack = <String?>[
      locator.sourceKind,
      locator.sourceTitle,
      locator.pageLabel,
      locator.excerpt,
      ...extra,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(normalized);
  }

  static bool _matchesTodoTarget(TextSystemReferenceTarget target, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final haystack = <String?>[
      target.title,
      target.subtitle,
      _stringValue(target.metadata['priority']),
      _stringValue(target.metadata['deadline']),
      _stringValue(target.metadata['sourceTitle']),
      _stringValue(target.metadata['excerpt']),
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(normalized);
  }

  static bool _isUsefulPdfLocatorAnchor(String anchorType, String noteType) {
    return anchorType == 'sidecarPosition' ||
        anchorType == 'pdfHighlight' ||
        anchorType == 'todoPdfTextSelection' ||
        anchorType == 'todoPdfFreeform' ||
        noteType == 'highlight';
  }

  static List<TextSystemReferenceTarget> _dedupeAndSort(
    List<TextSystemReferenceTarget> targets,
  ) {
    final byId = <String, TextSystemReferenceTarget>{};
    for (final target in targets) {
      byId[target.id] = target;
    }
    final output = byId.values.toList();
    output.sort((a, b) {
      final aUpdated = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bUpdated = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final updated = bUpdated.compareTo(aUpdated);
      if (updated != 0) return updated;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return output;
  }

  static String? _documentIdFromTargetId(String targetId) {
    for (final prefix in <String>['citation_pdf_', 'source_pdf_']) {
      if (targetId.startsWith(prefix)) return targetId.substring(prefix.length);
    }
    return null;
  }

  static _PdfLocatorTargetParts? _pdfLocatorTargetParts(String targetId) {
    final firstSeparator = targetId.indexOf('_');
    if (firstSeparator <= 0) return null;
    final secondSeparator = targetId.indexOf('_', firstSeparator + 1);
    if (secondSeparator <= firstSeparator + 1 || secondSeparator >= targetId.length - 1) {
      return null;
    }

    final kind = TextSystemReferenceTargetKindX.fromId(
      targetId.substring(0, firstSeparator),
    );
    if (kind != TextSystemReferenceTargetKind.citation &&
        kind != TextSystemReferenceTargetKind.source) {
      return null;
    }

    final sourceKind = targetId.substring(firstSeparator + 1, secondSeparator);
    if (!sourceKind.startsWith('pdf') || sourceKind == 'pdf') return null;

    final sourceId = targetId.substring(secondSeparator + 1).trim();
    if (sourceId.isEmpty) return null;

    return _PdfLocatorTargetParts(
      kind: kind,
      sourceKind: sourceKind,
      sourceId: sourceId,
    );
  }
}

class _PdfLocatorTargetParts {
  const _PdfLocatorTargetParts({
    required this.kind,
    required this.sourceKind,
    required this.sourceId,
  });

  final TextSystemReferenceTargetKind kind;
  final String sourceKind;
  final String sourceId;
}

class _PdfSourceWorkState {
  const _PdfSourceWorkState({
    required this.sidecarNoteCount,
    required this.highlightCount,
    required this.openTodoCount,
  });

  final int sidecarNoteCount;
  final int highlightCount;
  final int openTodoCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sidecarNoteCount': sidecarNoteCount,
      'highlightCount': highlightCount,
      'openTodoCount': openTodoCount,
    };
  }
}

String _pdfDocumentSubtitle(PdfDocument document, _PdfSourceWorkState workState) {
  final parts = <String>[
    'PDF library',
    if (_stringValue(document.authors) != null) document.authors!.trim(),
    if (_stringValue(document.journal) != null) document.journal!.trim(),
    if (workState.sidecarNoteCount > 0) '${workState.sidecarNoteCount} note${workState.sidecarNoteCount == 1 ? '' : 's'}',
    if (workState.highlightCount > 0) '${workState.highlightCount} highlight${workState.highlightCount == 1 ? '' : 's'}',
    if (workState.openTodoCount > 0) '${workState.openTodoCount} open TODO${workState.openTodoCount == 1 ? '' : 's'}',
  ];
  return parts.join(' · ');
}

String? _citationKeyForPdf(PdfDocument document) {
  final authors = _authorsFromString(document.authors);
  final firstAuthor = authors.isEmpty ? document.name : authors.first;
  return _citationKeyFromLabel(firstAuthor, null);
}

String? _citationKeyFromLabel(String label, int? pageNumber) {
  final words = label
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .take(4)
      .toList(growable: false);
  if (words.isEmpty) return null;
  final base = words.first.toLowerCase() +
      words.skip(1).map((word) {
        if (word.isEmpty) return '';
        return word[0].toUpperCase() + word.substring(1);
      }).join();
  return pageNumber == null ? base : '${base}P$pageNumber';
}

List<String> _authorsFromString(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return const <String>[];
  return value
      .split(RegExp(r'\s*;\s*|\s+and\s+|\s+&\s+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

String _sourceKindLabel(String sourceKind) {
  return switch (sourceKind) {
    'pdf' => 'PDF',
    'pdfSidecarNote' => 'PDF sidecar note',
    'pdfHighlight' => 'PDF highlight',
    'pdfTodo' => 'PDF TODO',
    'pdfNote' => 'PDF note',
    _ => 'PDF source',
  };
}

String? _cleanExcerpt(String? value) {
  if (value == null) return null;
  final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return null;
  return clean.length <= 120 ? clean : '${clean.substring(0, 117)}…';
}

String? _stringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is String) return bool.tryParse(value);
  if (value is num) return value != 0;
  return null;
}

DateTime? _dateValue(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

Map<String, Object?> _mapFromJsonString(String? value) {
  if (value == null || value.trim().isEmpty) return const <String, Object?>{};
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return decoded.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?));
    }
  } catch (_) {
    return const <String, Object?>{};
  }
  return const <String, Object?>{};
}

List<TextSystemSourceRect> _sourceRectsFromGeometry(String? geometryJson) {
  final geometry = _mapFromJsonString(geometryJson);
  final rawRects = geometry['sourceRects'];
  if (rawRects is! List) return const <TextSystemSourceRect>[];
  return rawRects
      .whereType<Map>()
      .map((item) => TextSystemSourceRect.fromJson(
            item.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?)),
          ))
      .where((rect) => rect.isValid)
      .toList(growable: false);
}
