/// Future-proof link target for the project-wide text system.
///
/// Phase 7 does not build the internal linking/backlink system yet. This model
/// reserves the shape so link marks can later point to URLs, documents, blocks,
/// workspace items, references, or other app-native entities without changing
/// every surface.
class TextLinkTarget {
  const TextLinkTarget({
    required this.type,
    required this.value,
    this.metadata = const <String, Object?>{},
  });

  factory TextLinkTarget.externalUrl(String url) {
    return TextLinkTarget(type: TextLinkTargetType.externalUrl, value: url);
  }

  factory TextLinkTarget.fromJson(Map<String, Object?> json) {
    return TextLinkTarget(
      type: TextLinkTargetType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => TextLinkTargetType.externalUrl,
      ),
      value: json['value'] as String? ?? '',
      metadata: Map<String, Object?>.from(json['metadata'] as Map? ?? const <String, Object?>{}),
    );
  }

  final TextLinkTargetType type;
  final String value;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      'value': value,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

enum TextLinkTargetType {
  externalUrl,
  internalReference,
  document,
  block,
  workspaceItem,
  reference,
  custom,
}
