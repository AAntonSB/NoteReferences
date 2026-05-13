import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/text_system_controller.dart';
import '../fluent/fluent_document_buffer_mapper.dart';
import '../fluent/fluent_document_natural_editing_formatter.dart';
import '../persistence/text_system_autosave_controller.dart';
import 'text_system_page_setup.dart';
import 'text_system_page_viewport.dart';

@immutable
class TextSystemPagedDocumentMetrics {
  const TextSystemPagedDocumentMetrics({
    required this.pageWidthPx,
    required this.pageHeightPx,
    required this.pageContentWidthPx,
    required this.pageContentHeightPx,
    required this.pageMarginsPx,
    required this.pageTopOffsetPx,
    required this.pageGapPx,
    required this.pageExtentPx,
    required this.pageCount,
    required this.linesPerPage,
  });

  final double pageWidthPx;
  final double pageHeightPx;
  final double pageContentWidthPx;
  final double pageContentHeightPx;
  final EdgeInsets pageMarginsPx;
  final double pageTopOffsetPx;
  final double pageGapPx;
  final double pageExtentPx;
  final int pageCount;
  final int linesPerPage;

  String get physicalLabel => '${pageWidthPx.round()} × ${pageHeightPx.round()} px';
  String get contentLabel => '${pageContentWidthPx.round()} × ${pageContentHeightPx.round()} px content';
}

@immutable
class TextSystemPagedTextSlice {
  const TextSystemPagedTextSlice({
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  final String text;
  final int startOffset;
  final int endOffset;

  bool containsOffset(int offset) {
    if (startOffset == endOffset) return offset == startOffset;
    return offset >= startOffset && offset <= endOffset;
  }
}

/// Page-bound fluent document projection.
///
/// The source of truth is still [TextSystemController.document]. This widget is
/// only a paged presentation of the same fluent buffer used by
/// [FluentDocumentSurface]. In pageless mode the premium writer should still use
/// the normal continuous fluent surface.
class TextSystemPagedDocumentSurface extends StatefulWidget {
  const TextSystemPagedDocumentSurface({
    super.key,
    required this.textController,
    this.autosaveController,
    required this.pageSetup,
    this.pageMaxWidth = 794,
    this.focusMode = false,
    this.showMarginGuides = true,
    this.scrollController,
    this.onViewportChanged,
    this.cacheExtentPages = 2,
    this.readOnly = false,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController? autosaveController;
  final TextSystemPageSetup pageSetup;
  final double pageMaxWidth;
  final bool focusMode;
  final bool showMarginGuides;
  final ScrollController? scrollController;
  final ValueChanged<TextSystemPageViewport>? onViewportChanged;
  final int cacheExtentPages;
  final bool readOnly;

  @override
  State<TextSystemPagedDocumentSurface> createState() => _TextSystemPagedDocumentSurfaceState();
}

class _TextSystemPagedDocumentSurfaceState extends State<TextSystemPagedDocumentSurface> {
  static const double _a4PortraitReferenceWidthMm = 210;
  static const double _pageHeaderHeight = 24;
  static const double _pageHeaderGap = 8;

  final List<TextEditingController> _pageControllers = <TextEditingController>[];
  final List<FocusNode> _pageFocusNodes = <FocusNode>[];
  List<TextSystemPagedTextSlice> _slices = const <TextSystemPagedTextSlice>[];
  String _bufferText = '';
  bool _applyingLayout = false;
  ScrollController? _ownedScrollController;
  TextSystemPageViewport? _viewport;

  ScrollController get _scrollController => widget.scrollController ?? _ownedScrollController!;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController == null) {
      _ownedScrollController = ScrollController();
    }
    widget.textController.addListener(_handleDocumentChanged);
    _bufferText = FluentDocumentBufferMapper.fromDocument(widget.textController.document).text;
  }

  @override
  void didUpdateWidget(covariant TextSystemPagedDocumentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_handleDocumentChanged);
      widget.textController.addListener(_handleDocumentChanged);
      _bufferText = FluentDocumentBufferMapper.fromDocument(widget.textController.document).text;
      _viewport = null;
    }
    if (oldWidget.scrollController != widget.scrollController) {
      _ownedScrollController?.dispose();
      _ownedScrollController = widget.scrollController == null ? ScrollController() : null;
      _viewport = null;
    }
    if (oldWidget.pageSetup != widget.pageSetup ||
        oldWidget.pageMaxWidth != widget.pageMaxWidth ||
        oldWidget.cacheExtentPages != widget.cacheExtentPages) {
      _viewport = null;
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_handleDocumentChanged);
    for (final controller in _pageControllers) {
      controller.dispose();
    }
    for (final focusNode in _pageFocusNodes) {
      focusNode.dispose();
    }
    _ownedScrollController?.dispose();
    super.dispose();
  }

