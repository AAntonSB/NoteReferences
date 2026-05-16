/// Lightweight source model and diagnostics for owned display-equation editing.
///
/// This is deliberately not a full TeX parser. It is a pragmatic authoring
/// model for the Premium Writer equation surface: normalize display delimiters,
/// extract a renderable math body, and catch the structural mistakes that make
/// authoring feel opaque (unmatched braces, malformed common commands, bad
/// begin/end pairs, and unsupported environments). A later phase can replace or
/// augment this with a structure tree without changing the equation surface API.
class OwnedEquationSourceModel {
  const OwnedEquationSourceModel({
    required this.rawSource,
    required this.displayBody,
    required this.normalizedSource,
    required this.bodyStartOffset,
    required this.bodyEndOffset,
    required this.diagnostics,
  });

  final String rawSource;
  final String displayBody;
  final String normalizedSource;
  final int bodyStartOffset;
  final int bodyEndOffset;
  final List<OwnedEquationDiagnostic> diagnostics;

  bool get hasDiagnostics => diagnostics.isNotEmpty;

  bool get hasErrors => diagnostics.any((diagnostic) => diagnostic.severity == OwnedEquationDiagnosticSeverity.error);

  Iterable<OwnedEquationDiagnostic> get errors =>
      diagnostics.where((diagnostic) => diagnostic.severity == OwnedEquationDiagnosticSeverity.error);

  Iterable<OwnedEquationDiagnostic> get warnings =>
      diagnostics.where((diagnostic) => diagnostic.severity == OwnedEquationDiagnosticSeverity.warning);

  /// Parse and validate raw equation source as typed in the focused source lane.
  static OwnedEquationSourceModel analyze(String rawSource) {
    final safeRaw = _sanitizeUtf16(rawSource);
    final delimiter = _displayDelimiterFor(safeRaw);
    final bodyStart = delimiter?.bodyStart ?? 0;
    final bodyEnd = delimiter?.bodyEnd ?? safeRaw.length;
    final body = safeRaw.substring(bodyStart, bodyEnd).trim();
    final diagnostics = <OwnedEquationDiagnostic>[];

    if (safeRaw.trim().isEmpty) {
      diagnostics.add(const OwnedEquationDiagnostic(
        message: 'Equation is empty.',
        start: 0,
        end: 0,
        severity: OwnedEquationDiagnosticSeverity.warning,
      ));
    }

    if (delimiter == null && safeRaw.trim().isNotEmpty) {
      diagnostics.add(OwnedEquationDiagnostic(
        message: r'Display equations should use \[ ... \]. Use Format to normalize the source.',
        start: 0,
        end: safeRaw.length.clamp(0, 8).toInt(),
        severity: OwnedEquationDiagnosticSeverity.info,
      ));
    } else if (delimiter != null && !delimiter.complete) {
      diagnostics.add(OwnedEquationDiagnostic(
        message: 'Missing closing display delimiter ${delimiter.close}.',
        start: delimiter.openStart,
        end: delimiter.openEnd,
        severity: OwnedEquationDiagnosticSeverity.error,
      ));
    }

    diagnostics.addAll(_braceDiagnostics(safeRaw, bodyStart, bodyEnd));
    diagnostics.addAll(_environmentDiagnostics(safeRaw, bodyStart, bodyEnd));
    diagnostics.addAll(_commandDiagnostics(safeRaw, bodyStart, bodyEnd));

    diagnostics.sort((a, b) {
      final severityOrder = b.severity.index.compareTo(a.severity.index);
      if (severityOrder != 0) return severityOrder;
      return a.start.compareTo(b.start);
    });

    return OwnedEquationSourceModel(
      rawSource: safeRaw,
      displayBody: body,
      normalizedSource: normalizeDisplaySource(safeRaw),
      bodyStartOffset: bodyStart,
      bodyEndOffset: bodyEnd,
      diagnostics: diagnostics,
    );
  }

