/// High-level implementation modes for the long-form TextSystem editor.
///
/// Phase 16A introduced this seam so the current production editor could be
/// isolated before the owned document editor was added. The owned path now has
/// its first basic keyboard-editing loop, but it remains experimental.
enum TextSystemEditorSurfaceMode {
  /// Current real-page editor backed by page fragments and local TextFields.
  currentPagedTextFieldBridge,

  /// Experimental owned document editor. It renders from the document and paged
  /// layout model without body TextFields. Click-to-caret, atomic object hit
  /// testing, and basic desktop keyboard editing are active; range selection,
  /// rich clipboard, and IME support come later.
  ownedDocumentExperimental;

  String get label {
    return switch (this) {
      TextSystemEditorSurfaceMode.currentPagedTextFieldBridge => 'Current real-page editor',
      TextSystemEditorSurfaceMode.ownedDocumentExperimental => 'Owned document editor',
    };
  }

  String get description {
    return switch (this) {
      TextSystemEditorSurfaceMode.currentPagedTextFieldBridge =>
        'The stable production path. Uses the existing paged block surface while the owned editor is built beside it.',
      TextSystemEditorSurfaceMode.ownedDocumentExperimental =>
        'Experimental owned editor. The document model and layout index own the rendered surface; click-to-caret, object hit testing, and basic desktop keyboard editing are active.',
    };
  }

  bool get isImplemented {
    return switch (this) {
      TextSystemEditorSurfaceMode.currentPagedTextFieldBridge => true,
      TextSystemEditorSurfaceMode.ownedDocumentExperimental => true,
    };
  }
}
