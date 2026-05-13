import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'text_system_section_page_metrics.dart';

/// Read-only writing-plan intelligence derived from measured page metrics.
///
/// This layer is deliberately not part of document mutation. It converts the
/// passive page/section metrics into planning signals for the premium writer:
/// target progress, required pace, section imbalance, and next-step hints.
@immutable
class TextSystemPageWorkPlan {
  const TextSystemPageWorkPlan({
    required this.measuredPages,
    required this.targetPages,
    required this.remainingPages,
    required this.planningHorizonDays,
    required this.pagesPerDay,
    required this.completionRatio,
    required this.isOverTarget,
    required this.signals,
  });

  final double measuredPages;
  final double targetPages;
  final double remainingPages;
  final int planningHorizonDays;
  final double pagesPerDay;
  final double completionRatio;
  final bool isOverTarget;
  final List<TextSystemPageWorkSignal> signals;

  bool get hasUrgentSignals => signals.any(
        (signal) => signal.severity == TextSystemPageWorkSignalSeverity.urgent,
      );

  bool get hasWarningSignals => signals.any(
        (signal) => signal.severity == TextSystemPageWorkSignalSeverity.warning,
      );

  String get planningHorizonLabel {
    return planningHorizonDays == 1 ? '1 day' : '$planningHorizonDays days';
  }

  String get paceLabel {
    if (remainingPages <= 0 && isOverTarget) {
      return 'Over target by ${_formatPages(measuredPages - targetPages)} p';
    }
    if (remainingPages <= 0) {
      return 'Target length reached';
    }
    return '${_formatPages(pagesPerDay)} p/day for $planningHorizonLabel';
  }

  String get headline {
    if (remainingPages <= 0 && isOverTarget) {
      return 'Reduce or revise: ${_formatPages(measuredPages - targetPages)} pages over target.';
    }
    if (remainingPages <= 0) {
      return 'Draft length target reached. Shift focus to structure and revision.';
    }
    return '${_formatPages(remainingPages)} pages remaining · $paceLabel.';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'measuredPages': measuredPages,
      'targetPages': targetPages,
      'remainingPages': remainingPages,
      'planningHorizonDays': planningHorizonDays,
      'pagesPerDay': pagesPerDay,
      'completionRatio': completionRatio,
      'isOverTarget': isOverTarget,
      'paceLabel': paceLabel,
      'headline': headline,
      'signals': [for (final signal in signals) signal.toJson()],
    };
  }

  static TextSystemPageWorkPlan compute({
    required TextSystemSectionPageMetricsResult sectionMetrics,
    required int planningHorizonDays,
  }) {
    final safeHorizon = math.max(1, planningHorizonDays);
    final remainingPages = sectionMetrics.remainingPages;
    final pagesPerDay = remainingPages <= 0 ? 0.0 : remainingPages / safeHorizon;
    final signals = <TextSystemPageWorkSignal>[];

    if (sectionMetrics.isOverTarget) {
      signals.add(
        TextSystemPageWorkSignal(
          severity: TextSystemPageWorkSignalSeverity.urgent,
          title: 'Over page target',
          message:
              'The draft is ${_formatPages(sectionMetrics.measuredPages - sectionMetrics.targetPages)} pages over the current target. Prioritize tightening, moving material to notes, or increasing the target if the assignment allows it.',
        ),
      );
    } else if (remainingPages <= 0) {
      signals.add(
        const TextSystemPageWorkSignal(
          severity: TextSystemPageWorkSignalSeverity.info,
          title: 'Target length reached',
          message:
              'You have reached the current page target. Use the page map to rebalance sections and move into revision.',
        ),
      );
    } else if (pagesPerDay >= 1.0) {
      signals.add(
        TextSystemPageWorkSignal(
          severity: TextSystemPageWorkSignalSeverity.warning,
          title: 'High writing pace',
          message:
              'To hit the target in $safeHorizon ${safeHorizon == 1 ? 'day' : 'days'}, you need about ${_formatPages(pagesPerDay)} pages per day.',
        ),
      );
    } else {
      signals.add(
        TextSystemPageWorkSignal(
          severity: TextSystemPageWorkSignalSeverity.info,
          title: 'Page pace',
          message:
              'About ${_formatPages(pagesPerDay)} pages per day reaches the target in $safeHorizon ${safeHorizon == 1 ? 'day' : 'days'}.',
        ),
      );
    }

    if (sectionMetrics.sections.isEmpty) {
      signals.add(
        const TextSystemPageWorkSignal(
          severity: TextSystemPageWorkSignalSeverity.warning,
          title: 'No section structure',
          message:
              'Add headings to unlock section spans, balance diagnostics, and page-aware navigation.',
        ),
      );
    } else {
      final averageSectionPages = sectionMetrics.measuredPages / sectionMetrics.sectionCount;
      final longest = sectionMetrics.longestSections.first;
      if (longest.pageSpan > math.max(1.5, averageSectionPages * 1.75)) {
        signals.add(
          TextSystemPageWorkSignal(
            severity: TextSystemPageWorkSignalSeverity.warning,
            title: 'Long section',
            message:
                '“${longest.title}” spans ${longest.pageSpanLabel}. Consider splitting it or checking whether it is carrying too much of the argument.',
          ),
        );
      }

      final thinSections = sectionMetrics.sections
          .where((section) => section.pageSpan > 0 && section.pageSpan < 0.20)
          .take(3)
          .toList(growable: false);
      if (thinSections.isNotEmpty) {
        signals.add(
          TextSystemPageWorkSignal(
            severity: TextSystemPageWorkSignalSeverity.info,
            title: 'Thin sections',
            message:
                'Some sections are under 0.2 pages. Check whether they need expansion, merging, or removal.',
          ),
        );
      }

      final overdueSections = sectionMetrics.sections
          .where((section) => section.overdueCount > 0)
          .toList(growable: false);
      if (overdueSections.isNotEmpty) {
        signals.add(
          TextSystemPageWorkSignal(
            severity: TextSystemPageWorkSignalSeverity.urgent,
            title: 'Overdue project signals',
            message:
                '${overdueSections.length} section${overdueSections.length == 1 ? '' : 's'} contain overdue linked work signals.',
          ),
        );
      }
    }

    return TextSystemPageWorkPlan(
      measuredPages: sectionMetrics.measuredPages,
      targetPages: sectionMetrics.targetPages,
      remainingPages: remainingPages,
      planningHorizonDays: safeHorizon,
      pagesPerDay: pagesPerDay,
      completionRatio: sectionMetrics.completionRatio,
      isOverTarget: sectionMetrics.isOverTarget,
      signals: List<TextSystemPageWorkSignal>.unmodifiable(signals),
    );
  }

  static String _formatPages(double pages) {
    if (pages >= 10) return pages.toStringAsFixed(0);
    return pages.toStringAsFixed(1);
  }
}

enum TextSystemPageWorkSignalSeverity {
  info,
  warning,
  urgent;

  String get label {
    return switch (this) {
      TextSystemPageWorkSignalSeverity.info => 'Info',
      TextSystemPageWorkSignalSeverity.warning => 'Warning',
      TextSystemPageWorkSignalSeverity.urgent => 'Urgent',
    };
  }
}

@immutable
class TextSystemPageWorkSignal {
  const TextSystemPageWorkSignal({
    required this.severity,
    required this.title,
    required this.message,
  });

  final TextSystemPageWorkSignalSeverity severity;
  final String title;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'severity': severity.name,
      'title': title,
      'message': message,
    };
  }
}
