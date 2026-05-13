import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_page_spec.dart';
import 'paged_document_layout_engine.dart';

class DocumentPageModel {
  DocumentPageModel({
    required this.id,
    required String initialText,
    required this.startOffset,
    required this.endOffset,
  })  : textController = TextEditingController(text: initialText),
        focusNode = FocusNode(debugLabel: id);

  final String id;
  final TextEditingController textController;
  final FocusNode focusNode;

  int startOffset;
  int endOffset;

  String get text => textController.text;
  bool get isEmpty => text.trim().isEmpty;

  bool containsGlobalOffset(int offset) {
    if (startOffset == endOffset) {
      return offset == startOffset;
    }
    return offset >= startOffset && offset <= endOffset;
  }

  void dispose() {
    textController.dispose();
    focusNode.dispose();
  }
}

@immutable
class PagedDocumentDebugSnapshot {
  const PagedDocumentDebugSnapshot({
    required this.pageCount,
    required this.characterCount,
    required this.pageRanges,
  });

  final int pageCount;
  final int characterCount;
  final List<String> pageRanges;
}

/// Controller for a page-bound document editor.
///
/// Phase 13C changes the internal model:
/// - 13A/13B treated page text fields as the document.
/// - 13C keeps a canonical document string and treats pages as layout slices.
///
/// That makes reflow bidirectional. Adding text pushes forward. Deleting text
/// pulls later text backward into earlier pages. Changing page size or academic
/// typography repaginates from the same canonical source.
class PagedDocumentController extends ChangeNotifier {
  PagedDocumentController({
    String initialText = '',
    AcademicPageStyle? initialPageStyle,
  }) : _pageStyle = initialPageStyle ?? AcademicPageStyle.from() {
    setPlainText(initialText, notify: false);
  }

  final List<DocumentPageModel> _pages = <DocumentPageModel>[];
  bool _isApplyingLayout = false;
  int _idCounter = 0;

  String _documentText = '';
  AcademicPageStyle _pageStyle;

  List<DocumentPageModel> get pages =>
      List<DocumentPageModel>.unmodifiable(_pages);

  AcademicPageStyle get pageStyle => _pageStyle;

  bool get isEmpty => _documentText.trim().isEmpty;

  String get plainText => _documentText.trimRight();

  String get rawText => _documentText;

  String get plainTextWithPageBreaks => _pages
      .map((page) => page.text.trimRight())
      .join('\n\n--- page break ---\n\n');

  PagedDocumentDebugSnapshot get debugSnapshot {
    return PagedDocumentDebugSnapshot(
      pageCount: _pages.length,
      characterCount: _documentText.length,
      pageRanges: _pages
          .map((page) => '${page.startOffset}..${page.endOffset}')
          .toList(growable: false),
    );
  }

  void setPlainText(String value, {bool notify = true}) {
    _documentText = value.replaceAll('\r\n', '\n');
    _repaginate(
      preferredGlobalCaretOffset: 0,
      preserveFocus: false,
    );

    if (notify) {
      notifyListeners();
    }
  }

  void setPageSize(DocumentPageSize size) {
    if (size == _pageStyle.pageSize) {
      return;
    }

    final caret = _currentGlobalCaretOffset();

    _pageStyle = AcademicPageStyle.from(
      pageSize: size,
      typographyPreset: _pageStyle.typographyPreset,
      showMarginGuides: _pageStyle.showMarginGuides,
    );

    _repaginate(
      preferredGlobalCaretOffset: caret,
      preserveFocus: true,
    );
    notifyListeners();
  }

  void setTypographyPreset(AcademicTypographyPreset preset) {
    if (preset == _pageStyle.typographyPreset) {
      return;
    }

    final caret = _currentGlobalCaretOffset();

    _pageStyle = AcademicPageStyle.from(
      pageSize: _pageStyle.pageSize,
      typographyPreset: preset,
      showMarginGuides: _pageStyle.showMarginGuides,
    );

    _repaginate(
      preferredGlobalCaretOffset: caret,
      preserveFocus: true,
    );
    notifyListeners();
  }

  void setMarginGuidesVisible(bool visible) {
    if (visible == _pageStyle.showMarginGuides) {
      return;
    }

    _pageStyle = _pageStyle.copyWith(showMarginGuides: visible);
    notifyListeners();
  }

  /// Adds writing room at the end of the document and moves focus there.
  ///
  /// Since Phase 13C has automatic pagination, this is not a hard/manual page
  /// break yet. Manual page breaks should become their own explicit block type
  /// later, not an invisible text hack.
  void addPage({int? afterIndex, bool focus = true}) {
    final insertionOffset = afterIndex == null || afterIndex >= _pages.length
        ? _documentText.length
        : _pages[afterIndex].endOffset;

    final spacer = _documentText.isEmpty ? '' : '\n\n';
    _documentText =
        _documentText.replaceRange(insertionOffset, insertionOffset, spacer);

    final caret = insertionOffset + spacer.length;

    _repaginate(
      preferredGlobalCaretOffset: caret,
      preserveFocus: focus,
    );

    if (focus) {
      _focusGlobalOffset(caret);
    }

    notifyListeners();
  }

