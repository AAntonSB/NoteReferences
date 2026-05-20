import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../domain/study_material_source.dart';

class StudyMaterialOutlineReadResult {
  final StudyMaterialSource source;
  final String message;
  final bool hasDetectedOutline;

  const StudyMaterialOutlineReadResult({
    required this.source,
    required this.message,
    required this.hasDetectedOutline,
  });
}

class StudyMaterialOutlineReader {
  Future<StudyMaterialOutlineReadResult> read(File file) async {
    final extension = p.extension(file.path).toLowerCase();
    if (extension == '.pdf') {
      return _readPdf(file);
    }
    if (extension == '.epub') {
      return _readEpub(file);
    }
    throw UnsupportedError('Only PDF and EPUB files can be inspected for a planning outline.');
  }

  Future<StudyMaterialOutlineReadResult> _readPdf(File file) async {
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    try {
      final info = document.documentInformation;
      final title = _emptyToNull(info.title) ?? p.basenameWithoutExtension(file.path);
      final pageCount = document.pages.count;
      final bookmarkSegments = <StudyMaterialSegment>[];
      _collectPdfBookmarks(
        document.bookmarks,
        document,
        bookmarkSegments,
        level: 0,
      );
      final bookmarkQuality = _evaluatePdfBookmarkOutline(bookmarkSegments, pageCount);
      final bookmarkOutline = bookmarkQuality.accepted ? bookmarkQuality.segments : const <StudyMaterialSegment>[];

      var segments = bookmarkOutline;
      var confidence = bookmarkOutline.isEmpty
          ? StudyMaterialStructureConfidence.none
          : StudyMaterialStructureConfidence.explicitMetadata;
      var structureMessage = bookmarkSegments.isEmpty
          ? 'No explicit PDF bookmark outline was found.'
          : bookmarkQuality.accepted
              ? 'Explicit PDF bookmark outline found.'
              : bookmarkQuality.message;
      var detectionMessage = bookmarkSegments.isEmpty
          ? 'PDF page count was detected, but the file does not expose a bookmark outline.'
          : bookmarkQuality.accepted
              ? 'Detected ${bookmarkOutline.length} PDF outline entr${bookmarkOutline.length == 1 ? 'y' : 'ies'} from bookmarks.'
              : bookmarkQuality.message;

      if (segments.isEmpty) {
        final toc = _detectVisiblePdfTableOfContents(document, pageCount);
        if (toc.isReliable) {
          segments = toc.segments;
          confidence = StudyMaterialStructureConfidence.parsedToc;
          structureMessage = 'A visible table of contents was parsed with a high-confidence pattern. Review it before relying on it.';
          detectionMessage = 'Detected ${segments.length} outline entr${segments.length == 1 ? 'y' : 'ies'} from a visible table of contents.';
        }
      }

      final source = StudyMaterialSource(
        type: StudyMaterialSourceType.pdfFile,
        title: title,
        filePath: file.path,
        pageCount: pageCount,
        startPage: pageCount > 0 ? 1 : null,
        endPage: pageCount > 0 ? pageCount : null,
        notes: segments.isEmpty
            ? 'PDF inspected · $pageCount pages detected · no reliable outline found'
            : confidence == StudyMaterialStructureConfidence.explicitMetadata
                ? 'PDF inspected · $pageCount pages detected · ${segments.length} bookmark outline entries found'
                : 'PDF inspected · $pageCount pages detected · ${segments.length} table-of-contents entries parsed',
        structureConfidence: confidence,
        structureMessage: structureMessage,
        segments: segments,
      );

      return StudyMaterialOutlineReadResult(
        source: source,
        hasDetectedOutline: segments.isNotEmpty,
        message: detectionMessage,
      );
    } finally {
      document.dispose();
    }
  }

  void _collectPdfBookmarks(
    PdfBookmarkBase bookmarks,
    PdfDocument document,
    List<StudyMaterialSegment> output, {
    required int level,
  }) {
    for (var i = 0; i < bookmarks.count; i++) {
      final bookmark = bookmarks[i];
      final title = bookmark.title.trim();
      if (title.isNotEmpty) {
        output.add(
          StudyMaterialSegment(
            id: 'pdf-outline-${output.length + 1}',
            title: title,
            type: StudyMaterialSegmentType.chapter,
            startPage: _pageNumberForDestination(document, bookmark.destination),
            level: level,
            structureConfidence: StudyMaterialStructureConfidence.explicitMetadata,
          ),
        );
      }
      if (bookmark.count > 0) {
        _collectPdfBookmarks(bookmark, document, output, level: level + 1);
      }
    }
  }

  int? _pageNumberForDestination(PdfDocument document, PdfDestination? destination) {
    final targetPage = destination?.page;
    if (targetPage == null) return null;
    for (var i = 0; i < document.pages.count; i++) {
      final page = document.pages[i];
      if (identical(page, targetPage) || page == targetPage) {
        return i + 1;
      }
    }
    return null;
  }


