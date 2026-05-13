import 'package:flutter/material.dart';

import '../core/text_system_controller.dart';
import '../fluent/fluent_document_command_controller.dart';
import '../fluent/fluent_document_surface.dart';
import '../persistence/text_system_autosave_controller.dart';
import '../references/actions/text_system_reference_actions.dart';
import 'document_text_surface.dart';

enum TextSystemDocumentSurfaceMode {
  fluent,
  basic,
}

class TextSystemDocumentSurfaceConfig {
  const TextSystemDocumentSurfaceConfig({
    this.mode = TextSystemDocumentSurfaceMode.fluent,
    this.placeholder = 'Start writing...',
    this.showStatusBar = true,
    this.showToolbar = true,
    this.showFrame = true,
    this.showTitle = true,
    this.readOnly = false,
    this.minLines = 16,
    this.maxLines,
    this.padding = const EdgeInsets.all(20),
    this.textStyle,
  });

  const TextSystemDocumentSurfaceConfig.fluent({
    this.placeholder = 'Start writing...',
    this.showStatusBar = true,
    this.showToolbar = true,
    this.showFrame = true,
    this.showTitle = true,
    this.readOnly = false,
    this.minLines = 16,
    this.maxLines,
    this.padding = const EdgeInsets.all(20),
    this.textStyle,
  }) : mode = TextSystemDocumentSurfaceMode.fluent;

  const TextSystemDocumentSurfaceConfig.basic({
    this.placeholder = 'Start writing...',
    this.showStatusBar = true,
    this.showToolbar = true,
    this.showFrame = true,
    this.showTitle = true,
    this.readOnly = false,
    this.minLines = 16,
    this.maxLines,
    this.padding = const EdgeInsets.all(20),
    this.textStyle,
  }) : mode = TextSystemDocumentSurfaceMode.basic;

  final TextSystemDocumentSurfaceMode mode;
  final String placeholder;
  final bool showStatusBar;
  final bool showToolbar;
  final bool showFrame;
  final bool showTitle;
  final bool readOnly;
  final int minLines;
  final int? maxLines;
  final EdgeInsetsGeometry padding;
  final TextStyle? textStyle;

  TextSystemDocumentSurfaceConfig copyWith({
    TextSystemDocumentSurfaceMode? mode,
    String? placeholder,
    bool? showStatusBar,
    bool? showToolbar,
    bool? showFrame,
    bool? showTitle,
    bool? readOnly,
    int? minLines,
    int? maxLines,
    EdgeInsetsGeometry? padding,
    TextStyle? textStyle,
  }) {
    return TextSystemDocumentSurfaceConfig(
      mode: mode ?? this.mode,
      placeholder: placeholder ?? this.placeholder,
      showStatusBar: showStatusBar ?? this.showStatusBar,
      showToolbar: showToolbar ?? this.showToolbar,
      showFrame: showFrame ?? this.showFrame,
      showTitle: showTitle ?? this.showTitle,
      readOnly: readOnly ?? this.readOnly,
      minLines: minLines ?? this.minLines,
      maxLines: maxLines ?? this.maxLines,
      padding: padding ?? this.padding,
      textStyle: textStyle ?? this.textStyle,
    );
  }

  Map<String, Object?> toDebugJson() {
    return <String, Object?>{
      'mode': mode.name,
      'placeholder': placeholder,
      'showStatusBar': showStatusBar,
      'showToolbar': showToolbar,
      'showFrame': showFrame,
      'showTitle': showTitle,
      'readOnly': readOnly,
      'minLines': minLines,
      'maxLines': maxLines,
      'padding': padding.toString(),
      'textStyle': textStyle?.toString(),
    };
  }
}

class TextSystemDocumentSurface extends StatelessWidget {
  const TextSystemDocumentSurface({
    super.key,
    required this.textController,
    this.autosaveController,
    this.config,
    this.mode,
    this.placeholder,
    this.showStatusBar,
    this.showToolbar,
    this.showFrame,
    this.showTitle,
    this.readOnly,
    this.minLines,
    this.maxLines,
    this.padding,
    this.textStyle,
    this.onFluentBufferChanged,
    this.fluentCommandController,
    this.referenceActionRepository,
  });

  final TextSystemController textController;
  final TextSystemAutosaveController? autosaveController;

  final TextSystemDocumentSurfaceConfig? config;

  final TextSystemDocumentSurfaceMode? mode;
  final String? placeholder;
  final bool? showStatusBar;
  final bool? showToolbar;
  final bool? showFrame;
  final bool? showTitle;
  final bool? readOnly;
  final int? minLines;
  final int? maxLines;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  final ValueChanged<dynamic>? onFluentBufferChanged;
  final FluentDocumentCommandController? fluentCommandController;
  final TextSystemReferenceActionRepository? referenceActionRepository;

  TextSystemDocumentSurfaceConfig get _effectiveConfig {
    final base = config ?? const TextSystemDocumentSurfaceConfig();
    return base.copyWith(
      mode: mode,
      placeholder: placeholder,
      showStatusBar: showStatusBar,
      showToolbar: showToolbar,
      showFrame: showFrame,
      showTitle: showTitle,
      readOnly: readOnly,
      minLines: minLines,
      maxLines: maxLines,
      padding: padding,
      textStyle: textStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveConfig = _effectiveConfig;

    return switch (effectiveConfig.mode) {
      TextSystemDocumentSurfaceMode.fluent => FluentDocumentSurface(
          textController: textController,
          autosaveController: autosaveController,
          placeholder: effectiveConfig.placeholder,
          showStatusBar: effectiveConfig.showStatusBar,
          showToolbar: effectiveConfig.showToolbar,
          showFrame: effectiveConfig.showFrame,
          minLines: effectiveConfig.minLines,
          maxLines: effectiveConfig.maxLines,
          padding: effectiveConfig.padding,
          textStyle: effectiveConfig.textStyle,
          readOnly: effectiveConfig.readOnly,
          onBufferChanged: onFluentBufferChanged,
          commandController: fluentCommandController,
          referenceActionRepository: referenceActionRepository,
        ),
      TextSystemDocumentSurfaceMode.basic => DocumentTextSurface(
          textController: textController,
          autosaveController: autosaveController,
          placeholder: effectiveConfig.placeholder,
          showTitle: effectiveConfig.showTitle,
          showStatusBars: effectiveConfig.showStatusBar,
          enabled: !effectiveConfig.readOnly,
          maxBlockLines: effectiveConfig.maxLines ?? 12,
        ),
    };
  }
}