  void _handleDocumentChanged() {
    if (_applyingLayout) return;
    final next = FluentDocumentBufferMapper.fromDocument(widget.textController.document).text;
    if (next == _bufferText) return;
    setState(() {
      _bufferText = next;
      _viewport = null;
    });
  }

  void _handlePageChanged(int pageIndex, TextSystemPagedDocumentMetrics metrics, TextStyle textStyle) {
    if (_applyingLayout || widget.readOnly) return;
    if (pageIndex < 0 || pageIndex >= _slices.length || pageIndex >= _pageControllers.length) return;

    final slice = _slices[pageIndex];
    final controller = _pageControllers[pageIndex];
    final localSelection = controller.selection;
    final localCaret = localSelection.isValid
        ? localSelection.baseOffset.clamp(0, controller.text.length).toInt()
        : controller.text.length;
    final globalCaret = (slice.startOffset + localCaret).clamp(0, _bufferText.length).toInt();

    final safeStart = slice.startOffset.clamp(0, _bufferText.length).toInt();
    final safeEnd = slice.endOffset.clamp(safeStart, _bufferText.length).toInt();
    final nextBufferText = _bufferText.replaceRange(safeStart, safeEnd, controller.text);

    _applyingLayout = true;
    final nextDocument = FluentDocumentBufferMapper.documentFromBuffer(
      previousDocument: widget.textController.document,
      bufferText: nextBufferText,
    );
    widget.textController.replaceDocument(nextDocument, label: 'Edit paged fluent document');
    _bufferText = FluentDocumentBufferMapper.fromDocument(widget.textController.document).text;
    final nextSlices = _paginate(
      text: _bufferText,
      metrics: metrics,
      style: textStyle,
    );
    _applySlices(nextSlices, preferredGlobalCaretOffset: globalCaret, requestFocus: true);
    _applyingLayout = false;
    setState(() {
      _viewport = null;
    });
  }

  void _applySlices(
    List<TextSystemPagedTextSlice> slices, {
    required int preferredGlobalCaretOffset,
    required bool requestFocus,
  }) {
    _slices = slices;

    while (_pageControllers.length < slices.length) {
      final index = _pageControllers.length;
      final controller = TextEditingController();
      controller.addListener(() {
        final style = _lastTextStyle;
        final metrics = _lastMetrics;
        if (style == null || metrics == null) return;
        _handlePageChanged(index, metrics, style);
      });
      _pageControllers.add(controller);
      _pageFocusNodes.add(FocusNode(debugLabel: 'TextSystemPagedDocumentSurface.page.$index'));
    }

    while (_pageControllers.length > slices.length) {
      final controller = _pageControllers.removeLast();
      final focusNode = _pageFocusNodes.removeLast();
      controller.dispose();
      focusNode.dispose();
    }

    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final controller = _pageControllers[i];
      final selectionOffset = _localOffsetForGlobalOffset(slice, preferredGlobalCaretOffset);
      controller.value = TextEditingValue(
        text: slice.text,
        selection: TextSelection.collapsed(offset: selectionOffset),
        composing: TextRange.empty,
      );
    }

