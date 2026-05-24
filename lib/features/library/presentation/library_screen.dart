import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import '../../home/presentation/study_home_screen.dart';
import '../../planning/data/study_planning_repository.dart';
import '../../planning/presentation/create_workspace_document_screen.dart';
import '../../planning/presentation/dev_todo_drawer.dart';
import '../../planning/presentation/project_quick_access_sheet.dart';
import '../../planning/presentation/document_workspace_screen.dart';
import '../../reader/presentation/reader_screen.dart';
import '../../tags/data/tag_repository.dart';
import '../../tags/presentation/tag_icon_registry.dart';
import '../../tags/presentation/tag_manager_dialog.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../text_system/presentation/text_system_test_env_screen.dart';
import '../data/document_import_service.dart';
import '../data/epub_import_service.dart';
import '../data/epub_library_repository.dart';
import '../data/epub_metadata_extractor.dart';
import '../data/pdf_metadata_extractor.dart';
import '../data/online_metadata_lookup_service.dart';
import '../domain/epub_library_document.dart';

enum LibrarySortField { name, authors, addedAt, fileLastModifiedAt, subject }

class LibraryTodayWorkSession {
  const LibraryTodayWorkSession({
    required this.date,
    required this.createdAt,
    required this.items,
  });

  final DateTime date;
  final DateTime createdAt;
  final List<LibraryTodayWorkItem> items;

  int get itemCount => items.length;
}

class LibraryTodayWorkItem {
  const LibraryTodayWorkItem({
    required this.id,
    required this.title,
    required this.description,
    this.sourceLabel,
    this.sourceIcon,
    this.onOpenSource,
    this.onComplete,
  });

  final String id;
  final String title;
  final String description;
  final String? sourceLabel;
  final IconData? sourceIcon;
  final Future<void> Function()? onOpenSource;
  final Future<void> Function()? onComplete;
}


final ValueNotifier<LibraryTodayWorkSession?> libraryTodayWorkSessionStore =
    ValueNotifier<LibraryTodayWorkSession?>(null);

class _LibraryChroma {
  const _LibraryChroma({
    required this.accent,
    required this.soft,
    required this.canvas,
    required this.surface,
    required this.navSurface,
    required this.border,
    required this.borderStrong,
  });

  final Color accent;
  final Color soft;
  final Color canvas;
  final Color surface;
  final Color navSurface;
  final Color border;
  final Color borderStrong;

  static _LibraryChroma current() => _LibraryColorSystem.monthChroma(DateTime.now().month);
}

class _LibraryColorSystem {
  const _LibraryColorSystem._();

  static _LibraryChroma monthChroma(int month) {
    final accent = monthAccent(month);
    final base = monthWeekDayTint(month, alternateTone: false, saturated: false);
    final baseAlt = monthWeekDayTint(month, alternateTone: true, saturated: false);
    return _LibraryChroma(
      accent: accent,
      soft: _tint(accent, .90),
      surface: _blend(_tint(base, .42), Colors.white, .52),
      canvas: _blend(_tint(base, .72), const Color(0xFFFCFBF7), .72),
      navSurface: _blend(_tint(baseAlt, .76), Colors.white, .78),
      border: _blend(accent, const Color(0xFFE8E1D6), .84),
      borderStrong: _blend(accent, const Color(0xFFDCD3C8), .72),
    );
  }

  static Color _tint(Color color, double amount) => Color.lerp(color, Colors.white, amount)!;

  static Color _blend(Color a, Color b, double amount) => Color.lerp(a, b, amount)!;

  static Color monthAccent(int month) {
    switch (month) {
      case 1:
        return const Color(0xFF4F6C8C); // January: winter blue slate
      case 2:
        return const Color(0xFF7A5F8B); // February: winter plum
      case 3:
        return const Color(0xFF5E8A68); // March: early spring green
      case 4:
        return const Color(0xFF7B8E48); // April: leaf olive
      case 5:
        return const Color(0xFF4F8B78); // May: fresh sage teal
      case 6:
        return const Color(0xFFA98339); // June: warm ochre
      case 7:
        return const Color(0xFFB46F46); // July: sun clay
      case 8:
        return const Color(0xFF8B7B43); // August: dry grass
      case 9:
        return const Color(0xFF9A6E3D); // September: amber
      case 10:
        return const Color(0xFF9A5B43); // October: rust
      case 11:
        return const Color(0xFF7A5A63); // November: muted berry
      case 12:
      default:
        return const Color(0xFF55726B); // December: evergreen slate
    }
  }

  static Color monthWeekDayTint(
    int month, {
    required bool alternateTone,
    required bool saturated,
  }) {
    final set = _seasonSet(month);
    final tone = alternateTone ? 1 : 0;
    switch (_seasonForMonth(month)) {
      case _LibrarySeason.winter:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFF2F5F6) : const Color(0xFFE9EEF1))
              : (tone == 0 ? const Color(0xFFF7F9FA) : const Color(0xFFF1F4F6));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF3F1F6) : const Color(0xFFEBE7F0))
            : (tone == 0 ? const Color(0xFFF8F7FA) : const Color(0xFFF2F0F6));
      case _LibrarySeason.spring:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFF1F6EF) : const Color(0xFFE8F1E5))
              : (tone == 0 ? const Color(0xFFF7FAF5) : const Color(0xFFF1F6EE));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF4F4EA) : const Color(0xFFECECD9))
            : (tone == 0 ? const Color(0xFFFAFAF5) : const Color(0xFFF4F4EA));
      case _LibrarySeason.summer:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFFAF4E7) : const Color(0xFFF3E8D2))
              : (tone == 0 ? const Color(0xFFFCF9F1) : const Color(0xFFF8F1E5));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF9EFE7) : const Color(0xFFF0DFD2))
            : (tone == 0 ? const Color(0xFFFCF7F3) : const Color(0xFFF8EEE7));
      case _LibrarySeason.autumn:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFFAF1E9) : const Color(0xFFF0E2D5))
              : (tone == 0 ? const Color(0xFFFCF8F4) : const Color(0xFFF6EEE7));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF8EEEE) : const Color(0xFFEEDDDD))
            : (tone == 0 ? const Color(0xFFFCF7F7) : const Color(0xFFF5EDED));
    }
  }

  static _LibrarySeason _seasonForMonth(int month) {
    if (month == 12 || month == 1 || month == 2) return _LibrarySeason.winter;
    if (month >= 3 && month <= 5) return _LibrarySeason.spring;
    if (month >= 6 && month <= 8) return _LibrarySeason.summer;
    return _LibrarySeason.autumn;
  }

  static int _seasonSet(int month) {
    switch (month) {
      case 1:
      case 3:
      case 5:
      case 6:
      case 8:
      case 9:
      case 11:
        return 0;
      case 2:
      case 4:
      case 7:
      case 10:
      case 12:
      default:
        return 1;
    }
  }
}

enum _LibrarySeason { winter, spring, summer, autumn }

class LibraryScreen extends StatefulWidget {
  final AppDatabase database;
  final StudyPlanningRepository? planningRepository;
  final LibraryTodayWorkSession? todayWorkSession;

  const LibraryScreen({
    super.key,
    required this.database,
    this.planningRepository,
    this.todayWorkSession,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();

  LibrarySortField _sortField = LibrarySortField.addedAt;
  bool _sortAscending = false;

  bool _isDragging = false;
  bool _isImporting = false;
  bool _isImportingEpub = false;

  String _searchQuery = '';
  final Set<int> _selectedTagFilterIds = <int>{};
  bool _matchAllSelectedTags = false;
  _LibraryCollectionSelection _librarySelection = const _LibraryCollectionSelection.all();

  late final DocumentImportService _importService;
  late final EpubLibraryRepository _epubLibraryRepository;
  late final EpubImportService _epubImportService;
  late final OnlineMetadataLookupService _onlineMetadataLookupService;
  late final TagRepository _tagRepository;
  late final StudyPlanningRepository _planningRepository;
  late final bool _ownsPlanningRepository;
  bool _planningLoaded = false;
  bool _epubLibraryLoaded = false;
  List<EpubLibraryDocument> _epubDocuments = const <EpubLibraryDocument>[];
  final Set<String> _todayWorkDoneIds = <String>{};

  @override
  void initState() {
    super.initState();
    libraryTodayWorkSessionStore.addListener(_onTodayWorkSessionChanged);

    _importService = DocumentImportService(
      database: widget.database,
      metadataExtractor: PdfMetadataExtractor(),
    );
    _epubLibraryRepository = EpubLibraryRepository();
    _epubImportService = EpubImportService(
      repository: _epubLibraryRepository,
      metadataExtractor: EpubMetadataExtractor(),
    );
    _onlineMetadataLookupService = OnlineMetadataLookupService();
    _tagRepository = TagRepository(database: widget.database);
    _ownsPlanningRepository = widget.planningRepository == null;
    _planningRepository = widget.planningRepository ?? StudyPlanningRepository();
    _loadPlanning();
    unawaited(_loadEpubLibrary());

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    libraryTodayWorkSessionStore.removeListener(_onTodayWorkSessionChanged);
    _searchController.dispose();
    if (_ownsPlanningRepository) {
      _planningRepository.dispose();
    }
    super.dispose();
  }

  void _onTodayWorkSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPlanning() async {
    await _planningRepository.load();
    if (!mounted) return;
    setState(() => _planningLoaded = true);
  }

  Future<void> _loadEpubLibrary() async {
    final documents = await _epubLibraryRepository.loadDocuments();
    if (!mounted) return;
    setState(() {
      _epubDocuments = documents;
      _epubLibraryLoaded = true;
    });
  }

  Future<void> _openTagManager() async {
    await showDialog<void>(
      context: context,
      builder: (context) => TagManagerDialog(tagRepository: _tagRepository),
    );
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const SettingsScreen(),
    );
  }

  Future<void> _openDevTodos() async {
    await showDevTodoDrawer(
      context: context,
      planningRepository: _planningRepository,
    );
  }

  Future<void> _openTextSystemTestEnv() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TextSystemTestEnvScreen(
          database: widget.database,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _createWorkspaceDocument() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreateWorkspaceDocumentScreen(
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _openWorkspaceDocument(WorkspaceDocument document) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DocumentWorkspaceScreen(
          planningRepository: _planningRepository,
          initialDocumentId: document.id,
        ),
      ),
    );
  }

  Future<void> _openProjectQuickAccess() async {
    await _planningRepository.load();
    if (!mounted) return;
    await showProjectQuickAccessSheet(
      context: context,
      planningRepository: _planningRepository,
      sourceLabel: 'PDF library',
      database: widget.database,
    );
  }


  Future<void> _createLibraryFolder({String? projectId, String? parentId}) async {
    await _planningRepository.load();
    if (!mounted) return;

    final title = await showDialog<String>(
      context: context,
      builder: (_) => _CreateLibraryFolderDialog(
        scopeLabel: _folderScopeLabel(projectId: projectId, parentId: parentId),
      ),
    );

    if (title == null || title.trim().isEmpty) return;
    final folder = await _planningRepository.createLibraryFolder(
      title: title,
      projectId: projectId,
      parentId: parentId,
    );
    if (!mounted) return;
    setState(() {
      _librarySelection = _LibraryCollectionSelection.folder(folder.id);
    });
  }

