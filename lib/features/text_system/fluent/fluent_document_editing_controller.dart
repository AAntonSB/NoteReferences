import 'package:flutter/material.dart';

import '../core/text_system_document.dart';
import '../core/text_system_document_position.dart';
import '../core/text_system_document_range.dart';
import 'fluent_document_buffer.dart';
import 'fluent_document_buffer_mapper.dart';
import 'fluent_document_text_styler.dart';

/// Flutter editing controller for the experimental continuous document surface.
///
/// This is intentionally modest in Phase 9A. It proves that the visible editor
/// can be one continuous text buffer while the structured document remains the
/// source of truth underneath.
class FluentDocumentEditingController extends TextEditingController {
  FluentDocumentEditingController({required TextSystemDocument document})
      : _buffer = FluentDocumentBufferMapper.fromDocument(document),
        super(text: FluentDocumentBufferMapper.fromDocument(document).text);

  FluentDocumentBuffer _buffer;
  bool _syncingFromDocument = false;

  FluentDocumentBuffer get buffer => _buffer;
  TextSystemDocument get document => _buffer.document;
  bool get isSyncingFromDocument => _syncingFromDocument;

  void syncFromDocument(TextSystemDocument document) {
    final nextBuffer = FluentDocumentBufferMapper.fromDocument(document);
    if (nextBuffer.text == text &&
        FluentDocumentBufferMapper.equivalentDocumentShape(nextBuffer.document, _buffer.document)) {
      _buffer = nextBuffer;
      return;
    }

    final currentSelection = selection;
    final safeSelection = TextSelection(
      baseOffset: currentSelection.baseOffset.clamp(0, nextBuffer.text.length).toInt(),
      extentOffset: currentSelection.extentOffset.clamp(0, nextBuffer.text.length).toInt(),
      affinity: currentSelection.affinity,
      isDirectional: currentSelection.isDirectional,
    );

    _syncingFromDocument = true;
    _buffer = nextBuffer;
    value = TextEditingValue(
      text: nextBuffer.text,
      selection: safeSelection,
      composing: TextRange.empty,
    );
    _syncingFromDocument = false;
  }

  TextSystemDocument documentFromCurrentBuffer() {
    return FluentDocumentBufferMapper.documentFromBuffer(
      previousDocument: _buffer.document,
      bufferText: text,
    );
  }

  void acceptDocumentFromCurrentBuffer(TextSystemDocument document) {
    _buffer = FluentDocumentBufferMapper.fromDocument(document);
  }

  TextSystemDocumentRange? documentRangeForSelection([TextSelection? selectionOverride]) {
    final effectiveSelection = selectionOverride ?? selection;
    if (!effectiveSelection.isValid || effectiveSelection.isCollapsed) return null;
    return FluentDocumentBufferMapper.rangeFromBufferSelection(
      _buffer,
      effectiveSelection.start,
      effectiveSelection.end,
    );
  }

  TextSystemDocumentPosition documentPositionForBufferOffset(int offset) {
    return FluentDocumentBufferMapper.positionForBufferOffset(_buffer, offset);
  }

  int bufferOffsetForDocumentPosition(TextSystemDocumentPosition position) {
    return _buffer.offsetForPosition(position);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return const FluentDocumentTextStyler().buildTextSpan(
      context: context,
      buffer: _buffer,
      text: text,
      composing: value.composing,
      withComposing: withComposing,
      baseStyle: style,
    );
  }
}
