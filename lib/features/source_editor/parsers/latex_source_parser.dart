import '../core/source_document_block.dart';
import '../core/source_document_parser.dart';
import '../core/source_range.dart';
import '../latex/latex_macro_registry.dart';

/// Phase 2 LaTeX parser for the source-aware editor kernel.
///
/// This parser is intentionally conservative. It renders structures only when
/// it can identify stable source ranges; otherwise it emits editable source
/// fallback blocks. The source string remains canonical.
class LatexSourceParser extends SourceDocumentParser {
  LatexSourceParser({LatexMacroRegistry? macroRegistry})
      : macroRegistry = macroRegistry ?? LatexMacroRegistry.defaults();

  final LatexMacroRegistry macroRegistry;

  @override
  ParsedSourceDocument parse(SourceParseContext context) {
    final source = context.source;
    if (source.isEmpty) {
      return ParsedSourceDocument(
        source: source,
        blocks: const <SourceDocumentBlock>[],
      );
    }

    final blocks = <SourceDocumentBlock>[];
    final errors = <String>[];
    var index = 0;
    var blockNumber = 0;

    while (index < source.length) {
      if (_isBlankAt(source, index)) {
        final end = _consumeBlank(source, index);
        blocks.add(
          SourceDocumentBlock(
            id: 'latex-spacer-$blockNumber-$index',
            type: SourceBlockType.spacer,
            sourceRange: SourceRange(index, end),
            text: '',
          ),
        );
        index = end;
        blockNumber += 1;
        continue;
      }

      final lineStart = index;
      final trimmedIndex = _skipHorizontalWhitespace(source, index);

      if (trimmedIndex >= source.length) break;

      if (source.startsWith('%', trimmedIndex)) {
        final lineEnd = _lineEnd(source, trimmedIndex);
        final commentText = source.substring(trimmedIndex + 1, lineEnd).trim();
        blocks.add(
          SourceDocumentBlock(
            id: 'latex-comment-$blockNumber-$lineStart',
            type: SourceBlockType.comment,
            sourceRange: SourceRange(lineStart, lineEnd),
            editableRange: SourceRange(trimmedIndex + 1, lineEnd),
            text: commentText,
            metadata: const {'language': 'latex'},
          ),
        );
        index = _skipLineBreak(source, lineEnd);
        blockNumber += 1;
        continue;
      }

      final heading = _tryParseHeading(source, trimmedIndex, lineStart, blockNumber);
      if (heading != null) {
        blocks.add(heading.block);
        index = _skipTrailingWhitespaceToLineEnd(source, heading.end);
        blockNumber += 1;
        continue;
      }

      final listResult = _tryParseListEnvironment(source, trimmedIndex, lineStart, blockNumber);
      if (listResult != null) {
        blocks.addAll(listResult.blocks);
        index = listResult.end;
        blockNumber += listResult.blocks.length;
        continue;
      }

      final mathResult = _tryParseMathBlock(source, trimmedIndex, lineStart, blockNumber);
      if (mathResult != null) {
        blocks.add(mathResult.block);
        index = mathResult.end;
        blockNumber += 1;
        continue;
      }

      final environment = _tryParseEnvironment(source, trimmedIndex, lineStart, blockNumber);
      if (environment != null) {
        blocks.add(environment.block);
        index = environment.end;
        blockNumber += 1;
        continue;
      }

      final command = _tryParseCommandExpression(source, trimmedIndex, lineStart, blockNumber);
      if (command != null) {
        blocks.add(command.block);
        index = command.end;
        blockNumber += 1;
        continue;
      }

      final paragraph = _parseParagraph(source, lineStart, blockNumber);
      if (paragraph != null) {
        blocks.add(paragraph.block);
        index = paragraph.end;
        blockNumber += 1;
        continue;
      }

      errors.add('Could not parse LaTeX near offset $index.');
      final lineEnd = _lineEnd(source, index);
      blocks.add(
        SourceDocumentBlock(
          id: 'latex-fallback-$blockNumber-$index',
          type: SourceBlockType.sourceFallback,
          sourceRange: SourceRange(index, lineEnd),
          editableRange: SourceRange(index, lineEnd),
          text: source.substring(index, lineEnd),
          metadata: const {'reason': 'unparsed'},
        ),
      );
      index = _skipLineBreak(source, lineEnd);
      blockNumber += 1;
    }

    return ParsedSourceDocument(source: source, blocks: blocks, errors: errors);
  }

