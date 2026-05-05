import 'text_mark.dart';

/// Internal rich clipboard payload.
///
/// Platform clipboard integration can still expose plain text. Inside the app,
/// this fragment lets moved/copied text keep marks such as bold and highlight.
class TextClipboardFragment {
  const TextClipboardFragment({
    required this.text,
    this.marks = const <TextMark>[],
    this.metadata = const <String, Object?>{},
  });

  factory TextClipboardFragment.fromJson(Map<String, Object?> json) {
    return TextClipboardFragment(
      text: json['text'] as String? ?? '',
      marks: (json['marks'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((mark) => TextMark.fromJson(Map<String, Object?>.from(mark)))
          .toList(),
      metadata: Map<String, Object?>.from(json['metadata'] as Map? ?? const <String, Object?>{}),
    );
  }

  final String text;
  final List<TextMark> marks;
  final Map<String, Object?> metadata;

  bool get isEmpty => text.isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'text': text,
      if (marks.isNotEmpty) 'marks': marks.map((mark) => mark.toJson()).toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}
