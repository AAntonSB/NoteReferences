import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CanvasImportRepository extends ChangeNotifier {
  final List<CanvasCalendarEvent> _events = <CanvasCalendarEvent>[];

  File? _storageFile;
  bool _loaded = false;
  CanvasImportSettings _settings = CanvasImportSettings.empty();
  DateTime? _lastSyncedAt;

  bool get isLoaded => _loaded;
  CanvasImportSettings get settings => _settings;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isConfigured => _settings.isConfigured;

  List<CanvasCalendarEvent> get events => List.unmodifiable(_events);

  Future<void> load() async {
    if (_loaded) return;

    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    _storageFile = File(p.join(directory.path, 'canvas_import.json'));

    final file = _storageFile!;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final map = decoded.map((key, value) => MapEntry(key.toString(), value));
          _settings = CanvasImportSettings.fromJson(_stringMap(map['settings']));
          _lastSyncedAt = _readDateTime(map['lastSyncedAt']);
          final rawEvents = map['events'];
          _events
            ..clear()
            ..addAll(
              rawEvents is List
                  ? rawEvents
                      .whereType<Map>()
                      .map((item) => CanvasCalendarEvent.fromJson(_stringMap(item)))
                      .where((item) => item.id.isNotEmpty)
                  : const <CanvasCalendarEvent>[],
            );
        }
      } catch (error, stackTrace) {
        debugPrint('Could not read Canvas import data: $error');
        debugPrint('$stackTrace');
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> saveSettings(CanvasImportSettings settings) async {
    _settings = settings.normalized();
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    _settings = CanvasImportSettings.empty();
    _lastSyncedAt = null;
    _events.clear();
    await _save();
    notifyListeners();
  }

  Future<int> syncCalendarEvents({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final settings = _settings.normalized();
    if (!settings.isConfigured) {
      throw const CanvasImportException('Add your Canvas URL and access token first.');
    }

    final client = HttpClient();
    try {
      final fetched = <CanvasCalendarEvent>[];

      final calendarRows = await _getPaginatedJsonList(
        client: client,
        settings: settings,
        endpoint: '/api/v1/calendar_events',
        query: {
          'type': 'event',
          'start_date': rangeStart.toUtc().toIso8601String(),
          'end_date': rangeEnd.toUtc().toIso8601String(),
          'per_page': '100',
          'include[]': 'course',
        },
      );
      fetched.addAll(
        calendarRows
            .whereType<Map>()
            .map((item) => CanvasCalendarEvent.fromCanvasCalendarEvent(_stringMap(item)))
            .where((event) => event.id.isNotEmpty),
      );

      if (settings.includeUpcomingAssignments) {
        final upcomingRows = await _getPaginatedJsonList(
          client: client,
          settings: settings,
          endpoint: '/api/v1/users/self/upcoming_events',
          query: {
            'include[]': 'course',
            'per_page': '100',
          },
        );
        fetched.addAll(
          upcomingRows
              .whereType<Map>()
              .map((item) => CanvasCalendarEvent.fromCanvasUpcomingEvent(_stringMap(item)))
              .where((event) => event.id.isNotEmpty),
        );
      }

      final start = _dateOnly(rangeStart);
      final end = _dateOnly(rangeEnd);
      final byId = <String, CanvasCalendarEvent>{
        for (final event in _events)
          if (event.startAt.isBefore(start) || event.startAt.isAfter(end)) event.id: event,
      };

      for (final event in fetched) {
        final eventDate = _dateOnly(event.startAt);
        if (eventDate.isBefore(start) || eventDate.isAfter(end)) continue;
        byId[event.id] = event;
      }

      _events
        ..clear()
        ..addAll(byId.values);
      _events.sort((a, b) {
        final timeCompare = a.startAt.compareTo(b.startAt);
        if (timeCompare != 0) return timeCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      _lastSyncedAt = DateTime.now();
      await _save();
      notifyListeners();
      return fetched.length;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<dynamic>> _getPaginatedJsonList({
    required HttpClient client,
    required CanvasImportSettings settings,
    required String endpoint,
    required Map<String, String> query,
  }) async {
    final rows = <dynamic>[];
    Uri? uri = _buildCanvasUri(settings.baseUrl, endpoint, query);

    while (uri != null) {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.accessToken}');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CanvasImportException(
          'Canvas returned ${response.statusCode}. Check your URL, token, and course access.',
        );
      }

      final decoded = body.trim().isEmpty ? const <dynamic>[] : jsonDecode(body);
      if (decoded is List) {
        rows.addAll(decoded);
      } else {
        throw const CanvasImportException('Canvas returned an unexpected response.');
      }

      uri = _nextPageUri(response.headers);
    }

    return rows;
  }

  Future<void> _save() async {
    final file = _storageFile;
    if (file == null) return;

    final data = jsonEncode({
      'settings': _settings.toJson(),
      'lastSyncedAt': _lastSyncedAt?.toIso8601String(),
      'events': _events.map((event) => event.toJson()).toList(),
    });
    await file.writeAsString(data);
  }
}

class CanvasImportSettings {
  final String baseUrl;
  final String accessToken;
  final bool includeUpcomingAssignments;

  const CanvasImportSettings({
    required this.baseUrl,
    required this.accessToken,
    this.includeUpcomingAssignments = true,
  });

  factory CanvasImportSettings.empty() {
    return const CanvasImportSettings(baseUrl: '', accessToken: '');
  }

  factory CanvasImportSettings.fromJson(Map<String, dynamic> json) {
    return CanvasImportSettings(
      baseUrl: _readString(json['baseUrl']) ?? '',
      accessToken: _readString(json['accessToken']) ?? '',
      includeUpcomingAssignments: _readBool(json['includeUpcomingAssignments']) ?? true,
    );
  }

  bool get isConfigured => baseUrl.trim().isNotEmpty && accessToken.trim().isNotEmpty;

  CanvasImportSettings normalized() {
    var url = baseUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return CanvasImportSettings(
      baseUrl: url,
      accessToken: accessToken.trim(),
      includeUpcomingAssignments: includeUpcomingAssignments,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'accessToken': accessToken,
      'includeUpcomingAssignments': includeUpcomingAssignments,
    };
  }

  CanvasImportSettings copyWith({
    String? baseUrl,
    String? accessToken,
    bool? includeUpcomingAssignments,
  }) {
    return CanvasImportSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      accessToken: accessToken ?? this.accessToken,
      includeUpcomingAssignments: includeUpcomingAssignments ?? this.includeUpcomingAssignments,
    );
  }
}

class CanvasCalendarEvent {
  final String id;
  final String title;
  final String courseLabel;
  final DateTime startAt;
  final DateTime? endAt;
  final String? htmlUrl;
  final bool isAssignment;
  final bool isDeadline;

  const CanvasCalendarEvent({
    required this.id,
    required this.title,
    required this.courseLabel,
    required this.startAt,
    this.endAt,
    this.htmlUrl,
    required this.isAssignment,
    required this.isDeadline,
  });

  factory CanvasCalendarEvent.fromCanvasCalendarEvent(Map<String, dynamic> json) {
    final id = _readString(json['id']) ?? _readString(json['calendar_event_id']) ?? '';
    final course = _readString(json['context_name']) ??
        _readString(json['effective_context_code']) ??
        _readCourseName(json['course']) ??
        'Canvas';
    final title = _readString(json['title']) ?? 'Canvas event';
    final start = _readDateTime(json['start_at']) ?? _readDateTime(json['all_day_date']) ?? DateTime.now();
    final end = _readDateTime(json['end_at']);
    return CanvasCalendarEvent(
      id: 'canvas-event-$id',
      title: title,
      courseLabel: course,
      startAt: start,
      endAt: end,
      htmlUrl: _readString(json['html_url']) ?? _readString(json['url']),
      isAssignment: false,
      isDeadline: false,
    );
  }

  factory CanvasCalendarEvent.fromCanvasUpcomingEvent(Map<String, dynamic> json) {
    final assignment = json['assignment'];
    final assignmentMap = assignment is Map ? _stringMap(assignment) : const <String, dynamic>{};
    final id = _readString(json['id']) ?? _readString(assignmentMap['id']) ?? '';
    final title = _readString(json['title']) ?? _readString(assignmentMap['name']) ?? 'Canvas item';
    final course = _readCourseName(json['course']) ?? _readString(json['context_name']) ?? 'Canvas';
    final start = _readDateTime(json['start_at']) ??
        _readDateTime(json['all_day_date']) ??
        _readDateTime(json['due_at']) ??
        _readDateTime(assignmentMap['due_at']) ??
        DateTime.now();
    final isAssignment = assignmentMap.isNotEmpty || _readString(json['type']) == 'assignment';
    return CanvasCalendarEvent(
      id: 'canvas-upcoming-$id',
      title: title,
      courseLabel: course,
      startAt: start,
      endAt: _readDateTime(json['end_at']),
      htmlUrl: _readString(json['html_url']) ??
          _readString(json['url']) ??
          _readString(assignmentMap['html_url']),
      isAssignment: isAssignment,
      isDeadline: isAssignment,
    );
  }

  factory CanvasCalendarEvent.fromJson(Map<String, dynamic> json) {
    return CanvasCalendarEvent(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Canvas item',
      courseLabel: _readString(json['courseLabel']) ?? 'Canvas',
      startAt: _readDateTime(json['startAt']) ?? DateTime.now(),
      endAt: _readDateTime(json['endAt']),
      htmlUrl: _readString(json['htmlUrl']),
      isAssignment: _readBool(json['isAssignment']) ?? false,
      isDeadline: _readBool(json['isDeadline']) ?? false,
    );
  }

  String get timeLabel {
    if (isDeadline) return 'Due';
    final hour = startAt.hour.toString().padLeft(2, '0');
    final minute = startAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'courseLabel': courseLabel,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
      'htmlUrl': htmlUrl,
      'isAssignment': isAssignment,
      'isDeadline': isDeadline,
    };
  }
}

class CanvasImportException implements Exception {
  final String message;

  const CanvasImportException(this.message);

  @override
  String toString() => message;
}

Uri _buildCanvasUri(String baseUrl, String endpoint, Map<String, String> query) {
  final base = Uri.parse(baseUrl.trim());
  final basePath = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  final endpointPath = endpoint.startsWith('/') ? endpoint : '/$endpoint';
  return base.replace(
    path: '$basePath$endpointPath',
    queryParameters: query,
  );
}

Uri? _nextPageUri(HttpHeaders headers) {
  final linkValues = headers['link'];
  if (linkValues == null || linkValues.isEmpty) return null;

  final link = linkValues.join(',');
  if (link.trim().isEmpty) return null;

  for (final part in link.split(',')) {
    if (!part.contains('rel="next"')) continue;
    final match = RegExp(r'<([^>]+)>').firstMatch(part);
    final url = match?.group(1);
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url);
  }
  return null;
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String? _readString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num) return value.toString();
  return null;
}

bool? _readBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return bool.tryParse(value);
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toLocal();
  }
  return null;
}

String? _readCourseName(Object? value) {
  final map = _stringMap(value);
  return _readString(map['name']) ?? _readString(map['course_code']);
}
