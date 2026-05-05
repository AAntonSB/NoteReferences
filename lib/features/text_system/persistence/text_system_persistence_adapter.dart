import '../core/text_system_document.dart';

/// Storage boundary for project-wide text documents.
///
/// Concrete app features can back this with SQLite, files, sync storage, or
/// encrypted local drafts. The text engine only depends on this contract.
abstract class TextSystemPersistenceAdapter {
  Future<TextSystemDocument?> loadTextDocument(String documentId);
  Future<void> saveTextDocument(TextSystemDocument document);
}
