import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';

/// Platform text-input bridge for the owned editor.
///
/// This is deliberately not a hidden [TextField]. The owned editor remains the
/// source of truth for document text, selection, caret, and layout. This client
/// only owns the short-lived platform input buffer that IMEs need for dead keys,
/// accents, emoji, and CJK composition.
class TextSystemEditorTextInputClient extends ChangeNotifier implements TextInputClient {
  TextSystemEditorTextInputClient({
    required bool Function() canAcceptInput,
    required TextSystemDocumentRange? Function() activeRange,
    required TextSystemDocumentPosition? Function() activeTextPosition,
    required FutureOr<void> Function(String text) commitText,
    required FutureOr<void> Function() deleteBackward,
    required FutureOr<void> Function() deleteForward,
    required FutureOr<void> Function() insertNewline,
  })  : _canAcceptInput = canAcceptInput,
        _activeRange = activeRange,
        _activeTextPosition = activeTextPosition,
        _commitText = commitText,
        _deleteBackward = deleteBackward,
        _deleteForward = deleteForward,
        _insertNewline = insertNewline;

  final bool Function() _canAcceptInput;
  final TextSystemDocumentRange? Function() _activeRange;
  final TextSystemDocumentPosition? Function() _activeTextPosition;
  final FutureOr<void> Function(String text) _commitText;
  final FutureOr<void> Function() _deleteBackward;
  final FutureOr<void> Function() _deleteForward;
  final FutureOr<void> Function() _insertNewline;

  TextInputConnection? _connection;
  static const TextEditingValue _emptyEditingValue = TextEditingValue(
    text: '',
    selection: TextSelection.collapsed(offset: 0),
  );

  TextEditingValue _editingValue = _emptyEditingValue;
  TextSystemDocumentPosition? _compositionAnchor;

  String? _recentRawKeyboardText;
  DateTime? _recentRawKeyboardTextAt;

  bool get isAttached => _connection?.attached == true;
  bool get hasComposingText => composingText.isNotEmpty;
  String get composingText {
    final composing = _editingValue.composing;
    if (!composing.isValid || composing.isCollapsed) return '';
    final start = composing.start.clamp(0, _editingValue.text.length).toInt();
    final end = composing.end.clamp(start, _editingValue.text.length).toInt();
    if (start >= end) return '';
    return _editingValue.text.substring(start, end);
  }

  TextSystemDocumentPosition? get compositionAnchor => _compositionAnchor ?? _activeTextPosition();

  TextInputConfiguration _configurationForView(int viewId) => TextInputConfiguration(
        viewId: viewId,
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableSuggestions: true,
        autocorrect: true,
      );

  /// Opens the platform text input connection.
  ///
  /// Important: do not immediately call [TextInputConnection.setEditingState]
  /// after [TextInput.attach]. On Windows this can race the platform-side
  /// `setClient` call and produce:
  ///
  ///   Set editing state has been invoked, but no client is set.
  ///
  /// The owned editor keeps an empty platform buffer and exposes the current
  /// value through [currentTextEditingValue], so showing the connection is
  /// sufficient for this bridge phase.
  void open({required int viewId}) {
    if (!_canAcceptInput()) {
      close();
      return;
    }
    _compositionAnchor = _activeTextPosition();
    try {
      if (!isAttached) {
        _connection = TextInput.attach(this, _configurationForView(viewId));
      }
      _connection?.show();
    } on PlatformException catch (error, stackTrace) {
      // The owned editor must remain usable even if the platform text-input
      // bridge rejects attachment. Raw hardware-key editing still works without
      // this connection. The most common cause on recent Flutter desktop builds
      // is a missing view id, which is prevented by passing View.of(context).viewId
      // from the surface, but keep this guard so a failed bridge never breaks
      // typing/copy/paste.
      _connection = null;
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'text_system',
        context: ErrorDescription('while opening owned editor text input bridge'),
      ));
    }
  }

  void close() {
    _clearComposing(notify: false);
    _connection?.close();
    _connection = null;
    notifyListeners();
  }

  void refreshFromEditorSelection() {
    if (!_canAcceptInput()) {
      close();
      return;
    }
    _compositionAnchor = _activeTextPosition();
    notifyListeners();
  }

  void resetComposingBuffer() {
    _clearComposing();
  }

  /// Records text that has already been inserted from a raw hardware-key event.
  ///
  /// Desktop Flutter does not consistently route ordinary hardware-key text
  /// through [updateEditingValue] for custom [TextInputClient]s. The editor
  /// therefore keeps the raw keyboard insertion path as a fallback. If the
  /// platform later echoes the same committed text through the input client, this
  /// lets us suppress that duplicate commit without disabling IME composition.
  void markRawKeyboardTextHandled(String text) {
    if (text.isEmpty) return;
    _recentRawKeyboardText = text;
    _recentRawKeyboardTextAt = DateTime.now();
  }

  @override
  TextEditingValue get currentTextEditingValue => _editingValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (!_canAcceptInput()) {
      _editingValue = _emptyEditingValue;
      _clearComposing();
      return;
    }

    final composing = value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      _editingValue = value;
      _compositionAnchor ??= _activeTextPosition();
      notifyListeners();
      return;
    }

    final committedText = value.text;
    if (committedText.isNotEmpty) {
      if (_shouldSuppressRawKeyboardEcho(committedText)) {
        _editingValue = _emptyEditingValue;
        _clearComposing();
        return;
      }
      final anchorRange = _activeRange();
      _compositionAnchor = anchorRange?.normalized().start ?? _activeTextPosition();
      unawaited(Future<void>.sync(() => _commitText(committedText)).whenComplete(() {
        _editingValue = _emptyEditingValue;
        _clearComposing();
      }));
      return;
    }

    _editingValue = _emptyEditingValue;
    _clearComposing();
  }

  bool _shouldSuppressRawKeyboardEcho(String committedText) {
    final rawText = _recentRawKeyboardText;
    final rawTime = _recentRawKeyboardTextAt;
    if (rawText == null || rawTime == null) return false;
    final elapsed = DateTime.now().difference(rawTime);
    if (elapsed > const Duration(milliseconds: 750)) {
      _recentRawKeyboardText = null;
      _recentRawKeyboardTextAt = null;
      return false;
    }
    if (committedText != rawText) return false;
    _recentRawKeyboardText = null;
    _recentRawKeyboardTextAt = null;
    return true;
  }

  @override
  void performAction(TextInputAction action) {
    switch (action) {
      case TextInputAction.newline:
      case TextInputAction.done:
        unawaited(Future<void>.sync(_insertNewline));
        break;
      default:
        break;
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void connectionClosed() {
    _connection = null;
    _clearComposing();
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {}

  @override
  void performSelector(String selectorName) {
    switch (selectorName) {
      case 'deleteBackward:':
        unawaited(Future<void>.sync(_deleteBackward));
        break;
      case 'deleteForward:':
        unawaited(Future<void>.sync(_deleteForward));
        break;
      case 'insertNewline:':
        unawaited(Future<void>.sync(_insertNewline));
        break;
      default:
        break;
    }
  }

  void _clearComposing({bool notify = true}) {
    _editingValue = _emptyEditingValue;
    _compositionAnchor = _activeTextPosition();
    if (notify) notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
