import 'package:flutter/foundation.dart';

@immutable
class FutureMapMonth implements Comparable<FutureMapMonth> {
  final int year;
  final int month;

  const FutureMapMonth({required this.year, required this.month})
      : assert(month >= 1 && month <= 12);

  factory FutureMapMonth.fromDate(DateTime date) {
    return FutureMapMonth(year: date.year, month: date.month);
  }

  FutureMapMonth add(int months) {
    final zeroBased = (year * 12) + (month - 1) + months;
    return FutureMapMonth(year: zeroBased ~/ 12, month: (zeroBased % 12) + 1);
  }

  int distanceTo(FutureMapMonth other) {
    return (other.year * 12 + other.month) - (year * 12 + month);
  }

  DateTime get startDate => DateTime(year, month);

  String get monthLabel => _monthNames[month - 1];

  String get compactLabel => monthLabel;

  String get fullLabel => '$monthLabel $year';

  @override
  int compareTo(FutureMapMonth other) {
    return (year * 12 + month).compareTo(other.year * 12 + other.month);
  }

  @override
  bool operator ==(Object other) {
    return other is FutureMapMonth && other.year == year && other.month == month;
  }

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => fullLabel;

  static const List<String> _monthNames = <String>[
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
}

@immutable
class FutureMapTimeframe {
  final FutureMapMonth start;
  final int monthCount;

  const FutureMapTimeframe({required this.start, required this.monthCount})
      : assert(monthCount > 0);

  factory FutureMapTimeframe.fiveYearsFrom(DateTime date) {
    return FutureMapTimeframe(
      start: FutureMapMonth.fromDate(DateTime(date.year, date.month)),
      monthCount: 60,
    );
  }

  FutureMapMonth get end => start.add(monthCount - 1);

  List<FutureMapMonth> get months {
    return List<FutureMapMonth>.generate(monthCount, start.add);
  }

  int indexOf(FutureMapMonth month) {
    final index = start.distanceTo(month);
    return index.clamp(0, monthCount - 1).toInt();
  }

  FutureMapMonth monthAtIndex(int index) {
    return start.add(index.clamp(0, monthCount - 1).toInt());
  }

  bool contains(FutureMapMonth month) {
    final index = start.distanceTo(month);
    return index >= 0 && index < monthCount;
  }

  String get label => '${start.fullLabel} → ${end.fullLabel}';
}

enum FutureMapNodeType {
  goal,
  futureState,
  condition,
  step,
  fallback,
  obstacle,
  lifeEvent,
  review,
}

extension FutureMapNodeTypeX on FutureMapNodeType {
  String get label {
    switch (this) {
      case FutureMapNodeType.goal:
        return 'Goal';
      case FutureMapNodeType.futureState:
        return 'Future state';
      case FutureMapNodeType.condition:
        return 'Condition';
      case FutureMapNodeType.step:
        return 'Step';
      case FutureMapNodeType.fallback:
        return 'Fallback';
      case FutureMapNodeType.obstacle:
        return 'Obstacle';
      case FutureMapNodeType.lifeEvent:
        return 'Life event';
      case FutureMapNodeType.review:
        return 'Review';
    }
  }

  String get helperText {
    switch (this) {
      case FutureMapNodeType.goal:
        return 'Something you want to achieve or make happen.';
      case FutureMapNodeType.futureState:
        return 'A life situation or destination that makes a goal possible.';
      case FutureMapNodeType.condition:
        return 'Something that must become true for a future to make sense.';
      case FutureMapNodeType.step:
        return 'A concrete move that can bring a condition closer.';
      case FutureMapNodeType.fallback:
        return 'A route to take if the preferred path breaks.';
      case FutureMapNodeType.obstacle:
        return 'A risk, blocker, pressure, or uncertainty.';
      case FutureMapNodeType.lifeEvent:
        return 'Something life-shaped that affects the plan.';
      case FutureMapNodeType.review:
        return 'A check-in point for reassessing the map.';
    }
  }
}

enum FutureMapTimeMode {
  unscheduled,
  roughPeriod,
  targetMonth,
  timeRange,
  anchoredDate,
}

extension FutureMapTimeModeX on FutureMapTimeMode {
  String get label {
    switch (this) {
      case FutureMapTimeMode.unscheduled:
        return 'Not placed yet';
      case FutureMapTimeMode.roughPeriod:
        return 'Rough period';
      case FutureMapTimeMode.targetMonth:
        return 'Target month';
      case FutureMapTimeMode.timeRange:
        return 'Time range';
      case FutureMapTimeMode.anchoredDate:
        return 'Fixed month';
    }
  }

  String get helperText {
    switch (this) {
      case FutureMapTimeMode.unscheduled:
        return 'Keep this in the unplaced tray until the timing becomes clearer.';
      case FutureMapTimeMode.roughPeriod:
        return 'Use this when the timing is approximate and may move.';
      case FutureMapTimeMode.targetMonth:
        return 'Use this when the block belongs around one month.';
      case FutureMapTimeMode.timeRange:
        return 'Use this when the block spans a known period.';
      case FutureMapTimeMode.anchoredDate:
        return 'Use this when the month is externally fixed or hard to move.';
    }
  }

