import '../core/source_document_block.dart';
import '../core/source_range.dart';

/// Source-aware LaTeX macro argument.
///
/// The parser provides both the raw content and the source ranges so renderers
/// can produce visual blocks without taking ownership away from canonical
/// source text. Phase 4 still edits custom macro blocks as source, but these
/// ranges are the foundation for field-level visual editing later.
class LatexMacroArgument {
  const LatexMacroArgument({
    required this.content,
    required this.sourceRange,
    required this.contentRange,
  });

  final String content;
  final SourceRange sourceRange;
  final SourceRange contentRange;
}

class LatexMacroRenderContext {
  const LatexMacroRenderContext({
    required this.source,
    required this.sourceStart,
    required this.sourceEnd,
    required this.blockNumber,
    required this.commandName,
    required this.inlineRenderer,
  });

  final String source;
  final int sourceStart;
  final int sourceEnd;
  final int blockNumber;
  final String commandName;
  final String Function(String source) inlineRenderer;
}

/// A custom macro renderer turns known domain/template LaTeX commands into
/// stable visual blocks. Unsupported commands still fall back to editable source.
abstract class LatexMacroRenderer {
  const LatexMacroRenderer();

  String get commandName;

  /// Minimum required brace arguments. The parser may pass more arguments.
  int get minRequiredArguments;

  bool canRender(List<LatexMacroArgument> arguments) {
    return arguments.length >= minRequiredArguments;
  }

  SourceDocumentBlock render({
    required LatexMacroRenderContext context,
    required List<LatexMacroArgument> arguments,
  });
}

class LatexMacroRegistry {
  const LatexMacroRegistry(this._renderers);

  factory LatexMacroRegistry.defaults() {
    return const LatexMacroRegistry(<LatexMacroRenderer>[
      RoleMacroRenderer(),
      EducationMacroRenderer(),
      ProjectMacroRenderer(),
      SkillRowMacroRenderer(),
      CvItemMacroRenderer(),
    ]);
  }

  final List<LatexMacroRenderer> _renderers;

  LatexMacroRenderer? rendererFor(String commandName, List<LatexMacroArgument> arguments) {
    for (final renderer in _renderers) {
      if (renderer.commandName == commandName && renderer.canRender(arguments)) {
        return renderer;
      }
    }
    return null;
  }

  SourceDocumentBlock? tryRender({
    required String commandName,
    required List<LatexMacroArgument> arguments,
    required LatexMacroRenderContext context,
  }) {
    final renderer = rendererFor(commandName, arguments);
    if (renderer == null) return null;
    return renderer.render(context: context, arguments: arguments);
  }
}

abstract class _StructuredMacroRenderer extends LatexMacroRenderer {
  const _StructuredMacroRenderer();

  String clean(LatexMacroRenderContext context, LatexMacroArgument argument) {
    return context.inlineRenderer(argument.content).trim();
  }

  SourceDocumentBlock structuredBlock({
    required LatexMacroRenderContext context,
    required String title,
    String? subtitle,
    String? meta,
    String? body,
    String? kind,
    Map<String, Object?> extraMetadata = const <String, Object?>{},
  }) {
    final visibleLines = <String>[
      title,
      if (subtitle != null && subtitle.trim().isNotEmpty) subtitle,
      if (meta != null && meta.trim().isNotEmpty) meta,
      if (body != null && body.trim().isNotEmpty) body,
    ];

    return SourceDocumentBlock(
      id: 'latex-macro-${context.commandName}-${context.blockNumber}-${context.sourceStart}',
      type: SourceBlockType.custom,
      sourceRange: SourceRange(context.sourceStart, context.sourceEnd),
      text: visibleLines.join('\n'),
      metadata: <String, Object?>{
        'command': context.commandName,
        'macro': context.commandName,
        'kind': kind ?? 'latex-macro',
        'displayMode': 'structured',
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (meta != null) 'meta': meta,
        if (body != null) 'body': body,
        ...extraMetadata,
      },
    );
  }
}

