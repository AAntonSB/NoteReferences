import 'package:flutter/material.dart';

import '../core/text_mark.dart';
import '../core/text_system_controller.dart';
import 'text_system_editable_surface_frame.dart';
import 'text_system_rich_text_renderer.dart';
import 'text_system_surface_config.dart';

/// Non-mutating renderer for project-wide structured text.
///
/// This lets previews, search snippets, archived revisions, side-note summaries,
/// and collapsed text cards display the same text-system model without exposing
/// editing controls or creating transactions.
class ReadOnlyTextSurface extends StatelessWidget {
  const ReadOnlyTextSurface({
    super.key,
    required this.textController,
    this.config,
    this.selectable = true,
    this.padding = const EdgeInsets.all(16),
    this.showTitle = false,
    this.frameStyle = TextSystemSurfaceFrameStyle.subtle,
    this.onLinkTap,
  });

  final TextSystemController textController;
  final TextSystemSurfaceConfig? config;
  final bool selectable;
  final EdgeInsetsGeometry padding;
  final bool showTitle;
  final TextSystemSurfaceFrameStyle frameStyle;
  final void Function(TextMark mark)? onLinkTap;

  TextSystemSurfaceConfig get _config => config ??
      const TextSystemSurfaceConfig(
        id: 'read-only-text-surface',
        label: 'Read-only text',
        kind: TextSystemSurfaceKind.readOnly,
        editorMode: TextSystemEditorMode.readOnly,
        features: TextSystemFeatureSet.minimal(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: textController,
      builder: (context, _) {
        final document = textController.document;
        return Semantics(
          label: _config.label,
          readOnly: true,
          child: _ReadOnlyFrame(
            frameStyle: frameStyle,
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTitle) ...[
                    Text(document.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                  ],
                  if (document.blocks.isEmpty)
                    Text(
                      'Nothing written yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final block in document.blocks)
                      TextSystemRichTextRenderer.block(
                        context,
                        block: block,
                        selectable: selectable,
                        onLinkTap: onLinkTap,
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReadOnlyFrame extends StatelessWidget {
  const _ReadOnlyFrame({
    required this.frameStyle,
    required this.child,
  });

  final TextSystemSurfaceFrameStyle frameStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (frameStyle == TextSystemSurfaceFrameStyle.plain) {
      return child;
    }
    final outlined = frameStyle == TextSystemSurfaceFrameStyle.outlined;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? colorScheme.surface : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(outlined ? 18 : 14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: outlined ? 0.78 : 0.38),
        ),
      ),
      child: child,
    );
  }
}
