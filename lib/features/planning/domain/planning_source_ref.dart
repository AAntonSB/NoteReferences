/// Stable source categories for planning data.
///
/// These values deliberately describe where a planning item comes from rather
/// than how it is rendered. The same source-backed item can later appear in
/// Today, Week, Month, project timelines, focus sessions, and recovery plans.
enum PlanningItemSource {
  studyPlan,
  pdfTodo,
  documentTodo,
  canvas,
  manual,
  externalCalendar,
  generatedRecovery,
}

enum PlanningItemType {
  generatedRequirement,
  task,
  deadline,
  event,
  studySession,
  review,
  handoff,
  buffer,
}

/// A normalized, UI-agnostic pointer back to the place where a planning item
/// came from.
class PlanningSourceRef {
  final PlanningItemSource source;
  final String sourceId;
  final String? projectId;
  final String? documentId;
  final String? url;
  final int? pageNumber;

  const PlanningSourceRef({
    required this.source,
    required this.sourceId,
    this.projectId,
    this.documentId,
    this.url,
    this.pageNumber,
  });

  bool get hasDocumentLink {
    final value = documentId;
    return value != null && value.trim().isNotEmpty;
  }

  bool get hasExternalLink {
    final value = url;
    return value != null && value.trim().isNotEmpty;
  }
}
