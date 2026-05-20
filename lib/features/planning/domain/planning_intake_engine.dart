import '../data/study_planning_repository.dart';
import 'planning_draft.dart';
import 'planning_intent.dart';

class PlanningIntakeContext {
  final StudyProject? project;
  final DateTime now;

  const PlanningIntakeContext({
    required this.project,
    required this.now,
  });
}

class PlanningIntakeEngine {
  const PlanningIntakeEngine();

  PlanningDraft draftFromIntent(
    PlanningIntentType intent,
    PlanningIntakeContext context,
  ) {
    final today = _dateOnly(context.now);
    final projectDeadline = context.project?.deadline == null
        ? null
        : _dateOnly(context.project!.deadline!);
    final fallbackDue = projectDeadline ?? today.add(const Duration(days: 7));

    final draft = PlanningDraft(
      intent: intent,
      title: intent.defaultTitle,
      unitType: intent.defaultUnitType,
      startUnit: 1,
      endUnit: _defaultEndUnit(intent),
      dailyTarget: _defaultDailyTarget(intent),
      startDate: today,
      dueDate: intent == PlanningIntentType.buildRoutine || intent == PlanningIntentType.addTask || intent == PlanningIntentType.rememberDeadline
          ? null
          : fallbackDue,
      taskDate: intent == PlanningIntentType.addTask || intent == PlanningIntentType.rememberDeadline
          ? projectDeadline ?? today
          : null,
      weekendsOff: intent != PlanningIntentType.addTask && intent != PlanningIntentType.rememberDeadline,
      checklistItems: _defaultChecklistItems(intent),
      customUnitSingular: intent.defaultUnitType == 'custom' ? intent.singularUnitFallback : null,
      customUnitPlural: intent.defaultUnitType == 'custom' ? intent.pluralUnitFallback : null,
      customUnitLabel: intent.defaultUnitType == 'custom' ? intent.shortUnitFallback : null,
      estimateMinutes: null,
      questions: const <PlanningDraftQuestion>[],
    );

    return draft.copyWith(questions: questionsFor(draft));
  }

