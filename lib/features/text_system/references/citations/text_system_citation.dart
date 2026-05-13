import 'dart:convert';

import '../../core/text_mark.dart';
import '../../core/text_system_block.dart';
import '../../core/text_system_document.dart';
import '../../core/text_system_range.dart';
import '../actions/text_system_reference_action_models.dart';

/// Phase 15J-B citation layer.
///
/// The reference-action layer creates generic inline reference marks. This file
/// adds the academic citation semantics that sit above that generic bridge:
/// document-level citation settings, source metadata, in-text citation rendering,
/// and generated bibliography-page blocks.
enum TextSystemCitationStyle {
  apa7,
  harvard,
  chicagoAuthorDate,
  mla9,
  ieee,
}

extension TextSystemCitationStyleX on TextSystemCitationStyle {
  String get id {
    return switch (this) {
      TextSystemCitationStyle.apa7 => 'apa-7',
      TextSystemCitationStyle.harvard => 'harvard',
      TextSystemCitationStyle.chicagoAuthorDate => 'chicago-author-date',
      TextSystemCitationStyle.mla9 => 'mla-9',
      TextSystemCitationStyle.ieee => 'ieee',
    };
  }

  String get label {
    return switch (this) {
      TextSystemCitationStyle.apa7 => 'APA 7',
      TextSystemCitationStyle.harvard => 'Harvard',
      TextSystemCitationStyle.chicagoAuthorDate => 'Chicago author-date',
      TextSystemCitationStyle.mla9 => 'MLA 9',
      TextSystemCitationStyle.ieee => 'IEEE',
    };
  }

  String get bibliographyTitle {
    return switch (this) {
      TextSystemCitationStyle.mla9 => 'Works Cited',
      _ => 'References',
    };
  }

  bool get usesNumericInlineCitation => this == TextSystemCitationStyle.ieee;

  static TextSystemCitationStyle fromId(String? id) {
    return switch (id) {
      'apa-7' || 'apa7' || 'apa' => TextSystemCitationStyle.apa7,
      'harvard' => TextSystemCitationStyle.harvard,
      'chicago-author-date' || 'chicago' => TextSystemCitationStyle.chicagoAuthorDate,
      'mla-9' || 'mla9' || 'mla' => TextSystemCitationStyle.mla9,
      'ieee' => TextSystemCitationStyle.ieee,
      _ => TextSystemCitationStyle.apa7,
    };
  }
}

enum TextSystemCitationInlineMode {
  parenthetical,
  narrative,
}

extension TextSystemCitationInlineModeX on TextSystemCitationInlineMode {
  String get id {
    return switch (this) {
      TextSystemCitationInlineMode.parenthetical => 'parenthetical',
      TextSystemCitationInlineMode.narrative => 'narrative',
    };
  }

  String get label {
    return switch (this) {
      TextSystemCitationInlineMode.parenthetical => 'Parenthetical',
      TextSystemCitationInlineMode.narrative => 'Narrative',
    };
  }

  static TextSystemCitationInlineMode fromId(String? id) {
    return switch (id) {
      'narrative' => TextSystemCitationInlineMode.narrative,
      _ => TextSystemCitationInlineMode.parenthetical,
    };
  }
}

class TextSystemCitationSettings {
  const TextSystemCitationSettings({
    this.style = TextSystemCitationStyle.apa7,
    this.inlineMode = TextSystemCitationInlineMode.parenthetical,
    this.bibliographyPlacement = 'generatedFinalPage',
  });

  factory TextSystemCitationSettings.fromDocument(TextSystemDocument document) {
    final raw = document.metadata[metadataKey];
    if (raw is Map<String, Object?>) return TextSystemCitationSettings.fromJson(raw);
    if (raw is Map) {
      return TextSystemCitationSettings.fromJson(
        raw.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?)),
      );
    }
    return const TextSystemCitationSettings();
  }

  factory TextSystemCitationSettings.fromJson(Map<String, Object?> json) {
    return TextSystemCitationSettings(
      style: TextSystemCitationStyleX.fromId(json['style'] as String?),
      inlineMode: TextSystemCitationInlineModeX.fromId(json['inlineMode'] as String?),
      bibliographyPlacement: json['bibliographyPlacement'] as String? ?? 'generatedFinalPage',
    );
  }

  static const String metadataKey = 'citationSettings';

  final TextSystemCitationStyle style;
  final TextSystemCitationInlineMode inlineMode;
  final String bibliographyPlacement;

  TextSystemCitationSettings copyWith({
    TextSystemCitationStyle? style,
    TextSystemCitationInlineMode? inlineMode,
    String? bibliographyPlacement,
  }) {
    return TextSystemCitationSettings(
      style: style ?? this.style,
      inlineMode: inlineMode ?? this.inlineMode,
      bibliographyPlacement: bibliographyPlacement ?? this.bibliographyPlacement,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'style': style.id,
      'inlineMode': inlineMode.id,
      'bibliographyPlacement': bibliographyPlacement,
    };
  }

  TextSystemDocument applyToDocument(TextSystemDocument document) {
    return document.copyWith(
      metadata: <String, Object?>{
        ...document.metadata,
        metadataKey: toJson(),
      },
      updatedAt: DateTime.now(),
    );
  }
}