  /// Normalize a source string into a display equation with stable delimiters.
  static String normalizeDisplaySource(String rawSource) {
    final safeRaw = _sanitizeUtf16(rawSource).trim();
    if (safeRaw.isEmpty) return r'\[\]';
    final delimiter = _displayDelimiterFor(safeRaw);
    final body = delimiter == null
        ? safeRaw
        : safeRaw.substring(delimiter.bodyStart, delimiter.bodyEnd.clamp(delimiter.bodyStart, safeRaw.length).toInt());
    final trimmedBody = body.trim();
    return trimmedBody.isEmpty ? r'\[\]' : '\\[\n$trimmedBody\n\\]';
  }

  static _EquationDisplayDelimiter? _displayDelimiterFor(String raw) {
    final value = raw.trim();
    final leadingWhitespace = raw.indexOf(value);
    if (value.startsWith(r'\[')) {
      final closeIndex = value.lastIndexOf(r'\]');
      final complete = closeIndex >= 2 && closeIndex + 2 == value.length;
      return _EquationDisplayDelimiter(
        open: r'\[',
        close: r'\]',
        openStart: leadingWhitespace,
        openEnd: leadingWhitespace + 2,
        bodyStart: leadingWhitespace + 2,
        bodyEnd: complete ? leadingWhitespace + closeIndex : raw.length,
        complete: complete,
      );
    }
    if (value.startsWith(r'\(')) {
      final closeIndex = value.lastIndexOf(r'\)');
      final complete = closeIndex >= 2 && closeIndex + 2 == value.length;
      return _EquationDisplayDelimiter(
        open: r'\(',
        close: r'\)',
        openStart: leadingWhitespace,
        openEnd: leadingWhitespace + 2,
        bodyStart: leadingWhitespace + 2,
        bodyEnd: complete ? leadingWhitespace + closeIndex : raw.length,
        complete: complete,
      );
    }
    if (value.startsWith(r'$$')) {
      final closeIndex = value.lastIndexOf(r'$$');
      final complete = closeIndex >= 2 && closeIndex + 2 == value.length;
      return _EquationDisplayDelimiter(
        open: r'$$',
        close: r'$$',
        openStart: leadingWhitespace,
        openEnd: leadingWhitespace + 2,
        bodyStart: leadingWhitespace + 2,
        bodyEnd: complete ? leadingWhitespace + closeIndex : raw.length,
        complete: complete,
      );
    }
    return null;
  }

  static List<OwnedEquationDiagnostic> _braceDiagnostics(String source, int bodyStart, int bodyEnd) {
    final diagnostics = <OwnedEquationDiagnostic>[];
    final stack = <_DelimiterToken>[];
    final pairs = <String, String>{'{': '}', '[': ']', '(': ')'};
    final reversePairs = <String, String>{'}': '{', ']': '[', ')': '('};
    for (var i = bodyStart; i < bodyEnd; i++) {
      final char = source[i];
      if (pairs.containsKey(char)) {
        stack.add(_DelimiterToken(char, i));
        continue;
      }
      final expectedOpen = reversePairs[char];
      if (expectedOpen == null) continue;
      if (stack.isEmpty || stack.last.char != expectedOpen) {
        diagnostics.add(OwnedEquationDiagnostic(
          message: 'Unexpected closing delimiter "$char".',
          start: i,
          end: i + 1,
          severity: OwnedEquationDiagnosticSeverity.error,
        ));
        continue;
      }
      stack.removeLast();
    }
    for (final token in stack.reversed) {
      diagnostics.add(OwnedEquationDiagnostic(
        message: 'Missing closing delimiter for "${token.char}".',
        start: token.index,
        end: token.index + 1,
        severity: OwnedEquationDiagnosticSeverity.error,
      ));
    }
    return diagnostics;
  }

