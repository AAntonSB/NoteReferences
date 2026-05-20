import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class ExtractedEpubMetadata {
  final String? title;
  final String? authors;
  final String? language;
  final String? publisher;
  final String? identifier;
  final String? description;
  final int spineItemCount;
  final int tocEntryCount;
  final bool hasPageMap;
  final String? packagePath;

  const ExtractedEpubMetadata({
    required this.title,
    required this.authors,
    required this.language,
    required this.publisher,
    required this.identifier,
    required this.description,
    required this.spineItemCount,
    required this.tocEntryCount,
    required this.hasPageMap,
    required this.packagePath,
  });

  const ExtractedEpubMetadata.empty()
      : title = null,
        authors = null,
        language = null,
        publisher = null,
        identifier = null,
        description = null,
        spineItemCount = 0,
        tocEntryCount = 0,
        hasPageMap = false,
        packagePath = null;
}

class EpubMetadataExtractor {
  Future<ExtractedEpubMetadata> extract(File file) async {
    final bytes = await file.readAsBytes();
    final archive = _SimpleZipArchive(bytes);
    final containerXml = _decodeZipText(archive.read('META-INF/container.xml'));
    final packagePath = _packagePathFromContainer(containerXml);
    if (packagePath == null || packagePath.isEmpty) {
      return const ExtractedEpubMetadata.empty();
    }

    final opf = _decodeZipText(archive.read(packagePath));
    if (opf.trim().isEmpty) {
      return ExtractedEpubMetadata(
        title: null,
        authors: null,
        language: null,
        publisher: null,
        identifier: null,
        description: null,
        spineItemCount: 0,
        tocEntryCount: 0,
        hasPageMap: false,
        packagePath: packagePath,
      );
    }

    final metadata = _metadataBlock(opf) ?? opf;
    final manifest = _readManifest(opf, packagePath);
    final spineIds = _readSpineIdRefs(opf);
    final navItem = _firstManifestItem(
      manifest,
      (item) => item.properties.toLowerCase().contains('nav'),
    );
    final ncxId = _attribute(RegExp(r'<spine\b([^>]*)>', caseSensitive: false, dotAll: true).firstMatch(opf)?.group(1) ?? '', 'toc');
    final ncxItem = ncxId == null
        ? null
        : _firstManifestItem(manifest, (item) => item.id == ncxId);

    final navDocument = navItem == null ? '' : _decodeZipText(archive.read(navItem.absoluteHref));
    final ncxDocument = ncxItem == null ? '' : _decodeZipText(archive.read(ncxItem.absoluteHref));
    final tocCount = _countTocEntries(navDocument, ncxDocument);
    final hasPageMap = _hasPageMap(navDocument, ncxDocument, archive, manifest, spineIds);

    return ExtractedEpubMetadata(
      title: _emptyToNull(_firstElementText(metadata, 'dc:title') ?? _firstElementText(metadata, 'title') ?? ''),
      authors: _emptyToNull(_allElementText(metadata, 'dc:creator').join('; ')),
      language: _emptyToNull(_firstElementText(metadata, 'dc:language') ?? _firstElementText(metadata, 'language') ?? ''),
      publisher: _emptyToNull(_firstElementText(metadata, 'dc:publisher') ?? _firstElementText(metadata, 'publisher') ?? ''),
      identifier: _emptyToNull(_firstElementText(metadata, 'dc:identifier') ?? _firstElementText(metadata, 'identifier') ?? ''),
      description: _emptyToNull(_firstElementText(metadata, 'dc:description') ?? _firstElementText(metadata, 'description') ?? ''),
      spineItemCount: spineIds.length,
      tocEntryCount: tocCount,
      hasPageMap: hasPageMap,
      packagePath: packagePath,
    );
  }

  String? _packagePathFromContainer(String containerXml) {
    final rootfileMatch = RegExp(r'<rootfile\b([^>]*)>', caseSensitive: false, dotAll: true).firstMatch(containerXml);
    if (rootfileMatch == null) return null;
    return _attribute(rootfileMatch.group(1) ?? '', 'full-path');
  }

  String? _metadataBlock(String opf) {
    return RegExp(r'<metadata\b[^>]*>(.*?)</metadata>', caseSensitive: false, dotAll: true).firstMatch(opf)?.group(1);
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

  int _countTocEntries(String navDocument, String ncxDocument) {
    if (navDocument.trim().isNotEmpty) {
      final tocNav = _extractNavByType(navDocument, 'toc') ?? _extractNavByType(navDocument, 'table of contents');
      final source = tocNav ?? navDocument;
      final count = RegExp(r'<a\b', caseSensitive: false).allMatches(source).length;
      if (count > 0) return count;
    }
    if (ncxDocument.trim().isNotEmpty) {
      return RegExp(r'<navPoint\b', caseSensitive: false).allMatches(ncxDocument).length;
    }
    return 0;
  }

  bool _hasPageMap(
    String navDocument,
    String ncxDocument,
    _SimpleZipArchive archive,
    List<_EpubManifestItem> manifest,
    List<String> spineIds,
  ) {
    final pageList = _extractNavByType(navDocument, 'page-list');
    if (pageList != null && RegExp(r'<a\b', caseSensitive: false).hasMatch(pageList)) return true;
    if (RegExp(r'<pageList\b', caseSensitive: false).hasMatch(ncxDocument)) return true;

    final byId = <String, _EpubManifestItem>{for (final item in manifest) item.id: item};
    for (final idref in spineIds.take(12)) {
      final item = byId[idref];
      if (item == null) continue;
      final mediaType = item.mediaType.toLowerCase();
      if (!mediaType.contains('html') && !mediaType.contains('xhtml')) continue;
      final document = _decodeZipText(archive.read(item.absoluteHref));
      if (document.contains('epub:type="pagebreak"') ||
          document.contains("epub:type='pagebreak'") ||
          document.contains('role="doc-pagebreak"') ||
          document.contains("role='doc-pagebreak'")) {
        return true;
      }
    }
    return false;
  }

  String? _extractNavByType(String document, String typeValue) {
    final navPattern = RegExp(r'<nav\b([^>]*)>(.*?)</nav>', caseSensitive: false, dotAll: true);
    for (final match in navPattern.allMatches(document)) {
      final attrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      if (attrs.toLowerCase().contains(typeValue.toLowerCase())) return body;
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
