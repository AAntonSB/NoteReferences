import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class EpubReaderBook {
  final String title;
  final String? author;
  final List<EpubReaderSpineItem> spine;
  final List<EpubReaderTocEntry> toc;
  final bool contentLoadedLazily;

  const EpubReaderBook({
    required this.title,
    required this.author,
    required this.spine,
    required this.toc,
    this.contentLoadedLazily = false,
  });

  bool get hasReadableContent => spine.isNotEmpty;
}

class EpubReaderSpineItem {
  final int index;
  final String id;
  final String href;
  final String title;
  final List<String> paragraphs;
  final int wordCount;

  const EpubReaderSpineItem({
    required this.index,
    required this.id,
    required this.href,
    required this.title,
    required this.paragraphs,
    required this.wordCount,
  });
}

class EpubReaderTocEntry {
  final String title;
  final String href;
  final int spineIndex;
  final int level;

  const EpubReaderTocEntry({
    required this.title,
    required this.href,
    required this.spineIndex,
    required this.level,
  });
}

class EpubReaderLoadException implements Exception {
  final String message;

  const EpubReaderLoadException(this.message);

  @override
  String toString() => message;
}

class EpubReaderLoader {
  Future<EpubReaderBook> load(File file) async {
    if (!await file.exists()) {
      throw const EpubReaderLoadException('The EPUB file could not be found.');
    }

    final archive = _SimpleZipArchive(await file.readAsBytes());
    final containerXml = _decodeZipText(archive.read('META-INF/container.xml'));
    final packagePath = _packagePathFromContainer(containerXml);
    if (packagePath == null || packagePath.trim().isEmpty) {
      throw const EpubReaderLoadException('This EPUB does not expose a package document.');
    }

    final opf = _decodeZipText(archive.read(packagePath));
    if (opf.trim().isEmpty) {
      throw const EpubReaderLoadException('The EPUB package document could not be read.');
    }

    final manifest = _readManifest(opf, packagePath);
    final spineIdRefs = _readSpineIdRefs(opf);
    final byId = <String, _EpubManifestItem>{for (final item in manifest) item.id: item};
    final spineManifestItems = <_EpubManifestItem>[
      for (final idref in spineIdRefs)
        if (byId[idref] != null && _isReadableHtmlItem(byId[idref]!)) byId[idref]!,
    ];

    if (spineManifestItems.isEmpty) {
      throw const EpubReaderLoadException('No readable spine content was found in this EPUB.');
    }

    final title = _emptyToNull(_firstElementText(opf, 'dc:title') ?? _firstElementText(opf, 'title') ?? '') ??
        p.basenameWithoutExtension(file.path);
    final author = _emptyToNull(_allElementText(opf, 'dc:creator').join('; '));

    final toc = _readToc(archive, manifest, opf, spineManifestItems);
    final tocTitleBySpineIndex = <int, String>{};
    for (final entry in toc) {
      tocTitleBySpineIndex.putIfAbsent(entry.spineIndex, () => entry.title);
    }

    final spine = <EpubReaderSpineItem>[];
    for (var i = 0; i < spineManifestItems.length; i++) {
      final item = spineManifestItems[i];
      final fallbackTitle = tocTitleBySpineIndex[i] ?? _fallbackTitleForHref(item.href, i);
      spine.add(
        EpubReaderSpineItem(
          index: i,
          id: item.id,
          href: item.absoluteHref,
          title: fallbackTitle,
          paragraphs: const <String>[],
          wordCount: 0,
        ),
      );
    }

    return EpubReaderBook(
      title: title,
      author: author,
      spine: spine,
      toc: toc,
      contentLoadedLazily: true,
    );
  }

  Future<EpubReaderSpineItem> loadSpineItem(
    File file,
    EpubReaderBook book,
    int index,
  ) async {
    if (index < 0 || index >= book.spine.length) {
      throw const EpubReaderLoadException('The requested EPUB section is outside the reading order.');
    }
    if (!await file.exists()) {
      throw const EpubReaderLoadException('The EPUB file could not be found.');
    }

    final metadata = book.spine[index];
    final archive = _SimpleZipArchive(await file.readAsBytes());
    final document = _decodeZipText(archive.read(metadata.href));
    final parsedTitle = _titleFromHtml(document);
    final paragraphs = _paragraphsFromHtml(document);
    final wordCount = paragraphs.fold<int>(0, (sum, paragraph) => sum + _wordCount(paragraph));

    return EpubReaderSpineItem(
      index: metadata.index,
      id: metadata.id,
      href: metadata.href,
      title: parsedTitle == null ? metadata.title : (_emptyToNull(parsedTitle) ?? metadata.title),
      paragraphs: paragraphs,
      wordCount: wordCount,
    );
  }

