import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import '../../pdf_reader/presentation/pdf_reader_screen.dart';
import '../../planning/data/study_planning_repository.dart';
import '../fluent/fluent_document_command_controller.dart';
import '../commands/text_system_writer_command_registry.dart';
import '../page/text_system_layout_style_resolver.dart';
import '../page/text_system_page_canvas.dart';
import '../page/text_system_page_estimator.dart';
import '../page/text_system_page_layout.dart';
import '../page/text_system_page_map.dart';
import '../page/text_system_pagination_engine.dart';
import '../page/text_system_section_page_metrics.dart';
import '../page/text_system_page_work_plan.dart';
import '../editor/text_system_current_paged_editor_surface.dart';
import '../editor/text_system_owned_editor_command_controller.dart';
import '../editor/text_system_owned_document_editor_surface.dart';
import '../page/text_system_paged_block_surface.dart';
import '../page/text_system_page_setup.dart';
import '../page/text_system_page_furniture.dart';
import '../page/text_system_page_viewport.dart';
import '../references/actions/text_system_reference_actions.dart';
import '../text_system.dart';

/// Full-screen long-form writing shell built on the project-wide text system.
///
/// The writer can still open the older pageless/fluent paths, but its primary
/// real-page mode now routes through [TextSystemCurrentPagedEditorSurface].
/// Phase 16A deliberately isolates that current TextField-backed editor behind
/// an editor-level seam so the owned document editor can be built beside it.
class PremiumWriterScreen extends StatefulWidget {
  const PremiumWriterScreen({
    super.key,
    this.textController,
    this.autosaveController,
    this.initialDocument,
    this.screenTitle = 'Premium Writer',
    this.showInspectorByDefault = false,
    this.database,
    this.planningRepository,
  });

  final TextSystemController? textController;
  final TextSystemAutosaveController? autosaveController;
  final TextSystemDocument? initialDocument;
  final String screenTitle;
  final bool showInspectorByDefault;
  final AppDatabase? database;
  final StudyPlanningRepository? planningRepository;

  @override
  State<PremiumWriterScreen> createState() => _PremiumWriterScreenState();
}


enum _PremiumWriterPageMode {
  pageless,
  hybrid,
  chromeOnly,
  pagedBlocksExperimental,
  ownedDocumentPreview;

  static const List<_PremiumWriterPageMode> displayOrder = <_PremiumWriterPageMode>[
    ownedDocumentPreview,
    pagedBlocksExperimental,
    pageless,
    hybrid,
    chromeOnly,
  ];

  String get label {
    return switch (this) {
      _PremiumWriterPageMode.pageless => 'Pageless',
      _PremiumWriterPageMode.hybrid => 'Hybrid pages',
      _PremiumWriterPageMode.chromeOnly => 'Page chrome',
      _PremiumWriterPageMode.pagedBlocksExperimental => 'Real pages fallback',
      _PremiumWriterPageMode.ownedDocumentPreview => 'Owned editor',
    };
  }

  String get description {
    return switch (this) {
      _PremiumWriterPageMode.pageless => 'Continuous writing surface. No page chrome or break markers.',
      _PremiumWriterPageMode.hybrid => 'Continuous editor with physical page chrome and measured page-break markers.',
      _PremiumWriterPageMode.chromeOnly => 'Continuous editor with physical page frames only.',
      _PremiumWriterPageMode.pagedBlocksExperimental => 'Fallback TextField-backed real-page editor. Keep this available while the owned editor is promoted and hardened.',
      _PremiumWriterPageMode.ownedDocumentPreview => 'Default owned document editor. Edits real pages without body TextFields and supports document-level selection, keyboard editing, clipboard, formatting, references, inline atoms, object blocks, and the text-input bridge.',
    };
  }
}

enum _PremiumWriterRibbonTab {
  home,
  insert,
  references,
  layout,
  review,
  view;

  String get label {
    return switch (this) {
      _PremiumWriterRibbonTab.home => 'Home',
      _PremiumWriterRibbonTab.insert => 'Insert',
      _PremiumWriterRibbonTab.references => 'References',
      _PremiumWriterRibbonTab.layout => 'Layout',
      _PremiumWriterRibbonTab.review => 'Review',
      _PremiumWriterRibbonTab.view => 'View',
    };
  }

  IconData get icon {
    return switch (this) {
      _PremiumWriterRibbonTab.home => Icons.edit_note_rounded,
      _PremiumWriterRibbonTab.insert => Icons.add_box_outlined,
      _PremiumWriterRibbonTab.references => Icons.menu_book_outlined,
      _PremiumWriterRibbonTab.layout => Icons.dashboard_customize_outlined,
      _PremiumWriterRibbonTab.review => Icons.rate_review_outlined,
      _PremiumWriterRibbonTab.view => Icons.visibility_outlined,
    };
  }
}

class _PremiumWriterScreenState extends State<PremiumWriterScreen> {
  late final bool _ownsTextController;
  late final bool _ownsAutosaveController;
  late final TextSystemController _textController;
  late final TextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;
  late final FluentDocumentCommandController _fluentCommands;
  late final TextSystemPagedBlockCommandController _pagedBlockCommands;
  late final TextSystemOwnedEditorCommandController _ownedEditorCommands;
  late final TextSystemWriterCommandRegistry _writerCommands;
  late final TextSystemReferenceActionRepository _referenceActionRepository;
  late final TextSystemEmbeddedTodoRepository? _embeddedTodoRepository;
  late final ScrollController _pageScrollController;
  late final ValueNotifier<int> _writerCommandRevision;

  bool _overviewExpanded = false;
  bool _showToolbar = true;
  bool _showInspector = false;
  bool _showSourceManager = false;
  bool _showObjectNavigator = false;
  bool _focusMode = false;
  bool _widePage = false;
  bool _showMarginGuides = true;
  bool _showDetailedPageBreakLabels = true;
  bool _showMarginMarkers = false;
  bool _showMarginAnnotations = true;
  bool _showInPageToolbar = false;
  double _pageZoom = 1.15;
  _PremiumWriterPageMode _pageMode = _PremiumWriterPageMode.ownedDocumentPreview;
  _PremiumWriterRibbonTab _activeRibbonTab = _PremiumWriterRibbonTab.home;
  TextSystemPageSetup _pageSetup = TextSystemPagePreset.a4FivePages.setup;
  TextSystemPageFurniture _pageFurniture = const TextSystemPageFurniture.defaults();
  TextSystemPageViewport? _pageViewport;
  double _targetPageCount = 5;
  int _planningHorizonDays = 7;