class TextSystemCitationSource {
  const TextSystemCitationSource({
    required this.id,
    required this.title,
    this.authors = const <String>[],
    this.year,
    this.containerTitle,
    this.publisher,
    this.doi,
    this.url,
    this.locator,
    this.citationKey,
    this.kind,
  });

  factory TextSystemCitationSource.fromReferenceTarget(TextSystemReferenceTarget target) {
    final metadata = target.metadata;
    final parsed = _parseAcademicLabel(target.title);
    final sourceKind = _stringValue(metadata['sourceKind']);
    final isPdfBacked = _isPdfBackedSourceKind(sourceKind) || _stringValue(metadata['pdfDocumentId']) != null;
    final sourceTitle = _stringValue(metadata['sourceTitle']);
    final metadataTitle = _stringValue(metadata['title']);
    return TextSystemCitationSource(
      id: target.id,
      title: (isPdfBacked ? sourceTitle : null) ?? metadataTitle ?? parsed.title ?? target.title,
      authors: _authorsValue(metadata['authors']) ?? parsed.authors,
      year: _stringValue(metadata['year']) ?? parsed.year,
      containerTitle: _stringValue(metadata['containerTitle']) ?? (isPdfBacked ? null : target.subtitle),
      publisher: _stringValue(metadata['publisher']),
      doi: _stringValue(metadata['doi']),
      url: _stringValue(metadata['url']) ?? _externalUriString(target.uri),
      locator: _stringValue(metadata['locator']),
      citationKey: target.citationKey,
      kind: sourceKind,
    );
  }

  factory TextSystemCitationSource.fromInlineMark(TextSystemInlineReferenceMark mark) {
    final metadata = mark.metadata;
    final parsed = _parseAcademicLabel(mark.label);
    final sourceKind = _stringValue(metadata['sourceKind']);
    final isPdfBacked = _isPdfBackedSourceKind(sourceKind) || _stringValue(metadata['pdfDocumentId']) != null;
    final sourceTitle = _stringValue(metadata['sourceTitle']);
    final metadataTitle = _stringValue(metadata['title']);
    return TextSystemCitationSource(
      id: mark.targetId,
      title: (isPdfBacked ? sourceTitle : null) ?? metadataTitle ?? parsed.title ?? mark.label,
      authors: _authorsValue(metadata['authors']) ?? parsed.authors,
      year: _stringValue(metadata['year']) ?? parsed.year,
      containerTitle: _stringValue(metadata['containerTitle']),
      publisher: _stringValue(metadata['publisher']),
      doi: _stringValue(metadata['doi']),
      url: _stringValue(metadata['url']) ?? _externalUriString(mark.uri),
      locator: _stringValue(metadata['locator']),
      citationKey: mark.citationKey,
      kind: sourceKind,
    );
  }

  final String id;
  final String title;
  final List<String> authors;
  final String? year;
  final String? containerTitle;
  final String? publisher;
  final String? doi;
  final String? url;
  final String? locator;
  final String? citationKey;
  final String? kind;

  String get authorLabel {
    if (authors.isEmpty) return title.trim().isEmpty ? 'Unknown author' : title.trim();
    if (authors.length == 1) return _familyName(authors.single);
    if (authors.length == 2) return '${_familyName(authors[0])} & ${_familyName(authors[1])}';
    return '${_familyName(authors.first)} et al.';
  }

  String get authorBibliographyLabel {
    if (authors.isEmpty) return 'Unknown author';
    return authors.join(', ');
  }