  static List<OwnedEquationDiagnostic> _environmentDiagnostics(String source, int bodyStart, int bodyEnd) {
    final diagnostics = <OwnedEquationDiagnostic>[];
    final stack = <_EnvironmentToken>[];
    var i = bodyStart;
    while (i < bodyEnd) {
      if (!source.startsWith(r'\begin', i) && !source.startsWith(r'\end', i)) {
        i++;
        continue;
      }
      final isBegin = source.startsWith(r'\begin', i);
      final commandEnd = i + (isBegin ? 6 : 4);
      final group = _readRequiredGroup(source, commandEnd, bodyEnd);
      if (group == null) {
        diagnostics.add(OwnedEquationDiagnostic(
          message: isBegin ? r'\begin needs an environment name.' : r'\end needs an environment name.',
          start: i,
          end: commandEnd,
          severity: OwnedEquationDiagnosticSeverity.error,
        ));
        i = commandEnd;
        continue;
      }
      final environment = source.substring(group.contentStart, group.contentEnd).trim();
      if (environment.isEmpty) {
        diagnostics.add(OwnedEquationDiagnostic(
          message: 'Environment name is empty.',
          start: group.openIndex,
          end: group.closeIndex + 1,
          severity: OwnedEquationDiagnosticSeverity.error,
        ));
      } else if (!_supportedEnvironments.contains(environment)) {
        diagnostics.add(OwnedEquationDiagnostic(
          message: 'Environment "$environment" may not be supported by the current renderer.',
          start: group.contentStart,
          end: group.contentEnd,
          severity: OwnedEquationDiagnosticSeverity.warning,
        ));
      }
      if (isBegin) {
        stack.add(_EnvironmentToken(environment, i, group.contentStart, group.contentEnd));
      } else if (stack.isEmpty) {
        diagnostics.add(OwnedEquationDiagnostic(
          message: 'Found \\end{$environment} without a matching \\begin.',
          start: i,
          end: group.closeIndex + 1,
          severity: OwnedEquationDiagnosticSeverity.error,
        ));
      } else if (stack.last.name != environment) {
        final open = stack.last;
        diagnostics.add(OwnedEquationDiagnostic(
          message: 'Environment mismatch: opened ${open.name}, closed $environment.',
          start: i,
          end: group.closeIndex + 1,
          severity: OwnedEquationDiagnosticSeverity.error,
        ));
      } else {
        stack.removeLast();
      }
      i = group.closeIndex + 1;
    }
    for (final token in stack.reversed) {
      diagnostics.add(OwnedEquationDiagnostic(
        message: 'Missing \\end{${token.name}}.',
        start: token.start,
        end: token.nameEnd,
        severity: OwnedEquationDiagnosticSeverity.error,
      ));
    }
    return diagnostics;
  }

  static List<OwnedEquationDiagnostic> _commandDiagnostics(String source, int bodyStart, int bodyEnd) {
    final diagnostics = <OwnedEquationDiagnostic>[];
    var i = bodyStart;
    while (i < bodyEnd) {
      if (source[i] != '\\') {
        i++;
        continue;
      }
      final commandRange = _readCommand(source, i, bodyEnd);
      if (commandRange == null) {
        i++;
        continue;
      }
      final command = source.substring(commandRange.start + 1, commandRange.end);
      final requiredGroups = _requiredGroupCount[command] ?? 0;
      var cursor = commandRange.end;
      var foundGroups = 0;
      for (var groupIndex = 0; groupIndex < requiredGroups; groupIndex++) {
        cursor = _skipWhitespace(source, cursor, bodyEnd);
        final group = _readRequiredGroup(source, cursor, bodyEnd);
        if (group == null) {
          diagnostics.add(OwnedEquationDiagnostic(
            message: '\\\\$command needs $requiredGroups argument${requiredGroups == 1 ? '' : 's'}.',
            start: commandRange.start,
            end: commandRange.end,
            severity: OwnedEquationDiagnosticSeverity.error,
          ));
          break;
        }
        foundGroups++;
        if (source.substring(group.contentStart, group.contentEnd).trim().isEmpty && command != 'text') {
          diagnostics.add(OwnedEquationDiagnostic(
            message: 'Empty argument for \\$command.',
            start: group.openIndex,
            end: group.closeIndex + 1,
            severity: OwnedEquationDiagnosticSeverity.warning,
          ));
        }
        cursor = group.closeIndex + 1;
      }
      if (requiredGroups > 0 && foundGroups == requiredGroups) {
        i = cursor;
      } else {
        i = commandRange.end;
      }
    }
    return diagnostics;
  }