    if (requestFocus && _pageFocusNodes.isNotEmpty) {
      final targetPage = _pageIndexForGlobalOffset(preferredGlobalCaretOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || targetPage >= _pageFocusNodes.length) return;
        _pageFocusNodes[targetPage].requestFocus();
        final slice = _slices[targetPage];
        final local = _localOffsetForGlobalOffset(slice, preferredGlobalCaretOffset);
        _pageControllers[targetPage].selection = TextSelection.collapsed(offset: local);
      });
    }
  }

  TextSystemPagedDocumentMetrics? _lastMetrics;
  TextStyle? _lastTextStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textStyle = _pageBodyStyle(theme);

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = widget.focusMode ? 24.0 : 44.0;
          final availableWidth = math.max(320.0, constraints.maxWidth - horizontalPadding * 2);
          final pageWidth = _resolvedPageWidthPx(availableWidth);
          final pageHeight = pageWidth * widget.pageSetup.heightToWidthRatio;
          final margins = widget.pageSetup.margins.toPagePadding(pageWidth, widget.pageSetup.pageWidthMm);
          final contentWidth = math.max(1.0, pageWidth - margins.horizontal);
          final contentHeight = math.max(1.0, pageHeight - margins.vertical);
          final lineHeightPx = _lineHeightPx(textStyle);
          final linesPerPage = math.max(1, (contentHeight / lineHeightPx).floor());
          final pageGap = widget.focusMode ? 72.0 : 96.0;
          final pageTopOffset = _pageHeaderHeight + _pageHeaderGap;
          final pageExtent = pageTopOffset + pageHeight + pageGap;

          final metrics = TextSystemPagedDocumentMetrics(
            pageWidthPx: pageWidth,
            pageHeightPx: pageHeight,
            pageContentWidthPx: contentWidth,
            pageContentHeightPx: contentHeight,
            pageMarginsPx: margins,
            pageTopOffsetPx: pageTopOffset,
            pageGapPx: pageGap,
            pageExtentPx: pageExtent,
            pageCount: math.max(1, _slices.length),
            linesPerPage: linesPerPage,
          );
          _lastMetrics = metrics;
          _lastTextStyle = textStyle;

          final nextSlices = _paginate(text: _bufferText, metrics: metrics, style: textStyle);
          if (_slicesSignature(_slices) != _slicesSignature(nextSlices)) {
            _applyingLayout = true;
            _applySlices(
              nextSlices,
              preferredGlobalCaretOffset: _currentGlobalCaretOffset(),
              requestFocus: false,
            );
            _applyingLayout = false;
          }

          final pageCount = math.max(1, _slices.length);
          final totalHeight = math.max(pageExtent, pageCount * pageExtent);
          final viewportHeight = constraints.hasBoundedHeight ? constraints.maxHeight : pageHeight;
          final viewport = _viewport ??
              TextSystemPageViewportPlanner.fromScroll(
                pageCount: pageCount,
                scrollOffsetPx: 0,
                viewportHeightPx: viewportHeight,
                pageExtentPx: pageExtent,
                cacheExtentPages: widget.cacheExtentPages,
              );

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _reportViewport(
              pageCount: pageCount,
              pageExtentPx: pageExtent,
              viewportHeightPx: viewportHeight,
            );
          });

          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis == Axis.vertical) {
                _reportViewport(
                  pageCount: pageCount,
                  pageExtentPx: pageExtent,
                  viewportHeightPx: notification.metrics.viewportDimension,
                  scrollOffsetPx: notification.metrics.pixels,
                );
              }
              return false;
            },
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  widget.focusMode ? 24 : 38,
                  horizontalPadding,
                  widget.focusMode ? 30 : 58,
                ),
                child: Center(
                  child: SizedBox(
                    width: pageWidth,
                    height: totalHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var pageIndex = 0; pageIndex < pageCount; pageIndex++)
                          _PagedEditorPage(
                            pageIndex: pageIndex,
                            pageCount: pageCount,
                            top: pageIndex * pageExtent,
                            metrics: metrics,
                            pageSetup: widget.pageSetup,
                            showMarginGuides: widget.showMarginGuides,
                            isCurrentPage: pageIndex + 1 == viewport.currentPage,
                            controller: _pageControllers[pageIndex],
                            focusNode: _pageFocusNodes[pageIndex],
                            textStyle: textStyle,
                            readOnly: widget.readOnly,
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: math.max(12, pageGap * 0.35),
                          child: _PagedDocumentFooter(
                            viewport: viewport,
                            pageSetup: widget.pageSetup,
                            metrics: metrics,
                            saveMessage: widget.autosaveController?.saveState.message,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _resolvedPageWidthPx(double availableWidth) {
    final scaledPhysicalWidth = widget.pageMaxWidth *
        (widget.pageSetup.pageWidthMm / _a4PortraitReferenceWidthMm);
    return math.min(scaledPhysicalWidth, availableWidth);
  }

  TextStyle _pageBodyStyle(ThemeData theme) {
    final fallback = theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    return fallback.copyWith(
      fontSize: widget.pageSetup.defaultFontSize,
      height: widget.pageSetup.lineSpacing,
      color: theme.colorScheme.onSurface,
    );
  }

  double _lineHeightPx(TextStyle style) {
    final fontSize = style.fontSize ?? widget.pageSetup.defaultFontSize;
    final height = style.height ?? widget.pageSetup.lineSpacing;
    return fontSize * height;
  }

  List<TextSystemPagedTextSlice> _paginate({
    required String text,
    required TextSystemPagedDocumentMetrics metrics,
    required TextStyle style,
  }) {
    if (text.isEmpty) {
      return const <TextSystemPagedTextSlice>[
        TextSystemPagedTextSlice(text: '', startOffset: 0, endOffset: 0),
      ];
    }

    final slices = <TextSystemPagedTextSlice>[];
    var cursor = 0;
    while (cursor < text.length) {
      final localEnd = _bestFittingEnd(
        text.substring(cursor),
        metrics: metrics,
        style: style,
      );
      var end = cursor + math.max(1, localEnd).clamp(1, text.length - cursor).toInt();
      if (end < text.length) {
        final semanticBreak = _lastBreakBefore(text, cursor, end, preferSentence: true);
        if (semanticBreak > cursor && semanticBreak > cursor + (end - cursor) * 0.62) {
          end = semanticBreak;
        } else {
          final whitespaceBreak = _lastBreakBefore(text, cursor, end, preferSentence: false);
          if (whitespaceBreak > cursor && whitespaceBreak > cursor + (end - cursor) * 0.62) {
            end = whitespaceBreak;
          }
        }
      }

      slices.add(
        TextSystemPagedTextSlice(
          text: text.substring(cursor, end),
          startOffset: cursor,
          endOffset: end,
        ),
      );
      cursor = end;
      while (cursor < text.length && (text.codeUnitAt(cursor) == 0x20 || text.codeUnitAt(cursor) == 0x09)) {
        cursor++;
      }
    }
    return slices;
  }

  int _bestFittingEnd(
    String text, {
    required TextSystemPagedDocumentMetrics metrics,
    required TextStyle style,
  }) {
    if (_fitsPage(text, metrics: metrics, style: style)) return text.length;

    var low = 0;
    var high = text.length;
    var best = 0;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      if (_fitsPage(text.substring(0, mid), metrics: metrics, style: style)) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return math.max(1, best);
  }

  bool _fitsPage(
    String text, {
    required TextSystemPagedDocumentMetrics metrics,
    required TextStyle style,
  }) {
    if (text.trim().isEmpty) return true;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: metrics.pageContentWidthPx);
    return painter.height <= metrics.pageContentHeightPx - 1;
  }

  int _lastBreakBefore(String text, int start, int end, {required bool preferSentence}) {
    final safeStart = start.clamp(0, text.length).toInt();
    final safeEnd = end.clamp(safeStart, text.length).toInt();
    final candidate = text.substring(safeStart, safeEnd);
    final pattern = preferSentence ? RegExp(r'[.!?]\s+') : RegExp(r'\s+');
    var result = -1;
    for (final match in pattern.allMatches(candidate)) {
      result = safeStart + match.end;
    }
    return result;
  }

  String _slicesSignature(List<TextSystemPagedTextSlice> slices) {
    return slices.map((slice) => '${slice.startOffset}:${slice.endOffset}:${slice.text.length}').join('|');
  }

  int _currentGlobalCaretOffset() {
    for (var i = 0; i < _pageFocusNodes.length && i < _slices.length; i++) {
      if (!_pageFocusNodes[i].hasFocus) continue;
      final selection = _pageControllers[i].selection;
      final local = selection.isValid
          ? selection.baseOffset.clamp(0, _pageControllers[i].text.length).toInt()
          : _pageControllers[i].text.length;
      return (_slices[i].startOffset + local).clamp(0, _bufferText.length).toInt();
    }
    return _bufferText.length;
  }

  int _pageIndexForGlobalOffset(int globalOffset) {
    if (_slices.isEmpty) return 0;
    final safe = globalOffset.clamp(0, _bufferText.length).toInt();
    for (var i = 0; i < _slices.length; i++) {
      if (_slices[i].containsOffset(safe)) return i;
    }
    return _slices.length - 1;
  }

  int _localOffsetForGlobalOffset(TextSystemPagedTextSlice slice, int globalOffset) {
    final safe = globalOffset.clamp(slice.startOffset, slice.endOffset).toInt();
    return (safe - slice.startOffset).clamp(0, slice.text.length).toInt();
  }

  void _reportViewport({
    required int pageCount,
    required double pageExtentPx,
    required double viewportHeightPx,
    double? scrollOffsetPx,
  }) {
    final offset = scrollOffsetPx ?? (_scrollController.hasClients ? _scrollController.offset : 0.0);
    final nextViewport = TextSystemPageViewportPlanner.fromScroll(
      pageCount: pageCount,
      scrollOffsetPx: offset,
      viewportHeightPx: viewportHeightPx,
      pageExtentPx: pageExtentPx,
      cacheExtentPages: widget.cacheExtentPages,
    );
    if (_viewport?.signature == nextViewport.signature) return;
    if (mounted) {
      setState(() => _viewport = nextViewport);
    } else {
      _viewport = nextViewport;
    }
    widget.onViewportChanged?.call(nextViewport);
  }
}

class _PagedEditorPage extends StatelessWidget {
  const _PagedEditorPage({
    required this.pageIndex,
    required this.pageCount,
    required this.top,
    required this.metrics,
    required this.pageSetup,
    required this.showMarginGuides,
    required this.isCurrentPage,
    required this.controller,
    required this.focusNode,
    required this.textStyle,
    required this.readOnly,
  });

  final int pageIndex;
  final int pageCount;
  final double top;
  final TextSystemPagedDocumentMetrics metrics;
  final TextSystemPageSetup pageSetup;
  final bool showMarginGuides;
  final bool isCurrentPage;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle textStyle;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dimensionLabel = '${pageSetup.pageWidthMm.toStringAsFixed(0)} × ${pageSetup.pageHeightMm.toStringAsFixed(0)} mm';

    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall?.copyWith(
                color: isCurrentPage ? colorScheme.primary : colorScheme.onSurfaceVariant,
                fontWeight: isCurrentPage ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                children: [
                  Text('Page ${pageIndex + 1} of $pageCount'),
                  Text(pageSetup.shortLabel),
                  Text(dimensionLabel),
                  if (isCurrentPage)
                    Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: isCurrentPage
                    ? colorScheme.primary.withValues(alpha: 0.35)
                    : colorScheme.outlineVariant.withValues(alpha: 0.65),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isCurrentPage ? 0.18 : 0.13),
                  blurRadius: isCurrentPage ? 28 : 22,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SizedBox(
              width: metrics.pageWidthPx,
              height: metrics.pageHeightPx,
              child: Stack(
                children: [
                  if (showMarginGuides)
                    Positioned(
                      left: metrics.pageMarginsPx.left,
                      top: metrics.pageMarginsPx.top,
                      right: metrics.pageMarginsPx.right,
                      bottom: metrics.pageMarginsPx.bottom,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.16),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: metrics.pageMarginsPx.left,
                    top: metrics.pageMarginsPx.top,
                    right: metrics.pageMarginsPx.right,
                    bottom: metrics.pageMarginsPx.bottom,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      readOnly: readOnly,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      inputFormatters: const <TextInputFormatter>[
                        FluentDocumentNaturalEditingFormatter(),
                      ],
                      textAlignVertical: TextAlignVertical.top,
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      style: textStyle,
                      cursorHeight: (textStyle.fontSize ?? 12) * (textStyle.height ?? 1.15),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (pageSetup.showPageNumbers)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: math.max(14, metrics.pageMarginsPx.bottom * 0.35),
                      child: IgnorePointer(
                        child: Text(
                          '${pageIndex + 1}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PagedDocumentFooter extends StatelessWidget {
  const _PagedDocumentFooter({
    required this.viewport,
    required this.pageSetup,
    required this.metrics,
    required this.saveMessage,
  });

  final TextSystemPageViewport viewport;
  final TextSystemPageSetup pageSetup;
  final TextSystemPagedDocumentMetrics metrics;
  final String? saveMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = [
      viewport.statusLabel,
      '${metrics.linesPerPage} lines/page',
      '${pageSetup.pageWidthMm.toStringAsFixed(0)} × ${pageSetup.pageHeightMm.toStringAsFixed(0)} mm',
      if (saveMessage != null && saveMessage!.trim().isNotEmpty) saveMessage!,
    ].join(' · ');

    return Text(
      label,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
