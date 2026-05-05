import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import 'text_system_persistence_adapter.dart';
import 'text_system_save_state.dart';

/// Coordinates dirty state, debounced autosave, manual save, and load handoff.
///
/// This is intentionally small but product-critical: every future text surface
/// should be able to show the same save confidence state without reimplementing
/// autosave logic.
class TextSystemAutosaveController extends ChangeNotifier {
  TextSystemAutosaveController({
    required this.textController,
    required this.persistenceAdapter,
    this.debounceDuration = const Duration(milliseconds: 650),
  })  : _lastObservedDocument = textController.document,
        _lastSavedDocument = textController.document {
    textController.addListener(_handleTextControllerChanged);
  }

  final TextSystemController textController;
  final TextSystemPersistenceAdapter persistenceAdapter;
  final Duration debounceDuration;

  TextSystemDocument _lastObservedDocument;
  TextSystemDocument _lastSavedDocument;
  Timer? _debounceTimer;
  TextSystemSaveState _saveState = const TextSystemSaveState.clean();

  TextSystemSaveState get saveState => _saveState;
  bool get hasUnsavedChanges => !identical(textController.document, _lastSavedDocument);

  Future<TextSystemDocument?> load(String documentId) async {
    final loaded = await persistenceAdapter.loadTextDocument(documentId);
    if (loaded == null) return null;
    _cancelPendingAutosave();
    textController.replaceDocument(loaded, label: 'Load text-system document');
    _cancelPendingAutosave();
    _lastObservedDocument = textController.document;
    _lastSavedDocument = textController.document;
    _setSaveState(
      TextSystemSaveState(
        status: TextSystemSaveStatus.saved,
        lastSavedAt: loaded.updatedAt,
        message: 'Loaded saved document.',
      ),
    );
    return loaded;
  }

  Future<void> saveNow({String message = 'Saved.'}) async {
    _cancelPendingAutosave();
    final documentToSave = textController.document.copyWith(updatedAt: DateTime.now());
    final attemptedAt = DateTime.now();
    _setSaveState(
      TextSystemSaveState(
        status: TextSystemSaveStatus.saving,
        lastSavedAt: _saveState.lastSavedAt,
        lastAttemptedAt: attemptedAt,
        message: 'Saving…',
      ),
    );

    try {
      await persistenceAdapter.saveTextDocument(documentToSave);
      _lastSavedDocument = textController.document;
      _lastObservedDocument = textController.document;
      _setSaveState(
        TextSystemSaveState(
          status: TextSystemSaveStatus.saved,
          lastSavedAt: DateTime.now(),
          lastAttemptedAt: attemptedAt,
          message: message,
        ),
      );
    } catch (error) {
      _setSaveState(
        TextSystemSaveState(
          status: TextSystemSaveStatus.failed,
          lastSavedAt: _saveState.lastSavedAt,
          lastAttemptedAt: attemptedAt,
          message: 'Save failed.',
          error: error,
        ),
      );
    }
  }

  void markCleanForCurrentDocument({String message = 'Current document is clean.'}) {
    _cancelPendingAutosave();
    _lastObservedDocument = textController.document;
    _lastSavedDocument = textController.document;
    _setSaveState(
      TextSystemSaveState(
        status: TextSystemSaveStatus.clean,
        lastSavedAt: _saveState.lastSavedAt,
        message: message,
      ),
    );
  }

  void _handleTextControllerChanged() {
    if (identical(textController.document, _lastObservedDocument)) return;
    _lastObservedDocument = textController.document;
    _setSaveState(
      TextSystemSaveState(
        status: TextSystemSaveStatus.dirty,
        lastSavedAt: _saveState.lastSavedAt,
        message: 'Unsaved changes.',
      ),
    );
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _cancelPendingAutosave();
    _debounceTimer = Timer(debounceDuration, () {
      unawaited(saveNow(message: 'Autosaved.'));
    });
  }

  void _cancelPendingAutosave() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _setSaveState(TextSystemSaveState state) {
    _saveState = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelPendingAutosave();
    textController.removeListener(_handleTextControllerChanged);
    super.dispose();
  }
}
