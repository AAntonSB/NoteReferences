import 'text_system_block.dart';

/// Semantic block categories used by the document interaction core.
///
/// These are intentionally broader than [TextSystemBlockType]. A block's raw
/// type tells us how it is stored; the semantic kind tells selection, copy,
/// delete, diagnostics, references, and export systems how the block behaves in
/// the document.
enum TextSystemBlockSemanticKind {
  paragraph,
  heading,
  listItem,
  todo,
  quote,
  code,
  divider,
  figure,
  table,
  equation,
  pageBreak,
  sectionBreak,
  unknownObject,
}

/// Capability descriptor for one block instance.
///
/// New block features should provide capabilities instead of requiring selection,
/// copy/delete, reference, and diagnostics code to hard-code every block kind.
class TextSystemBlockCapabilities {
  const TextSystemBlockCapabilities({
    required this.semanticKind,
    required this.displayName,
    required this.isTextEditable,
    required this.isAtomicObject,
    required this.supportsCaption,
    required this.supportsLabel,
    required this.supportsInlineAtoms,
    required this.supportsTableCells,
    required this.canBeCrossReferenced,
    required this.canBeCommented,
    required this.canBeCopiedAsStructuredContent,
    this.supportsLatexSource = false,
    this.supportsObjectSelection = false,
    this.supportsRangeSelection = true,
    this.metadata = const <String, Object?>{},
  });

  final TextSystemBlockSemanticKind semanticKind;
  final String displayName;

  /// True for paragraph-like blocks where the main content is directly editable
  /// text owned by the block.
  final bool isTextEditable;

  /// True when the block behaves as one document object at the document level.
  /// Tables can still have an internal table-cell editing mode, but for document
  /// selection/copy/delete they are atomic unless the table subsystem is active.
  final bool isAtomicObject;

  final bool supportsCaption;
  final bool supportsLabel;
  final bool supportsInlineAtoms;
  final bool supportsTableCells;
  final bool canBeCrossReferenced;
  final bool canBeCommented;
  final bool canBeCopiedAsStructuredContent;

  /// Useful for equations and future code/math/proof blocks.
  final bool supportsLatexSource;

  /// True when the block should use object selection affordances rather than
  /// text-field selection affordances.
  final bool supportsObjectSelection;

  /// True when the block can participate in document-range selection. This is
  /// usually true, but a future ephemeral/debug block could opt out.
  final bool supportsRangeSelection;

  final Map<String, Object?> metadata;

  bool get isTextLike => isTextEditable && !isAtomicObject;

  bool get isStructuralBoundary =>
      semanticKind == TextSystemBlockSemanticKind.pageBreak ||
      semanticKind == TextSystemBlockSemanticKind.sectionBreak ||
      semanticKind == TextSystemBlockSemanticKind.divider;

  bool get isAcademicObject =>
      semanticKind == TextSystemBlockSemanticKind.figure ||
      semanticKind == TextSystemBlockSemanticKind.table ||
      semanticKind == TextSystemBlockSemanticKind.equation;

  bool get isFigure => semanticKind == TextSystemBlockSemanticKind.figure;
  bool get isTable => semanticKind == TextSystemBlockSemanticKind.table;
  bool get isEquation => semanticKind == TextSystemBlockSemanticKind.equation;

