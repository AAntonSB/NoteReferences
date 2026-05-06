import 'dart:convert';

import 'text_mark.dart';
import 'text_system_block.dart';
import 'text_system_document.dart';
import 'text_system_document_fragment.dart';

/// Severity for a text-system diagnostic check.
enum TextSystemDiagnosticSeverity { pass, warning, error }

/// One shareable validation result for the text-system diagnostic lab.
class TextSystemDiagnosticCheck {
  const TextSystemDiagnosticCheck({
    required this.id,
    required this.label,
    required this.severity,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final String id;
  final String label;
  final TextSystemDiagnosticSeverity severity;
  final String message;
  final Map<String, Object?> details;

  bool get passed => severity != TextSystemDiagnosticSeverity.error;

  String get statusLabel => switch (severity) {
        TextSystemDiagnosticSeverity.pass => 'PASS',
        TextSystemDiagnosticSeverity.warning => 'WARN',
        TextSystemDiagnosticSeverity.error => 'FAIL',
      };

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'status': statusLabel,
      'message': message,
      if (details.isNotEmpty) 'details': details,
    };
  }

  String toReportLine() {
    final suffix = details.isEmpty ? '' : ' | ${jsonEncode(details)}';
    return '[$statusLabel] $label — $message$suffix';
  }
}

/// Pure model validator for the reusable text-system document model.
///
/// This intentionally does not depend on Flutter widgets. The fluent editor lab
/// can use these checks while any future text surface can reuse the same model
/// validation before save, export, or bug-report generation.
class TextSystemDocumentValidator {
  const TextSystemDocumentValidator._();

  static List<TextSystemDiagnosticCheck> validateDocument(TextSystemDocument document) {
    final checks = <TextSystemDiagnosticCheck>[
      _validateIdentity(document),
      _validateBlocksPresent(document),
      _validateBlockIds(document),
      ..._validateBlockTextAndMarks(document),
      _validateJsonRoundTrip(document),
    ];
    return checks;
  }

  static List<TextSystemDiagnosticCheck> validateDocumentFragment(
    TextSystemDocumentFragment? fragment, {
    String idPrefix = 'fragment',
  }) {
    if (fragment == null) {
      return <TextSystemDiagnosticCheck>[
        TextSystemDiagnosticCheck(
          id: '$idPrefix.present',
          label: 'Structured clipboard',
          severity: TextSystemDiagnosticSeverity.warning,
          message: 'No structured document fragment is currently stored.',
        ),
      ];
    }

    final pseudoDocument = TextSystemDocument(
      id: '$idPrefix-document',
      title: 'Diagnostic fragment',
      blocks: fragment.blocks,
      metadata: fragment.metadata,
    );
    return validateDocument(pseudoDocument)
        .map(
          (check) => TextSystemDiagnosticCheck(
            id: '$idPrefix.${check.id}',
            label: 'Fragment ${check.label}',
            severity: check.severity,
            message: check.message,
            details: check.details,
          ),
        )
        .toList();
  }

  static int errorCount(Iterable<TextSystemDiagnosticCheck> checks) {
    return checks.where((check) => check.severity == TextSystemDiagnosticSeverity.error).length;
  }

  static int warningCount(Iterable<TextSystemDiagnosticCheck> checks) {
    return checks.where((check) => check.severity == TextSystemDiagnosticSeverity.warning).length;
  }

  static TextSystemDiagnosticCheck _validateIdentity(TextSystemDocument document) {
    final missing = <String>[];
    if (document.id.trim().isEmpty) missing.add('id');
    if (document.title.trim().isEmpty) missing.add('title');

    if (missing.isEmpty) {
      return TextSystemDiagnosticCheck(
        id: 'document.identity',
        label: 'Document identity',
        severity: TextSystemDiagnosticSeverity.pass,
        message: 'Document id and title are present.',
      );
    }

    return TextSystemDiagnosticCheck(
      id: 'document.identity',
      label: 'Document identity',
      severity: TextSystemDiagnosticSeverity.error,
      message: 'Missing required identity fields: ${missing.join(', ')}.',
    );
  }

  static TextSystemDiagnosticCheck _validateBlocksPresent(TextSystemDocument document) {
    if (document.blocks.isEmpty) {
      return const TextSystemDiagnosticCheck(
        id: 'document.blocks.present',
        label: 'Text units present',
        severity: TextSystemDiagnosticSeverity.warning,
        message: 'Document has no text units. This is valid but unusual for the editor lab.',
      );
    }
    return TextSystemDiagnosticCheck(
      id: 'document.blocks.present',
      label: 'Text units present',
      severity: TextSystemDiagnosticSeverity.pass,
      message: 'Document has ${document.blocks.length} text units.',
    );
  }

  static TextSystemDiagnosticCheck _validateBlockIds(TextSystemDocument document) {
    final seen = <String>{};
    final duplicates = <String>{};
    final empty = <int>[];

    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      if (block.id.trim().isEmpty) {
        empty.add(i);
        continue;
      }
      if (!seen.add(block.id)) duplicates.add(block.id);
    }

    if (duplicates.isEmpty && empty.isEmpty) {
      return TextSystemDiagnosticCheck(
        id: 'document.blocks.ids',
        label: 'Text unit ids',
        severity: TextSystemDiagnosticSeverity.pass,
        message: 'All text unit ids are present and unique.',
      );
    }

