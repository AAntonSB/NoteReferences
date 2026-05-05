import 'text_system_range.dart';

enum TextMarkKind {
  bold,
  italic,
  underline,
  strikethrough,
  highlight,
  code,
  link,
}

TextMarkKind _textMarkKindFromName(String? name) {
  return TextMarkKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => TextMarkKind.bold,
  );
}

/// Inline formatting mark applied to a range inside a [TextSystemBlock].
class TextMark {
  const TextMark({
    required this.kind,
    required this.range,
    this.attributes = const <String, String>{},
  });

  factory TextMark.fromJson(Map<String, Object?> json) {
    final rawAttributes = json['attributes'];
    return TextMark(
      kind: _textMarkKindFromName(json['kind'] as String?),
      range: TextSystemRange.fromJson(
        Map<String, Object?>.from(json['range'] as Map? ?? const <String, Object?>{}),
      ),
      attributes: rawAttributes is Map
          ? rawAttributes.map((key, value) => MapEntry('$key', '$value'))
          : const <String, String>{},
    );
  }

  final TextMarkKind kind;
  final TextSystemRange range;
  final Map<String, String> attributes;

  bool get isEmpty => range.isCollapsed;

  TextMark copyWith({
    TextMarkKind? kind,
    TextSystemRange? range,
    Map<String, String>? attributes,
  }) {
    return TextMark(
      kind: kind ?? this.kind,
      range: range ?? this.range,
      attributes: attributes ?? this.attributes,
    );
  }

  TextMark clamp(int textLength) => copyWith(range: range.clamp(textLength));

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'range': range.toJson(),
      if (attributes.isNotEmpty) 'attributes': attributes,
    };
  }

  @override
  String toString() => 'TextMark($kind, $range)';
}
