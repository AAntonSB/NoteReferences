import 'package:flutter/material.dart';

import '../core/text_mark.dart';
import '../core/text_system_controller.dart';
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
    this.padding = const EdgeInsets.all(14),
    this.showTitle = false,
    this.onLinkTap,
  });

  final TextSystemController textController;
  final TextSystemSurfaceConfig? config;
  final bool selectable;
  final EdgeInsetsGeometry padding;
  final bool showTitle;
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8)),
            ),
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showTitle) ...[
                    Text(document.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 10),
                  ],
                  if (document.blocks.isEmpty)
                    Text('No text.', style: theme.textTheme.bodyMedium)
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