  TextSystemBlockCapabilities copyWith({
    TextSystemBlockSemanticKind? semanticKind,
    String? displayName,
    bool? isTextEditable,
    bool? isAtomicObject,
    bool? supportsCaption,
    bool? supportsLabel,
    bool? supportsInlineAtoms,
    bool? supportsTableCells,
    bool? canBeCrossReferenced,
    bool? canBeCommented,
    bool? canBeCopiedAsStructuredContent,
    bool? supportsLatexSource,
    bool? supportsObjectSelection,
    bool? supportsRangeSelection,
    Map<String, Object?>? metadata,
  }) {
    return TextSystemBlockCapabilities(
      semanticKind: semanticKind ?? this.semanticKind,
      displayName: displayName ?? this.displayName,
      isTextEditable: isTextEditable ?? this.isTextEditable,
      isAtomicObject: isAtomicObject ?? this.isAtomicObject,
      supportsCaption: supportsCaption ?? this.supportsCaption,
      supportsLabel: supportsLabel ?? this.supportsLabel,
      supportsInlineAtoms: supportsInlineAtoms ?? this.supportsInlineAtoms,
      supportsTableCells: supportsTableCells ?? this.supportsTableCells,
      canBeCrossReferenced: canBeCrossReferenced ?? this.canBeCrossReferenced,
      canBeCommented: canBeCommented ?? this.canBeCommented,
      canBeCopiedAsStructuredContent:
          canBeCopiedAsStructuredContent ?? this.canBeCopiedAsStructuredContent,
      supportsLatexSource: supportsLatexSource ?? this.supportsLatexSource,
      supportsObjectSelection: supportsObjectSelection ?? this.supportsObjectSelection,
      supportsRangeSelection: supportsRangeSelection ?? this.supportsRangeSelection,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'semanticKind': semanticKind.name,
      'displayName': displayName,
      'isTextEditable': isTextEditable,
      'isAtomicObject': isAtomicObject,
      'supportsCaption': supportsCaption,
      'supportsLabel': supportsLabel,
      'supportsInlineAtoms': supportsInlineAtoms,
      'supportsTableCells': supportsTableCells,
      'canBeCrossReferenced': canBeCrossReferenced,
      'canBeCommented': canBeCommented,
      'canBeCopiedAsStructuredContent': canBeCopiedAsStructuredContent,
      'supportsLatexSource': supportsLatexSource,
      'supportsObjectSelection': supportsObjectSelection,
      'supportsRangeSelection': supportsRangeSelection,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// User-facing shorter alias matching the architectural roadmap language.
typedef BlockCapabilities = TextSystemBlockCapabilities;

/// Adapter contract for feature-owned block semantics.
///
/// A future theorem/proof/PDF-excerpt/diagram block should be able to register an
/// adapter here instead of requiring the document index, selection controller,
/// clipboard, and diagnostics systems to learn its internals directly.
abstract class TextSystemBlockCapabilityAdapter {
  const TextSystemBlockCapabilityAdapter();

  bool supportsBlock(TextSystemBlock block);
  TextSystemBlockCapabilities capabilitiesFor(TextSystemBlock block);
}

class TextSystemBlockCapabilityRegistry {
  const TextSystemBlockCapabilityRegistry({
    this.adapters = const <TextSystemBlockCapabilityAdapter>[
      TextSystemDefaultBlockCapabilityAdapter(),
    ],
  });

  static const TextSystemBlockCapabilityRegistry standard = TextSystemBlockCapabilityRegistry();

  final List<TextSystemBlockCapabilityAdapter> adapters;

  TextSystemBlockCapabilities capabilitiesFor(TextSystemBlock block) {
    for (final adapter in adapters) {
      if (adapter.supportsBlock(block)) return adapter.capabilitiesFor(block);
    }
    return const TextSystemBlockCapabilities(
      semanticKind: TextSystemBlockSemanticKind.unknownObject,
      displayName: 'Unknown object',
      isTextEditable: false,
      isAtomicObject: true,
      supportsCaption: false,
      supportsLabel: false,
      supportsInlineAtoms: false,
      supportsTableCells: false,
      canBeCrossReferenced: false,
      canBeCommented: true,
      canBeCopiedAsStructuredContent: true,
      supportsObjectSelection: true,
    );
  }
}

/// Default project block semantics for the current text engine.
class TextSystemDefaultBlockCapabilityAdapter extends TextSystemBlockCapabilityAdapter {
  const TextSystemDefaultBlockCapabilityAdapter();

  @override
  bool supportsBlock(TextSystemBlock block) => true;

  @override
  TextSystemBlockCapabilities capabilitiesFor(TextSystemBlock block) {
    if (block.type == TextSystemBlockType.divider) {
      final dividerKind = _normalizedMetadataKind(block);
      if (dividerKind.contains('pagebreak')) {
        return _atomic(
          semanticKind: TextSystemBlockSemanticKind.pageBreak,
          displayName: 'Page break',
          canBeCommented: false,
        );
      }
      if (dividerKind.contains('sectionbreak')) {
        return _atomic(
          semanticKind: TextSystemBlockSemanticKind.sectionBreak,
          displayName: 'Section break',
          canBeCommented: false,
        );
      }
      return _atomic(
        semanticKind: TextSystemBlockSemanticKind.divider,
        displayName: 'Divider',
        canBeCommented: false,
      );
    }

    if (block.type == TextSystemBlockType.custom) {
      final customKind = _normalizedMetadataKind(block);
      if (customKind.contains('figure')) {
        return _academicObject(
          semanticKind: TextSystemBlockSemanticKind.figure,
          displayName: 'Figure',
          supportsCaption: true,
          supportsLabel: true,
        );
      }
      if (customKind.contains('table')) {
        return _academicObject(
          semanticKind: TextSystemBlockSemanticKind.table,
          displayName: 'Table',
          supportsCaption: true,
          supportsLabel: true,
          supportsTableCells: true,
        );
      }
      if (customKind.contains('equation') || customKind.contains('displaymath')) {
        return _academicObject(
          semanticKind: TextSystemBlockSemanticKind.equation,
          displayName: 'Equation',
          supportsLabel: true,
          supportsLatexSource: true,
        );
      }
      if (customKind.isNotEmpty) {
        return _atomic(
          semanticKind: TextSystemBlockSemanticKind.unknownObject,
          displayName: _titleCase(customKind),
        );
      }
    }

    switch (block.type) {
      case TextSystemBlockType.paragraph:
        return _text(
          semanticKind: TextSystemBlockSemanticKind.paragraph,
          displayName: 'Paragraph',
          supportsInlineAtoms: true,
        );
      case TextSystemBlockType.heading:
        return _text(
          semanticKind: TextSystemBlockSemanticKind.heading,
          displayName: 'Heading',
          supportsInlineAtoms: true,
          canBeCrossReferenced: true,
        );
      case TextSystemBlockType.listItem:
        return _text(
          semanticKind: TextSystemBlockSemanticKind.listItem,
          displayName: 'List item',
          supportsInlineAtoms: true,
        );
      case TextSystemBlockType.todo:
        return _text(
          semanticKind: TextSystemBlockSemanticKind.todo,
          displayName: 'Todo',
          supportsInlineAtoms: true,
        );
      case TextSystemBlockType.quote:
        return _text(
          semanticKind: TextSystemBlockSemanticKind.quote,
          displayName: 'Quote',
          supportsInlineAtoms: true,
        );
      case TextSystemBlockType.code:
        return _text(
          semanticKind: TextSystemBlockSemanticKind.code,
          displayName: 'Code block',
          supportsInlineAtoms: false,
          supportsLatexSource: false,
        );
      case TextSystemBlockType.divider:
      case TextSystemBlockType.custom:
        return _atomic(
          semanticKind: TextSystemBlockSemanticKind.unknownObject,
          displayName: 'Unknown object',
        );
    }
  }

  static TextSystemBlockCapabilities _text({
    required TextSystemBlockSemanticKind semanticKind,
    required String displayName,
    bool supportsInlineAtoms = false,
    bool canBeCrossReferenced = false,
    bool supportsLatexSource = false,
  }) {
    return TextSystemBlockCapabilities(
      semanticKind: semanticKind,
      displayName: displayName,
      isTextEditable: true,
      isAtomicObject: false,
      supportsCaption: false,
      supportsLabel: false,
      supportsInlineAtoms: supportsInlineAtoms,
      supportsTableCells: false,
      canBeCrossReferenced: canBeCrossReferenced,
      canBeCommented: true,
      canBeCopiedAsStructuredContent: true,
      supportsLatexSource: supportsLatexSource,
      supportsObjectSelection: false,
    );
  }

  static TextSystemBlockCapabilities _academicObject({
    required TextSystemBlockSemanticKind semanticKind,
    required String displayName,
    bool supportsCaption = false,
    bool supportsLabel = false,
    bool supportsTableCells = false,
    bool supportsLatexSource = false,
  }) {
    return TextSystemBlockCapabilities(
      semanticKind: semanticKind,
      displayName: displayName,
      isTextEditable: false,
      isAtomicObject: true,
      supportsCaption: supportsCaption,
      supportsLabel: supportsLabel,
      supportsInlineAtoms: false,
      supportsTableCells: supportsTableCells,
      canBeCrossReferenced: true,
      canBeCommented: true,
      canBeCopiedAsStructuredContent: true,
      supportsLatexSource: supportsLatexSource,
      supportsObjectSelection: true,
    );
  }

  static TextSystemBlockCapabilities _atomic({
    required TextSystemBlockSemanticKind semanticKind,
    required String displayName,
    bool canBeCommented = true,
  }) {
    return TextSystemBlockCapabilities(
      semanticKind: semanticKind,
      displayName: displayName,
      isTextEditable: false,
      isAtomicObject: true,
      supportsCaption: false,
      supportsLabel: false,
      supportsInlineAtoms: false,
      supportsTableCells: false,
      canBeCrossReferenced: false,
      canBeCommented: canBeCommented,
      canBeCopiedAsStructuredContent: true,
      supportsObjectSelection: true,
    );
  }

  static String _normalizedMetadataKind(TextSystemBlock block) {
    return _normalizeKind(
      block.metadata['kind'] ??
          block.metadata['objectKind'] ??
          block.metadata['academicObjectKind'] ??
          block.metadata['blockKind'] ??
          block.metadata['type'],
    );
  }

  static String _normalizeKind(Object? value) {
    if (value == null) return '';
    return '$value'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return 'Unknown object';
    return value.substring(0, 1).toUpperCase() + value.substring(1);
  }
}
