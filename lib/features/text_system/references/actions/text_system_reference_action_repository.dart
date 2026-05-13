import 'text_system_reference_action_models.dart';

/// Repository boundary for reference/citation actions.
///
/// In production this should be backed by the app's source/document/project/todo
/// stores. The memory implementation below exists so Phase 15J can be wired and
/// tested without blocking on those app-wide repositories.
abstract class TextSystemReferenceActionRepository {
  const TextSystemReferenceActionRepository();

  Future<List<TextSystemReferenceTarget>> searchTargets({
    required String query,
    required Set<TextSystemReferenceTargetKind> kinds,
    int limit = 12,
  });

  Future<List<TextSystemReferenceTarget>> recentTargets({
    required Set<TextSystemReferenceTargetKind> kinds,
    int limit = 6,
  });

  Future<TextSystemReferenceTarget> createTarget(
    TextSystemReferenceActionDraft draft,
  );

  Future<TextSystemReferenceTarget?> resolveTarget(String targetId);
}

class TextSystemMemoryReferenceActionRepository
    extends TextSystemReferenceActionRepository {
  TextSystemMemoryReferenceActionRepository({
    List<TextSystemReferenceTarget> seedTargets = const <TextSystemReferenceTarget>[],
  }) : _targets = <TextSystemReferenceTarget>[...seedTargets];

  final List<TextSystemReferenceTarget> _targets;

  @override
  Future<List<TextSystemReferenceTarget>> searchTargets({
    required String query,
    required Set<TextSystemReferenceTargetKind> kinds,
    int limit = 12,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = _targets.where((target) {
      if (kinds.isNotEmpty && !kinds.contains(target.kind)) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final haystack = <String?>[
        target.title,
        target.subtitle,
        target.citationKey,
        target.uri?.toString(),
        ...target.metadata.values.map((value) => value?.toString()),
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();

    filtered.sort(_sortByUpdatedThenTitle);
    return filtered.take(limit).toList(growable: false);
  }

  @override
  Future<List<TextSystemReferenceTarget>> recentTargets({
    required Set<TextSystemReferenceTargetKind> kinds,
    int limit = 6,
  }) async {
    final filtered = _targets.where((target) {
      return kinds.isEmpty || kinds.contains(target.kind);
    }).toList();
    filtered.sort(_sortByUpdatedThenTitle);
    return filtered.take(limit).toList(growable: false);
  }

  @override
  Future<TextSystemReferenceTarget> createTarget(
    TextSystemReferenceActionDraft draft,
  ) async {
    final now = DateTime.now();
    final target = TextSystemReferenceTarget(
      id: TextSystemReferenceActionIds.newTargetId(draft.targetKind, now: now),
      kind: draft.targetKind,
      title: draft.effectiveLabel,
      subtitle: _subtitleForDraft(draft),
      uri: draft.uri,
      citationKey: draft.citationKey,
      createdAt: now,
      updatedAt: now,
      metadata: draft.metadata,
    );
    _targets.insert(0, target);
    return target;
  }

  @override
  Future<TextSystemReferenceTarget?> resolveTarget(String targetId) async {
    for (final target in _targets) {
      if (target.id == targetId) return target;
    }
    return null;
  }

  static int _sortByUpdatedThenTitle(
    TextSystemReferenceTarget a,
    TextSystemReferenceTarget b,
  ) {
    final aUpdated = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bUpdated = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final updated = bUpdated.compareTo(aUpdated);
    if (updated != 0) return updated;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  static String? _subtitleForDraft(TextSystemReferenceActionDraft draft) {
    switch (draft.actionType) {
      case TextSystemReferenceActionType.citation:
        return draft.citationKey == null ? 'Citation' : 'Citation key: ${draft.citationKey}';
      case TextSystemReferenceActionType.source:
        return draft.uri?.toString() ?? 'Source';
      case TextSystemReferenceActionType.document:
        return 'Document';
      case TextSystemReferenceActionType.project:
        return 'Project';
      case TextSystemReferenceActionType.todo:
        return 'Todo';
      case TextSystemReferenceActionType.link:
        return draft.uri?.toString() ?? 'Link';
    }
  }
}

class TextSystemReferenceActionRepositorySeed {
  const TextSystemReferenceActionRepositorySeed._();

  static List<TextSystemReferenceTarget> academicDemoTargets() {
    final now = DateTime.now();
    return <TextSystemReferenceTarget>[
      TextSystemReferenceTarget(
        id: 'citation_acemoglu_restrepo_2019',
        kind: TextSystemReferenceTargetKind.citation,
        title: 'Acemoglu & Restrepo (2019)',
        subtitle: 'Automation and new tasks',
        citationKey: 'acemogluRestrepo2019',
        createdAt: now.subtract(const Duration(days: 8)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
      TextSystemReferenceTarget(
        id: 'citation_aghion_howitt_1992',
        kind: TextSystemReferenceTargetKind.citation,
        title: 'Aghion & Howitt (1992)',
        subtitle: 'Creative destruction and growth',
        citationKey: 'aghionHowitt1992',
        createdAt: now.subtract(const Duration(days: 12)),
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      TextSystemReferenceTarget(
        id: 'source_pdf_ai_productivity_notes',
        kind: TextSystemReferenceTargetKind.source,
        title: 'AI productivity notes',
        subtitle: 'PDF source',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(hours: 12)),
      ),
      TextSystemReferenceTarget(
        id: 'document_literature_review',
        kind: TextSystemReferenceTargetKind.document,
        title: 'Literature review',
        subtitle: 'Internal document',
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now.subtract(const Duration(days: 4)),
      ),
    ];
  }
}