  _OutlineQuality _evaluatePdfBookmarkOutline(List<StudyMaterialSegment> rawSegments, int pageCount) {
    if (rawSegments.isEmpty) {
      return const _OutlineQuality(
        accepted: false,
        segments: <StudyMaterialSegment>[],
        message: 'No explicit PDF bookmark outline was found.',
      );
    }

    final nonRootSegments = rawSegments.where((segment) => !_isGenericOutlineRoot(segment.title)).toList(growable: false);
    final usefulSegments = nonRootSegments.isEmpty ? rawSegments : nonRootSegments;
    final pageOnlyCount = usefulSegments.where((segment) => _looksLikePageNavigationBookmark(segment.title)).length;
    final richTitleCount = usefulSegments.length - pageOnlyCount;
    final pageOnlyRatio = usefulSegments.isEmpty ? 0.0 : pageOnlyCount / usefulSegments.length;
    final manyEntries = usefulSegments.length >= 20;
    final almostOnlyPageNavigation = pageOnlyRatio >= 0.65 && richTitleCount < 8;
    final noStudyStructure = richTitleCount < 3 && usefulSegments.length > 6;

    if (manyEntries && almostOnlyPageNavigation || noStudyStructure) {
      return _OutlineQuality(
        accepted: false,
        segments: const <StudyMaterialSegment>[],
        message: 'The PDF exposes bookmarks, but they look like page navigation rather than a usable study outline. No chapters were imported from those bookmarks.',
      );
    }

    final cleaned = _dedupeSegments(usefulSegments);
    if (cleaned.isEmpty) {
      return const _OutlineQuality(
        accepted: false,
        segments: <StudyMaterialSegment>[],
        message: 'The PDF bookmark outline did not contain usable study entries.',
      );
    }

    return _OutlineQuality(
      accepted: true,
      segments: cleaned,
      message: 'Explicit PDF bookmark outline found.',
    );
  }

  bool _isGenericOutlineRoot(String title) {
    final lower = title.trim().toLowerCase();
    return lower == 'contents' || lower == 'table of contents' || lower == 'bookmarks' || lower == 'outline';
  }

  bool _looksLikePageNavigationBookmark(String title) {
    final lower = title.trim().toLowerCase().replaceAll(RegExp(r'[\[\]()]'), '').replaceAll(RegExp(r'\s+'), ' ');
    if (lower.isEmpty) return false;
    final patterns = <RegExp>[
      RegExp(r'^p\.?\s*\d{1,5}$'),
      RegExp(r'^pp\.?\s*\d{1,5}(?:\s*[-–]\s*\d{1,5})?$'),
      RegExp(r'^page\s+\d{1,5}$'),
      RegExp(r'^pages\s+\d{1,5}(?:\s*[-–]\s*\d{1,5})?$'),
      RegExp(r'^\d{1,5}$'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(lower));
  }


  _PdfTocDetection _detectVisiblePdfTableOfContents(PdfDocument document, int pageCount) {
    if (pageCount <= 0) return const _PdfTocDetection.empty();
    String text;
    try {
      final extractor = PdfTextExtractor(document);
      text = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: (pageCount - 1).clamp(0, 14).toInt(),
      );
    } catch (_) {
      // Scanned/image-only PDFs usually fail here or return unusable text. We do not OCR or guess.
      return const _PdfTocDetection.empty();
    }

    if (text.trim().isEmpty) return const _PdfTocDetection.empty();
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (!_containsTocHeading(lines)) return const _PdfTocDetection.empty();

    final candidates = <_ParsedTocEntry>[];
    for (final line in lines) {
      final entry = _parseVisibleTocLine(line, pageCount);
      if (entry != null) candidates.add(entry);
    }
    final deduped = _dedupeTocEntries(candidates);
    if (!_tocEntriesAreReliable(deduped, pageCount)) {
      return const _PdfTocDetection.empty();
    }

    final segments = <StudyMaterialSegment>[
      for (var i = 0; i < deduped.length; i++)
        StudyMaterialSegment(
          id: 'pdf-visible-toc-${i + 1}',
          title: deduped[i].title,
          type: StudyMaterialSegmentType.chapter,
          startPage: deduped[i].pageNumber,
          level: deduped[i].level,
          structureConfidence: StudyMaterialStructureConfidence.parsedToc,
        ),
    ];
    return _PdfTocDetection(segments: segments, isReliable: true);
  }

  bool _containsTocHeading(List<String> lines) {
    return lines.take(80).any((line) {
      final lower = line.toLowerCase();
      return lower == 'contents' ||
          lower == 'table of contents' ||
          lower.startsWith('contents ') ||
          lower.startsWith('table of contents ');
    });
  }