  _ParsedBlock? _tryParseHeading(
    String source,
    int commandStart,
    int sourceStart,
    int blockNumber,
  ) {
    final match = RegExp(r'^\\(section|subsection|subsubsection)\*?')
        .firstMatch(source.substring(commandStart));
    if (match == null) return null;

    final commandName = match.group(1)!;
    final commandEnd = commandStart + match.end;
    final argument = _readRequiredArgument(source, commandEnd);
    if (argument == null) return null;

    final level = switch (commandName) {
      'section' => 1,
      'subsection' => 2,
      'subsubsection' => 3,
      _ => 1,
    };

    final text = _renderInline(argument.content).trim();
    return _ParsedBlock(
      end: argument.end,
      block: SourceDocumentBlock(
        id: 'latex-heading-$blockNumber-$sourceStart-${argument.end}',
        type: SourceBlockType.heading,
        sourceRange: SourceRange(sourceStart, argument.end),
        editableRange: SourceRange(argument.contentStart, argument.contentEnd),
        text: text,
        level: level,
        metadata: {
          'command': commandName,
          'starred': source.substring(commandStart, commandEnd).contains('*'),
        },
      ),
    );
  }

  _ParsedBlocks? _tryParseListEnvironment(
    String source,
    int beginStart,
    int sourceStart,
    int blockNumber,
  ) {
    final begin = _readBeginEnvironment(source, beginStart);
    if (begin == null) return null;
    if (begin.name != 'itemize' && begin.name != 'enumerate') return null;

    final endTag = '\\end{${begin.name}}';
    final endStart = source.indexOf(endTag, begin.end);
    if (endStart == -1) {
      return _ParsedBlocks(
        end: _lineEnd(source, beginStart),
        blocks: [
          _fallbackBlock(
            id: 'latex-broken-list-$blockNumber-$sourceStart',
            source: source,
            start: sourceStart,
            end: _lineEnd(source, beginStart),
            reason: 'unterminated ${begin.name}',
          ),
        ],
      );
    }

    final envEnd = endStart + endTag.length;
    final bodyStart = begin.end;
    final bodyEnd = endStart;
    final itemRegex = RegExp(r'\\item(?:\s*\[[^\]]*\])?');
    final body = source.substring(bodyStart, bodyEnd);
    final itemMatches = itemRegex.allMatches(body).toList();

    if (itemMatches.isEmpty) {
      return _ParsedBlocks(
        end: envEnd,
        blocks: [
          _fallbackBlock(
            id: 'latex-empty-list-$blockNumber-$sourceStart',
            source: source,
            start: sourceStart,
            end: envEnd,
            reason: 'list without item markers',
          ),
        ],
      );
    }

    final blocks = <SourceDocumentBlock>[];
    for (var i = 0; i < itemMatches.length; i += 1) {
      final current = itemMatches[i];
      final next = i + 1 < itemMatches.length ? itemMatches[i + 1].start : body.length;
      final itemSourceStart = bodyStart + current.start;
      final itemContentStart = bodyStart + current.end;
      final itemSourceEnd = bodyStart + next;
      final rawContent = source.substring(itemContentStart, itemSourceEnd);
      final trimmedInfo = _trimRange(source, itemContentStart, itemSourceEnd);
      blocks.add(
        SourceDocumentBlock(
          id: 'latex-list-item-$blockNumber-$i-$itemSourceStart',
          type: SourceBlockType.listItem,
          sourceRange: SourceRange(itemSourceStart, itemSourceEnd),
          editableRange: SourceRange(trimmedInfo.start, trimmedInfo.end),
          text: _renderInline(rawContent.trim()),
          metadata: {'environment': begin.name, 'ordinal': i},
        ),
      );
    }

    return _ParsedBlocks(end: envEnd, blocks: blocks);
  }

