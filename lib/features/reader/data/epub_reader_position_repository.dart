import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EpubReaderPosition {
  final int spineIndex;
  final int pageIndex;
  final DateTime updatedAt;

  const EpubReaderPosition({
    required this.spineIndex,
    required this.pageIndex,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'spineIndex': spineIndex,
      'pageIndex': pageIndex,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory EpubReaderPosition.fromJson(Map<String, Object?> json) {
    int intValue(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    DateTime dateValue(Object? value) {
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return EpubReaderPosition(
      spineIndex: intValue(json['spineIndex']),
      pageIndex: intValue(json['pageIndex']),
      updatedAt: dateValue(json['updatedAt']),
    );
  }
}

class EpubReaderPositionRepository {
  const EpubReaderPositionRepository();

  Future<EpubReaderPosition?> load(String documentId) async {
    final positions = await _loadAll();
    return positions[documentId];
  }

  Future<void> save({
    required String documentId,
    required int spineIndex,
    int pageIndex = 0,
  }) async {
    final positions = await _loadAll();
    positions[documentId] = EpubReaderPosition(
      spineIndex: spineIndex < 0 ? 0 : spineIndex,
      pageIndex: pageIndex < 0 ? 0 : pageIndex,
      updatedAt: DateTime.now(),
    );
    await _writeAll(positions);
  }

  Future<Map<String, EpubReaderPosition>> _loadAll() async {
    final file = await _positionFile();
    if (!await file.exists()) return <String, EpubReaderPosition>{};
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return <String, EpubReaderPosition>{};
      final result = <String, EpubReaderPosition>{};
      raw.forEach((key, value) {
        if (key is! String || value is! Map) return;
        result[key] = EpubReaderPosition.fromJson(value.cast<String, Object?>());
      });
      return result;
    } catch (_) {
      return <String, EpubReaderPosition>{};
    }
  }

  Future<void> _writeAll(Map<String, EpubReaderPosition> positions) async {
    final file = await _positionFile();
    final encoded = const JsonEncoder.withIndent('  ').convert(
      positions.map(
        (key, value) => MapEntry<String, Object?>(key, value.toJson()),
      ),
    );
    await file.writeAsString(encoded);
  }

  Future<File> _positionFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(appDir.path, 'reader_state'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'epub_positions.json'));
  }
}
