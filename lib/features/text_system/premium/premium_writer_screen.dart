import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../fluent/fluent_document_command_controller.dart';
import '../page/text_system_layout_style_resolver.dart';
import '../page/text_system_page_canvas.dart';
import '../page/text_system_page_estimator.dart';
import '../page/text_system_page_layout.dart';
import '../page/text_system_page_map.dart';
import '../page/text_system_pagination_engine.dart';
import '../page/text_system_section_page_metrics.dart';
import '../page/text_system_page_work_plan.dart';
import '../page/text_system_paged_block_surface.dart';
import '../page/text_system_page_setup.dart';
import '../page/text_system_page_furniture.dart';
import '../page/text_system_page_viewport.dart';
import '../references/actions/text_system_reference_actions.dart';
import '../text_system.dart';

/// Full-screen long-form writing shell built on the project-wide text system.
///
/// Phase 12E adds scroll-aware page viewport metadata and a future render-window plan on top of page setup.
/// The writer still uses a single fluent document surface, while the page
/// presentation now understands page size, margins, orientation, and page limits.
class PremiumWriterScreen extends StatefulWidget {
  const PremiumWriterScreen({
    super.key,
    this.textController,
    this.autosaveController,
    this.initialDocument,
    this.screenTitle = 'Premium Writer',
    this.showInspectorByDefault = false,
  });

  final TextSystemController? textController;
  final TextSystemAutosaveController? autosaveController;
  final TextSystemDocument? initialDocument;
  final String screenTitle;
  final bool showInspectorByDefault;

  @override
  State<PremiumWriterScreen> createState() => _PremiumWriterScreenState();
}


enum _PremiumWriterPageMode {
  pageless,
  hybrid,
  chromeOnly,
  pagedBlocksExperimental;

  String get label {
    return switch (this) {
      _PremiumWriterPageMode.pageless => 'Pageless',
      _PremiumWriterPageMode.hybrid => 'Hybrid pages',
      _PremiumWriterPageMode.chromeOnly => 'Page chrome',
      _PremiumWriterPageMode.pagedBlocksExperimental => 'Real pages experiment',
    };
  }

  String get description {
    return switch (this) {
      _PremiumWriterPageMode.pageless => 'Continuous writing surface. No page chrome or break markers.',
      _PremiumWriterPageMode.hybrid => 'Continuous editor with physical page chrome and measured page-break markers.',
      _PremiumWriterPageMode.chromeOnly => 'Continuous editor with physical page frames only.',
      _PremiumWriterPageMode.pagedBlocksExperimental => 'Fresh block-level page surface. Blocks/fragments are laid out inside real pages with experimental structural editing.',
    };
  }
}

class _PremiumWriterScreenState extends State<PremiumWriterScreen> {
  late final bool _ownsTextController;
  late final bool _ownsAutosaveController;
  late final TextSystemController _textController;
  late final InMemoryTextSystemPersistenceAdapter _persistenceAdapter;
  late final TextSystemAutosaveController _autosaveController;
  late final FluentDocumentCommandController _fluentCommands;
  late final TextSystemReferenceActionRepository _referenceActionRepository;
  late final ScrollController _pageScrollController;

  bool _overviewExpanded = false;
  bool _showToolbar = true;
  bool _showInspector = false;
  bool _focusMode = false;
  bool _widePage = false;
  bool _showMarginGuides = true;
  bool _showDetailedPageBreakLabels = true;
  _PremiumWriterPageMode _pageMode = _PremiumWriterPageMode.hybrid;
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
    _referenceActionRepository = TextSystemMemoryReferenceActionRepository(
      seedTargets: TextSystemReferenceActionRepositorySeed.academicDemoTargets(),
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

    _persistenceAdapter = InMemoryTextSystemPersistenceAdapter()..seed(_textController.document);
    _ownsAutosaveController = widget.autosaveController == null;
    _autosaveController = widget.autosaveController ??
        TextSystemAutosaveController(
          textController: _textController,
          persistenceAdapter: _persistenceAdapter,
        );
  }

  @override
  void dispose() {
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

  Future<void> _saveNow() async {
    await _autosaveController.saveNow(message: 'Saved premium writer draft.');
  }

  void _resetDemo() {
    _textController.replaceDocument(_seedDocument(), label: 'Reset premium writer demo');
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _buildReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Premium writer report copied.')),
    );
  }

  Future<void> _exportDocument(TextSystemExportFormat format) async {
    final exportDocument = _documentWithPremiumWriterDemoListFix(_textController.document);
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
    final topChromeOffset = _pageMode == _PremiumWriterPageMode.pagedBlocksExperimental
        ? _estimatedPagedBlockSurfaceTopChromeOffset()
        : 0.0;

    return topChromeOffset + pageIndexOffset + intraPageOffset;
  }

  double _estimatedPagedBlockSurfaceTopChromeOffset() {
    // This is intentionally conservative. The exact toolbar/banner height is
    // responsive, but page navigation only needs to avoid landing above page 2+
    // when the paged-block surface is active.
    return _focusMode ? 96.0 : 132.0;
  }

