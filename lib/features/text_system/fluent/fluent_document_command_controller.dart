import 'package:flutter/foundation.dart';

/// User-facing paragraph styles exposed by the premium writer toolbar.
///
/// Internally these map to TextSystemBlock types/levels. The user should think
/// in document styles, not internal blocks.
enum FluentParagraphStyle {
  paragraph,
  heading1,
  heading2,
  heading3,
  bullet,
  numbered,
  quote,
  todo,
  code,
}

extension FluentParagraphStyleLabel on FluentParagraphStyle {
  String get label {
    return switch (this) {
      FluentParagraphStyle.paragraph => 'Paragraph',
      FluentParagraphStyle.heading1 => 'Heading 1',
      FluentParagraphStyle.heading2 => 'Heading 2',
      FluentParagraphStyle.heading3 => 'Heading 3',
      FluentParagraphStyle.bullet => 'Bullet list',
      FluentParagraphStyle.numbered => 'Numbered list',
      FluentParagraphStyle.quote => 'Quote',
      FluentParagraphStyle.todo => 'Todo',
      FluentParagraphStyle.code => 'Code',
    };
  }
}

/// External command bridge for [FluentDocumentSurface].
///
/// This lets shells such as the premium writer keep formatting/editing controls
/// outside the page while the continuous editor still owns selection, clipboard,
/// paragraph style, and document mapping internally.
class FluentDocumentCommandController extends ChangeNotifier {
  bool _hasExpandedSelection = false;
  bool _canUndo = false;
  bool _canRedo = false;
  bool _readOnly = false;
  FluentParagraphStyle _currentParagraphStyle = FluentParagraphStyle.paragraph;

  VoidCallback? _onBold;
  VoidCallback? _onItalic;
  VoidCallback? _onUnderline;
  VoidCallback? _onHighlight;
  VoidCallback? _onCode;
  VoidCallback? _onLink;
  VoidCallback? _onAddCitation;
  VoidCallback? _onLinkSource;
  VoidCallback? _onLinkDocument;
  VoidCallback? _onLinkProject;
  VoidCallback? _onLinkTodo;
  VoidCallback? _onAddReferenceLink;
  VoidCallback? _onCopy;
  VoidCallback? _onCut;
  VoidCallback? _onPaste;
  VoidCallback? _onUndo;
  VoidCallback? _onRedo;
  ValueChanged<FluentParagraphStyle>? _onApplyParagraphStyle;
  ValueChanged<String>? _onJumpToBlock;

  bool get hasExpandedSelection => _hasExpandedSelection;
  bool get canUndo => _canUndo;
  bool get canRedo => _canRedo;
  bool get readOnly => _readOnly;
  FluentParagraphStyle get currentParagraphStyle => _currentParagraphStyle;

  bool get canFormatSelection => _hasExpandedSelection && !_readOnly;
  bool get canCopy => _hasExpandedSelection;
  bool get canCut => _hasExpandedSelection && !_readOnly;
  bool get canPaste => !_readOnly;
  bool get canApplyParagraphStyle => !_readOnly;
  bool get canCreateReference => canFormatSelection && _onLinkSource != null;
  bool get canJumpToBlock => _onJumpToBlock != null;