  @override
  void initState() {
    super.initState();
    _showInspector = widget.showInspectorByDefault;
    _fluentCommands = FluentDocumentCommandController();
    _pagedBlockCommands = TextSystemPagedBlockCommandController();
    _ownedEditorCommands = TextSystemOwnedEditorCommandController();
    _writerCommandRevision = ValueNotifier<int>(_pagedBlockCommands.stateRevision + _ownedEditorCommands.stateRevision);
    _pagedBlockCommands.addListener(_handlePagedBlockCommandStateChanged);
    _ownedEditorCommands.addListener(_handlePagedBlockCommandStateChanged);
    _writerCommands = _buildWriterCommandRegistry();
    _referenceActionRepository = widget.database == null
        ? TextSystemMemoryReferenceActionRepository()
        : TextSystemPdfLibraryReferenceActionRepository(
            database: widget.database!,
          );
    _embeddedTodoRepository = widget.database == null
        ? null
        : TextSystemEmbeddedTodoRepository(
            noteRepository: NoteRepository(widget.database!),
          );
    _pageScrollController = ScrollController();

    _ownsTextController = widget.textController == null;
    _textController = widget.textController ?? TextSystemController(document: widget.initialDocument ?? _seedDocument());

    final normalizedDemoDocument = _documentWithPremiumWriterDemoListFix(_textController.document);
    if (!identical(normalizedDemoDocument, _textController.document)) {
      _textController.replaceDocument(
        normalizedDemoDocument,
        label: 'Normalize Writing goals list',
      );
    }

    _persistenceAdapter = const LocalFileTextSystemPersistenceAdapter();
    if (_ownsTextController) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadSavedPremiumWriterDraft());
      });
    }
    _ownsAutosaveController = widget.autosaveController == null;
    _autosaveController = widget.autosaveController ??
        TextSystemAutosaveController(
          textController: _textController,
          persistenceAdapter: _persistenceAdapter,
        );
  }

  void _handlePagedBlockCommandStateChanged() {
    if (!mounted || !_isDocumentEditorCommandSurfaceActive) return;
    _writerCommandRevision.value = _pagedBlockCommands.stateRevision + _ownedEditorCommands.stateRevision;
  }

  @override
  void dispose() {
    _pagedBlockCommands.removeListener(_handlePagedBlockCommandStateChanged);
    _ownedEditorCommands.removeListener(_handlePagedBlockCommandStateChanged);
    _pagedBlockCommands.dispose();
    _ownedEditorCommands.dispose();
    _writerCommandRevision.dispose();
    _pageScrollController.dispose();
    _fluentCommands.dispose();
    if (_ownsAutosaveController) {
      _autosaveController.dispose();
    }
    if (_ownsTextController) {
      _textController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSavedPremiumWriterDraft() async {
    final loaded = await _autosaveController.load(_textController.document.id);
    if (!mounted || loaded == null) return;

    final hydrated = await _hydrateSavedInlineReferences(
      _textController.document,
    );
    final refreshed = TextSystemCitationBibliographyGenerator.refreshDocument(
      hydrated,
    );
    if (jsonEncode(refreshed.toJson()) != jsonEncode(_textController.document.toJson())) {
      _textController.replaceDocument(
        refreshed,
        label: 'Load PDF citation targets',
      );
      await _autosaveController.saveNow(message: 'Loaded and refreshed citations.');
    }

    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Loaded saved premium writer draft.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<TextSystemDocument> _hydrateSavedInlineReferences(
    TextSystemDocument document,
  ) async {
    final targetCache = <String, TextSystemReferenceTarget?>{};
    var changed = false;
    final nextBlocks = <TextSystemBlock>[];

    for (final block in document.blocks) {
      if (TextSystemCitationBibliographyGenerator.isGeneratedBibliographyBlock(block)) {
        nextBlocks.add(block);
        continue;
      }

      var blockChanged = false;
      final nextMarks = <TextMark>[];
      for (final mark in block.marks) {
        final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(
          mark.attributes,
        );
        if (inlineReference == null || inlineReference.targetId.trim().isEmpty) {
          nextMarks.add(mark);
          continue;
        }

        final target = targetCache.containsKey(inlineReference.targetId)
            ? targetCache[inlineReference.targetId]
            : await _referenceActionRepository.resolveTarget(inlineReference.targetId);
        targetCache[inlineReference.targetId] = target;
        if (target == null) {
          nextMarks.add(mark);
          continue;
        }

        final hydrated = _hydrateInlineReferenceFromTarget(
          inlineReference: inlineReference,
          target: target,
        );
        final attributes = hydrated.toTextMarkAttributes();
        if (jsonEncode(attributes) != jsonEncode(mark.attributes)) {
          changed = true;
          blockChanged = true;
          nextMarks.add(mark.copyWith(attributes: attributes));
        } else {
          nextMarks.add(mark);
        }
      }

      nextBlocks.add(
        blockChanged ? block.copyWith(marks: nextMarks).normalizeMarks() : block,
      );
    }

    if (!changed) return document;
    return document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now());
  }

  TextSystemInlineReferenceMark _hydrateInlineReferenceFromTarget({
    required TextSystemInlineReferenceMark inlineReference,
    required TextSystemReferenceTarget target,
  }) {
    final citationInlineMode = inlineReference.metadata['citationInlineMode'];
    final citationStyleId = inlineReference.metadata['citationStyleId'];
    final citationText = inlineReference.metadata['citationText'];

    return inlineReference.copyWith(
      kind: target.kind,
      label: target.title,
      uri: target.uri ?? inlineReference.uri,
      citationKey: target.citationKey ?? inlineReference.citationKey,
      updatedAt: target.updatedAt ?? inlineReference.updatedAt,
      metadata: <String, Object?>{
        ...inlineReference.metadata,
        ...target.metadata,
        if (citationInlineMode != null) 'citationInlineMode': citationInlineMode,
        if (citationStyleId != null) 'citationStyleId': citationStyleId,
        if (citationText != null) 'citationText': citationText,
      },
    );
  }

  TextSystemDocument _seedDocument() {
    final now = DateTime.now();
    return TextSystemDocument(
      id: 'phase-12e-premium-writer-viewport',
      title: 'Premium Writer Draft',
      createdAt: now,
      updatedAt: now,
      metadata: const <String, Object?>{'phase': '12E'},
      blocks: <TextSystemBlock>[
        TextSystemBlock(
          id: 'heading-1',
          type: TextSystemBlockType.heading,
          level: 1,
          text: 'Premium writer',
          metadata: <String, Object?>{'todoCount': 2, 'noteCount': 1},
        ),
        TextSystemBlock.paragraph(
          id: 'paragraph-1',
          text:
              'The premium writer uses a page canvas. Document tools live outside the page, and structure is exposed through styles and overview instead of visible blocks.',
          marks: <TextMark>[
            TextMark(kind: TextMarkKind.bold, range: TextSystemRange(4, 19)),
            TextMark(kind: TextMarkKind.highlight, range: TextSystemRange(66, 73)),
          ],
        ),
        TextSystemBlock(
          id: 'heading-2',
          type: TextSystemBlockType.heading,
          level: 2,
          text: 'Writing goals',
          metadata: <String, Object?>{'todoCount': 1, 'dueSoonCount': 1},
        ),
        TextSystemBlock(
          id: 'writing-goal-1',
          type: TextSystemBlockType.listItem,
          text: 'A4-like page surface with real margins.',
          metadata: <String, Object?>{
            'ordered': true,
            'listGroupId': 'writing-goals',
          },
        ),
        TextSystemBlock(
          id: 'writing-goal-2',
          type: TextSystemBlockType.listItem,
          text: 'Paragraph styles create Heading 1, Heading 2, Heading 3, lists, quotes, todos, and code.',
          metadata: <String, Object?>{
            'ordered': true,
            'listGroupId': 'writing-goals',
          },
        ),
        TextSystemBlock(
          id: 'heading-3',
          type: TextSystemBlockType.heading,
          level: 2,
          text: 'Document map',
          metadata: <String, Object?>{'noteCount': 2},
        ),
        TextSystemBlock.paragraph(
          id: 'paragraph-2',
          text:
              'The overview is derived from headings and lives outside the page. It can expand when useful and collapse when the user wants a clean writing canvas.',
        ),
        TextSystemBlock(
          id: 'heading-4',
          type: TextSystemBlockType.heading,
          level: 3,
          text: 'Phase boundary',
          metadata: <String, Object?>{'todoCount': 1, 'overdueCount': 1},
        ),
        TextSystemBlock.paragraph(
          id: 'paragraph-3',
          text:
              'Phase 12E adds page-layout metadata and heading/page anchors. The editor remains one continuous surface, while the document map can now show approximate page numbers and jump to headings.',
        ),
      ],
    );
  }

  Future<void> _openReferenceTarget(TextSystemInlineReferenceMark inlineReference) async {
    final database = widget.database;
    final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
    final pdfDocumentId = locator?.effectivePdfDocumentId;

    if (database != null && pdfDocumentId != null && pdfDocumentId.trim().isNotEmpty) {
      final documents = await database.getAllDocuments();
      PdfDocument? document;
      for (final candidate in documents) {
        if (candidate.documentId == pdfDocumentId) {
          document = candidate;
          break;
        }
      }

      if (!mounted) return;
      if (document == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find PDF target: $pdfDocumentId.')),
        );
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfReaderScreen(
            database: database,
            documentId: document!.documentId,
            filePath: document!.filePath,
            title: document!.name,
            planningRepository: widget.planningRepository,
            initialPageNumber: locator?.effectivePageNumber,
            initialSourceRects: locator?.sourceRects
                    .map((rect) => PdfSourceRect(
                          pageNumber: rect.pageNumber,
                          left: rect.left,
                          top: rect.top,
                          right: rect.right,
                          bottom: rect.bottom,
                        ))
                    .toList(growable: false) ??
                const <PdfSourceRect>[],
            initialSidecarNoteId: locator?.sidecarNoteId,
            initialOpenLabel: locator?.pageLabel ?? locator?.excerpt,
          ),
        ),
      );
      return;
    }

    final uri = inlineReference.uri?.toString();
    if (uri != null && uri.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: uri));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied target URI: $uri')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No openable PDF/source target is attached to ${inlineReference.label}.')),
    );
  }

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Saved premium writer draft.');
  }

  void _resetDemo() {
    _textController.replaceDocument(_seedDocument(), label: 'Reset premium writer demo');
  }

  void _applyCitationSettings(TextSystemCitationSettings settings) {
    final nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(
      settings.applyToDocument(_textController.document),
      settings: settings,
    );
    _textController.replaceDocument(nextDocument, label: 'Change citation settings');
  }

  Future<void> _editCitationSourceMetadata(TextSystemCitationRegistryItem item) async {
    final source = item.source;
    final authorsController = TextEditingController(text: source.authors.join('; '));
    final yearController = TextEditingController(text: source.year ?? '');
    final titleController = TextEditingController(text: source.title);
    final containerController = TextEditingController(text: source.containerTitle ?? '');
    final publisherController = TextEditingController(text: source.publisher ?? '');
    final doiController = TextEditingController(text: source.doi ?? '');
    final urlController = TextEditingController(text: source.url ?? '');
    final locatorController = TextEditingController(text: source.locator ?? '');

    final result = await showDialog<TextSystemCitationSource>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit citation source'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: authorsController,
                    decoration: const InputDecoration(
                      labelText: 'Authors',
                      helperText: 'Separate multiple authors with semicolons.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: yearController,
                    decoration: const InputDecoration(labelText: 'Year'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: containerController,
                    decoration: const InputDecoration(labelText: 'Journal, book, site, or container'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: publisherController,
                    decoration: const InputDecoration(labelText: 'Publisher'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: doiController,
                    decoration: const InputDecoration(labelText: 'DOI'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(labelText: 'URL'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: locatorController,
                    decoration: const InputDecoration(labelText: 'Locator / page'),
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
                final authors = authorsController.text
                    .split(RegExp(r';|\n'))
                    .map((part) => part.trim())
                    .where((part) => part.isNotEmpty)
                    .toList(growable: false);
                Navigator.of(context).pop(
                  TextSystemCitationSource(
                    id: source.id,
                    title: titleController.text.trim().isEmpty ? 'Untitled source' : titleController.text.trim(),
                    authors: authors,
                    year: _optionalText(yearController.text),
                    containerTitle: _optionalText(containerController.text),
                    publisher: _optionalText(publisherController.text),
                    doi: _optionalText(doiController.text),
                    url: _optionalText(urlController.text),
                    locator: _optionalText(locatorController.text),
                    citationKey: source.citationKey,
                    kind: source.kind,
                  ),
                );
              },
              child: const Text('Save source'),
            ),
          ],
        );
      },
    );

    authorsController.dispose();
    yearController.dispose();
    titleController.dispose();
    containerController.dispose();
    publisherController.dispose();
    doiController.dispose();
    urlController.dispose();
    locatorController.dispose();

    if (result == null) return;
    _replaceCitationSourceMetadata(
      targetId: item.mark.targetId,
      source: result,
    );
  }

  static String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _replaceCitationSourceMetadata({
    required String targetId,
    required TextSystemCitationSource source,
  }) {
    final updatedAt = DateTime.now();
    var changed = false;
    final nextBlocks = <TextSystemBlock>[];

    for (final block in _textController.document.blocks) {
      if (TextSystemCitationBibliographyGenerator.isGeneratedBibliographyBlock(block)) {
        continue;
      }

      var blockChanged = false;
      final nextMarks = <TextMark>[];
      for (final mark in block.marks) {
        final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
        if (inlineReference == null ||
            inlineReference.kind != TextSystemReferenceTargetKind.citation ||
            inlineReference.targetId != targetId) {
          nextMarks.add(mark);
          continue;
        }

        final preserved = Map<String, Object?>.of(inlineReference.metadata)
          ..remove('authors')
          ..remove('year')
          ..remove('title')
          ..remove('sourceTitle')
          ..remove('containerTitle')
          ..remove('publisher')
          ..remove('doi')
          ..remove('url')
          ..remove('locator');
        final metadata = <String, Object?>{
          ...preserved,
          ...source.toMetadata(),
          'title': source.title,
          'sourceTitle': source.title,
          if (source.citationKey != null && source.citationKey!.trim().isNotEmpty)
            'citationKey': source.citationKey!.trim(),
        };

        final updatedReference = inlineReference.copyWith(
          label: source.title,
          citationKey: source.citationKey ?? inlineReference.citationKey,
          updatedAt: updatedAt,
          metadata: metadata,
        );
        nextMarks.add(mark.copyWith(attributes: updatedReference.toTextMarkAttributes()));
        changed = true;
        blockChanged = true;
      }

      nextBlocks.add(blockChanged ? block.copyWith(marks: nextMarks).normalizeMarks() : block);
    }

    if (!changed) return;
    final withoutGenerated = _textController.document.copyWith(
      blocks: nextBlocks,
      updatedAt: updatedAt,
    );
    final refreshed = TextSystemCitationBibliographyGenerator.refreshDocument(withoutGenerated);
    _textController.replaceDocument(refreshed, label: 'Edit citation source');
  }

  Future<void> _repairCitationTargets() async {
    final hydrated = await _hydrateSavedInlineReferences(_textController.document);
    final refreshed = TextSystemCitationBibliographyGenerator.refreshDocument(hydrated);
    final changed = jsonEncode(refreshed.toJson()) != jsonEncode(_textController.document.toJson());
    if (changed) {
      _textController.replaceDocument(refreshed, label: 'Repair citation targets');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(changed ? 'Citation/source targets repaired.' : 'No repairable citation/source targets found.')),
    );
  }

  void _deduplicateCitationSources() {
    final canonicalBySignature = <String, TextSystemInlineReferenceMark>{};
    var mergedCount = 0;
    var changed = false;
    final nextBlocks = <TextSystemBlock>[];

    for (final block in _textController.document.blocks) {
      if (TextSystemCitationBibliographyGenerator.isGeneratedBibliographyBlock(block)) {
        continue;
      }

      var blockChanged = false;
      final nextMarks = <TextMark>[];
      for (final mark in block.marks) {
        final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
        if (inlineReference == null || inlineReference.kind != TextSystemReferenceTargetKind.citation) {
          nextMarks.add(mark);
          continue;
        }

        final signature = _citationSignature(TextSystemCitationSource.fromInlineMark(inlineReference));
        if (signature.isEmpty) {
          nextMarks.add(mark);
          continue;
        }
        final canonical = canonicalBySignature[signature];
        if (canonical == null) {
          canonicalBySignature[signature] = inlineReference;
          nextMarks.add(mark);
          continue;
        }
        if (canonical.targetId == inlineReference.targetId) {
          nextMarks.add(mark);
          continue;
        }

        final merged = inlineReference.copyWith(
          targetId: canonical.targetId,
          label: canonical.label,
          citationKey: canonical.citationKey ?? inlineReference.citationKey,
          metadata: <String, Object?>{
            ...inlineReference.metadata,
            ...canonical.metadata,
            'deduplicatedFromTargetId': inlineReference.targetId,
          },
        );
        nextMarks.add(mark.copyWith(attributes: merged.toTextMarkAttributes()));
        changed = true;
        blockChanged = true;
        mergedCount += 1;
      }
      nextBlocks.add(blockChanged ? block.copyWith(marks: nextMarks).normalizeMarks() : block);
    }

    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No duplicate citation sources found.')),
      );
      return;
    }

    final withoutGenerated = _textController.document.copyWith(
      blocks: nextBlocks,
      updatedAt: DateTime.now(),
    );
    final refreshed = TextSystemCitationBibliographyGenerator.refreshDocument(withoutGenerated);
    _textController.replaceDocument(refreshed, label: 'Deduplicate citation sources');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Merged $mergedCount duplicate citation occurrence${mergedCount == 1 ? '' : 's'}.')),
    );
  }

  String _citationSignature(TextSystemCitationSource source) {
    final title = source.title.trim().toLowerCase();
    final year = (source.year ?? '').trim().toLowerCase();
    final authors = source.authors.map((author) => author.trim().toLowerCase()).where((author) => author.isNotEmpty).join('|');
    final fallbackAuthor = source.authorLabel.trim().toLowerCase();
    final authorPart = authors.isEmpty ? fallbackAuthor : authors;
    final value = '$authorPart::$year::$title';
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _openCitationSourceFromManager(TextSystemCitationRegistryItem item) async {
    await _openReferenceTarget(item.mark);
  }

  Future<void> _openLinkedReferenceFromManager(TextSystemStructureReference reference) async {
    final inlineReference = _inlineReferenceForStructureReference(reference);
    if (inlineReference != null) {
      await _openReferenceTarget(inlineReference);
      return;
    }

    final url = reference.url;
    if (url != null && url.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: url.trim()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied target URL: ${url.trim()}')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No openable target is attached to ${reference.label}.')),
    );
  }

  TextSystemInlineReferenceMark? _inlineReferenceForStructureReference(TextSystemStructureReference reference) {
    final document = _textController.document;
    for (final block in document.blocks) {
      if (block.id != reference.blockId) continue;
      for (final mark in block.marks) {
        final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
        if (inlineReference == null) continue;
        final sameId = inlineReference.id == reference.id;
        final sameTarget = reference.targetId != null && inlineReference.targetId == reference.targetId;
        final sameOffset = mark.range.start == reference.offset;
        if (sameId || (sameTarget && sameOffset)) return inlineReference;
      }
    }
    return null;
  }

  void _showCitationOccurrences(TextSystemCitationRegistryItem item) {
    final occurrences = _citationOccurrencesForTarget(item.mark.targetId);
    _showSourceOccurrencesDialog(
      title: 'Citation occurrences',
      subtitle: item.source.title,
      occurrences: occurrences,
    );
  }

  void _showLinkedReferenceOccurrences(TextSystemStructureReference reference) {
    final occurrences = _linkedReferenceOccurrences(reference);
    _showSourceOccurrencesDialog(
      title: '${reference.kind.label} occurrences',
      subtitle: reference.label,
      occurrences: occurrences,
    );
  }

  List<_SourceOccurrence> _citationOccurrencesForTarget(String targetId) {
    final occurrences = <_SourceOccurrence>[];
    final blocks = _textController.document.blocks;
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      if (TextSystemCitationBibliographyGenerator.isGeneratedBibliographyBlock(block)) continue;
      for (final mark in block.marks) {
        final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
        if (inlineReference == null ||
            inlineReference.kind != TextSystemReferenceTargetKind.citation ||
            inlineReference.targetId != targetId) {
          continue;
        }
        occurrences.add(_SourceOccurrence.fromBlock(block, blockIndex, mark.range.start));
      }
    }
    return occurrences;
  }

  List<_SourceOccurrence> _linkedReferenceOccurrences(TextSystemStructureReference reference) {
    final occurrences = <_SourceOccurrence>[];
    final blocks = _textController.document.blocks;
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      for (final mark in block.marks) {
        final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
        if (inlineReference == null) continue;
        final matchesTarget = reference.targetId != null && inlineReference.targetId == reference.targetId;
        final matchesUrl = reference.url != null && inlineReference.uri?.toString() == reference.url;
        final matchesKind = inlineReference.kind.id == reference.role || inlineReference.kind.name == reference.kind.name;
        if (matchesTarget || matchesUrl || (matchesKind && block.id == reference.blockId && mark.range.start == reference.offset)) {
          occurrences.add(_SourceOccurrence.fromBlock(block, blockIndex, mark.range.start));
        }
      }
    }
    return occurrences;
  }

  void _showSourceOccurrencesDialog({
    required String title,
    required String subtitle,
    required List<_SourceOccurrence> occurrences,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle.trim().isEmpty ? 'Untitled source' : subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (occurrences.isEmpty)
                  const Text('No occurrences found in the editable document body.')
                else
                  SizedBox(
                    height: 340,
                    child: ListView.builder(
                      itemCount: occurrences.length,
                      itemBuilder: (context, index) {
                        final occurrence = occurrences[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 13,
                            child: Text('${index + 1}', style: theme.textTheme.labelSmall),
                          ),
                          title: Text(
                            occurrence.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('Block ${occurrence.blockIndex + 1}'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _navigateToBlock(occurrence.blockId);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }


  bool get _isRealPageEditorActive => _pageMode == _PremiumWriterPageMode.pagedBlocksExperimental;
  bool get _isOwnedDocumentEditorActive => _pageMode == _PremiumWriterPageMode.ownedDocumentPreview;
  bool get _isDocumentEditorCommandSurfaceActive => _isRealPageEditorActive || _isOwnedDocumentEditorActive;

  bool get _canRunRealPageInsertCommand {
    return _isRealPageEditorActive && _pagedBlockCommands.canRunEditorCommand;
  }

  bool get _canRunRealPageReferenceCommand {
    return _isRealPageEditorActive && _pagedBlockCommands.canCreateReference;
  }

  bool get _canRunRealPageEmbeddedTodoCommand {
    return _isRealPageEditorActive && _pagedBlockCommands.canCreateEmbeddedTodo;
  }

  bool get _canRunRealPageHomeCommand {
    return _isRealPageEditorActive && _pagedBlockCommands.canRunEditorCommand;
  }

  bool get _canRunActiveDocumentHomeCommand {
    if (_isOwnedDocumentEditorActive) return _ownedEditorCommands.canRunEditorCommand;
    return _canRunRealPageHomeCommand;
  }

  bool get _canRunActiveDocumentInsertCommand {
    if (_isOwnedDocumentEditorActive) return _ownedEditorCommands.canInsertAtSelection;
    return _canRunRealPageInsertCommand;
  }

  bool get _canRunActiveDocumentStyleCommand {
    if (_isOwnedDocumentEditorActive) return _ownedEditorCommands.canChangeActiveBlockStyle;
    return _canRunRealPageHomeCommand;
  }

  bool get _canRunActiveDocumentEmbeddedTodoCommand {
    if (_isOwnedDocumentEditorActive) return _ownedEditorCommands.canInsertEmbeddedTodo;
    return _canRunRealPageEmbeddedTodoCommand;
  }

  bool get _canUndoActiveDocumentEditor => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canUndo
      : _isRealPageEditorActive && _pagedBlockCommands.canUndo;
  bool get _canRedoActiveDocumentEditor => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canRedo
      : _isRealPageEditorActive && _pagedBlockCommands.canRedo;

  String? _realPageCommandUnavailableReason() {
    if (!_isRealPageEditorActive) {
      return 'Switch to Real pages fallback to use this legacy-only command.';
    }
    if (!_pagedBlockCommands.isAttached) {
      return 'The real-page fallback editor is still initializing.';
    }
    return null;
  }

  String? _activeDocumentCommandUnavailableReason() {
    if (_isOwnedDocumentEditorActive) {
      if (!_ownedEditorCommands.isAttached) {
        return 'The owned editor is still initializing.';
      }
      return null;
    }
    return _realPageCommandUnavailableReason();
  }


  bool get _canRunDocumentReferenceCommand {
    if (_isOwnedDocumentEditorActive) return _ownedEditorCommands.canCreateReference;
    return _canRunRealPageReferenceCommand;
  }

  bool get _canCopyActiveDocumentSelection => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canCopySelection
      : _isRealPageEditorActive && _pagedBlockCommands.canCopySelection;
  bool get _canCutActiveDocumentSelection => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canCutSelection
      : _isRealPageEditorActive && _pagedBlockCommands.canCutSelection;
  bool get _canPasteIntoActiveDocumentSelection => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canPastePlainText
      : _isRealPageEditorActive && _pagedBlockCommands.canPastePlainText;
  bool get _canToggleActiveBold => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canToggleBold
      : _isRealPageEditorActive && _pagedBlockCommands.canToggleBold;
  bool get _canToggleActiveItalic => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canToggleItalic
      : _isRealPageEditorActive && _pagedBlockCommands.canToggleItalic;
  bool get _canToggleActiveUnderline => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canToggleUnderline
      : _isRealPageEditorActive && _pagedBlockCommands.canToggleUnderline;
  bool get _canToggleActiveCode => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canToggleCode
      : _isRealPageEditorActive && _pagedBlockCommands.canToggleCode;
  bool get _canToggleActiveHighlight => _isOwnedDocumentEditorActive
      ? _ownedEditorCommands.canToggleHighlight
      : _isRealPageEditorActive && _pagedBlockCommands.canToggleHighlight;

  bool get _activeBoldSelected => _isOwnedDocumentEditorActive ? _ownedEditorCommands.boldActive : _pagedBlockCommands.boldActive;
  bool get _activeItalicSelected => _isOwnedDocumentEditorActive ? _ownedEditorCommands.italicActive : _pagedBlockCommands.italicActive;
  bool get _activeUnderlineSelected => _isOwnedDocumentEditorActive ? _ownedEditorCommands.underlineActive : _pagedBlockCommands.underlineActive;
  bool get _activeCodeSelected => _isOwnedDocumentEditorActive ? _ownedEditorCommands.codeActive : _pagedBlockCommands.codeActive;
  bool get _activeHighlightSelected => _isOwnedDocumentEditorActive ? _ownedEditorCommands.highlightActive : _pagedBlockCommands.highlightActive;

  Future<void> _copyActiveDocumentSelection() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.copySelection();
      return;
    }
    await _pagedBlockCommands.copySelection();
  }

  Future<void> _cutActiveDocumentSelection() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.cutSelection();
      return;
    }
    await _pagedBlockCommands.cutSelection();
  }

  Future<void> _pasteIntoActiveDocumentSelection() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.pastePlainText();
      return;
    }
    await _pagedBlockCommands.pastePlainText();
  }

  void _toggleActiveBold() => _isOwnedDocumentEditorActive ? _ownedEditorCommands.toggleBold() : _pagedBlockCommands.toggleBold();
  void _toggleActiveItalic() => _isOwnedDocumentEditorActive ? _ownedEditorCommands.toggleItalic() : _pagedBlockCommands.toggleItalic();
  void _toggleActiveUnderline() => _isOwnedDocumentEditorActive ? _ownedEditorCommands.toggleUnderline() : _pagedBlockCommands.toggleUnderline();
  void _toggleActiveCode() => _isOwnedDocumentEditorActive ? _ownedEditorCommands.toggleInlineCode() : _pagedBlockCommands.toggleInlineCode();
  void _toggleActiveHighlight() => _isOwnedDocumentEditorActive ? _ownedEditorCommands.toggleHighlight() : _pagedBlockCommands.toggleHighlight();

  Future<void> _runActiveReferenceAction(TextSystemReferenceActionType actionType) async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.runReferenceAction(actionType);
      return;
    }
    await _pagedBlockCommands.runReferenceAction(actionType);
  }

  void _undoActiveDocumentEditor() {
    if (_isOwnedDocumentEditorActive) {
      _ownedEditorCommands.undo();
      return;
    }
    _pagedBlockCommands.undo();
  }

  void _redoActiveDocumentEditor() {
    if (_isOwnedDocumentEditorActive) {
      _ownedEditorCommands.redo();
      return;
    }
    _pagedBlockCommands.redo();
  }

  void _changeActiveBlockStyleById(String styleId) {
    if (_isOwnedDocumentEditorActive) {
      _ownedEditorCommands.changeActiveBlockStyleById(styleId);
      return;
    }
    _pagedBlockCommands.changeActiveBlockStyleById(styleId);
  }

  void _insertActivePageBreak() {
    if (_isOwnedDocumentEditorActive) {
      _ownedEditorCommands.insertPageBreak();
      return;
    }
    _pagedBlockCommands.insertPageBreak();
  }

  void _insertActiveSectionBreak() {
    if (_isOwnedDocumentEditorActive) {
      _ownedEditorCommands.insertSectionBreak();
      return;
    }
    _pagedBlockCommands.insertSectionBreak();
  }

  void _insertActiveFootnote() {
    if (_isOwnedDocumentEditorActive) {
      _ownedEditorCommands.insertFootnote();
      return;
    }
    _pagedBlockCommands.insertFootnote();
  }

  Future<void> _insertActiveEmbeddedTodo() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.insertEmbeddedTodo();
      return;
    }
    await _pagedBlockCommands.insertEmbeddedTodo();
  }

  Future<void> _insertActiveFigure() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.insertFigure();
      return;
    }
    await _pagedBlockCommands.insertFigure();
  }

  Future<void> _insertActiveTable() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.insertTable();
      return;
    }
    await _pagedBlockCommands.insertTable();
  }

  Future<void> _insertActiveEquation() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.insertEquation();
      return;
    }
    await _pagedBlockCommands.insertEquation();
  }

  Future<void> _insertActiveInlineMath() async {
    if (_isOwnedDocumentEditorActive) {
      await _ownedEditorCommands.insertInlineMath();
      return;
    }
    await _pagedBlockCommands.insertInlineMath();
  }

  TextSystemWriterCommandBinding _realPageInsertCommand({
    required TextSystemWriterCommandId id,
    required String label,
    required String description,
    required FutureOr<void> Function() execute,
    bool Function()? isEnabled,
    String? disabledReason,
  }) {
    return TextSystemWriterCommandBinding(
      id: id,
      label: label,
      description: description,
      execute: execute,
      isEnabled: isEnabled ?? () => _canRunActiveDocumentInsertCommand,
      disabledReason: () => disabledReason ??
          _activeDocumentCommandUnavailableReason() ??
          'Place the caret in the document before using this command.',
    );
  }

  TextSystemWriterCommandBinding _realPageHomeCommand({
    required TextSystemWriterCommandId id,
    required String label,
    required String description,
    required FutureOr<void> Function() execute,
    bool Function()? isEnabled,
    bool Function()? isSelected,
    String? disabledReason,
  }) {
    return TextSystemWriterCommandBinding(
      id: id,
      label: label,
      description: description,
      execute: execute,
      isEnabled: isEnabled ?? () => _canRunActiveDocumentHomeCommand,
      isSelected: isSelected,
      disabledReason: () => disabledReason ??
          _activeDocumentCommandUnavailableReason() ??
          'Click inside the active document editor before using this command.',
    );
  }

  TextSystemWriterCommandRegistry _buildWriterCommandRegistry() {
    final registry = TextSystemWriterCommandRegistry();
    registry.registerAll([
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.save,
        label: 'Save',
        description: 'Save the current Premium Writer document.',
        execute: _saveNow,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.toggleFocusMode,
        label: 'Focus',
        description: 'Toggle focus mode.',
        execute: () => setState(() => _focusMode = !_focusMode),
        isSelected: () => _focusMode,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.toggleDocumentMap,
        label: 'Map',
        description: 'Show or hide the document map.',
        execute: () => setState(() => _overviewExpanded = !_overviewExpanded),
        isSelected: () => _overviewExpanded,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.toggleInspector,
        label: 'Inspector',
        description: 'Show or hide the document inspector.',
        execute: () => setState(() => _showInspector = !_showInspector),
        isSelected: () => _showInspector,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.objectNavigator,
        label: 'Objects',
        description: 'Show or hide the figure and table navigator.',
        execute: () => setState(() => _showObjectNavigator = !_showObjectNavigator),
        isSelected: () => _showObjectNavigator,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.toggleWidePage,
        label: 'Wide',
        description: 'Toggle the wide writing canvas.',
        execute: () => setState(() => _widePage = !_widePage),
        isSelected: () => _widePage,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.toggleMarginGuides,
        label: 'Margins',
        description: 'Show or hide page margin guides.',
        execute: () => setState(() => _showMarginGuides = !_showMarginGuides),
        isSelected: () => _showMarginGuides,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.togglePageBreakLabels,
        label: 'Breaks',
        description: 'Show or hide detailed page-break labels.',
        execute: () => setState(() => _showDetailedPageBreakLabels = !_showDetailedPageBreakLabels),
        isSelected: () => _showDetailedPageBreakLabels,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.toggleMarginMarkers,
        label: 'Source marks',
        description: 'Show or hide compact in-page markers for citations, links, footnotes, and synced TODOs.',
        execute: () => setState(() => _showMarginMarkers = !_showMarginMarkers),
        isSelected: () => _showMarginMarkers,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.hideMasterHeader,
        label: 'Hide header',
        description: 'Hide the master writer header.',
        execute: () => setState(() => _showToolbar = false),
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.undo,
        label: 'Undo',
        description: 'Undo the latest document edit.',
        execute: _undoActiveDocumentEditor,
        isEnabled: () => _canUndoActiveDocumentEditor,
        disabledReason: 'There is nothing to undo yet.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.redo,
        label: 'Redo',
        description: 'Redo the latest undone document edit.',
        execute: _redoActiveDocumentEditor,
        isEnabled: () => _canRedoActiveDocumentEditor,
        disabledReason: 'There is nothing to redo yet.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.copy,
        label: 'Copy',
        description: 'Copy the current selection.',
        execute: _copyActiveDocumentSelection,
        isEnabled: () => _canCopyActiveDocumentSelection,
        disabledReason: 'Select text before copying.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.cut,
        label: 'Cut',
        description: 'Cut the current selection.',
        execute: _cutActiveDocumentSelection,
        isEnabled: () => _canCutActiveDocumentSelection,
        disabledReason: 'Select text before cutting.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.paste,
        label: 'Paste',
        description: 'Paste clipboard content into the document.',
        execute: _pasteIntoActiveDocumentSelection,
        isEnabled: () => _canPasteIntoActiveDocumentSelection,
        disabledReason: 'Click inside an editable text block before pasting.',
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.style,
        label: 'Style',
        description: 'Apply a paragraph style.',
        disabledReason: 'Use the style picker in the Home tab.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.bold,
        label: 'Bold',
        description: 'Toggle bold text.',
        execute: _toggleActiveBold,
        isEnabled: () => _canToggleActiveBold,
        isSelected: () => _activeBoldSelected,
        disabledReason: 'Select text before toggling bold.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.italic,
        label: 'Italic',
        description: 'Toggle italic text.',
        execute: _toggleActiveItalic,
        isEnabled: () => _canToggleActiveItalic,
        isSelected: () => _activeItalicSelected,
        disabledReason: 'Select text before toggling italic.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.underline,
        label: 'Underline',
        description: 'Toggle underline text.',
        execute: _toggleActiveUnderline,
        isEnabled: () => _canToggleActiveUnderline,
        isSelected: () => _activeUnderlineSelected,
        disabledReason: 'Select text before toggling underline.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.inlineCode,
        label: 'Code',
        description: 'Toggle inline code.',
        execute: _toggleActiveCode,
        isEnabled: () => _canToggleActiveCode,
        isSelected: () => _activeCodeSelected,
        disabledReason: 'Select text before toggling inline code.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.highlight,
        label: 'Highlight',
        description: 'Toggle highlight.',
        execute: _toggleActiveHighlight,
        isEnabled: () => _canToggleActiveHighlight,
        isSelected: () => _activeHighlightSelected,
        disabledReason: 'Select text before toggling highlight.',
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.bulletList,
        label: 'Bullets',
        description: 'Convert the active block/list group to a bullet list.',
        execute: () => _changeActiveBlockStyleById(TextSystemDocumentStyleSheet.listParagraph),
        isEnabled: () => _canRunActiveDocumentStyleCommand,
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.numberedList,
        label: 'Numbered',
        description: 'Convert the active block/list group to a numbered list.',
        execute: () => _changeActiveBlockStyleById(TextSystemDocumentStyleSheet.numberedList),
        isEnabled: () => _canRunActiveDocumentStyleCommand,
      ),
      _realPageHomeCommand(
        id: TextSystemWriterCommandId.documentTodo,
        label: 'Doc TODO',
        description: 'Convert the active block/list group to a document-local todo.',
        execute: () => _changeActiveBlockStyleById(TextSystemDocumentStyleSheet.todo),
        isEnabled: () => _canRunActiveDocumentStyleCommand,
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.align,
        label: 'Align',
        description: 'Change paragraph alignment.',
        disabledReason: 'Alignment controls will move after the style/paragraph migration hardens.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.pageBreak,
        label: 'Page break',
        description: 'Insert a structural page break at the active caret.',
        execute: _insertActivePageBreak,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.sectionBreak,
        label: 'Section',
        description: 'Insert a next-page section break at the active caret.',
        execute: _insertActiveSectionBreak,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.footnote,
        label: 'Footnote',
        description: 'Insert a footnote anchor at the active caret.',
        execute: _insertActiveFootnote,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.appTodo,
        label: 'App TODO',
        description: 'Insert a TODO block synced with the app TODO system.',
        execute: _insertActiveEmbeddedTodo,
        isEnabled: () => _canRunActiveDocumentEmbeddedTodoCommand,
        disabledReason: widget.database == null
            ? 'Open the writer from the app/library route to create synced app TODOs.'
            : null,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.table,
        label: 'Table',
        description: 'Insert an academic table block with caption and label metadata.',
        execute: _insertActiveTable,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.figure,
        label: 'Figure',
        description: 'Insert an academic figure block with caption and label metadata.',
        execute: _insertActiveFigure,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.equation,
        label: 'Equation',
        description: 'Insert an unnumbered centered LaTeX display equation block.',
        execute: _insertActiveEquation,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.inlineMath,
        label: 'Inline math',
        description: r'Insert inline LaTeX math using \( ... \) delimiters at the caret or around the selection.',
        execute: _insertActiveInlineMath,
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.crossReference,
        label: 'Cross-ref',
        description: 'Insert a cross-reference to a figure, table, or equation.',
        execute: _pagedBlockCommands.insertCrossReference,
        isEnabled: () => _canRunRealPageInsertCommand,
        disabledReason: () => _realPageCommandUnavailableReason() ??
            'Place the caret where the cross-reference should be inserted.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.addCitation,
        label: 'Cite',
        description: 'Insert an academic citation from the active caret or selection.',
        execute: () => _runActiveReferenceAction(TextSystemReferenceActionType.citation),
        isEnabled: () => _canRunDocumentReferenceCommand,
        disabledReason: 'Select text or place the caret before creating a citation.',
      ),
      TextSystemWriterCommandBinding(
        id: TextSystemWriterCommandId.sourceManager,
        label: 'Sources',
        description: 'Open or close the citation and source manager panel.',
        execute: () => setState(() => _showSourceManager = !_showSourceManager),
        isSelected: () => _showSourceManager,
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.linkSource,
        label: 'Source',
        description: 'Link the active caret or selection to a source/PDF.',
        execute: () => _runActiveReferenceAction(TextSystemReferenceActionType.source),
        isEnabled: () => _canRunDocumentReferenceCommand,
        disabledReason: 'Select text or place the caret before linking a source.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.linkDocument,
        label: 'Document',
        description: 'Link the active caret or selection to another document.',
        execute: () => _runActiveReferenceAction(TextSystemReferenceActionType.document),
        isEnabled: () => _canRunDocumentReferenceCommand,
        disabledReason: 'Select text or place the caret before linking a document.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.linkProject,
        label: 'Project',
        description: 'Link the active caret or selection to a project.',
        execute: () => _runActiveReferenceAction(TextSystemReferenceActionType.project),
        isEnabled: () => _canRunDocumentReferenceCommand,
        disabledReason: 'Select text or place the caret before linking a project.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.linkTodo,
        label: 'Todo',
        description: 'Link the active caret or selection to an app TODO.',
        execute: () => _runActiveReferenceAction(TextSystemReferenceActionType.todo),
        isEnabled: () => _canRunDocumentReferenceCommand,
        disabledReason: 'Select text or place the caret before linking a todo.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.externalLink,
        label: 'Link',
        description: 'Insert or apply an external link.',
        execute: () => _runActiveReferenceAction(TextSystemReferenceActionType.link),
        isEnabled: () => _canRunDocumentReferenceCommand,
        disabledReason: 'Select text or place the caret before creating a link.',
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.headerFooter,
        label: 'Header',
        description: 'Edit headers and footers.',
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.pageNumbers,
        label: 'Numbers',
        description: 'Configure page numbers.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.comment,
        label: 'Comment',
        description: 'Open a Google Docs-style comment card beside the active caret position.',
        execute: _pagedBlockCommands.addMarginComment,
        isEnabled: () => _isRealPageEditorActive && _pagedBlockCommands.canRunEditorCommand,
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.checkReferences,
        label: 'Check refs',
        description: 'Review broken or incomplete references.',
        disabledReason: 'Reference validation will move into the source manager/review panel later.',
      ),
      _realPageInsertCommand(
        id: TextSystemWriterCommandId.documentTodos,
        label: 'Doc TODO',
        description: 'Open a Google Docs-style action-item card beside the active caret position.',
        execute: _pagedBlockCommands.addMarginTodo,
        isEnabled: () => _isRealPageEditorActive && _pagedBlockCommands.canRunEditorCommand,
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.stats,
        label: 'Stats',
        description: 'Open document statistics.',
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.versionHistory,
        label: 'History',
        description: 'Open version history.',
        disabledReason: 'Version history is planned for a later persistence phase.',
      ),
      disabledTextSystemWriterCommand(
        id: TextSystemWriterCommandId.splitView,
        label: 'Split',
        description: 'Open split view.',
        disabledReason: 'Split view is planned for a later workspace phase.',
      ),
    ]);
    return registry;
  }

  Future<void> _executeWriterCommand(TextSystemWriterCommandId commandId) async {
    await _writerCommands.execute(commandId);
    if (mounted) setState(() {});
  }

  void _applyBlockStyleFromHeader(String styleId) {
    _changeActiveBlockStyleById(styleId);
    if (mounted) setState(() {});
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _buildReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Premium writer report copied.')),
    );
  }

  Future<void> _exportDocument(TextSystemExportFormat format) async {
    final exportDocument = TextSystemCitationBibliographyGenerator.refreshDocument(
      _documentWithPremiumWriterDemoListFix(_textController.document),
    );
    final result = await TextSystemExportService.exportDocument(
      document: exportDocument,
      format: format,
      options: TextSystemExportOptions(
        pageSetup: _pageSetup,
        pageFurniture: _pageFurniture,
        layoutTree: _buildUnifiedLayoutTree(document: exportDocument),
      ),
    );

    if (!mounted) return;

    if (result.text != null) {
      await Clipboard.setData(ClipboardData(text: result.text!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${format.label} export copied to clipboard.')),
      );
      return;
    }

    final bytes = result.bytes;
    if (bytes == null) return;

    final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final fileName = '${_safeExportFileName(_textController.document.title)}.${result.fileExtension}';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${format.label} exported to ${file.path}')),
    );
  }

  String _safeExportFileName(String rawTitle) {
    final trimmed = rawTitle.trim().isEmpty ? 'premium-writer-export' : rawTitle.trim();
    final sanitized = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return sanitized.isEmpty ? 'premium-writer-export' : sanitized;
  }

  void _setPageZoom(double value) {
    final clamped = value.clamp(0.75, 1.75).toDouble();
    final roundedToPercent = (clamped * 100).roundToDouble() / 100;
    setState(() => _pageZoom = roundedToPercent);
  }

  void _zoomIn() {
    _setPageZoom(_pageZoom + 0.05);
  }

  void _zoomOut() {
    _setPageZoom(_pageZoom - 0.05);
  }

  TextSystemDocumentLayoutTree _buildUnifiedLayoutTree({TextSystemDocument? document}) {
    final pageMaxWidth = _widePage ? 900.0 : 794.0;
    final effectivePageWidth = pageMaxWidth * _pageSetup.visualWidthScaleRelativeToA4Portrait;

    return TextSystemLayoutTreeBuilder.build(
      context: context,
      document: document ?? _textController.document,
      pageSetup: _pageSetup,
      pageFurniture: _pageFurniture,
      pageWidthPx: effectivePageWidth,
      documentRevision: _textController.revision,
    );
  }


  TextSystemDocument _documentWithPremiumWriterDemoListFix(TextSystemDocument document) {
    var changed = false;
    var insideWritingGoals = false;

    final blocks = <TextSystemBlock>[
      for (final block in document.blocks)
        () {
          if (block.type == TextSystemBlockType.heading) {
            insideWritingGoals = block.text.trim().toLowerCase() == 'writing goals';
            return block;
          }

          if (!insideWritingGoals ||
              (block.type != TextSystemBlockType.listItem && block.type != TextSystemBlockType.paragraph)) {
            return block;
          }

          final text = block.text.trim();
          final isPremiumWriterGoal =
              text == 'A4-like page surface with real margins.' ||
              text == 'Paragraph styles create Heading 1, Heading 2, Heading 3, lists, quotes, todos, and code.';

          if (!isPremiumWriterGoal) {
            return block;
          }

          if (block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true) {
            return block;
          }

          changed = true;
          return block.copyWith(
            type: TextSystemBlockType.listItem,
            metadata: <String, Object?>{
              ...block.metadata,
              'ordered': true,
              'listGroupId': block.metadata['listGroupId'] ?? 'writing-goals',
            },
          );
        }(),
    ];

    return changed
        ? document.copyWith(blocks: blocks, updatedAt: DateTime.now())
        : document;
  }

  String _buildReport() {
    final document = _textController.document;
    final pageEstimate = TextSystemPageEstimator.estimate(document: document, pageSetup: _pageSetup);
    final pageLayout = TextSystemPageLayoutEngine.layout(
      document: document,
      pageSetup: _pageSetup,
      estimate: pageEstimate,
    );
    final pageMap = TextSystemPaginationEngine.paginate(
      context: context,
      document: document,
      pageSetup: _pageSetup,
      documentRevision: _textController.revision,
      pageWidthPx: 794 * _pageSetup.visualWidthScaleRelativeToA4Portrait,
    );
    final sectionMetrics = TextSystemSectionPageMetricsResult.compute(
      document: document,
      pageMap: pageMap,
      targetPages: _targetPageCount,
    );
    final workPlan = TextSystemPageWorkPlan.compute(
      sectionMetrics: sectionMetrics,
      planningHorizonDays: _planningHorizonDays,
    );
    final outlineItems = _outlineItems(document, pageLayout, sectionMetrics);
    final unifiedLayoutTree = _buildUnifiedLayoutTree(document: document);
    final documentStructure = TextSystemDocumentStructure.build(
      document: document,
      layoutTree: unifiedLayoutTree,
    );
    final referenceIndex = TextSystemReferenceIndex.fromStructure(documentStructure);
    final payload = <String, Object?>{
      'phase': '13G',
      'surface': 'PremiumWriterScreen',
      'presentation': 'Page-aware premium writer canvas with scroll-aware viewport and render-window planning',
      'documentId': document.id,
      'title': document.title,
      'textUnits': document.blocks.length,
      'outlineItems': outlineItems.length,
      'wordCount': _wordCount(document),
      'characterCount': document.plainText.length,
      'revision': _textController.revision,
      'transactions': _textController.transactionLog.length,
      'snapshots': _textController.snapshots.length,
      'canUndo': _textController.canUndo,
      'canRedo': _textController.canRedo,
      'saveStatus': _autosaveController.saveState.status.name,
      'saveMessage': _autosaveController.saveState.message,
      'layout': <String, Object?>{
        'overviewExpanded': _overviewExpanded,
        'showToolbar': _showToolbar,
        'showInspector': _showInspector,
        'focusMode': _focusMode,
        'widePage': _widePage,
        'showMarginGuides': _showMarginGuides,
        'showDetailedPageBreakLabels': _showDetailedPageBreakLabels,
        'pageMode': _pageMode.name,
        'hybridPageBreakOverlay': <String, Object?>{
          'enabled': _pageMode == _PremiumWriterPageMode.hybrid,
          'markerCount': pageMap.breakMarkers.length,
          'labelMode': _showDetailedPageBreakLabels ? 'detailed' : 'compact',
          'currentPage': _pageViewport?.currentPage,
          'visibleRange': _pageViewport?.visibleRangeLabel,
        },
      },
      'pageSetup': _pageSetup.toJson(),
      'pageFurniture': _pageFurniture.toJson(),
      'pageEstimate': pageEstimate.toJson(),
      'pageLayout': pageLayout.toJson(),
      'pageMap': pageMap.toJson(),
      'sectionPageMetrics': sectionMetrics.toJson(),
      'documentStructure': documentStructure.toJson(),
      'referenceIndex': referenceIndex.toJson(),
      'pageWorkPlan': workPlan.toJson(),
      'targetPageCount': _targetPageCount,
      'planningHorizonDays': _planningHorizonDays,
      'pageViewport': _pageViewport?.toJson(),
      'document': document.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }



  List<_AcademicObjectNavigatorItem> _academicObjectItems(
    TextSystemDocument document,
    TextSystemDocumentStructure documentStructure,
  ) {
    final pageByBlockId = <String, int>{
      for (final reference in documentStructure.references)
        if (reference.kind == TextSystemStructureReferenceKind.figure ||
            reference.kind == TextSystemStructureReferenceKind.table ||
            reference.kind == TextSystemStructureReferenceKind.equation)
          reference.blockId: reference.pageNumber,
    };

    final items = <_AcademicObjectNavigatorItem>[];
    var figureOrdinal = 0;
    var tableOrdinal = 0;
    var equationOrdinal = 0;

    for (var blockIndex = 0; blockIndex < document.blocks.length; blockIndex++) {
      final block = document.blocks[blockIndex];
      if (block.type != TextSystemBlockType.custom) continue;
      final rawKind = block.metadata['kind'];
      if (rawKind != 'figure' && rawKind != 'table' && rawKind != 'equation') continue;

      final kind = rawKind == 'table'
          ? TextSystemStructureReferenceKind.table
          : rawKind == 'equation'
              ? TextSystemStructureReferenceKind.equation
              : TextSystemStructureReferenceKind.figure;
      final ordinal = kind == TextSystemStructureReferenceKind.figure
          ? ++figureOrdinal
          : kind == TextSystemStructureReferenceKind.table
              ? ++tableOrdinal
              : ++equationOrdinal;
      final caption = rawKind == 'equation'
          ? _stringMetadata(block.metadata, 'latex').trim().isNotEmpty
              ? _stringMetadata(block.metadata, 'latex').trim()
              : block.text.trim()
          : _stringMetadata(block.metadata, 'caption').trim().isNotEmpty
              ? _stringMetadata(block.metadata, 'caption').trim()
              : block.text.trim();
      final label = _stringMetadata(block.metadata, 'label').trim();
      final source = _stringMetadata(block.metadata, 'source').trim();
      final note = _stringMetadata(block.metadata, 'note').trim();
      final imagePath = _stringMetadata(block.metadata, 'imagePath').trim();
      final rows = _metadataInt(block.metadata, 'rows');
      final columns = _metadataInt(block.metadata, 'columns');

      items.add(
        _AcademicObjectNavigatorItem(
          blockId: block.id,
          blockIndex: blockIndex,
          kind: kind,
          ordinal: ordinal,
          caption: caption,
          label: label,
          pageNumber: pageByBlockId[block.id] ?? 1,
          source: source,
          note: note,
          imagePath: imagePath,
          rows: rows,
          columns: columns,
        ),
      );
    }

    return items;
  }

  String _stringMetadata(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    return value is String ? value : '';
  }

  int _wordCount(TextSystemDocument document) {
    final trimmed = document.plainText.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }

  List<_PremiumOutlineItem> _outlineItems(
    TextSystemDocument document,
    TextSystemPageLayout pageLayout,
    TextSystemSectionPageMetricsResult sectionMetrics,
  ) {
    final items = <_PremiumOutlineItem>[];
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (block.type != TextSystemBlockType.heading) continue;
      final text = block.text.trim();
      if (text.isEmpty) continue;
      items.add(
        _PremiumOutlineItem(
          blockId: block.id,
          text: text,
          level: block.level ?? 2,
          index: i,
          todoCount: _metadataInt(block.metadata, 'todoCount'),
          noteCount: _metadataInt(block.metadata, 'noteCount'),
          dueSoonCount: _metadataInt(block.metadata, 'dueSoonCount'),
          overdueCount: _metadataInt(block.metadata, 'overdueCount'),
          pageAnchor: pageLayout.anchorForBlockId(block.id),
          sectionMetric: sectionMetrics.metricForBlockId(block.id),
        ),
      );
    }
    return items;
  }

  int _metadataInt(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  void _handlePageViewportChanged(TextSystemPageViewport viewport) {
    if (_pageViewport?.signature == viewport.signature) return;
    setState(() => _pageViewport = viewport);
  }

  void _jumpToHeading(_PremiumOutlineItem item) {
    _navigateToBlock(
      item.blockId,
      label: item.text,
      fallbackPageNumber: item.pageAnchor?.pageNumber ?? item.sectionMetric?.startPage,
    );
  }

  Future<void> _navigateToBlock(
    String blockId, {
    String? label,
    int? fallbackPageNumber,
  }) async {
    final didJump = _fluentCommands.jumpToBlock(blockId);
    final layoutTree = _buildUnifiedLayoutTree();
    final fragment = layoutTree.firstFragmentForBlock(blockId);
    final pageNumber = fragment?.physicalPageNumber ?? fallbackPageNumber ?? 1;
    final intraPageOffset = fragment?.rect.top ?? 0.0;

    await _navigateToPage(
      pageNumber,
      intraPageOffset: intraPageOffset,
      label: label,
      showSnackBar: false,
    );

    if (!mounted) return;
    final readableLabel = label == null || label.trim().isEmpty ? 'selected item' : '"${label.trim()}"';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          didJump
              ? 'Jumped to $readableLabel on page $pageNumber.'
              : 'Scrolled to page $pageNumber for $readableLabel.',
        ),
      ),
    );
  }

  Future<void> _navigateToPage(
    int pageNumber, {
    double intraPageOffset = 0,
    String? label,
    bool showSnackBar = true,
  }) async {
    if (!_pageScrollController.hasClients) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Page navigation will be available after the page viewport is measured.')),
        );
      }
      return;
    }

    final layoutTree = _buildUnifiedLayoutTree();
    final viewport = _pageViewport;
    var pageCount = layoutTree.pageCount;
    if (viewport != null && viewport.pageCount > pageCount) {
      pageCount = viewport.pageCount;
    }

    final clampedPage = pageNumber.clamp(1, pageCount).toInt();
    final pageExtent = _navigationPageExtent(viewport);
    final safeIntraPageOffset = intraPageOffset.clamp(0.0, pageExtent * 0.72).toDouble();
    final rawOffset = _navigationOffsetForPage(
      clampedPage,
      pageExtent: pageExtent,
      intraPageOffset: safeIntraPageOffset,
    );
    final targetOffset = rawOffset.clamp(
      _pageScrollController.position.minScrollExtent,
      _pageScrollController.position.maxScrollExtent,
    ).toDouble();

    await _pageScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );

    if (!mounted || !showSnackBar) return;
    final suffix = label == null || label.trim().isEmpty ? '' : ' · ${label.trim()}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Jumped to page $clampedPage$suffix.')),
    );
  }

  double _navigationPageExtent(TextSystemPageViewport? viewport) {
    final viewportExtent = viewport?.pageExtentPx;
    if (viewportExtent != null && viewportExtent > 1) {
      return viewportExtent;
    }
    return _estimatedNavigationPageExtent();
  }

  double _navigationOffsetForPage(
    int pageNumber, {
    required double pageExtent,
    required double intraPageOffset,
  }) {
    final pageIndexOffset = (pageNumber - 1) * pageExtent;

    // The real-page block surface has toolbar/banner chrome above the first
    // physical page. Account for it so page jumps do not undershoot in the
    // experimental paged-block editor.
    final topChromeOffset = (_pageMode == _PremiumWriterPageMode.pagedBlocksExperimental ||
            _pageMode == _PremiumWriterPageMode.ownedDocumentPreview)
        ? _estimatedPagedBlockSurfaceTopChromeOffset()
        : 0.0;

    return topChromeOffset + pageIndexOffset + intraPageOffset;
  }

  double _estimatedPagedBlockSurfaceTopChromeOffset() {
    // The in-page toolbar is retired by default. Page navigation should account
    // only for the scroll padding above the first physical page unless the
    // legacy fallback toolbar is explicitly re-enabled.
    if (!_showInPageToolbar) return _focusMode ? 38.0 : 68.0;

    return _focusMode ? 96.0 : 132.0;
  }

  double _estimatedNavigationPageExtent() {
    final pageMaxWidth = _widePage ? 900.0 : 794.0;
    final pageWidth = pageMaxWidth * _pageSetup.visualWidthScaleRelativeToA4Portrait;
    final visualPageHeight = pageWidth * _pageSetup.heightToWidthRatio * _pageZoom;
    final pageHeaderAndGap = ((_pageMode == _PremiumWriterPageMode.pagedBlocksExperimental ||
            _pageMode == _PremiumWriterPageMode.ownedDocumentPreview)
        ? 50.0
        : 32.0) * _pageZoom;
    final pageGap = ((_pageMode == _PremiumWriterPageMode.pagedBlocksExperimental ||
            _pageMode == _PremiumWriterPageMode.ownedDocumentPreview)
            ? 76.0
            : (_focusMode ? 72.0 : 96.0)) *
        _pageZoom;
    return pageHeaderAndGap + visualPageHeight + pageGap;
  }

  Widget _buildDocumentSurface({
    required EdgeInsetsGeometry padding,
    required int minLines,
    required TextStyle textStyle,
  }) {
    return TextSystemDocumentSurface(
      textController: _textController,
      autosaveController: _autosaveController,
      fluentCommandController: _fluentCommands,
      referenceActionRepository: _referenceActionRepository,
      config: TextSystemDocumentSurfaceConfig.fluent(
        showStatusBar: false,
        showToolbar: false,
        showFrame: false,
        minLines: minLines,
        padding: padding,
        textStyle: textStyle,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_textController, _autosaveController, _fluentCommands]),
      builder: (context, _) {
        final document = _textController.document;
        final wordCount = _wordCount(document);
        final pageEstimate = TextSystemPageEstimator.estimate(document: document, pageSetup: _pageSetup);
        final pageLayout = TextSystemPageLayoutEngine.layout(
          document: document,
          pageSetup: _pageSetup,
          estimate: pageEstimate,
        );
        final showPanels = !_focusMode;
        final pageMaxWidth = _widePage ? 900.0 : 794.0;
        final effectivePageWidth = pageMaxWidth * _pageSetup.visualWidthScaleRelativeToA4Portrait;
        final editorPagePadding = _pageSetup.margins.toPagePadding(
          effectivePageWidth,
          _pageSetup.pageWidthMm,
        );
        final pageMap = TextSystemPaginationEngine.paginate(
          context: context,
          document: document,
          pageSetup: _pageSetup,
          documentRevision: _textController.revision,
          pageWidthPx: effectivePageWidth,
        );
        final sectionMetrics = TextSystemSectionPageMetricsResult.compute(
          document: document,
          pageMap: pageMap,
          targetPages: _targetPageCount,
        );
        final workPlan = TextSystemPageWorkPlan.compute(
          sectionMetrics: sectionMetrics,
          planningHorizonDays: _planningHorizonDays,
        );
        final outlineItems = _outlineItems(document, pageLayout, sectionMetrics);
        final editorBodyStyle = TextSystemLayoutStyleResolver.editorBodyStyle(
          context: context,
          pageSetup: _pageSetup,
        );
        final unifiedLayoutTree = TextSystemLayoutTreeBuilder.build(
          context: context,
          document: document,
          pageSetup: _pageSetup,
          pageFurniture: _pageFurniture,
          pageWidthPx: effectivePageWidth,
          documentRevision: _textController.revision,
        );
        final documentStructure = TextSystemDocumentStructure.build(
          document: document,
          layoutTree: unifiedLayoutTree,
        );
        final referenceIndex = TextSystemReferenceIndex.fromStructure(documentStructure);

        return Scaffold(
          backgroundColor: colorScheme.surfaceContainerLow,
          appBar: AppBar(
            title: Text(widget.screenTitle),
            centerTitle: false,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: null,
                onPressed: () => unawaited(_executeWriterCommand(TextSystemWriterCommandId.toggleFocusMode)),
                icon: Icon(_focusMode ? Icons.center_focus_strong_rounded : Icons.center_focus_weak_rounded),
              ),
              PopupMenuButton<TextSystemExportFormat>(
                tooltip: null,
                icon: const Icon(Icons.ios_share_rounded),
                onSelected: _exportDocument,
                itemBuilder: (context) => <PopupMenuEntry<TextSystemExportFormat>>[
                  for (final format in TextSystemExportFormat.values)
                    PopupMenuItem<TextSystemExportFormat>(
                      value: format,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          switch (format) {
                            TextSystemExportFormat.markdown => Icons.notes_rounded,
                            TextSystemExportFormat.pdf => Icons.picture_as_pdf_rounded,
                            TextSystemExportFormat.latex => Icons.functions_rounded,
                            TextSystemExportFormat.typst => Icons.article_outlined,
                            TextSystemExportFormat.html => Icons.web_rounded,
                          },
                        ),
                        title: Text(format.label),
                        subtitle: Text(
                          format == TextSystemExportFormat.pdf
                              ? 'Save visual PDF to Downloads/Documents'
                              : 'Copy semantic ${format.fileExtension} text to clipboard',
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                tooltip: null,
                onPressed: _copyReport,
                icon: const Icon(Icons.copy_all_rounded),
              ),
              IconButton(
                tooltip: null,
                onPressed: () => unawaited(_executeWriterCommand(TextSystemWriterCommandId.save)),
                icon: const Icon(Icons.save_rounded),
              ),
              IconButton(
                tooltip: null,
                onPressed: _ownsTextController ? _resetDemo : null,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_showToolbar && !_focusMode)
                ValueListenableBuilder<int>(
                  valueListenable: _writerCommandRevision,
                  builder: (context, _, __) => _PremiumWriterMasterHeader(
                    activeTab: _activeRibbonTab,
                    onTabChanged: (tab) => setState(() => _activeRibbonTab = tab),
                    overviewExpanded: _overviewExpanded,
                    showInspector: _showInspector,
                    showSourceManager: _showSourceManager,
                    showObjectNavigator: _showObjectNavigator,
                    widePage: _widePage,
                    pageSetup: _pageSetup,
                    pageMode: _pageMode,
                    pageZoom: _pageZoom,
                    citationSettings: TextSystemCitationSettings.fromDocument(document),
                    showMarginGuides: _showMarginGuides,
                    showDetailedPageBreakLabels: _showDetailedPageBreakLabels,
                    showMarginMarkers: _showMarginMarkers,
                    showMarginAnnotations: _showMarginAnnotations,
                    showInPageToolbar: _showInPageToolbar,
                    writerCommands: _writerCommands,
                    pagedBlockCommands: _pagedBlockCommands,
                    ownedEditorCommands: _ownedEditorCommands,
                    onExecuteCommand: _executeWriterCommand,
                    onApplyBlockStyle: _applyBlockStyleFromHeader,
                    onToggleOverview: () => setState(() => _overviewExpanded = !_overviewExpanded),
                    onToggleInspector: () => setState(() => _showInspector = !_showInspector),
                    onToggleSourceManager: () => setState(() => _showSourceManager = !_showSourceManager),
                    onToggleObjectNavigator: () => setState(() => _showObjectNavigator = !_showObjectNavigator),
                    onToggleWidePage: () => setState(() => _widePage = !_widePage),
                    onToggleMarginGuides: () => setState(() => _showMarginGuides = !_showMarginGuides),
                    onTogglePageBreakLabels: () => setState(() => _showDetailedPageBreakLabels = !_showDetailedPageBreakLabels),
                    onToggleMarginMarkers: () => setState(() => _showMarginMarkers = !_showMarginMarkers),
                    onToggleMarginAnnotations: () => setState(() => _showMarginAnnotations = !_showMarginAnnotations),
                    onToggleInPageToolbar: () => setState(() => _showInPageToolbar = !_showInPageToolbar),
                    onPageZoomChanged: _setPageZoom,
                    onZoomIn: _zoomIn,
                    onZoomOut: _zoomOut,
                    onCitationSettingsChanged: _applyCitationSettings,
                    onPageModeChanged: (mode) => setState(() => _pageMode = mode),
                    onPageSetupChanged: (setup) => setState(() {
                      _pageSetup = setup;
                      final maxPages = setup.constraint.maxPages;
                      if (maxPages != null && maxPages > 0) {
                        _targetPageCount = maxPages.toDouble();
                      }
                    }),
                    onHideHeader: () => setState(() => _showToolbar = false),
                  ),
                )
              else if (!_focusMode)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showToolbar = true),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Show writer controls'),
                    ),
                  ),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showPanels && _overviewExpanded)
                      SizedBox(
                        width: 300,
                        child: _PremiumDocumentMapDrawer(
                          items: outlineItems,
                          wordCount: wordCount,
                          characterCount: document.plainText.length,
                          sectionMetrics: sectionMetrics,
                          onItemSelected: _jumpToHeading,
                        ),
                      ),
                    Expanded(
                      child: switch (_pageMode) {
                        _PremiumWriterPageMode.pageless => _PagelessPremiumWriterCanvas(
                            focusMode: _focusMode,
                            widePage: _widePage,
                            child: _buildDocumentSurface(
                              padding: const EdgeInsets.fromLTRB(28, 30, 28, 34),
                              minLines: _widePage ? 46 : 42,
                              textStyle: editorBodyStyle,
                            ),
                          ),
                        _PremiumWriterPageMode.pagedBlocksExperimental => TextSystemCurrentPagedEditorSurface(
                            textController: _textController,
                            document: document,
                            pageSetup: _pageSetup,
                            pageFurniture: _pageFurniture,
                            onPageFurnitureChanged: (value) => setState(() => _pageFurniture = value),
                            pageMaxWidth: pageMaxWidth,
                            pageZoom: _pageZoom,
                            onPageZoomChanged: _setPageZoom,
                            focusMode: _focusMode,
                            showMarginGuides: _showMarginGuides,
                            showMarginMarkers: _showMarginMarkers,
                            showMarginAnnotations: _showMarginAnnotations,
                            showSurfaceToolbar: _showInPageToolbar,
                            scrollController: _pageScrollController,
                            commandController: _pagedBlockCommands,
                            referenceActionRepository: _referenceActionRepository,
                            embeddedTodoRepository: _embeddedTodoRepository,
                            onOpenReferenceTarget: _openReferenceTarget,
                          ),
                        _PremiumWriterPageMode.ownedDocumentPreview => TextSystemOwnedDocumentEditorSurface(
                            textController: _textController,
                            document: document,
                            pageSetup: _pageSetup,
                            pageFurniture: _pageFurniture,
                            pageMaxWidth: pageMaxWidth,
                            pageZoom: _pageZoom,
                            focusMode: _focusMode,
                            showMarginGuides: _showMarginGuides,
                            scrollController: _pageScrollController,
                            commandController: _ownedEditorCommands,
                            referenceActionRepository: _referenceActionRepository,
                            onOpenReferenceTarget: _openReferenceTarget,
                          ),
                        _ => TextSystemPageCanvas(
                            pageMaxWidth: pageMaxWidth,
                            focusMode: _focusMode,
                            pageSetup: _pageSetup,
                            showMarginGuides: _showMarginGuides,
                            showPageChrome: true,
                            showPageBreakMarkers: _pageMode == _PremiumWriterPageMode.hybrid,
                            showDetailedPageBreakLabels: _showDetailedPageBreakLabels,
                            pageLabel: _pageViewport?.currentPageLabel ?? 'Page 1 of ~${pageMap.pageCount}',
                            footerLabel: _pageViewport?.mountedRangeLabel ?? pageEstimate.statusLabel,
                            pageLayout: pageLayout,
                            pageMap: pageMap,
                            scrollController: _pageScrollController,
                            onViewportChanged: _handlePageViewportChanged,
                            child: _buildDocumentSurface(
                              padding: editorPagePadding,
                              minLines: _widePage ? 46 : 42,
                              textStyle: editorBodyStyle,
                            ),
                          ),
                      },
                    ),
                    if (showPanels && _showObjectNavigator)
                      SizedBox(
                        width: 320,
                        child: _AcademicObjectNavigatorPanel(
                          items: _academicObjectItems(document, documentStructure),
                          onNavigateToBlock: (blockId) {
                            _navigateToBlock(blockId);
                          },
                          onClose: () => setState(() => _showObjectNavigator = false),
                        ),
                      ),
                    if (showPanels && _showInspector)
                      SizedBox(
                        width: 300,
                        child: _PremiumInspectorPanel(
                          document: document,
                          textController: _textController,
                          autosaveController: _autosaveController,
                          wordCount: wordCount,
                          outlineItems: outlineItems.length,
                          pageSetup: _pageSetup,
                          pageFurniture: _pageFurniture,
                          onPageFurnitureChanged: (value) => setState(() => _pageFurniture = value),
                          pageEstimate: pageEstimate,
                          pageLayout: pageLayout,
                          pageMap: pageMap,
                          sectionMetrics: sectionMetrics,
                          workPlan: workPlan,
                          unifiedLayoutTree: unifiedLayoutTree,
                          documentStructure: documentStructure,
                          referenceIndex: referenceIndex,
                          pageMode: _pageMode,
                          showDetailedPageBreakLabels: _showDetailedPageBreakLabels,
                          targetPageCount: _targetPageCount,
                          planningHorizonDays: _planningHorizonDays,
                          onTargetPageCountChanged: (value) => setState(() => _targetPageCount = value.clamp(1, 200).toDouble()),
                          onPlanningHorizonDaysChanged: (value) => setState(() => _planningHorizonDays = value.clamp(1, 30).toInt()),
                          onNavigateToBlock: (blockId) {
                            _navigateToBlock(blockId);
                          },
                          onNavigateToPage: (pageNumber) {
                            _navigateToPage(pageNumber);
                          },
                          pageViewport: _pageViewport,
                        ),
                      ),
                    if (showPanels && _showSourceManager)
                      SizedBox(
                        width: 340,
                        child: _CitationSourceManagerPanel(
                          document: document,
                          referenceIndex: referenceIndex,
                          citationSettings: TextSystemCitationSettings.fromDocument(document),
                          onNavigateToBlock: (blockId) {
                            _navigateToBlock(blockId);
                          },
                          onEditCitationSource: _editCitationSourceMetadata,
                          onOpenCitationSource: _openCitationSourceFromManager,
                          onShowCitationOccurrences: _showCitationOccurrences,
                          onOpenLinkedReference: _openLinkedReferenceFromManager,
                          onShowLinkedReferenceOccurrences: _showLinkedReferenceOccurrences,
                          onRepairCitations: _repairCitationTargets,
                          onDeduplicateSources: _deduplicateCitationSources,
                          onClose: () => setState(() => _showSourceManager = false),
                        ),
                      ),
                  ],
                ),
              ),
              if (!_focusMode)
                _PremiumWriterStatusBar(
                  saveState: _autosaveController.saveState,
                  revision: _textController.revision,
                  transactionCount: _textController.transactionLog.length,
                  wordCount: wordCount,
                  characterCount: document.plainText.length,
                  outlineCount: outlineItems.length,
                  pageSetup: _pageSetup,
                  pageFurniture: _pageFurniture,
                  pageEstimate: pageEstimate,
                  pageLayout: pageLayout,
                  pageMap: pageMap,
                  sectionMetrics: sectionMetrics,
                  workPlan: workPlan,
                  documentStructure: documentStructure,
                  pageMode: _pageMode,
                  pageViewport: _pageViewport,
                )
            ],
          ),
        );
      },
    );
  }
}

