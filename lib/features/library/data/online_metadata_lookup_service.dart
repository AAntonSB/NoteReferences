import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../infrastructure/database/app_database.dart';

class OnlineMetadataCandidate {
  final String source;
  final String sourceId;
  final String? title;
  final String? authors;
  final String? abstractText;
  final String? doi;
  final String? journal;
  final String? publisher;
  final String? fieldOfStudy;
  final String? keywords;
  final String? issn;
  final String? sourceUrl;
  final double confidence;
  final String reason;

  const OnlineMetadataCandidate({
    required this.source,
    required this.sourceId,
    required this.confidence,
    required this.reason,
    this.title,
    this.authors,
    this.abstractText,
    this.doi,
    this.journal,
    this.publisher,
    this.fieldOfStudy,
    this.keywords,
    this.issn,
    this.sourceUrl,
  });

  bool get hasUsefulMetadata {
    return [
      title,
      authors,
      abstractText,
      doi,
      journal,
      publisher,
      fieldOfStudy,
      keywords,
      issn,
    ].any((value) => value != null && value!.trim().isNotEmpty);
  }

  String get confidenceLabel => '${(confidence * 100).round()}%';
}

class OnlineMetadataLookupService {
  static const Duration _timeout = Duration(seconds: 14);

  Future<List<OnlineMetadataCandidate>> lookup(
    PdfDocument document, {
    String? queryOverride,
  }) async {
    final query = _buildQuery(document, queryOverride: queryOverride);
    final doi =
        _normalizeDoi(document.doi) ??
        _extractDoi(document.name) ??
        _extractDoi(document.subject) ??
        _extractDoi(document.keywords);

    final candidates = <OnlineMetadataCandidate>[];

    if (doi != null) {
      final crossrefByDoi = await _safeLookup(() => _lookupCrossrefByDoi(doi));
      if (crossrefByDoi != null) candidates.add(crossrefByDoi);
    }

    if (query.trim().isNotEmpty) {
      final results = await Future.wait<List<OnlineMetadataCandidate>>([
        _safeLookupList(() => _searchCrossref(query)),
        _safeLookupList(() => _searchOpenAlex(query)),
      ]);

      for (final result in results) {
        candidates.addAll(result);
      }
    }

    return _deduplicateAndRank(candidates);
  }

  String _buildQuery(PdfDocument document, {String? queryOverride}) {
    final override = queryOverride?.trim();
    if (override != null && override.isNotEmpty) return override;

    return [
      document.doi,
      document.name,
      document.authors,
      document.journal,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
  }

  Future<T?> _safeLookup<T>(Future<T?> Function() lookup) async {
    try {
      return await lookup();
    } catch (_) {
      return null;
    }
  }

  Future<List<T>> _safeLookupList<T>(Future<List<T>> Function() lookup) async {
    try {
      return await lookup();
    } catch (_) {
      return const [];
    }
  }

  Future<OnlineMetadataCandidate?> _lookupCrossrefByDoi(String doi) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.crossref.org',
      pathSegments: ['works', doi],
    );

    final json = await _getJson(uri);
    final message = _asMap(json['message']);
    if (message == null) return null;

