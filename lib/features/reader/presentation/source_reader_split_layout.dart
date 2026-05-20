import 'dart:math' as math;

import 'package:flutter/material.dart';

class SourceReaderTwoPaneLayout extends StatelessWidget {
  final Widget Function() readerBuilder;
  final Widget Function() paneBuilder;
  final double paneFraction;
  final ValueChanged<double> onPaneFractionChanged;
  final VoidCallback? onPaneFractionChangeCommitted;
  final double minPaneWidth;
  final double dividerWidth;
  final bool collapseToReaderWhenNarrow;

  const SourceReaderTwoPaneLayout({
    super.key,
    required this.readerBuilder,
    required this.paneBuilder,
    required this.paneFraction,
    required this.onPaneFractionChanged,
    this.onPaneFractionChangeCommitted,
    this.minPaneWidth = 280.0,
    this.dividerWidth = 8.0,
    this.collapseToReaderWhenNarrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        if (collapseToReaderWhenNarrow &&
            totalWidth < (minPaneWidth * 2 + dividerWidth)) {
          return readerBuilder();
        }

        final availableWidth = math.max(1.0, totalWidth - dividerWidth);
        final minFraction = (minPaneWidth / availableWidth).clamp(0.05, 0.95);
        final maxFraction = (1.0 - (minPaneWidth / availableWidth)).clamp(0.05, 0.95);
        final safeReaderPaneFraction = paneFraction
            .clamp(math.min(minFraction, maxFraction), math.max(minFraction, maxFraction))
            .toDouble();

        final readerPaneWidth = availableWidth * safeReaderPaneFraction;
        final sidePaneWidth = availableWidth - readerPaneWidth;

        return Row(
          children: [
            SizedBox(width: readerPaneWidth, child: readerBuilder()),
            SourceReaderVerticalDivider(
              width: dividerWidth,
              onDragUpdate: (details) {
                final newReaderWidth = readerPaneWidth + details.delta.dx;
                final nextFraction = (newReaderWidth / availableWidth)
                    .clamp(math.min(minFraction, maxFraction), math.max(minFraction, maxFraction))
                    .toDouble();
                onPaneFractionChanged(nextFraction);
              },
              onDragEnd: (_) => onPaneFractionChangeCommitted?.call(),
            ),
            SizedBox(width: sidePaneWidth, child: paneBuilder()),
          ],
        );
      },
    );
  }
}

class SourceReaderSynthesisLayout extends StatelessWidget {
  final Widget Function() readerBuilder;
  final Widget Function() sidecarBuilder;
  final Widget Function() synthesisBuilder;
  final Widget Function() fallbackBuilder;
  final double minPaneWidth;
  final double dividerWidth;

  const SourceReaderSynthesisLayout({
    super.key,
    required this.readerBuilder,
    required this.sidecarBuilder,
    required this.synthesisBuilder,
    required this.fallbackBuilder,
    this.minPaneWidth = 280.0,
    this.dividerWidth = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        if (totalWidth < (minPaneWidth * 3 + dividerWidth * 2)) {
          return fallbackBuilder();
        }

        return Row(
          children: [
            Expanded(flex: 5, child: readerBuilder()),
            SourceReaderVerticalDivider(width: dividerWidth),
            Expanded(flex: 3, child: sidecarBuilder()),
            SourceReaderVerticalDivider(width: dividerWidth),
            Expanded(flex: 4, child: synthesisBuilder()),
          ],
        );
      },
    );
  }
}

class SourceReaderVerticalDivider extends StatelessWidget {
  final double width;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  const SourceReaderVerticalDivider({
    super.key,
    this.width = 8.0,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = Container(
      width: width,
      color: theme.colorScheme.outlineVariant,
      child: Center(
        child: Container(width: 2, color: theme.colorScheme.outline),
      ),
    );

    if (onDragUpdate == null) return divider;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: onDragEnd,
        child: divider,
      ),
    );
  }
}