  _ParsedTocEntry? _parseVisibleTocLine(String line, int pageCount) {
    if (line.length < 5 || line.length > 180) return null;
    final lower = line.toLowerCase();
    if (lower == 'contents' || lower == 'table of contents' || lower.startsWith('page ')) {
      return null;
    }

    final patterns = <RegExp>[
      RegExp(r'^(.*?)\s*\.{2,}\s*(\d{1,4})$'),
      RegExp(r'^(Chapter\s+[\divxlcdm]+[\.:\-\s]+.*?)\s+(\d{1,4})$', caseSensitive: false),
      RegExp(r'^((?:\d+|[IVXLCDM]+)(?:\.\d+)*[\.)]?\s+.*?)\s{2,}(\d{1,4})$', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final title = _cleanTocTitle(match.group(1) ?? '');
      final pageNumber = int.tryParse(match.group(2) ?? '');
      if (title == null || pageNumber == null) continue;
      if (pageNumber < 1 || pageNumber > pageCount) continue;
      return _ParsedTocEntry(
        title: title,
        pageNumber: pageNumber,
        level: _tocLevelForTitle(title),
      );
    }
    return null;
  }

  String? _cleanTocTitle(String raw) {
    final title = raw
        .replaceAll(RegExp(r'\.{2,}'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.length < 3) return null;
    final lower = title.toLowerCase();
    const blocked = <String>{'contents', 'table of contents', 'page', 'pages'};
    if (blocked.contains(lower)) return null;
    if (RegExp(r'^\d+$').hasMatch(title)) return null;
    return title;
  }

  int _tocLevelForTitle(String title) {
    final trimmed = title.trim();
    if (RegExp(r'^chapter\s+', caseSensitive: false).hasMatch(trimmed)) return 0;
    final numbered = RegExp(r'^(\d+(?:\.\d+)*)').firstMatch(trimmed)?.group(1);
    if (numbered == null) return 0;
    return numbered.split('.').length - 1;
  }

  List<_ParsedTocEntry> _dedupeTocEntries(List<_ParsedTocEntry> entries) {
    final seen = <String>{};
    final result = <_ParsedTocEntry>[];
    for (final entry in entries) {
      final key = '${entry.title.toLowerCase()}|${entry.pageNumber}';
      if (seen.add(key)) result.add(entry);
    }
    return result;
  }

  bool _tocEntriesAreReliable(List<_ParsedTocEntry> entries, int pageCount) {
    if (entries.length < 3) return false;
    final uniquePages = entries.map((entry) => entry.pageNumber).toSet().length;
    if (uniquePages < 3) return false;

    var orderedPairs = 0;
    for (var i = 1; i < entries.length; i++) {
      if (entries[i].pageNumber >= entries[i - 1].pageNumber) orderedPairs++;
    }
    final orderRatio = orderedPairs / (entries.length - 1);
    if (orderRatio < 0.85) return false;

    final structuralTitles = entries.where((entry) {
      final title = entry.title.trim();
      return RegExp(r'^chapter\s+', caseSensitive: false).hasMatch(title) ||
          RegExp(r'^(\d+|[IVXLCDM]+)(?:\.\d+)*[\.)]?\s+', caseSensitive: false).hasMatch(title);
    }).length;
    final structuralRatio = structuralTitles / entries.length;

    // A clean dotted-leader TOC can be useful even without explicit numbering, but we require
    // strong ordering and at least one structural signal to avoid importing random index lines.
    return structuralRatio >= 0.25 || entries.length >= 5;
  }

  Future<StudyMaterialOutlineReadResult> _readEpub(File file) async {
    final archive = _SimpleZipArchive(await file.readAsBytes());
    final container = _decodeZipText(archive.read('META-INF/container.xml'));
    final opfPath = _firstAttribute(container, 'full-path');
    if (opfPath == null) {
      return _epubResultWithoutOutline(file, 'EPUB inspected, but META-INF/container.xml did not expose a package file.');
    }

    final opf = _decodeZipText(archive.read(opfPath));
    if (opf.trim().isEmpty) {
      return _epubResultWithoutOutline(file, 'EPUB inspected, but the package file could not be read.');
    }

    final title = _firstElementText(opf, 'dc:title') ??
        _firstElementText(opf, 'title') ??
        p.basenameWithoutExtension(file.path);
    final manifest = _readEpubManifest(opf, opfPath);
    final nav = manifest.firstWhere(
      (item) => item.properties.toLowerCase().split(RegExp(r'\s+')).contains('nav'),
      orElse: () => const _EpubManifestItem.empty(),
    );
    final ncx = manifest.firstWhere(
      (item) => item.mediaType == 'application/x-dtbncx+xml',
      orElse: () => const _EpubManifestItem.empty(),
    );

    final navDocument = nav.isNotEmpty ? _decodeZipText(archive.read(nav.absoluteHref)) : '';
    final ncxDocument = ncx.isNotEmpty ? _decodeZipText(archive.read(ncx.absoluteHref)) : '';

    List<StudyMaterialSegment> segments = const <StudyMaterialSegment>[];
    if (navDocument.trim().isNotEmpty) {
      segments = _segmentsFromNavDocument(navDocument);
    }
    if (segments.isEmpty && ncxDocument.trim().isNotEmpty) {
      segments = _segmentsFromNcxDocument(ncxDocument);
    }

    var pageMap = const _EpubPageMapDetection.empty();
    if (navDocument.trim().isNotEmpty) {
      pageMap = _pageMarkersFromNavDocument(navDocument);
    }
    if (!pageMap.hasPages && ncxDocument.trim().isNotEmpty) {
      pageMap = _pageMarkersFromNcxDocument(ncxDocument);
    }
    if (!pageMap.hasPages) {
      final spineIdRefs = _readEpubSpineIdRefs(opf);
      pageMap = _pageMarkersFromContentPageBreaks(archive, manifest, spineIdRefs);
    }

    final noteParts = <String>['EPUB inspected'];
    if (segments.isEmpty) {
      noteParts.add('no structured table of contents found');
    } else {
      noteParts.add('${segments.length} table-of-contents entr${segments.length == 1 ? 'y' : 'ies'} found');
    }
    if (pageMap.hasPages) {
      noteParts.add('${pageMap.pageCount} real page-map entr${pageMap.pageCount == 1 ? 'y' : 'ies'} found');
    } else if (pageMap.rejectedMessage != null) {
      noteParts.add(pageMap.rejectedMessage!);
    }

    final source = StudyMaterialSource(
      type: StudyMaterialSourceType.epubFile,
      title: title,
      filePath: file.path,
      pageCount: pageMap.pageCount,
      startPage: pageMap.startPage,
      endPage: pageMap.endPage,
      notes: noteParts.join(' · '),
      structureConfidence: segments.isEmpty
          ? StudyMaterialStructureConfidence.none
          : StudyMaterialStructureConfidence.explicitMetadata,
      structureMessage: segments.isEmpty
          ? 'No structured EPUB table of contents was found.'
          : 'Explicit EPUB table of contents found.',
      paginationSource: pageMap.paginationSource,
      pageMarkers: pageMap.pageMarkers,
      segments: segments,
    );

    final outlineMessage = segments.isEmpty
        ? 'no structured table of contents'
        : '${segments.length} EPUB outline entr${segments.length == 1 ? 'y' : 'ies'}';
    final pageMessage = pageMap.hasPages
        ? ' ${pageMap.pageCount} real EPUB page entr${pageMap.pageCount == 1 ? 'y' : 'ies'} were also found.'
        : '';

    return StudyMaterialOutlineReadResult(
      source: source,
      hasDetectedOutline: segments.isNotEmpty || pageMap.hasPages,
      message: 'EPUB inspected: $outlineMessage.$pageMessage',
    );
  }

  StudyMaterialOutlineReadResult _epubResultWithoutOutline(File file, String message) {
    return StudyMaterialOutlineReadResult(
      source: StudyMaterialSource(
        type: StudyMaterialSourceType.epubFile,
        title: p.basenameWithoutExtension(file.path),
        filePath: file.path,
        notes: message,
        structureConfidence: StudyMaterialStructureConfidence.none,
        structureMessage: 'No structured EPUB table of contents was found.',
      ),
      hasDetectedOutline: false,
      message: message,
    );
  }

  List<_EpubManifestItem> _readEpubManifest(String opf, String opfPath) {
    final basePath = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);
    final itemPattern = RegExp(r'<item\b([^>]*)>', caseSensitive: false, dotAll: true);
    return itemPattern.allMatches(opf).map((match) {
      final attrs = match.group(1) ?? '';
      final id = _attribute(attrs, 'id') ?? '';
      final href = _attribute(attrs, 'href') ?? '';
      final mediaType = _attribute(attrs, 'media-type') ?? '';
      final properties = _attribute(attrs, 'properties') ?? '';
      if (href.isEmpty) return const _EpubManifestItem.empty();
      final absoluteHref = basePath.isEmpty ? href : p.posix.normalize(p.posix.join(basePath, href));
      return _EpubManifestItem(
        id: id,
        href: href,
        absoluteHref: Uri.decodeFull(absoluteHref.split('#').first),
        mediaType: mediaType,
        properties: properties,
      );
    }).where((item) => item.isNotEmpty).toList(growable: false);
  }

  List<StudyMaterialSegment> _segmentsFromNavDocument(String navDocument) {
    if (navDocument.trim().isEmpty) return const <StudyMaterialSegment>[];
    final tocNav = _extractTocNav(navDocument) ?? navDocument;
    final anchorPattern = RegExp(r'<a\b([^>]*)>(.*?)</a>', caseSensitive: false, dotAll: true);
    final segments = <StudyMaterialSegment>[];
    for (final match in anchorPattern.allMatches(tocNav)) {
      final attrs = match.group(1) ?? '';
      final rawTitle = match.group(2) ?? '';
      final title = _cleanXmlText(rawTitle);
      if (title.isEmpty) continue;
      final href = _attribute(attrs, 'href');
      segments.add(
        StudyMaterialSegment(
          id: 'epub-toc-${segments.length + 1}',
          title: title,
          type: StudyMaterialSegmentType.chapter,
          href: href,
          level: _approximateListDepth(tocNav, match.start),
          structureConfidence: StudyMaterialStructureConfidence.explicitMetadata,
        ),
      );
    }
    return _dedupeSegments(segments);
  }

  String? _extractTocNav(String document) {
    return _extractNavByType(document, 'toc') ?? _extractNavByType(document, 'table of contents');
  }

  List<StudyMaterialSegment> _segmentsFromNcxDocument(String ncxDocument) {
    if (ncxDocument.trim().isEmpty) return const <StudyMaterialSegment>[];
    final navPointPattern = RegExp(r'<navPoint\b([^>]*)>(.*?)</navPoint>', caseSensitive: false, dotAll: true);
    final segments = <StudyMaterialSegment>[];
    for (final match in navPointPattern.allMatches(ncxDocument)) {
      final body = match.group(2) ?? '';
      final title = _firstElementText(body, 'text');
      if (title == null || title.trim().isEmpty) continue;
      final contentMatch = RegExp(r'<content\b([^>]*)/?>', caseSensitive: false, dotAll: true).firstMatch(body);
      final href = contentMatch == null ? null : _attribute(contentMatch.group(1) ?? '', 'src');
      segments.add(
        StudyMaterialSegment(
          id: 'epub-ncx-${segments.length + 1}',
          title: title.trim(),
          type: StudyMaterialSegmentType.chapter,
          href: href,
          level: _navPointDepth(ncxDocument, match.start),
          structureConfidence: StudyMaterialStructureConfidence.explicitMetadata,
        ),
      );
    }
    return _dedupeSegments(segments);
  }

  _EpubPageMapDetection _pageMarkersFromNavDocument(String navDocument) {
    if (navDocument.trim().isEmpty) return const _EpubPageMapDetection.empty();
    final pageListNav = _extractNavByType(navDocument, 'page-list');
    if (pageListNav == null || pageListNav.trim().isEmpty) return const _EpubPageMapDetection.empty();
    final anchorPattern = RegExp(r'<a\b([^>]*)>(.*?)</a>', caseSensitive: false, dotAll: true);
    final raw = <_RawEpubPageMarker>[];
    for (final match in anchorPattern.allMatches(pageListNav)) {
      final attrs = match.group(1) ?? '';
      final label = _cleanXmlText(match.group(2) ?? '');
      final href = _attribute(attrs, 'href');
      raw.add(_RawEpubPageMarker(label: label, href: href, sortIndex: raw.length));
    }
    return _normalizeEpubPageMarkers(
      raw,
      paginationSource: StudyMaterialPaginationSource.epubNavPageList,
      rejectedMessage: 'EPUB page-list was found, but it did not expose a usable numeric page map.',
    );
  }

  _EpubPageMapDetection _pageMarkersFromNcxDocument(String ncxDocument) {
    if (ncxDocument.trim().isEmpty) return const _EpubPageMapDetection.empty();
    final pageListMatch = RegExp(r'<pageList\b[^>]*>(.*?)</pageList>', caseSensitive: false, dotAll: true).firstMatch(ncxDocument);
    if (pageListMatch == null) return const _EpubPageMapDetection.empty();
    final pageListBody = pageListMatch.group(1) ?? '';
    final targetPattern = RegExp(r'<pageTarget\b([^>]*)>(.*?)</pageTarget>', caseSensitive: false, dotAll: true);
    final raw = <_RawEpubPageMarker>[];
    for (final match in targetPattern.allMatches(pageListBody)) {
      final attrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      final title = _firstElementText(body, 'text') ?? _attribute(attrs, 'value') ?? _attribute(attrs, 'name') ?? '';
      final contentMatch = RegExp(r'<content\b([^>]*)/?>', caseSensitive: false, dotAll: true).firstMatch(body);
      final href = contentMatch == null ? null : _attribute(contentMatch.group(1) ?? '', 'src');
      raw.add(_RawEpubPageMarker(label: title, href: href, sortIndex: raw.length));
    }
    return _normalizeEpubPageMarkers(
      raw,
      paginationSource: StudyMaterialPaginationSource.epubNcxPageList,
      rejectedMessage: 'NCX pageList was found, but it did not expose a usable numeric page map.',
    );
  }

  _EpubPageMapDetection _pageMarkersFromContentPageBreaks(
    _SimpleZipArchive archive,
    List<_EpubManifestItem> manifest,
    List<String> spineIdRefs,
  ) {
    if (spineIdRefs.isEmpty) return const _EpubPageMapDetection.empty();
    final byId = <String, _EpubManifestItem>{for (final item in manifest) item.id: item};
    final raw = <_RawEpubPageMarker>[];
    for (final idref in spineIdRefs) {
      final item = byId[idref];
      if (item == null) continue;
      final mediaType = item.mediaType.toLowerCase();
      if (!mediaType.contains('html') && !mediaType.contains('xhtml')) continue;
      final document = _decodeZipText(archive.read(item.absoluteHref));
      if (document.trim().isEmpty) continue;
      raw.addAll(_pageBreakMarkersFromContentDocument(document, item.absoluteHref, raw.length));
    }
    return _normalizeEpubPageMarkers(
      raw,
      paginationSource: StudyMaterialPaginationSource.epubPageBreakMarkers,
      rejectedMessage: 'EPUB pagebreak markers were found, but they did not expose a usable numeric page map.',
    );
  }

  List<_RawEpubPageMarker> _pageBreakMarkersFromContentDocument(String document, String href, int baseIndex) {
    final markers = <_RawEpubPageMarker>[];
    final tagPattern = RegExp(r'<([a-zA-Z0-9:_-]+)\b([^>]*)>(.*?)</\1>|<([a-zA-Z0-9:_-]+)\b([^>]*)/?>', caseSensitive: false, dotAll: true);
    for (final match in tagPattern.allMatches(document)) {
      final attrs = (match.group(2) ?? match.group(5) ?? '').trim();
      if (!_looksLikePageBreakAttributes(attrs)) continue;
      final body = match.group(3) ?? '';
      final id = _attribute(attrs, 'id');
      final label = _cleanXmlText(body).isNotEmpty
          ? _cleanXmlText(body)
          : _attribute(attrs, 'title') ?? _attribute(attrs, 'aria-label') ?? id ?? '';
      final targetHref = id == null || id.isEmpty ? href : '$href#$id';
      markers.add(_RawEpubPageMarker(label: label, href: targetHref, sortIndex: baseIndex + markers.length));
    }
    return markers;
  }

  bool _looksLikePageBreakAttributes(String attrs) {
    final lower = attrs.toLowerCase();
    return lower.contains('epub:type="pagebreak"') ||
        lower.contains("epub:type='pagebreak'") ||
        lower.contains('epub:type="page-break"') ||
        lower.contains("epub:type='page-break'") ||
        lower.contains('role="doc-pagebreak"') ||
        lower.contains("role='doc-pagebreak'") ||
        lower.contains('doc-pagebreak') ||
        lower.contains('pagebreak');
  }

  _EpubPageMapDetection _normalizeEpubPageMarkers(
    List<_RawEpubPageMarker> rawMarkers, {
    required String paginationSource,
    required String rejectedMessage,
  }) {
    if (rawMarkers.isEmpty) return const _EpubPageMapDetection.empty();
    final seen = <String>{};
    final numeric = <_NumericEpubPageMarker>[];
    for (final marker in rawMarkers) {
      final page = _numericPageLabel(marker.label);
      if (page == null) continue;
      final key = '${page}|${marker.href ?? ''}';
      if (!seen.add(key)) continue;
      numeric.add(_NumericEpubPageMarker(page: page, href: marker.href, sortIndex: marker.sortIndex));
    }
    if (numeric.length < 2) {
      return _EpubPageMapDetection.rejected(rejectedMessage);
    }
    var orderedPairs = 0;
    for (var i = 1; i < numeric.length; i++) {
      if (numeric[i].page >= numeric[i - 1].page) orderedPairs++;
    }
    final orderRatio = numeric.length <= 1 ? 1.0 : orderedPairs / (numeric.length - 1);
    if (orderRatio < 0.80) {
      return _EpubPageMapDetection.rejected(rejectedMessage);
    }
    final pages = numeric.map((marker) => marker.page).toList(growable: false);
    final startPage = pages.reduce((a, b) => a < b ? a : b);
    final endPage = pages.reduce((a, b) => a > b ? a : b);
    final markers = <StudyMaterialSegment>[
      for (var i = 0; i < numeric.length; i++)
        StudyMaterialSegment(
          id: 'epub-page-marker-${i + 1}',
          title: 'Page ${numeric[i].page}',
          type: StudyMaterialSegmentType.pageMarker,
          startPage: numeric[i].page,
          href: numeric[i].href,
          level: 0,
          structureConfidence: StudyMaterialStructureConfidence.explicitMetadata,
        ),
    ];
    return _EpubPageMapDetection(
      pageMarkers: markers,
      paginationSource: paginationSource,
      startPage: startPage,
      endPage: endPage,
      pageCount: endPage >= startPage ? endPage - startPage + 1 : numeric.length,
    );
  }

  int? _numericPageLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return null;
    final direct = RegExp(r'^\d{1,6}$').firstMatch(trimmed);
    if (direct != null) return int.tryParse(direct.group(0)!);
    final pageLike = RegExp(r'^(?:p\.?|page)\s*(\d{1,6})$', caseSensitive: false).firstMatch(trimmed);
    if (pageLike != null) return int.tryParse(pageLike.group(1)!);
    return null;
  }