  static TextRange? _readCommand(String source, int slashIndex, int limit) {
    if (slashIndex < 0 || slashIndex >= limit || source[slashIndex] != '\\') return null;
    var end = slashIndex + 1;
    while (end < limit) {
      final unit = source.codeUnitAt(end);
      final isLetter = (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
      if (!isLetter) break;
      end++;
    }
    // Do not diagnose single-character control symbols (\[, \], \{, etc.)
    // as command words. They are valid source syntax or still-in-progress user
    // input, and autocomplete should be suggestive rather than assumptive.
    if (end == slashIndex + 1) return null;
    return TextRange(start: slashIndex, end: end);
  }

  static _RequiredGroup? _readRequiredGroup(String source, int start, int limit) {
    var i = _skipWhitespace(source, start, limit);
    if (i >= limit || source[i] != '{') return null;
    var depth = 0;
    for (var cursor = i; cursor < limit; cursor++) {
      final char = source[cursor];
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) {
          return _RequiredGroup(
            openIndex: i,
            closeIndex: cursor,
            contentStart: i + 1,
            contentEnd: cursor,
          );
        }
      }
    }
    return null;
  }

  static int _skipWhitespace(String source, int start, int limit) {
    var i = start;
    while (i < limit) {
      final unit = source.codeUnitAt(i);
      if (unit != 32 && unit != 9 && unit != 10 && unit != 13) break;
      i++;
    }
    return i;
  }

  static String _sanitizeUtf16(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
        if (i + 1 < text.length) {
          final next = text.codeUnitAt(i + 1);
          if (next >= 0xDC00 && next <= 0xDFFF) {
            buffer.writeCharCode(codeUnit);
            i++;
            buffer.writeCharCode(next);
            continue;
          }
        }
        buffer.write('�');
        continue;
      }
      if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
        buffer.write('�');
        continue;
      }
      buffer.writeCharCode(codeUnit);
    }
    return buffer.toString();
  }

  static const Set<String> _supportedEnvironments = <String>{
    'aligned',
    'alignedat',
    'array',
    'bmatrix',
    'cases',
    'gathered',
    'matrix',
    'pmatrix',
    'smallmatrix',
    'split',
    'vmatrix',
    'Vmatrix',
  };

  static const Map<String, int> _requiredGroupCount = <String, int>{
    'frac': 2,
    'dfrac': 2,
    'tfrac': 2,
    'binom': 2,
    'sqrt': 1,
    'text': 1,
    'mathrm': 1,
    'mathbf': 1,
    'mathit': 1,
    'mathcal': 1,
    'operatorname': 1,
    'begin': 1,
    'end': 1,
    'overbrace': 1,
    'underbrace': 1,
    'overline': 1,
    'underline': 1,
    'hat': 1,
    'bar': 1,
    'vec': 1,
    'dot': 1,
    'ddot': 1,
  };
}

class OwnedEquationDiagnostic {
  const OwnedEquationDiagnostic({
    required this.message,
    required this.start,
    required this.end,
    required this.severity,
  });

  final String message;
  final int start;
  final int end;
  final OwnedEquationDiagnosticSeverity severity;

  bool intersects(int tokenStart, int tokenEnd) {
    final safeEnd = end <= start ? start + 1 : end;
    return tokenStart < safeEnd && tokenEnd > start;
  }
}

enum OwnedEquationDiagnosticSeverity {
  info,
  warning,
  error,
}

class _EquationDisplayDelimiter {
  const _EquationDisplayDelimiter({
    required this.open,
    required this.close,
    required this.openStart,
    required this.openEnd,
    required this.bodyStart,
    required this.bodyEnd,
    required this.complete,
  });

  final String open;
  final String close;
  final int openStart;
  final int openEnd;
  final int bodyStart;
  final int bodyEnd;
  final bool complete;
}

class _DelimiterToken {
  const _DelimiterToken(this.char, this.index);

  final String char;
  final int index;
}

class _EnvironmentToken {
  const _EnvironmentToken(this.name, this.start, this.nameStart, this.nameEnd);

  final String name;
  final int start;
  final int nameStart;
  final int nameEnd;
}

class _RequiredGroup {
  const _RequiredGroup({
    required this.openIndex,
    required this.closeIndex,
    required this.contentStart,
    required this.contentEnd,
  });

  final int openIndex;
  final int closeIndex;
  final int contentStart;
  final int contentEnd;
}

class TextRange {
  const TextRange({required this.start, required this.end});

  final int start;
  final int end;
}
