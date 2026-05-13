import '../structure/text_system_document_structure.dart';

class TextSystemReferenceIndex {
  const TextSystemReferenceIndex({
    required this.buckets,
    required this.totalCount,
  });

  factory TextSystemReferenceIndex.fromStructure(TextSystemDocumentStructure structure) {
    final preferredOrder = <TextSystemStructureReferenceKind>[
      TextSystemStructureReferenceKind.citation,
      TextSystemStructureReferenceKind.source,
      TextSystemStructureReferenceKind.link,
      TextSystemStructureReferenceKind.footnote,
      TextSystemStructureReferenceKind.project,
      TextSystemStructureReferenceKind.todo,
      TextSystemStructureReferenceKind.figure,
      TextSystemStructureReferenceKind.table,
      TextSystemStructureReferenceKind.unknown,
    ];

    final referencesByKind = <TextSystemStructureReferenceKind, List<TextSystemStructureReference>>{};
    for (final reference in structure.references) {
      referencesByKind.putIfAbsent(reference.kind, () => <TextSystemStructureReference>[]).add(reference);
    }

    final buckets = <TextSystemReferenceBucket>[
      for (final kind in preferredOrder)
        if ((referencesByKind[kind] ?? const <TextSystemStructureReference>[]).isNotEmpty)
          TextSystemReferenceBucket(
            kind: kind,
            references: List<TextSystemStructureReference>.unmodifiable(referencesByKind[kind]!),
          ),
    ];

    return TextSystemReferenceIndex(
      buckets: List<TextSystemReferenceBucket>.unmodifiable(buckets),
      totalCount: structure.references.length,
    );
  }

  final List<TextSystemReferenceBucket> buckets;
  final int totalCount;

  bool get isEmpty => totalCount == 0;
  bool get isNotEmpty => !isEmpty;

  int countFor(TextSystemStructureReferenceKind kind) {
    for (final bucket in buckets) {
      if (bucket.kind == kind) return bucket.count;
    }
    return 0;
  }

  Iterable<TextSystemStructureReference> get allReferences sync* {
    for (final bucket in buckets) {
      yield* bucket.references;
    }
  }

  List<TextSystemStructureReference> get navigationPreview {
    return allReferences.take(8).toList(growable: false);
  }

  String get compactLabel {
    if (isEmpty) return 'No structured references';
    final parts = <String>[];
    final citations = countFor(TextSystemStructureReferenceKind.citation);
    final sources = countFor(TextSystemStructureReferenceKind.source);
    final links = countFor(TextSystemStructureReferenceKind.link);
    final todos = countFor(TextSystemStructureReferenceKind.todo);

    if (citations > 0) parts.add('$citations citation${citations == 1 ? '' : 's'}');
    if (sources > 0) parts.add('$sources source${sources == 1 ? '' : 's'}');
    if (links > 0) parts.add('$links link${links == 1 ? '' : 's'}');
    if (todos > 0) parts.add('$todos todo${todos == 1 ? '' : 's'}');

    if (parts.isEmpty) return '$totalCount reference${totalCount == 1 ? '' : 's'}';
    return parts.join(' · ');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'totalCount': totalCount,
      'compactLabel': compactLabel,
      'buckets': [for (final bucket in buckets) bucket.toJson()],
    };
  }
}

class TextSystemReferenceBucket {
  const TextSystemReferenceBucket({
    required this.kind,
    required this.references,
  });

  final TextSystemStructureReferenceKind kind;
  final List<TextSystemStructureReference> references;

  int get count => references.length;
  String get label => kind.label;
  String get countLabel => '$count ${label.toLowerCase()}${count == 1 ? '' : 's'}';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'label': label,
      'count': count,
      'references': [for (final reference in references) reference.toJson()],
    };
  }
}
