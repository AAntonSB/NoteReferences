import 'dart:math' as math;

/// Lightweight structural model for Premium Writer display-equation authoring.
///
/// This is intentionally smaller than a full TeX engine. Its job is to give the
/// owned editor a stable source-range tree for the math structures we already
/// author interactively: commands with required groups, fractions, roots,
/// super/subscripts, text groups, and matrix/aligned/cases environments. The
/// renderer can still rely on flutter_math_fork; this model is for authoring
/// behavior, diagnostics, slot navigation, preview-to-source jumps, and future
/// visual editing tools.
class OwnedEquationStructureModel {
  const OwnedEquationStructureModel({
    required this.rawSource,
    required this.bodyStartOffset,
    required this.bodyEndOffset,
    required this.root,
    required this.environments,
  });

  final String rawSource;
  final int bodyStartOffset;
  final int bodyEndOffset;
  final OwnedEquationStructureNode root;
  final List<OwnedEquationEnvironmentStructure> environments;

  String get bodySource => rawSource.substring(
        bodyStartOffset.clamp(0, rawSource.length).toInt(),
        bodyEndOffset.clamp(bodyStartOffset, rawSource.length).toInt(),
      );

  static OwnedEquationStructureModel parse(String rawSource) {
    final delimiter = _displayDelimiterFor(rawSource);
    final bodyStart = delimiter?.bodyStart ?? 0;
    final bodyEnd = delimiter?.bodyEnd ?? rawSource.length;
    final parser = _OwnedEquationStructureParser(
      rawSource,
      bodyStart.clamp(0, rawSource.length).toInt(),
      bodyEnd.clamp(bodyStart, rawSource.length).toInt(),
    );
    return parser.parse();
  }

  OwnedEquationStructureNode? smallestNodeContaining(int offset) {
    return root.smallestNodeContaining(offset);
  }

  OwnedEquationEnvironmentStructure? environmentForOffset(
    Set<String> supportedEnvironments,
    int? activeOffset,
  ) {
    final supported = environments
        .where((environment) => supportedEnvironments.contains(environment.environment))
        .toList(growable: false);
    if (supported.isEmpty) return null;

    final offset = activeOffset?.clamp(0, rawSource.length).toInt();
    if (offset != null) {
      final containing = supported
          .where((environment) => offset >= environment.beginStart && offset <= environment.endEnd)
          .toList(growable: false);
      if (containing.isNotEmpty) {
        containing.sort((a, b) => (a.endEnd - a.beginStart).compareTo(b.endEnd - b.beginStart));
        return containing.first;
      }
    }

    final sorted = List<OwnedEquationEnvironmentStructure>.from(supported)
      ..sort((a, b) => a.beginStart.compareTo(b.beginStart));
    return sorted.first;
  }