  _ParsedBlock? _tryParseMathBlock(
    String source,
    int mathStart,
    int sourceStart,
    int blockNumber,
  ) {
    if (source.startsWith(r'\[', mathStart)) {
      final endStart = source.indexOf(r'\]', mathStart + 2);
      if (endStart == -1) return null;
      final contentStart = mathStart + 2;
      final contentEnd = endStart;
      final end = endStart + 2;
      return _ParsedBlock(
        end: end,
        block: SourceDocumentBlock(
          id: 'latex-display-math-$blockNumber-$sourceStart',
          type: SourceBlockType.math,
          sourceRange: SourceRange(sourceStart, end),
          editableRange: SourceRange(contentStart, contentEnd),
          text: source.substring(contentStart, contentEnd).trim(),
          metadata: const {'display': true, 'delimiter': r'\[\]'},
        ),
      );
    }

    if (source.startsWith(r'$$', mathStart)) {
      final endStart = source.indexOf(r'$$', mathStart + 2);
      if (endStart == -1) return null;
      final contentStart = mathStart + 2;
      final contentEnd = endStart;
      final end = endStart + 2;
      return _ParsedBlock(
        end: end,
        block: SourceDocumentBlock(
          id: 'latex-display-math-dollar-$blockNumber-$sourceStart',
          type: SourceBlockType.math,
          sourceRange: SourceRange(sourceStart, end),
          editableRange: SourceRange(contentStart, contentEnd),
          text: source.substring(contentStart, contentEnd).trim(),
          metadata: const {'display': true, 'delimiter': r'$$'},
        ),
      );
    }

    final equation = _readBeginEnvironment(source, mathStart);
    if (equation == null || equation.name != 'equation') return null;
    final endTag = r'\end{equation}';
    final endStart = source.indexOf(endTag, equation.end);
    if (endStart == -1) return null;
    final end = endStart + endTag.length;
    return _ParsedBlock(
      end: end,
      block: SourceDocumentBlock(
        id: 'latex-equation-$blockNumber-$sourceStart',
        type: SourceBlockType.math,
        sourceRange: SourceRange(sourceStart, end),
        editableRange: SourceRange(equation.end, endStart),
        text: source.substring(equation.end, endStart).trim(),
        metadata: const {'display': true, 'environment': 'equation'},
      ),
    );
  }

  _ParsedBlock? _tryParseEnvironment(
    String source,
    int beginStart,
    int sourceStart,
    int blockNumber,
  ) {
    final begin = _readBeginEnvironment(source, beginStart);
    if (begin == null) return null;

    final endTag = '\\end{${begin.name}}';
    final endStart = source.indexOf(endTag, begin.end);
    final envEnd = endStart == -1 ? _lineEnd(source, beginStart) : endStart + endTag.length;

    if (begin.name == 'center') {
      final contentEnd = endStart == -1 ? envEnd : endStart;
      return _ParsedBlock(
        end: envEnd,
        block: SourceDocumentBlock(
          id: 'latex-center-$blockNumber-$sourceStart',
          type: SourceBlockType.custom,
          sourceRange: SourceRange(sourceStart, envEnd),
          editableRange: SourceRange(begin.end, contentEnd),
          text: _renderInline(source.substring(begin.end, contentEnd)).trim(),
          metadata: const {'environment': 'center', 'align': 'center'},
        ),
      );
    }

    return _ParsedBlock(
      end: envEnd,
      block: _fallbackBlock(
        id: 'latex-env-fallback-$blockNumber-$sourceStart',
        source: source,
        start: sourceStart,
        end: envEnd,
        reason: endStart == -1 ? 'unterminated ${begin.name}' : 'unsupported environment ${begin.name}',
        metadata: {'environment': begin.name},
      ),
    );
  }

  _ParsedBlock? _tryParseCommandExpression(
    String source,
    int commandStart,
    int sourceStart,
    int blockNumber,
  ) {
    if (!source.startsWith('\\', commandStart)) return null;
    final commandMatch = RegExp(r'^\\([A-Za-z@]+)\*?').firstMatch(source.substring(commandStart));
    if (commandMatch == null) return null;

    final name = commandMatch.group(1)!;
    final commandEnd = commandStart + commandMatch.end;
    final args = <_LatexArgument>[];
    var cursor = commandEnd;

    while (true) {
      final next = _readRequiredArgument(source, cursor);
      if (next == null) break;
      args.add(next);
      cursor = next.end;
    }

    final macroArguments = args.map(_toMacroArgument).toList(growable: false);
    final customMacro = macroRegistry.tryRender(
      commandName: name,
      arguments: macroArguments,
      context: LatexMacroRenderContext(
        source: source,
        sourceStart: sourceStart,
        sourceEnd: cursor,
        blockNumber: blockNumber,
        commandName: name,
        inlineRenderer: _renderInline,
      ),
    );
    if (customMacro != null) {
      return _ParsedBlock(end: cursor, block: customMacro);
    }

    final end = args.isEmpty ? _lineEnd(source, commandStart) : cursor;
    return _ParsedBlock(
      end: end,
      block: _fallbackBlock(
        id: 'latex-command-fallback-$blockNumber-$sourceStart',
        source: source,
        start: sourceStart,
        end: end,
        reason: 'unsupported command \\$name',
        metadata: {'command': name, 'argumentCount': args.length},
      ),
    );
  }

