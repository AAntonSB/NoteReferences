import 'dart:convert';

import 'reader_anchor.dart';

/// EPUB equivalent of the PDF sidecar note placement geometry.
///
/// This is intentionally not a fake PDF page placement. It stores the reader
/// section/spine location, optional paragraph index and normalized note position
/// inside an EPUB sidecar section canvas.
class EpubSidecarPlacement {
  final int spineIndex;
  final String? href;
  final String? sectionTitle;
  final int? paragraphIndex;
  final double x;
  final double y;
  final double width;

  const EpubSidecarPlacement({
    required this.spineIndex,
    this.href,
    this.sectionTitle,
    this.paragraphIndex,
    this.x = 0.08,
    this.y = 0.12,
    this.width = 0.42,
  });

  bool matchesSection(int value) => spineIndex == value;

  EpubSidecarPlacement copyWith({
    int? spineIndex,
    String? href,
    String? sectionTitle,
    int? paragraphIndex,
    double? x,
    double? y,
    double? width,
  }) {
    return EpubSidecarPlacement(
      spineIndex: spineIndex ?? this.spineIndex,
      href: href ?? this.href,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
    );
  }

  Map<String, Object?> toJson({ReaderAnchor? anchor}) {
    return <String, Object?>{
      'placementType': 'epubSidecar',
      'spineIndex': spineIndex,
      'href': href,
      'sectionTitle': sectionTitle,
      'paragraphIndex': paragraphIndex,
      'x': x.clamp(0.0, 1.0).toDouble(),
      'y': y.clamp(0.0, 1.0).toDouble(),
      'width': width.clamp(0.18, 1.0).toDouble(),
      if (anchor != null) 'readerAnchor': anchor.toJson(),
      if (anchor != null)
        'source': <String, Object?>{
          'kind': anchor.documentKind.name,
          'documentId': anchor.documentId,
          'documentTitle': anchor.documentTitle,
          'locationLabel': anchor.locationLabel,
        },
    };
  }

  String toJsonString({ReaderAnchor? anchor}) => jsonEncode(toJson(anchor: anchor));

  static EpubSidecarPlacement? fromGeometryJson(String? geometryJson) {
    final json = _decode(geometryJson);
    if (json == null) return null;

    final placementType = _readString(json['placementType']);
    if (placementType != 'epubSidecar') return null;

    final spineIndex = _readInt(json['spineIndex']);
    if (spineIndex == null || spineIndex < 0) return null;

    return EpubSidecarPlacement(
      spineIndex: spineIndex,
      href: _readString(json['href']),
      sectionTitle: _readString(json['sectionTitle']),
      paragraphIndex: _readInt(json['paragraphIndex']),
      x: _readDouble(json['x']) ?? 0.08,
      y: _readDouble(json['y']) ?? 0.12,
      width: _readDouble(json['width']) ?? 0.42,
    );
  }

  static Map<String, dynamic>? _decode(String? geometryJson) {
    if (geometryJson == null || geometryJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(geometryJson);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? _readString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