  void removePageAt(int index) {
    if (_pages.length <= 1 || index < 0 || index >= _pages.length) {
      return;
    }

    final page = _pages[index];
    _documentText = _documentText.replaceRange(
      page.startOffset,
      page.endOffset,
      '',
    );

    final caret = math.min(page.startOffset, _documentText.length);

    _repaginate(
      preferredGlobalCaretOffset: caret,
      preserveFocus: true,
    );
    _focusGlobalOffset(caret);
    notifyListeners();
  }

  void focusPage(int index) {
    if (index < 0 || index >= _pages.length) {
      return;
    }
    _pages[index].focusNode.requestFocus();
  }

  void focusDocumentEnd() {
    _focusGlobalOffset(_documentText.length);
  }

  void trimEmptyTrailingPages() {
    final trimmed = _documentText.trimRight();
    if (trimmed == _documentText) {
      return;
    }

    _documentText = trimmed;
    _repaginate(
      preferredGlobalCaretOffset: _documentText.length,
      preserveFocus: true,
    );
    notifyListeners();
  }

  DocumentPageModel _createPage({
    required String initialText,
    required int startOffset,
    required int endOffset,
  }) {
    final id =
        'document_page_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

    final page = DocumentPageModel(
      id: id,
      initialText: initialText,
      startOffset: startOffset,
      endOffset: endOffset,
    );

    page.textController.addListener(() => _handlePageTextChanged(page));
    return page;
  }

  void _handlePageTextChanged(DocumentPageModel page) {
    if (_isApplyingLayout) {
      return;
    }

    final index = _pages.indexWhere((candidate) => candidate.id == page.id);
    if (index == -1) {
      return;
    }

    final selection = page.textController.selection;
    final localCaretOffset = selection.isValid
        ? math.max(0, math.min(selection.baseOffset, page.text.length))
        : page.text.length;

    final globalCaretOffset = page.startOffset + localCaretOffset;

    final safeStart =
        math.max(0, math.min(page.startOffset, _documentText.length));
    final safeEnd =
        math.max(safeStart, math.min(page.endOffset, _documentText.length));

    _documentText = _documentText.replaceRange(
      safeStart,
      safeEnd,
      page.text,
    );

    final adjustedGlobalCaretOffset = math.min(
      _documentText.length,
      math.max(0, globalCaretOffset),
    );

    _repaginate(
      preferredGlobalCaretOffset: adjustedGlobalCaretOffset,
      preserveFocus: true,
    );

    _focusGlobalOffset(adjustedGlobalCaretOffset);
    notifyListeners();
  }

  void _repaginate({
    required int preferredGlobalCaretOffset,
    required bool preserveFocus,
  }) {
    _isApplyingLayout = true;

    final engine = PagedDocumentLayoutEngine(pageStyle: _pageStyle);
    final slices = engine.paginate(_documentText);

    while (_pages.length < slices.length) {
      _pages.add(
        _createPage(
          initialText: '',
          startOffset: 0,
          endOffset: 0,
        ),
      );
    }

    while (_pages.length > slices.length) {
      final removed = _pages.removeLast();
      removed.dispose();
    }

    for (var i = 0; i < slices.length; i++) {
      final page = _pages[i];
      final slice = slices[i];

      page.startOffset = slice.startOffset;
      page.endOffset = slice.endOffset;

      _setText(
        page.textController,
        slice.text,
        selectionOffset: _localOffsetForGlobalOffset(
          slice,
          preferredGlobalCaretOffset,
        ),
      );
    }

    _isApplyingLayout = false;

    if (preserveFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusGlobalOffset(preferredGlobalCaretOffset);
      });
    }
  }

  int _currentGlobalCaretOffset() {
    for (final page in _pages) {
      if (!page.focusNode.hasFocus) {
        continue;
      }

      final selection = page.textController.selection;
      final local = selection.isValid
          ? math.max(0, math.min(selection.baseOffset, page.text.length))
          : page.text.length;

      return math.min(_documentText.length, page.startOffset + local);
    }

    return _documentText.length;
  }

  int _localOffsetForGlobalOffset(PageTextSlice slice, int globalOffset) {
    if (globalOffset < slice.startOffset) {
      return 0;
    }
    if (globalOffset > slice.endOffset) {
      return slice.text.length;
    }
    return math.max(
      0,
      math.min(globalOffset - slice.startOffset, slice.text.length),
    );
  }

  void _focusGlobalOffset(int globalOffset) {
    if (_pages.isEmpty) {
      return;
    }

    final safeGlobalOffset =
        math.max(0, math.min(globalOffset, _documentText.length));

    var targetPage = _pages.last;
    for (final page in _pages) {
      if (page.containsGlobalOffset(safeGlobalOffset)) {
        targetPage = page;
        break;
      }
    }

    final localOffset = math.max(
      0,
      math.min(
        safeGlobalOffset - targetPage.startOffset,
        targetPage.text.length,
      ),
    );

    targetPage.focusNode.requestFocus();
    targetPage.textController.selection =
        TextSelection.collapsed(offset: localOffset);
  }

  void _setText(
    TextEditingController controller,
    String value, {
    required int selectionOffset,
  }) {
    final safeSelectionOffset = math.min(
      math.max(selectionOffset, 0),
      value.length,
    );

    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: safeSelectionOffset),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    for (final page in _pages) {
      page.dispose();
    }
    _pages.clear();
    super.dispose();
  }
}