  _ParsedBlock? _parseParagraph(String source, int start, int blockNumber) {
    var end = start;
    while (end < source.length) {
      final lineEnd = _lineEnd(source, end);
      final trimmedStart = _skipHorizontalWhitespace(source, end);
      final line = source.substring(trimmedStart, lineEnd).trimRight();
      if (line.isEmpty && end != start) break;
      if (end != start && _lineStartsStructuralLatex(source, trimmedStart)) break;
      end = _skipLineBreak(source, lineEnd);
      if (lineEnd >= source.length) break;
      final nextTrimmed = _skipHorizontalWhitespace(source, end);
      if (nextTrimmed < source.length && _lineStartsStructuralLatex(source, nextTrimmed)) break;
      if (nextTrimmed >= source.length) break;
    }

    final trimmed = _trimRange(source, start, end);
    if (trimmed.start >= trimmed.end) return null;
    final raw = source.substring(trimmed.start, trimmed.end);
    return _ParsedBlock(
      end: end,
      block: SourceDocumentBlock(
        id: 'latex-paragraph-$blockNumber-${trimmed.start}',
        type: SourceBlockType.paragraph,
        sourceRange: SourceRange(start, end),
        editableRange: SourceRange(trimmed.start, trimmed.end),
        text: _renderInline(raw),
        metadata: const {'language': 'latex'},
      ),
    );
  }

  bool _lineStartsStructuralLatex(String source, int offset) {
    return source.startsWith('%', offset) ||
        source.startsWith(r'\section', offset) ||
        source.startsWith(r'\subsection', offset) ||
        source.startsWith(r'\subsubsection', offset) ||
        source.startsWith(r'\begin{', offset) ||
        source.startsWith(r'\[', offset) ||
        source.startsWith(r'$$', offset) ||
        source.startsWith(r'\role', offset);
  }

