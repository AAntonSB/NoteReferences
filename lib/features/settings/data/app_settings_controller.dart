import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum SidecarDragKeybind {
  shift('shift', 'Shift'),
  alt('alt', 'Alt'),
  control('control', 'Ctrl');

  final String id;
  final String label;

  const SidecarDragKeybind(this.id, this.label);

  static SidecarDragKeybind fromId(String? id) {
    return SidecarDragKeybind.values.firstWhere(
      (value) => value.id == id,
      orElse: () => SidecarDragKeybind.shift,
    );
  }
}

class AppSettings {
  final bool sidecarDraggableHeaderEnabled;
  final SidecarDragKeybind sidecarDragKeybind;

  const AppSettings({
    this.sidecarDraggableHeaderEnabled = true,
    this.sidecarDragKeybind = SidecarDragKeybind.shift,
  });

  AppSettings copyWith({
    bool? sidecarDraggableHeaderEnabled,
    SidecarDragKeybind? sidecarDragKeybind,
  }) {
    return AppSettings(
      sidecarDraggableHeaderEnabled:
          sidecarDraggableHeaderEnabled ?? this.sidecarDraggableHeaderEnabled,
      sidecarDragKeybind: sidecarDragKeybind ?? this.sidecarDragKeybind,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sidecarDraggableHeaderEnabled': sidecarDraggableHeaderEnabled,
      'sidecarDragKeybind': sidecarDragKeybind.id,
    };
  }

  static AppSettings fromJson(Map<String, dynamic> json) {
    return AppSettings(
      sidecarDraggableHeaderEnabled:
          json['sidecarDraggableHeaderEnabled'] as bool? ?? true,
      sidecarDragKeybind: SidecarDragKeybind.fromId(
        json['sidecarDragKeybind'] as String?,
      ),
    );
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  bool _isLoaded = false;

  AppSettings get settings => _settings;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          _settings = AppSettings.fromJson(decoded);
        } else if (decoded is Map) {
          _settings = AppSettings.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load settings: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setSidecarDraggableHeaderEnabled(bool value) async {
    _settings = _settings.copyWith(sidecarDraggableHeaderEnabled: value);
    notifyListeners();
    await _save();
  }

  Future<void> setSidecarDragKeybind(SidecarDragKeybind value) async {
    _settings = _settings.copyWith(sidecarDragKeybind: value);
    notifyListeners();
    await _save();
  }

  Future<File> _settingsFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'app_settings.json'));
  }

  Future<void> _save() async {
    try {
      final file = await _settingsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_settings.toJson()),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to save settings: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'No AppSettingsScope found in context.');
    return scope!.notifier!;
  }

  static AppSettingsController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>()
        ?.notifier;
  }
}