  double _estimatedNavigationPageExtent() {
    final pageMaxWidth = _widePage ? 900.0 : 794.0;
    final pageWidth = pageMaxWidth * _pageSetup.visualWidthScaleRelativeToA4Portrait;
    final pageHeight = pageWidth * _pageSetup.heightToWidthRatio;
    final pageHeaderAndGap = _pageMode == _PremiumWriterPageMode.pagedBlocksExperimental ? 50.0 : 32.0;
    final pageGap = _pageMode == _PremiumWriterPageMode.pagedBlocksExperimental
        ? 76.0
        : (_focusMode ? 72.0 : 96.0);
    return pageHeaderAndGap + pageHeight + pageGap;
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
                tooltip: _focusMode ? 'Exit focus mode' : 'Enter focus mode',
                onPressed: () => setState(() => _focusMode = !_focusMode),
                icon: Icon(_focusMode ? Icons.center_focus_strong_rounded : Icons.center_focus_weak_rounded),
              ),
              PopupMenuButton<TextSystemExportFormat>(
                tooltip: 'Export document',
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
                tooltip: 'Copy writer report',
                onPressed: _copyReport,
                icon: const Icon(Icons.copy_all_rounded),
              ),
              IconButton(
                tooltip: 'Save now',
                onPressed: _saveNow,
                icon: const Icon(Icons.save_rounded),
              ),
              IconButton(
                tooltip: 'Reset demo document',
                onPressed: _ownsTextController ? _resetDemo : null,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_showToolbar && !_focusMode)
                _PremiumWriterToolbar(
                  commandController: _fluentCommands,
                  overviewExpanded: _overviewExpanded,
                  showInspector: _showInspector,
                  widePage: _widePage,
                  onToggleOverview: () => setState(() => _overviewExpanded = !_overviewExpanded),
                  onToggleInspector: () => setState(() => _showInspector = !_showInspector),
                  pageSetup: _pageSetup,
                  pageMode: _pageMode,
                  onPageModeChanged: (mode) => setState(() => _pageMode = mode),
                  onPageSetupChanged: (setup) => setState(() {
                    _pageSetup = setup;
                    final maxPages = setup.constraint.maxPages;
                    if (maxPages != null && maxPages > 0) {
                      _targetPageCount = maxPages.toDouble();
                    }
                  }),
                  onToggleWidePage: () => setState(() => _widePage = !_widePage),
                  showMarginGuides: _showMarginGuides,
                  onToggleMarginGuides: () => setState(() => _showMarginGuides = !_showMarginGuides),
                  showDetailedPageBreakLabels: _showDetailedPageBreakLabels,
                  onTogglePageBreakLabels: () => setState(() => _showDetailedPageBreakLabels = !_showDetailedPageBreakLabels),
                  onHideToolbar: () => setState(() => _showToolbar = false),
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
                        _PremiumWriterPageMode.pagedBlocksExperimental => TextSystemPagedBlockSurface(
                            textController: _textController,
                            document: document,
                            pageSetup: _pageSetup,
                            pageFurniture: _pageFurniture,
                            onPageFurnitureChanged: (value) => setState(() => _pageFurniture = value),
                            pageMaxWidth: pageMaxWidth,
                            focusMode: _focusMode,
                            showMarginGuides: _showMarginGuides,
                            scrollController: _pageScrollController,
                            referenceActionRepository: _referenceActionRepository,
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

class _PremiumWriterToolbar extends StatelessWidget {
  const _PremiumWriterToolbar({
    required this.commandController,
    required this.overviewExpanded,
    required this.showInspector,
    required this.widePage,
    required this.pageSetup,
    required this.pageMode,
    required this.onPageSetupChanged,
    required this.onPageModeChanged,
    required this.onToggleOverview,
    required this.onToggleInspector,
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
  final bool widePage;
  final TextSystemPageSetup pageSetup;
  final _PremiumWriterPageMode pageMode;
  final ValueChanged<TextSystemPageSetup> onPageSetupChanged;
  final ValueChanged<_PremiumWriterPageMode> onPageModeChanged;
  final bool showMarginGuides;
  final bool showDetailedPageBreakLabels;
  final VoidCallback onToggleOverview;
  final VoidCallback onToggleInspector;
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
        for (final mode in _PremiumWriterPageMode.values)
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
      tooltip: 'Page setup',
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

    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 700),
      child: Container(
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
          _MetricRow(label: 'Real pages surface', value: pageMode == _PremiumWriterPageMode.pagedBlocksExperimental ? 'experimental selectable block layout' : 'off'),
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
            'This panel is diagnostic. Phase 14B keeps pageless, hybrid, and page-chrome modes on the stable fluent editor, while Real pages mode uses the experimental block-level page surface. Complete text blocks are editable there; split page fragments remain preview-only until paragraph-fragment editing lands.',
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