class _PremiumWriterMasterHeader extends StatelessWidget {
  const _PremiumWriterMasterHeader({
    required this.activeTab,
    required this.onTabChanged,
    required this.overviewExpanded,
    required this.showInspector,
    required this.showSourceManager,
    required this.showObjectNavigator,
    required this.widePage,
    required this.pageSetup,
    required this.pageMode,
    required this.pageZoom,
    required this.citationSettings,
    required this.showMarginGuides,
    required this.showDetailedPageBreakLabels,
    required this.showMarginMarkers,
    required this.showMarginAnnotations,
    required this.showInPageToolbar,
    required this.onToggleOverview,
    required this.onToggleInspector,
    required this.onToggleSourceManager,
    required this.onToggleObjectNavigator,
    required this.onToggleWidePage,
    required this.onToggleMarginGuides,
    required this.onTogglePageBreakLabels,
    required this.onToggleMarginMarkers,
    required this.onToggleMarginAnnotations,
    required this.onToggleInPageToolbar,
    required this.onPageZoomChanged,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCitationSettingsChanged,
    required this.onPageModeChanged,
    required this.onPageSetupChanged,
    required this.onHideHeader,
    required this.writerCommands,
    required this.pagedBlockCommands,
    required this.ownedEditorCommands,
    required this.onExecuteCommand,
    required this.onApplyBlockStyle,
  });