  SourceDocumentBlock _fallbackBlock({
    required String id,
    required String source,
    required int start,
    required int end,
    required String reason,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return SourceDocumentBlock(
      id: id,
      type: SourceBlockType.sourceFallback,
      sourceRange: SourceRange(start, end),
      editableRange: SourceRange(start, end),
      text: source.substring(start, end).trimRight(),
      metadata: <String, Object?>{'reason': reason, ...metadata},
    );
  }

  String _renderInline(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'(?<!\\)%.*'), '');
    text = text.replaceAll(RegExp(r'\\\\(?:\s*\[[^\]]*\])?'), '\n');
    text = text.replaceAll(RegExp(r'\\(?:smallskip|medskip|bigskip)\b'), '\n');
    text = text.replaceAll(RegExp(r'\\(?:vspace|hspace)\*?\s*\{[^}]*\}'), '');
    text = _replaceCommandWithSingleArgument(text, 'textbf');
    text = _replaceCommandWithSingleArgument(text, 'textit');
    text = _replaceCommandWithSingleArgument(text, 'emph');
    text = _replaceCommandWithSingleArgument(text, 'underline');
    text = _replaceHref(text);
    text = _replaceUrl(text);
    text = text.replaceAll(RegExp(r'\\(?:LARGE|Large|large|small|footnotesize|scriptsize|normalsize)\b'), '');
    text = text.replaceAll(RegExp(r'[{}]'), '');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    return text.trim();
  }

  String _replaceCommandWithSingleArgument(String input, String command) {
    final buffer = StringBuffer();
    var index = 0;
    final needle = '\\$command';
    while (index < input.length) {
      final start = input.indexOf(needle, index);
      if (start == -1) {
        buffer.write(input.substring(index));
        break;
      }
      buffer.write(input.substring(index, start));
      final arg = _readRequiredArgument(input, start + needle.length);
      if (arg == null) {
        buffer.write(input.substring(start, start + needle.length));
        index = start + needle.length;
        continue;
      }
      buffer.write(_renderInline(arg.content));
      index = arg.end;
    }
    return buffer.toString();
  }

  String _replaceHref(String input) {
    final buffer = StringBuffer();
    var index = 0;
    const needle = r'\href';
    while (index < input.length) {
      final start = input.indexOf(needle, index);
      if (start == -1) {
        buffer.write(input.substring(index));
        break;
      }
      buffer.write(input.substring(index, start));
      final first = _readRequiredArgument(input, start + needle.length);
      final second = first == null ? null : _readRequiredArgument(input, first.end);
      if (first == null || second == null) {
        buffer.write(needle);
        index = start + needle.length;
        continue;
      }
      buffer.write(_renderInline(second.content));
      index = second.end;
    }
    return buffer.toString();
  }

  String _replaceUrl(String input) {
    final buffer = StringBuffer();
    var index = 0;
    const needle = r'\url';
    while (index < input.length) {
      final start = input.indexOf(needle, index);
      if (start == -1) {
        buffer.write(input.substring(index));
        break;
      }
      buffer.write(input.substring(index, start));
      final arg = _readRequiredArgument(input, start + needle.length);
      if (arg == null) {
        buffer.write(needle);
        index = start + needle.length;
        continue;
      }
      buffer.write(arg.content);
      index = arg.end;
    }
    return buffer.toString();
  }

  LatexMacroArgument _toMacroArgument(_LatexArgument argument) {
    return LatexMacroArgument(
      content: argument.content,
      sourceRange: SourceRange(argument.start, argument.end),
      contentRange: SourceRange(argument.contentStart, argument.contentEnd),
    );
  }

  _LatexBeginEnvironment? _readBeginEnvironment(String source, int start) {
    if (!source.startsWith(r'\begin{', start)) return null;
    final nameStart = start + r'\begin{'.length;
    final nameEnd = source.indexOf('}', nameStart);
    if (nameEnd == -1) return null;
    return _LatexBeginEnvironment(
      name: source.substring(nameStart, nameEnd),
      start: start,
      end: nameEnd + 1,
    );
  }

  _LatexArgument? _readRequiredArgument(String source, int start) {
    var index = _skipWhitespace(source, start);
    if (index >= source.length || source[index] != '{') return null;
    final contentStart = index + 1;
    var depth = 1;
    index += 1;
    while (index < source.length) {
      final char = source[index];
      if (char == '\\') {
        index += 2;
        continue;
      }
      if (char == '{') depth += 1;
      if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return _LatexArgument(
            content: source.substring(contentStart, index),
            start: contentStart - 1,
            end: index + 1,
            contentStart: contentStart,
            contentEnd: index,
          );
        }
      }
      index += 1;
    }
    return null;
  }

  _TrimmedRange _trimRange(String source, int start, int end) {
    var safeStart = start;
    var safeEnd = end;
    while (safeStart < safeEnd && source[safeStart].trim().isEmpty) {
      safeStart += 1;
    }
    while (safeEnd > safeStart && source[safeEnd - 1].trim().isEmpty) {
      safeEnd -= 1;
    }
    return _TrimmedRange(safeStart, safeEnd);
  }

  bool _isBlankAt(String source, int index) {
    final lineEnd = _lineEnd(source, index);
    return source.substring(index, lineEnd).trim().isEmpty;
  }

  int _consumeBlank(String source, int start) {
    var index = start;
    while (index < source.length) {
      final lineEnd = _lineEnd(source, index);
      if (source.substring(index, lineEnd).trim().isNotEmpty) break;
      index = _skipLineBreak(source, lineEnd);
      if (lineEnd >= source.length) break;
    }
    return index;
  }

  int _skipHorizontalWhitespace(String source, int start) {
    var index = start;
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code != 32 && code != 9) break;
      index += 1;
    }
    return index;
  }

  int _skipWhitespace(String source, int start) {
    var index = start;
    while (index < source.length && source[index].trim().isEmpty) {
      index += 1;
    }
    return index;
  }

  int _lineEnd(String source, int start) {
    final newline = source.indexOf('\n', start);
    return newline == -1 ? source.length : newline;
  }

  int _skipLineBreak(String source, int index) {
    if (index < source.length && source.codeUnitAt(index) == 10) return index + 1;
    return index;
  }

  int _skipTrailingWhitespaceToLineEnd(String source, int index) {
    var cursor = index;
    while (cursor < source.length) {
      final char = source[cursor];
      if (char == '\n') return cursor + 1;
      if (char.trim().isNotEmpty) return cursor;
      cursor += 1;
    }
    return cursor;
  }
}

class _ParsedBlock {
  const _ParsedBlock({required this.block, required this.end});

  final SourceDocumentBlock block;
  final int end;
}

class _ParsedBlocks {
  const _ParsedBlocks({required this.blocks, required this.end});

  final List<SourceDocumentBlock> blocks;
  final int end;
}

class _LatexBeginEnvironment {
  const _LatexBeginEnvironment({required this.name, required this.start, required this.end});

  final String name;
  final int start;
  final int end;
}

class _LatexArgument {
  const _LatexArgument({
    required this.content,
    required this.start,
    required this.end,
    required this.contentStart,
    required this.contentEnd,
  });

  final String content;
  final int start;
  final int end;
  final int contentStart;
  final int contentEnd;
}

class _TrimmedRange {
  const _TrimmedRange(this.start, this.end);

  final int start;
  final int end;
}