  List<String> _readEpubSpineIdRefs(String opf) {
    final spineMatch = RegExp(r'<spine\b[^>]*>(.*?)</spine>', caseSensitive: false, dotAll: true).firstMatch(opf);
    if (spineMatch == null) return const <String>[];
    final body = spineMatch.group(1) ?? '';
    final itemRefPattern = RegExp(r'<itemref\b([^>]*)>', caseSensitive: false, dotAll: true);
    return itemRefPattern
        .allMatches(body)
        .map((match) => _attribute(match.group(1) ?? '', 'idref'))
        .whereType<String>()
        .where((idref) => idref.trim().isNotEmpty)
        .toList(growable: false);
  }

  String? _extractNavByType(String document, String typeValue) {
    final navPattern = RegExp(r'<nav\b([^>]*)>(.*?)</nav>', caseSensitive: false, dotAll: true);
    for (final match in navPattern.allMatches(document)) {
      final attrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      final normalized = attrs.toLowerCase();
      if (normalized.contains(typeValue.toLowerCase())) {
        return body;
      }
    }
    return null;
  }

  List<StudyMaterialSegment> _dedupeSegments(List<StudyMaterialSegment> segments) {
    final seen = <String>{};
    final result = <StudyMaterialSegment>[];
    for (final segment in segments) {
      final key = '${segment.title.toLowerCase()}|${segment.href ?? ''}|${segment.startPage ?? ''}';
      if (seen.add(key)) result.add(segment);
    }
    return result;
  }

