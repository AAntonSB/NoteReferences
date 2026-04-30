import '../domain/pdf_higlight.dart';

abstract class PdfHighlightRepository {
  Future<List<PdfHighlight>> getHighlightsForDocument(String documentId);

  Future<void> saveHighlight(PdfHighlight highlight);

  Future<void> saveHighlights(List<PdfHighlight> highlights);

  Future<void> deleteHighlight(String highlightId);
}

/// First-pass implementation.
///
/// This keeps behavior simple while we build the PDF interaction model.
/// Replace this class later with Drift/SQLite/Isar/Hive without changing
/// the reader UI.
class InMemoryPdfHighlightRepository implements PdfHighlightRepository {
  InMemoryPdfHighlightRepository._();

  static final InMemoryPdfHighlightRepository instance =
      InMemoryPdfHighlightRepository._();

  final Map<String, List<PdfHighlight>> _itemsByDocument = {};

  @override
  Future<List<PdfHighlight>> getHighlightsForDocument(String documentId) async {
    final items = List<PdfHighlight>.from(_itemsByDocument[documentId] ?? const []);
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  @override
  Future<void> saveHighlight(PdfHighlight highlight) async {
    final items = _itemsByDocument.putIfAbsent(highlight.documentId, () => []);

    final existingIndex = items.indexWhere((item) => item.id == highlight.id);
    if (existingIndex == -1) {
      items.add(highlight);
    } else {
      items[existingIndex] = highlight;
    }
  }

  @override
  Future<void> saveHighlights(List<PdfHighlight> highlights) async {
    for (final highlight in highlights) {
      await saveHighlight(highlight);
    }
  }

  @override
  Future<void> deleteHighlight(String highlightId) async {
    for (final entry in _itemsByDocument.entries) {
      entry.value.removeWhere((highlight) => highlight.id == highlightId);
    }
  }
}