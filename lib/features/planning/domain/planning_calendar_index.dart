import '../../canvas/data/canvas_import_repository.dart';
import '../../notes/data/note_repository.dart';
import '../data/study_planning_repository.dart';
import 'planning_item.dart';

class PlanningCalendarIndex {
  final Map<String, List<PlanningCalendarItem>> _itemsByDate;

  const PlanningCalendarIndex(this._itemsByDate);

  factory PlanningCalendarIndex.fromSources({
    required List<TodoItem> todos,
    required List<StudyPlanRequirement> planRequirements,
    required List<CanvasCalendarEvent> canvasEvents,
    DateTime? now,
  }) {
    final today = PlanningDateUtils.dateOnly(now ?? DateTime.now());
    final map = <String, List<PlanningCalendarItem>>{};

    void add(DateTime date, PlanningCalendarItem item) {
      final key = PlanningDateUtils.dateKey(date);
      map.putIfAbsent(key, () => <PlanningCalendarItem>[]).add(item);
    }

    for (final requirement in planRequirements) {
      add(
        requirement.date,
        PlanningCalendarItem.fromRequirement(requirement),
      );
    }

    for (final todo in todos) {
      final deadline = todo.deadline;
      if (deadline == null) continue;
      add(
        deadline,
        PlanningCalendarItem.fromTodo(
          todo,
          isDebt: PlanningDateUtils.dateOnly(deadline).isBefore(today),
        ),
      );
    }

    for (final event in canvasEvents) {
      add(
        event.startAt,
        PlanningCalendarItem.fromCanvasEvent(event),
      );
    }

    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final rankCompare = a.sortRank.compareTo(b.sortRank);
        if (rankCompare != 0) return rankCompare;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    }

    return PlanningCalendarIndex(map);
  }

  List<PlanningCalendarItem> itemsFor(DateTime date) {
    return _itemsByDate[PlanningDateUtils.dateKey(date)] ?? const <PlanningCalendarItem>[];
  }
}

class PlanningCalendarItem {
  final String label;
  final bool isDebt;
  final bool isDeadline;
  final int sortRank;
  final PlanningItem normalizedItem;
  final StudyPlanRequirement? planRequirement;
  final TodoItem? todo;
  final CanvasCalendarEvent? canvasEvent;

  const PlanningCalendarItem({
    required this.label,
    required this.isDebt,
    required this.isDeadline,
    required this.sortRank,
    required this.normalizedItem,
    this.planRequirement,
    this.todo,
    this.canvasEvent,
  });

  factory PlanningCalendarItem.fromRequirement(StudyPlanRequirement requirement) {
    return PlanningCalendarItem(
      label: calendarLabelForRequirement(requirement),
      isDebt: false,
      isDeadline: requirement.plan.isDeadlineMarker,
      sortRank: requirement.plan.isDeadlineMarker ? 20 : 10,
      normalizedItem: PlanningItem.fromStudyPlanRequirement(requirement),
      planRequirement: requirement,
    );
  }

  factory PlanningCalendarItem.fromTodo(TodoItem todo, {required bool isDebt}) {
    return PlanningCalendarItem(
      label: '${todo.pdfLabel}: ${todo.title}',
      isDebt: isDebt,
      isDeadline: true,
      sortRank: 30,
      normalizedItem: PlanningItem.fromTodo(todo),
      todo: todo,
    );
  }

  factory PlanningCalendarItem.fromCanvasEvent(CanvasCalendarEvent event) {
    return PlanningCalendarItem(
      label: '${event.courseLabel}: ${event.timeLabel} ${event.title}',
      isDebt: false,
      isDeadline: event.isDeadline,
      sortRank: event.isDeadline ? 35 : 5,
      normalizedItem: PlanningItem.fromCanvasEvent(event),
      canvasEvent: event,
    );
  }

  bool get isDocumentLinked => normalizedItem.hasDocumentLink;
}

String calendarLabelForRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) {
    return '${requirement.projectTitle}: ⚑ ${requirement.plan.title}';
  }
  if (requirement.plan.isSingleTask) {
    return '${requirement.projectTitle}: ${requirement.plan.title}';
  }
  if (requirement.plan.isChecklist) {
    return '${requirement.projectTitle}: ${requirement.rangeLabel}';
  }
  return '${requirement.projectTitle}: ${requirement.plan.title} · ${requirement.rangeLabel}';
}