  Map<String, Object?> toMetadata() {
    return <String, Object?>{
      if (title.trim().isNotEmpty) 'title': title.trim(),
      if (authors.isNotEmpty) 'authors': authors,
      if (year != null && year!.trim().isNotEmpty) 'year': year!.trim(),
      if (containerTitle != null && containerTitle!.trim().isNotEmpty) 'containerTitle': containerTitle!.trim(),
      if (publisher != null && publisher!.trim().isNotEmpty) 'publisher': publisher!.trim(),
      if (doi != null && doi!.trim().isNotEmpty) 'doi': doi!.trim(),
      if (url != null && url!.trim().isNotEmpty) 'url': url!.trim(),
      if (locator != null && locator!.trim().isNotEmpty) 'locator': locator!.trim(),
      if (kind != null && kind!.trim().isNotEmpty) 'sourceKind': kind!.trim(),
    };
  }
}

class TextSystemCitationRegistry {
  const TextSystemCitationRegistry({
    required this.items,
    required this.numbersByTargetId,
  });

  factory TextSystemCitationRegistry.fromDocument(TextSystemDocument document) {
    final items = <TextSystemCitationRegistryItem>[];
    final numbersByTargetId = <String, int>{};
    final seenTargets = <String>{};

    for (final block in document.blocks) {
      if (TextSystemCitationBibliographyGenerator.isGeneratedBibliographyBlock(block)) continue;
      for (final mark in block.marks) {
        final inlineReference = _citationMarkFromTextMark(mark);
        if (inlineReference == null) continue;
        final targetId = inlineReference.targetId;
        if (targetId.isEmpty || seenTargets.contains(targetId)) continue;
        seenTargets.add(targetId);
        numbersByTargetId[targetId] = items.length + 1;
        items.add(
          TextSystemCitationRegistryItem(
            mark: inlineReference,
            source: TextSystemCitationSource.fromInlineMark(inlineReference),
            firstBlockId: block.id,
            firstRange: mark.range,
            number: items.length + 1,
          ),
        );
      }
    }

    return TextSystemCitationRegistry(
      items: List<TextSystemCitationRegistryItem>.unmodifiable(items),
      numbersByTargetId: Map<String, int>.unmodifiable(numbersByTargetId),
    );
  }

  final List<TextSystemCitationRegistryItem> items;
  final Map<String, int> numbersByTargetId;

  int numberForTarget(String targetId) => numbersByTargetId[targetId] ?? items.length + 1;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
}

class TextSystemCitationRegistryItem {
  const TextSystemCitationRegistryItem({
    required this.mark,
    required this.source,
    required this.firstBlockId,
    required this.firstRange,
    required this.number,
  });

  final TextSystemInlineReferenceMark mark;
  final TextSystemCitationSource source;
  final String firstBlockId;
  final TextSystemRange firstRange;
  final int number;
}

class TextSystemCitationFormatter {
  const TextSystemCitationFormatter._();

  static String inlineCitation({
    required TextSystemCitationSettings settings,
    required TextSystemCitationSource source,
    required int sequenceNumber,
    TextSystemCitationInlineMode? inlineMode,
  }) {
    final mode = inlineMode ?? settings.inlineMode;
    final locator = _locatorSuffix(source.locator, settings.style);
    final year = source.year == null || source.year!.trim().isEmpty ? 'n.d.' : source.year!.trim();
    final author = source.authorLabel;

    switch (settings.style) {
      case TextSystemCitationStyle.apa7:
      case TextSystemCitationStyle.harvard:
        return mode == TextSystemCitationInlineMode.narrative
            ? '$author ($year$locator)'
            : '($author, $year$locator)';
      case TextSystemCitationStyle.chicagoAuthorDate:
        return mode == TextSystemCitationInlineMode.narrative
            ? '$author ($year${_chicagoLocator(source.locator)})'
            : '($author $year${_chicagoLocator(source.locator)})';
      case TextSystemCitationStyle.mla9:
        final mlaLocator = source.locator == null || source.locator!.trim().isEmpty ? '' : ' ${source.locator!.trim()}';
        return mode == TextSystemCitationInlineMode.narrative ? '$author$mlaLocator' : '($author$mlaLocator)';
      case TextSystemCitationStyle.ieee:
        return '[$sequenceNumber]';
    }
  }

