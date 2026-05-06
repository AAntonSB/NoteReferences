import 'text_clipboard_fragment.dart';
import 'text_system_document_fragment.dart';
import 'text_system_document_range.dart';
import 'text_mark.dart';
import 'text_system_range.dart';

enum TextOperationType {
  replaceBlockText,
  toggleMark,
  toggleDocumentMark,
  insertFragment,
  insertDocumentFragment,
  replaceDocument,
}

TextOperationType _textOperationTypeFromName(String? name) {
  return TextOperationType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => TextOperationType.replaceDocument,
  );
}

TextMarkKind? _nullableTextMarkKindFromName(String? name) {
  if (name == null) return null;
  return TextMarkKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => TextMarkKind.bold,
  );
}

/// Describes an intended text-system mutation.
///
/// Operations are intentionally small and serializable-friendly so they can
/// later power persistence, revision history, sync, or review tooling.
class TextOperation {
  const TextOperation({
    required this.type,
    this.blockId,
    this.range,
    this.text,
    this.markKind,
    this.fragment,
    this.documentRange,
    this.documentFragment,
  });

  factory TextOperation.fromJson(Map<String, Object?> json) {
    final rangeJson = json['range'];
    final fragmentJson = json['fragment'];
    final documentRangeJson = json['documentRange'];
    final documentFragmentJson = json['documentFragment'];
    return TextOperation(
      type: _textOperationTypeFromName(json['type'] as String?),
      blockId: json['blockId'] as String?,
      range: rangeJson is Map
          ? TextSystemRange.fromJson(Map<String, Object?>.from(rangeJson))
          : null,
      text: json['text'] as String?,
      markKind: _nullableTextMarkKindFromName(json['markKind'] as String?),
      fragment: fragmentJson is Map
          ? TextClipboardFragment.fromJson(Map<String, Object?>.from(fragmentJson))
          : null,
      documentRange: documentRangeJson is Map
          ? TextSystemDocumentRange.fromJson(Map<String, Object?>.from(documentRangeJson))
          : null,
      documentFragment: documentFragmentJson is Map
          ? TextSystemDocumentFragment.fromJson(Map<String, Object?>.from(documentFragmentJson))
          : null,
    );
  }

  final TextOperationType type;
  final String? blockId;
  final TextSystemRange? range;
  final String? text;
  final TextMarkKind? markKind;
  final TextClipboardFragment? fragment;
  final TextSystemDocumentRange? documentRange;
  final TextSystemDocumentFragment? documentFragment;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      if (blockId != null) 'blockId': blockId,
      if (range != null) 'range': range!.toJson(),
      if (text != null) 'text': text,
      if (markKind != null) 'markKind': markKind!.name,
      if (fragment != null) 'fragment': fragment!.toJson(),
      if (documentRange != null) 'documentRange': documentRange!.toJson(),
      if (documentFragment != null) 'documentFragment': documentFragment!.toJson(),
    };
  }
}
