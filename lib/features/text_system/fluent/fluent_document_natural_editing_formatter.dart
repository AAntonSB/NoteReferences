import 'package:flutter/services.dart';

/// Lightweight natural-editing rules for the continuous fluent document buffer.
///
/// This formatter keeps the editor user-facing and text-first while allowing the
/// buffer to behave like a document instead of a plain textarea for common
/// paragraph/list interactions. It intentionally works on the visible buffer,
/// not on row widgets, so selection remains owned by the single Flutter text
/// surface.
class FluentDocumentNaturalEditingFormatter extends TextInputFormatter {
  const FluentDocumentNaturalEditingFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final enter = _handleEnter(oldValue, newValue);
    if (enter != null) return _renumberOrderedLines(enter);

    final markerExit = _handleBackspaceAtMarker(oldValue, newValue);
    if (markerExit != null) return _renumberOrderedLines(markerExit);

    final renumbered = _renumberOrderedLines(newValue);
    return renumbered;
  }

  TextEditingValue? _handleEnter(TextEditingValue oldValue, TextEditingValue newValue) {
    final selection = oldValue.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;

    final offset = selection.baseOffset;
    if (offset < 0 || offset > oldValue.text.length) return null;
    final inserted = _insertedText(oldValue.text, newValue.text, offset);
    if (inserted != '\n') return null;

    final line = _LineInfo.at(oldValue.text, offset);
    final prefix = _ListPrefix.parse(line.text);
    if (prefix == null) return null;

    final localOffset = offset - line.start;
    if (localOffset < prefix.length) return null;

    final content = line.text.substring(prefix.length);
    final beforeCursor = line.text.substring(0, localOffset);
    final afterCursor = line.text.substring(localOffset);
    final nextPrefix = prefix.nextVisiblePrefix;

    if (content.trim().isEmpty) {
      final nextText = '${oldValue.text.substring(0, line.start)}${oldValue.text.substring(line.end)}';
      final nextOffset = line.start.clamp(0, nextText.length).toInt();
      return TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextOffset),
        composing: TextRange.empty,
      );
    }

    final nextText = '${oldValue.text.substring(0, line.start)}$beforeCursor\n$nextPrefix$afterCursor${oldValue.text.substring(line.end)}';
    final nextOffset = line.start + beforeCursor.length + 1 + nextPrefix.length;
    return TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset.clamp(0, nextText.length).toInt()),
      composing: TextRange.empty,
    );
  }

  TextEditingValue? _handleBackspaceAtMarker(TextEditingValue oldValue, TextEditingValue newValue) {
    final selection = oldValue.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    if (newValue.text.length >= oldValue.text.length) return null;

    final offset = selection.baseOffset;
    if (offset < 0 || offset > oldValue.text.length) return null;

    final line = _LineInfo.at(oldValue.text, offset);
    final prefix = _ListPrefix.parse(line.text);
    if (prefix == null) return null;

    final localOffset = offset - line.start;
    if (localOffset != prefix.length) return null;

    final content = line.text.substring(prefix.length);
    final nextText = '${oldValue.text.substring(0, line.start)}$content${oldValue.text.substring(line.end)}';
    final nextOffset = line.start.clamp(0, nextText.length).toInt();
    return TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  TextEditingValue _renumberOrderedLines(TextEditingValue value) {
    final lines = value.text.split('\n');
    var nextIndex = 1;
    var changed = false;
    var cursorDelta = 0;
    var consumed = 0;
    final rebuilt = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) {
        rebuilt.write('\n');
        consumed += 1;
      }

      final line = lines[i];
      final match = RegExp(r'^(\s*)\d+([\.)])\s+(.*)$').firstMatch(line);
      if (match == null) {
        rebuilt.write(line);
        consumed += line.length;
        continue;
      }

      final leading = match.group(1) ?? '';
      final separator = match.group(2) ?? '.';
      final rest = match.group(3) ?? '';
      final replacementPrefix = '$leading$nextIndex$separator ';
      final oldPrefixLength = (match.group(0) ?? line).length - rest.length;
      final replacement = '$replacementPrefix$rest';
      rebuilt.write(replacement);

      if (replacement != line) {
        changed = true;
        final lineStart = consumed;
        final oldPrefixEnd = lineStart + oldPrefixLength;
        if (value.selection.baseOffset >= oldPrefixEnd) {
          cursorDelta += replacementPrefix.length - oldPrefixLength;
        }
      }

      consumed += line.length;
      nextIndex++;
    }

    if (!changed) return value;
    final nextText = rebuilt.toString();
    final base = (value.selection.baseOffset + cursorDelta).clamp(0, nextText.length).toInt();
    final extent = (value.selection.extentOffset + cursorDelta).clamp(0, nextText.length).toInt();
    return TextEditingValue(
      text: nextText,
      selection: TextSelection(
        baseOffset: base,
        extentOffset: extent,
        affinity: value.selection.affinity,
        isDirectional: value.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }

  String? _insertedText(String oldText, String newText, int oldOffset) {
    if (newText.length != oldText.length + 1) return null;
    if (oldOffset < 0 || oldOffset > oldText.length) return null;
    final before = oldText.substring(0, oldOffset);
    final after = oldText.substring(oldOffset);
    if (!newText.startsWith(before) || !newText.endsWith(after)) return null;
    return newText.substring(oldOffset, oldOffset + 1);
  }
}

class _LineInfo {
  const _LineInfo({required this.start, required this.end, required this.text});

  factory _LineInfo.at(String buffer, int offset) {
    final safeOffset = offset.clamp(0, buffer.length).toInt();
    final before = safeOffset <= 0 ? -1 : buffer.lastIndexOf('\n', safeOffset - 1);
    final start = before < 0 ? 0 : before + 1;
    final after = buffer.indexOf('\n', safeOffset);
    final end = after < 0 ? buffer.length : after;
    return _LineInfo(start: start, end: end, text: buffer.substring(start, end));
  }

  final int start;
  final int end;
  final String text;
}

class _ListPrefix {
  const _ListPrefix._({required this.length, required this.nextVisiblePrefix});

  final int length;
  final String nextVisiblePrefix;

  static _ListPrefix? parse(String line) {
    final ordered = RegExp(r'^(\s*)(\d+)([\.)])\s+').firstMatch(line);
    if (ordered != null) {
      final leading = ordered.group(1) ?? '';
      final number = int.tryParse(ordered.group(2) ?? '') ?? 1;
      final separator = ordered.group(3) ?? '.';
      final matched = ordered.group(0) ?? '';
      return _ListPrefix._(
        length: matched.length,
        nextVisiblePrefix: '$leading${number + 1}$separator ',
      );
    }

    final bullet = RegExp(r'^(\s*)(?:[-*•])\s+').firstMatch(line);
    if (bullet != null) {
      final leading = bullet.group(1) ?? '';
      final matched = bullet.group(0) ?? '';
      return _ListPrefix._(length: matched.length, nextVisiblePrefix: '$leading• ');
    }

    final todo = RegExp(r'^(\s*)([☐☑])\s+').firstMatch(line);
    if (todo != null) {
      final leading = todo.group(1) ?? '';
      final matched = todo.group(0) ?? '';
      return _ListPrefix._(length: matched.length, nextVisiblePrefix: '${leading}☐ ');
    }

    return null;
  }
}