  final _PremiumWriterRibbonTab activeTab;
  final ValueChanged<_PremiumWriterRibbonTab> onTabChanged;
  final bool overviewExpanded;
  final bool showInspector;
  final bool showSourceManager;
  final bool showObjectNavigator;
  final bool widePage;
  final TextSystemPageSetup pageSetup;
  final _PremiumWriterPageMode pageMode;
  final double pageZoom;
  final TextSystemCitationSettings citationSettings;
  final bool showMarginGuides;
  final bool showDetailedPageBreakLabels;
  final bool showMarginMarkers;
  final bool showMarginAnnotations;
  final bool showInPageToolbar;
  final VoidCallback onToggleOverview;
  final VoidCallback onToggleInspector;
  final VoidCallback onToggleSourceManager;
  final VoidCallback onToggleObjectNavigator;
  final VoidCallback onToggleWidePage;
  final VoidCallback onToggleMarginGuides;
  final VoidCallback onTogglePageBreakLabels;
  final VoidCallback onToggleMarginMarkers;
  final VoidCallback onToggleMarginAnnotations;
  final VoidCallback onToggleInPageToolbar;
  final ValueChanged<double> onPageZoomChanged;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final ValueChanged<TextSystemCitationSettings> onCitationSettingsChanged;
  final ValueChanged<_PremiumWriterPageMode> onPageModeChanged;
  final ValueChanged<TextSystemPageSetup> onPageSetupChanged;
  final VoidCallback onHideHeader;
  final TextSystemWriterCommandRegistry writerCommands;
  final TextSystemPagedBlockCommandController pagedBlockCommands;
  final TextSystemOwnedEditorCommandController ownedEditorCommands;
  final Future<void> Function(TextSystemWriterCommandId commandId) onExecuteCommand;
  final ValueChanged<String> onApplyBlockStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final tab in _PremiumWriterRibbonTab.values)
                              _RibbonTabButton(
                                tab: tab,
                                selected: tab == activeTab,
                                onPressed: () => onTabChanged(tab),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _HeaderQuickCommandStrip(
                      registry: writerCommands,
                      onExecuteCommand: onExecuteCommand,
                    ),
                    const SizedBox(width: 10),
                    _WriterModeBadge(pageMode: pageMode),
                    const SizedBox(width: 8),
                    _EditorSurfaceSettingsMenu(
                      pageMode: pageMode,
                      onPageModeChanged: onPageModeChanged,
                      overviewExpanded: overviewExpanded,
                      showInspector: showInspector,
                      showSourceManager: showSourceManager,
                      showObjectNavigator: showObjectNavigator,
                      widePage: widePage,
                      showMarginGuides: showMarginGuides,
                      showDetailedPageBreakLabels: showDetailedPageBreakLabels,
                      showMarginMarkers: showMarginMarkers,
                      showMarginAnnotations: showMarginAnnotations,
                      showInPageToolbar: showInPageToolbar,
                      onToggleOverview: onToggleOverview,
                      onToggleInspector: onToggleInspector,
                      onToggleSourceManager: onToggleSourceManager,
                      onToggleObjectNavigator: onToggleObjectNavigator,
                      onToggleWidePage: onToggleWidePage,
                      onToggleMarginGuides: onToggleMarginGuides,
                      onTogglePageBreakLabels: onTogglePageBreakLabels,
                      onToggleMarginMarkers: onToggleMarginMarkers,
                      onToggleMarginAnnotations: onToggleMarginAnnotations,
                      onToggleInPageToolbar: onToggleInPageToolbar,
                      onHideHeader: onHideHeader,
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
            SizedBox(
              height: 106,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                child: _RibbonTabContent(
                  key: ValueKey(activeTab),
                  activeTab: activeTab,
                  pageSetup: pageSetup,
                  pageZoom: pageZoom,
                  citationSettings: citationSettings,
                  onCitationSettingsChanged: onCitationSettingsChanged,
                  onPageSetupChanged: onPageSetupChanged,
                  onPageZoomChanged: onPageZoomChanged,
                  onZoomIn: onZoomIn,
                  onZoomOut: onZoomOut,
                  overviewExpanded: overviewExpanded,
                  showInspector: showInspector,
                  showObjectNavigator: showObjectNavigator,
                  widePage: widePage,
                  showMarginGuides: showMarginGuides,
                  showDetailedPageBreakLabels: showDetailedPageBreakLabels,
                  onToggleOverview: onToggleOverview,
                  onToggleInspector: onToggleInspector,
                  onToggleObjectNavigator: onToggleObjectNavigator,
                  onToggleWidePage: onToggleWidePage,
                  onToggleMarginGuides: onToggleMarginGuides,
                  onTogglePageBreakLabels: onTogglePageBreakLabels,
                  writerCommands: writerCommands,
                  pagedBlockCommands: pagedBlockCommands,
                  ownedEditorCommands: ownedEditorCommands,
                  onExecuteCommand: onExecuteCommand,
                  onApplyBlockStyle: onApplyBlockStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RibbonTabContent extends StatelessWidget {
  const _RibbonTabContent({
    super.key,
    required this.activeTab,
    required this.pageSetup,
    required this.pageZoom,
    required this.citationSettings,
    required this.onCitationSettingsChanged,
    required this.onPageSetupChanged,
    required this.onPageZoomChanged,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.overviewExpanded,
    required this.showInspector,
    required this.showObjectNavigator,
    required this.widePage,
    required this.showMarginGuides,
    required this.showDetailedPageBreakLabels,
    required this.onToggleOverview,
    required this.onToggleInspector,
    required this.onToggleObjectNavigator,
    required this.onToggleWidePage,
    required this.onToggleMarginGuides,
    required this.onTogglePageBreakLabels,
    required this.writerCommands,
    required this.pagedBlockCommands,
    required this.ownedEditorCommands,
    required this.onExecuteCommand,
    required this.onApplyBlockStyle,
  });

  final _PremiumWriterRibbonTab activeTab;
  final TextSystemPageSetup pageSetup;
  final double pageZoom;
  final TextSystemCitationSettings citationSettings;
  final ValueChanged<TextSystemCitationSettings> onCitationSettingsChanged;
  final ValueChanged<TextSystemPageSetup> onPageSetupChanged;
  final ValueChanged<double> onPageZoomChanged;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool overviewExpanded;
  final bool showInspector;
  final bool showObjectNavigator;
  final bool widePage;
  final bool showMarginGuides;
  final bool showDetailedPageBreakLabels;
  final VoidCallback onToggleOverview;
  final VoidCallback onToggleInspector;
  final VoidCallback onToggleObjectNavigator;
  final VoidCallback onToggleWidePage;
  final VoidCallback onToggleMarginGuides;
  final VoidCallback onTogglePageBreakLabels;
  final TextSystemWriterCommandRegistry writerCommands;
  final TextSystemPagedBlockCommandController pagedBlockCommands;
  final TextSystemOwnedEditorCommandController ownedEditorCommands;
  final Future<void> Function(TextSystemWriterCommandId commandId) onExecuteCommand;
  final ValueChanged<String> onApplyBlockStyle;

  @override
  Widget build(BuildContext context) {
    final groups = switch (activeTab) {
      _PremiumWriterRibbonTab.home => _homeGroups(context),
      _PremiumWriterRibbonTab.insert => _insertGroups(context),
      _PremiumWriterRibbonTab.references => _referenceGroups(context),
      _PremiumWriterRibbonTab.layout => [
          ..._contextualLayoutGroups(context),
          ..._layoutGroups(context),
        ],
      _PremiumWriterRibbonTab.review => _reviewGroups(context),
      _PremiumWriterRibbonTab.view => _viewGroups(context),
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const _RibbonGroupDivider(),
              groups[i],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _homeGroups(BuildContext context) {
    return [
      _RibbonGroup(
        label: 'Document',
        children: [
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.save,
            icon: Icons.save_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.toggleFocusMode,
            icon: Icons.center_focus_strong_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
        ],
      ),
      _RibbonGroup(
        label: 'Clipboard',
        children: [
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.undo,
            icon: Icons.undo_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.redo,
            icon: Icons.redo_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.copy,
            icon: Icons.content_copy_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.cut,
            icon: Icons.content_cut_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.paste,
            icon: Icons.content_paste_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
        ],
      ),
      _RibbonGroup(
        label: 'Text',
        children: [
          _RibbonStyleMenuCommand(onApplyStyle: onApplyBlockStyle),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.bold, icon: Icons.format_bold_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.italic, icon: Icons.format_italic_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.underline, icon: Icons.format_underlined_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.inlineCode, icon: Icons.code_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.highlight, icon: Icons.border_color_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
      _RibbonGroup(
        label: 'Paragraph',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.bulletList, icon: Icons.format_list_bulleted_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.numberedList, icon: Icons.format_list_numbered_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.documentTodo, icon: Icons.check_box_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.align, icon: Icons.format_align_left_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
    ];
  }

  List<Widget> _insertGroups(BuildContext context) {
    return [
      _RibbonGroup(
        label: 'Pages',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.pageBreak, icon: Icons.post_add_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.sectionBreak, icon: Icons.vertical_split_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
      _RibbonGroup(
        label: 'Academic objects',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.footnote, icon: Icons.sticky_note_2_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.appTodo, icon: Icons.task_alt_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.table, icon: Icons.table_chart_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.figure, icon: Icons.image_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.equation, icon: Icons.functions_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.inlineMath, icon: Icons.calculate_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.crossReference, icon: Icons.tag_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
    ];
  }

  List<Widget> _referenceGroups(BuildContext context) {
    return [
      _RibbonGroup(
        label: 'Citations',
        children: [
          _MasterCitationSettingsMenu(
            settings: citationSettings,
            onChanged: onCitationSettingsChanged,
          ),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.addCitation, icon: Icons.format_quote_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.sourceManager, icon: Icons.library_books_outlined, onExecuteCommand: onExecuteCommand),
        ],
      ),
      _RibbonGroup(
        label: 'Links',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.linkSource, icon: Icons.source_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.linkDocument, icon: Icons.article_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.linkProject, icon: Icons.account_tree_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.linkTodo, icon: Icons.task_alt_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.externalLink, icon: Icons.link_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
    ];
  }

  List<Widget> _contextualLayoutGroups(BuildContext context) {
    if (pagedBlockCommands.hasActiveTableContext) {
      return [
        _RibbonGroup(
          label: 'Table layout',
          children: [
            _RibbonDirectCommand(
              icon: Icons.vertical_align_top_rounded,
              label: 'Row above',
              onPressed: pagedBlockCommands.tableInsertRowAbove,
            ),
            _RibbonDirectCommand(
              icon: Icons.vertical_align_bottom_rounded,
              label: 'Row below',
              onPressed: pagedBlockCommands.tableInsertRowBelow,
            ),
            _RibbonDirectCommand(
              icon: Icons.align_horizontal_left_rounded,
              label: 'Col left',
              onPressed: pagedBlockCommands.tableInsertColumnLeft,
            ),
            _RibbonDirectCommand(
              icon: Icons.align_horizontal_right_rounded,
              label: 'Col right',
              onPressed: pagedBlockCommands.tableInsertColumnRight,
            ),
            _RibbonDirectCommand(
              icon: Icons.table_rows_outlined,
              label: 'Del row',
              enabled: pagedBlockCommands.canDeleteSelectedTableRow,
              onPressed: pagedBlockCommands.tableDeleteRow,
            ),
            _RibbonDirectCommand(
              icon: Icons.view_column_outlined,
              label: 'Del col',
              enabled: pagedBlockCommands.canDeleteSelectedTableColumn,
              onPressed: pagedBlockCommands.tableDeleteColumn,
            ),
            _RibbonDirectCommand(
              icon: Icons.table_chart_outlined,
              label: 'Headers ${pagedBlockCommands.tableHeaderRows}',
              onPressed: pagedBlockCommands.tableCycleHeaderRows,
            ),
            _RibbonDirectCommand(
              icon: Icons.content_paste_go_outlined,
              label: 'Paste',
              onPressed: pagedBlockCommands.tablePaste,
            ),
            _RibbonDirectCommand(
              icon: Icons.tune_rounded,
              label: 'Props',
              onPressed: pagedBlockCommands.tableProperties,
            ),
            _RibbonDirectCommand(
              icon: Icons.check_rounded,
              label: 'Done',
              onPressed: pagedBlockCommands.tableDone,
            ),
          ],
        ),
      ];
    }

    if (ownedEditorCommands.hasSelectedObject) {
      final objectKind = ownedEditorCommands.selectedObjectKind;
      final objectLabel = objectKind.isEmpty
          ? 'Object'
          : '${objectKind[0].toUpperCase()}${objectKind.substring(1)}';
      return [
        _RibbonGroup(
          label: '$objectLabel layout',
          children: [
            _RibbonDirectCommand(
              icon: Icons.copy_all_rounded,
              label: 'Copy',
              onPressed: () => unawaited(ownedEditorCommands.copySelection()),
            ),
            _RibbonDirectCommand(
              icon: Icons.copy_rounded,
              label: 'Duplicate',
              enabled: ownedEditorCommands.canDuplicateSelectedObject,
              onPressed: ownedEditorCommands.duplicateSelectedObject,
            ),
            _RibbonDirectCommand(
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'Move up',
              enabled: ownedEditorCommands.canMoveSelectedObjectUp,
              onPressed: ownedEditorCommands.moveSelectedObjectUp,
            ),
            _RibbonDirectCommand(
              icon: Icons.keyboard_arrow_down_rounded,
              label: 'Move down',
              enabled: ownedEditorCommands.canMoveSelectedObjectDown,
              onPressed: ownedEditorCommands.moveSelectedObjectDown,
            ),
            _RibbonDirectCommand(
              icon: Icons.tag_rounded,
              label: 'Copy ref',
              enabled: ownedEditorCommands.canCopySelectedObjectReference,
              onPressed: () => unawaited(ownedEditorCommands.copySelectedObjectReference()),
            ),
            _RibbonDirectCommand(
              icon: Icons.add_comment_outlined,
              label: 'Comment',
              enabled: ownedEditorCommands.canCommentOnSelectedObject,
              onPressed: () => unawaited(ownedEditorCommands.addCommentToSelectedObject()),
            ),
            _RibbonDirectCommand(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              enabled: ownedEditorCommands.canDeleteSelectedObject,
              onPressed: ownedEditorCommands.deleteSelectedObject,
            ),
          ],
        ),
      ];
    }

    if (pagedBlockCommands.hasSelectedObject) {
      final objectLabel = pagedBlockCommands.selectedObjectKind.isEmpty
          ? 'Object'
          : '${pagedBlockCommands.selectedObjectKind[0].toUpperCase()}${pagedBlockCommands.selectedObjectKind.substring(1)}';
      return [
        _RibbonGroup(
          label: '$objectLabel layout',
          children: [
            _RibbonDirectCommand(
              icon: Icons.copy_rounded,
              label: 'Duplicate',
              onPressed: pagedBlockCommands.duplicateSelectedObject,
            ),
            _RibbonDirectCommand(
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'Move up',
              onPressed: pagedBlockCommands.moveSelectedObjectUp,
            ),
            _RibbonDirectCommand(
              icon: Icons.keyboard_arrow_down_rounded,
              label: 'Move down',
              onPressed: pagedBlockCommands.moveSelectedObjectDown,
            ),
            _RibbonDirectCommand(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              onPressed: pagedBlockCommands.deleteSelectedObject,
            ),
          ],
        ),
      ];
    }

    return const <Widget>[];
  }

  List<Widget> _layoutGroups(BuildContext context) {
    return [
      _RibbonGroup(
        label: 'Page setup',
        children: [
          _MasterPageSetupMenu(
            pageSetup: pageSetup,
            onChanged: onPageSetupChanged,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.toggleWidePage,
            icon: Icons.view_week_outlined,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.toggleMarginGuides,
            icon: Icons.border_outer_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
        ],
      ),
      _RibbonGroup(
        label: 'Page furniture',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.headerFooter, icon: Icons.web_asset_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.pageNumbers, icon: Icons.pin_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
    ];
  }

  List<Widget> _reviewGroups(BuildContext context) {
    return [
      _RibbonGroup(
        label: 'Review',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.comment, icon: Icons.comment_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.checkReferences, icon: Icons.rule_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.documentTodos, icon: Icons.add_task_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
      _RibbonGroup(
        label: 'Progress',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.stats, icon: Icons.analytics_outlined, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.versionHistory, icon: Icons.history_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
    ];
  }

  List<Widget> _viewGroups(BuildContext context) {
    return [
      _RibbonGroup(
        label: 'Panels',
        children: [
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.toggleDocumentMap,
            icon: Icons.account_tree_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.toggleInspector,
            icon: Icons.analytics_outlined,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.objectNavigator,
            icon: Icons.view_list_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.togglePageBreakLabels,
            icon: Icons.label_outline_rounded,
            onExecuteCommand: onExecuteCommand,
          ),
          _RibbonWriterCommand(
            registry: writerCommands,
            commandId: TextSystemWriterCommandId.toggleMarginMarkers,
            icon: Icons.comment_bank_outlined,
            onExecuteCommand: onExecuteCommand,
          ),
        ],
      ),
      _RibbonGroup(
        label: 'Zoom',
        children: [
          _RibbonZoomControls(
            zoom: pageZoom,
            onZoomChanged: onPageZoomChanged,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
          ),
        ],
      ),
      _RibbonGroup(
        label: 'Focus',
        children: [
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.toggleFocusMode, icon: Icons.center_focus_strong_rounded, onExecuteCommand: onExecuteCommand),
          _RibbonWriterCommand(registry: writerCommands, commandId: TextSystemWriterCommandId.splitView, icon: Icons.splitscreen_rounded, onExecuteCommand: onExecuteCommand),
        ],
      ),
    ];
  }
}


class _HeaderQuickCommandStrip extends StatelessWidget {
  const _HeaderQuickCommandStrip({
    required this.registry,
    required this.onExecuteCommand,
  });

  final TextSystemWriterCommandRegistry registry;
  final Future<void> Function(TextSystemWriterCommandId commandId) onExecuteCommand;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55)),
          right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderQuickCommandButton(
              registry: registry,
              commandId: TextSystemWriterCommandId.save,
              icon: Icons.save_rounded,
              onExecuteCommand: onExecuteCommand,
            ),
            _HeaderQuickCommandButton(
              registry: registry,
              commandId: TextSystemWriterCommandId.toggleFocusMode,
              icon: Icons.center_focus_strong_rounded,
              onExecuteCommand: onExecuteCommand,
            ),
            _HeaderQuickCommandButton(
              registry: registry,
              commandId: TextSystemWriterCommandId.toggleDocumentMap,
              icon: Icons.account_tree_rounded,
              onExecuteCommand: onExecuteCommand,
            ),
            _HeaderQuickCommandButton(
              registry: registry,
              commandId: TextSystemWriterCommandId.toggleInspector,
              icon: Icons.analytics_outlined,
              onExecuteCommand: onExecuteCommand,
            ),
            _HeaderQuickCommandButton(
              registry: registry,
              commandId: TextSystemWriterCommandId.objectNavigator,
              icon: Icons.view_list_rounded,
              onExecuteCommand: onExecuteCommand,
            ),
          ],
        ),
      ),
    );
  }
}


class _HeaderQuickCommandButton extends StatefulWidget {
  const _HeaderQuickCommandButton({
    required this.registry,
    required this.commandId,
    required this.icon,
    required this.onExecuteCommand,
  });

  final TextSystemWriterCommandRegistry registry;
  final TextSystemWriterCommandId commandId;
  final IconData icon;
  final Future<void> Function(TextSystemWriterCommandId commandId) onExecuteCommand;

  @override
  State<_HeaderQuickCommandButton> createState() => _HeaderQuickCommandButtonState();
}

class _HeaderQuickCommandButtonState extends State<_HeaderQuickCommandButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = widget.registry.state(widget.commandId);
    final enabled = state.enabled;
    final foreground = enabled
        ? (state.selected ? colorScheme.primary : colorScheme.onSurfaceVariant)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    final background = !enabled
        ? Colors.transparent
        : state.selected
            ? colorScheme.primaryContainer.withValues(alpha: _pressed ? 0.78 : 0.58)
            : _pressed
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.95)
                : _hovered
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.72)
                    : Colors.transparent;
    final borderColor = !enabled
        ? Colors.transparent
        : state.selected
            ? colorScheme.primary.withValues(alpha: 0.38)
            : _hovered
                ? colorScheme.outlineVariant.withValues(alpha: 0.92)
                : Colors.transparent;

    return MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _setPressed(false);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => unawaited(widget.onExecuteCommand(widget.commandId)) : null,
            onTapDown: enabled ? (_) => _setPressed(true) : null,
            onTapUp: enabled ? (_) => _setPressed(false) : null,
            onTapCancel: enabled ? () => _setPressed(false) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 95),
              curve: Curves.easeOutCubic,
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: borderColor),
              ),
              child: Transform.scale(
                scale: _pressed ? 0.94 : 1.0,
                child: Icon(widget.icon, size: 16, color: foreground),
              ),
            ),
          ),
        ),
      );
  }
}

