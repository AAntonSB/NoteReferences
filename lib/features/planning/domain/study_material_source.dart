class StudyMaterialSourceType {
  static const String currentFile = 'currentFile';
  static const String libraryFile = 'libraryFile';
  static const String pdfFile = 'pdfFile';
  static const String epubFile = 'epubFile';
  static const String physicalBook = 'physicalBook';
  static const String articleOrWebsite = 'articleOrWebsite';
  static const String noSourceYet = 'noSourceYet';

  static const List<String> values = <String>[
    currentFile,
    libraryFile,
    pdfFile,
    epubFile,
    physicalBook,
    articleOrWebsite,
    noSourceYet,
  ];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return noSourceYet;
  }

  static String label(String value) {
    switch (normalize(value)) {
      case currentFile:
        return 'Current file';
      case libraryFile:
        return 'Library file';
      case pdfFile:
        return 'PDF file';
      case epubFile:
        return 'EPUB file';
      case physicalBook:
        return 'Physical book';
      case articleOrWebsite:
        return 'Article / website';
      case noSourceYet:
      default:
        return 'No source yet';
    }
  }
}


class StudyMaterialStructureConfidence {
  static const String none = 'none';
  static const String explicitMetadata = 'explicitMetadata';
  static const String parsedToc = 'parsedToc';
  static const String userDefined = 'userDefined';

  static const List<String> values = <String>[
    none,
    explicitMetadata,
    parsedToc,
    userDefined,
  ];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return none;
  }

  static String label(String? value) {
    switch (normalize(value)) {
      case explicitMetadata:
        return 'Explicit outline';
      case parsedToc:
        return 'Parsed table of contents';
      case userDefined:
        return 'User-defined structure';
      case none:
      default:
        return 'No confirmed structure';
    }
  }

  static bool isTrusted(String? value) {
    final normalized = normalize(value);
    return normalized == explicitMetadata || normalized == parsedToc || normalized == userDefined;
  }
}


class StudyMaterialPaginationSource {
  static const String none = 'none';
  static const String epubNavPageList = 'epubNavPageList';
  static const String epubNcxPageList = 'epubNcxPageList';
  static const String epubPageBreakMarkers = 'epubPageBreakMarkers';
  static const String userDefined = 'userDefined';
  static const String generatedLocation = 'generatedLocation';

  static const List<String> values = <String>[
    none,
    epubNavPageList,
    epubNcxPageList,
    epubPageBreakMarkers,
    userDefined,
    generatedLocation,
  ];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return none;
  }

  static String label(String? value) {
    switch (normalize(value)) {
      case epubNavPageList:
        return 'EPUB page-list';
      case epubNcxPageList:
        return 'NCX page list';
      case epubPageBreakMarkers:
        return 'EPUB page breaks';
      case userDefined:
        return 'User-defined pages';
      case generatedLocation:
        return 'Generated locations';
      case none:
      default:
        return 'No page map';
    }
  }

  static bool isRealPageMap(String? value) {
    final normalized = normalize(value);
    return normalized == epubNavPageList ||
        normalized == epubNcxPageList ||
        normalized == epubPageBreakMarkers ||
        normalized == userDefined;
  }
}

class StudyMaterialSegmentType {
  static const String chapter = 'chapter';
  static const String section = 'section';
  static const String pageRange = 'pageRange';
  static const String topic = 'topic';
  static const String exerciseSet = 'exerciseSet';
  static const String custom = 'custom';
  static const String pageMarker = 'pageMarker';

  static const List<String> values = <String>[
    chapter,
    section,
    pageRange,
    topic,
    exerciseSet,
    custom,
    pageMarker,
  ];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return custom;
  }
}

class StudyMaterialSegment {
  final String id;
  final String title;
  final String type;
  final int? startPage;
  final int? endPage;
  final int? estimatedMinutes;
  final double? weight;
  final int? level;
  final String? href;
  final String structureConfidence;

  const StudyMaterialSegment({
    required this.id,
    required this.title,
    this.type = StudyMaterialSegmentType.custom,
    this.startPage,
    this.endPage,
    this.estimatedMinutes,
    this.weight,
    this.level,
    this.href,
    this.structureConfidence = StudyMaterialStructureConfidence.none,
  });

  int? get pageCount {
    final start = startPage;
    final end = endPage;
    if (start == null || end == null || end < start) return null;
    return end - start + 1;
  }

  factory StudyMaterialSegment.fromJson(Map<String, dynamic> json) {
    return StudyMaterialSegment(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Untitled segment',
      type: StudyMaterialSegmentType.normalize(_readString(json['type'])),
      startPage: _readInt(json['startPage']),
      endPage: _readInt(json['endPage']),
      estimatedMinutes: _readInt(json['estimatedMinutes']),
      weight: _readDouble(json['weight']),
      level: _readInt(json['level']),
      href: _readString(json['href']),
      structureConfidence: StudyMaterialStructureConfidence.normalize(_readString(json['structureConfidence'])),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'type': type,
      'startPage': startPage,
      'endPage': endPage,
      'estimatedMinutes': estimatedMinutes,
      'weight': weight,
      'level': level,
      'href': href,
      'structureConfidence': structureConfidence,
    };
  }
}