  bool get isPlaced => this != FutureMapTimeMode.unscheduled;

  bool get usesRange => this == FutureMapTimeMode.roughPeriod || this == FutureMapTimeMode.timeRange;
}

@immutable
class FutureMapNode {
  final String id;
  final FutureMapNodeType type;
  final String title;
  final String notes;
  final FutureMapTimeMode timeMode;
  final FutureMapMonth? startMonth;
  final FutureMapMonth? endMonth;
  final double x;
  final double y;
  final DateTime createdAt;

  const FutureMapNode({
    required this.id,
    required this.type,
    required this.title,
    required this.notes,
    required this.timeMode,
    required this.startMonth,
    required this.endMonth,
    required this.x,
    required this.y,
    required this.createdAt,
  });

  bool get isPlaced => timeMode.isPlaced && startMonth != null;

  int get durationMonths {
    final start = startMonth;
    if (start == null) return 1;
    final end = endMonth;
    if (end == null) return 1;
    return (start.distanceTo(end) + 1).clamp(1, 120).toInt();
  }

  FutureMapMonth? get effectiveEndMonth {
    final start = startMonth;
    if (start == null) return null;
    return endMonth ?? start;
  }

  FutureMapNode copyWith({
    FutureMapNodeType? type,
    String? title,
    String? notes,
    FutureMapTimeMode? timeMode,
    FutureMapMonth? startMonth,
    FutureMapMonth? endMonth,
    double? x,
    double? y,
    bool clearTime = false,
  }) {
    return FutureMapNode(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      timeMode: timeMode ?? this.timeMode,
      startMonth: clearTime ? null : (startMonth ?? this.startMonth),
      endMonth: clearTime ? null : (endMonth ?? this.endMonth),
      x: x ?? this.x,
      y: y ?? this.y,
      createdAt: createdAt,
    );
  }
}

enum FutureMapConnectionType {
  leadsTo,
  requires,
  supports,
  blocks,
  threatens,
  fallbackIfFailed,
  alternativePath,
  reviewAfter,
  partOf,
}

extension FutureMapConnectionTypeX on FutureMapConnectionType {
  String get label {
    switch (this) {
      case FutureMapConnectionType.leadsTo:
        return 'Leads to';
      case FutureMapConnectionType.requires:
        return 'Requires';
      case FutureMapConnectionType.supports:
        return 'Supports';
      case FutureMapConnectionType.blocks:
        return 'Blocks';
      case FutureMapConnectionType.threatens:
        return 'Threatens';
      case FutureMapConnectionType.fallbackIfFailed:
        return 'Fallback if failed';
      case FutureMapConnectionType.alternativePath:
        return 'Alternative path';
      case FutureMapConnectionType.reviewAfter:
        return 'Review after';
      case FutureMapConnectionType.partOf:
        return 'Part of';
    }
  }

  String get helperText {
    switch (this) {
      case FutureMapConnectionType.leadsTo:
        return 'This naturally leads toward the next block.';
      case FutureMapConnectionType.requires:
        return 'The target needs this to be true first.';
      case FutureMapConnectionType.supports:
        return 'This makes the target easier or healthier.';
      case FutureMapConnectionType.blocks:
        return 'This prevents or stops the target.';
      case FutureMapConnectionType.threatens:
        return 'This may delay, weaken, or destabilize the target.';
      case FutureMapConnectionType.fallbackIfFailed:
        return 'Use this path if the preferred route breaks.';
      case FutureMapConnectionType.alternativePath:
        return 'This is another possible route, not necessarily worse.';
      case FutureMapConnectionType.reviewAfter:
        return 'Check the target after this has happened.';
      case FutureMapConnectionType.partOf:
        return 'This is one piece of the larger block.';
    }
  }

  bool get isDashed {
    switch (this) {
      case FutureMapConnectionType.fallbackIfFailed:
      case FutureMapConnectionType.alternativePath:
      case FutureMapConnectionType.reviewAfter:
        return true;
      case FutureMapConnectionType.leadsTo:
      case FutureMapConnectionType.requires:
      case FutureMapConnectionType.supports:
      case FutureMapConnectionType.blocks:
      case FutureMapConnectionType.threatens:
      case FutureMapConnectionType.partOf:
        return false;
    }
  }
}

@immutable
class FutureMapConnection {
  final String id;
  final String fromNodeId;
  final String toNodeId;
  final FutureMapConnectionType type;
  final String label;
  final DateTime createdAt;

  const FutureMapConnection({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.type,
    required this.label,
    required this.createdAt,
  });

  FutureMapConnection copyWith({
    FutureMapConnectionType? type,
    String? label,
  }) {
    return FutureMapConnection(
      id: id,
      fromNodeId: fromNodeId,
      toNodeId: toNodeId,
      type: type ?? this.type,
      label: label ?? this.label,
      createdAt: createdAt,
    );
  }
}