class _WriterModeBadge extends StatelessWidget {
  const _WriterModeBadge({required this.pageMode});

  final _PremiumWriterPageMode pageMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 15, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            pageMode.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}


class _RibbonTabButton extends StatefulWidget {
  const _RibbonTabButton({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final _PremiumWriterRibbonTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_RibbonTabButton> createState() => _RibbonTabButtonState();
}

class _RibbonTabButtonState extends State<_RibbonTabButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = widget.selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final background = widget.selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.24)
        : _pressed
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.92)
            : _hovered
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.62)
                : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            border: Border(
              left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: _hovered ? 0.38 : 0.0)),
              right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: _hovered ? 0.38 : 0.0)),
            ),
          ),
          child: Transform.scale(
            scale: _pressed ? 0.985 : 1.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.tab.icon, size: 15, color: foreground),
                    const SizedBox(width: 6),
                    Text(
                      widget.tab.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: widget.selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 2,
                  width: widget.selected ? 34 : (_hovered ? 18 : 0),
                  color: widget.selected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonGroupDivider extends StatelessWidget {
  const _RibbonGroupDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.75),
      ),
    );
  }
}

class _RibbonGroup extends StatelessWidget {
  const _RibbonGroup({
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      height: 86,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 60,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  children[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 15,
            child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
              fontSize: 10.5,
              height: 1.0,
            ),
          ),
          ),
        ],
      ),
    );
  }
}

class _RibbonInfoGroup extends StatelessWidget {
  const _RibbonInfoGroup({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, minHeight: 86),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.85), width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}



class _RibbonStyleMenuCommand extends StatelessWidget {
  const _RibbonStyleMenuCommand({required this.onApplyStyle});

  final ValueChanged<String> onApplyStyle;

  static const List<_RibbonStyleChoice> _choices = [
    _RibbonStyleChoice('Paragraph', TextSystemDocumentStyleSheet.paragraph, Icons.notes_rounded),
    _RibbonStyleChoice('Heading 1', TextSystemDocumentStyleSheet.heading1, Icons.title_rounded),
    _RibbonStyleChoice('Heading 2', TextSystemDocumentStyleSheet.heading2, Icons.format_size_rounded),
    _RibbonStyleChoice('Heading 3', TextSystemDocumentStyleSheet.heading3, Icons.text_fields_rounded),
    _RibbonStyleChoice('Quote', TextSystemDocumentStyleSheet.quote, Icons.format_quote_rounded),
    _RibbonStyleChoice('Code block', TextSystemDocumentStyleSheet.code, Icons.code_rounded),
    _RibbonStyleChoice('Bullets', TextSystemDocumentStyleSheet.listParagraph, Icons.format_list_bulleted_rounded),
    _RibbonStyleChoice('Numbered', TextSystemDocumentStyleSheet.numberedList, Icons.format_list_numbered_rounded),
    _RibbonStyleChoice('Todo', TextSystemDocumentStyleSheet.todo, Icons.check_box_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: null,
      onSelected: onApplyStyle,
      itemBuilder: (context) => [
        for (final choice in _choices)
          PopupMenuItem<String>(
            value: choice.styleId,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(choice.icon, size: 17),
                const SizedBox(width: 10),
                Text(choice.label),
              ],
            ),
          ),
      ],
      child: IgnorePointer(
        child: _RibbonCommandSurface(
          enabled: true,
          icon: Icons.format_size_rounded,
          label: 'Style',
          onPressed: null,
        ),
      ),
    );
  }
}

class _RibbonStyleChoice {
  const _RibbonStyleChoice(this.label, this.styleId, this.icon);

  final String label;
  final String styleId;
  final IconData icon;
}

class _RibbonDirectCommand extends StatelessWidget {
  const _RibbonDirectCommand({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _RibbonCommandSurface(
      enabled: enabled,
      icon: icon,
      label: label,
      tooltip: enabled ? null : '$label is not available for the current selection.',
      onPressed: enabled ? onPressed : null,
    );
  }
}

class _RibbonWriterCommand extends StatelessWidget {
  const _RibbonWriterCommand({
    required this.registry,
    required this.commandId,
    required this.icon,
    required this.onExecuteCommand,
  });

  final TextSystemWriterCommandRegistry registry;
  final TextSystemWriterCommandId commandId;
  final IconData icon;
  final Future<void> Function(TextSystemWriterCommandId commandId) onExecuteCommand;

  @override
  Widget build(BuildContext context) {
    final state = registry.state(commandId);
    final label = registry.label(commandId);
    final description = registry.description(commandId);
    return _RibbonCommandSurface(
      enabled: state.enabled,
      selected: state.selected,
      icon: icon,
      label: label,
      tooltip: state.enabled ? null : (state.disabledReason ?? description),
      onPressed: state.enabled
          ? () {
              unawaited(onExecuteCommand(commandId));
            }
          : null,
    );
  }
}

class _RibbonStaticCommand extends StatelessWidget {
  const _RibbonStaticCommand({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _RibbonCommandSurface(
      enabled: false,
      icon: icon,
      label: label,
      onPressed: null,
    );
  }
}

class _RibbonToggleCommand extends StatelessWidget {
  const _RibbonToggleCommand({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _RibbonCommandSurface(
      enabled: true,
      selected: selected,
      icon: icon,
      label: label,
      onPressed: onPressed,
    );
  }
}



class _RibbonZoomControls extends StatelessWidget {
  const _RibbonZoomControls({
    required this.zoom,
    required this.onZoomChanged,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  String get _label => '${(zoom * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: colorScheme.onSurface,
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom out',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
            onPressed: zoom <= 0.76 ? null : onZoomOut,
            icon: const Icon(Icons.remove_rounded),
          ),
          Tooltip(
            message: 'Drag to set page zoom',
            child: SizedBox(
              width: 120,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: zoom.clamp(0.75, 1.75).toDouble(),
                  min: 0.75,
                  max: 1.75,
                  divisions: 100,
                  label: _label,
                  onChanged: onZoomChanged,
                ),
              ),
            ),
          ),
          PopupMenuButton<double>(
            tooltip: 'Page zoom presets',
            onSelected: onZoomChanged,
            itemBuilder: (context) => const <PopupMenuEntry<double>>[
              PopupMenuItem<double>(value: 0.90, child: Text('90%')),
              PopupMenuItem<double>(value: 1.00, child: Text('100%')),
              PopupMenuItem<double>(value: 1.10, child: Text('110%')),
              PopupMenuItem<double>(value: 1.15, child: Text('115%')),
              PopupMenuItem<double>(value: 1.25, child: Text('125%')),
              PopupMenuItem<double>(value: 1.50, child: Text('150%')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_label, style: textStyle),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Zoom in',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            padding: EdgeInsets.zero,
            onPressed: zoom >= 1.74 ? null : onZoomIn,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _RibbonCommandSurface extends StatefulWidget {
  const _RibbonCommandSurface({
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.tooltip,
  });

  final bool enabled;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  State<_RibbonCommandSurface> createState() => _RibbonCommandSurfaceState();
}

class _RibbonCommandSurfaceState extends State<_RibbonCommandSurface> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInteractive = widget.enabled;
    final canInvokeDirectly = widget.enabled && widget.onPressed != null;
    final foreground = widget.enabled
        ? (widget.selected ? colorScheme.primary : colorScheme.onSurface)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.48);
    final background = !widget.enabled
        ? Colors.transparent
        : widget.selected
            ? colorScheme.primaryContainer.withValues(alpha: _pressed ? 0.82 : 0.60)
            : _pressed
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.96)
                : _hovered
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.70)
                    : Colors.transparent;
    final borderColor = !widget.enabled
        ? Colors.transparent
        : widget.selected
            ? colorScheme.primary.withValues(alpha: 0.42)
            : _hovered
                ? colorScheme.outlineVariant.withValues(alpha: 0.95)
                : Colors.transparent;
    final shadowColor = _pressed || _hovered
        ? colorScheme.shadow.withValues(alpha: _pressed ? 0.10 : 0.06)
        : Colors.transparent;

    final tooltipMessage = widget.tooltip ??
        (widget.enabled ? null : '${widget.label} is not available in this header yet.');
    final commandChild = MouseRegion(
        cursor: isInteractive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _setPressed(false);
        },
        child: Semantics(
          button: true,
          enabled: widget.enabled,
          selected: widget.selected,
          label: widget.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canInvokeDirectly ? widget.onPressed : null,
            onTapDown: canInvokeDirectly ? (_) => _setPressed(true) : null,
            onTapUp: canInvokeDirectly ? (_) => _setPressed(false) : null,
            onTapCancel: canInvokeDirectly ? () => _setPressed(false) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 105),
              curve: Curves.easeOutCubic,
              width: 64,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
                boxShadow: [
                  if (shadowColor != Colors.transparent)
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Transform.translate(
                offset: Offset(0, _pressed ? 1 : 0),
                child: Transform.scale(
                  scale: _pressed ? 0.985 : 1.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 105),
                        curve: Curves.easeOutCubic,
                        scale: _hovered && widget.enabled ? 1.04 : 1.0,
                        child: Icon(widget.icon, size: 18, color: foreground),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 12,
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                            fontSize: 10.0,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

    return commandChild;
  }
}

class _RibbonMenuButton extends StatelessWidget {
  const _RibbonMenuButton({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _RibbonCommandSurface(
      enabled: true,
      icon: icon,
      label: label,
      onPressed: () {},
    );
  }
}

class _EditorSurfaceSettingsMenu extends StatelessWidget {
  const _EditorSurfaceSettingsMenu({
    required this.pageMode,
    required this.onPageModeChanged,
    required this.overviewExpanded,
    required this.showInspector,
    required this.showSourceManager,
    required this.showObjectNavigator,
    required this.widePage,
    required this.showMarginGuides,
    required this.showDetailedPageBreakLabels,
    required this.showMarginMarkers,
    required this.showMarginAnnotations,
    required this.showInPageToolbar,
    required this.onToggleOverview,
    required this.onToggleInspector,
    required this.onToggleSourceManager,
    required this.onToggleObjectNavigator,
    required this.onToggleWidePage,
    required this.onToggleMarginGuides,
    required this.onTogglePageBreakLabels,
    required this.onToggleMarginMarkers,
    required this.onToggleMarginAnnotations,
    required this.onToggleInPageToolbar,
    required this.onHideHeader,
  });

