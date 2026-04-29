import 'dart:convert';
import 'dart:io';

class PdfReaderSessionState {
  final String documentId;
  final double visibleTop;
  final double visibleCenterX;
  final double zoom;
  final double pdfPaneFraction;
  final bool outlineOpen;
  final bool debugEnabled;
  final DateTime updatedAt;

  const PdfReaderSessionState({
    required this.documentId,
    required this.visibleTop,
    required this.visibleCenterX,
    required this.zoom,
    required this.pdfPaneFraction,
    required this.outlineOpen,
    required this.debugEnabled,
    required this.updatedAt,
  });

  factory PdfReaderSessionState.fromJson(
    String documentId,
    Map<String, dynamic> json,
  ) {
    return PdfReaderSessionState(
      documentId: documentId,
      visibleTop: _readDouble(json['visibleTop']) ?? 0,
      visibleCenterX: _readDouble(json['visibleCenterX']) ?? 0,
      zoom: _readDouble(json['zoom']) ?? 1,
      pdfPaneFraction: (_readDouble(json['pdfPaneFraction']) ?? 0.5)
          .clamp(0.2, 0.8)
          .toDouble(),
      outlineOpen: _readBool(json['outlineOpen']) ?? false,
      debugEnabled: _readBool(json['debugEnabled']) ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'visibleTop': visibleTop,
      'visibleCenterX': visibleCenterX,
      'zoom': zoom,
      'pdfPaneFraction': pdfPaneFraction,
      'outlineOpen': outlineOpen,
      'debugEnabled': debugEnabled,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static double? _readDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool? _readBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return bool.tryParse(value);
    return null;
  }
}

class PdfReaderSessionStateStore {
  Future<PdfReaderSessionState?> load(String documentId) async {
    final all = await _readAll();
    final raw = all[documentId];

    if (raw is! Map) {
      return null;
    }

    return PdfReaderSessionState.fromJson(
      documentId,
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<void> save(PdfReaderSessionState state) async {
    final all = await _readAll();
    all[state.documentId] = state.toJson();

    final file = await _stateFile();
    await file.parent.create(recursive: true);

    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(all));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _stateFile();

    if (!await file.exists()) {
      return {};
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return {};
    }

    return {};
  }

  Future<File> _stateFile() async {
    final basePath = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;

    return File(
      '$basePath${Platform.pathSeparator}NoteReferences'
      '${Platform.pathSeparator}reader_session_state.json',
    );
  }
}