  static String bibliographyEntry({
    required TextSystemCitationSettings settings,
    required TextSystemCitationSource source,
    required int sequenceNumber,
  }) {
    final authors = source.authorBibliographyLabel;
    final year = source.year == null || source.year!.trim().isEmpty ? 'n.d.' : source.year!.trim();
    final title = source.title.trim().isEmpty ? 'Untitled source' : source.title.trim();
    final container = source.containerTitle?.trim();
    final publisher = source.publisher?.trim();
    final doi = source.doi?.trim();
    final url = source.url?.trim();

    switch (settings.style) {
      case TextSystemCitationStyle.apa7:
        return _joinSentences(<String>[
          '$authors ($year). $title.',
          if (container != null && container.isNotEmpty) container,
          if (publisher != null && publisher.isNotEmpty) publisher,
          if (doi != null && doi.isNotEmpty) 'https://doi.org/$doi' else if (url != null && url.isNotEmpty) url,
        ]);
      case TextSystemCitationStyle.harvard:
        return _joinParts(<String>[
          '$authors $year',
          title,
          if (container != null && container.isNotEmpty) container,
          if (publisher != null && publisher.isNotEmpty) publisher,
          if (doi != null && doi.isNotEmpty) 'doi:$doi' else if (url != null && url.isNotEmpty) url,
        ]);
      case TextSystemCitationStyle.chicagoAuthorDate:
        return _joinSentences(<String>[
          '$authors. $year. $title.',
          if (container != null && container.isNotEmpty) container,
          if (publisher != null && publisher.isNotEmpty) publisher,
          if (doi != null && doi.isNotEmpty) 'doi:$doi' else if (url != null && url.isNotEmpty) url,
        ]);
      case TextSystemCitationStyle.mla9:
        return _joinSentences(<String>[
          '$authors. "$title."',
          if (container != null && container.isNotEmpty) container,
          if (publisher != null && publisher.isNotEmpty) publisher,
          year,
          if (doi != null && doi.isNotEmpty) 'doi:$doi' else if (url != null && url.isNotEmpty) url,
        ]);
      case TextSystemCitationStyle.ieee:
        return '[$sequenceNumber] ${_joinParts(<String>[
          authors,
          '"$title"',
          if (container != null && container.isNotEmpty) container,
          year,
          if (doi != null && doi.isNotEmpty) 'doi:$doi' else if (url != null && url.isNotEmpty) url,
        ])}';
    }
  }

  static String bibliographyText({
    required TextSystemCitationSettings settings,
    required TextSystemCitationRegistry registry,
  }) {
    if (registry.isEmpty) return '';
    final entries = <String>[
      settings.style.bibliographyTitle,
      '',
      for (final item in registry.items)
        bibliographyEntry(
          settings: settings,
          source: item.source,
          sequenceNumber: item.number,
        ),
    ];
    return entries.join('\n');
  }
}

class TextSystemCitationBibliographyGenerator {
  const TextSystemCitationBibliographyGenerator._();

  static const String generatedPageBreakBlockId = 'generated-bibliography-page-break';
  static const String generatedBibliographyBlockId = 'generated-bibliography';

  static bool isGeneratedBibliographyBlock(TextSystemBlock block) {
    return block.metadata['generatedKind'] == 'bibliography' ||
        block.id == generatedBibliographyBlockId ||
        block.id == generatedPageBreakBlockId;
  }

  static TextSystemDocument refreshDocument(
    TextSystemDocument document, {
    TextSystemCitationSettings? settings,
  }) {
    final effectiveSettings = settings ?? TextSystemCitationSettings.fromDocument(document);
    final withoutGenerated = _withoutGeneratedBibliography(document);
    final refreshedInlineCitations = _withRefreshedInlineCitationText(
      withoutGenerated,
      effectiveSettings,
    );
    final withSettings = effectiveSettings.applyToDocument(refreshedInlineCitations);
    final registry = TextSystemCitationRegistry.fromDocument(withSettings);
    if (registry.isEmpty) return withSettings;

    final bibliographyText = TextSystemCitationFormatter.bibliographyText(
      settings: effectiveSettings,
      registry: registry,
    );

    final pageBreak = TextSystemBlock(
      id: generatedPageBreakBlockId,
      type: TextSystemBlockType.divider,
      text: '',
      metadata: <String, Object?>{
        'kind': 'pageBreak',
        'generated': true,
        'generatedKind': 'bibliography',
        'locked': true,
      },
    );

    final bibliography = TextSystemBlock(
      id: generatedBibliographyBlockId,
      type: TextSystemBlockType.custom,
      text: bibliographyText,
      metadata: <String, Object?>{
        'kind': 'bibliography',
        'generated': true,
        'generatedKind': 'bibliography',
        'locked': true,
        'styleId': 'bibliography',
        'citationStyle': effectiveSettings.style.id,
      },
    );

    return withSettings.copyWith(
      blocks: <TextSystemBlock>[
        ...withSettings.blocks,
        pageBreak,
        bibliography,
      ],
      updatedAt: DateTime.now(),
    );
  }

