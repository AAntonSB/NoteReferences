import 'planning_item.dart';

/// Day-level planning container. C1 introduces this as the shared shape for
/// upcoming Today/Week/Month surfaces; later phases can add persistence-backed
/// scheduled blocks and user overrides without changing every UI.
class DayPlan {
  final DateTime date;
  final List<PlanningItem> requiredItems;
  final List<PlanningItem> debtItems;
  final List<PlanningBlock> scheduledBlocks;
  final int? availableMinutes;
  final int plannedMinutes;
  final double pressureScore;
  final double riskScore;

  const DayPlan({
    required this.date,
    this.requiredItems = const <PlanningItem>[],
    this.debtItems = const <PlanningItem>[],
    this.scheduledBlocks = const <PlanningBlock>[],
    this.availableMinutes,
    this.plannedMinutes = 0,
    this.pressureScore = 0,
    this.riskScore = 0,
  });

  bool get hasWork => requiredItems.isNotEmpty || scheduledBlocks.isNotEmpty;
  bool get hasDebt => debtItems.isNotEmpty;
  bool get isOverCapacity {
    final capacity = availableMinutes;
    return capacity != null && plannedMinutes > capacity;
  }
}

class PlanningBlock {
  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final List<String> planningItemIds;
  final bool userLocked;
  final bool generated;
  final String? projectId;

  const PlanningBlock({
    required this.id,
    required this.startAt,
    required this.endAt,
    this.planningItemIds = const <String>[],
    this.userLocked = false,
    this.generated = false,
    this.projectId,
  });

  int get durationMinutes => endAt.difference(startAt).inMinutes;
}