  List<EpubReaderTocEntry> _readToc(
    _SimpleZipArchive archive,
    List<_EpubManifestItem> manifest,
    String opf,
    List<_EpubManifestItem> spineItems,
  ) {
    final nav = _firstManifestItem(
      manifest,
      (item) => item.properties.toLowerCase().split(RegExp(r'\s+')).contains('nav'),
    );
    if (nav != null) {
      final navDocument = _decodeZipText(archive.read(nav.absoluteHref));
      final entries = _tocEntriesFromNav(navDocument, nav.absoluteHref, spineItems);
      if (entries.isNotEmpty) return entries;
    }

    final ncxId = _attribute(RegExp(r'<spine\b([^>]*)>', caseSensitive: false, dotAll: true).firstMatch(opf)?.group(1) ?? '', 'toc');
    final ncx = ncxId == null
        ? _firstManifestItem(manifest, (item) => item.mediaType.toLowerCase() == 'application/x-dtbncx+xml')
        : _firstManifestItem(manifest, (item) => item.id == ncxId);
    if (ncx != null) {
      final ncxDocument = _decodeZipText(archive.read(ncx.absoluteHref));
      return _tocEntriesFromNcx(ncxDocument, ncx.absoluteHref, spineItems);
    }

    return const <EpubReaderTocEntry>[];
  }

  List<EpubReaderTocEntry> _tocEntriesFromNav(
    String navDocument,
    String navPath,
    List<_EpubManifestItem> spineItems,
  ) {
    if (navDocument.trim().isEmpty) return const <EpubReaderTocEntry>[];
    final tocNav = _extractNavByType(navDocument, 'toc') ?? navDocument;
    final anchorPattern = RegExp(r'<a\b([^>]*)>(.*?)</a>', caseSensitive: false, dotAll: true);
    final entries = <EpubReaderTocEntry>[];
    for (final match in anchorPattern.allMatches(tocNav)) {
      final attrs = match.group(1) ?? '';
      final href = _attribute(attrs, 'href');
      if (href == null || href.trim().isEmpty) continue;
      final resolvedHref = _resolveHref(href, navPath);
      final spineIndex = _spineIndexForHref(resolvedHref, spineItems);
      if (spineIndex == null) continue;
      final title = _cleanXmlText(match.group(2) ?? '');
      if (title.isEmpty) continue;
      entries.add(
        EpubReaderTocEntry(
          title: title,
          href: resolvedHref,
          spineIndex: spineIndex,
          level: _approximateListDepth(tocNav, match.start),
        ),
      );
    }
    return _dedupeTocEntries(entries);
  }

  List<EpubReaderTocEntry> _tocEntriesFromNcx(
    String ncxDocument,
    String ncxPath,
    List<_EpubManifestItem> spineItems,
  ) {
    if (ncxDocument.trim().isEmpty) return const <EpubReaderTocEntry>[];
    final navPointPattern = RegExp(r'<navPoint\b([^>]*)>(.*?)</navPoint>', caseSensitive: false, dotAll: true);
    final entries = <EpubReaderTocEntry>[];
    for (final match in navPointPattern.allMatches(ncxDocument)) {
      final body = match.group(2) ?? '';
      final title = _firstElementText(body, 'text');
      if (title == null || title.trim().isEmpty) continue;
      final contentMatch = RegExp(r'<content\b([^>]*)/?>', caseSensitive: false, dotAll: true).firstMatch(body);
      final rawHref = contentMatch == null ? null : _attribute(contentMatch.group(1) ?? '', 'src');
      if (rawHref == null || rawHref.trim().isEmpty) continue;
      final resolvedHref = _resolveHref(rawHref, ncxPath);
      final spineIndex = _spineIndexForHref(resolvedHref, spineItems);
      if (spineIndex == null) continue;
      entries.add(
        EpubReaderTocEntry(
          title: title.trim(),
          href: resolvedHref,
          spineIndex: spineIndex,
          level: _navPointDepth(ncxDocument, match.start),
        ),
      );
    }
    return _dedupeTocEntries(entries);
  }

  List<EpubReaderTocEntry> _dedupeTocEntries(List<EpubReaderTocEntry> entries) {
    final seen = <String>{};
    final result = <EpubReaderTocEntry>[];
    for (final entry in entries) {
      final key = '${entry.title.toLowerCase()}|${entry.href}|${entry.spineIndex}';
      if (seen.add(key)) result.add(entry);
    }
    return result;
  }

