import 'dart:async';

import 'package:flutter/foundation.dart';

import 'text_system_reference_action_models.dart';
import 'text_system_reference_action_repository.dart';

class TextSystemReferenceActionController extends ChangeNotifier {
  TextSystemReferenceActionController({
    required TextSystemReferenceActionRepository repository,
    required String selectedText,
    TextSystemReferenceActionType initialActionType = TextSystemReferenceActionType.source,
  })  : _repository = repository,
        _selectedText = selectedText,
        _actionType = initialActionType,
        _query = selectedText.trim();

  final TextSystemReferenceActionRepository _repository;
  final String _selectedText;

  TextSystemReferenceActionType _actionType;
  String _query;
  bool _isLoading = false;
  Object? _error;
  List<TextSystemReferenceTarget> _results = const <TextSystemReferenceTarget>[];
  List<TextSystemReferenceTarget> _recent = const <TextSystemReferenceTarget>[];
  Timer? _queryDebounce;
  int _requestSerial = 0;

  TextSystemReferenceActionType get actionType => _actionType;
  String get selectedText => _selectedText;
  String get query => _query;
  bool get isLoading => _isLoading;
  Object? get error => _error;
  List<TextSystemReferenceTarget> get results => _results;
  List<TextSystemReferenceTarget> get recent => _recent;

  bool get hasSelection => _selectedText.trim().isNotEmpty;

  Set<TextSystemReferenceTargetKind> get activeKinds {
    return <TextSystemReferenceTargetKind>{_actionType.targetKind};
  }

  Future<void> initialize() async {
    await Future.wait(<Future<void>>[
      loadRecent(),
      searchNow(),
    ]);
  }

  Future<void> loadRecent() async {
    final serial = ++_requestSerial;
    try {
      final recent = await _repository.recentTargets(
        kinds: activeKinds,
        limit: 6,
      );
      if (serial != _requestSerial && _queryDebounce?.isActive == true) return;
      _recent = recent;
      _error = null;
      notifyListeners();
    } catch (error) {
      _error = error;
      notifyListeners();
    }
  }

  void setActionType(TextSystemReferenceActionType type) {
    if (_actionType == type) return;
    _actionType = type;
    _error = null;
    notifyListeners();
    unawaited(loadRecent());
    unawaited(searchNow());
  }

  void updateQuery(String value) {
    if (_query == value) return;
    _query = value;
    _error = null;
    notifyListeners();
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(searchNow());
    });
  }

  Future<void> searchNow() async {
    final serial = ++_requestSerial;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await _repository.searchTargets(
        query: _query,
        kinds: activeKinds,
        limit: 12,
      );
      if (serial != _requestSerial) return;
      _results = results;
      _isLoading = false;
      notifyListeners();
    } catch (error) {
      if (serial != _requestSerial) return;
      _error = error;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<TextSystemReferenceActionResult> createAndSelect({
    String? label,
    Uri? uri,
    String? citationKey,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final draft = TextSystemReferenceActionDraft(
      actionType: _actionType,
      selectedText: _selectedText,
      query: _query,
      label: label,
      uri: uri,
      citationKey: citationKey,
      metadata: metadata,
    );
    final target = await _repository.createTarget(draft);
    final result = composeResult(target);
    await loadRecent();
    await searchNow();
    return result;
  }

  TextSystemReferenceActionResult composeResult(TextSystemReferenceTarget target) {
    final now = DateTime.now();
    final visibleLabel = _selectedText.trim().isEmpty ? target.compactLabel : _selectedText;
    final inlineMark = TextSystemInlineReferenceMark(
      id: TextSystemReferenceActionIds.newReferenceId(now: now),
      kind: target.kind,
      targetId: target.id,
      label: target.compactLabel,
      selectedText: visibleLabel,
      uri: target.uri,
      citationKey: target.citationKey,
      createdAt: now,
      updatedAt: now,
      metadata: <String, Object?>{
        ...target.metadata,
        'actionType': _actionType.id,
      },
    );
    return TextSystemReferenceActionResult(
      actionType: _actionType,
      target: target,
      inlineMark: inlineMark,
      visibleLabel: visibleLabel,
    );
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    super.dispose();
  }
}
