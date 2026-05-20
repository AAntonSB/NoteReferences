import '../../canvas/data/canvas_import_repository.dart';
import '../../notes/data/note_repository.dart';
import '../data/study_planning_repository.dart';
import 'planning_item.dart';

class PlanningWeekStyle {
  final int themeIndex;
  final int deadlinePressure;

  const PlanningWeekStyle({required this.themeIndex, required this.deadlinePressure});
}

class PlanningPressure {
  const PlanningPressure._();

  static Map<String, PlanningWeekStyle> weekStylesForMonths({
    required List<DateTime> months,
    required List<DateTime> deadlineDates,
  }) {
    if (months.isEmpty) return const <String, PlanningWeekStyle>{};

    final firstWeek = PlanningDateUtils.startOfWeek(DateTime(months.first.year, months.first.month));
    final lastMonth = months.last;
    final lastWeek = PlanningDateUtils.startOfWeek(DateTime(lastMonth.year, lastMonth.month + 1, 0));
    final result = <String, PlanningWeekStyle>{};
    var cursor = firstWeek;

    while (!cursor.isAfter(lastWeek)) {
      final weekIndex = cursor.difference(DateTime(2000, 1, 3)).inDays ~/ 7;
      final pressure = deadlinePressureForWeek(cursor, deadlineDates);
      result[PlanningDateUtils.dateKey(cursor)] = PlanningWeekStyle(
        themeIndex: weekIndex.abs() % 4,
        deadlinePressure: pressure,
      );
      cursor = cursor.add(const Duration(days: 7));
    }

    return result;
  }

  static int deadlinePressureForWeek(DateTime weekStart, List<DateTime> deadlineDates) {
    var pressure = 0;
    for (final deadline in deadlineDates) {
      final deadlineWeek = PlanningDateUtils.startOfWeek(deadline);
      final weeksUntil = deadlineWeek.difference(weekStart).inDays ~/ 7;
      if (weeksUntil < 0 || weeksUntil > 2) continue;
      final nextPressure = switch (weeksUntil) {
        0 => 3,
        1 => 2,
        2 => 1,
        _ => 0,
      };
      if (nextPressure > pressure) pressure = nextPressure;
    }
    return pressure;
  }

  static List<DateTime> deadlineDatesForSources({
    required StudyPlanningRepository planningRepository,
    required List<TodoItem> todos,
    required List<CanvasCalendarEvent> canvasEvents,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final start = PlanningDateUtils.dateOnly(rangeStart);
    final end = PlanningDateUtils.dateOnly(rangeEnd);

    bool inRange(DateTime date) {
      final value = PlanningDateUtils.dateOnly(date);
      return !value.isBefore(start) && !value.isAfter(end);
    }

    final dates = <DateTime>[];
    for (final project in planningRepository.projects) {
      final deadline = project.deadline;
      if (deadline != null && inRange(deadline)) dates.add(PlanningDateUtils.dateOnly(deadline));
    }
    for (final plan in planningRepository.plans) {
      final deadline = plan.deadline ?? plan.taskDate;
      if (deadline != null && inRange(deadline)) dates.add(PlanningDateUtils.dateOnly(deadline));
    }
    for (final todo in todos) {
      final deadline = todo.deadline;
      if (deadline != null && inRange(deadline)) dates.add(PlanningDateUtils.dateOnly(deadline));
    }
    for (final event in canvasEvents) {
      if (event.isDeadline && inRange(event.startAt)) {
        dates.add(PlanningDateUtils.dateOnly(event.startAt));
      }
    }

    dates.sort();
    return dates;
  }
}