  static TextSystemDocument _withoutGeneratedBibliography(TextSystemDocument document) {
    final filtered = document.blocks.where((block) => !isGeneratedBibliographyBlock(block)).toList(growable: false);
    if (filtered.length == document.blocks.length) return document;
    return document.copyWith(blocks: filtered, updatedAt: DateTime.now());
  }


  static TextSystemDocument _withRefreshedInlineCitationText(
    TextSystemDocument document,
    TextSystemCitationSettings settings,
  ) {
    final registry = TextSystemCitationRegistry.fromDocument(document);
    if (registry.isEmpty) return document;

    var changed = false;
    final nextBlocks = <TextSystemBlock>[];

    for (final block in document.blocks) {
      if (isGeneratedBibliographyBlock(block)) continue;
      final citationMarks = block.marks
          .where((mark) => _citationMarkFromTextMark(mark) != null)
          .toList()
        ..sort((a, b) => b.range.start.compareTo(a.range.start));

      if (citationMarks.isEmpty) {
        nextBlocks.add(block);
        continue;
      }

      var nextText = block.text;
      var nextMarks = <TextMark>[...block.marks];

      for (final citationMark in citationMarks) {
        final inlineReference = _citationMarkFromTextMark(citationMark);
        if (inlineReference == null) continue;
        final start = citationMark.range.start.clamp(0, nextText.length).toInt();
        final end = citationMark.range.end.clamp(start, nextText.length).toInt();
        if (start >= end) continue;

        final source = TextSystemCitationSource.fromInlineMark(inlineReference);
        final sequenceNumber = registry.numberForTarget(inlineReference.targetId);
        final inlineMode = TextSystemCitationInlineModeX.fromId(
          inlineReference.metadata['citationInlineMode'] as String?,
        );
        final citationText = TextSystemCitationFormatter.inlineCitation(
          settings: settings,
          source: source,
          sequenceNumber: sequenceNumber,
          inlineMode: inlineMode,
        );
        final existingText = nextText.substring(start, end);
        final delta = citationText.length - existingText.length;
        if (delta == 0 && existingText == citationText) {
          final refreshed = _refreshedCitationMark(
            mark: inlineReference,
            source: source,
            settings: settings,
            citationText: citationText,
            inlineMode: inlineMode,
          );
          nextMarks = nextMarks
              .map((mark) => _isSameCitationMark(mark, citationMark, inlineReference)
                  ? mark.copyWith(attributes: refreshed.toTextMarkAttributes())
                  : mark)
              .toList(growable: false);
          continue;
        }

        changed = true;
        nextText = nextText.replaceRange(start, end, citationText);
        final refreshed = _refreshedCitationMark(
          mark: inlineReference,
          source: source,
          settings: settings,
          citationText: citationText,
          inlineMode: inlineMode,
        );
        nextMarks = nextMarks.map((mark) {
          if (_isSameCitationMark(mark, citationMark, inlineReference)) {
            return mark.copyWith(
              range: TextSystemRange(start, start + citationText.length),
              attributes: refreshed.toTextMarkAttributes(),
            );
          }
          if (mark.range.start >= end) {
            return mark.copyWith(range: mark.range.shift(delta));
          }
          if (mark.range.end > end) {
            return mark.copyWith(
              range: TextSystemRange(mark.range.start, mark.range.end + delta),
            );
          }
          return mark;
        }).toList(growable: false);
      }

      nextBlocks.add(block.copyWith(text: nextText, marks: nextMarks).normalizeMarks());
    }

    if (!changed) {
      return document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now());
    }
    return document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now());
  }

  static TextSystemInlineReferenceMark _refreshedCitationMark({
    required TextSystemInlineReferenceMark mark,
    required TextSystemCitationSource source,
    required TextSystemCitationSettings settings,
    required String citationText,
    required TextSystemCitationInlineMode inlineMode,
  }) {
    return mark.copyWith(
      selectedText: citationText,
      metadata: <String, Object?>{
        ...mark.metadata,
        ...source.toMetadata(),
        'citationStyleId': settings.style.id,
        'citationInlineMode': inlineMode.id,
        'citationText': citationText,
        'bibliographyManaged': true,
      },
    );
  }

  static bool _isSameCitationMark(
    TextMark candidate,
    TextMark original,
    TextSystemInlineReferenceMark inlineReference,
  ) {
    if (candidate.kind != TextMarkKind.link) return false;
    final candidateReference = _citationMarkFromTextMark(candidate);
    if (candidateReference == null) return false;
    return candidateReference.id == inlineReference.id ||
        (candidate.range.start == original.range.start &&
            candidate.range.end == original.range.end &&
            candidateReference.targetId == inlineReference.targetId);
  }
}

