import '../../canvas/data/canvas_import_repository.dart';
import '../../notes/data/note_repository.dart';
import '../data/study_planning_repository.dart';
import 'planning_source_ref.dart';

/// A normalized planning item that can be consumed by different planning
/// surfaces without each surface re-implementing source-specific merging.
class PlanningItem {
  final String id;
  final PlanningItemSource source;
  final PlanningItemType type;
  final String title;
  final String? body;
  final String? projectId;
  final String projectLabel;
  final String detailLabel;
  final DateTime date;
  final DateTime? dueAt;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool allDay;
  final int? estimateMinutes;
  final int? minBlockMinutes;
  final PlanningPriority priority;
  final PlanningStatus status;
  final PlanningSourceRef sourceRef;

  const PlanningItem({
    required this.id,
    required this.source,
    required this.type,
    required this.title,
    required this.body,
    required this.projectId,
    required this.projectLabel,
    required this.detailLabel,
    required this.date,
    this.dueAt,
    this.startAt,
    this.endAt,
    this.allDay = true,
    this.estimateMinutes,
    this.minBlockMinutes,
    this.priority = PlanningPriority.normal,
    this.status = PlanningStatus.open,
    required this.sourceRef,
  });

  bool get isDeadline => type == PlanningItemType.deadline || dueAt != null;
  bool get isEvent => type == PlanningItemType.event;
  bool get isDone => status == PlanningStatus.done;
  bool get hasDocumentLink => sourceRef.hasDocumentLink;
  String get compactLabel => '$projectLabel: $title';
  String get sortLabel => compactLabel.toLowerCase();

  factory PlanningItem.fromStudyPlanRequirement(StudyPlanRequirement requirement) {
    final plan = requirement.plan;
    final type = plan.isDeadlineMarker ? PlanningItemType.deadline : PlanningItemType.generatedRequirement;
    final title = _titleForPlanRequirement(requirement);
    final date = PlanningDateUtils.dateOnly(requirement.date);
    return PlanningItem(
      id: 'plan-${plan.id}-${PlanningDateUtils.shortDate(date)}',
      source: PlanningItemSource.studyPlan,
      type: type,
      title: title,
      body: _bodyForPlanRequirement(requirement),
      projectId: plan.projectId,
      projectLabel: requirement.projectTitle,
      detailLabel: _detailForPlanRequirement(requirement),
      date: date,
      dueAt: plan.isDeadlineMarker ? date : null,
      allDay: true,
      priority: plan.isDeadlineMarker ? PlanningPriority.high : PlanningPriority.normal,
      sourceRef: PlanningSourceRef(
        source: PlanningItemSource.studyPlan,
        sourceId: plan.id,
        projectId: plan.projectId,
      ),
    );
  }

  factory PlanningItem.fromTodo(TodoItem todo) {
    final due = todo.deadline == null ? null : PlanningDateUtils.dateOnly(todo.deadline!);
    final source = todo.sourceType == kTodoSourceDocumentNote
        ? PlanningItemSource.documentTodo
        : PlanningItemSource.pdfTodo;
    return PlanningItem(
      id: 'todo-${todo.id}',
      source: source,
      type: PlanningItemType.task,
      title: todo.title,
      body: todo.body,
      projectId: null,
      projectLabel: todo.pdfLabel,
      detailLabel: _priorityLabel(todo.priority),
      date: due ?? PlanningDateUtils.dateOnly(DateTime.now()),
      dueAt: due,
      allDay: true,
      priority: _priorityFromTodo(todo.priority),
      status: todo.isCompleted ? PlanningStatus.done : PlanningStatus.open,
      sourceRef: PlanningSourceRef(
        source: source,
        sourceId: todo.id,
        documentId: todo.note.documentId,
        pageNumber: todo.pageNumber,
      ),
    );
  }



