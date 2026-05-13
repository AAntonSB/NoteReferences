import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'text_system_page_break_overlay.dart';
import 'text_system_page_layout.dart';
import 'text_system_page_map.dart';
import 'text_system_page_setup.dart';
import 'text_system_page_viewport.dart';

/// Reusable page-canvas renderer for document-grade writing surfaces.
///
/// Phase 13C keeps the fluent editor as one continuous editable surface and
/// layers passive pagination metadata over it. Page chrome, margin guides,
/// viewport metadata, and page-break markers are read-only presentation. They
/// must not create document transactions.
class TextSystemPageCanvas extends StatefulWidget {
  const TextSystemPageCanvas({
    super.key,
    required this.pageMaxWidth,
    required this.focusMode,
    required this.pageSetup,
    required this.child,
    this.showMarginGuides = true,
    this.showPageBreakMarkers = true,
    this.showDetailedPageBreakLabels = true,
    this.showPageChrome = true,
    this.pageLabel,
    this.footerLabel,
    this.pageLayout,
    this.pageMap,
    this.scrollController,
    this.onViewportChanged,
    this.cacheExtentPages = 2,
  });

  final double pageMaxWidth;
  final bool focusMode;
  final TextSystemPageSetup pageSetup;
  final Widget child;
  final bool showMarginGuides;
  final bool showPageBreakMarkers;
  final bool showDetailedPageBreakLabels;
  final bool showPageChrome;
  final String? pageLabel;
  final String? footerLabel;
  final TextSystemPageLayout? pageLayout;
  final TextSystemPageMap? pageMap;
  final ScrollController? scrollController;
  final ValueChanged<TextSystemPageViewport>? onViewportChanged;
  final int cacheExtentPages;

  @override
  State<TextSystemPageCanvas> createState() => _TextSystemPageCanvasState();
}

class _TextSystemPageCanvasState extends State<TextSystemPageCanvas> {
  static const double _a4PortraitReferenceWidthMm = 210;
  static const double _pageHeaderHeight = 42;
  static const double _pageHeaderGap = 8;

  ScrollController? _ownedScrollController;
  TextSystemPageViewport? _viewport;

