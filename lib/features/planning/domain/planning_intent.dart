import '../data/study_planning_repository.dart';

/// User-facing planning intents. These are deliberately not the same as the
/// storage-level [StudyPlanKind] values: they describe what the user is trying
/// to accomplish before the app maps the work to its current plan model.
enum PlanningIntentType {
  studyMaterial,
  finishByDate,
  addTask,
  rememberDeadline,
  reviewTopics,
  buildRoutine,
  writeSomething,
}

extension PlanningIntentTypeX on PlanningIntentType {
  String get label {
    switch (this) {
      case PlanningIntentType.studyMaterial:
        return 'Study material';
      case PlanningIntentType.finishByDate:
        return 'Finish by a date';
      case PlanningIntentType.addTask:
        return 'Add one task';
      case PlanningIntentType.rememberDeadline:
        return 'Remember a deadline';
      case PlanningIntentType.reviewTopics:
        return 'Review topics';
      case PlanningIntentType.buildRoutine:
        return 'Build a routine';
      case PlanningIntentType.writeSomething:
        return 'Write something';
    }
  }

  String get actionLabel {
    switch (this) {
      case PlanningIntentType.studyMaterial:
        return 'Plan study work';
      case PlanningIntentType.finishByDate:
        return 'Create work plan';
      case PlanningIntentType.addTask:
        return 'Create task';
      case PlanningIntentType.rememberDeadline:
        return 'Create deadline';
      case PlanningIntentType.reviewTopics:
        return 'Create topic plan';
      case PlanningIntentType.buildRoutine:
        return 'Create routine';
      case PlanningIntentType.writeSomething:
        return 'Create writing plan';
    }
  }

  String get helperText {
    switch (this) {
      case PlanningIntentType.studyMaterial:
        return 'Use this for pages, chapters, articles, lectures, or exercises that should become dated study work.';
      case PlanningIntentType.finishByDate:
        return 'Use this when there is a measurable amount of work and a date where it should be done.';
      case PlanningIntentType.addTask:
        return 'Use this for one concrete action on one day.';
      case PlanningIntentType.rememberDeadline:
        return 'Use this for a due date, exam, presentation, or milestone that should add calendar pressure without generating workload by itself.';
      case PlanningIntentType.reviewTopics:
        return 'Use this for named topics, lectures, articles, or checklist items that should be distributed across study days.';
      case PlanningIntentType.buildRoutine:
        return 'Use this for repeating work such as daily flashcards, cases, practice sets, or weekly review.';
      case PlanningIntentType.writeSomething:
        return 'Use this for essays, thesis sections, drafts, outlines, or revision passes.';
    }
  }

  String get storageKind {
    switch (this) {
      case PlanningIntentType.addTask:
        return StudyPlanKind.singleTask;
      case PlanningIntentType.rememberDeadline:
        return StudyPlanKind.deadline;
      case PlanningIntentType.reviewTopics:
        return StudyPlanKind.checklist;
      case PlanningIntentType.buildRoutine:
        return StudyPlanKind.recurring;
      case PlanningIntentType.studyMaterial:
      case PlanningIntentType.finishByDate:
      case PlanningIntentType.writeSomething:
        return StudyPlanKind.progress;
    }
  }

  String get defaultUnitType {
    switch (this) {
      case PlanningIntentType.studyMaterial:
        return 'pages';
      case PlanningIntentType.writeSomething:
        return 'custom';
      case PlanningIntentType.finishByDate:
        return 'custom';
      case PlanningIntentType.reviewTopics:
        return 'topic';
      case PlanningIntentType.addTask:
        return 'task';
      case PlanningIntentType.rememberDeadline:
        return 'deadline';
      case PlanningIntentType.buildRoutine:
        return 'custom';
    }
  }

  String get defaultTitle {
    switch (this) {
      case PlanningIntentType.studyMaterial:
        return 'Study material';
      case PlanningIntentType.finishByDate:
        return 'Finish work';
      case PlanningIntentType.addTask:
        return 'New task';
      case PlanningIntentType.rememberDeadline:
        return 'Deadline';
      case PlanningIntentType.reviewTopics:
        return 'Review topics';
      case PlanningIntentType.buildRoutine:
        return 'Routine';
      case PlanningIntentType.writeSomething:
        return 'Write draft';
    }
  }

  String get singularUnitFallback {
    switch (this) {
      case PlanningIntentType.writeSomething:
        return 'section';
      case PlanningIntentType.finishByDate:
        return 'unit';
      case PlanningIntentType.buildRoutine:
        return 'item';
      default:
        return 'unit';
    }
  }

  String get pluralUnitFallback {
    switch (this) {
      case PlanningIntentType.writeSomething:
        return 'sections';
      case PlanningIntentType.finishByDate:
        return 'units';
      case PlanningIntentType.buildRoutine:
        return 'items';
      default:
        return 'units';
    }
  }

  String get shortUnitFallback {
    switch (this) {
      case PlanningIntentType.writeSomething:
        return 'sec.';
      case PlanningIntentType.buildRoutine:
        return 'item';
      default:
        return 'unit';
    }
  }
}
