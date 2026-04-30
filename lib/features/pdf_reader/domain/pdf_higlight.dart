import 'package:flutter/material.dart';

@immutable
class PdfHighlight {
  final String id;
  final String documentId;
  final int pageNumber;
  final String? noteId;
  final String selectedText;
  final List<PdfHighlightRect> rects;
  final int colorValue;
  final double opacity;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PdfHighlight({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.noteId,
    required this.selectedText,
    required this.rects,
    required this.colorValue,
    required this.opacity,
    required this.createdAt,
    required this.updatedAt,
  });

  Color get color => Color(colorValue);

  PdfHighlight copyWith({
    String? id,
    String? documentId,
    int? pageNumber,
    String? noteId,
    bool clearNoteId = false,
    String? selectedText,
    List<PdfHighlightRect>? rects,
    int? colorValue,
    double? opacity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PdfHighlight(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      pageNumber: pageNumber ?? this.pageNumber,
      noteId: clearNoteId ? null : noteId ?? this.noteId,
      selectedText: selectedText ?? this.selectedText,
      rects: rects ?? this.rects,
      colorValue: colorValue ?? this.colorValue,
      opacity: opacity ?? this.opacity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'documentId': documentId,
      'pageNumber': pageNumber,
      'noteId': noteId,
      'selectedText': selectedText,
      'rects': rects.map((rect) => rect.toJson()).toList(),
      'colorValue': colorValue,
      'opacity': opacity,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PdfHighlight.fromJson(Map<String, dynamic> json) {
    return PdfHighlight(
      id: json['id'] as String,
      documentId: json['documentId'] as String,
      pageNumber: json['pageNumber'] as int,
      noteId: json['noteId'] as String?,
      selectedText: json['selectedText'] as String? ?? '',
      rects: (json['rects'] as List<dynamic>? ?? const [])
          .map((item) => PdfHighlightRect.fromJson(item as Map<String, dynamic>))
          .toList(),
      colorValue: json['colorValue'] as int? ?? 0xFFFFFF00,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.35,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

@immutable
class PdfHighlightRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const PdfHighlightRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;

  double get height => top - bottom;

  bool get isValid => width > 0 && height > 0;

  Map<String, dynamic> toJson() {
    return {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    };
  }

  factory PdfHighlightRect.fromJson(Map<String, dynamic> json) {
    return PdfHighlightRect(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
  }
}