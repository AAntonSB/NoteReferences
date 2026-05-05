import 'package:flutter/services.dart';

import '../core/text_system_range.dart';

/// Converts Flutter selection state into text-system ranges.
///
/// The bridge keeps Flutter-specific selection details out of the core text
/// model. Surfaces can use it consistently whether they are tiny inline fields,
/// simple notes, document editors, or future source-aware writers.
class TextSystemSelectionBridge {
  const TextSystemSelectionBridge._();

  static TextSystemRange? rangeFromSelection(
    TextSelection selection, {
    required int textLength,
    bool requireExpanded = false,
  }) {
    if (!selection.isValid) return null;

    final base = selection.baseOffset.clamp(0, textLength).toInt();
    final extent = selection.extentOffset.clamp(0, textLength).toInt();
    final start = base < extent ? base : extent;
    final end = base < extent ? extent : base;
    final range = TextSystemRange(start, end);

    if (requireExpanded && range.isCollapsed) return null;
    return range;
  }

  static TextSelection selectionFromRange(
    TextSystemRange range, {
    required int textLength,
  }) {
    final safe = range.clamp(textLength);
    return TextSelection(baseOffset: safe.start, extentOffset: safe.end);
  }

  static TextSelection collapsedSelection(int offset, {required int textLength}) {
    final safeOffset = offset.clamp(0, textLength).toInt();
    return TextSelection.collapsed(offset: safeOffset);
  }

  static String describeSelection(TextSelection selection, {required int textLength}) {
    final range = rangeFromSelection(selection, textLength: textLength);
    if (range == null) return 'No valid selection';
    if (range.isCollapsed) return 'Cursor at ${range.start}';
    return '${range.length} chars selected (${range.start}–${range.end})';
  }
}
