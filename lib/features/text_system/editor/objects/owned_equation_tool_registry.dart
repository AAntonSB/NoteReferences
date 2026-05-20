/// Metadata for the equation authoring control suite.
///
/// The registry separates what a tool does from where it is shown. The UI can
/// then surface high-confidence actions directly, keep specialized actions in a
/// drawer, and keep every action searchable/available later through a command
/// palette without hard-coding a growing wall of buttons.
class OwnedEquationToolDefinition {
  const OwnedEquationToolDefinition({
    required this.id,
    required this.label,
    required this.tooltip,
    required this.group,
    required this.surface,
    required this.priority,
    this.visualCost = 1,
    this.beginnerFriendly = true,
  });

  final String id;
  final String label;
  final String tooltip;
  final OwnedEquationToolGroup group;
  final OwnedEquationToolSurface surface;
  final int priority;
  final int visualCost;
  final bool beginnerFriendly;
}

enum OwnedEquationToolGroup {
  build,
  symbols,
  structures,
  context,
  references,
  format,
  navigation,
}

enum OwnedEquationToolSurface {
  /// Visible in the compact top-level authoring ribbon.
  pinned,

  /// Visible when the current source/AST context makes the tool highly relevant.
  contextual,

  /// Available from a drawer/menu because it is useful but more specific.
  drawer,

  /// Suggested by autocomplete or another transient affordance.
  suggested,
}

class OwnedEquationToolRegistry {
  const OwnedEquationToolRegistry._();

  static const fraction = OwnedEquationToolDefinition(
    id: 'equation.insert.fraction',
    label: r'\frac',
    tooltip: 'Insert a fraction template',
    group: OwnedEquationToolGroup.build,
    surface: OwnedEquationToolSurface.pinned,
    priority: 100,
  );

  static const superscript = OwnedEquationToolDefinition(
    id: 'equation.insert.superscript',
    label: '^',
    tooltip: 'Insert a superscript slot',
    group: OwnedEquationToolGroup.build,
    surface: OwnedEquationToolSurface.pinned,
    priority: 95,
  );

  static const subscript = OwnedEquationToolDefinition(
    id: 'equation.insert.subscript',
    label: '_',
    tooltip: 'Insert a subscript slot',
    group: OwnedEquationToolGroup.build,
    surface: OwnedEquationToolSurface.pinned,
    priority: 94,
  );

  static const text = OwnedEquationToolDefinition(
    id: 'equation.insert.text',
    label: r'\text{}',
    tooltip: 'Insert text mode',
    group: OwnedEquationToolGroup.build,
    surface: OwnedEquationToolSurface.drawer,
    priority: 70,
  );

  static const derivative = OwnedEquationToolDefinition(
    id: 'equation.insert.derivative',
    label: 'd/dt',
    tooltip: 'Insert a derivative template',
    group: OwnedEquationToolGroup.build,
    surface: OwnedEquationToolSurface.drawer,
    priority: 60,
  );

  static const matrix = OwnedEquationToolDefinition(
    id: 'equation.insert.matrix',
    label: 'matrix',
    tooltip: 'Insert a matrix template',
    group: OwnedEquationToolGroup.structures,
    surface: OwnedEquationToolSurface.pinned,
    priority: 92,
  );

  static const aligned = OwnedEquationToolDefinition(
    id: 'equation.insert.aligned',
    label: 'align',
    tooltip: 'Insert an aligned equation template',
    group: OwnedEquationToolGroup.structures,
    surface: OwnedEquationToolSurface.pinned,
    priority: 90,
  );

  static const cases = OwnedEquationToolDefinition(
    id: 'equation.insert.cases',
    label: 'cases',
    tooltip: 'Insert a cases/piecewise template',
    group: OwnedEquationToolGroup.structures,
    surface: OwnedEquationToolSurface.drawer,
    priority: 82,
  );

  static const matrixRow = OwnedEquationToolDefinition(
    id: 'equation.matrix.addRow',
    label: '+ row',
    tooltip: 'Append a row to the current matrix',
    group: OwnedEquationToolGroup.context,
    surface: OwnedEquationToolSurface.contextual,
    priority: 100,
  );

  static const matrixColumn = OwnedEquationToolDefinition(
    id: 'equation.matrix.addColumn',
    label: '+ col',
    tooltip: 'Append a column to every matrix row',
    group: OwnedEquationToolGroup.context,
    surface: OwnedEquationToolSurface.contextual,
    priority: 98,
  );

  static const alignedLine = OwnedEquationToolDefinition(
    id: 'equation.aligned.addLine',
    label: '+ line',
    tooltip: 'Append an aligned equation line',
    group: OwnedEquationToolGroup.context,
    surface: OwnedEquationToolSurface.contextual,
    priority: 100,
  );

  static const alignmentMarker = OwnedEquationToolDefinition(
    id: 'equation.aligned.marker',
    label: '&=',
    tooltip: 'Insert or normalize an alignment marker',
    group: OwnedEquationToolGroup.context,
    surface: OwnedEquationToolSurface.contextual,
    priority: 96,
  );

  static const casesRow = OwnedEquationToolDefinition(
    id: 'equation.cases.addCase',
    label: '+ case',
    tooltip: 'Append another cases row',
    group: OwnedEquationToolGroup.context,
    surface: OwnedEquationToolSurface.contextual,
    priority: 100,
  );

  static const format = OwnedEquationToolDefinition(
    id: 'equation.source.format',
    label: 'Format',
    tooltip: 'Normalize display delimiters and spacing',
    group: OwnedEquationToolGroup.format,
    surface: OwnedEquationToolSurface.pinned,
    priority: 80,
  );

  static const numbered = OwnedEquationToolDefinition(
    id: 'equation.reference.numbered',
    label: 'Numbered',
    tooltip: 'Toggle equation numbering',
    group: OwnedEquationToolGroup.references,
    surface: OwnedEquationToolSurface.pinned,
    priority: 100,
  );

  static const label = OwnedEquationToolDefinition(
    id: 'equation.reference.label',
    label: 'Label',
    tooltip: 'Add or edit the equation label',
    group: OwnedEquationToolGroup.references,
    surface: OwnedEquationToolSurface.pinned,
    priority: 95,
  );

  static const copyReference = OwnedEquationToolDefinition(
    id: 'equation.reference.copy',
    label: 'Copy ref',
    tooltip: 'Copy equation cross-reference text',
    group: OwnedEquationToolGroup.references,
    surface: OwnedEquationToolSurface.drawer,
    priority: 80,
  );

  static const visualTargets = OwnedEquationToolDefinition(
    id: 'equation.navigation.targets',
    label: 'Targets',
    tooltip: 'Open visual source targets for this equation',
    group: OwnedEquationToolGroup.navigation,
    surface: OwnedEquationToolSurface.drawer,
    priority: 70,
  );

  static const all = <OwnedEquationToolDefinition>[
    fraction,
    superscript,
    subscript,
    text,
    derivative,
    matrix,
    aligned,
    cases,
    matrixRow,
    matrixColumn,
    alignedLine,
    alignmentMarker,
    casesRow,
    format,
    numbered,
    label,
    copyReference,
    visualTargets,
  ];

  static List<OwnedEquationToolDefinition> byGroup(OwnedEquationToolGroup group) {
    final tools = all.where((tool) => tool.group == group).toList(growable: false);
    tools.sort((a, b) => b.priority.compareTo(a.priority));
    return tools;
  }
}