  String _folderScopeLabel({String? projectId, String? parentId}) {
    if (parentId != null && parentId.trim().isNotEmpty) {
      final folder = _planningRepository.libraryFolderById(parentId.trim());
      if (folder != null) return folder.title;
    }
    if (projectId != null && projectId.trim().isNotEmpty) {
      final project = _planningRepository.projectById(projectId.trim());
      if (project != null) return project.title;
    }
    return 'Uncategorized';
  }

  Future<void> _openDocumentFolderPicker(PdfDocument document) async {
    await _planningRepository.load();
    if (!mounted) return;

    final selectedFolderId = await showDialog<String?>(
      context: context,
      builder: (_) => _PdfFolderAssignmentDialog(
        documentTitle: document.name,
        projects: _planningRepository.projects,
        folders: _planningRepository.libraryFolders,
        currentFolderId: _planningRepository.folderIdForPdf(document.documentId),
      ),
    );

    if (selectedFolderId == null) return;
    if (selectedFolderId.isEmpty) {
      await _planningRepository.clearPdfFolder(document.documentId);
    } else {
      await _planningRepository.assignPdfToFolder(
        documentId: document.documentId,
        folderId: selectedFolderId,
      );
    }
    if (!mounted) return;
    setState(() {});
  }

  List<PdfDocument> _applyLibrarySelection(List<PdfDocument> documents) {
    return documents.where((document) => _documentMatchesLibrarySelection(document, _librarySelection)).toList(growable: false);
  }

  bool _documentMatchesLibrarySelection(PdfDocument document, _LibraryCollectionSelection selection) {
    final documentId = document.documentId;
    final projectId = _planningRepository.pdfProjectIds[documentId];
    final folderId = _planningRepository.folderIdForPdf(documentId);

    switch (selection.kind) {
      case _LibraryCollectionKind.all:
        return true;
      case _LibraryCollectionKind.uncategorized:
        return projectId == null || projectId.isEmpty;
      case _LibraryCollectionKind.uncategorizedUnfiled:
        return (projectId == null || projectId.isEmpty) && (folderId == null || folderId.isEmpty);
      case _LibraryCollectionKind.project:
        return projectId == selection.projectId;
      case _LibraryCollectionKind.projectUnfiled:
        return projectId == selection.projectId && (folderId == null || folderId.isEmpty);
      case _LibraryCollectionKind.folder:
        final selectedFolderId = selection.folderId;
        if (selectedFolderId == null || selectedFolderId.isEmpty || folderId == null || folderId.isEmpty) {
          return false;
        }
        if (folderId == selectedFolderId) return true;
        return _planningRepository.libraryFolderDescendants(selectedFolderId).any((folder) => folder.id == folderId);
    }
  }

  int _countDocumentsForSelection(List<PdfDocument> documents, _LibraryCollectionSelection selection) {
    var count = 0;
    for (final document in documents) {
      if (_documentMatchesLibrarySelection(document, selection)) count += 1;
    }
    return count;
  }

  Future<void> _openCalendarOverview() async {
    final noteRepository = NoteRepository(widget.database);
    await showStudyCalendarModal(
      context: context,
      planningRepository: _planningRepository,
      noteRepository: noteRepository,
      onOpenTodo: _openTodoSourceFromCalendar,
    );
  }

  Future<void> _openDailyBrief() async {
    await showTodayBriefingModal(
      context: context,
      database: widget.database,
      planningRepository: _planningRepository,
    );
  }

  Future<void> _openTodoSourceFromCalendar(TodoItem todo) async {
    final documentId = todo.note.documentId;
    if (documentId == null || documentId.trim().isEmpty) {
      _showSnackBar('This todo is not linked to a PDF yet.');
      return;
    }

    final documents = await widget.database.getAllDocuments();
    PdfDocument? document;
    for (final candidate in documents) {
      if (candidate.documentId == documentId) {
        document = candidate;
        break;
      }
    }

    if (!mounted) return;
    if (document == null) {
      _showSnackBar('Could not find the linked document.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen.pdf(
          database: widget.database,
          documentId: document!.documentId,
          filePath: document!.filePath,
          title: document!.name,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openDocumentProjectPicker(PdfDocument document) async {
    await _planningRepository.load();
    if (!mounted) return;

    final selectedProjectId = await showDialog<String?>(
      context: context,
      builder: (_) => _PdfProjectAssignmentDialog(
        documentTitle: document.name,
        projects: _planningRepository.projects,
        currentProjectId: _planningRepository.pdfProjectIds[document.documentId],
      ),
    );

    if (selectedProjectId == null) return;

    if (selectedProjectId.isEmpty) {
      await _planningRepository.clearPdfProject(document.documentId);
    } else {
      await _planningRepository.assignPdfToProject(
        documentId: document.documentId,
        projectId: selectedProjectId,
      );
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openDocumentTagPicker(
    PdfDocument document,
    List<AppTag> assignedTags,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => DocumentTagPickerDialog(
        tagRepository: _tagRepository,
        document: document,
        initiallyAssignedTags: assignedTags,
      ),
    );
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      lockParentWindow: true,
    );

    if (result == null) {
      return;
    }

    final files = result.files
        .where((file) => file.path != null)
        .map((file) => File(file.path!))
        .toList();

    await _importFiles(files);
  }

  Future<void> _importEpub() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      allowMultiple: true,
      lockParentWindow: true,
    );

    if (result == null) return;

    final files = result.files
        .where((file) => file.path != null)
        .map((file) => File(file.path!))
        .toList();

    await _importFiles(files);
  }

  Future<void> _importDroppedItems(List<DropItem> items) async {
    debugPrint('Drop item count: ${items.length}');

    final files = <File>[];

    for (final item in items) {
      final rawPath = item.path;
      final path = _normalizeDroppedPath(rawPath);

      debugPrint('Dropped raw path: $rawPath');
      debugPrint('Dropped normalized path: $path');

      final lowerPath = path.toLowerCase();
      if (!lowerPath.endsWith('.pdf') && !lowerPath.endsWith('.epub')) {
        debugPrint('Skipped non-reader file: $path');
        continue;
      }

      final file = File(path);
      final exists = await file.exists();

      debugPrint('Dropped file exists: $exists');

      if (!exists) {
        debugPrint('Skipped missing file: $path');
        continue;
      }

      final type = await FileSystemEntity.type(path);
      debugPrint('Dropped entity type: $type');

      if (type != FileSystemEntityType.file) {
        debugPrint('Skipped non-file entity: $path');
        continue;
      }

      files.add(file);
    }

    debugPrint('Valid dropped reader file count: ${files.length}');

    if (files.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drop one or more PDF or EPUB files to import.')),
      );
      return;
    }

    await _importFiles(files);
  }

  String _normalizeDroppedPath(String rawPath) {
    var path = rawPath.trim();

    if (path.startsWith('"') && path.endsWith('"')) {
      path = path.substring(1, path.length - 1);
    }

    if (path.startsWith("'") && path.endsWith("'")) {
      path = path.substring(1, path.length - 1);
    }

    if (path.startsWith('file:')) {
      try {
        path = Uri.parse(path).toFilePath(windows: Platform.isWindows);
      } catch (_) {
        path = path.replaceFirst(RegExp(r'^file:/*'), '');
      }
    } else {
      try {
        path = Uri.decodeFull(path);
      } catch (_) {
        // Keep the raw path if it is not valid URI-encoded text.
      }
    }

    if (Platform.isWindows) {
      path = path.replaceFirst(RegExp(r'^\\\\\?\\'), '');

      // Some drag providers report Windows paths as /C:/Users/...
      if (RegExp(r'^/[A-Za-z]:[/\\]').hasMatch(path)) {
        path = path.substring(1);
      }
    }

    return path;
  }

  Future<void> _importFiles(List<File> files) async {
    debugPrint('Import requested for ${files.length} file(s).');

    final pdfFiles = files
        .where((file) => file.path.toLowerCase().endsWith('.pdf'))
        .toList();
    final epubFiles = files
        .where((file) => file.path.toLowerCase().endsWith('.epub'))
        .toList();

    debugPrint('PDF files after filtering: ${pdfFiles.length}');
    debugPrint('EPUB files after filtering: ${epubFiles.length}');

    if (pdfFiles.isEmpty && epubFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF or EPUB files found.')),
      );
      return;
    }

    setState(() {
      _isImporting = pdfFiles.isNotEmpty;
      _isImportingEpub = epubFiles.isNotEmpty;
    });

    final importedDocuments = <PdfDocument>[];
    final importedEpubDocuments = <EpubLibraryDocument>[];

