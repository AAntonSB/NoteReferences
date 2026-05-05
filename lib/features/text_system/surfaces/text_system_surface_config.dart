enum TextSystemSurfaceKind {
  inline,
  sidecarNote,
  todo,
  simpleDocument,
  sourceAware,
  premiumWriter,
  readOnly,
}

enum TextSystemEditorMode {
  plainText,
  richText,
  markdownAware,
  latexAware,
  sourceOnly,
  readOnly,
}

/// Feature switches requested by a text surface.
///
/// This lets the same text engine back a todo field, a note, a LaTeX-aware
/// document, or a full writing environment without hardcoding separate editors.
class TextSystemFeatureSet {
  const TextSystemFeatureSet({
    this.inlineFormatting = false,
    this.highlighting = false,
    this.richClipboard = false,
    this.undoRedo = true,
    this.autosave = true,
    this.shortcuts = true,
    this.commandPalette = false,
    this.blockEditing = false,
    this.sourceView = false,
    this.preview = false,
    this.export = false,
    this.diagnostics = false,
    this.revisionSnapshots = false,
    this.links = false,
    this.lists = false,
  });

  const TextSystemFeatureSet.minimal()
      : inlineFormatting = false,
        highlighting = false,
        richClipboard = false,
        undoRedo = true,
        autosave = true,
        shortcuts = true,
        commandPalette = false,
        blockEditing = false,
        sourceView = false,
        preview = false,
        export = false,
        diagnostics = false,
        revisionSnapshots = false,
        links = false,
        lists = false;

  const TextSystemFeatureSet.richText()
      : inlineFormatting = true,
        highlighting = true,
        richClipboard = true,
        undoRedo = true,
        autosave = true,
        shortcuts = true,
        commandPalette = false,
        blockEditing = true,
        sourceView = false,
        preview = false,
        export = false,
        diagnostics = false,
        revisionSnapshots = true,
        links = true,
        lists = true;

  const TextSystemFeatureSet.sourceAware()
      : inlineFormatting = true,
        highlighting = true,
        richClipboard = true,
        undoRedo = true,
        autosave = true,
        shortcuts = true,
        commandPalette = true,
        blockEditing = true,
        sourceView = true,
        preview = true,
        export = true,
        diagnostics = true,
        revisionSnapshots = true,
        links = true,
        lists = true;

  final bool inlineFormatting;
  final bool highlighting;
  final bool richClipboard;
  final bool undoRedo;
  final bool autosave;
  final bool shortcuts;
  final bool commandPalette;
  final bool blockEditing;
  final bool sourceView;
  final bool preview;
  final bool export;
  final bool diagnostics;
  final bool revisionSnapshots;
  final bool links;
  final bool lists;

  TextSystemFeatureSet copyWith({
    bool? inlineFormatting,
    bool? highlighting,
    bool? richClipboard,
    bool? undoRedo,
    bool? autosave,
    bool? shortcuts,
    bool? commandPalette,
    bool? blockEditing,
    bool? sourceView,
    bool? preview,
    bool? export,
    bool? diagnostics,
    bool? revisionSnapshots,
    bool? links,
    bool? lists,
  }) {
    return TextSystemFeatureSet(
      inlineFormatting: inlineFormatting ?? this.inlineFormatting,
      highlighting: highlighting ?? this.highlighting,
      richClipboard: richClipboard ?? this.richClipboard,
      undoRedo: undoRedo ?? this.undoRedo,
      autosave: autosave ?? this.autosave,
      shortcuts: shortcuts ?? this.shortcuts,
      commandPalette: commandPalette ?? this.commandPalette,
      blockEditing: blockEditing ?? this.blockEditing,
      sourceView: sourceView ?? this.sourceView,
      preview: preview ?? this.preview,
      export: export ?? this.export,
      diagnostics: diagnostics ?? this.diagnostics,
      revisionSnapshots: revisionSnapshots ?? this.revisionSnapshots,
      links: links ?? this.links,
      lists: lists ?? this.lists,
    );
  }
}

/// UI contract for a concrete text-system instance.
class TextSystemSurfaceConfig {
  const TextSystemSurfaceConfig({
    required this.id,
    required this.label,
    required this.kind,
    required this.editorMode,
    this.features = const TextSystemFeatureSet.minimal(),
    this.metadata = const <String, Object?>{},
  });

  factory TextSystemSurfaceConfig.inline({required String id, required String label}) {
    return TextSystemSurfaceConfig(
      id: id,
      label: label,
      kind: TextSystemSurfaceKind.inline,
      editorMode: TextSystemEditorMode.richText,
      features: const TextSystemFeatureSet.minimal().copyWith(
        inlineFormatting: true,
        highlighting: true,
        richClipboard: true,
      ),
    );
  }

  factory TextSystemSurfaceConfig.simpleNote({required String id, required String label}) {
    return TextSystemSurfaceConfig(
      id: id,
      label: label,
      kind: TextSystemSurfaceKind.sidecarNote,
      editorMode: TextSystemEditorMode.richText,
      features: const TextSystemFeatureSet.richText(),
    );
  }

  factory TextSystemSurfaceConfig.readOnly({required String id, required String label}) {
    return TextSystemSurfaceConfig(
      id: id,
      label: label,
      kind: TextSystemSurfaceKind.readOnly,
      editorMode: TextSystemEditorMode.readOnly,
      features: const TextSystemFeatureSet.minimal(),
    );
  }

  factory TextSystemSurfaceConfig.simpleDocument({required String id, required String label}) {
    return TextSystemSurfaceConfig(
      id: id,
      label: label,
      kind: TextSystemSurfaceKind.simpleDocument,
      editorMode: TextSystemEditorMode.richText,
      features: const TextSystemFeatureSet.richText(),
    );
  }

  factory TextSystemSurfaceConfig.latexAware({required String id, required String label}) {
    return TextSystemSurfaceConfig(
      id: id,
      label: label,
      kind: TextSystemSurfaceKind.sourceAware,
      editorMode: TextSystemEditorMode.latexAware,
      features: const TextSystemFeatureSet.sourceAware(),
    );
  }

  final String id;
  final String label;
  final TextSystemSurfaceKind kind;
  final TextSystemEditorMode editorMode;
  final TextSystemFeatureSet features;
  final Map<String, Object?> metadata;

  TextSystemSurfaceConfig copyWith({
    String? id,
    String? label,
    TextSystemSurfaceKind? kind,
    TextSystemEditorMode? editorMode,
    TextSystemFeatureSet? features,
    Map<String, Object?>? metadata,
  }) {
    return TextSystemSurfaceConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      editorMode: editorMode ?? this.editorMode,
      features: features ?? this.features,
      metadata: metadata ?? this.metadata,
    );
  }
}
