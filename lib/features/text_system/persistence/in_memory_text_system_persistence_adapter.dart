import '../core/text_system_document.dart';
import 'text_system_persistence_adapter.dart';

/// Test/draft persistence adapter used by the text-system lab.
///
/// It stores JSON-compatible document snapshots to exercise serialization and
/// deserialization without binding Phase 6 to the app's final storage layer.
class InMemoryTextSystemPersistenceAdapter implements TextSystemPersistenceAdapter {
  final Map<String, Map<String, Object?>> _documents = <String, Map<String, Object?>>{};

  @override
  Future<TextSystemDocument?> loadTextDocument(String documentId) async {
    final json = _documents[documentId];
    if (json == null) return null;
    return TextSystemDocument.fromJson(json);
  }

  @override
  Future<void> saveTextDocument(TextSystemDocument document) async {
    _documents[document.id] = document.toJson();
  }

  Map<String, Object?>? rawJsonFor(String documentId) => _documents[documentId];

  void seed(TextSystemDocument document) {
    _documents[document.id] = document.toJson();
  }
}