  final _PremiumWriterPageMode pageMode;
  final ValueChanged<_PremiumWriterPageMode> onPageModeChanged;
  final bool overviewExpanded;
  final bool showInspector;
  final bool showSourceManager;
  final bool showObjectNavigator;
  final bool widePage;
  final bool showMarginGuides;
  final bool showDetailedPageBreakLabels;
  final bool showMarginMarkers;
  final bool showMarginAnnotations;
  final bool showInPageToolbar;
  final VoidCallback onToggleOverview;
  final VoidCallback onToggleInspector;
  final VoidCallback onToggleSourceManager;
  final VoidCallback onToggleObjectNavigator;
  final VoidCallback onToggleWidePage;
  final VoidCallback onToggleMarginGuides;
  final VoidCallback onTogglePageBreakLabels;
  final VoidCallback onToggleMarginMarkers;
  final VoidCallback onToggleMarginAnnotations;
  final VoidCallback onToggleInPageToolbar;
  final VoidCallback onHideHeader;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: null,
      onSelected: (value) {
        if (value is _PremiumWriterPageMode) {
          onPageModeChanged(value);
          return;
        }
        switch (value) {
          case 'map':
            onToggleOverview();
            break;
          case 'inspector':
            onToggleInspector();
            break;
          case 'source-manager':
            onToggleSourceManager();
            break;
          case 'object-navigator':
            onToggleObjectNavigator();
            break;
          case 'wide':
            onToggleWidePage();
            break;
          case 'margins':
            onToggleMarginGuides();
            break;
          case 'break-labels':
            onTogglePageBreakLabels();
            break;
          case 'margin-markers':
            onToggleMarginMarkers();
            break;
          case 'margin-annotations':
            onToggleMarginAnnotations();
            break;
          case 'in-page-toolbar':
            onToggleInPageToolbar();
            break;
          case 'hide-header':
            onHideHeader();
            break;
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<Object>>[
        const PopupMenuItem<Object>(enabled: false, child: Text('Editor surface')),
        for (final mode in _PremiumWriterPageMode.displayOrder)
          CheckedPopupMenuItem<Object>(
            value: mode,
            checked: mode == pageMode,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(mode.label),
              subtitle: Text(mode.description),
            ),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: 'map',
          checked: overviewExpanded,
          child: const Text('Document map'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'inspector',
          checked: showInspector,
          child: const Text('Inspector'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'source-manager',
          checked: showSourceManager,
          child: const Text('Source manager'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'object-navigator',
          checked: showObjectNavigator,
          child: const Text('Object navigator'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'wide',
          checked: widePage,
          child: const Text('Wide page'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'margins',
          checked: showMarginGuides,
          child: const Text('Margin guides'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'break-labels',
          checked: showDetailedPageBreakLabels,
          child: const Text('Detailed break labels'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'margin-markers',
          checked: showMarginMarkers,
          child: const Text('Passive source markers'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'margin-annotations',
          checked: showMarginAnnotations,
          child: const Text('Google Docs comment rail'),
        ),
        CheckedPopupMenuItem<Object>(
          value: 'in-page-toolbar',
          checked: showInPageToolbar,
          child: const Text('Legacy in-page toolbar'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'hide-header',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_off_rounded),
            title: Text('Hide master header'),
          ),
        ),
      ],
      child: Builder(
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              );
          return Container(
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.75))),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Settings', style: textStyle),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down_rounded, size: 17, color: colorScheme.onSurfaceVariant),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MasterCitationSettingsMenu extends StatelessWidget {
  const _MasterCitationSettingsMenu({
    required this.settings,
    required this.onChanged,
  });

  final TextSystemCitationSettings settings;
  final ValueChanged<TextSystemCitationSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: null,
      onSelected: (value) {
        if (value is TextSystemCitationStyle) {
          onChanged(settings.copyWith(style: value));
        } else if (value is TextSystemCitationInlineMode) {
          onChanged(settings.copyWith(inlineMode: value));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<Object>>[
        const PopupMenuItem<Object>(enabled: false, child: Text('Reference style')),
        for (final style in TextSystemCitationStyle.values)
          CheckedPopupMenuItem<Object>(
            value: style,
            checked: settings.style == style,
            child: Text(style.label),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(enabled: false, child: Text('Inline citation mode')),
        for (final mode in TextSystemCitationInlineMode.values)
          CheckedPopupMenuItem<Object>(
            value: mode,
            checked: settings.inlineMode == mode,
            child: Text(mode.label),
          ),
      ],
      child: const _RibbonCommandSurface(
        enabled: true,
        icon: Icons.menu_book_outlined,
        label: 'Style',
        onPressed: null,
      ),
    );
  }
}

class _MasterPageSetupMenu extends StatelessWidget {
  const _MasterPageSetupMenu({
    required this.pageSetup,
    required this.onChanged,
  });

  final TextSystemPageSetup pageSetup;
  final ValueChanged<TextSystemPageSetup> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: null,
      onSelected: (value) {
        if (value is TextSystemPagePreset) {
          onChanged(value.setup);
          return;
        }
        if (value is TextSystemPageTypography) {
          onChanged(pageSetup.copyWith(typography: value));
          return;
        }
        if (value == 'landscape') {
          onChanged(pageSetup.copyWith(orientation: TextSystemPageOrientation.landscape));
        } else if (value == 'portrait') {
          onChanged(pageSetup.copyWith(orientation: TextSystemPageOrientation.portrait));
        } else if (value == 'margin-academic') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.academic()));
        } else if (value == 'margin-compact') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.compact()));
        } else if (value == 'margin-roomy') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.roomy()));
        } else if (value == 'margin-binding') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.binding()));
        } else if (value == 'limit-none') {
          onChanged(pageSetup.copyWith(constraint: const TextSystemPageConstraint.none()));
        } else if (value == 'limit-5') {
          onChanged(pageSetup.copyWith(constraint: const TextSystemPageConstraint(maxPages: 5, label: 'Assignment limit')));
        } else if (value == 'limit-10') {
          onChanged(pageSetup.copyWith(constraint: const TextSystemPageConstraint(maxPages: 10, label: 'Assignment limit')));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<Object>>[
        const PopupMenuItem<Object>(enabled: false, child: Text('Document presets')),
        for (final preset in TextSystemPagePreset.builtIn)
          PopupMenuItem<TextSystemPagePreset>(
            value: preset,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(preset.label),
              subtitle: Text(preset.description),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(enabled: false, child: Text('Typography')),
        for (final typography in TextSystemPageTypography.builtIn)
          PopupMenuItem<TextSystemPageTypography>(
            value: typography,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(typography.compactLabel),
              subtitle: Text(typography.description),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(value: 'margin-academic', child: Text('Academic margins')),
        const PopupMenuItem<Object>(value: 'margin-compact', child: Text('Compact margins')),
        const PopupMenuItem<Object>(value: 'margin-roomy', child: Text('Roomy review margins')),
        const PopupMenuItem<Object>(value: 'margin-binding', child: Text('Binding margins')),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: pageSetup.orientation == TextSystemPageOrientation.portrait ? 'landscape' : 'portrait',
          child: Text(pageSetup.orientation == TextSystemPageOrientation.portrait ? 'Switch to landscape' : 'Switch to portrait'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(value: 'limit-none', child: Text('No page limit')),
        const PopupMenuItem<Object>(value: 'limit-5', child: Text('Max 5 pages')),
        const PopupMenuItem<Object>(value: 'limit-10', child: Text('Max 10 pages')),
      ],
      child: const _RibbonCommandSurface(
        enabled: true,
        icon: Icons.description_outlined,
        label: 'Setup',
        onPressed: null,
      ),
    );
  }
}


class _PremiumWriterToolbar extends StatelessWidget {
  const _PremiumWriterToolbar({
    required this.commandController,
    required this.overviewExpanded,
    required this.showInspector,
    required this.showObjectNavigator,
    required this.widePage,
    required this.pageSetup,
    required this.pageMode,
    required this.citationSettings,
    required this.onCitationSettingsChanged,
    required this.onPageSetupChanged,
    required this.onPageModeChanged,
    required this.onToggleOverview,
    required this.onToggleInspector,
    required this.onToggleObjectNavigator,
    required this.onToggleWidePage,
    required this.showMarginGuides,
    required this.onToggleMarginGuides,
    required this.showDetailedPageBreakLabels,
    required this.onTogglePageBreakLabels,
    required this.onHideToolbar,
  });

  final FluentDocumentCommandController commandController;
  final bool overviewExpanded;
  final bool showInspector;
  final bool showObjectNavigator;
  final bool widePage;
  final TextSystemPageSetup pageSetup;
  final _PremiumWriterPageMode pageMode;
  final TextSystemCitationSettings citationSettings;
  final ValueChanged<TextSystemCitationSettings> onCitationSettingsChanged;
  final ValueChanged<TextSystemPageSetup> onPageSetupChanged;
  final ValueChanged<_PremiumWriterPageMode> onPageModeChanged;
  final bool showMarginGuides;
  final bool showDetailedPageBreakLabels;
  final VoidCallback onToggleOverview;
  final VoidCallback onToggleInspector;
  final VoidCallback onToggleObjectNavigator;
  final VoidCallback onToggleWidePage;
  final VoidCallback onToggleMarginGuides;
  final VoidCallback onTogglePageBreakLabels;
  final VoidCallback onHideToolbar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.8)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Writer', style: theme.textTheme.labelLarge),
            const SizedBox(width: 4),
            _ParagraphStyleDropdown(commandController: commandController),
            _PageSetupMenu(
              pageSetup: pageSetup,
              onChanged: onPageSetupChanged,
            ),
            _PageModeMenu(
              pageMode: pageMode,
              onChanged: onPageModeChanged,
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              tooltip: 'Bold (Ctrl/Cmd+B)',
              icon: Icons.format_bold_rounded,
              onPressed: commandController.canFormatSelection ? commandController.bold : null,
            ),
            _ToolbarButton(
              tooltip: 'Italic (Ctrl/Cmd+I)',
              icon: Icons.format_italic_rounded,
              onPressed: commandController.canFormatSelection ? commandController.italic : null,
            ),
            _ToolbarButton(
              tooltip: 'Underline (Ctrl/Cmd+U)',
              icon: Icons.format_underlined_rounded,
              onPressed: commandController.canFormatSelection ? commandController.underline : null,
            ),
            _ToolbarButton(
              tooltip: 'Highlight (Ctrl/Cmd+Shift+H)',
              icon: Icons.border_color_rounded,
              onPressed: commandController.canFormatSelection ? commandController.highlight : null,
            ),
            _ToolbarButton(
              tooltip: 'Inline code',
              icon: Icons.code_rounded,
              onPressed: commandController.canFormatSelection ? commandController.code : null,
            ),
            _ReferenceActionMenu(commandController: commandController),
            _CitationSettingsMenu(
              settings: citationSettings,
              onChanged: onCitationSettingsChanged,
            ),
            _ToolbarButton(
              tooltip: 'Quick source link (Ctrl/Cmd+K)',
              icon: Icons.link_rounded,
              onPressed: commandController.canCreateReference ? commandController.linkSource : null,
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              tooltip: 'Copy (Ctrl/Cmd+C)',
              icon: Icons.copy_rounded,
              onPressed: commandController.canCopy ? commandController.copy : null,
            ),
            _ToolbarButton(
              tooltip: 'Cut (Ctrl/Cmd+X)',
              icon: Icons.content_cut_rounded,
              onPressed: commandController.canCut ? commandController.cut : null,
            ),
            _ToolbarButton(
              tooltip: 'Paste (Ctrl/Cmd+V)',
              icon: Icons.content_paste_rounded,
              onPressed: commandController.canPaste ? commandController.paste : null,
            ),
            const SizedBox(width: 8),
            _ToolbarButton(
              tooltip: 'Undo',
              icon: Icons.undo_rounded,
              onPressed: commandController.canUndo ? commandController.undo : null,
            ),
            _ToolbarButton(
              tooltip: 'Redo',
              icon: Icons.redo_rounded,
              onPressed: commandController.canRedo ? commandController.redo : null,
            ),
            const SizedBox(width: 14),
            FilterChip(
              label: const Text('Document map'),
              selected: overviewExpanded,
              onSelected: (_) => onToggleOverview(),
            ),
            FilterChip(
              label: const Text('Inspector'),
              selected: showInspector,
              onSelected: (_) => onToggleInspector(),
            ),
            FilterChip(
              label: const Text('Wide page'),
              selected: widePage,
              onSelected: (_) => onToggleWidePage(),
            ),
            FilterChip(
              label: const Text('Margins'),
              selected: showMarginGuides,
              onSelected: (_) => onToggleMarginGuides(),
            ),
            FilterChip(
              label: const Text('Break labels'),
              selected: showDetailedPageBreakLabels,
              onSelected: pageMode == _PremiumWriterPageMode.hybrid
                  ? (_) => onTogglePageBreakLabels()
                  : null,
            ),
            TextButton.icon(
              onPressed: onHideToolbar,
              icon: const Icon(Icons.visibility_off_rounded),
              label: const Text('Hide controls'),
            ),
          ],
        ),
      ),
    );
  }
}



enum _PremiumReferenceAction {
  citation,
  source,
  document,
  project,
  todo,
  link;

  String get label {
    return switch (this) {
      _PremiumReferenceAction.citation => 'Add citation',
      _PremiumReferenceAction.source => 'Link source',
      _PremiumReferenceAction.document => 'Link document',
      _PremiumReferenceAction.project => 'Link project',
      _PremiumReferenceAction.todo => 'Link todo',
      _PremiumReferenceAction.link => 'External link',
    };
  }

  IconData get icon {
    return switch (this) {
      _PremiumReferenceAction.citation => Icons.format_quote_rounded,
      _PremiumReferenceAction.source => Icons.source_outlined,
      _PremiumReferenceAction.document => Icons.description_outlined,
      _PremiumReferenceAction.project => Icons.account_tree_outlined,
      _PremiumReferenceAction.todo => Icons.check_circle_outline_rounded,
      _PremiumReferenceAction.link => Icons.link_rounded,
    };
  }

  void invoke(FluentDocumentCommandController controller) {
    switch (this) {
      case _PremiumReferenceAction.citation:
        controller.addCitation();
        break;
      case _PremiumReferenceAction.source:
        controller.linkSource();
        break;
      case _PremiumReferenceAction.document:
        controller.linkDocument();
        break;
      case _PremiumReferenceAction.project:
        controller.linkProject();
        break;
      case _PremiumReferenceAction.todo:
        controller.linkTodo();
        break;
      case _PremiumReferenceAction.link:
        controller.addReferenceLink();
        break;
    }
  }
}


class _CitationSettingsMenu extends StatelessWidget {
  const _CitationSettingsMenu({
    required this.settings,
    required this.onChanged,
  });

  final TextSystemCitationSettings settings;
  final ValueChanged<TextSystemCitationSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: null,
      onSelected: (value) {
        if (value is TextSystemCitationStyle) {
          onChanged(settings.copyWith(style: value));
        } else if (value is TextSystemCitationInlineMode) {
          onChanged(settings.copyWith(inlineMode: value));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<Object>>[
        const PopupMenuItem<Object>(enabled: false, child: Text('Reference style')),
        for (final style in TextSystemCitationStyle.values)
          PopupMenuItem<Object>(
            value: style,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 22, child: settings.style == style ? const Icon(Icons.check_rounded, size: 18) : null),
                Text(style.label),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(enabled: false, child: Text('Inline citation mode')),
        for (final mode in TextSystemCitationInlineMode.values)
          PopupMenuItem<Object>(
            value: mode,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 22, child: settings.inlineMode == mode ? const Icon(Icons.check_rounded, size: 18) : null),
                Text(mode.label),
              ],
            ),
          ),
      ],
      child: _ToolbarButtonShell(
        enabled: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 18),
            const SizedBox(width: 6),
            Text('Cite: ${settings.style.label}'),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ReferenceActionMenu extends StatelessWidget {
  const _ReferenceActionMenu({required this.commandController});

  final FluentDocumentCommandController commandController;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PremiumReferenceAction>(
      tooltip: commandController.canCreateReference
          ? 'Create citation/source link from selected text'
          : 'Select text to create a citation or source link',
      enabled: commandController.canCreateReference,
      onSelected: (action) => action.invoke(commandController),
      itemBuilder: (context) => <PopupMenuEntry<_PremiumReferenceAction>>[
        for (final action in _PremiumReferenceAction.values)
          PopupMenuItem<_PremiumReferenceAction>(
            value: action,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(action.icon),
              title: Text(action.label),
              subtitle: action == _PremiumReferenceAction.source
                  ? const Text('Default Ctrl/Cmd+K action')
                  : null,
            ),
          ),
      ],
      child: _ToolbarButtonShell(
        enabled: commandController.canCreateReference,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.hub_outlined, size: 18),
            SizedBox(width: 6),
            Text('Reference'),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButtonShell extends StatelessWidget {
  const _ToolbarButtonShell({
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.48,
      duration: const Duration(milliseconds: 120),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? colorScheme.secondaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: DefaultTextStyle.merge(
            style: theme.textTheme.labelMedium?.copyWith(
              color: enabled ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
            child: IconTheme.merge(
              data: IconThemeData(
                color: enabled ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageModeMenu extends StatelessWidget {
  const _PageModeMenu({
    required this.pageMode,
    required this.onChanged,
  });

  final _PremiumWriterPageMode pageMode;
  final ValueChanged<_PremiumWriterPageMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PremiumWriterPageMode>(
      tooltip: 'Writer page mode',
      initialValue: pageMode,
      onSelected: onChanged,
      itemBuilder: (context) => <PopupMenuEntry<_PremiumWriterPageMode>>[
        for (final mode in _PremiumWriterPageMode.displayOrder)
          PopupMenuItem<_PremiumWriterPageMode>(
            value: mode,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(mode.label),
              subtitle: Text(mode.description),
            ),
          ),
      ],
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_agenda_outlined, size: 18),
            const SizedBox(width: 8),
            Text(pageMode.label),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}

class _PageSetupMenu extends StatelessWidget {
  const _PageSetupMenu({
    required this.pageSetup,
    required this.onChanged,
  });

  final TextSystemPageSetup pageSetup;
  final ValueChanged<TextSystemPageSetup> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: null,
      onSelected: (value) {
        if (value is TextSystemPagePreset) {
          onChanged(value.setup);
          return;
        }
        if (value is TextSystemPageTypography) {
          onChanged(pageSetup.copyWith(typography: value));
          return;
        }
        if (value == 'landscape') {
          onChanged(pageSetup.copyWith(orientation: TextSystemPageOrientation.landscape));
        } else if (value == 'portrait') {
          onChanged(pageSetup.copyWith(orientation: TextSystemPageOrientation.portrait));
        } else if (value == 'margin-academic') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.academic()));
        } else if (value == 'margin-compact') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.compact()));
        } else if (value == 'margin-roomy') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.roomy()));
        } else if (value == 'margin-binding') {
          onChanged(pageSetup.copyWith(margins: const TextSystemPageMargins.binding()));
        } else if (value == 'limit-none') {
          onChanged(pageSetup.copyWith(constraint: const TextSystemPageConstraint.none()));
        } else if (value == 'limit-5') {
          onChanged(pageSetup.copyWith(constraint: const TextSystemPageConstraint(maxPages: 5, label: 'Assignment limit')));
        } else if (value == 'limit-10') {
          onChanged(pageSetup.copyWith(constraint: const TextSystemPageConstraint(maxPages: 10, label: 'Assignment limit')));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<Object>>[
        const PopupMenuItem<Object>(
          enabled: false,
          child: Text('Document presets'),
        ),
        for (final preset in TextSystemPagePreset.builtIn)
          PopupMenuItem<TextSystemPagePreset>(
            value: preset,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(preset.label),
              subtitle: Text(preset.description),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          enabled: false,
          child: Text('Typography'),
        ),
        for (final typography in TextSystemPageTypography.builtIn)
          PopupMenuItem<TextSystemPageTypography>(
            value: typography,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(typography.compactLabel),
              subtitle: Text(typography.description),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          enabled: false,
          child: Text('Margins'),
        ),
        const PopupMenuItem<Object>(value: 'margin-academic', child: Text('Academic — 25.4 mm')),
        const PopupMenuItem<Object>(value: 'margin-compact', child: Text('Compact — 18 mm')),
        const PopupMenuItem<Object>(value: 'margin-roomy', child: Text('Roomy review — 32 mm')),
        const PopupMenuItem<Object>(value: 'margin-binding', child: Text('Binding — 32 mm left')),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: pageSetup.orientation == TextSystemPageOrientation.portrait ? 'landscape' : 'portrait',
          child: Text(pageSetup.orientation == TextSystemPageOrientation.portrait ? 'Switch to landscape' : 'Switch to portrait'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(value: 'limit-none', child: Text('No page limit')),
        const PopupMenuItem<Object>(value: 'limit-5', child: Text('Max 5 pages')),
        const PopupMenuItem<Object>(value: 'limit-10', child: Text('Max 10 pages')),
      ],
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 18),
            const SizedBox(width: 8),
            Text(pageSetup.size.label),
            const SizedBox(width: 6),
            Text(pageSetup.typography.label),
            if (pageSetup.constraint.hasPageLimit) ...[
              const SizedBox(width: 6),
              Text('max ${pageSetup.constraint.maxPages}'),
            ],
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}

class _ParagraphStyleDropdown extends StatelessWidget {
  const _ParagraphStyleDropdown({required this.commandController});

  final FluentDocumentCommandController commandController;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<FluentParagraphStyle>(
      tooltip: 'Paragraph style',
      enabled: commandController.canApplyParagraphStyle,
      initialValue: commandController.currentParagraphStyle,
      onSelected: commandController.applyParagraphStyle,
      itemBuilder: (context) => const [
        PopupMenuItem(value: FluentParagraphStyle.paragraph, child: Text('Paragraph')),
        PopupMenuItem(value: FluentParagraphStyle.heading1, child: Text('Heading 1')),
        PopupMenuItem(value: FluentParagraphStyle.heading2, child: Text('Heading 2')),
        PopupMenuItem(value: FluentParagraphStyle.heading3, child: Text('Heading 3')),
        PopupMenuItem(value: FluentParagraphStyle.bullet, child: Text('Bullet list')),
        PopupMenuItem(value: FluentParagraphStyle.numbered, child: Text('Numbered list')),
        PopupMenuItem(value: FluentParagraphStyle.todo, child: Text('Todo')),
        PopupMenuItem(value: FluentParagraphStyle.quote, child: Text('Quote')),
        PopupMenuItem(value: FluentParagraphStyle.code, child: Text('Code')),
      ],
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.format_size_rounded, size: 18),
            const SizedBox(width: 8),
            Text(commandController.currentParagraphStyle.label),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down_rounded),
          ],
        ),
      ),
    );
  }
}



class _AcademicObjectNavigatorItem {
  const _AcademicObjectNavigatorItem({
    required this.blockId,
    required this.blockIndex,
    required this.kind,
    required this.ordinal,
    required this.caption,
    required this.label,
    required this.pageNumber,
    required this.source,
    required this.note,
    required this.imagePath,
    required this.rows,
    required this.columns,
  });

  final String blockId;
  final int blockIndex;
  final TextSystemStructureReferenceKind kind;
  final int ordinal;
  final String caption;
  final String label;
  final int pageNumber;
  final String source;
  final String note;
  final String imagePath;
  final int rows;
  final int columns;

  bool get isFigure => kind == TextSystemStructureReferenceKind.figure;
  bool get isTable => kind == TextSystemStructureReferenceKind.table;
  bool get isEquation => kind == TextSystemStructureReferenceKind.equation;
  bool get missingCaption => !isEquation && caption.trim().isEmpty;
  bool get missingLabel => label.trim().isEmpty;
  bool get missingImage => isFigure && imagePath.trim().isEmpty;
  bool get hasIssue => missingCaption || missingLabel || missingImage || (isEquation && caption.trim().isEmpty);
  String get noun => isTable ? 'Table' : isEquation ? 'Equation' : 'Figure';
  String get title => '$noun $ordinal';
  String get pageLabel => 'p. $pageNumber';
  String get compactMeta {
    if (isEquation) return 'LaTeX equation';
    if (isTable && rows > 0 && columns > 0) return '$rows × $columns cells';
    if (isFigure && imagePath.trim().isNotEmpty) {
      final normalized = imagePath.trim().replaceAll('\\', '/');
      final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
      return parts.isEmpty ? 'Image attached' : parts.last;
    }
    return isFigure ? 'No image attached' : 'Table';
  }
}

enum _AcademicObjectNavigatorFilter { all, figures, tables, equations, issues }

class _AcademicObjectNavigatorPanel extends StatefulWidget {
  const _AcademicObjectNavigatorPanel({
    required this.items,
    required this.onNavigateToBlock,
    required this.onClose,
  });

  final List<_AcademicObjectNavigatorItem> items;
  final ValueChanged<String> onNavigateToBlock;
  final VoidCallback onClose;

  @override
  State<_AcademicObjectNavigatorPanel> createState() => _AcademicObjectNavigatorPanelState();
}

class _AcademicObjectNavigatorPanelState extends State<_AcademicObjectNavigatorPanel> {
  _AcademicObjectNavigatorFilter _filter = _AcademicObjectNavigatorFilter.all;

