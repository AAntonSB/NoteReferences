import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../notes/data/note_repository.dart';
import '../data/epub_reader_loader.dart';
import '../data/epub_reader_position_repository.dart';
import '../domain/reader_document_ref.dart';
import '../domain/source_reader_workspace_layout.dart';
import 'source_reader_integration_placeholder.dart';
import 'source_reader_split_layout.dart';
import 'source_reader_workspace_selector.dart';
import 'epub_sidecar_notes_canvas.dart';

class EpubReaderScreen extends StatefulWidget {
  final AppDatabase database;
  final ReaderDocumentRef document;

  const EpubReaderScreen({
    super.key,
    required this.database,
    required this.document,
  });

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _loader = EpubReaderLoader();
  final _positionRepository = const EpubReaderPositionRepository();
  late final NoteRepository _noteRepository = NoteRepository(widget.database);

  EpubReaderBook? _book;
  PageController? _pageController;
  String? _errorMessage;
  bool _loading = true;
  int _spineIndex = 0;
  SourceReaderWorkspaceLayout _workspaceLayout = SourceReaderWorkspaceLayout.sidecar;
  double _readerPaneFraction = 0.5;
  double _fontSize = 18;
  double _lineHeight = 1.55;

  final Map<int, EpubReaderSpineItem> _loadedSections = <int, EpubReaderSpineItem>{};
  final Set<int> _loadingSections = <int>{};