class StudyMaterialSource {
  final String type;
  final String title;
  final String? libraryDocumentId;
  final String? filePath;
  final String? url;
  final int? pageCount;
  final int? startPage;
  final int? endPage;
  final String? notes;
  final String structureConfidence;
  final String? structureMessage;
  final String paginationSource;
  final List<StudyMaterialSegment> pageMarkers;
  final List<StudyMaterialSegment> segments;

  const StudyMaterialSource({
    required this.type,
    required this.title,
    this.libraryDocumentId,
    this.filePath,
    this.url,
    this.pageCount,
    this.startPage,
    this.endPage,
    this.notes,
    this.structureConfidence = StudyMaterialStructureConfidence.none,
    this.structureMessage,
    this.paginationSource = StudyMaterialPaginationSource.none,
    this.pageMarkers = const <StudyMaterialSegment>[],
    this.segments = const <StudyMaterialSegment>[],
  });

  bool get hasSource => type != StudyMaterialSourceType.noSourceYet;

  int? get selectedPageCount {
    final start = startPage;
    final end = endPage;
    if (start != null && end != null && end >= start) return end - start + 1;
    return pageCount;
  }

  String get typeLabel => StudyMaterialSourceType.label(type);

  bool get hasRealPageMap => StudyMaterialPaginationSource.isRealPageMap(paginationSource) && pageMarkers.isNotEmpty;

  String get paginationLabel => StudyMaterialPaginationSource.label(paginationSource);

  StudyMaterialSource copyWith({
    String? type,
    String? title,
    String? libraryDocumentId,
    String? filePath,
    String? url,
    int? pageCount,
    int? startPage,
    int? endPage,
    String? notes,
    String? structureConfidence,
    String? structureMessage,
    String? paginationSource,
    List<StudyMaterialSegment>? pageMarkers,
    List<StudyMaterialSegment>? segments,
    bool clearLibraryDocumentId = false,
    bool clearFilePath = false,
    bool clearUrl = false,
    bool clearPageCount = false,
    bool clearStartPage = false,
    bool clearEndPage = false,
    bool clearNotes = false,
    bool clearStructureMessage = false,
  }) {
    return StudyMaterialSource(
      type: type ?? this.type,
      title: title ?? this.title,
      libraryDocumentId: clearLibraryDocumentId ? null : libraryDocumentId ?? this.libraryDocumentId,
      filePath: clearFilePath ? null : filePath ?? this.filePath,
      url: clearUrl ? null : url ?? this.url,
      pageCount: clearPageCount ? null : pageCount ?? this.pageCount,
      startPage: clearStartPage ? null : startPage ?? this.startPage,
      endPage: clearEndPage ? null : endPage ?? this.endPage,
      notes: clearNotes ? null : notes ?? this.notes,
      structureConfidence: StudyMaterialStructureConfidence.normalize(structureConfidence ?? this.structureConfidence),
      structureMessage: clearStructureMessage ? null : structureMessage ?? this.structureMessage,
      paginationSource: StudyMaterialPaginationSource.normalize(paginationSource ?? this.paginationSource),
      pageMarkers: pageMarkers ?? this.pageMarkers,
      segments: segments ?? this.segments,
    );
  }

  factory StudyMaterialSource.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'];
    final rawPageMarkers = json['pageMarkers'];
    final sourceType = StudyMaterialSourceType.normalize(_readString(json['type']));
    return StudyMaterialSource(
      type: sourceType,
      title: _readString(json['title']) ?? StudyMaterialSourceType.label(sourceType),
      libraryDocumentId: _readString(json['libraryDocumentId']),
      filePath: _readString(json['filePath']),
      url: _readString(json['url']),
      pageCount: _readInt(json['pageCount']),
      startPage: _readInt(json['startPage']),
      endPage: _readInt(json['endPage']),
      notes: _readString(json['notes']),
      structureConfidence: StudyMaterialStructureConfidence.normalize(_readString(json['structureConfidence'])),
      structureMessage: _readString(json['structureMessage']),
      paginationSource: StudyMaterialPaginationSource.normalize(_readString(json['paginationSource'])),
      pageMarkers: rawPageMarkers is List
          ? rawPageMarkers
              .whereType<Map>()
              .map((item) => StudyMaterialSegment.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .toList(growable: false)
          : const <StudyMaterialSegment>[],
      segments: rawSegments is List
          ? rawSegments
              .whereType<Map>()
              .map((item) => StudyMaterialSegment.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .toList(growable: false)
          : const <StudyMaterialSegment>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'title': title,
      'libraryDocumentId': libraryDocumentId,
      'filePath': filePath,
      'url': url,
      'pageCount': pageCount,
      'startPage': startPage,
      'endPage': endPage,
      'notes': notes,
      'structureConfidence': structureConfidence,
      'structureMessage': structureMessage,
      'paginationSource': paginationSource,
      'pageMarkers': pageMarkers.map((segment) => segment.toJson()).toList(),
      'segments': segments.map((segment) => segment.toJson()).toList(),
    };
  }
}

String? _readString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _readDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