  PlanningDraft parseQuickInput(
    String input,
    PlanningIntakeContext context,
  ) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return draftFromIntent(PlanningIntentType.addTask, context);
    }

    final lower = raw.toLowerCase();
    final intent = _inferIntent(lower);
    var draft = draftFromIntent(intent, context);

    final dueDate = _extractDueDate(lower, context.now);
    final taskDate = _extractTaskDate(lower, context.now) ?? dueDate;
    final estimate = _extractEstimateMinutes(lower);
    final unitInfo = _extractUnitRange(lower, intent);

    var title = _cleanQuickTitle(raw);
    if (title.isEmpty) title = intent.defaultTitle;

    draft = draft.copyWith(
      title: _sentenceCase(title),
      dueDate: draft.usesDueDate ? dueDate ?? draft.dueDate : null,
      clearDueDate: !draft.usesDueDate,
      taskDate: draft.usesSingleDate ? taskDate ?? draft.taskDate : null,
      clearTaskDate: !draft.usesSingleDate,
      estimateMinutes: estimate,
    );

    if (unitInfo != null && draft.usesUnits) {
      draft = draft.copyWith(
        unitType: unitInfo.unitType,
        startUnit: unitInfo.start,
        endUnit: unitInfo.end,
      );
    }

    if (intent == PlanningIntentType.reviewTopics) {
      final topics = _extractTopics(raw);
      if (topics.isNotEmpty) {
        draft = draft.copyWith(checklistItems: topics);
      }
    }

    return draft.copyWith(questions: questionsFor(draft));
  }

  List<PlanningDraftQuestion> questionsFor(PlanningDraft draft) {
    final result = <PlanningDraftQuestion>[];
    if (draft.title.trim().isEmpty || _genericTitles.contains(draft.title.trim())) {
      result.add(
        const PlanningDraftQuestion(
          id: 'title',
          text: 'What should this be called?',
        ),
      );
    }

    if (draft.usesSingleDate && draft.taskDate == null) {
      result.add(
        const PlanningDraftQuestion(
          id: 'taskDate',
          text: 'When should this appear?',
        ),
      );
    }

    if (draft.usesDueDate && draft.dueDate == null) {
      result.add(
        const PlanningDraftQuestion(
          id: 'dueDate',
          text: 'When should this be done?',
        ),
      );
    }

    if (draft.usesRange && draft.endUnit <= draft.startUnit) {
      result.add(
        const PlanningDraftQuestion(
          id: 'amount',
          text: 'How much work is there?',
          helperText: 'For example pages 1–45, chapters 1–4, or sections 1–3.',
        ),
      );
    }

    if (draft.usesChecklist && draft.checklistItems.isEmpty) {
      result.add(
        const PlanningDraftQuestion(
          id: 'checklist',
          text: 'Which topics or items should be planned?',
        ),
      );
    }

    return result;
  }

  static final _genericTitles = <String>{
    for (final intent in PlanningIntentType.values) intent.defaultTitle,
  };

  static int _defaultEndUnit(PlanningIntentType intent) {
    switch (intent) {
      case PlanningIntentType.studyMaterial:
        return 20;
      case PlanningIntentType.writeSomething:
        return 3;
      case PlanningIntentType.finishByDate:
        return 5;
      case PlanningIntentType.buildRoutine:
        return 1;
      default:
        return 1;
    }
  }

  static int _defaultDailyTarget(PlanningIntentType intent) {
    switch (intent) {
      case PlanningIntentType.buildRoutine:
        return 1;
      default:
        return 1;
    }
  }

  static List<String> _defaultChecklistItems(PlanningIntentType intent) {
    return const <String>[];
  }

  static PlanningIntentType _inferIntent(String lower) {
    if (lower.contains('every ') || lower.contains('daily') || lower.contains('weekly')) {
      return PlanningIntentType.buildRoutine;
    }
    if (lower.contains('deadline') || lower.contains('exam') || lower.contains('presentation')) {
      return PlanningIntentType.rememberDeadline;
    }
    if (lower.contains('write') || lower.contains('draft') || lower.contains('essay') || lower.contains('thesis')) {
      return PlanningIntentType.writeSomething;
    }
    if (lower.contains('topic') || lower.contains('topics') || lower.contains('review lectures')) {
      return PlanningIntentType.reviewTopics;
    }
    if (lower.contains('read') || lower.contains('study') || lower.contains('pages') || lower.contains('chapter')) {
      return PlanningIntentType.studyMaterial;
    }
    if (lower.contains('finish') || lower.contains('complete') || lower.contains('solve')) {
      return PlanningIntentType.finishByDate;
    }
    return PlanningIntentType.addTask;
  }

  static DateTime? _extractDueDate(String lower, DateTime now) {
    final byMatch = RegExp(r'\bby\s+([a-z]+|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)').firstMatch(lower);
    if (byMatch != null) return _parseDatePhrase(byMatch.group(1)!, now);
    final dueMatch = RegExp(r'\bdue\s+([a-z]+|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)').firstMatch(lower);
    if (dueMatch != null) return _parseDatePhrase(dueMatch.group(1)!, now);
    if (lower.contains('this week')) return _nextWeekday(DateTime.sunday, now);
    return null;
  }

  static DateTime? _extractTaskDate(String lower, DateTime now) {
    final onMatch = RegExp(r'\bon\s+([a-z]+|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)').firstMatch(lower);
    if (onMatch != null) return _parseDatePhrase(onMatch.group(1)!, now);
    if (lower.contains('tomorrow')) return _dateOnly(now.add(const Duration(days: 1)));
    if (lower.contains('today')) return _dateOnly(now);
    return null;
  }

  static int? _extractEstimateMinutes(String lower) {
    final slash = RegExp(r'/(\d+)\s*(m|min|h|hr|hrs|hour|hours)?\b').firstMatch(lower);
    final match = slash ?? RegExp(r'\b(\d+)\s*(m|min|h|hr|hrs|hour|hours)\b').firstMatch(lower);
    if (match == null) return null;
    final amount = int.tryParse(match.group(1)!);
    if (amount == null) return null;
    final unit = match.group(2) ?? 'm';
    if (unit.startsWith('h')) return amount * 60;
    return amount;
  }

  static _UnitRange? _extractUnitRange(String lower, PlanningIntentType intent) {
    final patterns = <String, String>{
      r'\bpages?\s+(\d+)\s*[-–]\s*(\d+)': 'pages',
      r'\bpp\.?\s*(\d+)\s*[-–]\s*(\d+)': 'pages',
      r'\bchapters?\s+(\d+)\s*[-–]\s*(\d+)': 'chapters',
      r'\bsections?\s+(\d+)\s*[-–]\s*(\d+)': 'sections',
      r'\bexercises?\s+(\d+)\s*[-–]\s*(\d+)': 'exercises',
    };
    for (final entry in patterns.entries) {
      final match = RegExp(entry.key).firstMatch(lower);
      if (match == null) continue;
      final start = int.tryParse(match.group(1)!);
      final end = int.tryParse(match.group(2)!);
      if (start == null || end == null) continue;
      return _UnitRange(entry.value, start, end < start ? start : end);
    }

    final singlePatterns = <String, String>{
      r'\bchapter\s+(\d+)': 'chapters',
      r'\bsection\s+(\d+)': 'sections',
      r'\bexercise\s+(\d+)': 'exercises',
      r'\bpage\s+(\d+)': 'pages',
    };
    for (final entry in singlePatterns.entries) {
      final match = RegExp(entry.key).firstMatch(lower);
      if (match == null) continue;
      final value = int.tryParse(match.group(1)!);
      if (value == null) continue;
      return _UnitRange(entry.value, value, value);
    }

    if (intent == PlanningIntentType.studyMaterial) {
      final number = RegExp(r'\b(\d+)\s+pages?\b').firstMatch(lower);
      if (number != null) {
        final amount = int.tryParse(number.group(1)!);
        if (amount != null) return _UnitRange('pages', 1, amount);
      }
    }
    return null;
  }

  static List<String> _extractTopics(String raw) {
    final chunks = raw
        .split(RegExp(r'[,;\n]'))
        .map((item) => _cleanQuickTitle(item).trim())
        .where((item) => item.length > 2)
        .toList(growable: false);
    if (chunks.length <= 1) return const <String>[];
    return chunks;
  }

  static String _cleanQuickTitle(String raw) {
    var value = raw.trim();
    value = value.replaceAll(RegExp(r'/(\d+)\s*(m|min|h|hr|hrs|hour|hours)?\b', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\bby\s+([a-z]+|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\bdue\s+([a-z]+|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\bon\s+([a-z]+|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)', caseSensitive: false), '');
    value = value.replaceAll(RegExp(r'\b(today|tomorrow|this week)\b', caseSensitive: false), '');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _sentenceCase(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, 1).toUpperCase() + value.substring(1);
  }

  static DateTime? _parseDatePhrase(String phrase, DateTime now) {
    final clean = phrase.trim().toLowerCase();
    if (clean == 'today') return _dateOnly(now);
    if (clean == 'tomorrow') return _dateOnly(now.add(const Duration(days: 1)));

    final weekday = _weekdayNumber(clean);
    if (weekday != null) return _nextWeekday(weekday, now);

    final numeric = RegExp(r'^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?$').firstMatch(clean);
    if (numeric != null) {
      final day = int.tryParse(numeric.group(1)!);
      final month = int.tryParse(numeric.group(2)!);
      var year = int.tryParse(numeric.group(3) ?? '') ?? now.year;
      if (year < 100) year += 2000;
      if (day == null || month == null) return null;
      try {
        return DateTime(year, month, day);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  static int? _weekdayNumber(String value) {
    switch (value) {
      case 'mon':
      case 'monday':
        return DateTime.monday;
      case 'tue':
      case 'tues':
      case 'tuesday':
        return DateTime.tuesday;
      case 'wed':
      case 'wednesday':
        return DateTime.wednesday;
      case 'thu':
      case 'thur':
      case 'thurs':
      case 'thursday':
        return DateTime.thursday;
      case 'fri':
      case 'friday':
        return DateTime.friday;
      case 'sat':
      case 'saturday':
        return DateTime.saturday;
      case 'sun':
      case 'sunday':
        return DateTime.sunday;
    }
    return null;
  }

  static DateTime _nextWeekday(int weekday, DateTime now) {
    final today = _dateOnly(now);
    var delta = weekday - today.weekday;
    if (delta < 0) delta += 7;
    return today.add(Duration(days: delta));
  }

  static DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
}

class _UnitRange {
  final String unitType;
  final int start;
  final int end;

  const _UnitRange(this.unitType, this.start, this.end);
}
