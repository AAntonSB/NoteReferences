import 'dart:convert';

import '../actions/text_system_reference_action_models.dart';

/// Stable bridge payload between TextSystem references/citations and app-owned
/// research sources such as imported PDFs, sidecar notes, highlights, and
/// future external/source-manager objects.
class TextSystemSourceLocator {
  const TextSystemSourceLocator({
    required this.sourceKind,
    required this.sourceId,
    this.sourceTitle,
    this.pdfDocumentId,
    this.pdfPath,
    this.pageNumber,
    this.pageLabel,
    this.sidecarNoteId,
    this.anchorId,
    this.highlightId,
    this.excerpt,
    this.sourceRects = const <TextSystemSourceRect>[],
    this.workState = const <String, Object?>{},
    this.createdFrom,
  });

  final String sourceKind;
  final String sourceId;
  final String? sourceTitle;
  final String? pdfDocumentId;
  final String? pdfPath;
  final int? pageNumber;
  final String? pageLabel;
  final String? sidecarNoteId;
  final String? anchorId;
  final String? highlightId;
  final String? excerpt;
  final List<TextSystemSourceRect> sourceRects;
  final Map<String, Object?> workState;
  final String? createdFrom;

  bool get hasPdfTarget {
    return (pdfDocumentId != null && pdfDocumentId!.trim().isNotEmpty) ||
        (sourceKind == 'pdf' && sourceId.trim().isNotEmpty);
  }

  String? get effectivePdfDocumentId {
    final explicit = pdfDocumentId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (sourceKind == 'pdf' && sourceId.trim().isNotEmpty) return sourceId.trim();
    return null;
  }

  int? get effectivePageNumber {
    if (pageNumber != null && pageNumber! > 0) return pageNumber;
    if (sourceRects.isNotEmpty && sourceRects.first.pageNumber > 0) {
      return sourceRects.first.pageNumber;
    }
    return null;
  }

  String get compactLabel {
    final title = sourceTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    final id = effectivePdfDocumentId;
    if (id != null && id.isNotEmpty) return id;
    return sourceKind;
  }

  TextSystemSourceLocator copyWith({
    String? sourceKind,
    String? sourceId,
    Object? sourceTitle = _sentinel,
    Object? pdfDocumentId = _sentinel,
    Object? pdfPath = _sentinel,
    Object? pageNumber = _sentinel,
    Object? pageLabel = _sentinel,
    Object? sidecarNoteId = _sentinel,
    Object? anchorId = _sentinel,
    Object? highlightId = _sentinel,
    Object? excerpt = _sentinel,
    List<TextSystemSourceRect>? sourceRects,
    Map<String, Object?>? workState,
    Object? createdFrom = _sentinel,
  }) {
    return TextSystemSourceLocator(
      sourceKind: sourceKind ?? this.sourceKind,
      sourceId: sourceId ?? this.sourceId,
      sourceTitle: sourceTitle == _sentinel ? this.sourceTitle : sourceTitle as String?,
      pdfDocumentId: pdfDocumentId == _sentinel ? this.pdfDocumentId : pdfDocumentId as String?,
      pdfPath: pdfPath == _sentinel ? this.pdfPath : pdfPath as String?,
      pageNumber: pageNumber == _sentinel ? this.pageNumber : pageNumber as int?,
      pageLabel: pageLabel == _sentinel ? this.pageLabel : pageLabel as String?,
      sidecarNoteId: sidecarNoteId == _sentinel ? this.sidecarNoteId : sidecarNoteId as String?,
      anchorId: anchorId == _sentinel ? this.anchorId : anchorId as String?,
      highlightId: highlightId == _sentinel ? this.highlightId : highlightId as String?,
      excerpt: excerpt == _sentinel ? this.excerpt : excerpt as String?,
      sourceRects: sourceRects ?? this.sourceRects,
      workState: workState ?? this.workState,
      createdFrom: createdFrom == _sentinel ? this.createdFrom : createdFrom as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sourceKind': sourceKind,
      'sourceId': sourceId,
      if (sourceTitle != null) 'sourceTitle': sourceTitle,
      if (pdfDocumentId != null) 'pdfDocumentId': pdfDocumentId,
      if (pdfPath != null) 'pdfPath': pdfPath,
      if (pageNumber != null) 'pageNumber': pageNumber,
      if (pageLabel != null) 'pageLabel': pageLabel,
      if (sidecarNoteId != null) 'sidecarNoteId': sidecarNoteId,
      if (anchorId != null) 'anchorId': anchorId,
      if (highlightId != null) 'highlightId': highlightId,
      if (excerpt != null) 'excerpt': excerpt,
      if (sourceRects.isNotEmpty)
        'sourceRects': <Object?>[for (final rect in sourceRects) rect.toJson()],
      if (workState.isNotEmpty) 'workState': workState,
      if (createdFrom != null) 'createdFrom': createdFrom,
    };
  }