  int _approximateListDepth(String source, int offset) {
    final prefix = source.substring(0, offset);
    final openOl = RegExp(r'<ol\b', caseSensitive: false).allMatches(prefix).length;
    final closeOl = RegExp(r'</ol>', caseSensitive: false).allMatches(prefix).length;
    final openUl = RegExp(r'<ul\b', caseSensitive: false).allMatches(prefix).length;
    final closeUl = RegExp(r'</ul>', caseSensitive: false).allMatches(prefix).length;
    return (openOl + openUl - closeOl - closeUl).clamp(0, 6).toInt();
  }

  int _navPointDepth(String source, int offset) {
    final prefix = source.substring(0, offset);
    final opens = RegExp(r'<navPoint\b', caseSensitive: false).allMatches(prefix).length;
    final closes = RegExp(r'</navPoint>', caseSensitive: false).allMatches(prefix).length;
    return (opens - closes).clamp(0, 6).toInt();
  }

  String? _firstAttribute(String source, String name) {
    return _attribute(source, name);
  }

  String? _attribute(String source, String name) {
    final doubleQuoted = RegExp('$name\\s*=\\s*"([^"]*)"', caseSensitive: false).firstMatch(source);
    if (doubleQuoted != null) return _decodeXmlEntities(doubleQuoted.group(1) ?? '').trim();
    final singleQuoted = RegExp("$name\\s*=\\s*'([^']*)'", caseSensitive: false).firstMatch(source);
    if (singleQuoted != null) return _decodeXmlEntities(singleQuoted.group(1) ?? '').trim();
    return null;
  }