  ScrollController get _scrollController => widget.scrollController ?? _ownedScrollController!;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController == null) {
      _ownedScrollController = ScrollController();
    }
  }

  @override
  void didUpdateWidget(covariant TextSystemPageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _ownedScrollController?.dispose();
      _ownedScrollController = widget.scrollController == null ? ScrollController() : null;
      _viewport = null;
    }

    if (oldWidget.pageLayout?.pageCount != widget.pageLayout?.pageCount ||
        oldWidget.pageMap?.pageCount != widget.pageMap?.pageCount ||
        oldWidget.cacheExtentPages != widget.cacheExtentPages ||
        oldWidget.pageSetup != widget.pageSetup) {
      _viewport = null;
    }
  }

  @override
  void dispose() {
    _ownedScrollController?.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = widget.focusMode ? 24.0 : 44.0;
          final availableWidth = math.max(320.0, constraints.maxWidth - horizontalPadding * 2);
          final scaledPhysicalWidth = widget.pageMaxWidth *
              (widget.pageSetup.pageWidthMm / _a4PortraitReferenceWidthMm);
          final pageWidth = math.min(scaledPhysicalWidth, availableWidth);
          final pageHeight = pageWidth * widget.pageSetup.heightToWidthRatio;
          final margins = widget.pageSetup.margins.toPagePadding(pageWidth, widget.pageSetup.pageWidthMm);
          final viewportHeight = constraints.hasBoundedHeight ? constraints.maxHeight : pageHeight;
          final pageGap = widget.focusMode ? 72.0 : 96.0;
          final pageTopOffset = _pageHeaderHeight + _pageHeaderGap;
          final pageExtent = pageTopOffset + pageHeight + pageGap;
          final pageCount = math.max(1, widget.pageMap?.pageCount ?? widget.pageLayout?.pageCount ?? 1);
          final contentFlowHeight = widget.pageMap == null
              ? 0.0
              : pageTopOffset + margins.top + widget.pageMap!.totalContentHeightPx + margins.bottom + pageGap;
          final totalHeight = math.max(pageExtent, math.max(pageCount * pageExtent, contentFlowHeight));
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
                        if (widget.showPageChrome)
                          for (final pageNumber in _mountedPages(viewport, pageCount))
                            _VirtualizedPageFrame(
                              pageNumber: pageNumber,
                              pageCount: pageCount,
                              top: (pageNumber - 1) * pageExtent,
                              pageWidth: pageWidth,
                              pageHeight: pageHeight,
                              pageSetup: widget.pageSetup,
                              margins: margins,
                              showMarginGuides: widget.showMarginGuides,
                              isCurrentPage: pageNumber == viewport.currentPage,
                            ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: pageTopOffset,
                          child: widget.child,
                        ),
                        if (widget.showPageBreakMarkers && widget.pageMap != null)
                          Positioned.fill(
                            child: TextSystemHybridPageBreakOverlay(
                              pageMap: widget.pageMap!,
                              viewport: viewport,
                              pageWidth: pageWidth,
                              contentLeft: margins.left,
                              contentRight: margins.right,
                              topOffset: pageTopOffset + margins.top,
                              showDetailedLabels: widget.showDetailedPageBreakLabels,
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: math.max(12, pageGap * 0.35),
                          child: _VirtualizationFooter(
                            footerLabel: widget.footerLabel,
                            viewport: viewport,
                            pageLayout: widget.pageLayout,
                            pageMap: widget.pageMap,
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

  Iterable<int> _mountedPages(TextSystemPageViewport viewport, int pageCount) sync* {
    if (!widget.showPageChrome) return;
    final start = viewport.mountedPageStart.clamp(1, pageCount).toInt();
    final end = viewport.mountedPageEnd.clamp(start, pageCount).toInt();
    for (var page = start; page <= end; page++) {
      yield page;
    }
  }
}

class _VirtualizedPageFrame extends StatelessWidget {
  const _VirtualizedPageFrame({
    required this.pageNumber,
    required this.pageCount,
    required this.top,
    required this.pageWidth,
    required this.pageHeight,
    required this.pageSetup,
    required this.margins,
    required this.showMarginGuides,
    required this.isCurrentPage,
  });

  final int pageNumber;
  final int pageCount;
  final double top;
  final double pageWidth;
  final double pageHeight;
  final TextSystemPageSetup pageSetup;
  final EdgeInsets margins;
  final bool showMarginGuides;
  final bool isCurrentPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dimensionLabel = '${pageSetup.pageWidthMm.toStringAsFixed(0)} × ${pageSetup.pageHeightMm.toStringAsFixed(0)} mm';

    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _TextSystemPageCanvasConstants.headerHeight,
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
                    Text('Page $pageNumber of ~$pageCount'),
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
            SizedBox(height: _TextSystemPageCanvasConstants.headerGap),
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
                width: pageWidth,
                height: pageHeight,
                child: Stack(
                  children: [
                    if (showMarginGuides)
                      Positioned(
                        left: margins.left,
                        top: margins.top,
                        right: margins.right,
                        bottom: margins.bottom,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.16),
                              width: 1,
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
      ),
    );
  }
}

class _VirtualizationFooter extends StatelessWidget {
  const _VirtualizationFooter({
    required this.footerLabel,
    required this.viewport,
    required this.pageLayout,
    required this.pageMap,
  });

  final String? footerLabel;
  final TextSystemPageViewport viewport;
  final TextSystemPageLayout? pageLayout;
  final TextSystemPageMap? pageMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = [
      if (footerLabel != null && footerLabel!.trim().isNotEmpty) footerLabel!,
      viewport.statusLabel,
      if (pageMap != null) 'measured ${pageMap!.pageLabel}',
      'virtualized page chrome: ${viewport.mountedPageCount}/${viewport.pageCount} pages painted',
      if (pageLayout != null) '${pageLayout!.anchors.length} heading anchors',
    ].join(' · ');

    return Text(
      label,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: label.contains('over by') ? colorScheme.error : colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _TextSystemPageCanvasConstants {
  const _TextSystemPageCanvasConstants._();

  static const double headerHeight = _TextSystemPageCanvasState._pageHeaderHeight;
  static const double headerGap = _TextSystemPageCanvasState._pageHeaderGap;
}
