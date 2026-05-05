import 'text_operation.dart';
import 'text_system_document.dart';

enum TextTransactionOrigin { user, paste, undo, redo, system }

TextTransactionOrigin _textTransactionOriginFromName(String? name) {
  return TextTransactionOrigin.values.firstWhere(
    (origin) => origin.name == name,
    orElse: () => TextTransactionOrigin.system,
  );
}

/// Atomic before/after mutation for the reusable text system.
class TextTransaction {
  TextTransaction({
    required this.id,
    required this.label,
    required this.before,
    required this.after,
    required this.operations,
    required this.origin,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TextTransaction.fromJson(Map<String, Object?> json) {
    return TextTransaction(
      id: json['id'] as String? ?? 'tx',
      label: json['label'] as String? ?? 'Transaction',
      before: TextSystemDocument.fromJson(
        Map<String, Object?>.from(json['before'] as Map? ?? const <String, Object?>{}),
      ),
      after: TextSystemDocument.fromJson(
        Map<String, Object?>.from(json['after'] as Map? ?? const <String, Object?>{}),
      ),
      operations: (json['operations'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((operation) => TextOperation.fromJson(Map<String, Object?>.from(operation)))
          .toList(),
      origin: _textTransactionOriginFromName(json['origin'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  final String id;
  final String label;
  final TextSystemDocument before;
  final TextSystemDocument after;
  final List<TextOperation> operations;
  final TextTransactionOrigin origin;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'before': before.toJson(),
      'after': after.toJson(),
      'operations': operations.map((operation) => operation.toJson()).toList(),
      'origin': origin.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
