import 'dart:convert';

/// Phase 15J model layer for turning selected text into document references.
///
/// This file intentionally has no Flutter dependency. It is part of the
/// TextSystem reference/citation bridge and can be reused by the editor UI,
/// document model, reference index, and semantic export layers.

enum TextSystemReferenceActionType {
  citation,
  source,
  document,
  project,
  todo,
  link,
}

enum TextSystemReferenceTargetKind {
  citation,
  source,
  document,
  project,
  todo,
  link,
  figure,
  table,
  unknown,
}

extension TextSystemReferenceActionTypeX on TextSystemReferenceActionType {
  String get id {
    switch (this) {
      case TextSystemReferenceActionType.citation:
        return 'citation';
      case TextSystemReferenceActionType.source:
        return 'source';
      case TextSystemReferenceActionType.document:
        return 'document';
      case TextSystemReferenceActionType.project:
        return 'project';
      case TextSystemReferenceActionType.todo:
        return 'todo';
      case TextSystemReferenceActionType.link:
        return 'link';
    }
  }

  String get label {
    switch (this) {
      case TextSystemReferenceActionType.citation:
        return 'Citation';
      case TextSystemReferenceActionType.source:
        return 'Source';
      case TextSystemReferenceActionType.document:
        return 'Document';
      case TextSystemReferenceActionType.project:
        return 'Project';
      case TextSystemReferenceActionType.todo:
        return 'Todo';
      case TextSystemReferenceActionType.link:
        return 'Link';
    }
  }

  String get verbLabel {
    switch (this) {
      case TextSystemReferenceActionType.citation:
        return 'Add citation';
      case TextSystemReferenceActionType.source:
        return 'Link source';
      case TextSystemReferenceActionType.document:
        return 'Link document';
      case TextSystemReferenceActionType.project:
        return 'Link project';
      case TextSystemReferenceActionType.todo:
        return 'Link todo';
      case TextSystemReferenceActionType.link:
        return 'Add link';
    }
  }

  TextSystemReferenceTargetKind get targetKind {
    switch (this) {
      case TextSystemReferenceActionType.citation:
        return TextSystemReferenceTargetKind.citation;
      case TextSystemReferenceActionType.source:
        return TextSystemReferenceTargetKind.source;
      case TextSystemReferenceActionType.document:
        return TextSystemReferenceTargetKind.document;
      case TextSystemReferenceActionType.project:
        return TextSystemReferenceTargetKind.project;
      case TextSystemReferenceActionType.todo:
        return TextSystemReferenceTargetKind.todo;
      case TextSystemReferenceActionType.link:
        return TextSystemReferenceTargetKind.link;
    }
  }

  static TextSystemReferenceActionType fromId(String? id) {
    switch (id) {
      case 'citation':
        return TextSystemReferenceActionType.citation;
      case 'source':
        return TextSystemReferenceActionType.source;
      case 'document':
        return TextSystemReferenceActionType.document;
      case 'project':
        return TextSystemReferenceActionType.project;
      case 'todo':
        return TextSystemReferenceActionType.todo;
      case 'link':
        return TextSystemReferenceActionType.link;
      default:
        return TextSystemReferenceActionType.source;
    }
  }
}

extension TextSystemReferenceTargetKindX on TextSystemReferenceTargetKind {
  String get id {
    switch (this) {
      case TextSystemReferenceTargetKind.citation:
        return 'citation';
      case TextSystemReferenceTargetKind.source:
        return 'source';
      case TextSystemReferenceTargetKind.document:
        return 'document';
      case TextSystemReferenceTargetKind.project:
        return 'project';
      case TextSystemReferenceTargetKind.todo:
        return 'todo';
      case TextSystemReferenceTargetKind.link:
        return 'link';
      case TextSystemReferenceTargetKind.figure:
        return 'figure';
      case TextSystemReferenceTargetKind.table:
        return 'table';
      case TextSystemReferenceTargetKind.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case TextSystemReferenceTargetKind.citation:
        return 'Citation';
      case TextSystemReferenceTargetKind.source:
        return 'Source';
      case TextSystemReferenceTargetKind.document:
        return 'Document';
      case TextSystemReferenceTargetKind.project:
        return 'Project';
      case TextSystemReferenceTargetKind.todo:
        return 'Todo';
      case TextSystemReferenceTargetKind.link:
        return 'Link';
      case TextSystemReferenceTargetKind.figure:
        return 'Figure';
      case TextSystemReferenceTargetKind.table:
        return 'Table';
      case TextSystemReferenceTargetKind.unknown:
        return 'Reference';
    }
  }