    return TextSystemDiagnosticCheck(
      id: 'document.blocks.ids',
      label: 'Text unit ids',
      severity: TextSystemDiagnosticSeverity.error,
      message: 'Text unit ids must be present and unique.',
      details: <String, Object?>{
        if (duplicates.isNotEmpty) 'duplicates': duplicates.toList(),
        if (empty.isNotEmpty) 'emptyIndices': empty,
      },
    );
  }

  static List<TextSystemDiagnosticCheck> _validateBlockTextAndMarks(TextSystemDocument document) {
    final checks = <TextSystemDiagnosticCheck>[];
    for (var i = 0; i < document.blocks.length; i++) {
      final block = document.blocks[i];
      checks.add(_validateBlockShape(block, i));
      checks.add(_validateBlockMarks(block, i));
    }
    return checks;
  }

  static TextSystemDiagnosticCheck _validateBlockShape(TextSystemBlock block, int index) {
    final issues = <String>[];
    if (block.type == TextSystemBlockType.heading) {
      final level = block.level ?? 1;
      if (level < 1 || level > 6) issues.add('heading level should be 1–6');
    }
    if (block.type == TextSystemBlockType.listItem && block.metadata['ordered'] == true) {
      final orderIndex = block.metadata['index'];
      if (orderIndex is! int || orderIndex < 1) issues.add('ordered list item should have positive integer index metadata');
    }

    if (issues.isEmpty) {
      return TextSystemDiagnosticCheck(
        id: 'document.block.$index.shape',
        label: 'Text unit ${index + 1} shape',
        severity: TextSystemDiagnosticSeverity.pass,
        message: '${block.type.name} shape is valid.',
        details: <String, Object?>{'blockId': block.id},
      );
    }

    return TextSystemDiagnosticCheck(
      id: 'document.block.$index.shape',
      label: 'Text unit ${index + 1} shape',
      severity: TextSystemDiagnosticSeverity.warning,
      message: issues.join('; '),
      details: <String, Object?>{'blockId': block.id, 'type': block.type.name},
    );
  }

  static TextSystemDiagnosticCheck _validateBlockMarks(TextSystemBlock block, int index) {
    final invalid = <Map<String, Object?>>[];
    for (var markIndex = 0; markIndex < block.marks.length; markIndex++) {
      final mark = block.marks[markIndex];
      if (!_markRangeIsValid(mark, block.text.length)) {
        invalid.add(<String, Object?>{
          'markIndex': markIndex,
          'kind': mark.kind.name,
          'range': mark.range.toJson(),
          'textLength': block.text.length,
        });
      }
    }

    if (invalid.isEmpty) {
      return TextSystemDiagnosticCheck(
        id: 'document.block.$index.marks',
        label: 'Text unit ${index + 1} marks',
        severity: TextSystemDiagnosticSeverity.pass,
        message: '${block.marks.length} mark range(s) are valid.',
        details: <String, Object?>{'blockId': block.id},
      );
    }

    return TextSystemDiagnosticCheck(
      id: 'document.block.$index.marks',
      label: 'Text unit ${index + 1} marks',
      severity: TextSystemDiagnosticSeverity.error,
      message: 'One or more mark ranges are outside the text bounds.',
      details: <String, Object?>{'blockId': block.id, 'invalidMarks': invalid},
    );
  }

  static bool _markRangeIsValid(TextMark mark, int textLength) {
    return mark.range.start >= 0 &&
        mark.range.end >= mark.range.start &&
        mark.range.end <= textLength;
  }

  static TextSystemDiagnosticCheck _validateJsonRoundTrip(TextSystemDocument document) {
    try {
      final json = document.toJson();
      final decoded = Map<String, Object?>.from(jsonDecode(jsonEncode(json)) as Map);
      final roundTrip = TextSystemDocument.fromJson(decoded);
      final sameShape = roundTrip.id == document.id &&
          roundTrip.title == document.title &&
          roundTrip.blocks.length == document.blocks.length &&
          roundTrip.plainText == document.plainText &&
          _markCount(roundTrip) == _markCount(document);

      if (sameShape) {
        return TextSystemDiagnosticCheck(
          id: 'document.json.roundTrip',
          label: 'JSON round-trip',
          severity: TextSystemDiagnosticSeverity.pass,
          message: 'Document serializes and deserializes without losing text shape or mark count.',
        );
      }

      return TextSystemDiagnosticCheck(
        id: 'document.json.roundTrip',
        label: 'JSON round-trip',
        severity: TextSystemDiagnosticSeverity.error,
        message: 'Document JSON round-trip changed the text shape or mark count.',
        details: <String, Object?>{
          'beforeBlocks': document.blocks.length,
          'afterBlocks': roundTrip.blocks.length,
          'beforeMarks': _markCount(document),
          'afterMarks': _markCount(roundTrip),
        },
      );
    } catch (error) {
      return TextSystemDiagnosticCheck(
        id: 'document.json.roundTrip',
        label: 'JSON round-trip',
        severity: TextSystemDiagnosticSeverity.error,
        message: 'Document JSON round-trip threw: $error',
      );
    }
  }

  static int _markCount(TextSystemDocument document) {
    return document.blocks.fold<int>(0, (count, block) => count + block.marks.length);
  }
}