  List<_AcademicObjectNavigatorItem> get _visibleItems {
    return switch (_filter) {
      _AcademicObjectNavigatorFilter.all => widget.items,
      _AcademicObjectNavigatorFilter.figures => widget.items.where((item) => item.isFigure).toList(growable: false),
      _AcademicObjectNavigatorFilter.tables => widget.items.where((item) => item.isTable).toList(growable: false),
      _AcademicObjectNavigatorFilter.equations => widget.items.where((item) => item.isEquation).toList(growable: false),
      _AcademicObjectNavigatorFilter.issues => widget.items.where((item) => item.hasIssue).toList(growable: false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final figures = widget.items.where((item) => item.isFigure).length;
    final tables = widget.items.where((item) => item.isTable).length;
    final equations = widget.items.where((item) => item.isEquation).length;
    final issues = widget.items.where((item) => item.hasIssue).length;
    final visible = _visibleItems;

    return Material(
      color: colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.view_list_rounded, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Object navigator',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close object navigator',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$figures figures · $tables tables · $equations equations · $issues issue${issues == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _ObjectNavigatorFilterChip(
                        label: 'All',
                        selected: _filter == _AcademicObjectNavigatorFilter.all,
                        onSelected: () => setState(() => _filter = _AcademicObjectNavigatorFilter.all),
                      ),
                      _ObjectNavigatorFilterChip(
                        label: 'Figures',
                        selected: _filter == _AcademicObjectNavigatorFilter.figures,
                        onSelected: () => setState(() => _filter = _AcademicObjectNavigatorFilter.figures),
                      ),
                      _ObjectNavigatorFilterChip(
                        label: 'Tables',
                        selected: _filter == _AcademicObjectNavigatorFilter.tables,
                        onSelected: () => setState(() => _filter = _AcademicObjectNavigatorFilter.tables),
                      ),
                      _ObjectNavigatorFilterChip(
                        label: 'Equations',
                        selected: _filter == _AcademicObjectNavigatorFilter.equations,
                        onSelected: () => setState(() => _filter = _AcademicObjectNavigatorFilter.equations),
                      ),
                      _ObjectNavigatorFilterChip(
                        label: 'Issues',
                        selected: _filter == _AcademicObjectNavigatorFilter.issues,
                        onSelected: () => setState(() => _filter = _AcademicObjectNavigatorFilter.issues),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
            Expanded(
              child: visible.isEmpty
                  ? _AcademicObjectNavigatorEmptyState(filter: _filter)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        return _AcademicObjectNavigatorRow(
                          item: item,
                          onTap: () => widget.onNavigateToBlock(item.blockId),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObjectNavigatorFilterChip extends StatelessWidget {
  const _ObjectNavigatorFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _AcademicObjectNavigatorEmptyState extends StatelessWidget {
  const _AcademicObjectNavigatorEmptyState({required this.filter});

  final _AcademicObjectNavigatorFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = switch (filter) {
      _AcademicObjectNavigatorFilter.all => 'Insert a figure or table to build an academic object list.',
      _AcademicObjectNavigatorFilter.figures => 'No figures in this document yet.',
      _AcademicObjectNavigatorFilter.tables => 'No tables in this document yet.',
      _AcademicObjectNavigatorFilter.equations => 'No equations in this document yet.',
      _AcademicObjectNavigatorFilter.issues => 'No missing captions, labels, or figure images found.',
    };

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.view_list_outlined, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('No objects', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AcademicObjectNavigatorRow extends StatelessWidget {
  const _AcademicObjectNavigatorRow({
    required this.item,
    required this.onTap,
  });

  final _AcademicObjectNavigatorItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = item.isTable
        ? Icons.table_chart_outlined
        : item.isEquation
            ? Icons.functions_rounded
            : Icons.image_outlined;
    final caption = item.caption.trim().isEmpty ? 'Missing caption' : item.caption.trim();
    final issueParts = <String>[
      if (item.missingCaption) 'caption',
      if (item.missingLabel) 'label',
      if (item.missingImage) 'image',
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: item.hasIssue
              ? colorScheme.errorContainer.withValues(alpha: 0.22)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: item.hasIssue
                ? colorScheme.error.withValues(alpha: 0.24)
                : colorScheme.outlineVariant.withValues(alpha: 0.78),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: item.hasIssue ? colorScheme.error : colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _PageAnchorChip(label: item.pageLabel),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: item.missingCaption ? colorScheme.error : colorScheme.onSurface,
                fontWeight: item.missingCaption ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _ObjectNavigatorMetaChip(
                  icon: Icons.tag_rounded,
                  label: item.label.isEmpty ? 'Missing label' : item.label,
                  warning: item.label.isEmpty,
                ),
                _ObjectNavigatorMetaChip(
                  icon: item.isTable ? Icons.grid_on_rounded : Icons.image_search_rounded,
                  label: item.compactMeta,
                  warning: item.missingImage,
                ),
                if (item.source.isNotEmpty)
                  _ObjectNavigatorMetaChip(
                    icon: Icons.source_outlined,
                    label: item.source,
                  ),
                if (item.note.isNotEmpty)
                  _ObjectNavigatorMetaChip(
                    icon: Icons.notes_rounded,
                    label: item.note,
                  ),
              ],
            ),
            if (issueParts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Needs ${issueParts.join(', ')}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ObjectNavigatorMetaChip extends StatelessWidget {
  const _ObjectNavigatorMetaChip({
    required this.icon,
    required this.label,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: warning
            ? colorScheme.errorContainer.withValues(alpha: 0.46)
            : colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: warning
              ? colorScheme.error.withValues(alpha: 0.24)
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: warning ? colorScheme.error : colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: warning ? colorScheme.error : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumDocumentMapDrawer extends StatefulWidget {
  const _PremiumDocumentMapDrawer({
    required this.items,
    required this.wordCount,
    required this.characterCount,
    required this.sectionMetrics,
    required this.onItemSelected,
  });

  final List<_PremiumOutlineItem> items;
  final int wordCount;
  final int characterCount;
  final TextSystemSectionPageMetricsResult sectionMetrics;
  final ValueChanged<_PremiumOutlineItem> onItemSelected;

  @override
  State<_PremiumDocumentMapDrawer> createState() => _PremiumDocumentMapDrawerState();
}

class _PremiumDocumentMapDrawerState extends State<_PremiumDocumentMapDrawer> {
  final Set<String> _collapsedIds = <String>{};
  bool _showProjectSignals = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleItems = _visibleItems(widget.items);

    return Material(
      color: colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_tree_rounded, size: 19, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Document map', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.items.length} headings · ${widget.wordCount} words · ${widget.sectionMetrics.measuredPagesLabel} measured pages',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Shows structure, measured page anchors, section spans, and compact project signals.',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Switch.adaptive(
                        value: _showProjectSignals,
                        onChanged: (value) => setState(() => _showProjectSignals = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
            Expanded(
              child: widget.items.isEmpty
                  ? _DocumentMapEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
                      itemCount: visibleItems.length,
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        return _DocumentMapRow(
                          item: item,
                          hasChildren: _hasChildren(widget.items, item),
                          collapsed: _collapsedIds.contains(item.blockId),
                          showProjectSignals: _showProjectSignals,
                          onToggleCollapsed: () {
                            setState(() {
                              if (_collapsedIds.contains(item.blockId)) {
                                _collapsedIds.remove(item.blockId);
                              } else {
                                _collapsedIds.add(item.blockId);
                              }
                            });
                          },
                          onSelected: widget.onItemSelected,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<_PremiumOutlineItem> _visibleItems(List<_PremiumOutlineItem> items) {
    final visible = <_PremiumOutlineItem>[];
    final hiddenLevels = <int>[];

    for (final item in items) {
      hiddenLevels.removeWhere((level) => level >= item.level);
      if (hiddenLevels.isNotEmpty) continue;
      visible.add(item);
      if (_collapsedIds.contains(item.blockId)) {
        hiddenLevels.add(item.level);
      }
    }
    return visible;
  }

  bool _hasChildren(List<_PremiumOutlineItem> items, _PremiumOutlineItem item) {
    final startIndex = items.indexWhere((candidate) => candidate.blockId == item.blockId);
    if (startIndex < 0) return false;
    for (var i = startIndex + 1; i < items.length; i++) {
      final candidate = items[i];
      if (candidate.level <= item.level) return false;
      if (candidate.level > item.level) return true;
    }
    return false;
  }
}

class _DocumentMapEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.account_tree_outlined, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('No headings yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Use the style menu to create Heading 1, Heading 2, or Heading 3. The document map will build itself from those styles.',
            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DocumentMapRow extends StatelessWidget {
  const _DocumentMapRow({
    required this.item,
    required this.hasChildren,
    required this.collapsed,
    required this.showProjectSignals,
    required this.onToggleCollapsed,
    required this.onSelected,
  });

  final _PremiumOutlineItem item;
  final bool hasChildren;
  final bool collapsed;
  final bool showProjectSignals;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<_PremiumOutlineItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final indent = ((item.level - 1).clamp(0, 4)) * 18.0;
    final titleStyle = switch (item.level) {
      1 => theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.55,
        ),
      2 => theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      _ => theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
    };

    return Padding(
      padding: EdgeInsets.only(left: indent, right: 4, top: 2, bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onSelected(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                child: hasChildren
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: collapsed ? 'Expand section' : 'Collapse section',
                        onPressed: onToggleCollapsed,
                        icon: Icon(collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded),
                      )
                    : Text(
                        'H${item.level}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.level == 1 ? item.text.toUpperCase() : item.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 6),
              _PageAnchorChip(label: item.pageLabel),
              if (item.sectionSpanLabel != null) ...[
                const SizedBox(width: 4),
                _SectionSpanChip(label: item.sectionSpanLabel!),
              ],
              if (showProjectSignals) ...[
                const SizedBox(width: 6),
                _ProjectSignalBadges(item: item),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _PageAnchorChip extends StatelessWidget {
  const _PageAnchorChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}


class _SectionSpanChip extends StatelessWidget {
  const _SectionSpanChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}

class _ProjectSignalBadges extends StatelessWidget {
  const _ProjectSignalBadges({required this.item});

  final _PremiumOutlineItem item;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if (item.todoCount > 0) {
      badges.add(_SignalBadge(
        icon: Icons.check_circle_outline_rounded,
        count: item.todoCount,
        severity: item.deadlineSeverity,
        tooltip: '${item.todoCount} todo${item.todoCount == 1 ? '' : 's'}',
      ));
    }
    if (item.noteCount > 0) {
      badges.add(_SignalBadge(
        icon: Icons.sticky_note_2_outlined,
        count: item.noteCount,
        severity: _ProjectSignalSeverity.normal,
        tooltip: '${item.noteCount} note${item.noteCount == 1 ? '' : 's'}',
      ));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, children: badges);
  }
}

enum _ProjectSignalSeverity { normal, dueSoon, overdue }

class _SignalBadge extends StatelessWidget {
  const _SignalBadge({
    required this.icon,
    required this.count,
    required this.severity,
    required this.tooltip,
  });

  final IconData icon;
  final int count;
  final _ProjectSignalSeverity severity;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = switch (severity) {
      _ProjectSignalSeverity.overdue => colorScheme.error,
      _ProjectSignalSeverity.dueSoon => colorScheme.tertiary,
      _ => colorScheme.onSurfaceVariant,
    };

    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
  }
}


class _PagelessPremiumWriterCanvas extends StatelessWidget {
  const _PagelessPremiumWriterCanvas({
    required this.focusMode,
    required this.widePage,
    required this.child,
  });

  final bool focusMode;
  final bool widePage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxWidth = widePage ? 980.0 : 820.0;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            focusMode ? 24 : 44,
            focusMode ? 24 : 38,
            focusMode ? 24 : 44,
            focusMode ? 30 : 58,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumInspectorPanel extends StatelessWidget {
  const _PremiumInspectorPanel({
    required this.document,
    required this.textController,
    required this.autosaveController,
    required this.wordCount,
    required this.outlineItems,
    required this.pageSetup,
    required this.pageFurniture,
    required this.onPageFurnitureChanged,
    required this.pageEstimate,
    required this.pageLayout,
    required this.pageMap,
    required this.sectionMetrics,
    required this.workPlan,
    required this.unifiedLayoutTree,
    required this.documentStructure,
    required this.referenceIndex,
    required this.pageMode,
    required this.showDetailedPageBreakLabels,
    required this.targetPageCount,
    required this.planningHorizonDays,
    required this.onTargetPageCountChanged,
    required this.onPlanningHorizonDaysChanged,
    required this.onNavigateToBlock,
    required this.onNavigateToPage,
    this.pageViewport,
  });

  final TextSystemDocument document;
  final TextSystemController textController;
  final TextSystemAutosaveController autosaveController;
  final int wordCount;
  final int outlineItems;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture> onPageFurnitureChanged;
  final TextSystemPageEstimate pageEstimate;
  final TextSystemPageLayout pageLayout;
  final TextSystemPageMap pageMap;
  final TextSystemSectionPageMetricsResult sectionMetrics;
  final TextSystemPageWorkPlan workPlan;
  final TextSystemDocumentLayoutTree unifiedLayoutTree;
  final TextSystemDocumentStructure documentStructure;
  final TextSystemReferenceIndex referenceIndex;
  final _PremiumWriterPageMode pageMode;
  final bool showDetailedPageBreakLabels;
  final double targetPageCount;
  final int planningHorizonDays;
  final ValueChanged<double> onTargetPageCountChanged;
  final ValueChanged<int> onPlanningHorizonDaysChanged;
  final ValueChanged<String> onNavigateToBlock;
  final ValueChanged<int> onNavigateToPage;
  final TextSystemPageViewport? pageViewport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        children: [
          Text('Inspector', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _PageProgressCard(
            sectionMetrics: sectionMetrics,
            targetPageCount: targetPageCount,
            onTargetPageCountChanged: onTargetPageCountChanged,
          ),
          const SizedBox(height: 14),
          _WritingPlanCard(
            workPlan: workPlan,
            planningHorizonDays: planningHorizonDays,
            onPlanningHorizonDaysChanged: onPlanningHorizonDaysChanged,
          ),
          const SizedBox(height: 14),
          _DocumentStructureCard(
            structure: documentStructure,
            currentPage: pageViewport?.currentPage,
            onNavigateToBlock: onNavigateToBlock,
            onNavigateToPage: onNavigateToPage,
          ),
          const SizedBox(height: 14),
          _ReferenceBridgeCard(
            index: referenceIndex,
            onNavigateToBlock: onNavigateToBlock,
          ),
          const SizedBox(height: 14),
          _PageFurnitureCard(
            pageFurniture: pageFurniture,
            onChanged: onPageFurnitureChanged,
          ),
          const SizedBox(height: 14),
          _MetricRow(label: 'Document', value: document.title),
          _MetricRow(label: 'Text units', value: '${document.blocks.length}'),
          _MetricRow(label: 'Headings', value: '$outlineItems'),
          _MetricRow(label: 'Page setup', value: pageSetup.shortLabel),
          _MetricRow(label: 'Physical page', value: pageSetup.physicalSizeLabel),
          _MetricRow(label: 'Margins', value: pageSetup.margins.shortLabel),
          _MetricRow(label: 'Typography', value: pageSetup.typography.compactLabel),
          _MetricRow(label: 'Page furniture', value: pageFurniture.shortLabel),
          _MetricRow(label: 'Page estimate', value: pageEstimate.pageLabel),
          _MetricRow(label: 'Measured pages', value: pageMap.pageLabel),
          _MetricRow(label: 'Target pages', value: sectionMetrics.targetPagesLabel),
          _MetricRow(label: 'Remaining', value: sectionMetrics.remainingPagesLabel),
          _MetricRow(label: 'Required pace', value: workPlan.paceLabel),
          _MetricRow(label: 'Sections', value: '${sectionMetrics.sectionCount}'),
          _MetricRow(label: 'Page breaks', value: '${pageMap.breakMarkers.length}'),
          _MetricRow(label: 'Page editor', value: pageMode == _PremiumWriterPageMode.pagedBlocksExperimental
                ? 'TextField fallback'
                : pageMode == _PremiumWriterPageMode.ownedDocumentPreview
                    ? 'owned editor default'
                    : 'off'),
          _MetricRow(label: 'Unified layout tree', value: unifiedLayoutTree.compactLabel),
          _MetricRow(label: 'Layout mode', value: unifiedLayoutTree.measurementMode.label),
          _MetricRow(label: 'Structure', value: documentStructure.compactLabel),
          _MetricRow(label: 'References', value: referenceIndex.compactLabel),
          const _MetricRow(label: 'Export foundation', value: 'PDF visual · Markdown · LaTeX · Typst · HTML semantic'),
          _MetricRow(
            label: 'Hybrid overlay',
            value: pageMode == _PremiumWriterPageMode.hybrid
                ? '${pageMap.breakMarkers.length} non-interactive markers · ${showDetailedPageBreakLabels ? 'detailed labels' : 'compact labels'}'
                : 'off in ${pageMode.label}',
          ),
          _MetricRow(label: 'Measured content', value: pageMap.compactMetricsLabel),
          _MetricRow(label: 'Page anchors', value: '${pageLayout.anchors.length}'),
          _MetricRow(label: 'Layout lines', value: '${pageLayout.totalEstimatedLines}'),
          _MetricRow(label: 'Current page', value: pageViewport?.currentPageLabel ?? 'not measured yet'),
          _MetricRow(label: 'Visible pages', value: pageViewport?.visibleRangeLabel ?? 'not measured yet'),
          _MetricRow(label: 'Render window', value: pageViewport?.mountedRangeLabel ?? 'not measured yet'),
          _MetricRow(label: 'Page status', value: pageEstimate.statusLabel),
          _MetricRow(label: 'Content area', value: pageEstimate.compactLayoutLabel),
          _MetricRow(label: 'Words', value: '$wordCount'),
          _MetricRow(label: 'Characters', value: '${document.plainText.length}'),
          _MetricRow(label: 'Revision', value: '${textController.revision}'),
          _MetricRow(label: 'Transactions', value: '${textController.transactionLog.length}'),
          _MetricRow(label: 'Undo', value: textController.canUndo ? 'available' : 'none'),
          _MetricRow(label: 'Redo', value: textController.canRedo ? 'available' : 'none'),
          _MetricRow(label: 'Save', value: autosaveController.saveState.message ?? autosaveController.saveState.status.name),
          const SizedBox(height: 14),
          _LongestSectionList(sectionMetrics: sectionMetrics),
          const SizedBox(height: 14),
          Text(
            'This panel is diagnostic. Phase 16K promotes the owned real-page editor as the default Premium Writer surface while keeping the TextField-backed Real pages fallback selectable during stabilization.',
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}




class _DocumentStructureCard extends StatelessWidget {
  const _DocumentStructureCard({
    required this.structure,
    required this.onNavigateToBlock,
    required this.onNavigateToPage,
    this.currentPage,
  });

  final TextSystemDocumentStructure structure;
  final ValueChanged<String> onNavigateToBlock;
  final ValueChanged<int> onNavigateToPage;
  final int? currentPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stats = structure.stats;
    final outlinePreview = structure.outlineEntries.take(8).toList(growable: false);
    final sectionPreview = structure.sections.take(6).toList(growable: false);
    final visiblePageCount = structure.pageCount <= 8 ? structure.pageCount : 8;

    Widget metricChip(String label, String value, IconData icon) {
      return Chip(
        avatar: Icon(icon, size: 16),
        label: Text('$label: $value'),
        visualDensity: VisualDensity.compact,
      );
    }

    Widget navRow({
      required String title,
      required String trailing,
      required IconData icon,
      required VoidCallback onTap,
      double indent = 0,
      bool selected = false,
      String? subtitle,
    }) {
      final selectedColor = colorScheme.primaryContainer.withValues(alpha: 0.62);
      final baseColor = colorScheme.surface.withValues(alpha: 0.28);
      return Padding(
        padding: EdgeInsets.only(left: indent, bottom: 4),
        child: Material(
          color: selected ? selectedColor : baseColor,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(
                crossAxisAlignment: subtitle == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    trailing,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Document navigator',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Use the structure model to jump through outline, sections, and pages.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                metricChip('Sections', '${structure.sectionCount}', Icons.view_agenda_rounded),
                metricChip('Outline', '${structure.outlineCount}', Icons.format_list_bulleted_rounded),
                metricChip('Todos', stats.todoLabel, Icons.check_circle_outline_rounded),
                metricChip('Refs', '${structure.referenceCount}', Icons.link_rounded),
                metricChip('Notes', '${stats.footnoteCount}', Icons.notes_rounded),
              ],
            ),
            if (outlinePreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Outline', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final entry in outlinePreview)
                navRow(
                  title: entry.title,
                  trailing: entry.pageLabel,
                  icon: Icons.short_text_rounded,
                  indent: ((entry.level - 1).clamp(0, 4) * 10).toDouble(),
                  selected: currentPage != null && currentPage! >= entry.pageStart && currentPage! <= entry.pageEnd,
                  onTap: () => onNavigateToBlock(entry.blockId),
                ),
              if (structure.outlineEntries.length > outlinePreview.length)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+ ${structure.outlineEntries.length - outlinePreview.length} more headings',
                    style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'No headings yet. Add Heading 1/2/3 blocks to build a navigable outline.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (sectionPreview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Sections', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final section in sectionPreview)
                navRow(
                  title: section.title,
                  trailing: section.pageLabel,
                  subtitle: '${section.stats.wordCount} words · ${section.stats.todoLabel}',
                  icon: Icons.segment_rounded,
                  selected: currentPage != null && currentPage! >= section.pageStart && currentPage! <= section.pageEnd,
                  onTap: () {
                    final targetBlockId = section.headingBlockId ??
                        (section.blockIds.isNotEmpty ? section.blockIds.first : null);
                    if (targetBlockId != null) {
                      onNavigateToBlock(targetBlockId);
                    } else {
                      onNavigateToPage(section.pageStart);
                    }
                  },
                ),
            ],
            const SizedBox(height: 12),
            Text('Pages', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var page = 1; page <= visiblePageCount; page++)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: currentPage == page ? const Icon(Icons.my_location_rounded, size: 15) : null,
                    label: Text('p. $page'),
                    onPressed: () => onNavigateToPage(page),
                  ),
                if (structure.pageCount > visiblePageCount)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('+${structure.pageCount - visiblePageCount}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}




class _CitationSourceManagerPanel extends StatelessWidget {
  const _CitationSourceManagerPanel({
    required this.document,
    required this.referenceIndex,
    required this.citationSettings,
    required this.onNavigateToBlock,
    required this.onEditCitationSource,
    required this.onOpenCitationSource,
    required this.onShowCitationOccurrences,
    required this.onOpenLinkedReference,
    required this.onShowLinkedReferenceOccurrences,
    required this.onRepairCitations,
    required this.onDeduplicateSources,
    required this.onClose,
  });

  final TextSystemDocument document;
  final TextSystemReferenceIndex referenceIndex;
  final TextSystemCitationSettings citationSettings;
  final ValueChanged<String> onNavigateToBlock;
  final ValueChanged<TextSystemCitationRegistryItem> onEditCitationSource;
  final Future<void> Function(TextSystemCitationRegistryItem item) onOpenCitationSource;
  final ValueChanged<TextSystemCitationRegistryItem> onShowCitationOccurrences;
  final Future<void> Function(TextSystemStructureReference reference) onOpenLinkedReference;
  final ValueChanged<TextSystemStructureReference> onShowLinkedReferenceOccurrences;
  final VoidCallback onRepairCitations;
  final VoidCallback onDeduplicateSources;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final citationRegistry = TextSystemCitationRegistry.fromDocument(document);
    final linkedReferences = referenceIndex.allReferences
        .where((reference) => reference.kind != TextSystemStructureReferenceKind.citation)
        .where((reference) => reference.kind != TextSystemStructureReferenceKind.footnote)
        .toList(growable: false);
    final issues = _issuesFor(citationRegistry.items, linkedReferences);
    final duplicateCount = _duplicateCitationCount(citationRegistry.items);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
            child: Row(
              children: [
                Icon(Icons.library_books_outlined, size: 19, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Source manager',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${citationSettings.style.label} · ${citationSettings.inlineMode.label}',
                        style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: null,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              children: [
                _SourceManagerSummary(
                  citedSourceCount: citationRegistry.items.length,
                  linkedReferenceCount: linkedReferences.length,
                  issueCount: issues.length,
                ),
                const SizedBox(height: 12),
                _SourceManagerActionStrip(
                  duplicateCount: duplicateCount,
                  onRepair: onRepairCitations,
                  onDeduplicate: onDeduplicateSources,
                ),
                const SizedBox(height: 16),
                _SourceManagerSectionHeader(
                  icon: Icons.format_quote_rounded,
                  title: 'Cited sources',
                  subtitle: 'Edit metadata, open PDF/source targets, and inspect occurrences.',
                ),
                const SizedBox(height: 8),
                if (citationRegistry.items.isEmpty)
                  _SourceManagerEmptyState(
                    icon: Icons.format_quote_outlined,
                    message: 'No citations yet. Use References → Cite to add a source.',
                  )
                else
                  for (final item in citationRegistry.items)
                    _CitationSourceManagerRow(
                      icon: Icons.format_quote_rounded,
                      title: item.source.authorLabel,
                      subtitle: _citationSourceSubtitle(item.source),
                      trailing: item.source.year?.trim().isNotEmpty == true ? item.source.year!.trim() : 'n.d.',
                      onTap: () => onNavigateToBlock(item.firstBlockId),
                      actions: [
                        _SourceManagerRowAction(
                          icon: Icons.edit_outlined,
                          label: 'Edit',
                          onPressed: () => onEditCitationSource(item),
                        ),
                        _SourceManagerRowAction(
                          icon: Icons.open_in_new_rounded,
                          label: 'Open',
                          onPressed: () => unawaited(onOpenCitationSource(item)),
                        ),
                        _SourceManagerRowAction(
                          icon: Icons.format_list_bulleted_rounded,
                          label: 'Occurrences',
                          onPressed: () => onShowCitationOccurrences(item),
                        ),
                      ],
                    ),
                const SizedBox(height: 16),
                _SourceManagerSectionHeader(
                  icon: Icons.source_outlined,
                  title: 'Source and object links',
                  subtitle: 'Non-bibliography links to PDFs, documents, projects, todos, and URLs.',
                ),
                const SizedBox(height: 8),
                if (linkedReferences.isEmpty)
                  _SourceManagerEmptyState(
                    icon: Icons.link_off_rounded,
                    message: 'No source/object links yet. Use References → Source, Document, Project, Todo, or Link.',
                  )
                else
                  for (final reference in linkedReferences.take(18))
                    _CitationSourceManagerRow(
                      icon: _sourceManagerIconForReferenceKind(reference.kind),
                      title: reference.label,
                      subtitle: _sourceReferenceSubtitle(reference),
                      trailing: reference.pageLabel,
                      onTap: () => onNavigateToBlock(reference.blockId),
                      actions: [
                        _SourceManagerRowAction(
                          icon: Icons.open_in_new_rounded,
                          label: 'Open',
                          onPressed: () => unawaited(onOpenLinkedReference(reference)),
                        ),
                        _SourceManagerRowAction(
                          icon: Icons.format_list_bulleted_rounded,
                          label: 'Occurrences',
                          onPressed: () => onShowLinkedReferenceOccurrences(reference),
                        ),
                      ],
                    ),
                if (linkedReferences.length > 18)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+ ${linkedReferences.length - 18} more linked references',
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 16),
                _SourceManagerSectionHeader(
                  icon: Icons.rule_rounded,
                  title: 'Metadata checks',
                  subtitle: 'Warnings for incomplete, broken, or duplicated source metadata.',
                ),
                const SizedBox(height: 8),
                if (issues.isEmpty && duplicateCount == 0)
                  _SourceManagerEmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    message: 'No obvious citation/source metadata issues detected.',
                  )
                else ...[
                  if (duplicateCount > 0)
                    _SourceManagerIssueRow(
                      issue: _SourceManagerIssue('Possible duplicate sources', '$duplicateCount duplicate target${duplicateCount == 1 ? '' : 's'} can be merged.'),
                    ),
                  for (final issue in issues.take(10))
                    _SourceManagerIssueRow(issue: issue),
                ],
                if (issues.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+ ${issues.length - 10} more checks',
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_SourceManagerIssue> _issuesFor(
    List<TextSystemCitationRegistryItem> citationItems,
    List<TextSystemStructureReference> linkedReferences,
  ) {
    final issues = <_SourceManagerIssue>[];
    for (final item in citationItems) {
      final source = item.source;
      if (source.authors.isEmpty) {
        issues.add(_SourceManagerIssue('Missing author metadata', source.title));
      }
      if (source.year == null || source.year!.trim().isEmpty) {
        issues.add(_SourceManagerIssue('Missing year', source.title));
      }
      if (source.title.trim().isEmpty || source.title.trim() == 'Untitled source') {
        issues.add(_SourceManagerIssue('Missing source title', source.authorLabel));
      }
    }
    for (final reference in linkedReferences) {
      if ((reference.targetId == null || reference.targetId!.trim().isEmpty) &&
          (reference.url == null || reference.url!.trim().isEmpty)) {
        issues.add(_SourceManagerIssue('Missing target id', reference.label));
      }
    }
    return issues;
  }

  int _duplicateCitationCount(List<TextSystemCitationRegistryItem> citationItems) {
    final seen = <String, String>{};
    var duplicateCount = 0;
    for (final item in citationItems) {
      final signature = _sourceSignature(item.source);
      if (signature.isEmpty) continue;
      final existing = seen[signature];
      if (existing == null) {
        seen[signature] = item.mark.targetId;
      } else if (existing != item.mark.targetId) {
        duplicateCount += 1;
      }
    }
    return duplicateCount;
  }

  String _sourceSignature(TextSystemCitationSource source) {
    final title = source.title.trim().toLowerCase();
    final year = (source.year ?? '').trim().toLowerCase();
    final author = source.authorLabel.trim().toLowerCase();
    final signature = '$author::$year::$title'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return signature == '::::' ? '' : signature;
  }

  String _citationSourceSubtitle(TextSystemCitationSource source) {
    final parts = <String>[
      if (source.title.trim().isNotEmpty) source.title.trim(),
      if (source.containerTitle != null && source.containerTitle!.trim().isNotEmpty) source.containerTitle!.trim(),
      if (source.locator != null && source.locator!.trim().isNotEmpty) source.locator!.trim(),
      if (source.kind != null && source.kind!.trim().isNotEmpty) source.kind!.trim(),
    ];
    return parts.isEmpty ? 'Citation source' : parts.join(' · ');
  }

  String _sourceReferenceSubtitle(TextSystemStructureReference reference) {
    final parts = <String>[
      reference.kind.label,
      if (reference.role != null && reference.role!.trim().isNotEmpty) reference.role!.trim(),
      if (reference.targetId != null && reference.targetId!.trim().isNotEmpty) reference.targetId!.trim(),
      if (reference.url != null && reference.url!.trim().isNotEmpty) reference.url!.trim(),
    ];
    return parts.join(' · ');
  }

  IconData _sourceManagerIconForReferenceKind(TextSystemStructureReferenceKind kind) {
    return switch (kind) {
      TextSystemStructureReferenceKind.citation => Icons.format_quote_rounded,
      TextSystemStructureReferenceKind.source => Icons.source_outlined,
      TextSystemStructureReferenceKind.link => Icons.link_rounded,
      TextSystemStructureReferenceKind.footnote => Icons.notes_rounded,
      TextSystemStructureReferenceKind.project => Icons.folder_copy_outlined,
      TextSystemStructureReferenceKind.todo => Icons.check_circle_outline_rounded,
      TextSystemStructureReferenceKind.figure => Icons.image_outlined,
      TextSystemStructureReferenceKind.table => Icons.table_chart_outlined,
      TextSystemStructureReferenceKind.equation => Icons.functions_rounded,
      TextSystemStructureReferenceKind.unknown => Icons.hub_outlined,
    };
  }
}

class _SourceManagerSummary extends StatelessWidget {
  const _SourceManagerSummary({
    required this.citedSourceCount,
    required this.linkedReferenceCount,
    required this.issueCount,
  });

  final int citedSourceCount;
  final int linkedReferenceCount;
  final int issueCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _SourceManagerChip(icon: Icons.format_quote_rounded, label: '$citedSourceCount cited'),
        _SourceManagerChip(icon: Icons.source_outlined, label: '$linkedReferenceCount linked'),
        _SourceManagerChip(icon: Icons.rule_rounded, label: '$issueCount checks'),
      ],
    );
  }
}

class _SourceManagerChip extends StatelessWidget {
  const _SourceManagerChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 15, color: colorScheme.primary),
      label: Text(label),
      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
    );
  }
}

class _SourceManagerActionStrip extends StatelessWidget {
  const _SourceManagerActionStrip({
    required this.duplicateCount,
    required this.onRepair,
    required this.onDeduplicate,
  });

  final int duplicateCount;
  final VoidCallback onRepair;
  final VoidCallback onDeduplicate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onRepair,
          icon: const Icon(Icons.build_circle_outlined, size: 17),
          label: const Text('Repair citations'),
        ),
        OutlinedButton.icon(
          onPressed: duplicateCount > 0 ? onDeduplicate : null,
          icon: const Icon(Icons.merge_type_rounded, size: 17),
          label: Text(duplicateCount > 0 ? 'Deduplicate ($duplicateCount)' : 'Deduplicate'),
        ),
      ],
    );
  }
}

@immutable
class _SourceManagerRowAction {
  const _SourceManagerRowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _SourceManagerSectionHeader extends StatelessWidget {
  const _SourceManagerSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CitationSourceManagerRow extends StatelessWidget {
  const _CitationSourceManagerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.actions = const <_SourceManagerRowAction>[],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;
  final List<_SourceManagerRowAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.trim().isEmpty ? 'Untitled source' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle.trim().isEmpty ? 'No metadata' : subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trailing,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final action in actions)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(action.icon, size: 15),
                          label: Text(action.label),
                          onPressed: action.onPressed,
                        ),
                    ],
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

class _SourceManagerEmptyState extends StatelessWidget {
  const _SourceManagerEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _SourceOccurrence {
  const _SourceOccurrence({
    required this.blockId,
    required this.blockIndex,
    required this.offset,
    required this.snippet,
  });

  factory _SourceOccurrence.fromBlock(TextSystemBlock block, int blockIndex, int offset) {
    final text = block.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final safeOffset = offset.clamp(0, text.length).toInt();
    final start = (safeOffset - 50).clamp(0, text.length).toInt();
    final end = (safeOffset + 90).clamp(start, text.length).toInt();
    var snippet = text.substring(start, end).trim();
    if (start > 0) snippet = '…$snippet';
    if (end < text.length) snippet = '$snippet…';
    if (snippet.isEmpty) snippet = block.type.name;
    return _SourceOccurrence(
      blockId: block.id,
      blockIndex: blockIndex,
      offset: offset,
      snippet: snippet,
    );
  }

  final String blockId;
  final int blockIndex;
  final int offset;
  final String snippet;
}

@immutable
class _SourceManagerIssue {
  const _SourceManagerIssue(this.title, this.sourceLabel);

  final String title;
  final String sourceLabel;
}

class _SourceManagerIssueRow extends StatelessWidget {
  const _SourceManagerIssueRow({required this.issue});

  final _SourceManagerIssue issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issue.title, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      issue.sourceLabel.trim().isEmpty ? 'Untitled source' : issue.sourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
}

class _ReferenceBridgeCard extends StatelessWidget {
  const _ReferenceBridgeCard({
    required this.index,
    required this.onNavigateToBlock,
  });

  final TextSystemReferenceIndex index;
  final ValueChanged<String> onNavigateToBlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewReferences = index.navigationPreview;

    Widget bucketChip(TextSystemReferenceBucket bucket) {
      return Chip(
        avatar: Icon(_iconForReferenceKind(bucket.kind), size: 16),
        label: Text('${bucket.label}: ${bucket.count}'),
        visualDensity: VisualDensity.compact,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, size: 18, color: colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'References & sources',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Bridge document text to citations, sources, todos, projects, links, figures, and tables.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (index.isEmpty) ...[
              Text(
                'No structured references yet. Future source/citation actions will populate this panel.',
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: const [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.format_quote_rounded, size: 16),
                    label: Text('Citations'),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.source_outlined, size: 16),
                    label: Text('Sources'),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.image_outlined, size: 16),
                    label: Text('Figures'),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.table_chart_outlined, size: 16),
                    label: Text('Tables'),
                  ),
                ],
              ),
            ] else ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final bucket in index.buckets.take(6)) bucketChip(bucket),
                ],
              ),
              const SizedBox(height: 12),
              Text('Reference map', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final reference in previewReferences)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Material(
                    color: colorScheme.surface.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onNavigateToBlock(reference.blockId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _iconForReferenceKind(reference.kind),
                              size: 15,
                              color: colorScheme.secondary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reference.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _subtitleForReference(reference),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              reference.pageLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (index.totalCount > previewReferences.length)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+ ${index.totalCount - previewReferences.length} more references',
                    style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Text(
              'Next bridge: create citations/source links from selected text and connect them to the library/PDF system.',
              style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForReferenceKind(TextSystemStructureReferenceKind kind) {
    return switch (kind) {
      TextSystemStructureReferenceKind.citation => Icons.format_quote_rounded,
      TextSystemStructureReferenceKind.source => Icons.source_outlined,
      TextSystemStructureReferenceKind.link => Icons.link_rounded,
      TextSystemStructureReferenceKind.footnote => Icons.notes_rounded,
      TextSystemStructureReferenceKind.project => Icons.folder_copy_outlined,
      TextSystemStructureReferenceKind.todo => Icons.check_circle_outline_rounded,
      TextSystemStructureReferenceKind.figure => Icons.image_outlined,
      TextSystemStructureReferenceKind.table => Icons.table_chart_outlined,
      TextSystemStructureReferenceKind.equation => Icons.functions_rounded,
      TextSystemStructureReferenceKind.unknown => Icons.hub_outlined,
    };
  }

  String _subtitleForReference(TextSystemStructureReference reference) {
    final details = <String>[
      reference.kind.label,
      if (reference.role != null && reference.role!.trim().isNotEmpty) reference.role!.trim(),
      if (reference.targetId != null && reference.targetId!.trim().isNotEmpty) 'target ${reference.targetId}',
      if (reference.url != null && reference.url!.trim().isNotEmpty) reference.url!.trim(),
    ];
    return details.join(' · ');
  }
}


class _PageFurnitureCard extends StatelessWidget {
  const _PageFurnitureCard({
    required this.pageFurniture,
    required this.onChanged,
  });

  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture> onChanged;

  void _setPageNumbersEnabled(bool enabled) {
    onChanged(
      pageFurniture.copyWith(
        pageNumbers: pageFurniture.pageNumbers.copyWith(enabled: enabled),
      ),
    );
  }

  void _setShowOnFirstPage(bool showOnFirstPage) {
    onChanged(
      pageFurniture.copyWith(
        pageNumbers: pageFurniture.pageNumbers.copyWith(showOnFirstPage: showOnFirstPage),
      ),
    );
  }

  void _setPageNumberPosition(TextSystemPageNumberPosition position) {
    onChanged(
      pageFurniture.copyWith(
        pageNumbers: pageFurniture.pageNumbers.copyWith(position: position),
      ),
    );
  }

  void _setDocumentTitleHeader(bool enabled) {
    onChanged(
      pageFurniture.copyWith(
        headerMode: enabled ? TextSystemPageHeaderMode.documentTitle : TextSystemPageHeaderMode.none,
      ),
    );
  }

  void _setEditableHeaderFooterEnabled(bool enabled) {
    onChanged(
      pageFurniture.copyWith(
        headerFooter: pageFurniture.headerFooter.copyWith(enabled: enabled),
      ),
    );
  }

  void _setDifferentFirstPage(bool enabled) {
    onChanged(
      pageFurniture.copyWith(
        headerFooter: pageFurniture.headerFooter.copyWith(differentFirstPage: enabled),
      ),
    );
  }

  void _insertDefaultFooterPageNumberToken() {
    onChanged(
      pageFurniture.copyWith(
        headerFooter: pageFurniture.headerFooter.copyWith(
          primaryFooter: pageFurniture.headerFooter.primaryFooter.copyWith(
            enabled: true,
            text: 'Page {{pageNumber}}',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Page furniture', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Editable page-margin header/footer zones in Real pages. Tokens: {{pageNumber}}, {{documentTitle}}, {{sectionTitle}}.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Editable header/footer'),
                  selected: pageFurniture.headerFooter.enabled,
                  onSelected: _setEditableHeaderFooterEnabled,
                ),
                FilterChip(
                  label: const Text('Different first page'),
                  selected: pageFurniture.headerFooter.differentFirstPage,
                  onSelected: pageFurniture.headerFooter.enabled ? _setDifferentFirstPage : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.tag_rounded, size: 16),
                  label: const Text('Footer token: page number'),
                  onPressed: pageFurniture.headerFooter.enabled ? _insertDefaultFooterPageNumberToken : null,
                ),
                FilterChip(
                  label: const Text('Legacy page numbers'),
                  selected: pageFurniture.pageNumbers.enabled,
                  onSelected: _setPageNumbersEnabled,
                ),
                FilterChip(
                  label: const Text('Show on first page'),
                  selected: pageFurniture.pageNumbers.showOnFirstPage,
                  onSelected: pageFurniture.pageNumbers.enabled ? _setShowOnFirstPage : null,
                ),
                FilterChip(
                  label: const Text('Header: document title'),
                  selected: pageFurniture.headerMode == TextSystemPageHeaderMode.documentTitle,
                  onSelected: _setDocumentTitleHeader,
                ),
                PopupMenuButton<TextSystemPageNumberPosition>(
                  enabled: pageFurniture.pageNumbers.enabled,
                  tooltip: 'Page number position',
                  initialValue: pageFurniture.pageNumbers.position,
                  onSelected: _setPageNumberPosition,
                  itemBuilder: (context) {
                    return [
                      for (final position in TextSystemPageNumberPosition.values)
                        PopupMenuItem<TextSystemPageNumberPosition>(
                          value: position,
                          child: Text(position.label),
                        ),
                    ];
                  },
                  child: Chip(
                    avatar: const Icon(Icons.pin_drop_outlined, size: 16),
                    label: Text(pageFurniture.pageNumbers.position.label),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _PageProgressCard extends StatelessWidget {
  const _PageProgressCard({
    required this.sectionMetrics,
    required this.targetPageCount,
    required this.onTargetPageCountChanged,
  });

  final TextSystemSectionPageMetricsResult sectionMetrics;
  final double targetPageCount;
  final ValueChanged<double> onTargetPageCountChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ratio = sectionMetrics.completionRatio;
    final overTarget = sectionMetrics.isOverTarget;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: overTarget
            ? colorScheme.errorContainer.withValues(alpha: 0.38)
            : colorScheme.primaryContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: overTarget
              ? colorScheme.error.withValues(alpha: 0.28)
              : colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flag_circle_outlined,
                  size: 19,
                  color: overTarget ? colorScheme.error : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Page progress',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Decrease target pages',
                  onPressed: targetPageCount <= 1 ? null : () => onTargetPageCountChanged(targetPageCount - 1),
                  icon: const Icon(Icons.remove_rounded, size: 16),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    sectionMetrics.targetPagesLabel,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Increase target pages',
                  onPressed: () => onTargetPageCountChanged(targetPageCount + 1),
                  icon: const Icon(Icons.add_rounded, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              color: overTarget ? colorScheme.error : colorScheme.primary,
              backgroundColor: colorScheme.surface.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              sectionMetrics.progressLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: overTarget ? colorScheme.error : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _WritingPlanCard extends StatelessWidget {
  const _WritingPlanCard({
    required this.workPlan,
    required this.planningHorizonDays,
    required this.onPlanningHorizonDaysChanged,
  });

  final TextSystemPageWorkPlan workPlan;
  final int planningHorizonDays;
  final ValueChanged<int> onPlanningHorizonDaysChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Color accentColor;
    final IconData icon;

    if (workPlan.hasUrgentSignals) {
      accentColor = colorScheme.error;
      icon = Icons.priority_high_rounded;
    } else if (workPlan.hasWarningSignals) {
      accentColor = colorScheme.tertiary;
      icon = Icons.warning_amber_rounded;
    } else {
      accentColor = colorScheme.primary;
      icon = Icons.track_changes_rounded;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Writing plan',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Shorter planning horizon',
                  onPressed: planningHorizonDays <= 1
                      ? null
                      : () => onPlanningHorizonDaysChanged(planningHorizonDays - 1),
                  icon: const Icon(Icons.remove_rounded, size: 16),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    workPlan.planningHorizonLabel,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Longer planning horizon',
                  onPressed: planningHorizonDays >= 30
                      ? null
                      : () => onPlanningHorizonDaysChanged(planningHorizonDays + 1),
                  icon: const Icon(Icons.add_rounded, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              workPlan.headline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _WorkSignalList(workPlan: workPlan),
          ],
        ),
      ),
    );
  }
}

class _WorkSignalList extends StatelessWidget {
  const _WorkSignalList({required this.workPlan});

  final TextSystemPageWorkPlan workPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final signal in workPlan.signals.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconForSeverity(signal.severity),
                  size: 16,
                  color: _colorForSeverity(colorScheme, signal.severity),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signal.title,
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        signal.message,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _iconForSeverity(TextSystemPageWorkSignalSeverity severity) {
    return switch (severity) {
      TextSystemPageWorkSignalSeverity.urgent => Icons.error_outline_rounded,
      TextSystemPageWorkSignalSeverity.warning => Icons.warning_amber_rounded,
      TextSystemPageWorkSignalSeverity.info => Icons.info_outline_rounded,
    };
  }

  Color _colorForSeverity(ColorScheme colorScheme, TextSystemPageWorkSignalSeverity severity) {
    return switch (severity) {
      TextSystemPageWorkSignalSeverity.urgent => colorScheme.error,
      TextSystemPageWorkSignalSeverity.warning => colorScheme.tertiary,
      TextSystemPageWorkSignalSeverity.info => colorScheme.primary,
    };
  }
}

class _LongestSectionList extends StatelessWidget {
  const _LongestSectionList({required this.sectionMetrics});

  final TextSystemSectionPageMetricsResult sectionMetrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sections = sectionMetrics.longestSections;

    if (sections.isEmpty) {
      return Text(
        'No section page spans yet. Add headings to make page intelligence useful.',
        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
      );
    }

    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Longest sections', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      section.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SectionSpanChip(label: section.detailedLabel),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PremiumWriterStatusBar extends StatelessWidget {
  const _PremiumWriterStatusBar({
    required this.saveState,
    required this.revision,
    required this.transactionCount,
    required this.wordCount,
    required this.characterCount,
    required this.outlineCount,
    required this.pageSetup,
    required this.pageFurniture,
    required this.pageEstimate,
    required this.pageLayout,
    required this.pageMap,
    required this.sectionMetrics,
    required this.workPlan,
    required this.documentStructure,
    required this.pageMode,
    this.pageViewport,
  });

  final TextSystemSaveState saveState;
  final int revision;
  final int transactionCount;
  final int wordCount;
  final int characterCount;
  final int outlineCount;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final TextSystemPageEstimate pageEstimate;
  final TextSystemPageLayout pageLayout;
  final TextSystemPageMap pageMap;
  final TextSystemSectionPageMetricsResult sectionMetrics;
  final TextSystemPageWorkPlan workPlan;
  final TextSystemDocumentStructure documentStructure;
  final _PremiumWriterPageMode pageMode;
  final TextSystemPageViewport? pageViewport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconForSaveStatus(saveState.status), size: 15, color: _colorForSaveStatus(colorScheme, saveState.status)),
                  const SizedBox(width: 6),
                  Text(saveState.message ?? saveState.status.name),
                ],
              ),
              Text(pageMode.label),
              Text(pageEstimate.statusLabel, style: TextStyle(color: pageEstimate.isOverLimit ? colorScheme.error : colorScheme.onSurfaceVariant)),
              Text(pageMap.pageLabel),
              Text(sectionMetrics.progressLabel),
              Text(workPlan.paceLabel),
              Text(documentStructure.compactLabel),
              if (pageViewport != null) Text(pageViewport!.currentPageLabel),
              if (pageViewport != null) Text(pageViewport!.mountedRangeLabel),
              Text(pageSetup.size.label),
              Text(pageFurniture.shortLabel),
              Text('${pageLayout.anchors.length} anchors'),
              Text('~${pageEstimate.estimatedWordsPerPage} words/page'),
              Text('$wordCount words'),
              Text('$characterCount chars'),
              Text('$outlineCount headings'),
              Text('Revision $revision'),
              Text('$transactionCount transactions'),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForSaveStatus(TextSystemSaveStatus status) {
    return switch (status) {
      TextSystemSaveStatus.failed => Icons.error_rounded,
      TextSystemSaveStatus.saving => Icons.sync_rounded,
      TextSystemSaveStatus.dirty => Icons.edit_rounded,
      _ => Icons.check_circle_rounded,
    };
  }

  Color _colorForSaveStatus(ColorScheme colorScheme, TextSystemSaveStatus status) {
    return switch (status) {
      TextSystemSaveStatus.failed => colorScheme.error,
      TextSystemSaveStatus.dirty => colorScheme.tertiary,
      _ => colorScheme.primary,
    };
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label, style: Theme.of(context).textTheme.labelMedium),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      ),
    );
  }
}

class _PremiumOutlineItem {
  const _PremiumOutlineItem({
    required this.blockId,
    required this.text,
    required this.level,
    required this.index,
    this.todoCount = 0,
    this.noteCount = 0,
    this.dueSoonCount = 0,
    this.overdueCount = 0,
    this.pageAnchor,
    this.sectionMetric,
  });

  final String blockId;
  final String text;
  final int level;
  final int index;
  final int todoCount;
  final int noteCount;
  final int dueSoonCount;
  final int overdueCount;
  final TextSystemPageAnchor? pageAnchor;
  final TextSystemSectionPageMetric? sectionMetric;

  String get pageLabel => sectionMetric?.pageLabel ?? pageAnchor?.pageLabel ?? 'p. ?';
  String? get sectionSpanLabel => sectionMetric?.pageSpanLabel;

  _ProjectSignalSeverity get deadlineSeverity {
    if (overdueCount > 0) return _ProjectSignalSeverity.overdue;
    if (dueSoonCount > 0) return _ProjectSignalSeverity.dueSoon;
    return _ProjectSignalSeverity.normal;
  }
}