  void attach({
    required bool hasExpandedSelection,
    required bool canUndo,
    required bool canRedo,
    required bool readOnly,
    required FluentParagraphStyle currentParagraphStyle,
    required VoidCallback onBold,
    required VoidCallback onItalic,
    required VoidCallback onUnderline,
    required VoidCallback onHighlight,
    required VoidCallback onCode,
    required VoidCallback onLink,
    VoidCallback? onAddCitation,
    VoidCallback? onLinkSource,
    VoidCallback? onLinkDocument,
    VoidCallback? onLinkProject,
    VoidCallback? onLinkTodo,
    VoidCallback? onAddReferenceLink,
    required VoidCallback onCopy,
    required VoidCallback onCut,
    required VoidCallback onPaste,
    required VoidCallback onUndo,
    required VoidCallback onRedo,
    required ValueChanged<FluentParagraphStyle> onApplyParagraphStyle,
    ValueChanged<String>? onJumpToBlock,
  }) {
    final hadReferenceActions = _onLinkSource != null;
    final hasReferenceActions = onLinkSource != null;
    final changed = _hasExpandedSelection != hasExpandedSelection ||
        _canUndo != canUndo ||
        _canRedo != canRedo ||
        _readOnly != readOnly ||
        _currentParagraphStyle != currentParagraphStyle ||
        hadReferenceActions != hasReferenceActions;

    _hasExpandedSelection = hasExpandedSelection;
    _canUndo = canUndo;
    _canRedo = canRedo;
    _readOnly = readOnly;
    _currentParagraphStyle = currentParagraphStyle;
    _onBold = onBold;
    _onItalic = onItalic;
    _onUnderline = onUnderline;
    _onHighlight = onHighlight;
    _onCode = onCode;
    _onLink = onLink;
    _onAddCitation = onAddCitation;
    _onLinkSource = onLinkSource;
    _onLinkDocument = onLinkDocument;
    _onLinkProject = onLinkProject;
    _onLinkTodo = onLinkTodo;
    _onAddReferenceLink = onAddReferenceLink;
    _onCopy = onCopy;
    _onCut = onCut;
    _onPaste = onPaste;
    _onUndo = onUndo;
    _onRedo = onRedo;
    _onApplyParagraphStyle = onApplyParagraphStyle;
    _onJumpToBlock = onJumpToBlock;

    if (changed) notifyListeners();
  }

  void detach() {
    final changed = _hasExpandedSelection ||
        _canUndo ||
        _canRedo ||
        _readOnly ||
        _currentParagraphStyle != FluentParagraphStyle.paragraph ||
        _onLinkSource != null;
    _hasExpandedSelection = false;
    _canUndo = false;
    _canRedo = false;
    _readOnly = false;
    _currentParagraphStyle = FluentParagraphStyle.paragraph;
    _onBold = null;
    _onItalic = null;
    _onUnderline = null;
    _onHighlight = null;
    _onCode = null;
    _onLink = null;
    _onAddCitation = null;
    _onLinkSource = null;
    _onLinkDocument = null;
    _onLinkProject = null;
    _onLinkTodo = null;
    _onAddReferenceLink = null;
    _onCopy = null;
    _onCut = null;
    _onPaste = null;
    _onUndo = null;
    _onRedo = null;
    _onApplyParagraphStyle = null;
    _onJumpToBlock = null;
    if (changed) notifyListeners();
  }

  void applyParagraphStyle(FluentParagraphStyle style) {
    if (canApplyParagraphStyle) _onApplyParagraphStyle?.call(style);
  }

  bool jumpToBlock(String blockId) {
    final callback = _onJumpToBlock;
    if (callback == null || blockId.isEmpty) return false;
    callback(blockId);
    return true;
  }

  void bold() {
    if (canFormatSelection) _onBold?.call();
  }

  void italic() {
    if (canFormatSelection) _onItalic?.call();
  }

  void underline() {
    if (canFormatSelection) _onUnderline?.call();
  }

  void highlight() {
    if (canFormatSelection) _onHighlight?.call();
  }

  void code() {
    if (canFormatSelection) _onCode?.call();
  }

  void link() {
    if (canFormatSelection) _onLink?.call();
  }

  void addCitation() {
    if (canCreateReference) _onAddCitation?.call();
  }

  void linkSource() {
    if (canCreateReference) _onLinkSource?.call();
  }

  void linkDocument() {
    if (canCreateReference) _onLinkDocument?.call();
  }

  void linkProject() {
    if (canCreateReference) _onLinkProject?.call();
  }

  void linkTodo() {
    if (canCreateReference) _onLinkTodo?.call();
  }

  void addReferenceLink() {
    if (canCreateReference) _onAddReferenceLink?.call();
  }

  void copy() {
    if (canCopy) _onCopy?.call();
  }

  void cut() {
    if (canCut) _onCut?.call();
  }

  void paste() {
    if (canPaste) _onPaste?.call();
  }

  void undo() {
    if (_canUndo && !_readOnly) _onUndo?.call();
  }

  void redo() {
    if (_canRedo && !_readOnly) _onRedo?.call();
  }
}