TextSystemInlineReferenceMark? _citationMarkFromTextMark(TextMark mark) {
  if (mark.kind != TextMarkKind.link) return null;
  final inlineReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(mark.attributes);
  if (inlineReference == null || inlineReference.kind != TextSystemReferenceTargetKind.citation) return null;
  return inlineReference;
}

class _ParsedAcademicLabel {
  const _ParsedAcademicLabel({
    this.authors = const <String>[],
    this.year,
    this.title,
  });

  final List<String> authors;
  final String? year;
  final String? title;
}

_ParsedAcademicLabel _parseAcademicLabel(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const _ParsedAcademicLabel();

  final yearMatch = RegExp(r'\((\d{4}|n\.d\.)\)').firstMatch(trimmed);
  if (yearMatch != null) {
    final before = trimmed.substring(0, yearMatch.start).trim();
    final after = trimmed.substring(yearMatch.end).trim();
    return _ParsedAcademicLabel(
      authors: _splitAuthors(before),
      year: yearMatch.group(1),
      title: after.isEmpty ? trimmed : after,
    );
  }

  final looseYear = RegExp(r'\b(\d{4})\b').firstMatch(trimmed);
  if (looseYear != null) {
    return _ParsedAcademicLabel(
      authors: _splitAuthors(trimmed.substring(0, looseYear.start).trim()),
      year: looseYear.group(1),
      title: trimmed,
    );
  }

  return _ParsedAcademicLabel(title: trimmed);
}

List<String> _splitAuthors(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return const <String>[];
  return normalized
      .split(RegExp(r'\s+(?:&|and)\s+|;'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

List<String>? _authorsValue(Object? raw) {
  if (raw is List) {
    final authors = raw.map((value) => value.toString().trim()).where((value) => value.isNotEmpty).toList(growable: false);
    return authors.isEmpty ? null : authors;
  }
  if (raw is String && raw.trim().isNotEmpty) return _splitAuthors(raw);
  return null;
}


bool _isPdfBackedSourceKind(String? sourceKind) {
  if (sourceKind == null) return false;
  return sourceKind == 'pdf' || sourceKind.startsWith('pdf');
}

String? _externalUriString(Uri? uri) {
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'pdf' || scheme == 'note' || scheme == 'project' || scheme == 'todo') {
    return null;
  }
  final value = uri.toString().trim();
  return value.isEmpty ? null : value;
}

String? _stringValue(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

String _familyName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Unknown author';
  if (trimmed.contains(',')) return trimmed.split(',').first.trim();
  final parts = trimmed.split(RegExp(r'\s+'));
  return parts.isEmpty ? trimmed : parts.last.trim();
}

String _locatorSuffix(String? locator, TextSystemCitationStyle style) {
  if (locator == null || locator.trim().isEmpty) return '';
  final clean = locator.trim();
  if (clean.startsWith('p.') || clean.startsWith('pp.')) return ', $clean';
  return ', p. $clean';
}

String _chicagoLocator(String? locator) {
  if (locator == null || locator.trim().isEmpty) return '';
  return ', ${locator.trim()}';
}

String _joinParts(List<String> values) {
  return values.map((value) => value.trim()).where((value) => value.isNotEmpty).join(', ') + '.';
}

String _joinSentences(List<String> values) {
  final cleaned = values.map((value) => value.trim()).where((value) => value.isNotEmpty).toList();
  if (cleaned.isEmpty) return '';
  return cleaned.map((value) => value.endsWith('.') ? value : '$value.').join(' ');
}

String encodeCitationMetadata(Map<String, Object?> metadata) => jsonEncode(metadata);
