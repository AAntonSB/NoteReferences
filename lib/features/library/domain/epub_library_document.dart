import 'package:flutter/foundation.dart';

@immutable
class EpubLibraryDocument {
  final String documentId;
  final String filePath;
  final String originalFileName;
  final String title;
  final String? authors;
  final String? language;
  final String? publisher;
  final String? identifier;
  final String? description;
  final int spineItemCount;
  final int tocEntryCount;
  final bool hasPageMap;
  final DateTime addedAt;
  final DateTime? fileLastModifiedAt;
  final DateTime? metadataLastReadAt;

  const EpubLibraryDocument({
    required this.documentId,
    required this.filePath,
    required this.originalFileName,
    required this.title,
    this.authors,
    this.language,
    this.publisher,
    this.identifier,
    this.description,
    this.spineItemCount = 0,
    this.tocEntryCount = 0,
    this.hasPageMap = false,
    required this.addedAt,
    this.fileLastModifiedAt,
    this.metadataLastReadAt,
  });

  String get displayTitle {
    final trimmed = title.trim();
    return trimmed.isEmpty ? originalFileName : trimmed;
  }

  String get metadataSummary {
    final pieces = <String>[];
    final authorText = authors?.trim();
    if (authorText != null && authorText.isNotEmpty) pieces.add(authorText);
    final publisherText = publisher?.trim();
    if (publisherText != null && publisherText.isNotEmpty) pieces.add(publisherText);
    final languageText = language?.trim();
    if (languageText != null && languageText.isNotEmpty) pieces.add(languageText);
    return pieces.isEmpty ? 'EPUB metadata imported' : pieces.join(' · ');
  }

  String get structureSummary {
    final pieces = <String>[];
    if (tocEntryCount > 0) {
      pieces.add('$tocEntryCount TOC ${tocEntryCount == 1 ? 'entry' : 'entries'}');
    } else {
      pieces.add('No TOC detected');
    }
    if (spineItemCount > 0) {
      pieces.add('$spineItemCount spine ${spineItemCount == 1 ? 'item' : 'items'}');
    }
    if (hasPageMap) {
      pieces.add('page map');
    }
    return pieces.join(' · ');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'filePath': filePath,
      'originalFileName': originalFileName,
      'title': title,
      'authors': authors,
      'language': language,
      'publisher': publisher,
      'identifier': identifier,
      'description': description,
      'spineItemCount': spineItemCount,
      'tocEntryCount': tocEntryCount,
      'hasPageMap': hasPageMap,
      'addedAt': addedAt.toIso8601String(),
      'fileLastModifiedAt': fileLastModifiedAt?.toIso8601String(),
      'metadataLastReadAt': metadataLastReadAt?.toIso8601String(),
    };
  }

  factory EpubLibraryDocument.fromJson(Map<String, Object?> json) {
    DateTime? optionalDate(Object? value) {
      if (value is! String || value.trim().isEmpty) return null;
      return DateTime.tryParse(value);
    }

    int intValue(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    bool boolValue(Object? value) {
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    String stringValue(Object? value) => value is String ? value : '';
    String? optionalString(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return EpubLibraryDocument(
      documentId: stringValue(json['documentId']),
      filePath: stringValue(json['filePath']),
      originalFileName: stringValue(json['originalFileName']),
      title: stringValue(json['title']),
      authors: optionalString(json['authors']),
      language: optionalString(json['language']),
      publisher: optionalString(json['publisher']),
      identifier: optionalString(json['identifier']),
      description: optionalString(json['description']),
      spineItemCount: intValue(json['spineItemCount']),
      tocEntryCount: intValue(json['tocEntryCount']),
      hasPageMap: boolValue(json['hasPageMap']),
      addedAt: optionalDate(json['addedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      fileLastModifiedAt: optionalDate(json['fileLastModifiedAt']),
      metadataLastReadAt: optionalDate(json['metadataLastReadAt']),
    );
  }

  EpubLibraryDocument copyWith({
    String? documentId,
    String? filePath,
    String? originalFileName,
    String? title,
    String? authors,
    String? language,
    String? publisher,
    String? identifier,
    String? description,
    int? spineItemCount,
    int? tocEntryCount,
    bool? hasPageMap,
    DateTime? addedAt,
    DateTime? fileLastModifiedAt,
    DateTime? metadataLastReadAt,
  }) {
    return EpubLibraryDocument(
      documentId: documentId ?? this.documentId,
      filePath: filePath ?? this.filePath,
      originalFileName: originalFileName ?? this.originalFileName,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      language: language ?? this.language,
      publisher: publisher ?? this.publisher,
      identifier: identifier ?? this.identifier,
      description: description ?? this.description,
      spineItemCount: spineItemCount ?? this.spineItemCount,
      tocEntryCount: tocEntryCount ?? this.tocEntryCount,
      hasPageMap: hasPageMap ?? this.hasPageMap,
      addedAt: addedAt ?? this.addedAt,
      fileLastModifiedAt: fileLastModifiedAt ?? this.fileLastModifiedAt,
      metadataLastReadAt: metadataLastReadAt ?? this.metadataLastReadAt,
    );
  }
}