    return _candidateFromCrossrefItem(
      message,
      confidence: 0.98,
      reason: 'DOI match',
    );
  }

  Future<List<OnlineMetadataCandidate>> _searchCrossref(String query) async {
    final uri = Uri.https('api.crossref.org', '/works', {
      'query.bibliographic': query,
      'rows': '5',
      'select': [
        'DOI',
        'URL',
        'title',
        'author',
        'abstract',
        'container-title',
        'publisher',
        'subject',
        'ISSN',
        'score',
        'type',
      ].join(','),
    });

    final json = await _getJson(uri);
    final message = _asMap(json['message']);
    final items = _asList(message?['items']);
    if (items == null) return const [];

    return [
      for (final item in items)
        if (_asMap(item) != null)
          _candidateFromCrossrefItem(
            _asMap(item)!,
            confidence: _confidenceFromCrossrefScore(_asMap(item)!['score']),
            reason: 'Crossref bibliographic match',
          ),
    ].where((candidate) => candidate.hasUsefulMetadata).toList();
  }

  Future<List<OnlineMetadataCandidate>> _searchOpenAlex(String query) async {
    final uri = Uri.https('api.openalex.org', '/works', {
      'search': query,
      'per-page': '5',
    });

    final json = await _getJson(uri);
    final results = _asList(json['results']);
    if (results == null) return const [];

    return [
      for (final result in results)
        if (_asMap(result) != null) _candidateFromOpenAlexWork(_asMap(result)!),
    ].where((candidate) => candidate.hasUsefulMetadata).toList();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _timeout;

    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'NoteReferences/1.0 metadata lookup (desktop Flutter app)',
      );

      final response = await request.close().timeout(_timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Metadata lookup failed (${response.statusCode})',
          uri: uri,
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object response.');
      }

      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  OnlineMetadataCandidate _candidateFromCrossrefItem(
    Map<String, dynamic> item, {
    required double confidence,
    required String reason,
  }) {
    final doi = _normalizeDoi(_stringValue(item['DOI']));
    final title = _firstString(item['title']);
    final journal = _firstString(item['container-title']);
    final subjects = _stringList(item['subject']);
    final issns = _stringList(item['ISSN']);

    return OnlineMetadataCandidate(
      source: 'Crossref',
      sourceId: doi ?? _stringValue(item['URL']) ?? title ?? 'crossref',
      confidence: confidence,
      reason: reason,
      title: title,
      authors: _crossrefAuthors(item['author']),
      abstractText: _cleanAbstract(_stringValue(item['abstract'])),
      doi: doi,
      journal: journal,
      publisher: _stringValue(item['publisher']),
      keywords: subjects.isEmpty ? null : subjects.join(', '),
      issn: issns.isEmpty ? null : issns.join(', '),
      sourceUrl:
          _stringValue(item['URL']) ??
          (doi == null ? null : 'https://doi.org/$doi'),
    );
  }

  OnlineMetadataCandidate _candidateFromOpenAlexWork(
    Map<String, dynamic> work,
  ) {
    final source = _asMap(_asMap(work['primary_location'])?['source']);
    final primaryTopic = _asMap(work['primary_topic']);
    final topicField = _asMap(primaryTopic?['field']);
    final topics = _asList(work['topics']);

    final topicNames = <String>[
      for (final topic in topics ?? const [])
        if (_stringValue(_asMap(topic)?['display_name']) != null)
          _stringValue(_asMap(topic)?['display_name'])!,
    ];

    final concepts = _asList(work['concepts']);
    final conceptNames = <String>[
      for (final concept in concepts ?? const [])
        if (_stringValue(_asMap(concept)?['display_name']) != null)
          _stringValue(_asMap(concept)?['display_name'])!,
    ];

    final doi = _normalizeDoi(_stringValue(work['doi']));
    final relevanceScore = _numberValue(work['relevance_score']);

    return OnlineMetadataCandidate(
      source: 'OpenAlex',
      sourceId:
          _stringValue(work['id']) ??
          doi ??
          _stringValue(work['display_name']) ??
          'openalex',
      confidence: relevanceScore == null
          ? 0.66
          : (0.62 + (relevanceScore / 100).clamp(0.0, 0.25)).toDouble(),
      reason: doi == null ? 'OpenAlex search match' : 'OpenAlex work match',
      title: _stringValue(work['display_name']),
      authors: _openAlexAuthors(work['authorships']),
      abstractText: _openAlexAbstract(work['abstract_inverted_index']),
      doi: doi,
      journal: _stringValue(source?['display_name']),
      publisher: _stringValue(source?['publisher']),
      fieldOfStudy:
          _stringValue(topicField?['display_name']) ??
          (conceptNames.isEmpty ? null : conceptNames.first),
      keywords: topicNames.isNotEmpty
          ? topicNames.take(8).join(', ')
          : (conceptNames.isEmpty ? null : conceptNames.take(8).join(', ')),
      issn: _openAlexIssn(source),
      sourceUrl:
          _stringValue(work['id']) ??
          (doi == null ? null : 'https://doi.org/$doi'),
    );
  }

  List<OnlineMetadataCandidate> _deduplicateAndRank(
    List<OnlineMetadataCandidate> candidates,
  ) {
    final byKey = <String, OnlineMetadataCandidate>{};

    for (final candidate in candidates) {
      final doi = _normalizeDoi(candidate.doi);
      final title = candidate.title?.trim().toLowerCase();
      final key = doi ?? title ?? candidate.sourceId;
      final existing = byKey[key];

      if (existing == null || candidate.confidence > existing.confidence) {
        byKey[key] = candidate;
      }
    }

    final ranked = byKey.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    return ranked.take(8).toList(growable: false);
  }

  double _confidenceFromCrossrefScore(Object? value) {
    final score = _numberValue(value);
    if (score == null) return 0.72;
    return (0.55 + (score / 100).clamp(0.0, 0.38)).clamp(0.0, 0.93).toDouble();
  }

  String? _crossrefAuthors(Object? value) {
    final authors = _asList(value);
    if (authors == null) return null;

    final names = <String>[];
    for (final author in authors) {
      final map = _asMap(author);
      if (map == null) continue;

      final given = _stringValue(map['given']);
      final family = _stringValue(map['family']);
      final literal = _stringValue(map['name']);
      final name = [given, family]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(' ')
          .trim();

      if (name.isNotEmpty) {
        names.add(name);
      } else if (literal != null && literal.trim().isNotEmpty) {
        names.add(literal.trim());
      }
    }

    return names.isEmpty ? null : names.join('; ');
  }

  String? _openAlexAuthors(Object? value) {
    final authorships = _asList(value);
    if (authorships == null) return null;

    final names = <String>[];
    for (final authorship in authorships) {
      final author = _asMap(_asMap(authorship)?['author']);
      final name = _stringValue(author?['display_name']);
      if (name != null && name.trim().isNotEmpty) {
        names.add(name.trim());
      }
    }

    return names.isEmpty ? null : names.join('; ');
  }

  String? _openAlexIssn(Map<String, dynamic>? source) {
    final issn = _stringValue(source?['issn_l']);
    if (issn != null) return issn;

    final issns = _stringList(source?['issn']);
    return issns.isEmpty ? null : issns.join(', ');
  }

  String? _openAlexAbstract(Object? invertedIndexValue) {
    final invertedIndex = _asMap(invertedIndexValue);
    if (invertedIndex == null || invertedIndex.isEmpty) return null;

    final positionedWords = <MapEntry<int, String>>[];

    for (final entry in invertedIndex.entries) {
      final word = entry.key;
      final positions = _asList(entry.value);
      if (positions == null) continue;

      for (final position in positions) {
        final index = position is int ? position : int.tryParse('$position');
        if (index != null) positionedWords.add(MapEntry(index, word));
      }
    }

    if (positionedWords.isEmpty) return null;

    positionedWords.sort((a, b) => a.key.compareTo(b.key));
    return positionedWords.map((entry) => entry.value).join(' ');
  }

  String? _cleanAbstract(String? value) {
    if (value == null) return null;

    final stripped = value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return stripped.isEmpty ? null : stripped;
  }

  String? _normalizeDoi(String? value) {
    if (value == null) return null;

    final match = RegExp(
      r'(10\.\d{4,9}/[-._;()/:A-Z0-9]+)',
      caseSensitive: false,
    ).firstMatch(value.trim());

    return match?.group(1)?.trim().toLowerCase();
  }

  String? _extractDoi(String? value) => _normalizeDoi(value);

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  List<Object?>? _asList(Object? value) {
    if (value is List) return value.cast<Object?>();
    return null;
  }

  String? _stringValue(Object? value) {
    if (value == null) return null;
    final string = '$value'.trim();
    return string.isEmpty ? null : string;
  }

  num? _numberValue(Object? value) {
    if (value is num) return value;
    if (value == null) return null;
    return num.tryParse('$value');
  }

  List<String> _stringList(Object? value) {
    final list = _asList(value);
    if (list == null) return const [];

    return [
      for (final item in list)
        if (_stringValue(item) != null) _stringValue(item)!,
    ];
  }

  String? _firstString(Object? value) {
    final list = _stringList(value);
    if (list.isNotEmpty) return list.first;
    return _stringValue(value);
  }
}
