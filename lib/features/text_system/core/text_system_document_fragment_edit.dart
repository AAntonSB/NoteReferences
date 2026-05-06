import 'text_system_document.dart';
import 'text_system_document_range.dart';

/// Result of replacing a fluent document range with a structured document fragment.
///
/// This is intentionally internal-facing. It lets controllers and test labs report
/// what changed without making users manage blocks or structural units directly.
class TextSystemDocumentFragmentEditResult {
  const TextSystemDocumentFragmentEditResult({
    required this.document,
    required this.replacementRange,
    required this.insertedRange,
    required this.affectedBlockIds,
    required this.insertedPlainText,
  });

  final TextSystemDocument document;
  final TextSystemDocumentRange replacementRange;
  final TextSystemDocumentRange insertedRange;
  final List<String> affectedBlockIds;
  final String insertedPlainText;

  bool get insertedNothing => insertedPlainText.isEmpty && affectedBlockIds.isEmpty;
}