/// CV/work-experience style macro:
/// \role{Title}{Dates}{Organization}{Location}{Description}
class RoleMacroRenderer extends _StructuredMacroRenderer {
  const RoleMacroRenderer();

  @override
  String get commandName => 'role';

  @override
  int get minRequiredArguments => 5;

  @override
  SourceDocumentBlock render({
    required LatexMacroRenderContext context,
    required List<LatexMacroArgument> arguments,
  }) {
    final title = clean(context, arguments[0]);
    final dates = clean(context, arguments[1]);
    final organization = clean(context, arguments[2]);
    final location = clean(context, arguments[3]);
    final body = clean(context, arguments[4]);
    return structuredBlock(
      context: context,
      title: title,
      subtitle: [organization, location].where((value) => value.isNotEmpty).join(' · '),
      meta: dates,
      body: body,
      kind: 'cv-experience',
    );
  }
}

/// Common education macro shape:
/// \education{Degree}{Dates}{Institution}{Location}{Description}
/// The fifth argument is optional in many templates, so this renderer accepts
/// four or more arguments and uses any remaining text as body.
class EducationMacroRenderer extends _StructuredMacroRenderer {
  const EducationMacroRenderer();

  @override
  String get commandName => 'education';

  @override
  int get minRequiredArguments => 4;

  @override
  SourceDocumentBlock render({
    required LatexMacroRenderContext context,
    required List<LatexMacroArgument> arguments,
  }) {
    final degree = clean(context, arguments[0]);
    final dates = clean(context, arguments[1]);
    final institution = clean(context, arguments[2]);
    final location = clean(context, arguments[3]);
    final body = arguments.length > 4
        ? arguments.skip(4).map((argument) => clean(context, argument)).join('\n')
        : null;
    return structuredBlock(
      context: context,
      title: degree,
      subtitle: [institution, location].where((value) => value.isNotEmpty).join(' · '),
      meta: dates,
      body: body,
      kind: 'education',
    );
  }
}

/// Generic project macro shape:
/// \project{Name}{Context/Tech}{Description}
class ProjectMacroRenderer extends _StructuredMacroRenderer {
  const ProjectMacroRenderer();

  @override
  String get commandName => 'project';

  @override
  int get minRequiredArguments => 3;

  @override
  SourceDocumentBlock render({
    required LatexMacroRenderContext context,
    required List<LatexMacroArgument> arguments,
  }) {
    return structuredBlock(
      context: context,
      title: clean(context, arguments[0]),
      subtitle: clean(context, arguments[1]),
      body: arguments.skip(2).map((argument) => clean(context, argument)).join('\n'),
      kind: 'project',
    );
  }
}

/// Two-column skill row style macro:
/// \skillrow{Category}{Skills}
class SkillRowMacroRenderer extends _StructuredMacroRenderer {
  const SkillRowMacroRenderer();

  @override
  String get commandName => 'skillrow';

  @override
  int get minRequiredArguments => 2;

  @override
  SourceDocumentBlock render({
    required LatexMacroRenderContext context,
    required List<LatexMacroArgument> arguments,
  }) {
    return structuredBlock(
      context: context,
      title: clean(context, arguments[0]),
      body: clean(context, arguments[1]),
      kind: 'skill-row',
      extraMetadata: const {'compact': true},
    );
  }
}

/// Generic CV item macro:
/// \cvitem{Label}{Content}
class CvItemMacroRenderer extends _StructuredMacroRenderer {
  const CvItemMacroRenderer();

  @override
  String get commandName => 'cvitem';

  @override
  int get minRequiredArguments => 2;

  @override
  SourceDocumentBlock render({
    required LatexMacroRenderContext context,
    required List<LatexMacroArgument> arguments,
  }) {
    return structuredBlock(
      context: context,
      title: clean(context, arguments[0]),
      body: clean(context, arguments[1]),
      kind: 'cv-item',
      extraMetadata: const {'compact': true},
    );
  }
}