  static const double _dividerWidth = 8.0;
  static const double _minPaneWidth = 280.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _loadedSections.clear();
      _loadingSections.clear();
    });

    try {
      final book = await _loader.load(File(widget.document.filePath));
      final savedPosition = await _positionRepository.load(widget.document.documentId);
      final index = _clampSpineIndex(savedPosition?.spineIndex ?? 0, book);
      if (!mounted) return;
      _pageController?.dispose();
      _pageController = PageController(initialPage: index);
      setState(() {
        _book = book;
        _spineIndex = index;
        _loading = false;
      });
      _ensureWindowLoaded(index);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  int _clampSpineIndex(int index, EpubReaderBook book) {
    if (book.spine.isEmpty) return 0;
    return index.clamp(0, book.spine.length - 1).toInt();
  }

  Future<void> _selectSpineIndex(int index) async {
    final book = _book;
    if (book == null || book.spine.isEmpty) return;
    final nextIndex = _clampSpineIndex(index, book);
    setState(() => _spineIndex = nextIndex);
    _ensureWindowLoaded(nextIndex);
    await _saveCurrentPosition(spineIndex: nextIndex);

    final controller = _pageController;
    if (controller == null) return;
    if (!controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !controller.hasClients) return;
        controller.jumpToPage(nextIndex);
      });
      return;
    }
    await controller.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePageChanged(int index) {
    final book = _book;
    if (book == null) return;
    final nextIndex = _clampSpineIndex(index, book);
    if (nextIndex == _spineIndex) {
      _ensureWindowLoaded(nextIndex);
      return;
    }
    setState(() => _spineIndex = nextIndex);
    _ensureWindowLoaded(nextIndex);
    _saveCurrentPosition(spineIndex: nextIndex);
  }

  void _adjustFontSize(double delta) {
    setState(() {
      _fontSize = (_fontSize + delta).clamp(14, 28).toDouble();
      _lineHeight = _fontSize >= 22 ? 1.45 : 1.55;
    });
    _saveCurrentPosition(spineIndex: _spineIndex);
  }

  void _ensureWindowLoaded(int centerIndex) {
    final book = _book;
    if (book == null || book.spine.isEmpty) return;

    final indexes = <int>{
      centerIndex,
      if (centerIndex > 0) centerIndex - 1,
      if (centerIndex < book.spine.length - 1) centerIndex + 1,
    };

    for (final index in indexes) {
      _loadSection(index);
    }

    _loadedSections.removeWhere((index, _) => (index - centerIndex).abs() > 2);
  }

  Future<void> _loadSection(int index) async {
    final book = _book;
    if (book == null || index < 0 || index >= book.spine.length) return;
    if (_loadedSections.containsKey(index) || _loadingSections.contains(index)) return;

    setState(() => _loadingSections.add(index));
    try {
      final item = await _loader.loadSpineItem(
        File(widget.document.filePath),
        book,
        index,
      );
      if (!mounted || _book != book) return;
      setState(() {
        _loadedSections[index] = item;
        _loadingSections.remove(index);
      });
    } catch (_) {
      if (!mounted || _book != book) return;
      setState(() => _loadingSections.remove(index));
    }
  }

  Future<void> _saveCurrentPosition({required int spineIndex}) {
    return _positionRepository.save(
      documentId: widget.document.documentId,
      spineIndex: spineIndex,
      pageIndex: 0,
    );
  }

  void _closeReader() {
    Navigator.of(context).maybePop();
  }

  EpubReaderSpineItem? _currentReaderItem() {
    final book = _book;
    if (book == null || book.spine.isEmpty) return null;
    final index = _clampSpineIndex(_spineIndex, book);
    return _loadedSections[index] ?? book.spine[index];
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final hasContents = book != null && book.toc.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close reader',
          onPressed: _closeReader,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.document.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              _workspaceSubtitle(book) ?? 'EPUB source reader',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (hasContents)
            IconButton(
              tooltip: 'Contents',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.list_alt_rounded),
            ),
          IconButton(
            tooltip: 'Smaller text',
            onPressed: () => _adjustFontSize(-1),
            icon: const Icon(Icons.text_decrease_rounded),
          ),
          IconButton(
            tooltip: 'Larger text',
            onPressed: () => _adjustFontSize(1),
            icon: const Icon(Icons.text_increase_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: hasContents
          ? Drawer(
              width: 360,
              child: _EpubTocPanel(
                book: book!,
                selectedSpineIndex: _spineIndex,
                closeOnSelect: true,
                onSelectSpineIndex: _selectSpineIndex,
              ),
            )
          : null,
      body: Column(
        children: [
          _buildWorkspaceSelector(),
          Expanded(child: _buildWorkspaceBody()),
        ],
      ),
    );
  }

  Widget _buildWorkspaceSelector() {
    final theme = Theme.of(context);

    return SourceReaderWorkspaceSelector(
      selected: _workspaceLayout,
      readerIcon: Icons.menu_book_outlined,
      onChanged: (layout) => setState(() => _workspaceLayout = layout),
      trailing: Chip(
        avatar: const Icon(Icons.auto_stories_rounded, size: 18),
        label: const Text('EPUB surface'),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
    );
  }

  Widget _buildWorkspaceBody() {
    return switch (_workspaceLayout) {
      SourceReaderWorkspaceLayout.reader => _buildReaderBody(context),
      SourceReaderWorkspaceLayout.sidecar => _buildTwoPaneBody(
          paneBuilder: _buildSidecarPane,
        ),
      SourceReaderWorkspaceLayout.document => _buildTwoPaneBody(
          paneBuilder: () => _buildIntegrationPlaceholderPane(
            icon: Icons.article_outlined,
            title: 'Document notes for EPUB',
            message:
                'This EPUB now occupies the same reader workspace slot as PDFs. The next integration step is to connect EPUB anchors to the document-notes panel instead of using a PDF-only source model.',
          ),
        ),
      SourceReaderWorkspaceLayout.workspaceDocument => _buildTwoPaneBody(
          paneBuilder: () => _buildIntegrationPlaceholderPane(
            icon: Icons.edit_document,
            title: 'Writing beside EPUB',
            message:
                'This slot mirrors the PDF reader writing workspace. EPUB project assignment and workspace-document embedding will be wired through the shared reader source model next.',
          ),
        ),
      SourceReaderWorkspaceLayout.synthesis => _buildSynthesisBody(),
    };
  }

  Widget _buildSidecarPane() {
    final currentItem = _currentReaderItem();
    if (!_canShowSidecar || currentItem == null) {
      return _buildIntegrationPlaceholderPane(
        icon: Icons.view_sidebar_outlined,
        title: 'EPUB sidecar',
        message: _loading
            ? 'Loading the current EPUB reader section before the sidecar can attach to it.'
            : 'Open a readable EPUB section to place sidecar notes beside it.',
      );
    }

    return EpubSidecarNotesCanvas(
      noteRepository: _noteRepository,
      document: widget.document,
      spineIndex: currentItem.index,
      href: currentItem.href,
      sectionTitle: currentItem.title,
      paragraphs: currentItem.paragraphs,
      onClose: () => setState(() => _workspaceLayout = SourceReaderWorkspaceLayout.reader),
      onRequestJumpToParagraph: (paragraphIndex) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Paragraph ${paragraphIndex + 1} is already in the current EPUB section. Text-range reveal will be wired in the selection phase.',
            ),
          ),
        );
      },
    );
  }

  Widget _buildTwoPaneBody({required Widget Function() paneBuilder}) {
    return SourceReaderTwoPaneLayout(
      readerBuilder: () => _buildReaderBody(context),
      paneBuilder: paneBuilder,
      paneFraction: _readerPaneFraction,
      minPaneWidth: _minPaneWidth,
      dividerWidth: _dividerWidth,
      onPaneFractionChanged: (fraction) {
        setState(() => _readerPaneFraction = fraction);
      },
    );
  }

  Widget _buildSynthesisBody() {
    return SourceReaderSynthesisLayout(
      readerBuilder: () => _buildReaderBody(context),
      sidecarBuilder: _buildSidecarPane,
      synthesisBuilder: () => _buildIntegrationPlaceholderPane(
        icon: Icons.view_column_outlined,
        title: 'EPUB synthesis slot',
        message:
            'This mirrors the PDF synthesis workspace. The EPUB reader surface is now in the correct slot; source extraction and synthesis actions will attach to EPUB anchors in the next integration passes.',
      ),
      fallbackBuilder: () => _buildTwoPaneBody(paneBuilder: _buildSidecarPane),
      minPaneWidth: _minPaneWidth,
      dividerWidth: _dividerWidth,
    );
  }

  Widget _buildIntegrationPlaceholderPane({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return SourceReaderIntegrationPlaceholder(
      icon: icon,
      title: title,
      message: message,
    );
  }

  bool get _canShowSidecar {
    final book = _book;
    return !_loading && _errorMessage == null && book != null && book.hasReadableContent;
  }

  String? _workspaceSubtitle(EpubReaderBook? book) {
    final author = book?.author?.trim();
    if (author != null && author.isNotEmpty) return author;
    if (book == null) return 'EPUB reader';
    return 'EPUB · ${book.spine.length} reader sections';
  }

  Widget _buildReaderBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return _EpubReaderErrorView(
        message: errorMessage,
        onRetry: _load,
      );
    }

    final book = _book;
    final controller = _pageController;
    if (book == null || controller == null || book.spine.isEmpty || !book.hasReadableContent) {
      return _EpubReaderErrorView(
        message: 'This EPUB was imported, but no readable spine content could be found for the reader surface.',
        onRetry: _load,
      );
    }

    return _EpubVirtualReaderPane(
      book: book,
      selectedSpineIndex: _spineIndex,
      pageController: controller,
      loadedSections: _loadedSections,
      loadingSections: _loadingSections,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      onPreviousSection: _spineIndex > 0 ? () => _selectSpineIndex(_spineIndex - 1) : null,
      onNextSection: _spineIndex < book.spine.length - 1 ? () => _selectSpineIndex(_spineIndex + 1) : null,
      onPageChanged: _handlePageChanged,
    );
  }
}