  static TextSystemReferenceTargetKind fromId(String? id) {
    switch (id) {
      case 'citation':
        return TextSystemReferenceTargetKind.citation;
      case 'source':
        return TextSystemReferenceTargetKind.source;
      case 'document':
        return TextSystemReferenceTargetKind.document;
      case 'project':
        return TextSystemReferenceTargetKind.project;
      case 'todo':
        return TextSystemReferenceTargetKind.todo;
      case 'link':
        return TextSystemReferenceTargetKind.link;
      case 'figure':
        return TextSystemReferenceTargetKind.figure;
      case 'table':
        return TextSystemReferenceTargetKind.table;
      default:
        return TextSystemReferenceTargetKind.unknown;
    }
  }
}

class TextSystemReferenceTarget {
  const TextSystemReferenceTarget({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle,
    this.uri,
    this.citationKey,
    this.createdAt,
    this.updatedAt,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final TextSystemReferenceTargetKind kind;
  final String title;
  final String? subtitle;
  final Uri? uri;
  final String? citationKey;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, Object?> metadata;

  bool get hasUri => uri != null;

  String get compactLabel {
    final candidate = citationKey?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
    return title;
  }

  TextSystemReferenceTarget copyWith({
    String? id,
    TextSystemReferenceTargetKind? kind,
    String? title,
    Object? subtitle = _sentinel,
    Object? uri = _sentinel,
    Object? citationKey = _sentinel,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
    Map<String, Object?>? metadata,
  }) {
    return TextSystemReferenceTarget(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      subtitle: subtitle == _sentinel ? this.subtitle : subtitle as String?,
      uri: uri == _sentinel ? this.uri : uri as Uri?,
      citationKey:
          citationKey == _sentinel ? this.citationKey : citationKey as String?,
      createdAt:
          createdAt == _sentinel ? this.createdAt : createdAt as DateTime?,
      updatedAt:
          updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.id,
      'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (uri != null) 'uri': uri.toString(),
      if (citationKey != null) 'citationKey': citationKey,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  static TextSystemReferenceTarget fromJson(Map<String, Object?> json) {
    return TextSystemReferenceTarget(
      id: json['id'] as String? ?? '',
      kind: TextSystemReferenceTargetKindX.fromId(json['kind'] as String?),
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      uri: _tryParseUri(json['uri'] as String?),
      citationKey: json['citationKey'] as String?,
      createdAt: _tryParseDate(json['createdAt'] as String?),
      updatedAt: _tryParseDate(json['updatedAt'] as String?),
      metadata: _mapFromJson(json['metadata']),
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Inline mark stored on selected text.
///
/// In the existing TextSystem this should be attached to the selected inline
/// range using the document's inline mark/span metadata mechanism. Keep this
/// object as the canonical payload and let exports/reference index derive from
/// it instead of inventing separate ad-hoc maps per layer.
class TextSystemInlineReferenceMark {
  const TextSystemInlineReferenceMark({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.label,
    this.selectedText,
    this.uri,
    this.citationKey,
    this.createdAt,
    this.updatedAt,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final TextSystemReferenceTargetKind kind;
  final String targetId;
  final String label;
  final String? selectedText;
  final Uri? uri;
  final String? citationKey;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, Object?> metadata;

  static const String inlineAttributeKey = 'textSystemReference';
  static const String inlineReferenceIdKey = 'textSystemReferenceId';
  static const String inlineReferenceKindKey = 'textSystemReferenceKind';
  static const String inlineReferenceTargetIdKey = 'textSystemReferenceTargetId';

  bool get isCitation => kind == TextSystemReferenceTargetKind.citation;
  bool get isSource => kind == TextSystemReferenceTargetKind.source;
  bool get isExternalLink => kind == TextSystemReferenceTargetKind.link && uri != null;

  String get exportKey {
    final candidate = citationKey?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
    return targetId;
  }

  TextSystemInlineReferenceMark copyWith({
    String? id,
    TextSystemReferenceTargetKind? kind,
    String? targetId,
    String? label,
    Object? selectedText = _sentinel,
    Object? uri = _sentinel,
    Object? citationKey = _sentinel,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
    Map<String, Object?>? metadata,
  }) {
    return TextSystemInlineReferenceMark(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      targetId: targetId ?? this.targetId,
      label: label ?? this.label,
      selectedText:
          selectedText == _sentinel ? this.selectedText : selectedText as String?,
      uri: uri == _sentinel ? this.uri : uri as Uri?,
      citationKey:
          citationKey == _sentinel ? this.citationKey : citationKey as String?,
      createdAt:
          createdAt == _sentinel ? this.createdAt : createdAt as DateTime?,
      updatedAt:
          updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.id,
      'targetId': targetId,
      'label': label,
      if (selectedText != null) 'selectedText': selectedText,
      if (uri != null) 'uri': uri.toString(),
      if (citationKey != null) 'citationKey': citationKey,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  static TextSystemInlineReferenceMark fromJson(Map<String, Object?> json) {
    return TextSystemInlineReferenceMark(
      id: json['id'] as String? ?? '',
      kind: TextSystemReferenceTargetKindX.fromId(json['kind'] as String?),
      targetId: json['targetId'] as String? ?? '',
      label: json['label'] as String? ?? '',
      selectedText: json['selectedText'] as String?,
      uri: _tryParseUri(json['uri'] as String?),
      citationKey: json['citationKey'] as String?,
      createdAt: _tryParseDate(json['createdAt'] as String?),
      updatedAt: _tryParseDate(json['updatedAt'] as String?),
      metadata: _mapFromJson(json['metadata']),
    );
  }

  static TextSystemInlineReferenceMark? tryFromInlineAttribute(Object? value) {
    if (value == null) return null;
    if (value is TextSystemInlineReferenceMark) return value;
    if (value is Map<String, Object?>) {
      return TextSystemInlineReferenceMark.fromJson(value);
    }
    if (value is Map) {
      return TextSystemInlineReferenceMark.fromJson(
        value.map((dynamic key, dynamic value) {
          return MapEntry(key.toString(), value as Object?);
        }),
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, Object?>) {
          return TextSystemInlineReferenceMark.fromJson(decoded);
        }
        if (decoded is Map) {
          return TextSystemInlineReferenceMark.fromJson(
            decoded.map((dynamic key, dynamic value) {
              return MapEntry(key.toString(), value as Object?);
            }),
          );
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static TextSystemInlineReferenceMark? tryFromTextMarkAttributes(
    Map<String, String> attributes,
  ) {
    final embedded = tryFromInlineAttribute(attributes[inlineAttributeKey]);
    if (embedded != null) return embedded;

    final referenceId = attributes[inlineReferenceIdKey] ?? attributes['referenceId'];
    final targetId = attributes[inlineReferenceTargetIdKey] ??
        attributes['targetId'] ??
        attributes['citationId'] ??
        attributes['sourceId'] ??
        attributes['documentId'] ??
        attributes['projectId'] ??
        attributes['todoId'];
    if ((referenceId == null || referenceId.trim().isEmpty) &&
        (targetId == null || targetId.trim().isEmpty)) {
      return null;
    }

    final role = attributes[inlineReferenceKindKey] ??
        attributes['role'] ??
        attributes['kind'];
    final kind = TextSystemReferenceTargetKindX.fromId(role);
    final label = attributes['label'] ?? attributes['title'] ?? targetId ?? referenceId ?? kind.label;
    final uri = _tryParseUri(attributes['url'] ?? attributes['href']);

    return TextSystemInlineReferenceMark(
      id: referenceId ?? TextSystemReferenceActionIds.newReferenceId(),
      kind: kind,
      targetId: targetId ?? referenceId ?? '',
      label: label,
      selectedText: attributes['selectedText'],
      uri: uri,
      citationKey: attributes['citationKey'],
      createdAt: _tryParseDate(attributes['createdAt']),
      updatedAt: _tryParseDate(attributes['updatedAt']),
    );
  }

  Map<String, Object?> toInlineAttributes() {
    return <String, Object?>{
      inlineAttributeKey: toJson(),
      inlineReferenceIdKey: id,
      inlineReferenceKindKey: kind.id,
      inlineReferenceTargetIdKey: targetId,
    };
  }

  Map<String, String> toTextMarkAttributes() {
    final attributes = <String, String>{
      'role': kind.id,
      'kind': kind.id,
      'label': label,
      inlineAttributeKey: jsonEncode(toJson()),
      inlineReferenceIdKey: id,
      inlineReferenceKindKey: kind.id,
      inlineReferenceTargetIdKey: targetId,
      'targetId': targetId,
    };

    if (selectedText != null && selectedText!.trim().isNotEmpty) {
      attributes['selectedText'] = selectedText!.trim();
    }
    if (uri != null) {
      attributes['url'] = uri.toString();
      attributes['href'] = uri.toString();
    }
    if (citationKey != null && citationKey!.trim().isNotEmpty) {
      attributes['citationKey'] = citationKey!.trim();
    }
    if (createdAt != null) attributes['createdAt'] = createdAt!.toIso8601String();
    if (updatedAt != null) attributes['updatedAt'] = updatedAt!.toIso8601String();

    switch (kind) {
      case TextSystemReferenceTargetKind.citation:
        attributes['citationId'] = targetId;
        break;
      case TextSystemReferenceTargetKind.source:
        attributes['sourceId'] = targetId;
        break;
      case TextSystemReferenceTargetKind.document:
        attributes['documentId'] = targetId;
        break;
      case TextSystemReferenceTargetKind.project:
        attributes['projectId'] = targetId;
        break;
      case TextSystemReferenceTargetKind.todo:
        attributes['todoId'] = targetId;
        break;
      case TextSystemReferenceTargetKind.link:
      case TextSystemReferenceTargetKind.figure:
      case TextSystemReferenceTargetKind.table:
      case TextSystemReferenceTargetKind.unknown:
        break;
    }

    return Map<String, String>.unmodifiable(attributes);
  }

  @override
  String toString() => jsonEncode(toJson());
}

class TextSystemReferenceActionDraft {
  const TextSystemReferenceActionDraft({
    required this.actionType,
    required this.selectedText,
    required this.query,
    this.label,
    this.uri,
    this.citationKey,
    this.metadata = const <String, Object?>{},
  });

  final TextSystemReferenceActionType actionType;
  final String selectedText;
  final String query;
  final String? label;
  final Uri? uri;
  final String? citationKey;
  final Map<String, Object?> metadata;

  TextSystemReferenceTargetKind get targetKind => actionType.targetKind;

  String get effectiveLabel {
    final explicit = label?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      return q;
    }
    final selected = selectedText.trim();
    if (selected.isNotEmpty) {
      return selected;
    }
    return actionType.label;
  }
}

class TextSystemReferenceActionResult {
  const TextSystemReferenceActionResult({
    required this.actionType,
    required this.target,
    required this.inlineMark,
    required this.visibleLabel,
  });

  final TextSystemReferenceActionType actionType;
  final TextSystemReferenceTarget target;
  final TextSystemInlineReferenceMark inlineMark;

  /// Text that remains visible in the document after applying the reference.
  /// For most selected-text actions this should be the originally selected text.
  final String visibleLabel;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'actionType': actionType.id,
      'target': target.toJson(),
      'inlineMark': inlineMark.toJson(),
      'visibleLabel': visibleLabel,
    };
  }
}

class TextSystemReferenceActionIds {
  const TextSystemReferenceActionIds._();

  static String newReferenceId({DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    return 'ref_$timestamp';
  }

  static String newTargetId(TextSystemReferenceTargetKind kind, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    return '${kind.id}_$timestamp';
  }
}

const Object _sentinel = Object();

Uri? _tryParseUri(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return Uri.tryParse(raw.trim());
}

DateTime? _tryParseDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

Map<String, Object?> _mapFromJson(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((dynamic key, dynamic value) {
      return MapEntry(key.toString(), value as Object?);
    });
  }
  return const <String, Object?>{};
}