    try {
      for (final file in pdfFiles) {
        debugPrint('Importing PDF: ${file.path}');
        final document = await _importService.importPdf(file);
        importedDocuments.add(document);
        debugPrint('Imported PDF: ${document.documentId} | ${document.name}');
      }

      for (final file in epubFiles) {
        debugPrint('Importing EPUB: ${file.path}');
        final document = await _epubImportService.importEpub(file);
        importedEpubDocuments.add(document);
        debugPrint('Imported EPUB: ${document.documentId} | ${document.displayTitle}');
      }

      if (importedEpubDocuments.isNotEmpty) {
        await _loadEpubLibrary();
      }

      if (!mounted) return;

      final pieces = <String>[];
      if (importedDocuments.isNotEmpty) {
        pieces.add(importedDocuments.length == 1
            ? 'Imported 1 PDF'
            : 'Imported ${importedDocuments.length} PDFs');
      }
      if (importedEpubDocuments.isNotEmpty) {
        pieces.add(importedEpubDocuments.length == 1
            ? 'Imported 1 EPUB'
            : 'Imported ${importedEpubDocuments.length} EPUBs');
      }

      final singleImportedDocument = importedDocuments.length == 1 && importedEpubDocuments.isEmpty
          ? importedDocuments.single
          : null;
      final singleImportedEpub = importedEpubDocuments.length == 1 && importedDocuments.isEmpty
          ? importedEpubDocuments.single
          : null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${pieces.join(' and ')}.'),
          action: singleImportedDocument != null
              ? SnackBarAction(
                  label: 'Review metadata',
                  onPressed: () {
                    unawaited(
                      _openMetadataEditor(
                        singleImportedDocument,
                        dialogTitle: 'Review imported PDF metadata',
                      ),
                    );
                  },
                )
              : singleImportedEpub == null
                  ? null
                  : SnackBarAction(
                      label: 'Open',
                      onPressed: () => _openEpubDocument(singleImportedEpub),
                    ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Import failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _isImportingEpub = false;
        });
      }
    }
  }

  Future<void> _openEpubDocument(EpubLibraryDocument document) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReaderScreen.epub(
          database: widget.database,
          documentId: document.documentId,
          filePath: document.filePath,
          title: document.displayTitle,
          sourceLabel: 'Library EPUB',
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEpubDocument(EpubLibraryDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete EPUB?'),
        content: Text('Remove “${document.displayTitle}” from the EPUB library and delete the cached file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteEpubDocument(document);
  }

  Future<void> _deleteEpubDocument(EpubLibraryDocument document) async {
    try {
      await _epubLibraryRepository.deleteDocument(document.documentId);
      final cachedFile = File(document.filePath);
      if (await cachedFile.exists()) {
        await cachedFile.delete();
      }
      await _loadEpubLibrary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted “${document.displayTitle}”.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Delete EPUB failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $error')),
      );
    }
  }

  List<PdfDocument> _filterAndSortDocuments(
    List<PdfDocument> documents,
    Map<String, List<AppTag>> documentTags,
  ) {
    final filtered = documents.where((document) {
      final tags = documentTags[document.documentId] ?? const <AppTag>[];

      return _matchesSearch(document, tags) && _matchesTagFilter(tags);
    }).toList();

    return _sortDocuments(filtered);
  }

  bool _matchesSearch(PdfDocument document, List<AppTag> tags) {
    if (_searchQuery.isEmpty) return true;

    final haystack = [
      document.name,
      document.originalFileName,
      document.authors ?? '',
      document.subject ?? '',
      document.fieldOfStudy ?? '',
      document.doi ?? '',
      document.arxivId ?? '',
      document.journal ?? '',
      document.publisher ?? '',
      document.keywords ?? '',
      ...tags.map((tag) => tag.name),
      ...tags.map((tag) => tag.description ?? ''),
    ].join(' ').toLowerCase();

    return haystack.contains(_searchQuery);
  }

  bool _matchesTagFilter(List<AppTag> tags) {
    if (_selectedTagFilterIds.isEmpty) return true;

    final tagIds = tags.map((tag) => tag.id).toSet();

    if (_matchAllSelectedTags) {
      return _selectedTagFilterIds.every(tagIds.contains);
    }

    return _selectedTagFilterIds.any(tagIds.contains);
  }

  void _toggleTagFilter(int tagId) {
    setState(() {
      if (_selectedTagFilterIds.contains(tagId)) {
        _selectedTagFilterIds.remove(tagId);
      } else {
        _selectedTagFilterIds.add(tagId);
      }
    });
  }

  void _clearTagFilters() {
    setState(_selectedTagFilterIds.clear);
  }

  List<PdfDocument> _sortDocuments(List<PdfDocument> documents) {
    final sorted = [...documents];

    int compareNullableStrings(String? a, String? b) {
      final left = a?.toLowerCase() ?? '';
      final right = b?.toLowerCase() ?? '';
      return left.compareTo(right);
    }

    int comparison(PdfDocument a, PdfDocument b) {
      switch (_sortField) {
        case LibrarySortField.name:
          return compareNullableStrings(a.name, b.name);
        case LibrarySortField.authors:
          return compareNullableStrings(a.authors, b.authors);
        case LibrarySortField.addedAt:
          return a.addedAt.compareTo(b.addedAt);
        case LibrarySortField.fileLastModifiedAt:
          final left =
              a.fileLastModifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right =
              b.fileLastModifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return left.compareTo(right);
        case LibrarySortField.subject:
          return compareNullableStrings(a.subject, b.subject);
      }
    }

    sorted.sort((a, b) {
      final result = comparison(a, b);
      return _sortAscending ? result : -result;
    });

    return sorted;
  }

  void _setSort(LibrarySortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
    });
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '';

    final date = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _formatShortDate(DateTime? value) {
    if (value == null) return 'Unknown';

    final date = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  String _metadataQualityLabel(PdfDocument document) {
    final score = _metadataQualityScore(document);

    if (score >= 5) return 'Metadata rich';
    if (score >= 3) return 'Metadata partial';
    return 'Metadata sparse';
  }

  int _metadataQualityScore(PdfDocument document) {
    return [
      document.authors,
      document.doi,
      document.journal,
      document.publisher,
      document.subject,
      document.keywords,
      document.fieldOfStudy,
    ].where((value) => value != null && value.trim().isNotEmpty).length;
  }

  Color _metadataQualityColor(BuildContext context, PdfDocument document) {
    final score = _metadataQualityScore(document);
    final colorScheme = Theme.of(context).colorScheme;

    if (score >= 5) return Colors.green.shade700;
    if (score >= 3) return Colors.orange.shade800;
    return colorScheme.error;
  }

  String _sortLabel(LibrarySortField field) {
    switch (field) {
      case LibrarySortField.name:
        return 'Title';
      case LibrarySortField.authors:
        return 'Authors';
      case LibrarySortField.addedAt:
        return 'Added';
      case LibrarySortField.fileLastModifiedAt:
        return 'Modified';
      case LibrarySortField.subject:
        return 'Subject';
    }
  }

  void _openDocument(PdfDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen.pdf(
          database: widget.database,
          documentId: document.documentId,
          filePath: document.filePath,
          title: document.name,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _openMetadataEditor(
    PdfDocument document, {
    String dialogTitle = 'Edit PDF metadata',
    ExtractedPdfMetadata? extractedMetadata,
  }) async {
    final update = await showDialog<_DocumentMetadataUpdate>(
      context: context,
      builder: (context) => _MetadataEditorDialog(
        document: document,
        dialogTitle: dialogTitle,
        extractedMetadata: extractedMetadata,
      ),
    );

    if (update == null) return;

    await _applyMetadataUpdate(document, update);
  }

  Future<void> _applyMetadataUpdate(
    PdfDocument document,
    _DocumentMetadataUpdate update, {
    String? successMessage,
  }) async {
    await (widget.database.update(
      widget.database.pdfDocuments,
    )..where((table) => table.documentId.equals(document.documentId))).write(
      PdfDocumentsCompanion(
        name: drift.Value(update.name),
        authors: drift.Value(_emptyToNull(update.authors)),
        subject: drift.Value(_emptyToNull(update.subject)),
        fieldOfStudy: drift.Value(_emptyToNull(update.fieldOfStudy)),
        isbn: drift.Value(_emptyToNull(update.isbn)),
        doi: drift.Value(_emptyToNull(update.doi)),
        issn: drift.Value(_emptyToNull(update.issn)),
        arxivId: drift.Value(_emptyToNull(update.arxivId)),
        journal: drift.Value(_emptyToNull(update.journal)),
        publisher: drift.Value(_emptyToNull(update.publisher)),
        keywords: drift.Value(_emptyToNull(update.keywords)),
        metadataLastEditedAt: drift.Value(DateTime.now()),
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          successMessage ?? 'Updated metadata for “${update.name}”.',
        ),
      ),
    );
  }

  Future<void> _refreshLocalMetadata(PdfDocument document) async {
    try {
      final file = File(document.filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cached PDF file could not be found.')),
        );
        return;
      }

      final extracted = await PdfMetadataExtractor().extract(file);

      if (!mounted) return;

      await _openMetadataEditor(
        document,
        dialogTitle: 'Review extracted PDF metadata',
        extractedMetadata: extracted,
      );
    } catch (error, stackTrace) {
      debugPrint('Metadata refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Metadata extraction failed: $error')),
      );
    }
  }

  Future<void> _showOnlineMetadataInfo(PdfDocument document) async {
    final update = await showDialog<_DocumentMetadataUpdate>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _OnlineMetadataLookupDialog(
        document: document,
        lookupService: _onlineMetadataLookupService,
      ),
    );

    if (update == null) return;

    await _applyMetadataUpdate(
      document,
      update,
      successMessage: 'Applied online metadata to “${update.name}”.',
    );
  }

  Future<void> _revealFile(PdfDocument document) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', ['/select,', document.filePath]);
      } else if (Platform.isMacOS) {
        await Process.start('open', ['-R', document.filePath]);
      } else {
        final parent = File(document.filePath).parent.path;
        await Process.start('xdg-open', [parent]);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reveal file: $error')));
    }
  }

  Future<void> _confirmDeleteDocument(PdfDocument document) async {
    final impact = await _loadDeleteImpact(document.documentId);

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _DeleteDocumentDialog(document: document, impact: impact),
    );

    if (confirmed != true) return;

    await _deleteDocument(document, impact);
  }

  Future<_DocumentDeleteImpact> _loadDeleteImpact(String documentId) async {
    final notesWithDocumentId = await (widget.database.select(
      widget.database.notes,
    )..where((table) => table.documentId.equals(documentId))).get();

    final anchorsWithDocumentId = await (widget.database.select(
      widget.database.noteAnchors,
    )..where((table) => table.documentId.equals(documentId))).get();

    final noteIds = <String>{
      for (final note in notesWithDocumentId) note.id,
      for (final anchor in anchorsWithDocumentId) anchor.noteId,
    };

    final notes = noteIds.isEmpty
        ? <Note>[]
        : await (widget.database.select(
            widget.database.notes,
          )..where((table) => table.id.isIn(noteIds))).get();

    final blocks = noteIds.isEmpty
        ? <NoteBlock>[]
        : await (widget.database.select(
            widget.database.noteBlocks,
          )..where((table) => table.noteId.isIn(noteIds))).get();

    final anchors = noteIds.isEmpty
        ? <NoteAnchor>[]
        : await (widget.database.select(
            widget.database.noteAnchors,
          )..where((table) => table.noteId.isIn(noteIds))).get();

    return _DocumentDeleteImpact(
      noteIds: noteIds,
      noteCount: notes.length,
      blockCount: blocks.length,
      anchorCount: anchors.length,
      todoCount: notes.where((note) => note.noteType == kTodoNoteType).length,
      highlightCount: notes
          .where((note) => note.noteType == 'highlight')
          .length,
      documentNoteCount: notes
          .where((note) => note.noteType == 'documentNote')
          .length,
      sidecarNoteCount: anchors
          .where((anchor) => anchor.anchorType == 'sidecarPosition')
          .length,
    );
  }

  Future<void> _deleteDocument(
    PdfDocument document,
    _DocumentDeleteImpact impact,
  ) async {
    try {
      await widget.database.transaction(() async {
        if (impact.noteIds.isNotEmpty) {
          await (widget.database.delete(
            widget.database.noteAnchors,
          )..where((table) => table.noteId.isIn(impact.noteIds))).go();
          await (widget.database.delete(
            widget.database.noteBlocks,
          )..where((table) => table.noteId.isIn(impact.noteIds))).go();
          await (widget.database.delete(
            widget.database.notes,
          )..where((table) => table.id.isIn(impact.noteIds))).go();
        }

        await (widget.database.delete(
          widget.database.pdfSessions,
        )..where((table) => table.documentId.equals(document.documentId))).go();
        await (widget.database.delete(
          widget.database.documentTags,
        )..where((table) => table.documentId.equals(document.documentId))).go();
        await (widget.database.delete(
          widget.database.pdfDocuments,
        )..where((table) => table.documentId.equals(document.documentId))).go();
      });

      final cachedFile = File(document.filePath);
      if (await cachedFile.exists()) {
        await cachedFile.delete();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted “${document.name}”.')));
    } catch (error, stackTrace) {
      debugPrint('Delete failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _toggleTodayWorkItem(LibraryTodayWorkItem item, bool done) async {
    setState(() {
      if (done) {
        _todayWorkDoneIds.add(item.id);
      } else {
        _todayWorkDoneIds.remove(item.id);
      }
    });

    if (!done || item.onComplete == null) return;
    try {
      await item.onComplete!();
    } catch (error) {
      if (!mounted) return;
      setState(() => _todayWorkDoneIds.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not complete “${item.title}”: $error')),
      );
    }
  }

  Future<void> _openTodayWorkSource(LibraryTodayWorkItem item) async {
    final opener = item.onOpenSource;
    if (opener == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This item does not have a linked source yet.')),
      );
      return;
    }
    await opener();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chroma = _LibraryChroma.current();
    final baseScheme = theme.colorScheme;
    final libraryTheme = theme.copyWith(
      scaffoldBackgroundColor: chroma.canvas,
      colorScheme: baseScheme.copyWith(
        primary: chroma.accent,
        primaryContainer: chroma.soft,
        secondary: chroma.accent,
        secondaryContainer: chroma.soft,
        surface: chroma.surface,
        surfaceContainerLowest: chroma.canvas,
        surfaceContainerLow: chroma.surface,
        surfaceContainer: chroma.surface,
        outlineVariant: chroma.border,
        outline: chroma.borderStrong,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: chroma.accent),
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: chroma.navSurface,
        foregroundColor: const Color(0xFF25211C),
        iconTheme: IconThemeData(color: chroma.accent),
        actionsIconTheme: IconThemeData(color: chroma.accent),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );

    return Theme(
      data: libraryTheme,
      child: Scaffold(
        backgroundColor: chroma.canvas,
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          TextButton.icon(
            onPressed: _openTextSystemTestEnv,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('textsys test env'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Dev todos',
            onPressed: _planningLoaded ? _openDevTodos : null,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: 'Manage tags',
            onPressed: _openTagManager,
            icon: const Icon(Icons.sell_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Import PDF',
            onPressed: _isImporting ? null : _importPdf,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'Import EPUB',
            onPressed: _isImportingEpub ? null : _importEpub,
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) {
          setState(() {
            _isDragging = true;
          });
        },
        onDragExited: (_) {
          setState(() {
            _isDragging = false;
          });
        },
        onDragDone: (details) async {
          setState(() {
            _isDragging = false;
          });

          debugPrint(
            'Dropped files: ${details.files.map((file) => file.path).toList()}',
          );

          await _importDroppedItems(details.files);
        },
        child: SizedBox.expand(
          child: Stack(
            children: [
              StreamBuilder<List<PdfDocument>>(
                stream: widget.database.watchAllDocuments(),
                builder: (context, documentSnapshot) {
                  return StreamBuilder<List<AppTag>>(
                    stream: _tagRepository.watchTags(),
                    builder: (context, tagSnapshot) {
                      final allTags = tagSnapshot.data ?? const <AppTag>[];

                      return StreamBuilder<Map<String, List<AppTag>>>(
                        stream: _tagRepository.watchDocumentTagMap(),
                        builder: (context, documentTagSnapshot) {
                          final documentTags =
                              documentTagSnapshot.data ??
                              const <String, List<AppTag>>{};
                          final rawDocuments = documentSnapshot.data ?? [];
                          final matchingDocuments = _filterAndSortDocuments(
                            rawDocuments,
                            documentTags,
                          );
                          final documents = _applyLibrarySelection(matchingDocuments);

                          final todayWorkSession = widget.todayWorkSession ?? libraryTodayWorkSessionStore.value;

                          return Column(
                            children: [
                              _LibraryHeader(
                                searchController: _searchController,
                                documentCount: documents.length,
                                totalDocumentCount: rawDocuments.length,
                                sortField: _sortField,
                                sortAscending: _sortAscending,
                                onImportPdf: _isImporting ? null : _importPdf,
                                onSortChanged: _setSort,
                                sortLabel: _sortLabel,
                                allTags: allTags,
                                selectedTagFilterIds: _selectedTagFilterIds,
                                matchAllSelectedTags: _matchAllSelectedTags,
                                onTagFilterToggled: _toggleTagFilter,
                                onClearTagFilters: _clearTagFilters,
                                onMatchModeChanged: (value) {
                                  setState(() {
                                    _matchAllSelectedTags = value;
                                  });
                                },
                                onManageTags: _openTagManager,
                                onOpenToday: _openDailyBrief,
                                onOpenCalendar: _planningLoaded ? _openCalendarOverview : null,
                                onOpenProjects: _planningLoaded ? _openProjectQuickAccess : null,
                                onCreateDocument: _planningLoaded ? _createWorkspaceDocument : null,
                                onOpenDevTodos: _planningLoaded ? _openDevTodos : null,
                                librarySelection: _librarySelection,
                                onLibrarySelectionChanged: (selection) {
                                  setState(() => _librarySelection = selection);
                                },
                                todayWorkSession: todayWorkSession,
                                todayWorkDoneIds: _todayWorkDoneIds,
                                onToggleTodayWorkItem: _toggleTodayWorkItem,
                                onOpenTodayWorkSource: _openTodayWorkSource,
                              ),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (_planningLoaded)
                                      SizedBox(
                                        width: 292,
                                        child: _LibraryOrganizationRail(
                                          projects: _planningRepository.projects,
                                          folders: _planningRepository.libraryFolders,
                                          documents: rawDocuments,
                                          selected: _librarySelection,
                                          countForSelection: (selection) => _countDocumentsForSelection(rawDocuments, selection),
                                          onSelected: (selection) => setState(() => _librarySelection = selection),
                                          onCreateFolder: _createLibraryFolder,
                                        ),
                                      ),
                                    if (_planningLoaded) const VerticalDivider(width: 1),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          if (_planningLoaded)
                                            _WorkspaceDocumentsStrip(
                                              documents: _planningRepository.documents,
                                              onOpenDocument: _openWorkspaceDocument,
                                              onCreateDocument: _createWorkspaceDocument,
                                            ),
                                          if (_epubLibraryLoaded && _epubDocuments.isNotEmpty)
                                            _EpubDocumentsStrip(
                                              documents: _epubDocuments,
                                              onOpenDocument: _openEpubDocument,
                                              onDeleteDocument: _confirmDeleteEpubDocument,
                                            ),
                                          const Divider(height: 1),
                                          Expanded(
                                            child: documentSnapshot.connectionState == ConnectionState.waiting
                                                ? const Center(child: CircularProgressIndicator())
                                                : documents.isEmpty
                                                    ? _EmptyLibraryState(
                                                        isSearching: _searchQuery.isNotEmpty || _selectedTagFilterIds.isNotEmpty,
                                                        onImportPdf: _isImporting ? null : _importPdf,
                                                      )
                                                    : Column(
                                                        children: [
                                                          const _LibraryTableHeader(),
                                                          Expanded(
                                                            child: ListView.builder(
                                                              padding: const EdgeInsets.only(bottom: 24),
                                                              itemCount: documents.length,
                                                              itemBuilder: (context, index) {
                                                                final document = documents[index];
                                                                final tags = documentTags[document.documentId] ?? const <AppTag>[];

                                                                return _PdfDocumentCard(
                                                                  document: document,
                                                                  tags: tags,
                                                                  formatDateTime: _formatDateTime,
                                                                  formatShortDate: _formatShortDate,
                                                                  metadataQualityLabel: _metadataQualityLabel,
                                                                  metadataQualityColor: (document) => _metadataQualityColor(context, document),
                                                                  loadImpact: _loadDeleteImpact,
                                                                  assignedProject: _planningRepository.projectForPdf(document.documentId),
                                                                  assignedFolder: _planningRepository.folderForPdf(document.documentId),
                                                                  onOpen: () => _openDocument(document),
                                                                  onEditMetadata: () => _openMetadataEditor(document),
                                                                  onEditTags: () => _openDocumentTagPicker(document, tags),
                                                                  onAssignProject: () => _openDocumentProjectPicker(document),
                                                                  onMoveFolder: () => _openDocumentFolderPicker(document),
                                                                  onRefreshLocalMetadata: () => _refreshLocalMetadata(document),
                                                                  onOnlineMetadataLookup: () => _showOnlineMetadataInfo(document),
                                                                  onRevealFile: () => _revealFile(document),
                                                                  onDelete: () => _confirmDeleteDocument(document),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
              if (_isDragging)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.library_books_outlined, size: 64),
                              SizedBox(height: 16),
                              Text(
                                'Drop PDFs or EPUBs to import',
                                style: TextStyle(fontSize: 22),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_isImporting)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    ));
  }
}


enum _LibraryCollectionKind {
  all,
  uncategorized,
  uncategorizedUnfiled,
  project,
  projectUnfiled,
  folder,
}

class _LibraryCollectionSelection {
  final _LibraryCollectionKind kind;
  final String? projectId;
  final String? folderId;

  const _LibraryCollectionSelection._(this.kind, {this.projectId, this.folderId});

  const _LibraryCollectionSelection.all() : this._(_LibraryCollectionKind.all);
  const _LibraryCollectionSelection.uncategorized() : this._(_LibraryCollectionKind.uncategorized);
  const _LibraryCollectionSelection.uncategorizedUnfiled()
      : this._(_LibraryCollectionKind.uncategorizedUnfiled);
  const _LibraryCollectionSelection.project(String projectId)
      : this._(_LibraryCollectionKind.project, projectId: projectId);
  const _LibraryCollectionSelection.projectUnfiled(String projectId)
      : this._(_LibraryCollectionKind.projectUnfiled, projectId: projectId);
  const _LibraryCollectionSelection.folder(String folderId)
      : this._(_LibraryCollectionKind.folder, folderId: folderId);

  @override
  bool operator ==(Object other) {
    return other is _LibraryCollectionSelection &&
        other.kind == kind &&
        other.projectId == projectId &&
        other.folderId == folderId;
  }

  @override
  int get hashCode => Object.hash(kind, projectId, folderId);
}

class _LibraryOrganizationRail extends StatelessWidget {
  final List<StudyProject> projects;
  final List<LibraryFolder> folders;
  final List<PdfDocument> documents;
  final _LibraryCollectionSelection selected;
  final int Function(_LibraryCollectionSelection selection) countForSelection;
  final ValueChanged<_LibraryCollectionSelection> onSelected;
  final Future<void> Function({String? projectId, String? parentId}) onCreateFolder;

  const _LibraryOrganizationRail({
    required this.projects,
    required this.folders,
    required this.documents,
    required this.selected,
    required this.countForSelection,
    required this.onSelected,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topLevelUncategorizedFolders = _foldersFor(projectId: null, parentId: null);

    return Container(
      color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.55),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Organization',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'New uncategorized folder',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: () => onCreateFolder(),
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LibraryRailTile(
            icon: Icons.library_books_outlined,
            title: 'All documents',
            count: countForSelection(const _LibraryCollectionSelection.all()),
            selected: selected == const _LibraryCollectionSelection.all(),
            onTap: () => onSelected(const _LibraryCollectionSelection.all()),
          ),
          const SizedBox(height: 12),
          _LibraryRailSectionHeader(
            title: 'Uncategorized',
            count: countForSelection(const _LibraryCollectionSelection.uncategorized()),
            onAdd: () => onCreateFolder(),
          ),
          _LibraryRailTile(
            icon: Icons.inbox_outlined,
            title: 'Unfiled',
            count: countForSelection(const _LibraryCollectionSelection.uncategorizedUnfiled()),
            selected: selected == const _LibraryCollectionSelection.uncategorizedUnfiled(),
            onTap: () => onSelected(const _LibraryCollectionSelection.uncategorizedUnfiled()),
            indent: 8,
          ),
          for (final folder in topLevelUncategorizedFolders)
            _LibraryFolderTreeTile(
              folder: folder,
              folders: folders,
              countForSelection: countForSelection,
              selected: selected,
              onSelected: onSelected,
              onCreateFolder: onCreateFolder,
              depth: 1,
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Projects',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(
                'Assign PDFs to projects to group source material by work stream.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          for (final project in projects) _ProjectLibraryGroup(
            project: project,
            folders: _foldersFor(projectId: project.id, parentId: null),
            allFolders: folders,
            selected: selected,
            countForSelection: countForSelection,
            onSelected: onSelected,
            onCreateFolder: onCreateFolder,
          ),
        ],
      ),
    );
  }

  List<LibraryFolder> _foldersFor({String? projectId, String? parentId}) {
    final result = folders.where((folder) {
      final projectMatches = projectId == null
          ? folder.projectId == null || folder.projectId!.isEmpty
          : folder.projectId == projectId;
      final parentMatches = parentId == null
          ? folder.parentId == null || folder.parentId!.isEmpty
          : folder.parentId == parentId;
      return projectMatches && parentMatches;
    }).toList();
    result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return result;
  }
}

class _ProjectLibraryGroup extends StatelessWidget {
  final StudyProject project;
  final List<LibraryFolder> folders;
  final List<LibraryFolder> allFolders;
  final _LibraryCollectionSelection selected;
  final int Function(_LibraryCollectionSelection selection) countForSelection;
  final ValueChanged<_LibraryCollectionSelection> onSelected;
  final Future<void> Function({String? projectId, String? parentId}) onCreateFolder;

  const _ProjectLibraryGroup({
    required this.project,
    required this.folders,
    required this.allFolders,
    required this.selected,
    required this.countForSelection,
    required this.onSelected,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryRailSectionHeader(
            title: project.title,
            count: countForSelection(_LibraryCollectionSelection.project(project.id)),
            onAdd: () => onCreateFolder(projectId: project.id),
          ),
          _LibraryRailTile(
            icon: Icons.inbox_outlined,
            title: 'Unfiled',
            count: countForSelection(_LibraryCollectionSelection.projectUnfiled(project.id)),
            selected: selected == _LibraryCollectionSelection.projectUnfiled(project.id),
            onTap: () => onSelected(_LibraryCollectionSelection.projectUnfiled(project.id)),
            indent: 8,
          ),
          for (final folder in folders)
            _LibraryFolderTreeTile(
              folder: folder,
              folders: allFolders,
              countForSelection: countForSelection,
              selected: selected,
              onSelected: onSelected,
              onCreateFolder: onCreateFolder,
              depth: 1,
            ),
        ],
      ),
    );
  }
}

class _LibraryFolderTreeTile extends StatelessWidget {
  final LibraryFolder folder;
  final List<LibraryFolder> folders;
  final int Function(_LibraryCollectionSelection selection) countForSelection;
  final _LibraryCollectionSelection selected;
  final ValueChanged<_LibraryCollectionSelection> onSelected;
  final Future<void> Function({String? projectId, String? parentId}) onCreateFolder;
  final int depth;

  const _LibraryFolderTreeTile({
    required this.folder,
    required this.folders,
    required this.countForSelection,
    required this.selected,
    required this.onSelected,
    required this.onCreateFolder,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final children = folders.where((candidate) => candidate.parentId == folder.id).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final selection = _LibraryCollectionSelection.folder(folder.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LibraryRailTile(
          icon: Icons.folder_outlined,
          title: folder.title,
          count: countForSelection(selection),
          selected: selected == selection,
          onTap: () => onSelected(selection),
          onAdd: () => onCreateFolder(projectId: folder.projectId, parentId: folder.id),
          indent: 8.0 + (depth * 12),
        ),
        for (final child in children)
          _LibraryFolderTreeTile(
            folder: child,
            folders: folders,
            countForSelection: countForSelection,
            selected: selected,
            onSelected: onSelected,
            onCreateFolder: onCreateFolder,
            depth: depth + 1,
          ),
      ],
    );
  }
}

class _LibraryRailSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback? onAdd;

  const _LibraryRailSectionHeader({required this.title, required this.count, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 2, 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (onAdd != null)
            IconButton(
              tooltip: 'New folder',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
    );
  }
}

class _LibraryRailTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onAdd;
  final double indent;

  const _LibraryRailTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onAdd,
    this.indent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: indent, top: 3, bottom: 3),
      child: Material(
        color: selected ? colorScheme.primaryContainer.withValues(alpha: .42) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                if (onAdd != null) ...[
                  const SizedBox(width: 2),
                  InkResponse(
                    radius: 16,
                    onTap: onAdd,
                    child: Icon(Icons.add, size: 15, color: colorScheme.primary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateLibraryFolderDialog extends StatefulWidget {
  final String scopeLabel;

  const _CreateLibraryFolderDialog({required this.scopeLabel});

  @override
  State<_CreateLibraryFolderDialog> createState() => _CreateLibraryFolderDialogState();
}

class _CreateLibraryFolderDialogState extends State<_CreateLibraryFolderDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create folder'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inside ${widget.scopeLabel}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Folder name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create folder')),
      ],
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }
}


class _WorkspaceDocumentsStrip extends StatelessWidget {
  final List<WorkspaceDocument> documents;
  final ValueChanged<WorkspaceDocument> onOpenDocument;
  final VoidCallback onCreateDocument;

  const _WorkspaceDocumentsStrip({
    required this.documents,
    required this.onOpenDocument,
    required this.onCreateDocument,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleDocuments = documents.take(8).toList();
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLowest,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Documents', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Text(
                'text, sources, templates, links',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onCreateDocument,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (documents.isEmpty)
            Material(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onCreateDocument,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.note_add_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Create the first generic document. Use it for pasted job ads, letters, CV versions, source text, notes, or templates.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visibleDocuments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final document = visibleDocuments[index];
                  return SizedBox(
                    width: 260,
                    child: Card(
                      elevation: 0,
                      color: theme.colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => onOpenDocument(document),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(_iconForWorkspaceDocument(document), color: theme.colorScheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      document.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      WorkspaceDocumentKind.label(document.kind),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                    if (document.tags.isNotEmpty)
                                      Text(
                                        document.tags.take(3).join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

IconData _iconForWorkspaceDocument(WorkspaceDocument document) {
  switch (WorkspaceDocumentKind.normalize(document.kind)) {
    case WorkspaceDocumentKind.source:
      return Icons.article_outlined;
    case WorkspaceDocumentKind.template:
      return Icons.dashboard_customize_outlined;
    case WorkspaceDocumentKind.link:
      return Icons.link_rounded;
    case WorkspaceDocumentKind.collection:
      return Icons.folder_outlined;
    case WorkspaceDocumentKind.working:
    default:
      return Icons.edit_document;
  }
}


class _LibraryTodayWorkStrip extends StatelessWidget {
  const _LibraryTodayWorkStrip({
    required this.session,
    required this.doneIds,
    required this.onToggleDone,
    required this.onOpenSource,
    this.compact = false,
  });

  final LibraryTodayWorkSession session;
  final Set<String> doneIds;
  final Future<void> Function(LibraryTodayWorkItem item, bool done) onToggleDone;
  final Future<void> Function(LibraryTodayWorkItem item) onOpenSource;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final doneCount = session.items.where((item) => doneIds.contains(item.id)).length;
    final remaining = session.items.length - doneCount;

    return Container(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(24, 8, 24, 14),
      padding: compact ? const EdgeInsets.fromLTRB(12, 10, 12, 12) : const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(colorScheme.primary.withValues(alpha: .045), colorScheme.surface),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: .82)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withValues(alpha: .10),
                ),
                child: Icon(Icons.playlist_add_check_rounded, size: 19, color: colorScheme.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      remaining == 0
                          ? 'All selected work is checked off.'
                          : '$remaining item${remaining == 1 ? '' : 's'} left from setup',
                      style: TextStyle(
                        fontSize: 12.1,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatLibraryTodayWorkDate(session.date),
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: session.items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: .75)),
              itemBuilder: (context, index) {
                final item = session.items[index];
                return _LibraryTodayWorkRow(
                  item: item,
                  done: doneIds.contains(item.id),
                  onChanged: (done) => onToggleDone(item, done),
                  onOpenSource: item.onOpenSource == null ? null : () => onOpenSource(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryTodayWorkRow extends StatelessWidget {
  const _LibraryTodayWorkRow({
    required this.item,
    required this.done,
    required this.onChanged,
    this.onOpenSource,
  });

  final LibraryTodayWorkItem item;
  final bool done;
  final ValueChanged<bool> onChanged;
  final Future<void> Function()? onOpenSource;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: done,
            activeColor: colorScheme.primary,
            onChanged: (value) => onChanged(value ?? false),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.18,
                    fontWeight: FontWeight.w900,
                    color: done ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.9,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onOpenSource != null) ...[
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: () => unawaited(onOpenSource!()),
              icon: Icon(item.sourceIcon ?? Icons.description_outlined, size: 15),
              label: const Text('Open'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _LibraryTodayWorkHeaderButton extends StatelessWidget {
  const _LibraryTodayWorkHeaderButton({
    required this.session,
    required this.doneIds,
    required this.onToggleDone,
    required this.onOpenSource,
  });

  final LibraryTodayWorkSession session;
  final Set<String> doneIds;
  final Future<void> Function(LibraryTodayWorkItem item, bool done)? onToggleDone;
  final Future<void> Function(LibraryTodayWorkItem item)? onOpenSource;

  int get _remaining => session.items.where((item) => !doneIds.contains(item.id)).length;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remaining = _remaining;
    return FilledButton.tonalIcon(
      onPressed: () => _openTodayWorkSheet(context),
      icon: Icon(
        remaining == 0 ? Icons.task_alt_rounded : Icons.playlist_add_check_rounded,
        size: 18,
      ),
      label: Text(remaining == 0 ? 'Today done' : '$remaining left today'),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: remaining == 0
            ? colorScheme.secondaryContainer.withValues(alpha: .62)
            : colorScheme.primaryContainer.withValues(alpha: .72),
        foregroundColor: remaining == 0
            ? colorScheme.onSecondaryContainer
            : colorScheme.onPrimaryContainer,
        textStyle: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w900),
      ),
    );
  }

  void _openTodayWorkSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
                child: _LibraryTodayWorkStrip(
                  session: session,
                  doneIds: doneIds,
                  compact: false,
                  onToggleDone: (item, done) async {
                    await onToggleDone?.call(item, done);
                    setSheetState(() {});
                  },
                  onOpenSource: (item) async {
                    final opener = onOpenSource;
                    if (opener != null) {
                      await opener(item);
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _formatLibraryTodayWorkDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[date.month - 1];
  return '${date.day} $month';
}

class _LibraryHeader extends StatelessWidget {
  final TextEditingController searchController;
  final int documentCount;
  final int totalDocumentCount;
  final LibrarySortField sortField;
  final bool sortAscending;
  final VoidCallback? onImportPdf;
  final ValueChanged<LibrarySortField> onSortChanged;
  final String Function(LibrarySortField field) sortLabel;
  final List<AppTag> allTags;
  final Set<int> selectedTagFilterIds;
  final bool matchAllSelectedTags;
  final ValueChanged<int> onTagFilterToggled;
  final VoidCallback onClearTagFilters;
  final ValueChanged<bool> onMatchModeChanged;
  final VoidCallback onManageTags;
  final VoidCallback onOpenToday;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenProjects;
  final VoidCallback? onCreateDocument;
  final VoidCallback? onOpenDevTodos;
  final _LibraryCollectionSelection librarySelection;
  final ValueChanged<_LibraryCollectionSelection> onLibrarySelectionChanged;
  final LibraryTodayWorkSession? todayWorkSession;
  final Set<String> todayWorkDoneIds;
  final Future<void> Function(LibraryTodayWorkItem item, bool done)? onToggleTodayWorkItem;
  final Future<void> Function(LibraryTodayWorkItem item)? onOpenTodayWorkSource;

  const _LibraryHeader({
    required this.searchController,
    required this.documentCount,
    required this.totalDocumentCount,
    required this.sortField,
    required this.sortAscending,
    required this.onImportPdf,
    required this.onSortChanged,
    required this.sortLabel,
    required this.allTags,
    required this.selectedTagFilterIds,
    required this.matchAllSelectedTags,
    required this.onTagFilterToggled,
    required this.onClearTagFilters,
    required this.onMatchModeChanged,
    required this.onManageTags,
    required this.onOpenToday,
    required this.onOpenCalendar,
    required this.onOpenProjects,
    required this.onCreateDocument,
    required this.onOpenDevTodos,
    required this.librarySelection,
    required this.onLibrarySelectionChanged,
    required this.todayWorkSession,
    required this.todayWorkDoneIds,
    required this.onToggleTodayWorkItem,
    required this.onOpenTodayWorkSource,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleTags = allTags.take(12).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your library',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      documentCount == totalDocumentCount
                          ? '$documentCount PDF${documentCount == 1 ? '' : 's'} in library'
                          : '$documentCount of $totalDocumentCount documents shown in this collection',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (todayWorkSession != null) ...[
                _LibraryTodayWorkHeaderButton(
                  session: todayWorkSession!,
                  doneIds: todayWorkDoneIds,
                  onToggleDone: onToggleTodayWorkItem,
                  onOpenSource: onOpenTodayWorkSource,
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: onOpenToday,
                icon: const Icon(Icons.today_rounded),
                label: const Text('Today'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onOpenCalendar,
                icon: const Icon(Icons.calendar_month_rounded),
                label: const Text('Calendar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onOpenProjects,
                icon: const Icon(Icons.dashboard_customize_rounded),
                label: const Text('Projects'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onOpenDevTodos,
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Dev'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onManageTags,
                icon: const Icon(Icons.sell_outlined),
                label: const Text('Manage tags'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onCreateDocument,
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('New document'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onImportPdf,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import PDF'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText:
                        'Search title, author, DOI, journal, keyword, tag...',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: searchController.clear,
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<LibrarySortField>(
                tooltip: 'Sort library',
                initialValue: sortField,
                onSelected: onSortChanged,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: LibrarySortField.addedAt,
                    child: Text('Sort by added date'),
                  ),
                  PopupMenuItem(
                    value: LibrarySortField.name,
                    child: Text('Sort by title'),
                  ),
                  PopupMenuItem(
                    value: LibrarySortField.authors,
                    child: Text('Sort by authors'),
                  ),
                  PopupMenuItem(
                    value: LibrarySortField.fileLastModifiedAt,
                    child: Text('Sort by file modified date'),
                  ),
                  PopupMenuItem(
                    value: LibrarySortField.subject,
                    child: Text('Sort by subject'),
                  ),
                ],
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: Icon(
                    sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 18,
                  ),
                  label: Text(sortLabel(sortField)),
                ),
              ),
            ],
          ),
          if (allTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Tags',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final tag in visibleTags)
                          _LibraryTagFilterChip(
                            tag: tag,
                            selected: selectedTagFilterIds.contains(tag.id),
                            onSelected: (_) => onTagFilterToggled(tag.id),
                          ),
                        if (allTags.length > visibleTags.length)
                          ActionChip(
                            avatar: const Icon(Icons.more_horiz, size: 16),
                            label: Text(
                              '+${allTags.length - visibleTags.length}',
                            ),
                            onPressed: onManageTags,
                          ),
                      ],
                    ),
                  ),
                ),
                if (selectedTagFilterIds.length > 1) ...[
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('Any')),
                      ButtonSegment<bool>(value: true, label: Text('All')),
                    ],
                    selected: {matchAllSelectedTags},
                    onSelectionChanged: (selection) {
                      onMatchModeChanged(selection.first);
                    },
                  ),
                ],
                if (selectedTagFilterIds.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onClearTagFilters,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}


class _EpubDocumentsStrip extends StatelessWidget {
  final List<EpubLibraryDocument> documents;
  final ValueChanged<EpubLibraryDocument> onOpenDocument;
  final ValueChanged<EpubLibraryDocument> onDeleteDocument;

  const _EpubDocumentsStrip({
    required this.documents,
    required this.onOpenDocument,
    required this.onDeleteDocument,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.16),
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded, color: colorScheme.secondary),
              const SizedBox(width: 8),
              Text(
                'EPUB library',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${documents.length} imported',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: documents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final document = documents[index];
                return _EpubDocumentCard(
                  document: document,
                  onOpen: () => onOpenDocument(document),
                  onDelete: () => onDeleteDocument(document),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EpubDocumentCard extends StatelessWidget {
  final EpubLibraryDocument document;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _EpubDocumentCard({
    required this.document,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 340,
      child: Card(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.secondaryContainer,
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: colorScheme.onSecondaryContainer,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        document.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete EPUB',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  document.metadataSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  document.structureSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Reader surface coming next',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: onOpen,
                      child: const Text('Open'),
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

class _LibraryTableHeader extends StatelessWidget {
  const _LibraryTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget label(String value) {
      return Text(
        value,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      );
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 6, child: label('PDF')),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: label('METADATA')),
          const SizedBox(width: 16),
          SizedBox(width: 108, child: label('ADDED')),
          const SizedBox(width: 16),
          SizedBox(width: 116, child: label('WORK')),
          const SizedBox(width: 16),
          SizedBox(width: 104, child: label('STATUS')),
          const SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _PdfDocumentCard extends StatelessWidget {
  final PdfDocument document;
  final List<AppTag> tags;
  final String Function(DateTime? value) formatDateTime;
  final String Function(DateTime? value) formatShortDate;
  final String Function(PdfDocument document) metadataQualityLabel;
  final Color Function(PdfDocument document) metadataQualityColor;
  final Future<_DocumentDeleteImpact> Function(String documentId) loadImpact;
  final StudyProject? assignedProject;
  final LibraryFolder? assignedFolder;
  final VoidCallback onOpen;
  final VoidCallback onEditMetadata;
  final VoidCallback onEditTags;
  final VoidCallback onAssignProject;
  final VoidCallback onMoveFolder;
  final VoidCallback onRefreshLocalMetadata;
  final VoidCallback onOnlineMetadataLookup;
  final VoidCallback onRevealFile;
  final VoidCallback onDelete;

  const _PdfDocumentCard({
    required this.document,
    required this.tags,
    required this.formatDateTime,
    required this.formatShortDate,
    required this.metadataQualityLabel,
    required this.metadataQualityColor,
    required this.loadImpact,
    required this.assignedProject,
    required this.assignedFolder,
    required this.onOpen,
    required this.onEditMetadata,
    required this.onEditTags,
    required this.onAssignProject,
    required this.onMoveFolder,
    required this.onRefreshLocalMetadata,
    required this.onOnlineMetadataLookup,
    required this.onRevealFile,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadataColor = metadataQualityColor(document);

    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 6, child: _buildPrimaryColumn(context)),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: _buildMetadataColumn(context)),
              const SizedBox(width: 16),
              SizedBox(
                width: 108,
                child: Text(
                  formatShortDate(document.addedAt),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 116,
                child: FutureBuilder<_DocumentDeleteImpact>(
                  future: loadImpact(document.documentId),
                  builder: (context, snapshot) {
                    final impact = snapshot.data;
                    if (impact == null || impact.noteCount == 0) {
                      return Text(
                        'No notes',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }

                    return Text(
                      impact.compactLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 104,
                child: _MetadataChip(
                  label: metadataQualityLabel(document),
                  color: metadataColor,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Open PDF',
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new, size: 19),
                    ),
                    _DocumentActionsMenu(
                      onEditMetadata: onEditMetadata,
                      onEditTags: onEditTags,
                      onAssignProject: onAssignProject,
                      onMoveFolder: onMoveFolder,
                      onRefreshLocalMetadata: onRefreshLocalMetadata,
                      onOnlineMetadataLookup: onOnlineMetadataLookup,
                      onRevealFile: onRevealFile,
                      onDelete: onDelete,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryColumn(BuildContext context) {
    final theme = Theme.of(context);
    final filename = document.originalFileName.trim();
    final title = document.name.trim().isEmpty
        ? filename
        : document.name.trim();

    return Row(
      children: [
        Icon(Icons.picture_as_pdf, size: 24, color: theme.colorScheme.error),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 5),
                _DocumentTagSummary(tags: tags),
              ],
              if (assignedProject != null || assignedFolder != null) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (assignedProject != null) _AssignedProjectChip(project: assignedProject!),
                    if (assignedFolder != null) _AssignedFolderChip(folder: assignedFolder!),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataColumn(BuildContext context) {
    final theme = Theme.of(context);
    final primary = _metadataPrimary;
    final secondary = _metadataSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 3),
        Text(
          secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String get _metadataPrimary {
    final authors = document.authors?.trim();
    if (authors != null && authors.isNotEmpty) {
      return authors;
    }

    final publisher = document.publisher?.trim();
    if (publisher != null && publisher.isNotEmpty) {
      return publisher;
    }

    final journal = document.journal?.trim();
    if (journal != null && journal.isNotEmpty) {
      return journal;
    }

    return 'No author metadata';
  }

  String get _metadataSecondary {
    final pieces = <String>[];

    final journal = document.journal?.trim();
    if (journal != null && journal.isNotEmpty) {
      pieces.add(journal);
    }

    final doi = document.doi?.trim();
    if (doi != null && doi.isNotEmpty) {
      pieces.add('DOI');
    }

    final arxivId = document.arxivId?.trim();
    if (arxivId != null && arxivId.isNotEmpty) {
      pieces.add('arXiv');
    }

    final field = document.fieldOfStudy?.trim();
    if (field != null && field.isNotEmpty) {
      pieces.add(field);
    }

    if (pieces.isEmpty) {
      final subject = document.subject?.trim();
      if (subject != null && subject.isNotEmpty) {
        pieces.add(subject);
      }
    }

    return pieces.isEmpty ? 'Metadata missing' : pieces.join(' · ');
  }
}

class _DocumentActionsMenu extends StatelessWidget {
  final VoidCallback onEditMetadata;
  final VoidCallback onEditTags;
  final VoidCallback onAssignProject;
  final VoidCallback onMoveFolder;
  final VoidCallback onRefreshLocalMetadata;
  final VoidCallback onOnlineMetadataLookup;
  final VoidCallback onRevealFile;
  final VoidCallback onDelete;

  const _DocumentActionsMenu({
    required this.onEditMetadata,
    required this.onEditTags,
    required this.onAssignProject,
    required this.onMoveFolder,
    required this.onRefreshLocalMetadata,
    required this.onOnlineMetadataLookup,
    required this.onRevealFile,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DocumentAction>(
      tooltip: 'Document actions',
      onSelected: (action) {
        switch (action) {
          case _DocumentAction.editMetadata:
            onEditMetadata();
            return;
          case _DocumentAction.editTags:
            onEditTags();
            return;
          case _DocumentAction.assignProject:
            onAssignProject();
            return;
          case _DocumentAction.moveFolder:
            onMoveFolder();
            return;
          case _DocumentAction.refreshLocalMetadata:
            onRefreshLocalMetadata();
            return;
          case _DocumentAction.onlineMetadataLookup:
            onOnlineMetadataLookup();
            return;
          case _DocumentAction.revealFile:
            onRevealFile();
            return;
          case _DocumentAction.delete:
            onDelete();
            return;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _DocumentAction.editMetadata,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit metadata'),
          ),
        ),
        PopupMenuItem(
          value: _DocumentAction.editTags,
          child: ListTile(
            leading: Icon(Icons.sell_outlined),
            title: Text('Edit tags'),
          ),
        ),
        PopupMenuItem(
          value: _DocumentAction.assignProject,
          child: ListTile(
            leading: Icon(Icons.dashboard_customize_outlined),
            title: Text('Assign project'),
          ),
        ),
        PopupMenuItem(
          value: _DocumentAction.moveFolder,
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outlined),
            title: Text('Move to folder'),
          ),
        ),
        PopupMenuItem(
          value: _DocumentAction.refreshLocalMetadata,
          child: ListTile(
            leading: Icon(Icons.manage_search_outlined),
            title: Text('Extract local metadata'),
          ),
        ),
        PopupMenuItem(
          value: _DocumentAction.onlineMetadataLookup,
          child: ListTile(
            leading: Icon(Icons.cloud_sync_outlined),
            title: Text('Search online metadata'),
          ),
        ),
        PopupMenuItem(
          value: _DocumentAction.revealFile,
          child: ListTile(
            leading: Icon(Icons.folder_open_outlined),
            title: Text('Reveal cached PDF'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _DocumentAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_forever_outlined),
            title: Text('Delete PDF...'),
          ),
        ),
      ],
      child: const Icon(Icons.more_horiz),
    );
  }
}

enum _DocumentAction {
  editMetadata,
  editTags,
  assignProject,
  moveFolder,
  refreshLocalMetadata,
  onlineMetadataLookup,
  revealFile,
  delete,
}

class _MetadataChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetadataChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.55)),
      avatar: CircleAvatar(radius: 5, backgroundColor: color),
    );
  }
}

class _AssignedProjectChip extends StatelessWidget {
  final StudyProject project;

  const _AssignedProjectChip({required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.dashboard_customize_rounded, size: 15),
        label: Text(
          project.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.32)),
        backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.38),
      ),
    );
  }
}


class _AssignedFolderChip extends StatelessWidget {
  final LibraryFolder folder;

  const _AssignedFolderChip({required this.folder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.folder_rounded, size: 15),
      label: Text(
        folder.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      side: BorderSide(color: theme.colorScheme.tertiary.withValues(alpha: 0.28)),
      backgroundColor: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.34),
    );
  }
}

class _PdfProjectAssignmentDialog extends StatefulWidget {
  final String documentTitle;
  final List<StudyProject> projects;
  final String? currentProjectId;

  const _PdfProjectAssignmentDialog({
    required this.documentTitle,
    required this.projects,
    required this.currentProjectId,
  });

  @override
  State<_PdfProjectAssignmentDialog> createState() => _PdfProjectAssignmentDialogState();
}

class _PdfProjectAssignmentDialogState extends State<_PdfProjectAssignmentDialog> {
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.currentProjectId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Assign PDF to project'),
      content: SizedBox(
        width: 520,
        child: widget.projects.isEmpty
            ? Text(
                'Create a project first, then assign “${widget.documentTitle}” to it from the library.',
                style: theme.textTheme.bodyMedium,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.documentTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedProjectId != null &&
                            widget.projects.any((project) => project.id == _selectedProjectId)
                        ? _selectedProjectId
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('No project'),
                      ),
                      for (final project in widget.projects)
                        DropdownMenuItem<String>(
                          value: project.id,
                          child: Text(project.title),
                        ),
                    ],
                    onChanged: (value) => setState(() => _selectedProjectId = value),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: widget.projects.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selectedProjectId ?? ''),
          child: const Text('Save assignment'),
        ),
      ],
    );
  }
}


class _PdfFolderAssignmentDialog extends StatefulWidget {
  final String documentTitle;
  final List<StudyProject> projects;
  final List<LibraryFolder> folders;
  final String? currentFolderId;

  const _PdfFolderAssignmentDialog({
    required this.documentTitle,
    required this.projects,
    required this.folders,
    required this.currentFolderId,
  });

  @override
  State<_PdfFolderAssignmentDialog> createState() => _PdfFolderAssignmentDialogState();
}

class _PdfFolderAssignmentDialogState extends State<_PdfFolderAssignmentDialog> {
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.currentFolderId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedFolders = [...widget.folders]
      ..sort((a, b) => _folderSortLabel(a).compareTo(_folderSortLabel(b)));

    return AlertDialog(
      title: const Text('Move PDF to folder'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.documentTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedFolderId != null && sortedFolders.any((folder) => folder.id == _selectedFolderId)
                  ? _selectedFolderId
                  : '',
              decoration: const InputDecoration(
                labelText: 'Folder',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(value: '', child: Text('No folder')),
                for (final folder in sortedFolders)
                  DropdownMenuItem<String>(
                    value: folder.id,
                    child: Text(_folderLabel(folder)),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedFolderId = value),
            ),
            if (sortedFolders.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Create folders from the organization panel first. Then you can move PDFs into them.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_selectedFolderId ?? ''), child: const Text('Save folder')),
      ],
    );
  }

  String _folderLabel(LibraryFolder folder) {
    final scope = _folderScope(folder);
    return scope == null ? folder.title : '$scope / ${folder.title}';
  }

  String _folderSortLabel(LibraryFolder folder) => _folderLabel(folder).toLowerCase();

  String? _folderScope(LibraryFolder folder) {
    if (folder.projectId == null || folder.projectId!.isEmpty) return 'Uncategorized';
    for (final project in widget.projects) {
      if (project.id == folder.projectId) return project.title;
    }
    return 'Project';
  }
}

class _DocumentTagSummary extends StatelessWidget {
  final List<AppTag> tags;

  const _DocumentTagSummary({required this.tags});

  @override
  Widget build(BuildContext context) {
    final visibleTags = tags.take(3).toList();
    final hiddenCount = tags.length - visibleTags.length;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final tag in visibleTags) _SmallTagChip(tag: tag),
        if (hiddenCount > 0)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('+$hiddenCount'),
          ),
      ],
    );
  }
}

class _LibraryTagFilterChip extends StatelessWidget {
  final AppTag tag;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _LibraryTagFilterChip({
    required this.tag,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.colorValue);

    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      avatar: Icon(iconForTagKey(tag.iconKey), size: 16, color: color),
      label: Text(tag.name),
      selectedColor: color.withValues(alpha: 0.18),
      checkmarkColor: color,
      side: BorderSide(color: color.withValues(alpha: selected ? 0.65 : 0.35)),
    );
  }
}

class _SmallTagChip extends StatelessWidget {
  final AppTag tag;
  final VoidCallback? onDeleted;

  const _SmallTagChip({required this.tag, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.colorValue);

    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(iconForTagKey(tag.iconKey), size: 14, color: color),
      label: Text(tag.name),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      backgroundColor: color.withValues(alpha: 0.08),
      deleteIcon: onDeleted == null ? null : const Icon(Icons.close, size: 15),
      onDeleted: onDeleted,
    );
  }
}

class DocumentTagPickerDialog extends StatefulWidget {
  final TagRepository tagRepository;
  final PdfDocument document;
  final List<AppTag> initiallyAssignedTags;

  const DocumentTagPickerDialog({
    super.key,
    required this.tagRepository,
    required this.document,
    required this.initiallyAssignedTags,
  });

  @override
  State<DocumentTagPickerDialog> createState() =>
      _DocumentTagPickerDialogState();
}

class _DocumentTagPickerDialogState extends State<DocumentTagPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<int> _assignedTagIds;

  String _query = '';
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();

    _assignedTagIds = {for (final tag in widget.initiallyAssignedTags) tag.id};

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

  @override
  Widget build(BuildContext context) {
    final title = widget.document.name.trim().isEmpty
        ? widget.document.originalFileName
        : widget.document.name;

    return AlertDialog(
      title: const Text('Edit PDF tags'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search or create a tag...',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<AppTag>>(
              stream: widget.tagRepository.watchTags(),
              builder: (context, snapshot) {
                final tags = snapshot.data ?? const <AppTag>[];
                final visibleTags = _filterTags(tags);
                final exactMatch = tags.any(
                  (tag) => tag.name.toLowerCase() == _query,
                );

                return Expanded(
                  child: Column(
                    children: [
                      if (_query.isNotEmpty && !exactMatch)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _isMutating
                                ? null
                                : () => _createAndAssignTag(_query),
                            icon: const Icon(Icons.add),
                            label: Text(
                              'Create “${_searchController.text.trim()}”',
                            ),
                          ),
                        ),
                      if (_query.isNotEmpty && !exactMatch)
                        const SizedBox(height: 8),
                      Expanded(
                        child: visibleTags.isEmpty
                            ? const Center(child: Text('No matching tags.'))
                            : ListView.separated(
                                itemCount: visibleTags.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final tag = visibleTags[index];
                                  final selected = _assignedTagIds.contains(
                                    tag.id,
                                  );

                                  return CheckboxListTile(
                                    value: selected,
                                    onChanged: _isMutating
                                        ? null
                                        : (_) => _toggleTag(tag),
                                    secondary: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Color(
                                        tag.colorValue,
                                      ).withValues(alpha: 0.14),
                                      child: Icon(
                                        iconForTagKey(tag.iconKey),
                                        size: 17,
                                        color: Color(tag.colorValue),
                                      ),
                                    ),
                                    title: Text(tag.name),
                                    subtitle:
                                        tag.description == null ||
                                            tag.description!.trim().isEmpty
                                        ? null
                                        : Text(
                                            tag.description!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  List<AppTag> _filterTags(List<AppTag> tags) {
    if (_query.isEmpty) return tags;

    return tags.where((tag) {
      final haystack = [
        tag.name,
        tag.description ?? '',
        labelForTagIconKey(tag.iconKey),
      ].join(' ').toLowerCase();

      return haystack.contains(_query);
    }).toList();
  }

  Future<void> _toggleTag(AppTag tag) async {
    final assigned = _assignedTagIds.contains(tag.id);

    setState(() {
      _isMutating = true;
    });

    try {
      if (assigned) {
        await widget.tagRepository.unassignDocumentTag(
          documentId: widget.document.documentId,
          tagId: tag.id,
        );

        _assignedTagIds.remove(tag.id);
      } else {
        await widget.tagRepository.assignDocumentTag(
          documentId: widget.document.documentId,
          tagId: tag.id,
        );

        _assignedTagIds.add(tag.id);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
        });
      }
    }
  }

  Future<void> _createAndAssignTag(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;

    setState(() {
      _isMutating = true;
    });

    try {
      final tagId = await widget.tagRepository.createTag(name: name);
      await widget.tagRepository.assignDocumentTag(
        documentId: widget.document.documentId,
        tagId: tagId,
      );

      _assignedTagIds.add(tagId);
      _searchController.clear();
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
        });
      }
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 15),
      label: Text(label),
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  final bool isSearching;
  final VoidCallback? onImportPdf;

  const _EmptyLibraryState({
    required this.isSearching,
    required this.onImportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                isSearching
                    ? 'No PDFs match your search'
                    : 'Import your first PDF',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? 'Try a different title, author, DOI, journal, or keyword.'
                    : 'Drag PDFs into this window or use the import button.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!isSearching) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onImportPdf,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import PDF'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineMetadataLookupDialog extends StatefulWidget {
  final PdfDocument document;
  final OnlineMetadataLookupService lookupService;

  const _OnlineMetadataLookupDialog({
    required this.document,
    required this.lookupService,
  });

  @override
  State<_OnlineMetadataLookupDialog> createState() =>
      _OnlineMetadataLookupDialogState();
}

class _OnlineMetadataLookupDialogState
    extends State<_OnlineMetadataLookupDialog> {
  final TextEditingController _queryController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<OnlineMetadataCandidate> _candidates = const [];

  @override
  void initState() {
    super.initState();

    _queryController.text = _defaultQuery;
    unawaited(_lookup());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  String get _defaultQuery {
    return [
          widget.document.doi,
          widget.document.name,
          widget.document.authors,
          widget.document.journal,
        ]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' ')
        .trim();
  }

  Future<void> _lookup() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final candidates = await widget.lookupService.lookup(
        widget.document,
        queryOverride: _queryController.text,
      );

      if (!mounted) return;

      setState(() {
        _candidates = candidates;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Online metadata lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _error = '$error';
        _candidates = const [];
        _isLoading = false;
      });
    }
  }

  void _applyCandidate(OnlineMetadataCandidate candidate) {
    Navigator.of(context).pop(_updateFromCandidate(candidate));
  }

  _DocumentMetadataUpdate _updateFromCandidate(
    OnlineMetadataCandidate candidate,
  ) {
    return _DocumentMetadataUpdate(
      name: _fallback(candidate.title, widget.document.name),
      authors: _fallback(candidate.authors, widget.document.authors ?? ''),
      subject: _fallback(candidate.abstractText, widget.document.subject ?? ''),
      fieldOfStudy: _fallback(
        candidate.fieldOfStudy,
        widget.document.fieldOfStudy ?? '',
      ),
      isbn: widget.document.isbn ?? '',
      doi: _fallback(candidate.doi, widget.document.doi ?? ''),
      issn: _fallback(candidate.issn, widget.document.issn ?? ''),
      arxivId: widget.document.arxivId ?? '',
      journal: _fallback(candidate.journal, widget.document.journal ?? ''),
      publisher: _fallback(
        candidate.publisher,
        widget.document.publisher ?? '',
      ),
      keywords: _fallback(candidate.keywords, widget.document.keywords ?? ''),
    );
  }

  String _fallback(String? preferred, String fallback) {
    final value = preferred?.trim();
    if (value != null && value.isNotEmpty) return value;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Search online metadata'),
      content: SizedBox(
        width: 820,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search Crossref and OpenAlex, then review a candidate before applying it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: 'Search query',
                      hintText: 'DOI, title, authors, citation...',
                    ),
                    onSubmitted: (_) => _lookup(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _lookup,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResults(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _OnlineMetadataMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Metadata lookup failed',
        message: _error!,
      );
    }

    if (_candidates.isEmpty) {
      return const _OnlineMetadataMessage(
        icon: Icons.search_off_outlined,
        title: 'No online matches found',
        message:
            'Try searching with a DOI, exact title, author name, or citation text.',
      );
    }

    return ListView.separated(
      itemCount: _candidates.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final candidate = _candidates[index];
        return _OnlineMetadataCandidateCard(
          candidate: candidate,
          onApply: () => _applyCandidate(candidate),
        );
      },
    );
  }
}

class _OnlineMetadataCandidateCard extends StatelessWidget {
  final OnlineMetadataCandidate candidate;
  final VoidCallback onApply;

  const _OnlineMetadataCandidateCard({
    required this.candidate,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MetadataChip(
                            label: candidate.source,
                            color: theme.colorScheme.primary,
                          ),
                          _MetadataChip(
                            label:
                                '${candidate.confidenceLabel} · ${candidate.reason}',
                            color: Colors.green.shade700,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        candidate.title ?? 'Untitled result',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.check),
                  label: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _CandidateLine(label: 'Authors', value: candidate.authors),
            _CandidateLine(label: 'DOI', value: candidate.doi),
            _CandidateLine(label: 'Venue', value: candidate.journal),
            _CandidateLine(label: 'Publisher', value: candidate.publisher),
            _CandidateLine(label: 'Field', value: candidate.fieldOfStudy),
            _CandidateLine(label: 'Keywords', value: candidate.keywords),
            if (candidate.abstractText != null) ...[
              const SizedBox(height: 8),
              Text(
                candidate.abstractText!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CandidateLine extends StatelessWidget {
  final String label;
  final String? value;

  const _CandidateLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

class _OnlineMetadataMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _OnlineMetadataMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataEditorDialog extends StatefulWidget {
  final PdfDocument document;
  final String dialogTitle;
  final ExtractedPdfMetadata? extractedMetadata;

  const _MetadataEditorDialog({
    required this.document,
    required this.dialogTitle,
    required this.extractedMetadata,
  });

  @override
  State<_MetadataEditorDialog> createState() => _MetadataEditorDialogState();
}

class _MetadataEditorDialogState extends State<_MetadataEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _authorsController;
  late final TextEditingController _subjectController;
  late final TextEditingController _fieldOfStudyController;
  late final TextEditingController _isbnController;
  late final TextEditingController _doiController;
  late final TextEditingController _issnController;
  late final TextEditingController _arxivIdController;
  late final TextEditingController _journalController;
  late final TextEditingController _publisherController;
  late final TextEditingController _keywordsController;

  @override
  void initState() {
    super.initState();

    final extracted = widget.extractedMetadata;

    _nameController = TextEditingController(
      text: extracted?.title ?? widget.document.name,
    );
    _authorsController = TextEditingController(
      text: extracted?.authors ?? widget.document.authors ?? '',
    );
    _subjectController = TextEditingController(
      text: extracted?.subject ?? widget.document.subject ?? '',
    );
    _fieldOfStudyController = TextEditingController(
      text: widget.document.fieldOfStudy ?? '',
    );
    _isbnController = TextEditingController(text: widget.document.isbn ?? '');
    _doiController = TextEditingController(text: widget.document.doi ?? '');
    _issnController = TextEditingController(text: widget.document.issn ?? '');
    _arxivIdController = TextEditingController(
      text: widget.document.arxivId ?? '',
    );
    _journalController = TextEditingController(
      text: widget.document.journal ?? '',
    );
    _publisherController = TextEditingController(
      text: widget.document.publisher ?? '',
    );
    _keywordsController = TextEditingController(
      text: extracted?.keywords ?? widget.document.keywords ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _authorsController.dispose();
    _subjectController.dispose();
    _fieldOfStudyController.dispose();
    _isbnController.dispose();
    _doiController.dispose();
    _issnController.dispose();
    _arxivIdController.dispose();
    _journalController.dispose();
    _publisherController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MetadataTextField(
                controller: _nameController,
                label: 'Title',
                requiredField: true,
              ),
              _MetadataTextField(
                controller: _authorsController,
                label: 'Authors',
              ),
              _MetadataTextField(
                controller: _subjectController,
                label: 'Subject / abstract note',
                maxLines: 2,
              ),
              Row(
                children: [
                  Expanded(
                    child: _MetadataTextField(
                      controller: _doiController,
                      label: 'DOI',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetadataTextField(
                      controller: _arxivIdController,
                      label: 'arXiv ID',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _MetadataTextField(
                      controller: _journalController,
                      label: 'Journal / venue',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetadataTextField(
                      controller: _publisherController,
                      label: 'Publisher',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _MetadataTextField(
                      controller: _fieldOfStudyController,
                      label: 'Field of study',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetadataTextField(
                      controller: _keywordsController,
                      label: 'Keywords',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _MetadataTextField(
                      controller: _isbnController,
                      label: 'ISBN',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetadataTextField(
                      controller: _issnController,
                      label: 'ISSN',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;

            Navigator.of(context).pop(
              _DocumentMetadataUpdate(
                name: name,
                authors: _authorsController.text,
                subject: _subjectController.text,
                fieldOfStudy: _fieldOfStudyController.text,
                isbn: _isbnController.text,
                doi: _doiController.text,
                issn: _issnController.text,
                arxivId: _arxivIdController.text,
                journal: _journalController.text,
                publisher: _publisherController.text,
                keywords: _keywordsController.text,
              ),
            );
          },
          child: const Text('Save metadata'),
        ),
      ],
    );
  }
}

class _MetadataTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final bool requiredField;

  const _MetadataTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.requiredField = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: requiredField ? '$label *' : label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _DeleteDocumentDialog extends StatefulWidget {
  final PdfDocument document;
  final _DocumentDeleteImpact impact;

  const _DeleteDocumentDialog({required this.document, required this.impact});

  @override
  State<_DeleteDocumentDialog> createState() => _DeleteDocumentDialogState();
}

class _DeleteDocumentDialogState extends State<_DeleteDocumentDialog> {
  final TextEditingController _confirmationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _confirmationController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  bool get _canDelete => _confirmationController.text.trim() == 'DELETE';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Delete PDF?'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will permanently remove “${widget.document.name}” from your library.',
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.42),
                border: Border.all(color: theme.colorScheme.error),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ImpactLine(label: 'Notes', value: widget.impact.noteCount),
                    _ImpactLine(
                      label: 'Sidecar notes',
                      value: widget.impact.sidecarNoteCount,
                    ),
                    _ImpactLine(
                      label: 'Document notes',
                      value: widget.impact.documentNoteCount,
                    ),
                    _ImpactLine(
                      label: 'Highlights',
                      value: widget.impact.highlightCount,
                    ),
                    _ImpactLine(label: 'TODOs', value: widget.impact.todoCount),
                    _ImpactLine(
                      label: 'Anchors / source links',
                      value: widget.impact.anchorCount,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Type DELETE to confirm.'),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmationController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'DELETE',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _canDelete ? () => Navigator.of(context).pop(true) : null,
          icon: const Icon(Icons.delete_forever),
          label: const Text('Delete permanently'),
        ),
      ],
    );
  }
}

class _ImpactLine extends StatelessWidget {
  final String label;
  final int value;

  const _ImpactLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$value'),
        ],
      ),
    );
  }
}

class _DocumentMetadataUpdate {
  final String name;
  final String authors;
  final String subject;
  final String fieldOfStudy;
  final String isbn;
  final String doi;
  final String issn;
  final String arxivId;
  final String journal;
  final String publisher;
  final String keywords;

  const _DocumentMetadataUpdate({
    required this.name,
    required this.authors,
    required this.subject,
    required this.fieldOfStudy,
    required this.isbn,
    required this.doi,
    required this.issn,
    required this.arxivId,
    required this.journal,
    required this.publisher,
    required this.keywords,
  });
}

class _DocumentDeleteImpact {
  final Set<String> noteIds;
  final int noteCount;
  final int blockCount;
  final int anchorCount;
  final int todoCount;
  final int highlightCount;
  final int documentNoteCount;
  final int sidecarNoteCount;

  const _DocumentDeleteImpact({
    required this.noteIds,
    required this.noteCount,
    required this.blockCount,
    required this.anchorCount,
    required this.todoCount,
    required this.highlightCount,
    required this.documentNoteCount,
    required this.sidecarNoteCount,
  });

  String get summaryLabel {
    final parts = <String>[];

    if (noteCount > 0) parts.add('$noteCount notes');
    if (todoCount > 0) parts.add('$todoCount TODOs');
    if (highlightCount > 0) parts.add('$highlightCount highlights');

    if (parts.isEmpty) return 'No notes yet';
    return parts.join(' · ');
  }

  String get compactLabel {
    final parts = <String>[];

    if (noteCount > 0) parts.add('$noteCount notes');
    if (todoCount > 0) parts.add('$todoCount todos');
    if (highlightCount > 0) parts.add('$highlightCount hl');

    if (parts.isEmpty) return 'No notes';
    return parts.join('\n');
  }
}