  String? _firstElementText(String source, String tagName) {
    final escaped = RegExp.escape(tagName);
    final match = RegExp('<$escaped\\b[^>]*>(.*?)</$escaped>', caseSensitive: false, dotAll: true).firstMatch(source);
    final text = match == null ? null : _cleanXmlText(match.group(1) ?? '');
    if (text == null || text.trim().isEmpty) return null;
    return text.trim();
  }

  String _cleanXmlText(String value) {
    final noTags = value.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
    return _decodeXmlEntities(noTags).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decodeXmlEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  String _decodeZipText(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return '';
    return utf8.decode(bytes, allowMalformed: true);
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}


class _OutlineQuality {
  final bool accepted;
  final List<StudyMaterialSegment> segments;
  final String message;

  const _OutlineQuality({
    required this.accepted,
    required this.segments,
    required this.message,
  });
}

class _PdfTocDetection {
  final List<StudyMaterialSegment> segments;
  final bool isReliable;

  const _PdfTocDetection({required this.segments, required this.isReliable});

  const _PdfTocDetection.empty()
      : segments = const <StudyMaterialSegment>[],
        isReliable = false;
}

class _ParsedTocEntry {
  final String title;
  final int pageNumber;
  final int level;

  const _ParsedTocEntry({
    required this.title,
    required this.pageNumber,
    required this.level,
  });
}


class _RawEpubPageMarker {
  final String label;
  final String? href;
  final int sortIndex;

  const _RawEpubPageMarker({
    required this.label,
    required this.href,
    required this.sortIndex,
  });
}

class _NumericEpubPageMarker {
  final int page;
  final String? href;
  final int sortIndex;

  const _NumericEpubPageMarker({
    required this.page,
    required this.href,
    required this.sortIndex,
  });
}

class _EpubPageMapDetection {
  final List<StudyMaterialSegment> pageMarkers;
  final String paginationSource;
  final int? startPage;
  final int? endPage;
  final int? pageCount;
  final String? rejectedMessage;

  const _EpubPageMapDetection({
    required this.pageMarkers,
    required this.paginationSource,
    required this.startPage,
    required this.endPage,
    required this.pageCount,
    this.rejectedMessage,
  });

  const _EpubPageMapDetection.empty()
      : pageMarkers = const <StudyMaterialSegment>[],
        paginationSource = StudyMaterialPaginationSource.none,
        startPage = null,
        endPage = null,
        pageCount = null,
        rejectedMessage = null;

  const _EpubPageMapDetection.rejected(String message)
      : pageMarkers = const <StudyMaterialSegment>[],
        paginationSource = StudyMaterialPaginationSource.none,
        startPage = null,
        endPage = null,
        pageCount = null,
        rejectedMessage = message;

  bool get hasPages => pageMarkers.isNotEmpty && pageCount != null && startPage != null && endPage != null;
}

class _EpubManifestItem {
  final String id;
  final String href;
  final String absoluteHref;
  final String mediaType;
  final String properties;

  const _EpubManifestItem({
    required this.id,
    required this.href,
    required this.absoluteHref,
    required this.mediaType,
    required this.properties,
  });

  const _EpubManifestItem.empty()
      : id = '',
        href = '',
        absoluteHref = '',
        mediaType = '',
        properties = '';

  bool get isNotEmpty => href.isNotEmpty;
}

class _SimpleZipArchive {
  final Uint8List bytes;
  late final Map<String, _SimpleZipEntry> _entries = _readEntries();

  _SimpleZipArchive(this.bytes);

  Uint8List? read(String path) {
    final normalized = path.replaceAll('\\', '/');
    final entry = _entries[normalized];
    if (entry == null) return null;
    return entry.read(bytes);
  }

  Map<String, _SimpleZipEntry> _readEntries() {
    final end = _findEndOfCentralDirectory();
    if (end == null) return const <String, _SimpleZipEntry>{};
    final directoryOffset = _u32(end + 16);
    final totalEntries = _u16(end + 10);
    final entries = <String, _SimpleZipEntry>{};
    var offset = directoryOffset;
    for (var i = 0; i < totalEntries; i++) {
      if (offset + 46 > bytes.length || _u32(offset) != 0x02014b50) break;
      final method = _u16(offset + 10);
      final compressedSize = _u32(offset + 20);
      final uncompressedSize = _u32(offset + 24);
      final fileNameLength = _u16(offset + 28);
      final extraLength = _u16(offset + 30);
      final commentLength = _u16(offset + 32);
      final localHeaderOffset = _u32(offset + 42);
      final nameStart = offset + 46;
      final nameEnd = nameStart + fileNameLength;
      if (nameEnd > bytes.length) break;
      final name = utf8.decode(bytes.sublist(nameStart, nameEnd), allowMalformed: true).replaceAll('\\', '/');
      entries[name] = _SimpleZipEntry(
        name: name,
        method: method,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localHeaderOffset,
      );
      offset = nameEnd + extraLength + commentLength;
    }
    return entries;
  }

  int? _findEndOfCentralDirectory() {
    final minOffset = (bytes.length - 65557).clamp(0, bytes.length).toInt();
    for (var offset = bytes.length - 22; offset >= minOffset; offset--) {
      if (_u32(offset) == 0x06054b50) return offset;
    }
    return null;
  }

  int _u16(int offset) {
    if (offset + 2 > bytes.length) return 0;
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int _u32(int offset) {
    if (offset + 4 > bytes.length) return 0;
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}

class _SimpleZipEntry {
  final String name;
  final int method;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  const _SimpleZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  Uint8List? read(Uint8List archiveBytes) {
    if (localHeaderOffset + 30 > archiveBytes.length) return null;
    final signature = _u32(archiveBytes, localHeaderOffset);
    if (signature != 0x04034b50) return null;
    final nameLength = _u16(archiveBytes, localHeaderOffset + 26);
    final extraLength = _u16(archiveBytes, localHeaderOffset + 28);
    final dataStart = localHeaderOffset + 30 + nameLength + extraLength;
    final dataEnd = dataStart + compressedSize;
    if (dataStart < 0 || dataEnd > archiveBytes.length || dataStart > dataEnd) return null;
    final data = archiveBytes.sublist(dataStart, dataEnd);
    if (method == 0) return Uint8List.fromList(data);
    if (method == 8) {
      return Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
    }
    return null;
  }

  int _u16(Uint8List source, int offset) {
    if (offset + 2 > source.length) return 0;
    return source[offset] | (source[offset + 1] << 8);
  }

  int _u32(Uint8List source, int offset) {
    if (offset + 4 > source.length) return 0;
    return source[offset] |
        (source[offset + 1] << 8) |
        (source[offset + 2] << 16) |
        (source[offset + 3] << 24);
  }
}
