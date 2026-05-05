enum SourceEditorSurfaceMode { visual, source }

enum SourceEditorOutputMode { hidden, sideBySide, outputOnly }

class SourceEditorConfiguration {
  const SourceEditorConfiguration({
    this.surfaceMode = SourceEditorSurfaceMode.visual,
    this.outputMode = SourceEditorOutputMode.hidden,
  });

  final SourceEditorSurfaceMode surfaceMode;
  final SourceEditorOutputMode outputMode;

  SourceEditorConfiguration copyWith({
    SourceEditorSurfaceMode? surfaceMode,
    SourceEditorOutputMode? outputMode,
  }) {
    return SourceEditorConfiguration(
      surfaceMode: surfaceMode ?? this.surfaceMode,
      outputMode: outputMode ?? this.outputMode,
    );
  }
}