  factory PlanningItem.fromPlanningEntry(PlanningEntry entry, {String? projectLabel}) {
    final calendarDate = entry.calendarDate == null
        ? PlanningDateUtils.dateOnly(DateTime.now())
        : PlanningDateUtils.dateOnly(entry.calendarDate!);
    final type = entry.isDeadline
        ? PlanningItemType.deadline
        : entry.isEvent
            ? PlanningItemType.event
            : PlanningItemType.task;
    return PlanningItem(
      id: 'entry-${entry.id}',
      source: PlanningItemSource.manual,
      type: type,
      title: entry.title,
      body: entry.notes,
      projectId: entry.projectId,
      projectLabel: projectLabel ?? 'Inbox',
      detailLabel: PlanningEntryKind.label(entry.kind),
      date: calendarDate,
      dueAt: entry.dueAt,
      startAt: entry.startAt,
      endAt: entry.endAt,
      allDay: entry.allDay,
      estimateMinutes: entry.estimateMinutes,
      priority: _priorityFromPlanningEntry(entry.priority),
      status: entry.isDone ? PlanningStatus.done : PlanningStatus.open,
      sourceRef: PlanningSourceRef(
        source: PlanningItemSource.manual,
        sourceId: entry.id,
        projectId: entry.projectId,
      ),
    );
  }

  factory PlanningItem.fromCanvasEvent(CanvasCalendarEvent event) {
    final date = PlanningDateUtils.dateOnly(event.startAt);
    return PlanningItem(
      id: event.id,
      source: PlanningItemSource.canvas,
      type: event.isDeadline ? PlanningItemType.deadline : PlanningItemType.event,
      title: event.title,
      body: null,
      projectId: null,
      projectLabel: event.courseLabel,
      detailLabel: event.isDeadline ? 'Canvas deadline' : 'Canvas event',
      date: date,
      dueAt: event.isDeadline ? event.startAt : null,
      startAt: event.startAt,
      endAt: event.endAt,
      allDay: event.isDeadline,
      priority: event.isDeadline ? PlanningPriority.high : PlanningPriority.normal,
      sourceRef: PlanningSourceRef(
        source: PlanningItemSource.canvas,
        sourceId: event.id,
        url: event.htmlUrl,
      ),
    );
  }
}

enum PlanningPriority { low, normal, high }

enum PlanningStatus { open, done, archived }

class PlanningDateUtils {
  const PlanningDateUtils._();

  static DateTime dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static bool sameDate(DateTime a, DateTime b) {
    final left = dateOnly(a);
    final right = dateOnly(b);
    return left.year == right.year && left.month == right.month && left.day == right.day;
  }

  static DateTime startOfWeek(DateTime date) {
    final day = dateOnly(date);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static String dateKey(DateTime value) {
    final date = dateOnly(value);
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String shortDate(DateTime value) {
    final date = dateOnly(value);
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }
}

PlanningPriority _priorityFromTodo(String priority) {
  switch (priority) {
    case kTodoPriorityHigh:
      return PlanningPriority.high;
    case kTodoPriorityLow:
      return PlanningPriority.low;
    case kTodoPriorityMedium:
    default:
      return PlanningPriority.normal;
  }
}

String _priorityLabel(String priority) {
  switch (priority) {
    case kTodoPriorityHigh:
      return 'High priority';
    case kTodoPriorityLow:
      return 'Low priority';
    case kTodoPriorityMedium:
    default:
      return 'Medium priority';
  }
}

String _titleForPlanRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) return requirement.plan.title;
  if (requirement.plan.isSingleTask) return requirement.plan.title;
  if (requirement.plan.isChecklist) return '${requirement.plan.title} · ${requirement.rangeLabel}';
  return '${requirement.plan.title} · ${requirement.rangeLabel}';
}

String _detailForPlanRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) return 'Deadline';
  if (requirement.plan.isSingleTask) return 'Single task';
  if (requirement.plan.isChecklist) return 'Checklist item';
  return '${requirement.unitCount} ${requirement.plan.unitNounForCount(requirement.unitCount)}';
}

String _bodyForPlanRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) {
    return 'Deadline marker. It appears on the calendar as a fixed pressure point.';
  }
  if (requirement.plan.isSingleTask) {
    return 'Single task. If missed, it becomes unresolved study debt.';
  }
  if (requirement.plan.isChecklist) {
    return 'Checklist item. If missed, it stays visible as study debt.';
  }
  if (requirement.plan.isRecurring) {
    return 'Recurring plan. If missed, it becomes visible study debt.';
  }
  return 'Generated from plan. If missed, the remaining pace is recalculated.';
}


PlanningPriority _priorityFromPlanningEntry(String priority) {
  switch (PlanningEntryPriority.normalize(priority)) {
    case PlanningEntryPriority.high:
      return PlanningPriority.high;
    case PlanningEntryPriority.low:
      return PlanningPriority.low;
    case PlanningEntryPriority.normal:
    default:
      return PlanningPriority.normal;
  }
}