  Map<String, Object?> toReferenceMetadata() {
    return <String, Object?>{
      'sourceKind': sourceKind,
      'sourceId': sourceId,
      if (sourceTitle != null) 'sourceTitle': sourceTitle,
      if (pdfDocumentId != null) 'pdfDocumentId': pdfDocumentId,
      if (pdfPath != null) 'pdfPath': pdfPath,
      if (pageNumber != null) 'pageNumber': pageNumber,
      if (pageLabel != null) 'pageLabel': pageLabel,
      if (sidecarNoteId != null) 'sidecarNoteId': sidecarNoteId,
      if (anchorId != null) 'anchorId': anchorId,
      if (highlightId != null) 'highlightId': highlightId,
      if (excerpt != null) 'excerpt': excerpt,
      if (sourceRects.isNotEmpty)
        'sourceRects': <Object?>[for (final rect in sourceRects) rect.toJson()],
      if (workState.isNotEmpty) 'workState': workState,
      if (createdFrom != null) 'createdFrom': createdFrom,
      'sourceLocator': toJson(),
    };
  }

  factory TextSystemSourceLocator.fromJson(Map<String, Object?> json) {
    return TextSystemSourceLocator(
      sourceKind: _stringValue(json['sourceKind']) ?? _stringValue(json['kind']) ?? 'unknown',
      sourceId: _stringValue(json['sourceId']) ?? _stringValue(json['id']) ?? '',
      sourceTitle: _stringValue(json['sourceTitle']) ?? _stringValue(json['title']),
      pdfDocumentId: _stringValue(json['pdfDocumentId']) ?? _stringValue(json['documentId']),
      pdfPath: _stringValue(json['pdfPath']) ?? _stringValue(json['filePath']),
      pageNumber: _intValue(json['pageNumber']) ?? _intValue(json['page']),
      pageLabel: _stringValue(json['pageLabel']),
      sidecarNoteId: _stringValue(json['sidecarNoteId']) ?? _stringValue(json['noteId']),
      anchorId: _stringValue(json['anchorId']),
      highlightId: _stringValue(json['highlightId']),
      excerpt: _stringValue(json['excerpt']) ?? _stringValue(json['selectedText']),
      sourceRects: _sourceRectsFromJson(json['sourceRects']),
      workState: _mapFromJson(json['workState']),
      createdFrom: _stringValue(json['createdFrom']),
    );
  }

  static TextSystemSourceLocator? tryFromInlineReference(
    TextSystemInlineReferenceMark inlineReference,
  ) {
    return tryFromMetadata(inlineReference.metadata);
  }

  static TextSystemSourceLocator? tryFromReferenceTarget(
    TextSystemReferenceTarget target,
  ) {
    return tryFromMetadata(target.metadata);
  }

  static TextSystemSourceLocator? tryFromMetadata(Map<String, Object?> metadata) {
    final embedded = metadata['sourceLocator'];
    final parsedEmbedded = tryFromInlineAttribute(embedded);
    if (parsedEmbedded != null) return parsedEmbedded;

    final sourceKind = _stringValue(metadata['sourceKind']);
    final sourceId = _stringValue(metadata['sourceId']) ?? _stringValue(metadata['pdfDocumentId']);
    if ((sourceKind == null || sourceKind.isEmpty) &&
        (sourceId == null || sourceId.isEmpty) &&
        _stringValue(metadata['pdfDocumentId']) == null) {
      return null;
    }

    return TextSystemSourceLocator.fromJson(metadata);
  }

  static TextSystemSourceLocator? tryFromInlineAttribute(Object? value) {
    if (value == null) return null;
    if (value is TextSystemSourceLocator) return value;
    if (value is Map<String, Object?>) return TextSystemSourceLocator.fromJson(value);
    if (value is Map) {
      return TextSystemSourceLocator.fromJson(
        value.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?)),
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return tryFromInlineAttribute(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class TextSystemSourceRect {
  const TextSystemSourceRect({
    required this.pageNumber,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int pageNumber;
  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isValid {
    return pageNumber > 0 &&
        left.isFinite &&
        top.isFinite &&
        right.isFinite &&
        bottom.isFinite &&
        right != left &&
        top != bottom;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageNumber': pageNumber,
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    };
  }

  factory TextSystemSourceRect.fromJson(Map<String, Object?> json) {
    return TextSystemSourceRect(
      pageNumber: _intValue(json['pageNumber']) ?? 1,
      left: _doubleValue(json['left']) ?? 0,
      top: _doubleValue(json['top']) ?? 0,
      right: _doubleValue(json['right']) ?? 0,
      bottom: _doubleValue(json['bottom']) ?? 0,
    );
  }
}

const Object _sentinel = Object();

String? _stringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _doubleValue(Object? value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

Map<String, Object?> _mapFromJson(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?));
  }
  return const <String, Object?>{};
}

List<TextSystemSourceRect> _sourceRectsFromJson(Object? value) {
  if (value is! List) return const <TextSystemSourceRect>[];
  return value
      .whereType<Map>()
      .map((item) => TextSystemSourceRect.fromJson(
            item.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?)),
          ))
      .where((rect) => rect.isValid)
      .toList(growable: false);
}