  String? _extractNavByType(String document, String typeValue) {
    final navPattern = RegExp(r'<nav\b([^>]*)>(.*?)</nav>', caseSensitive: false, dotAll: true);
    for (final match in navPattern.allMatches(document)) {
      final attrs = match.group(1) ?? '';
      final normalized = attrs.toLowerCase();
      if (normalized.contains(typeValue.toLowerCase())) return match.group(2) ?? '';
    }
    return null;
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

  int? _spineIndexForHref(String href, List<_EpubManifestItem> spineItems) {
    final normalized = _stripFragment(href);
    for (var i = 0; i < spineItems.length; i++) {
      if (_stripFragment(spineItems[i].absoluteHref) == normalized) return i;
    }
    return null;
  }

  String _resolveHref(String href, String baseDocumentPath) {
    final withoutFragment = href.split('#').first;
    final fragment = href.contains('#') ? '#${href.split('#').skip(1).join('#')}' : '';
    final baseDir = p.posix.dirname(baseDocumentPath) == '.' ? '' : p.posix.dirname(baseDocumentPath);
    final joined = baseDir.isEmpty ? withoutFragment : p.posix.join(baseDir, withoutFragment);
    return Uri.decodeFull('${p.posix.normalize(joined)}$fragment');
  }

  String _stripFragment(String href) => Uri.decodeFull(href.split('#').first).replaceAll('\\', '/');

  String? _titleFromHtml(String document) {
    final headingPattern = RegExp(r'<h[1-3]\b[^>]*>(.*?)</h[1-3]>', caseSensitive: false, dotAll: true);
    final heading = headingPattern.firstMatch(document);
    if (heading != null) {
      final title = _cleanXmlText(heading.group(1) ?? '');
      if (title.isNotEmpty) return title;
    }
    final title = _firstElementText(document, 'title');
    if (title != null && title.trim().isNotEmpty) return title.trim();
    return null;
  }

  List<String> _paragraphsFromHtml(String document) {
    if (document.trim().isEmpty) return const <String>[];
    var source = document;
    source = source.replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), ' ');
    source = source.replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', caseSensitive: false, dotAll: true), ' ');
    source = source.replaceAll(RegExp(r'<head\b[^>]*>.*?</head>', caseSensitive: false, dotAll: true), ' ');
    source = source.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    source = source.replaceAll(RegExp(r'</(?:p|div|section|article|blockquote|h[1-6]|li|tr)>', caseSensitive: false), '\n\n');
    source = source.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n• ');
    source = source.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
    source = _decodeXmlEntities(source);
    final paragraphs = source
        .split(RegExp(r'\n\s*\n+'))
        .map((paragraph) => paragraph.replaceAll(RegExp(r'[ \t\x0B\f\r]+'), ' ').trim())
        .where((paragraph) => paragraph.length > 1)
        .toList(growable: false);
    return paragraphs;
  }

  int _wordCount(String value) {
    return RegExp(r"[\p{L}\p{N}']+", unicode: true).allMatches(value).length;
  }

  String _fallbackTitleForHref(String href, int index) {
    final basename = p.basenameWithoutExtension(href);
    final cleaned = basename.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isNotEmpty) return cleaned;
    return 'Section ${index + 1}';
  }

  bool _isReadableHtmlItem(_EpubManifestItem item) {
    final mediaType = item.mediaType.toLowerCase();
    return mediaType.contains('html') || mediaType.contains('xhtml');
  }

  String? _packagePathFromContainer(String containerXml) {
    final rootfileMatch = RegExp(r'<rootfile\b([^>]*)>', caseSensitive: false, dotAll: true).firstMatch(containerXml);
    if (rootfileMatch == null) return null;
    return _attribute(rootfileMatch.group(1) ?? '', 'full-path');
  }

  List<_EpubManifestItem> _readManifest(String opf, String opfPath) {
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

  List<String> _readSpineIdRefs(String opf) {
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

  _EpubManifestItem? _firstManifestItem(
    List<_EpubManifestItem> manifest,
    bool Function(_EpubManifestItem item) test,
  ) {
    for (final item in manifest) {
      if (test(item)) return item;
    }
    return null;
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

  List<String> _allElementText(String source, String tagName) {
    final escaped = RegExp.escape(tagName);
    return RegExp('<$escaped\\b[^>]*>(.*?)</$escaped>', caseSensitive: false, dotAll: true)
        .allMatches(source)
        .map((match) => _cleanXmlText(match.group(1) ?? ''))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
  }

  String _cleanXmlText(String value) {
    final noTags = value.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
    return _decodeXmlEntities(noTags).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decodeXmlEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
          final code = int.tryParse(match.group(1) ?? '');
          if (code == null) return match.group(0) ?? '';
          return String.fromCharCode(code);
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
          final code = int.tryParse(match.group(1) ?? '', radix: 16);
          if (code == null) return match.group(0) ?? '';
          return String.fromCharCode(code);
        });
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
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
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
    if (method == 8) return Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
    return null;
  }

  int _u16(Uint8List source, int offset) {
    if (offset + 2 > source.length) return 0;
    return source[offset] | (source[offset + 1] << 8);
  }

  int _u32(Uint8List source, int offset) {
    if (offset + 4 > source.length) return 0;
    return source[offset] | (source[offset + 1] << 8) | (source[offset + 2] << 16) | (source[offset + 3] << 24);
  }
}
