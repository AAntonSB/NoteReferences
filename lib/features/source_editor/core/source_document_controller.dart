import 'package:flutter/foundation.dart';

import 'source_edit.dart';
import 'source_range.dart';

class SourceDocumentSnapshot {
  const SourceDocumentSnapshot({
    required this.source,
    required this.createdAt,
    this.label,
  });

  final String source;
  final DateTime createdAt;
  final String? label;
}

/// Holds the canonical source for a document and applies source transactions.
///
/// This controller is deliberately independent from LaTeX, Markdown, or any
/// rendering technology. The editor surface can be swapped without changing how
/// source edits are represented.
class SourceDocumentController extends ChangeNotifier {
  SourceDocumentController({String source = ''}) : _source = source;

  String _source;
  final List<SourceDocumentSnapshot> _snapshots = <SourceDocumentSnapshot>[];

  String get source => _source;
  List<SourceDocumentSnapshot> get snapshots => List.unmodifiable(_snapshots);

  set source(String value) => replaceSource(value);

  void replaceSource(String value) {
    if (value == _source) return;
    _source = value;
    notifyListeners();
  }

  SourceEditResult applyEdit(SourceEdit edit) => applyEdits(<SourceEdit>[edit]);

  SourceEditResult applyEdits(List<SourceEdit> edits) {
    if (edits.isEmpty) {
      return SourceEditResult(before: _source, after: _source, edits: edits);
    }

    final sourceLength = _source.length;
    final normalized = edits
        .map(
          (edit) => SourceEdit(
            range: edit.range.clamp(sourceLength),
            replacement: edit.replacement,
          ),
        )
        .toList()
      ..sort((a, b) => b.range.start.compareTo(a.range.start));

    final before = _source;
    var next = _source;
    for (final edit in normalized) {
      next = next.replaceRange(
        edit.range.start,
        edit.range.end,
        edit.replacement,
      );
    }

    if (next != _source) {
      _source = next;
      notifyListeners();
    }

    return SourceEditResult(before: before, after: next, edits: normalized);
  }

  void replaceRange(SourceRange range, String replacement) {
    applyEdit(SourceEdit.replace(range, replacement));
  }

  void saveSnapshot({String? label}) {
    _snapshots.add(
      SourceDocumentSnapshot(
        source: _source,
        createdAt: DateTime.now(),
        label: label,
      ),
    );
    notifyListeners();
  }

  void restoreSnapshot(SourceDocumentSnapshot snapshot) {
    replaceSource(snapshot.source);
  }
}