class _EpubVirtualReaderPane extends StatelessWidget {
  final EpubReaderBook book;
  final int selectedSpineIndex;
  final PageController pageController;
  final Map<int, EpubReaderSpineItem> loadedSections;
  final Set<int> loadingSections;
  final double fontSize;
  final double lineHeight;
  final VoidCallback? onPreviousSection;
  final VoidCallback? onNextSection;
  final ValueChanged<int> onPageChanged;

  const _EpubVirtualReaderPane({
    required this.book,
    required this.selectedSpineIndex,
    required this.pageController,
    required this.loadedSections,
    required this.loadingSections,
    required this.fontSize,
    required this.lineHeight,
    required this.onPreviousSection,
    required this.onNextSection,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedItem = loadedSections[selectedSpineIndex] ?? book.spine[selectedSpineIndex];
    final selectedLoaded = loadedSections.containsKey(selectedSpineIndex);

    return Column(
      children: [
        Material(
          color: colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Previous section',
                  onPressed: onPreviousSection,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedItem.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selectedLoaded
                            ? 'Virtual reader window · Section ${selectedSpineIndex + 1} of ${book.spine.length} · ${selectedItem.wordCount} words loaded'
                            : 'Virtual reader window · Section ${selectedSpineIndex + 1} of ${book.spine.length} · loading this section only',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: 'Next section',
                  onPressed: onNextSection,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textStyle = theme.textTheme.bodyLarge?.copyWith(
                    fontSize: fontSize,
                    height: lineHeight,
                    color: colorScheme.onSurface,
                  ) ??
                  TextStyle(
                    fontSize: fontSize,
                    height: lineHeight,
                    color: colorScheme.onSurface,
                  );
              final titleStyle = theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ) ??
                  const TextStyle(fontWeight: FontWeight.w900, height: 1.15);
              final textWidth = math.min(760.0, math.max(280.0, constraints.maxWidth - 64));

              return PageView.builder(
                controller: pageController,
                itemCount: book.spine.length,
                onPageChanged: onPageChanged,
                allowImplicitScrolling: false,
                itemBuilder: (context, index) {
                  final item = loadedSections[index] ?? book.spine[index];
                  final loading = loadingSections.contains(index) && !loadedSections.containsKey(index);
                  return _EpubVirtualSectionPage(
                    item: item,
                    loading: loading,
                    sectionLabel: 'Section ${index + 1} of ${book.spine.length}',
                    textWidth: textWidth,
                    titleStyle: titleStyle,
                    textStyle: textStyle,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EpubVirtualSectionPage extends StatelessWidget {
  final EpubReaderSpineItem item;
  final bool loading;
  final String sectionLabel;
  final double textWidth;
  final TextStyle titleStyle;
  final TextStyle textStyle;

  const _EpubVirtualSectionPage({
    required this.item,
    required this.loading,
    required this.sectionLabel,
    required this.textWidth,
    required this.titleStyle,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paragraphs = item.paragraphs;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: textWidth),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
          itemCount: loading ? 2 : paragraphs.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Text(
                            sectionLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(item.title, style: titleStyle),
                    const SizedBox(height: 6),
                    Text(
                      loading
                          ? 'Loading only this reader section and its immediate neighbors.'
                          : '${item.wordCount} words · ${paragraphs.length} paragraphs',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (loading) {
              return const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (paragraphs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'No readable text was extracted for this section.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }

            final paragraph = paragraphs[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText(
                paragraph,
                style: textStyle,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EpubTocPanel extends StatelessWidget {
  final EpubReaderBook book;
  final int selectedSpineIndex;
  final ValueChanged<int> onSelectSpineIndex;
  final bool closeOnSelect;

  const _EpubTocPanel({
    required this.book,
    required this.selectedSpineIndex,
    required this.onSelectSpineIndex,
    this.closeOnSelect = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = book.toc.isEmpty
        ? <EpubReaderTocEntry>[
            for (final item in book.spine)
              EpubReaderTocEntry(
                title: item.title,
                href: item.href,
                spineIndex: item.index,
                level: 0,
              ),
          ]
        : book.toc;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Contents',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${entries.length} entries · ${book.spine.length} reader sections',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final selected = entry.spineIndex == selectedSpineIndex;
                  return Padding(
                    padding: EdgeInsets.only(left: (entry.level.clamp(0, 4) * 12).toDouble()),
                    child: ListTile(
                      dense: true,
                      selected: selected,
                      selectedTileColor: colorScheme.primaryContainer.withOpacity(0.7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Section ${entry.spineIndex + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        if (closeOnSelect) Navigator.of(context).maybePop();
                        onSelectSpineIndex(entry.spineIndex);
                      },
                    ),
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

class _EpubReaderErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _EpubReaderErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 38, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Could not open EPUB',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
