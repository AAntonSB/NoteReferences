import '../core/source_document_block.dart';
import '../core/source_document_parser.dart';
import '../core/source_range.dart';

/// A deliberately small parser used to validate the source-aware editor kernel.
///
/// It turns plain text into editable paragraph blocks and recognizes simple
/// Markdown-style headings. LaTeX/Markdown-specific parsers should be added as
/// separate implementations in later phases.
class PlainTextSourceParser extends SourceDocumentParser {
  const PlainTextSourceParser();

  @override
  ParsedSourceDocument parse(SourceParseContext context) {
    final source = context.source;
    if (source.isEmpty) {
      return ParsedSourceDocument(source: source, blocks: const <SourceDocumentBlock>[]);
    }

    final blocks = <SourceDocumentBlock>[];
    var index = 0;
    var blockNumber = 0;

    while (index < source.length) {
      final nextBreak = _nextBlankLine(source, index);
      final end = nextBreak == -1 ? source.length : nextBreak;
      final rawBlock = source.substring(index, end);
      final trimmed = rawBlock.trim();

      if (trimmed.isEmpty) {
        blocks.add(
          SourceDocumentBlock(
            id: 'spacer-$blockNumber-$index',
            type: SourceBlockType.spacer,
            sourceRange: SourceRange(index, end),
            text: '',
          ),
        );
      } else {
        final leadingWhitespace = rawBlock.indexOf(trimmed);
        final editableStart = index + (leadingWhitespace < 0 ? 0 : leadingWhitespace);
        final editableEnd = editableStart + trimmed.length;
        final headingLevel = _headingLevel(trimmed);
        final displayText = headingLevel == null
            ? trimmed
            : trimmed.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        final displayOffset = headingLevel == null ? 0 : trimmed.length - displayText.length;

        blocks.add(
          SourceDocumentBlock(
            id: 'block-$blockNumber-$index-$end',
            type: headingLevel == null ? SourceBlockType.paragraph : SourceBlockType.heading,
            sourceRange: SourceRange(index, end),
            editableRange: SourceRange(editableStart + displayOffset, editableEnd),
            text: displayText,
            level: headingLevel,
          ),
        );
      }

      blockNumber += 1;
      if (nextBreak == -1) break;
      index = _skipBlankLines(source, nextBreak);
    }

    return ParsedSourceDocument(source: source, blocks: blocks);
  }

  int _nextBlankLine(String source, int start) {
    final match = RegExp(r'\n\s*\n').firstMatch(source.substring(start));
    if (match == null) return -1;
    return start + match.start;
  }

  int _skipBlankLines(String source, int start) {
    var index = start;
    while (index < source.length && source.codeUnitAt(index) == 10) {
      index += 1;
    }
    while (index < source.length && source[index].trim().isEmpty) {
      index += 1;
    }
    return index;
  }

  int? _headingLevel(String text) {
    final match = RegExp(r'^(#{1,6})\s+').firstMatch(text);
    return match?.group(1)?.length;
  }
}
