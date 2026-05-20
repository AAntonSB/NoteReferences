import 'planning_intent.dart';

class PlanningDraftQuestion {
  final String id;
  final String text;
  final String? helperText;

  const PlanningDraftQuestion({
    required this.id,
    required this.text,
    this.helperText,
  });
}

class PlanningDraft {
  final PlanningIntentType intent;
  final String title;
  final String unitType;
  final int startUnit;
  final int endUnit;
  final int dailyTarget;
  final DateTime startDate;
  final DateTime? dueDate;
  final DateTime? taskDate;
  final bool weekendsOff;
  final List<String> checklistItems;
  final String? customUnitSingular;
  final String? customUnitPlural;
  final String? customUnitLabel;
  final int? estimateMinutes;
  final List<PlanningDraftQuestion> questions;

  const PlanningDraft({
    required this.intent,
    required this.title,
    required this.unitType,
    required this.startUnit,
    required this.endUnit,
    required this.dailyTarget,
    required this.startDate,
    required this.dueDate,
    required this.taskDate,
    required this.weekendsOff,
    required this.checklistItems,
    required this.customUnitSingular,
    required this.customUnitPlural,
    required this.customUnitLabel,
    required this.estimateMinutes,
    required this.questions,
  });

  PlanningDraft copyWith({
    PlanningIntentType? intent,
    String? title,
    String? unitType,
    int? startUnit,
    int? endUnit,
    int? dailyTarget,
    DateTime? startDate,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? taskDate,
    bool clearTaskDate = false,
    bool? weekendsOff,
    List<String>? checklistItems,
    String? customUnitSingular,
    bool clearCustomUnitSingular = false,
    String? customUnitPlural,
    bool clearCustomUnitPlural = false,
    String? customUnitLabel,
    bool clearCustomUnitLabel = false,
    int? estimateMinutes,
    bool clearEstimateMinutes = false,
    List<PlanningDraftQuestion>? questions,
  }) {
    return PlanningDraft(
      intent: intent ?? this.intent,
      title: title ?? this.title,
      unitType: unitType ?? this.unitType,
      startUnit: startUnit ?? this.startUnit,
      endUnit: endUnit ?? this.endUnit,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      startDate: startDate ?? this.startDate,
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      taskDate: clearTaskDate ? null : taskDate ?? this.taskDate,
      weekendsOff: weekendsOff ?? this.weekendsOff,
      checklistItems: checklistItems ?? this.checklistItems,
      customUnitSingular: clearCustomUnitSingular
          ? null
          : customUnitSingular ?? this.customUnitSingular,
      customUnitPlural: clearCustomUnitPlural
          ? null
          : customUnitPlural ?? this.customUnitPlural,
      customUnitLabel: clearCustomUnitLabel
          ? null
          : customUnitLabel ?? this.customUnitLabel,
      estimateMinutes: clearEstimateMinutes ? null : estimateMinutes ?? this.estimateMinutes,
      questions: questions ?? this.questions,
    );
  }

  String get storageKind => intent.storageKind;

  bool get usesRange => storageKind == 'progress';
  bool get usesRoutine => storageKind == 'recurring';
  bool get usesChecklist => storageKind == 'checklist';
  bool get usesSingleDate => storageKind == 'singleTask' || storageKind == 'deadline';
  bool get usesDueDate => usesRange || usesChecklist;
  bool get usesStartDate => usesRange || usesChecklist || usesRoutine;
  bool get usesUnits => usesRange || usesRoutine;
  bool get usesWeekends => usesRange || usesChecklist || usesRoutine;

  bool get hasCustomUnits => unitType == 'custom';

  int get totalUnits => (endUnit - startUnit + 1).clamp(1, 999999).toInt();
}
