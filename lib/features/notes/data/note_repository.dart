import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../infrastructure/database/app_database.dart';

class PdfSourceRect {
  final int pageNumber;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PdfSourceRect({
    required this.pageNumber,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory PdfSourceRect.fromJson(Map<String, dynamic> json) {
    return PdfSourceRect(
      pageNumber: _readInt(json['pageNumber']) ?? 1,
      left: _readDouble(json['left']) ?? 0,
      top: _readDouble(json['top']) ?? 0,
      right: _readDouble(json['right']) ?? 0,
      bottom: _readDouble(json['bottom']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageNumber': pageNumber,
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    };
  }

  bool get isValid {
    return pageNumber > 0 &&
        right != left &&
        top != bottom &&
        left.isFinite &&
        top.isFinite &&
        right.isFinite &&
        bottom.isFinite;
  }

  static List<PdfSourceRect> listFromGeometryJson(String? geometryJson) {
    final geometry = _decodeGeometry(geometryJson);
    final rawRects = geometry['sourceRects'];

    if (rawRects is! List) {
      return const [];
    }

    return rawRects
        .whereType<Map>()
        .map((item) {
          return PdfSourceRect.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .where((rect) => rect.isValid)
        .toList();
  }

  static Map<String, dynamic> _decodeGeometry(String? geometryJson) {
    if (geometryJson == null || geometryJson.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(geometryJson);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return {};
    }

    return {};
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

String? _readString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

const int kDefaultNoteHighlightColorValue = 0xFFFFD54F;
const double kDefaultNoteHighlightOpacity = 0.22;
const String kDefaultNoteHighlightStyle = 'marker';

class NoteMetadata {
  final List<String> tags;
  final String status;
  final String importance;
  final bool highlightEnabled;
  final int highlightColorValue;
  final double highlightOpacity;
  final String highlightStyle;

  const NoteMetadata({
    this.tags = const [],
    this.status = 'none',
    this.importance = 'normal',
    this.highlightEnabled = false,
    this.highlightColorValue = kDefaultNoteHighlightColorValue,
    this.highlightOpacity = kDefaultNoteHighlightOpacity,
    this.highlightStyle = kDefaultNoteHighlightStyle,
  });

  factory NoteMetadata.fromAnchor(NoteAnchor anchor) {
    final geometry = _decodeGeometry(anchor.geometryJson);
    final sourceRects = PdfSourceRect.listFromGeometryJson(anchor.geometryJson);
    final rawMetadata = geometry['metadata'];

    if (rawMetadata is! Map) {
      return NoteMetadata(highlightEnabled: sourceRects.isNotEmpty);
    }

    final metadata = rawMetadata.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    final rawTags = metadata['tags'];
    final tags = rawTags is List
        ? rawTags
              .whereType<String>()
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList()
        : const <String>[];

    return NoteMetadata(
      tags: tags,
      status: _readString(metadata['status']) ?? 'none',
      importance: _readString(metadata['importance']) ?? 'normal',
      highlightEnabled:
          _readBool(metadata['highlightEnabled']) ?? sourceRects.isNotEmpty,
      highlightColorValue:
          _readInt(metadata['highlightColorValue']) ??
          kDefaultNoteHighlightColorValue,
      highlightOpacity:
          (_readDouble(metadata['highlightOpacity']) ??
                  kDefaultNoteHighlightOpacity)
              .clamp(0.05, 0.75)
              .toDouble(),
      highlightStyle:
          _readString(metadata['highlightStyle']) ?? kDefaultNoteHighlightStyle,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tags': tags,
      'status': status,
      'importance': importance,
      'highlightEnabled': highlightEnabled,
      'highlightColorValue': highlightColorValue,
      'highlightOpacity': highlightOpacity,
      'highlightStyle': highlightStyle,
    };
  }

  NoteMetadata copyWith({
    List<String>? tags,
    String? status,
    String? importance,
    bool? highlightEnabled,
    int? highlightColorValue,
    double? highlightOpacity,
    String? highlightStyle,
  }) {
    return NoteMetadata(
      tags: tags ?? this.tags,
      status: status ?? this.status,
      importance: importance ?? this.importance,
      highlightEnabled: highlightEnabled ?? this.highlightEnabled,
      highlightColorValue: highlightColorValue ?? this.highlightColorValue,
      highlightOpacity: highlightOpacity ?? this.highlightOpacity,
      highlightStyle: highlightStyle ?? this.highlightStyle,
    );
  }

  static Map<String, dynamic> _decodeGeometry(String? geometryJson) {
    if (geometryJson == null || geometryJson.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(geometryJson);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return {};
    }

    return {};
  }

  static String? _readString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return null;
  }

  static bool? _readBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return bool.tryParse(value);
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class SidecarNotePlacement {
  final int pageNumber;
  final double x;
  final double y;
  final double width;

  const SidecarNotePlacement({
    required this.pageNumber,
    required this.x,
    required this.y,
    required this.width,
  });

  factory SidecarNotePlacement.fromAnchor(NoteAnchor anchor) {
    final fallbackPage = anchor.pageNumber ?? 1;

    if (anchor.geometryJson == null || anchor.geometryJson!.trim().isEmpty) {
      return SidecarNotePlacement(
        pageNumber: fallbackPage,
        x: 0.08,
        y: 0.12,
        width: 0.42,
      );
    }

    try {
      final decoded = jsonDecode(anchor.geometryJson!) as Map<String, dynamic>;

      return SidecarNotePlacement(
        pageNumber: _readInt(decoded['pageNumber']) ?? fallbackPage,
        x: _readDouble(decoded['x']) ?? 0.08,
        y: _readDouble(decoded['y']) ?? 0.12,
        width: _readDouble(decoded['width']) ?? 0.42,
      );
    } catch (_) {
      return SidecarNotePlacement(
        pageNumber: fallbackPage,
        x: 0.08,
        y: 0.12,
        width: 0.42,
      );
    }
  }

  String toJsonString({
    List<PdfSourceRect> sourceRects = const [],
    NoteMetadata? metadata,
  }) {
    return jsonEncode({
      'placementType': 'sidecar',
      'pageNumber': pageNumber,
      'x': x,
      'y': y,
      'width': width,
      if (sourceRects.isNotEmpty)
        'sourceRects': [for (final rect in sourceRects) rect.toJson()],
      if (metadata != null) 'metadata': metadata.toJson(),
    });
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class NoteWithAnchor {
  final Note note;
  final NoteBlock? firstBlock;
  final NoteAnchor anchor;

  const NoteWithAnchor({
    required this.note,
    required this.firstBlock,
    required this.anchor,
  });

  String get body => firstBlock?.contentText ?? '';

  String get noteType => note.noteType;

  SidecarNotePlacement get sidecarPlacement {
    return SidecarNotePlacement.fromAnchor(anchor);
  }

  List<PdfSourceRect> get sourceRects {
    return PdfSourceRect.listFromGeometryJson(anchor.geometryJson);
  }

  NoteMetadata get metadata {
    return NoteMetadata.fromAnchor(anchor);
  }
}

class PdfLinkedHighlightRegion {
  final String noteId;
  final String anchorId;
  final String anchorType;
  final String noteType;
  final bool hasSidecarNote;
  final String? selectedText;
  final List<PdfSourceRect> sourceRects;
  final int highlightColorValue;
  final double highlightOpacity;
  final String highlightStyle;

  const PdfLinkedHighlightRegion({
    required this.noteId,
    required this.anchorId,
    required this.anchorType,
    required this.noteType,
    required this.hasSidecarNote,
    required this.selectedText,
    required this.sourceRects,
    this.highlightColorValue = kDefaultNoteHighlightColorValue,
    this.highlightOpacity = kDefaultNoteHighlightOpacity,
    this.highlightStyle = kDefaultNoteHighlightStyle,
  });

  bool get isStandaloneHighlight {
    return anchorType == 'pdfHighlight' || noteType == 'highlight';
  }
}

const String kTodoNoteType = 'todo';
const String kTodoBlockType = 'todo';
const String kTodoSourcePdfTextSelection = 'pdfTextSelection';
const String kTodoSourcePdfFreeform = 'pdfFreeform';
const String kTodoSourceSidecarNote = 'sidecarNote';
const String kTodoSourceDocumentNote = 'documentNote';
const String kTodoSourceTodaySetup = 'todaySetup';
const String kReaderAnchorTypeDocument = 'readerDocument';
const String kReaderAnchorTypeEpubSection = 'readerEpubSection';
const String kReaderAnchorTypeEpubParagraph = 'readerEpubParagraph';
const String kReaderTodoSource = 'readerAnchor';
const List<String> kReaderAnchorTypes = <String>[
  kReaderAnchorTypeDocument,
  kReaderAnchorTypeEpubSection,
  kReaderAnchorTypeEpubParagraph,
];

const String kTodoPriorityLow = 'low';
const String kTodoPriorityMedium = 'medium';
const String kTodoPriorityHigh = 'high';

const int kTodoLowColorValue = 0xFF64B5F6;
const int kTodoMediumColorValue = 0xFFFFB74D;
const int kTodoHighColorValue = 0xFFE57373;
const double kTodoHighlightOpacity = 0.28;

class TodoItem {
  final Note note;
  final NoteBlock? block;
  final NoteAnchor? anchor;
  final String? documentName;
  final String sourceType;
  final String title;
  final String? body;
  final String priority;
  final bool isCompleted;
  final DateTime? deadline;
  final DateTime? completedAt;
  final int? pageNumber;
  final List<PdfSourceRect> sourceRects;

  const TodoItem({
    required this.note,
    required this.block,
    required this.anchor,
    required this.documentName,
    required this.sourceType,
    required this.title,
    required this.body,
    required this.priority,
    required this.isCompleted,
    required this.deadline,
    required this.completedAt,
    required this.pageNumber,
    required this.sourceRects,
  });

  String get id => note.id;

  String get pdfLabel {
    final name = documentName?.trim();
    if (name != null && name.isNotEmpty) return name;

    final documentId = note.documentId?.trim();
    if (documentId != null && documentId.isNotEmpty) return documentId;

    return 'Unlinked notes';
  }

  bool get hasPdfSource {
    return sourceRects.isNotEmpty || pageNumber != null;
  }

  bool get isOverdue {
    final due = deadline;
    if (due == null || isCompleted) return false;
    return due.isBefore(DateTime.now());
  }

  bool get isDueSoon {
    final due = deadline;
    if (due == null || isCompleted || isOverdue) return false;
    return due.isBefore(DateTime.now().add(const Duration(days: 2)));
  }

  factory TodoItem.fromRow({
    required Note note,
    required NoteBlock? block,
    required NoteAnchor? anchor,
    required String? documentName,
  }) {
    final metadata = _decodeTodoJson(block?.contentJson);
    final sourceRects = anchor == null
        ? const <PdfSourceRect>[]
        : PdfSourceRect.listFromGeometryJson(anchor.geometryJson);
    final fallbackPage =
        anchor?.pageNumber ??
        (sourceRects.isEmpty ? null : sourceRects.first.pageNumber);
    final sourceType =
        _readString(metadata['sourceType']) ??
        _sourceTypeFromAnchor(anchor?.anchorType);
    final selectedText = _cleanInlineText(anchor?.selectedText);
    final blockTitle = _cleanInlineText(block?.contentText);
    final noteTitle = _cleanInlineText(note.title);

    return TodoItem(
      note: note,
      block: block,
      anchor: anchor,
      documentName: documentName,
      sourceType: sourceType,
      title: noteTitle ?? blockTitle ?? selectedText ?? 'Untitled TODO',
      body: _readString(metadata['body']),
      priority: _normalizeTodoPriority(_readString(metadata['priority'])),
      isCompleted: _readBool(metadata['isCompleted']) ?? false,
      deadline: _readDateTime(metadata['deadline']),
      completedAt: _readDateTime(metadata['completedAt']),
      pageNumber: fallbackPage,
      sourceRects: sourceRects,
    );
  }

  Map<String, dynamic> metadataJson({
    String? title,
    String? body,
    String? priority,
    bool? isCompleted,
    DateTime? deadline,
    bool clearDeadline = false,
    DateTime? completedAt,
  }) {
    final nextDeadline = clearDeadline ? null : deadline ?? this.deadline;
    final nextCompletedAt = completedAt ?? this.completedAt;

    return {
      'sourceType': sourceType,
      'body': body ?? this.body,
      'priority': _normalizeTodoPriority(priority ?? this.priority),
      'isCompleted': isCompleted ?? this.isCompleted,
      if (nextDeadline != null) 'deadline': nextDeadline.toIso8601String(),
      if (nextCompletedAt != null)
        'completedAt': nextCompletedAt.toIso8601String(),
    };
  }

  static int colorForPriority(String priority) {
    switch (_normalizeTodoPriority(priority)) {
      case kTodoPriorityHigh:
        return kTodoHighColorValue;
      case kTodoPriorityLow:
        return kTodoLowColorValue;
      case kTodoPriorityMedium:
      default:
        return kTodoMediumColorValue;
    }
  }
}

Map<String, dynamic> _decodeTodoJson(String? value) {
  if (value == null || value.trim().isEmpty) return {};

  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return {};
  }

  return {};
}

String _sourceTypeFromAnchor(String? anchorType) {
  switch (anchorType) {
    case 'todoPdfTextSelection':
      return kTodoSourcePdfTextSelection;
    case 'todoPdfFreeform':
      return kTodoSourcePdfFreeform;
    case 'todoSidecarNote':
      return kTodoSourceSidecarNote;
    case 'todoDocumentNote':
      return kTodoSourceDocumentNote;
    default:
      return kTodoSourcePdfTextSelection;
  }
}

String _anchorTypeFromTodoSource(String sourceType) {
  switch (sourceType) {
    case kTodoSourcePdfFreeform:
      return 'todoPdfFreeform';
    case kTodoSourceSidecarNote:
      return 'todoSidecarNote';
    case kTodoSourceDocumentNote:
      return 'todoDocumentNote';
    case kTodoSourcePdfTextSelection:
    default:
      return 'todoPdfTextSelection';
  }
}

String _normalizeTodoPriority(String? value) {
  switch (value?.trim()) {
    case kTodoPriorityLow:
      return kTodoPriorityLow;
    case kTodoPriorityHigh:
      return kTodoPriorityHigh;
    case kTodoPriorityMedium:
    default:
      return kTodoPriorityMedium;
  }
}

bool? _readBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return bool.tryParse(value);
  if (value is num) return value != 0;
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _cleanInlineText(String? value) {
  if (value == null) return null;
  final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? null : cleaned;
}

String _shortenTodoTitle(String value) {
  final clean = _cleanInlineText(value) ?? 'Untitled TODO';
  if (clean.length <= 120) return clean;
  return '${clean.substring(0, 117)}...';
}

class DocumentNoteBlockTypes {
  /// The new one-block document-note storage format.
  ///
  /// The entire editable document lives in one NoteBlocks row. The row's
  /// contentText is the editable source shown in the editor, while contentJson
  /// stores structured metadata such as PDF references.
  static const String structuredDocument = 'structuredDocument';

  /// Legacy block types kept for compatibility with notes created before the
  /// single-document editor.
  static const String paragraph = 'paragraph';
  static const String math = 'math';
  static const String pdfReference = 'pdfReference';
}

class DocumentNotePdfReference {
  final String documentId;
  final int pageNumber;
  final String selectedText;
  final List<PdfSourceRect> sourceRects;
  final String citationLabel;

  const DocumentNotePdfReference({
    required this.documentId,
    required this.pageNumber,
    required this.selectedText,
    required this.sourceRects,
    required this.citationLabel,
  });

  factory DocumentNotePdfReference.fromJson(Map<String, dynamic> json) {
    final rawRects = json['sourceRects'];
    final sourceRects = rawRects is List
        ? rawRects
              .whereType<Map>()
              .map((item) {
                return PdfSourceRect.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                );
              })
              .where((rect) => rect.isValid)
              .toList()
        : const <PdfSourceRect>[];

    final pageNumber =
        _readInt(json['pageNumber']) ??
        (sourceRects.isEmpty ? 1 : sourceRects.first.pageNumber);

    return DocumentNotePdfReference(
      documentId: _readString(json['documentId']) ?? '',
      pageNumber: pageNumber,
      selectedText: _readString(json['selectedText']) ?? '',
      sourceRects: sourceRects,
      citationLabel: _readString(json['citationLabel']) ?? 'p. $pageNumber',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'documentId': documentId,
      'pageNumber': pageNumber,
      'selectedText': selectedText,
      'citationLabel': citationLabel,
      'sourceRects': [
        for (final rect in sourceRects.where((rect) => rect.isValid))
          rect.toJson(),
      ],
    };
  }
}

class DocumentNoteBlock {
  final NoteBlock block;

  const DocumentNoteBlock({required this.block});

  String get blockType => block.blockType;

  String get text => block.contentText ?? '';

  String get jsonText => block.contentJson ?? '';

  bool get isStructuredDocument {
    return block.blockType == DocumentNoteBlockTypes.structuredDocument;
  }

  Map<String, DocumentNotePdfReference> get structuredPdfReferences {
    if (!isStructuredDocument || jsonText.trim().isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return const {};

      final rawReferences = decoded['references'];
      if (rawReferences is! Map) return const {};

      final output = <String, DocumentNotePdfReference>{};
      for (final entry in rawReferences.entries) {
        final value = entry.value;
        if (value is Map) {
          output[entry.key.toString()] = DocumentNotePdfReference.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
      return output;
    } catch (_) {
      return const {};
    }
  }

  DocumentNotePdfReference? get pdfReference {
    if (block.blockType != DocumentNoteBlockTypes.pdfReference) {
      return null;
    }

    final json = block.contentJson;
    if (json == null || json.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return DocumentNotePdfReference.fromJson(decoded);
      }
      if (decoded is Map) {
        return DocumentNotePdfReference.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}

class StructuredDocumentNote {
  final Note note;
  final List<DocumentNoteBlock> blocks;

  const StructuredDocumentNote({required this.note, required this.blocks});

  DocumentNoteBlock? get structuredBlock {
    for (final block in blocks) {
      if (block.isStructuredDocument) return block;
    }
    return null;
  }

  String get documentText {
    final structured = structuredBlock;
    if (structured != null) return structured.text;

    return _legacyBlocksAsText();
  }

  Map<String, DocumentNotePdfReference> get pdfReferences {
    final structured = structuredBlock;
    if (structured != null) return structured.structuredPdfReferences;

    final output = <String, DocumentNotePdfReference>{};
    for (final block in blocks) {
      final reference = block.pdfReference;
      if (reference != null) {
        output['legacy_${block.block.id}'] = reference;
      }
    }
    return output;
  }

  String get displayTitle {
    final title = note.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    return 'Untitled document note';
  }

  String _legacyBlocksAsText() {
    final parts = <String>[];

    for (final block in blocks) {
      switch (block.blockType) {
        case DocumentNoteBlockTypes.math:
          final text = block.text.trim();
          if (text.isNotEmpty) {
            parts.add('\$\$\n$text\n\$\$');
          }
          break;
        case DocumentNoteBlockTypes.pdfReference:
          final reference = block.pdfReference;
          if (reference != null) {
            parts.add(
              '“${reference.selectedText}” [${reference.citationLabel}](pdfref:legacy_${block.block.id})',
            );
          } else if (block.text.trim().isNotEmpty) {
            parts.add(block.text.trim());
          }
          break;
        case DocumentNoteBlockTypes.paragraph:
        default:
          if (block.text.trim().isNotEmpty) {
            parts.add(block.text.trim());
          }
          break;
      }
    }

    return parts.join('\n\n');
  }
}

class NoteRepository {
  final AppDatabase database;
  final Uuid _uuid = const Uuid();

  NoteRepository(this.database);

  Stream<List<NoteWithAnchor>> watchSidecarNotesForDocument({
    required String documentId,
  }) {
    final query = database.select(database.noteAnchors).join([
      innerJoin(
        database.notes,
        database.notes.id.equalsExp(database.noteAnchors.noteId),
      ),
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
    ]);

    query.where(
      database.noteAnchors.documentId.equals(documentId) &
          database.noteAnchors.anchorType.equals('sidecarPosition') &
          database.notes.isArchived.equals(false),
    );

    query.orderBy([
      OrderingTerm.asc(database.noteAnchors.pageNumber),
      OrderingTerm.asc(database.noteAnchors.createdAt),
      OrderingTerm.asc(database.noteBlocks.sortOrder),
    ]);

    return query.watch().map((rows) {
      final items = <NoteWithAnchor>[];

      for (final row in rows) {
        items.add(
          NoteWithAnchor(
            anchor: row.readTable(database.noteAnchors),
            note: row.readTable(database.notes),
            firstBlock: row.readTableOrNull(database.noteBlocks),
          ),
        );
      }

      return items;
    });
  }

  Stream<List<NoteWithAnchor>> watchReaderAnchoredNotesForDocument({
    required String documentId,
  }) {
    final query = database.select(database.noteAnchors).join([
      innerJoin(
        database.notes,
        database.notes.id.equalsExp(database.noteAnchors.noteId),
      ),
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
    ]);

    query.where(
      database.noteAnchors.documentId.equals(documentId) &
          database.noteAnchors.anchorType.isIn(kReaderAnchorTypes) &
          database.notes.isArchived.equals(false),
    );

    query.orderBy([
      OrderingTerm.asc(database.noteAnchors.createdAt),
      OrderingTerm.asc(database.noteBlocks.sortOrder),
    ]);

    return query.watch().map((rows) {
      final itemsByNoteId = <String, NoteWithAnchor>{};

      for (final row in rows) {
        final anchor = row.readTable(database.noteAnchors);
        final note = row.readTable(database.notes);
        final block = row.readTableOrNull(database.noteBlocks);

        itemsByNoteId.putIfAbsent(
          note.id,
          () => NoteWithAnchor(
            anchor: anchor,
            note: note,
            firstBlock: block,
          ),
        );
      }

      return itemsByNoteId.values.toList();
    });
  }

  Future<NoteWithAnchor> createReaderAnchoredTextNote({
    required String documentId,
    required String anchorType,
    required String geometryJson,
    String? title,
    String? body,
    String? selectedText,
    String noteType = 'note',
  }) async {
    final normalizedAnchorType = kReaderAnchorTypes.contains(anchorType)
        ? anchorType
        : kReaderAnchorTypeDocument;
    final normalizedNoteType = _normalizeNoteType(noteType);
    final now = DateTime.now();
    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final anchorId = _uuid.v4();
    final cleanBody = body?.trim() ?? '';
    final sourceTitle = _cleanOptionalText(selectedText) ?? _cleanOptionalText(cleanBody);
    final cleanTitle = _cleanOptionalText(title) ??
        (sourceTitle == null ? 'Reader note' : _shortenTodoTitle(sourceTitle));

    await database.transaction(() async {
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              title: Value(cleanTitle),
              noteType: Value(normalizedNoteType),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: blockId,
              noteId: noteId,
              blockType: Value(normalizedNoteType == kTodoNoteType ? kTodoBlockType : 'text'),
              contentText: Value(cleanBody),
              contentJson: normalizedNoteType == kTodoNoteType
                  ? Value(
                      jsonEncode({
                        'sourceType': kReaderTodoSource,
                        'priority': kTodoPriorityMedium,
                        'isCompleted': false,
                      }),
                    )
                  : const Value.absent(),
              sortOrder: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteAnchors)
          .insert(
            NoteAnchorsCompanion.insert(
              id: anchorId,
              noteId: noteId,
              documentId: Value(documentId),
              anchorType: normalizedAnchorType,
              selectedText: Value(_cleanOptionalText(selectedText)),
              geometryJson: Value(geometryJson),
              createdAt: now,
            ),
          );
    });

    return _getReaderAnchoredNote(noteId);
  }

  Stream<List<PdfLinkedHighlightRegion>>
  watchPersistentHighlightRegionsForDocument({required String documentId}) {
    final query = database.select(database.noteAnchors).join([
      innerJoin(
        database.notes,
        database.notes.id.equalsExp(database.noteAnchors.noteId),
      ),
    ]);

    query.where(
      database.noteAnchors.documentId.equals(documentId) &
          database.notes.isArchived.equals(false),
    );

    return query.watch().map((rows) {
      final regions = <PdfLinkedHighlightRegion>[];

      for (final row in rows) {
        final anchor = row.readTable(database.noteAnchors);
        final note = row.readTable(database.notes);
        final sourceRects = PdfSourceRect.listFromGeometryJson(
          anchor.geometryJson,
        );

        if (sourceRects.isEmpty) {
          continue;
        }

        if (anchor.anchorType == 'pdfHighlight') {
          final metadata = NoteMetadata.fromAnchor(anchor);

          if (!metadata.highlightEnabled) {
            continue;
          }

          regions.add(
            PdfLinkedHighlightRegion(
              noteId: note.id,
              anchorId: anchor.id,
              anchorType: anchor.anchorType,
              noteType: note.noteType,
              hasSidecarNote: false,
              selectedText: anchor.selectedText,
              sourceRects: sourceRects,
              highlightColorValue: metadata.highlightColorValue,
              highlightOpacity: metadata.highlightOpacity,
              highlightStyle: metadata.highlightStyle,
            ),
          );
          continue;
        }

        if (note.noteType == kTodoNoteType &&
            (anchor.anchorType == 'todoPdfTextSelection' ||
                anchor.anchorType == 'todoPdfFreeform')) {
          final metadata = NoteMetadata.fromAnchor(anchor);

          if (!metadata.highlightEnabled) {
            continue;
          }

          regions.add(
            PdfLinkedHighlightRegion(
              noteId: note.id,
              anchorId: anchor.id,
              anchorType: anchor.anchorType,
              noteType: note.noteType,
              hasSidecarNote: false,
              selectedText: anchor.selectedText,
              sourceRects: sourceRects,
              highlightColorValue:
                  metadata.highlightColorValue !=
                      kDefaultNoteHighlightColorValue
                  ? metadata.highlightColorValue
                  : kTodoMediumColorValue,
              highlightOpacity: metadata.highlightOpacity,
              highlightStyle: metadata.highlightStyle,
            ),
          );
          continue;
        }

        if (anchor.anchorType == 'sidecarPosition') {
          final metadata = NoteMetadata.fromAnchor(anchor);

          if (metadata.highlightEnabled) {
            regions.add(
              PdfLinkedHighlightRegion(
                noteId: note.id,
                anchorId: anchor.id,
                anchorType: anchor.anchorType,
                noteType: note.noteType,
                hasSidecarNote: true,
                selectedText: anchor.selectedText,
                sourceRects: sourceRects,
                highlightColorValue: metadata.highlightColorValue,
                highlightOpacity: metadata.highlightOpacity,
                highlightStyle: metadata.highlightStyle,
              ),
            );
          }
        }
      }

      return regions;
    });
  }

  Stream<List<PdfSourceRect>> watchPersistentHighlightRectsForDocument({
    required String documentId,
  }) {
    return watchPersistentHighlightRegionsForDocument(
      documentId: documentId,
    ).map((regions) {
      return [for (final region in regions) ...region.sourceRects];
    });
  }

  Future<NoteWithAnchor> createSidecarTextNote({
    required String documentId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
    String noteType = 'note',
    String? selectedText,
    List<PdfSourceRect> sourceRects = const [],
    int highlightColorValue = kDefaultNoteHighlightColorValue,
    double highlightOpacity = kDefaultNoteHighlightOpacity,
  }) async {
    final now = DateTime.now();

    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final anchorId = _uuid.v4();
    final normalizedNoteType = _normalizeNoteType(noteType);
    final isTodoNote = normalizedNoteType == kTodoNoteType;

    final cleanSelectedText = _cleanOptionalText(selectedText);
    final cleanSourceRects = sourceRects.where((rect) => rect.isValid).toList();

    final placement = SidecarNotePlacement(
      pageNumber: pageNumber,
      x: x.clamp(0.0, 1.0).toDouble(),
      y: y.clamp(0.0, 1.0).toDouble(),
      width: width.clamp(0.15, 1.0).toDouble(),
    );

    final metadata = NoteMetadata(
      highlightEnabled: cleanSourceRects.isNotEmpty,
      highlightColorValue: highlightColorValue,
      highlightOpacity: highlightOpacity,
    );

    await database.transaction(() async {
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              noteType: Value(normalizedNoteType),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: blockId,
              noteId: noteId,
              blockType: Value(isTodoNote ? kTodoBlockType : 'text'),
              contentText: const Value(''),
              contentJson: isTodoNote
                  ? Value(
                      jsonEncode({
                        'sourceType': kTodoSourceSidecarNote,
                        'priority': kTodoPriorityMedium,
                        'isCompleted': false,
                      }),
                    )
                  : const Value.absent(),
              sortOrder: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteAnchors)
          .insert(
            NoteAnchorsCompanion.insert(
              id: anchorId,
              noteId: noteId,
              documentId: Value(documentId),
              anchorType: 'sidecarPosition',
              pageNumber: Value(pageNumber),
              selectedText: Value(cleanSelectedText),
              geometryJson: Value(
                placement.toJsonString(
                  sourceRects: cleanSourceRects,
                  metadata: metadata,
                ),
              ),
              createdAt: now,
            ),
          );
    });

    return _getSidecarNote(noteId);
  }

  Future<void> createPersistentHighlight({
    required String documentId,
    required int pageNumber,
    required String? selectedText,
    required List<PdfSourceRect> sourceRects,
    int highlightColorValue = kDefaultNoteHighlightColorValue,
    double highlightOpacity = kDefaultNoteHighlightOpacity,
  }) async {
    final cleanSourceRects = sourceRects.where((rect) => rect.isValid).toList();

    if (cleanSourceRects.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final noteId = _uuid.v4();
    final anchorId = _uuid.v4();

    await database.transaction(() async {
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              noteType: const Value('highlight'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteAnchors)
          .insert(
            NoteAnchorsCompanion.insert(
              id: anchorId,
              noteId: noteId,
              documentId: Value(documentId),
              anchorType: 'pdfHighlight',
              pageNumber: Value(pageNumber),
              selectedText: Value(_cleanOptionalText(selectedText)),
              geometryJson: Value(
                jsonEncode({
                  'sourceRects': [
                    for (final rect in cleanSourceRects) rect.toJson(),
                  ],
                  'metadata': NoteMetadata(
                    highlightEnabled: true,
                    highlightColorValue: highlightColorValue,
                    highlightOpacity: highlightOpacity,
                  ).toJson(),
                }),
              ),
              createdAt: now,
            ),
          );
    });
  }

  Future<void> removePersistentHighlightRegion(
    PdfLinkedHighlightRegion region,
  ) async {
    if (region.isStandaloneHighlight) {
      await archiveNote(region.noteId);
      return;
    }

    await _setAnchorHighlightEnabled(anchorId: region.anchorId, enabled: false);
  }

  Future<void> restorePersistentHighlightRegion(
    PdfLinkedHighlightRegion region,
  ) async {
    if (region.isStandaloneHighlight) {
      await (database.update(
        database.notes,
      )..where((table) => table.id.equals(region.noteId))).write(
        NotesCompanion(
          isArchived: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return;
    }

    await _setAnchorHighlightEnabled(anchorId: region.anchorId, enabled: true);
  }

  Future<void> updatePersistentHighlightStyle({
    required PdfLinkedHighlightRegion region,
    required int highlightColorValue,
    double? highlightOpacity,
    String? highlightStyle,
  }) async {
    await _updateAnchorHighlightMetadata(
      anchorId: region.anchorId,
      metadataBuilder: (metadata) => metadata.copyWith(
        highlightEnabled: true,
        highlightColorValue: highlightColorValue,
        highlightOpacity: highlightOpacity,
        highlightStyle: highlightStyle,
      ),
    );
  }

  Future<void> _setAnchorHighlightEnabled({
    required String anchorId,
    required bool enabled,
  }) async {
    await _updateAnchorHighlightMetadata(
      anchorId: anchorId,
      metadataBuilder: (metadata) =>
          metadata.copyWith(highlightEnabled: enabled),
    );
  }

  Future<void> _updateAnchorHighlightMetadata({
    required String anchorId,
    required NoteMetadata Function(NoteMetadata metadata) metadataBuilder,
  }) async {
    final existingAnchor = await (database.select(
      database.noteAnchors,
    )..where((table) => table.id.equals(anchorId))).getSingleOrNull();

    if (existingAnchor == null) {
      return;
    }

    final geometry = _decodeGeometry(existingAnchor.geometryJson);
    final metadata = metadataBuilder(NoteMetadata.fromAnchor(existingAnchor));

    geometry['metadata'] = metadata.toJson();

    await database.transaction(() async {
      await (database.update(
        database.noteAnchors,
      )..where((table) => table.id.equals(anchorId))).write(
        NoteAnchorsCompanion(geometryJson: Value(jsonEncode(geometry))),
      );

      await (database.update(database.notes)
            ..where((table) => table.id.equals(existingAnchor.noteId)))
          .write(NotesCompanion(updatedAt: Value(DateTime.now())));
    });
  }

  Future<void> updateTextBlock({
    required String noteId,
    required String blockId,
    required String body,
  }) async {
    final now = DateTime.now();

    await database.transaction(() async {
      await (database.update(
        database.noteBlocks,
      )..where((table) => table.id.equals(blockId))).write(
        NoteBlocksCompanion(contentText: Value(body), updatedAt: Value(now)),
      );

      await (database.update(database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> updateNoteType({
    required String noteId,
    required String noteType,
  }) async {
    final normalizedNoteType = _normalizeNoteType(noteType);
    final now = DateTime.now();

    await database.transaction(() async {
      await (database.update(
        database.notes,
      )..where((table) => table.id.equals(noteId))).write(
        NotesCompanion(
          noteType: Value(normalizedNoteType),
          updatedAt: Value(now),
        ),
      );

      if (normalizedNoteType == kTodoNoteType) {
        await _ensureNoteHasTodoMetadata(
          noteId: noteId,
          sourceType: kTodoSourceSidecarNote,
          updatedAt: now,
        );
      }
    });
  }

  Future<void> updateNoteMetadata({
    required String anchorId,
    required NoteMetadata metadata,
  }) async {
    final existingAnchor = await (database.select(
      database.noteAnchors,
    )..where((table) => table.id.equals(anchorId))).getSingleOrNull();

    if (existingAnchor == null) {
      return;
    }

    final geometry = _decodeGeometry(existingAnchor.geometryJson);
    geometry['metadata'] = metadata.toJson();

    await (database.update(database.noteAnchors)
          ..where((table) => table.id.equals(anchorId)))
        .write(NoteAnchorsCompanion(geometryJson: Value(jsonEncode(geometry))));

    await (database.update(database.notes)
          ..where((table) => table.id.equals(existingAnchor.noteId)))
        .write(NotesCompanion(updatedAt: Value(DateTime.now())));
  }

  Future<void> moveSidecarNote({
    required String anchorId,
    required int pageNumber,
    required double x,
    required double y,
    required double width,
  }) async {
    final existingAnchor = await (database.select(
      database.noteAnchors,
    )..where((table) => table.id.equals(anchorId))).getSingleOrNull();

    final geometry = _decodeGeometry(existingAnchor?.geometryJson);

    geometry['placementType'] = 'sidecar';
    geometry['pageNumber'] = pageNumber;
    geometry['x'] = x.clamp(0.0, 1.0).toDouble();
    geometry['y'] = y.clamp(0.0, 1.0).toDouble();
    geometry['width'] = width.clamp(0.15, 1.0).toDouble();

    await (database.update(
      database.noteAnchors,
    )..where((table) => table.id.equals(anchorId))).write(
      NoteAnchorsCompanion(
        pageNumber: Value(pageNumber),
        geometryJson: Value(jsonEncode(geometry)),
      ),
    );
  }

  Future<void> moveReaderSidecarNote({
    required String anchorId,
    required int spineIndex,
    String? href,
    String? sectionTitle,
    int? paragraphIndex,
    required double x,
    required double y,
    required double width,
  }) async {
    final existingAnchor = await (database.select(
      database.noteAnchors,
    )..where((table) => table.id.equals(anchorId))).getSingleOrNull();

    if (existingAnchor == null) {
      return;
    }

    final geometry = _decodeGeometry(existingAnchor.geometryJson);

    geometry['placementType'] = 'epubSidecar';
    geometry['spineIndex'] = spineIndex < 0 ? 0 : spineIndex;
    if (href != null && href.trim().isNotEmpty) {
      geometry['href'] = href.trim();
    }
    if (sectionTitle != null && sectionTitle.trim().isNotEmpty) {
      geometry['sectionTitle'] = sectionTitle.trim();
    }
    if (paragraphIndex != null && paragraphIndex >= 0) {
      geometry['paragraphIndex'] = paragraphIndex;
    }
    geometry['x'] = x.clamp(0.0, 1.0).toDouble();
    geometry['y'] = y.clamp(0.0, 1.0).toDouble();
    geometry['width'] = width.clamp(0.18, 1.0).toDouble();

    final rawAnchor = geometry['readerAnchor'];
    if (rawAnchor is Map) {
      rawAnchor['epubSpineIndex'] = geometry['spineIndex'];
      rawAnchor['epubHref'] = geometry['href'];
      rawAnchor['sectionTitle'] = geometry['sectionTitle'];
      rawAnchor['paragraphIndex'] = geometry['paragraphIndex'];
      geometry['readerAnchor'] = rawAnchor;
    }

    await (database.update(
      database.noteAnchors,
    )..where((table) => table.id.equals(anchorId))).write(
      NoteAnchorsCompanion(geometryJson: Value(jsonEncode(geometry))),
    );

    await (database.update(database.notes)
          ..where((table) => table.id.equals(existingAnchor.noteId)))
        .write(NotesCompanion(updatedAt: Value(DateTime.now())));
  }

  Future<void> archiveNote(String noteId) async {
    await (database.update(
      database.notes,
    )..where((table) => table.id.equals(noteId))).write(
      NotesCompanion(
        isArchived: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> archiveNoteIfEmpty({
    required String noteId,
    required String blockId,
  }) async {
    final block = await (database.select(
      database.noteBlocks,
    )..where((table) => table.id.equals(blockId))).getSingleOrNull();

    final text = block?.contentText?.trim() ?? '';

    if (text.isEmpty) {
      await archiveNote(noteId);
    }
  }

  Future<NoteWithAnchor> createTextNoteForPage({
    required String documentId,
    required int pageNumber,
    required String body,
    String? selectedText,
  }) async {
    final note = await createSidecarTextNote(
      documentId: documentId,
      pageNumber: pageNumber,
      x: 0.08,
      y: 0.12,
      width: 0.42,
      noteType: 'note',
      selectedText: selectedText,
    );

    final block = note.firstBlock;
    if (block != null) {
      await updateTextBlock(
        noteId: note.note.id,
        blockId: block.id,
        body: body,
      );
    }

    return _getSidecarNote(note.note.id);
  }

  Stream<List<NoteWithAnchor>> watchNotesForPage({
    required String documentId,
    required int pageNumber,
  }) {
    return watchSidecarNotesForDocument(documentId: documentId).map((notes) {
      return notes
          .where((note) => note.sidecarPlacement.pageNumber == pageNumber)
          .toList();
    });
  }

  Future<NoteWithAnchor> _getReaderAnchoredNote(String noteId) async {
    final query = database.select(database.noteAnchors).join([
      innerJoin(
        database.notes,
        database.notes.id.equalsExp(database.noteAnchors.noteId),
      ),
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
    ]);

    query.where(
      database.noteAnchors.noteId.equals(noteId) &
          database.noteAnchors.anchorType.isIn(kReaderAnchorTypes) &
          database.notes.isArchived.equals(false),
    );

    final row = await query.getSingle();

    return NoteWithAnchor(
      anchor: row.readTable(database.noteAnchors),
      note: row.readTable(database.notes),
      firstBlock: row.readTableOrNull(database.noteBlocks),
    );
  }

  Future<NoteWithAnchor> _getSidecarNote(String noteId) async {
    final query = database.select(database.noteAnchors).join([
      innerJoin(
        database.notes,
        database.notes.id.equalsExp(database.noteAnchors.noteId),
      ),
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
    ]);

    query.where(
      database.noteAnchors.noteId.equals(noteId) &
          database.noteAnchors.anchorType.equals('sidecarPosition') &
          database.notes.isArchived.equals(false),
    );

    final row = await query.getSingle();

    return NoteWithAnchor(
      anchor: row.readTable(database.noteAnchors),
      note: row.readTable(database.notes),
      firstBlock: row.readTableOrNull(database.noteBlocks),
    );
  }

  Stream<List<StructuredDocumentNote>> watchDocumentNotesForDocument({
    required String documentId,
  }) {
    final query = database.select(database.notes).join([
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
    ]);

    query.where(
      database.notes.documentId.equals(documentId) &
          database.notes.noteType.equals('documentNote') &
          database.notes.isArchived.equals(false),
    );

    query.orderBy([
      OrderingTerm.desc(database.notes.updatedAt),
      OrderingTerm.asc(database.noteBlocks.sortOrder),
      OrderingTerm.asc(database.noteBlocks.createdAt),
    ]);

    return query.watch().map((rows) {
      final notesById = <String, Note>{};
      final blocksByNoteId = <String, List<DocumentNoteBlock>>{};

      for (final row in rows) {
        final note = row.readTable(database.notes);
        final block = row.readTableOrNull(database.noteBlocks);

        notesById[note.id] = note;
        if (block != null) {
          blocksByNoteId
              .putIfAbsent(note.id, () => [])
              .add(DocumentNoteBlock(block: block));
        } else {
          blocksByNoteId.putIfAbsent(note.id, () => []);
        }
      }

      return [
        for (final note in notesById.values)
          StructuredDocumentNote(
            note: note,
            blocks: blocksByNoteId[note.id] ?? const [],
          ),
      ];
    });
  }

  Future<StructuredDocumentNote> ensureDefaultDocumentNote({
    required String documentId,
    required String documentTitle,
  }) async {
    final existing =
        await (database.select(database.notes)
              ..where(
                (table) =>
                    table.documentId.equals(documentId) &
                    table.noteType.equals('documentNote') &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.createdAt)])
              ..limit(1))
            .getSingleOrNull();

    if (existing != null) {
      return _getStructuredDocumentNote(existing.id);
    }

    return createDocumentNote(
      documentId: documentId,
      title: 'Notes — $documentTitle',
    );
  }

  Future<StructuredDocumentNote> createDocumentNote({
    required String documentId,
    required String title,
  }) async {
    final now = DateTime.now();
    final noteId = _uuid.v4();
    final blockId = _uuid.v4();

    await database.transaction(() async {
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              title: Value(_cleanOptionalText(title) ?? 'Reading note'),
              noteType: const Value('documentNote'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: blockId,
              noteId: noteId,
              blockType: const Value(DocumentNoteBlockTypes.structuredDocument),
              contentText: const Value(''),
              contentJson: const Value('{"version":1,"references":{}}'),
              sortOrder: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    return _getStructuredDocumentNote(noteId);
  }

  Future<void> updateDocumentNoteTitle({
    required String noteId,
    required String title,
  }) async {
    await (database.update(
      database.notes,
    )..where((table) => table.id.equals(noteId))).write(
      NotesCompanion(
        title: Value(_cleanOptionalText(title)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateStructuredDocumentNote({
    required String noteId,
    required String text,
    required String contentJson,
  }) async {
    final now = DateTime.now();

    await database.transaction(() async {
      final existing =
          await (database.select(database.noteBlocks)
                ..where(
                  (table) =>
                      table.noteId.equals(noteId) &
                      table.blockType.equals(
                        DocumentNoteBlockTypes.structuredDocument,
                      ),
                )
                ..limit(1))
              .getSingleOrNull();

      String structuredBlockId;

      if (existing == null) {
        structuredBlockId = _uuid.v4();
        await database
            .into(database.noteBlocks)
            .insert(
              NoteBlocksCompanion.insert(
                id: structuredBlockId,
                noteId: noteId,
                blockType: const Value(
                  DocumentNoteBlockTypes.structuredDocument,
                ),
                contentText: Value(text),
                contentJson: Value(contentJson),
                sortOrder: const Value(0),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        structuredBlockId = existing.id;
        await (database.update(
          database.noteBlocks,
        )..where((table) => table.id.equals(structuredBlockId))).write(
          NoteBlocksCompanion(
            contentText: Value(text),
            contentJson: Value(contentJson),
            updatedAt: Value(now),
          ),
        );
      }

      // Document notes now use a single editable structured-document block.
      // Remove legacy paragraph/math/pdfReference rows once the note has been
      // saved through the new editor.
      await (database.delete(database.noteBlocks)..where(
            (table) =>
                table.noteId.equals(noteId) &
                table.id.equals(structuredBlockId).not(),
          ))
          .go();

      await (database.update(database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> addDocumentNoteBlock({
    required String noteId,
    required String blockType,
    String contentText = '',
    String? contentJson,
  }) async {
    final now = DateTime.now();
    final nextSortOrder = await _nextDocumentNoteBlockSortOrder(noteId);

    await database.transaction(() async {
      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: _uuid.v4(),
              noteId: noteId,
              blockType: Value(_normalizeDocumentNoteBlockType(blockType)),
              contentText: Value(contentText),
              contentJson: Value(contentJson),
              sortOrder: Value(nextSortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await (database.update(database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> addPdfReferenceBlockToDocumentNote({
    required String noteId,
    required String documentId,
    required int pageNumber,
    required String selectedText,
    required List<PdfSourceRect> sourceRects,
    String? citationLabel,
  }) async {
    final cleanText = selectedText.trim();
    final cleanSourceRects = sourceRects.where((rect) => rect.isValid).toList();

    if (cleanText.isEmpty || cleanSourceRects.isEmpty) {
      return;
    }

    final reference = DocumentNotePdfReference(
      documentId: documentId,
      pageNumber: pageNumber,
      selectedText: cleanText,
      sourceRects: cleanSourceRects,
      citationLabel: citationLabel ?? 'p. $pageNumber',
    );

    await addDocumentNoteBlock(
      noteId: noteId,
      blockType: DocumentNoteBlockTypes.pdfReference,
      contentText: cleanText,
      contentJson: jsonEncode(reference.toJson()),
    );
  }

  Future<void> updateDocumentNoteBlockText({
    required String noteId,
    required String blockId,
    required String text,
  }) async {
    final now = DateTime.now();

    await database.transaction(() async {
      await (database.update(
        database.noteBlocks,
      )..where((table) => table.id.equals(blockId))).write(
        NoteBlocksCompanion(contentText: Value(text), updatedAt: Value(now)),
      );

      await (database.update(database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> deleteDocumentNoteBlock({
    required String noteId,
    required String blockId,
  }) async {
    final now = DateTime.now();

    await database.transaction(() async {
      await (database.delete(
        database.noteBlocks,
      )..where((table) => table.id.equals(blockId))).go();

      await (database.update(database.notes)
            ..where((table) => table.id.equals(noteId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Stream<List<TodoItem>> watchTodos({
    String? documentId,
    bool includeCompleted = false,
  }) {
    final query = database.select(database.notes).join([
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
      leftOuterJoin(
        database.noteAnchors,
        database.noteAnchors.noteId.equalsExp(database.notes.id),
      ),
      leftOuterJoin(
        database.pdfDocuments,
        database.pdfDocuments.documentId.equalsExp(database.notes.documentId),
      ),
    ]);

    var predicate =
        database.notes.noteType.equals(kTodoNoteType) &
        database.notes.isArchived.equals(false);

    if (documentId != null && documentId.trim().isNotEmpty) {
      predicate = predicate & database.notes.documentId.equals(documentId);
    }

    query.where(predicate);

    query.orderBy([
      OrderingTerm.asc(database.notes.createdAt),
      OrderingTerm.asc(database.noteBlocks.sortOrder),
      OrderingTerm.asc(database.noteAnchors.createdAt),
    ]);

    return query.watch().map((rows) {
      final byId = <String, TodoItem>{};

      for (final row in rows) {
        final note = row.readTable(database.notes);
        final block = row.readTableOrNull(database.noteBlocks);
        final anchor = row.readTableOrNull(database.noteAnchors);
        final pdfDocument = row.readTableOrNull(database.pdfDocuments);

        final todo = TodoItem.fromRow(
          note: note,
          block: block,
          anchor: anchor,
          documentName: pdfDocument?.name ?? pdfDocument?.originalFileName,
        );

        if (!includeCompleted && todo.isCompleted) {
          continue;
        }

        byId[note.id] = todo;
      }

      final todos = byId.values.toList();
      todos.sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }

        final aDeadline = a.deadline;
        final bDeadline = b.deadline;
        if (aDeadline != null && bDeadline != null) {
          final compare = aDeadline.compareTo(bDeadline);
          if (compare != 0) return compare;
        } else if (aDeadline != null) {
          return -1;
        } else if (bDeadline != null) {
          return 1;
        }

        final priorityCompare = _priorityRank(
          b.priority,
        ).compareTo(_priorityRank(a.priority));
        if (priorityCompare != 0) return priorityCompare;

        return b.note.updatedAt.compareTo(a.note.updatedAt);
      });

      return todos;
    });
  }


  Future<String> createStandaloneTodo({
    required String title,
    String? body,
    String priority = kTodoPriorityMedium,
    String sourceType = kTodoSourceTodaySetup,
    DateTime? deadline,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'New TODO' : title.trim();
    final cleanBody = body?.trim();
    final now = DateTime.now();
    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final normalizedPriority = _normalizeTodoPriority(priority);

    await database.transaction(() async {
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              title: Value(cleanTitle),
              noteType: const Value(kTodoNoteType),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: blockId,
              noteId: noteId,
              blockType: const Value(kTodoBlockType),
              contentText: Value(cleanTitle),
              contentJson: Value(
                jsonEncode({
                  'sourceType': sourceType,
                  if (cleanBody != null && cleanBody.isNotEmpty) 'body': cleanBody,
                  'priority': normalizedPriority,
                  'isCompleted': false,
                  if (deadline != null) 'deadline': deadline.toIso8601String(),
                }),
              ),
              sortOrder: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });

    return noteId;
  }

  Future<void> createPdfTextSelectionTodo({
    required String documentId,
    required int pageNumber,
    required String selectedText,
    required List<PdfSourceRect> sourceRects,
    String priority = kTodoPriorityMedium,
    DateTime? deadline,
  }) async {
    final cleanText = _shortenTodoTitle(selectedText);
    final cleanSourceRects = sourceRects.where((rect) => rect.isValid).toList();

    if (cleanText.isEmpty || cleanSourceRects.isEmpty) {
      throw ArgumentError(
        'A PDF text TODO requires selected text and source rects.',
      );
    }

    final now = DateTime.now();
    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final anchorId = _uuid.v4();
    final normalizedPriority = _normalizeTodoPriority(priority);

    await database.transaction(() async {
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              title: Value(cleanText),
              noteType: const Value(kTodoNoteType),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: blockId,
              noteId: noteId,
              blockType: const Value(kTodoBlockType),
              contentText: Value(cleanText),
              contentJson: Value(
                jsonEncode({
                  'sourceType': kTodoSourcePdfTextSelection,
                  'priority': normalizedPriority,
                  'isCompleted': false,
                  if (deadline != null) 'deadline': deadline.toIso8601String(),
                }),
              ),
              sortOrder: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteAnchors)
          .insert(
            NoteAnchorsCompanion.insert(
              id: anchorId,
              noteId: noteId,
              documentId: Value(documentId),
              anchorType: _anchorTypeFromTodoSource(
                kTodoSourcePdfTextSelection,
              ),
              pageNumber: Value(pageNumber),
              selectedText: Value(selectedText.trim()),
              geometryJson: Value(
                jsonEncode({
                  'sourceRects': [
                    for (final rect in cleanSourceRects) rect.toJson(),
                  ],
                  'todo': {'sourceType': kTodoSourcePdfTextSelection},
                  'metadata': NoteMetadata(
                    highlightEnabled: true,
                    highlightColorValue: TodoItem.colorForPriority(
                      normalizedPriority,
                    ),
                    highlightOpacity: kTodoHighlightOpacity,
                    highlightStyle: 'todo',
                  ).toJson(),
                }),
              ),
              createdAt: now,
            ),
          );
    });
  }

  Future<String> createDocumentNoteTodo({
    required String documentId,
    required String documentNoteId,
    required String documentNodeId,
    String title = 'New TODO',
    String priority = kTodoPriorityMedium,
    DateTime? deadline,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'New TODO' : title.trim();
    final now = DateTime.now();
    final noteId = _uuid.v4();
    final blockId = _uuid.v4();
    final anchorId = _uuid.v4();
    final normalizedPriority = _normalizeTodoPriority(priority);

    await database.transaction(() async {
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: noteId,
              documentId: Value(documentId),
              title: Value(cleanTitle),
              noteType: const Value(kTodoNoteType),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: blockId,
              noteId: noteId,
              blockType: const Value(kTodoBlockType),
              contentText: Value(cleanTitle),
              contentJson: Value(
                jsonEncode({
                  'sourceType': kTodoSourceDocumentNote,
                  'priority': normalizedPriority,
                  'isCompleted': false,
                  if (deadline != null) 'deadline': deadline.toIso8601String(),
                }),
              ),
              sortOrder: const Value(0),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await database
          .into(database.noteAnchors)
          .insert(
            NoteAnchorsCompanion.insert(
              id: anchorId,
              noteId: noteId,
              documentId: Value(documentId),
              anchorType: _anchorTypeFromTodoSource(kTodoSourceDocumentNote),
              selectedText: Value(cleanTitle),
              geometryJson: Value(
                jsonEncode({
                  'documentNoteId': documentNoteId,
                  'documentNodeId': documentNodeId,
                  'todo': {'sourceType': kTodoSourceDocumentNote},
                }),
              ),
              createdAt: now,
            ),
          );
    });

    return noteId;
  }

  Future<void> _ensureNoteHasTodoMetadata({
    required String noteId,
    required String sourceType,
    required DateTime updatedAt,
  }) async {
    final block =
        await (database.select(database.noteBlocks)
              ..where((table) => table.noteId.equals(noteId))
              ..orderBy([
                (table) => OrderingTerm.asc(table.sortOrder),
                (table) => OrderingTerm.asc(table.createdAt),
              ])
              ..limit(1))
            .getSingleOrNull();

    if (block == null) {
      await database
          .into(database.noteBlocks)
          .insert(
            NoteBlocksCompanion.insert(
              id: _uuid.v4(),
              noteId: noteId,
              blockType: const Value(kTodoBlockType),
              contentText: const Value(''),
              contentJson: Value(
                jsonEncode({
                  'sourceType': sourceType,
                  'priority': kTodoPriorityMedium,
                  'isCompleted': false,
                }),
              ),
              sortOrder: const Value(0),
              createdAt: updatedAt,
              updatedAt: updatedAt,
            ),
          );
      return;
    }

    final metadata = _decodeTodoJson(block.contentJson);
    metadata['sourceType'] = sourceType;
    metadata['priority'] = _normalizeTodoPriority(
      _readString(metadata['priority']),
    );
    metadata['isCompleted'] = _readBool(metadata['isCompleted']) ?? false;

    await (database.update(
      database.noteBlocks,
    )..where((table) => table.id.equals(block.id))).write(
      NoteBlocksCompanion(
        blockType: const Value(kTodoBlockType),
        contentJson: Value(jsonEncode(metadata)),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> updateTodoTitle({
    required String todoId,
    required String title,
  }) async {
    final existing = await _getTodoItem(todoId);
    if (existing == null) return;

    final cleanTitle = title.trim().isEmpty ? 'Untitled TODO' : title.trim();
    final now = DateTime.now();

    await database.transaction(() async {
      final block = existing.block;
      if (block != null) {
        await (database.update(
          database.noteBlocks,
        )..where((t) => t.id.equals(block.id))).write(
          NoteBlocksCompanion(
            contentText: Value(cleanTitle),
            updatedAt: Value(now),
          ),
        );
      }

      await (database.update(
        database.notes,
      )..where((t) => t.id.equals(todoId))).write(
        NotesCompanion(title: Value(cleanTitle), updatedAt: Value(now)),
      );

      final anchor = existing.anchor;
      if (anchor != null) {
        await (database.update(database.noteAnchors)
              ..where((t) => t.id.equals(anchor.id)))
            .write(NoteAnchorsCompanion(selectedText: Value(cleanTitle)));
      }
    });
  }

  Future<void> updateTodoCompleted({
    required String todoId,
    required bool isCompleted,
  }) async {
    final existing = await _getTodoItem(todoId);
    if (existing == null) return;

    final now = DateTime.now();
    final metadata = existing.metadataJson(
      isCompleted: isCompleted,
      completedAt: isCompleted ? now : null,
    );

    await database.transaction(() async {
      await _updateTodoBlockJson(
        todo: existing,
        metadata: metadata,
        updatedAt: now,
      );

      await (database.update(database.notes)..where((t) => t.id.equals(todoId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> updateTodoPriority({
    required String todoId,
    required String priority,
  }) async {
    final existing = await _getTodoItem(todoId);
    if (existing == null) return;

    final now = DateTime.now();
    final normalizedPriority = _normalizeTodoPriority(priority);

    await database.transaction(() async {
      await _updateTodoBlockJson(
        todo: existing,
        metadata: existing.metadataJson(priority: normalizedPriority),
        updatedAt: now,
      );

      final anchor = existing.anchor;
      if (anchor != null) {
        final geometry = _decodeGeometry(anchor.geometryJson);
        geometry['metadata'] = NoteMetadata(
          highlightEnabled: true,
          highlightColorValue: TodoItem.colorForPriority(normalizedPriority),
          highlightOpacity: kTodoHighlightOpacity,
          highlightStyle: 'todo',
        ).toJson();

        await (database.update(
          database.noteAnchors,
        )..where((t) => t.id.equals(anchor.id))).write(
          NoteAnchorsCompanion(geometryJson: Value(jsonEncode(geometry))),
        );
      }

      await (database.update(database.notes)..where((t) => t.id.equals(todoId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> updateTodoDeadline({
    required String todoId,
    DateTime? deadline,
  }) async {
    final existing = await _getTodoItem(todoId);
    if (existing == null) return;

    final now = DateTime.now();
    await database.transaction(() async {
      await _updateTodoBlockJson(
        todo: existing,
        metadata: existing.metadataJson(
          deadline: deadline,
          clearDeadline: deadline == null,
        ),
        updatedAt: now,
      );

      await (database.update(database.notes)..where((t) => t.id.equals(todoId)))
          .write(NotesCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> archiveTodo(String todoId) {
    return archiveNote(todoId);
  }

  Future<TodoItem?> _getTodoItem(String todoId) async {
    final query = database.select(database.notes).join([
      leftOuterJoin(
        database.noteBlocks,
        database.noteBlocks.noteId.equalsExp(database.notes.id),
      ),
      leftOuterJoin(
        database.noteAnchors,
        database.noteAnchors.noteId.equalsExp(database.notes.id),
      ),
      leftOuterJoin(
        database.pdfDocuments,
        database.pdfDocuments.documentId.equalsExp(database.notes.documentId),
      ),
    ]);

    query.where(database.notes.id.equals(todoId));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return TodoItem.fromRow(
      note: row.readTable(database.notes),
      block: row.readTableOrNull(database.noteBlocks),
      anchor: row.readTableOrNull(database.noteAnchors),
      documentName: row.readTableOrNull(database.pdfDocuments)?.name,
    );
  }

  Future<void> _updateTodoBlockJson({
    required TodoItem todo,
    required Map<String, dynamic> metadata,
    required DateTime updatedAt,
  }) async {
    final block = todo.block;
    if (block == null) return;

    await (database.update(
      database.noteBlocks,
    )..where((t) => t.id.equals(block.id))).write(
      NoteBlocksCompanion(
        contentText: Value(todo.title),
        contentJson: Value(jsonEncode(metadata)),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  int _priorityRank(String priority) {
    switch (_normalizeTodoPriority(priority)) {
      case kTodoPriorityHigh:
        return 3;
      case kTodoPriorityMedium:
        return 2;
      case kTodoPriorityLow:
      default:
        return 1;
    }
  }

  Future<StructuredDocumentNote> _getStructuredDocumentNote(
    String noteId,
  ) async {
    final note = await (database.select(
      database.notes,
    )..where((table) => table.id.equals(noteId))).getSingle();

    final blocks =
        await (database.select(database.noteBlocks)
              ..where((table) => table.noteId.equals(noteId))
              ..orderBy([
                (table) => OrderingTerm.asc(table.sortOrder),
                (table) => OrderingTerm.asc(table.createdAt),
              ]))
            .get();

    return StructuredDocumentNote(
      note: note,
      blocks: [for (final block in blocks) DocumentNoteBlock(block: block)],
    );
  }

  Future<int> _nextDocumentNoteBlockSortOrder(String noteId) async {
    final blocks =
        await (database.select(database.noteBlocks)
              ..where((table) => table.noteId.equals(noteId))
              ..orderBy([(table) => OrderingTerm.desc(table.sortOrder)])
              ..limit(1))
            .get();

    if (blocks.isEmpty) {
      return 0;
    }

    return blocks.first.sortOrder + 1;
  }

  String _normalizeDocumentNoteBlockType(String value) {
    switch (value.trim()) {
      case DocumentNoteBlockTypes.structuredDocument:
      case DocumentNoteBlockTypes.math:
      case DocumentNoteBlockTypes.pdfReference:
      case DocumentNoteBlockTypes.paragraph:
        return value.trim();
      case 'text':
        return DocumentNoteBlockTypes.paragraph;
      default:
        return DocumentNoteBlockTypes.paragraph;
    }
  }

  String _normalizeNoteType(String value) {
    final normalized = value.trim();

    switch (normalized) {
      case 'question':
      case 'summary':
      case 'definition':
      case 'task':
      case 'citation':
      case 'highlight':
      case 'documentNote':
      case kTodoNoteType:
      case 'note':
        return normalized;
      default:
        return 'note';
    }
  }

  String? _cleanOptionalText(String? value) {
    if (value == null) return null;

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, dynamic> _decodeGeometry(String? geometryJson) {
    if (geometryJson == null || geometryJson.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(geometryJson);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return {};
    }

    return {};
  }
}