  List<int> slotOffsets() {
    final slots = <int>{};
    void visit(OwnedEquationStructureNode node) {
      if (node.kind == OwnedEquationStructureKind.group &&
          node.contentStart != null &&
          node.contentEnd != null &&
          node.contentStart == node.contentEnd) {
        slots.add(node.contentStart!);
      }
      if ((node.kind == OwnedEquationStructureKind.superscript ||
              node.kind == OwnedEquationStructureKind.subscript) &&
          node.contentStart != null &&
          node.contentEnd != null &&
          node.contentStart == node.contentEnd) {
        slots.add(node.contentStart!);
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    for (final environment in environments) {
      for (final row in environment.rows) {
        for (final cell in row.cells) {
          if (cell.text.trim().isEmpty) slots.add(cell.caretOffset);
        }
      }
    }
    final sorted = slots.toList()..sort();
    return sorted;
  }

  static _EquationDisplayDelimiter? _displayDelimiterFor(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final leadingWhitespace = raw.indexOf(value);
    if (value.startsWith(r'\[')) {
      final closeIndex = value.lastIndexOf(r'\]');
      final complete = closeIndex >= 2 && closeIndex + 2 == value.length;
      return _EquationDisplayDelimiter(
        bodyStart: leadingWhitespace + 2,
        bodyEnd: complete ? leadingWhitespace + closeIndex : raw.length,
      );
    }
    if (value.startsWith(r'\(')) {
      final closeIndex = value.lastIndexOf(r'\)');
      final complete = closeIndex >= 2 && closeIndex + 2 == value.length;
      return _EquationDisplayDelimiter(
        bodyStart: leadingWhitespace + 2,
        bodyEnd: complete ? leadingWhitespace + closeIndex : raw.length,
      );
    }
    if (value.startsWith(r'$$')) {
      final closeIndex = value.lastIndexOf(r'$$');
      final complete = closeIndex >= 2 && closeIndex + 2 == value.length;
      return _EquationDisplayDelimiter(
        bodyStart: leadingWhitespace + 2,
        bodyEnd: complete ? leadingWhitespace + closeIndex : raw.length,
      );
    }
    return null;
  }
}

class OwnedEquationStructureNode {
  const OwnedEquationStructureNode({
    required this.kind,
    required this.sourceStart,
    required this.sourceEnd,
    this.contentStart,
    this.contentEnd,
    this.command,
    this.environment,
    this.children = const <OwnedEquationStructureNode>[],
  });

  final OwnedEquationStructureKind kind;
  final int sourceStart;
  final int sourceEnd;
  final int? contentStart;
  final int? contentEnd;
  final String? command;
  final String? environment;
  final List<OwnedEquationStructureNode> children;

  bool containsOffset(int offset) => offset >= sourceStart && offset <= sourceEnd;

  OwnedEquationStructureNode? smallestNodeContaining(int offset) {
    if (!containsOffset(offset)) return null;
    for (final child in children) {
      final nested = child.smallestNodeContaining(offset);
      if (nested != null) return nested;
    }
    return this;
  }
}

enum OwnedEquationStructureKind {
  root,
  textRun,
  command,
  group,
  fraction,
  squareRoot,
  textCommand,
  environment,
  superscript,
  subscript,
  operatorToken,
  symbol,
}

class OwnedEquationEnvironmentStructure {
  const OwnedEquationEnvironmentStructure({
    required this.environment,
    required this.beginStart,
    required this.contentStart,
    required this.contentEnd,
    required this.endEnd,
    required this.rows,
  });

  final String environment;
  final int beginStart;
  final int contentStart;
  final int contentEnd;
  final int endEnd;
  final List<OwnedEquationEnvironmentRow> rows;

  int get rowCount => math.max(1, rows.length);

  int get columnCount {
    if (rows.isEmpty) return 1;
    return rows
        .map((row) => math.max(1, row.cells.length))
        .fold<int>(1, (previous, value) => math.max(previous, value).toInt());
  }

  bool get isMatrix => const <String>{
        'matrix',
        'pmatrix',
        'bmatrix',
        'vmatrix',
        'Vmatrix',
        'smallmatrix',
      }.contains(environment);

  bool get isAligned => const <String>{
        'aligned',
        'alignedat',
        'split',
        'gathered',
      }.contains(environment);

  bool get isCases => environment == 'cases';
}

class OwnedEquationEnvironmentRow {
  const OwnedEquationEnvironmentRow({
    required this.start,
    required this.end,
    required this.cells,
  });

  final int start;
  final int end;
  final List<OwnedEquationEnvironmentCell> cells;
}

class OwnedEquationEnvironmentCell {
  const OwnedEquationEnvironmentCell({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;

  int get caretOffset {
    final trimmedLeft = text.length - text.trimLeft().length;
    return math.min(end, start + trimmedLeft);
  }
}

class _OwnedEquationStructureParser {
  _OwnedEquationStructureParser(this.source, this.bodyStart, this.bodyEnd);

  final String source;
  final int bodyStart;
  final int bodyEnd;
  final environments = <OwnedEquationEnvironmentStructure>[];

  OwnedEquationStructureModel parse() {
    final children = _parseNodes(bodyStart, bodyEnd);
    return OwnedEquationStructureModel(
      rawSource: source,
      bodyStartOffset: bodyStart,
      bodyEndOffset: bodyEnd,
      root: OwnedEquationStructureNode(
        kind: OwnedEquationStructureKind.root,
        sourceStart: bodyStart,
        sourceEnd: bodyEnd,
        contentStart: bodyStart,
        contentEnd: bodyEnd,
        children: children,
      ),
      environments: List<OwnedEquationEnvironmentStructure>.unmodifiable(environments),
    );
  }

  List<OwnedEquationStructureNode> _parseNodes(int start, int end) {
    final nodes = <OwnedEquationStructureNode>[];
    var i = start.clamp(0, source.length).toInt();
    final limit = end.clamp(i, source.length).toInt();
    while (i < limit) {
      final unit = source.codeUnitAt(i);
      if (_isWhitespace(unit)) {
        i++;
        continue;
      }

      if (unit == _backslash) {
        final parsed = _parseCommandOrEnvironment(i, limit);
        if (parsed != null) {
          nodes.add(parsed.node);
          i = parsed.end;
          continue;
        }
      }

      if (source[i] == '{') {
        final group = _readBalancedGroup(i, limit);
        if (group != null) {
          nodes.add(OwnedEquationStructureNode(
            kind: OwnedEquationStructureKind.group,
            sourceStart: group.start,
            sourceEnd: group.end,
            contentStart: group.contentStart,
            contentEnd: group.contentEnd,
            children: _parseNodes(group.contentStart, group.contentEnd),
          ));
          i = group.end;
          continue;
        }
      }

      if (source[i] == '^' || source[i] == '_') {
        final parsed = _parseScript(i, limit);
        nodes.add(parsed.node);
        i = parsed.end;
        continue;
      }

      if (_isAlphaNumeric(unit)) {
        final startRun = i;
        while (i < limit && _isAlphaNumeric(source.codeUnitAt(i))) {
          i++;
        }
        nodes.add(OwnedEquationStructureNode(
          kind: OwnedEquationStructureKind.textRun,
          sourceStart: startRun,
          sourceEnd: i,
          contentStart: startRun,
          contentEnd: i,
        ));
        continue;
      }

      nodes.add(OwnedEquationStructureNode(
        kind: _operatorChars.contains(source[i])
            ? OwnedEquationStructureKind.operatorToken
            : OwnedEquationStructureKind.symbol,
        sourceStart: i,
        sourceEnd: i + 1,
        contentStart: i,
        contentEnd: i + 1,
      ));
      i++;
    }
    return List<OwnedEquationStructureNode>.unmodifiable(nodes);
  }

  _ParsedNode? _parseCommandOrEnvironment(int slashIndex, int limit) {
    final commandEnd = _readCommandEnd(slashIndex, limit);
    if (commandEnd <= slashIndex + 1) {
      return _ParsedNode(
        OwnedEquationStructureNode(
          kind: OwnedEquationStructureKind.symbol,
          sourceStart: slashIndex,
          sourceEnd: math.min(slashIndex + 1, limit),
          contentStart: slashIndex,
          contentEnd: math.min(slashIndex + 1, limit),
        ),
        math.min(slashIndex + 1, limit),
      );
    }

    final command = source.substring(slashIndex + 1, commandEnd);
    if (command == 'begin') {
      final nameGroup = _readBalancedGroup(_skipWhitespace(commandEnd, limit), limit);
      if (nameGroup == null) {
        return _ParsedNode(
          OwnedEquationStructureNode(
            kind: OwnedEquationStructureKind.command,
            sourceStart: slashIndex,
            sourceEnd: commandEnd,
            command: command,
          ),
          commandEnd,
        );
      }
      final environment = source.substring(nameGroup.contentStart, nameGroup.contentEnd).trim();
      final endMatch = _findEnvironmentEnd(environment, nameGroup.end, limit);
      final contentEnd = endMatch?.start ?? limit;
      final endEnd = endMatch?.end ?? limit;
      final children = _parseNodes(nameGroup.end, contentEnd);
      final rows = _parseEnvironmentRows(nameGroup.end, contentEnd);
      final structure = OwnedEquationEnvironmentStructure(
        environment: environment,
        beginStart: slashIndex,
        contentStart: nameGroup.end,
        contentEnd: contentEnd,
        endEnd: endEnd,
        rows: rows.isEmpty
            ? <OwnedEquationEnvironmentRow>[
                OwnedEquationEnvironmentRow(
                  start: nameGroup.end,
                  end: contentEnd,
                  cells: <OwnedEquationEnvironmentCell>[
                    OwnedEquationEnvironmentCell(start: nameGroup.end, end: nameGroup.end, text: ''),
                  ],
                ),
              ]
            : rows,
      );
      environments.add(structure);
      return _ParsedNode(
        OwnedEquationStructureNode(
          kind: OwnedEquationStructureKind.environment,
          sourceStart: slashIndex,
          sourceEnd: endEnd,
          contentStart: nameGroup.end,
          contentEnd: contentEnd,
          command: command,
          environment: environment,
          children: children,
        ),
        endEnd,
      );
    }

    if (command == 'frac' || command == 'dfrac' || command == 'tfrac' || command == 'binom') {
      final first = _readBalancedGroup(_skipWhitespace(commandEnd, limit), limit);
      final second = first == null ? null : _readBalancedGroup(_skipWhitespace(first.end, limit), limit);
      if (first != null && second != null) {
        return _ParsedNode(
          OwnedEquationStructureNode(
            kind: OwnedEquationStructureKind.fraction,
            sourceStart: slashIndex,
            sourceEnd: second.end,
            contentStart: first.contentStart,
            contentEnd: second.contentEnd,
            command: command,
            children: <OwnedEquationStructureNode>[
              _groupNode(first),
              _groupNode(second),
            ],
          ),
          second.end,
        );
      }
    }

    if (_singleGroupCommands.contains(command)) {
      final group = _readBalancedGroup(_skipWhitespace(commandEnd, limit), limit);
      if (group != null) {
        final kind = command == 'sqrt'
            ? OwnedEquationStructureKind.squareRoot
            : command == 'text' || command == 'mathrm' || command == 'mathbf' || command == 'mathit'
                ? OwnedEquationStructureKind.textCommand
                : OwnedEquationStructureKind.command;
        return _ParsedNode(
          OwnedEquationStructureNode(
            kind: kind,
            sourceStart: slashIndex,
            sourceEnd: group.end,
            contentStart: group.contentStart,
            contentEnd: group.contentEnd,
            command: command,
            children: <OwnedEquationStructureNode>[_groupNode(group)],
          ),
          group.end,
        );
      }
    }

    return _ParsedNode(
      OwnedEquationStructureNode(
        kind: OwnedEquationStructureKind.command,
        sourceStart: slashIndex,
        sourceEnd: commandEnd,
        contentStart: slashIndex,
        contentEnd: commandEnd,
        command: command,
      ),
      commandEnd,
    );
  }

  _ParsedNode _parseScript(int offset, int limit) {
    final marker = source[offset];
    final afterMarker = _skipWhitespace(offset + 1, limit);
    final group = afterMarker < limit && source[afterMarker] == '{'
        ? _readBalancedGroup(afterMarker, limit)
        : null;
    if (group != null) {
      return _ParsedNode(
        OwnedEquationStructureNode(
          kind: marker == '^'
              ? OwnedEquationStructureKind.superscript
              : OwnedEquationStructureKind.subscript,
          sourceStart: offset,
          sourceEnd: group.end,
          contentStart: group.contentStart,
          contentEnd: group.contentEnd,
          children: <OwnedEquationStructureNode>[_groupNode(group)],
        ),
        group.end,
      );
    }
    final end = math.min(afterMarker + 1, limit);
    return _ParsedNode(
      OwnedEquationStructureNode(
        kind: marker == '^'
            ? OwnedEquationStructureKind.superscript
            : OwnedEquationStructureKind.subscript,
        sourceStart: offset,
        sourceEnd: end,
        contentStart: afterMarker,
        contentEnd: end,
        children: afterMarker < limit ? _parseNodes(afterMarker, end) : const <OwnedEquationStructureNode>[],
      ),
      end,
    );
  }

  OwnedEquationStructureNode _groupNode(_BalancedSourceGroup group) {
    return OwnedEquationStructureNode(
      kind: OwnedEquationStructureKind.group,
      sourceStart: group.start,
      sourceEnd: group.end,
      contentStart: group.contentStart,
      contentEnd: group.contentEnd,
      children: _parseNodes(group.contentStart, group.contentEnd),
    );
  }

  _EnvironmentEndMatch? _findEnvironmentEnd(String environment, int start, int limit) {
    if (environment.isEmpty) return null;
    var depth = 1;
    var i = start;
    while (i < limit) {
      if (source.codeUnitAt(i) != _backslash) {
        i++;
        continue;
      }
      final commandEnd = _readCommandEnd(i, limit);
      if (commandEnd <= i + 1) {
        i++;
        continue;
      }
      final command = source.substring(i + 1, commandEnd);
      if (command != 'begin' && command != 'end') {
        i = commandEnd;
        continue;
      }
      final group = _readBalancedGroup(_skipWhitespace(commandEnd, limit), limit);
      if (group == null) {
        i = commandEnd;
        continue;
      }
      final name = source.substring(group.contentStart, group.contentEnd).trim();
      if (name == environment) {
        if (command == 'begin') {
          depth++;
        } else {
          depth--;
          if (depth == 0) return _EnvironmentEndMatch(i, group.end);
        }
      }
      i = group.end;
    }
    return null;
  }

  List<OwnedEquationEnvironmentRow> _parseEnvironmentRows(int contentStart, int contentEnd) {
    final rows = <OwnedEquationEnvironmentRow>[];
    var rowStart = contentStart;
    var i = contentStart;
    var braceDepth = 0;
    while (i < contentEnd) {
      final char = source[i];
      if (char == '{') {
        braceDepth++;
      } else if (char == '}') {
        braceDepth = math.max(0, braceDepth - 1).toInt();
      }
      final isRowSeparator = braceDepth == 0 &&
          i + 1 < contentEnd &&
          source.codeUnitAt(i) == _backslash &&
          source.codeUnitAt(i + 1) == _backslash;
      if (isRowSeparator) {
        rows.add(_parseEnvironmentRow(rowStart, i));
        i += 2;
        rowStart = i;
        continue;
      }
      i++;
    }
    rows.add(_parseEnvironmentRow(rowStart, contentEnd));
    return rows;
  }

  OwnedEquationEnvironmentRow _parseEnvironmentRow(int rowStart, int rowEnd) {
    final cells = <OwnedEquationEnvironmentCell>[];
    var cellStart = rowStart;
    var i = rowStart;
    var braceDepth = 0;
    while (i < rowEnd) {
      final char = source[i];
      if (char == '{') {
        braceDepth++;
      } else if (char == '}') {
        braceDepth = math.max(0, braceDepth - 1).toInt();
      }
      final escaped = i > rowStart && source.codeUnitAt(i - 1) == _backslash;
      if (char == '&' && !escaped && braceDepth == 0) {
        cells.add(OwnedEquationEnvironmentCell(
          start: cellStart,
          end: i,
          text: source.substring(cellStart, i),
        ));
        cellStart = i + 1;
      }
      i++;
    }
    cells.add(OwnedEquationEnvironmentCell(
      start: cellStart,
      end: rowEnd,
      text: source.substring(cellStart, rowEnd),
    ));
    return OwnedEquationEnvironmentRow(start: rowStart, end: rowEnd, cells: cells);
  }

  _BalancedSourceGroup? _readBalancedGroup(int offset, int limit) {
    var i = _skipWhitespace(offset, limit);
    if (i >= limit || source[i] != '{') return null;
    var depth = 0;
    for (var cursor = i; cursor < limit; cursor++) {
      final char = source[cursor];
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return _BalancedSourceGroup(i, cursor + 1);
      }
    }
    return null;
  }

  int _readCommandEnd(int slashIndex, int limit) {
    var end = math.min(slashIndex + 1, limit);
    while (end < limit && _isCommandLetter(source.codeUnitAt(end))) {
      end++;
    }
    return end;
  }

  int _skipWhitespace(int start, int limit) {
    var i = start;
    while (i < limit && _isWhitespace(source.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  static bool _isWhitespace(int unit) => unit == 32 || unit == 9 || unit == 10 || unit == 13;

  static bool _isAlphaNumeric(int unit) {
    return (unit >= 48 && unit <= 57) ||
        (unit >= 65 && unit <= 90) ||
        (unit >= 97 && unit <= 122);
  }

  static bool _isCommandLetter(int unit) {
    return (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  }

  static const int _backslash = 92;

  static const Set<String> _operatorChars = <String>{
    '+',
    '-',
    '=',
    '<',
    '>',
    '*',
    '/',
    '|',
    ',',
    '.',
    ':',
    ';',
  };

  static const Set<String> _singleGroupCommands = <String>{
    'sqrt',
    'text',
    'mathrm',
    'mathbf',
    'mathit',
    'mathcal',
    'operatorname',
    'overbrace',
    'underbrace',
    'overline',
    'underline',
    'hat',
    'bar',
    'vec',
    'dot',
    'ddot',
  };
}

class _EquationDisplayDelimiter {
  const _EquationDisplayDelimiter({
    required this.bodyStart,
    required this.bodyEnd,
  });

  final int bodyStart;
  final int bodyEnd;
}

class _ParsedNode {
  const _ParsedNode(this.node, this.end);

  final OwnedEquationStructureNode node;
  final int end;
}

class _BalancedSourceGroup {
  const _BalancedSourceGroup(this.start, this.end);

  final int start;
  final int end;

  int get contentStart => math.min(start + 1, end);

  int get contentEnd => math.max(start + 1, end - 1);
}

class _EnvironmentEndMatch {
  const _EnvironmentEndMatch(this.start, this.end);

  final int start;
  final int end;
}
