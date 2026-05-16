import 'package:flutter/foundation.dart';

import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import 'text_system_inline_atom_renderer.dart';

/// Tracks source-edit mode for inline math atoms in the owned editor.
///
/// Inline math remains ordinary document text (`\(...\)`) in the model, but the
/// owned renderer can show a readable/math-like display when inactive and the
/// literal source when the user activates the atom.
class TextSystemInlineMathEditorController extends ChangeNotifier {
  TextSystemInlineAtom? _activeAtom;

  TextSystemInlineAtom? get activeAtom => _activeAtom;
  bool get hasActiveAtom => _activeAtom != null;

  TextSystemDocumentRange? get activeRange {
    final atom = _activeAtom;
    if (atom == null) return null;
    return TextSystemDocumentRange(
      start: TextSystemDocumentPosition.text(
        blockId: atom.blockId,
        blockIndex: atom.blockIndex,
        offset: atom.globalRange.start,
      ),
      end: TextSystemDocumentPosition.text(
        blockId: atom.blockId,
        blockIndex: atom.blockIndex,
        offset: atom.globalRange.end,
      ),
    );
  }

  void activate(TextSystemInlineAtom atom) {
    if (!atom.isMath) return;
    if (_activeAtom?.id == atom.id &&
        _activeAtom?.globalRange == atom.globalRange &&
        _activeAtom?.blockId == atom.blockId) {
      return;
    }
    _activeAtom = atom;
    notifyListeners();
  }

  void deactivate() {
    if (_activeAtom == null) return;
    _activeAtom = null;
    notifyListeners();
  }

  void syncWithDocumentSelection(TextSystemDocumentRange? range) {
    final atom = _activeAtom;
    if (atom == null) return;
    if (range == null) {
      deactivate();
      return;
    }
    final normalized = range.normalized();
    if (normalized.start.blockId != atom.blockId || normalized.end.blockId != atom.blockId) {
      deactivate();
      return;
    }
    final start = normalized.start.offset;
    final end = normalized.end.offset;
    final overlaps = start < atom.globalRange.end && atom.globalRange.start < end;
    final collapsedInside = normalized.isCollapsed &&
        start > atom.globalRange.start &&
        start < atom.globalRange.end;
    if (!overlaps && !collapsedInside) deactivate();
  }
}
