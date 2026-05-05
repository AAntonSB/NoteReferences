import 'package:flutter/material.dart';

import '../core/source_document_block.dart';
import '../core/source_document_controller.dart';
import '../core/source_document_parser.dart';
import '../core/source_edit.dart';
import '../core/source_editor_configuration.dart';

/// Source-aware editor surface.
///
/// Phase 3 makes the visual surface editable without abandoning the canonical
/// source model: visual blocks render calmly by default, but tapping/clicking a
/// block reveals and edits the underlying source range for that block. This is
/// deliberately conservative and safe for LaTeX: source remains the truth, and
/// unsupported/broken constructs are edited as source blocks instead of being
/// guessed into broken visuals.
class SourceAwareEditor extends StatefulWidget {
  const SourceAwareEditor({
    super.key,
    required this.controller,
    required this.parser,
    this.configuration = const SourceEditorConfiguration(),
    this.onConfigurationChanged,
    this.outputPane,
  });

  final SourceDocumentController controller;
  final SourceDocumentParser parser;
  final SourceEditorConfiguration configuration;
  final ValueChanged<SourceEditorConfiguration>? onConfigurationChanged;
  final Widget? outputPane;

  @override
  State<SourceAwareEditor> createState() => _SourceAwareEditorState();
}

class _SourceAwareEditorState extends State<SourceAwareEditor> {
  late TextEditingController _sourceController;

  @override
  void initState() {
    super.initState();
    _sourceController = TextEditingController(text: widget.controller.source);
    widget.controller.addListener(_syncFromSourceController);
  }

  @override
  void didUpdateWidget(SourceAwareEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromSourceController);
      widget.controller.addListener(_syncFromSourceController);
      _sourceController.dispose();
      _sourceController = TextEditingController(text: widget.controller.source);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromSourceController);
    _sourceController.dispose();
    super.dispose();
  }

  void _syncFromSourceController() {
    if (_sourceController.text == widget.controller.source) return;
    final selection = _sourceController.selection;
    _sourceController.text = widget.controller.source;
    if (selection.isValid) {
      final safeOffset = selection.baseOffset.clamp(0, _sourceController.text.length);
      _sourceController.selection = TextSelection.collapsed(offset: safeOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.configuration;
    final showOutput =
        config.outputMode != SourceEditorOutputMode.hidden && widget.outputPane != null;

    if (config.outputMode == SourceEditorOutputMode.outputOnly &&
        widget.outputPane != null) {
      return widget.outputPane!;
    }

    final editor = config.surfaceMode == SourceEditorSurfaceMode.source
        ? _buildSourceEditor(context)
        : _buildVisualEditor(context);

    if (!showOutput) return editor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: editor),
        const VerticalDivider(width: 1),
        Expanded(child: widget.outputPane!),
      ],
    );
  }

  Widget _buildSourceEditor(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: TextField(
        controller: _sourceController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.45),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(24),
          hintText: 'Start writing source...',
        ),
        onChanged: widget.controller.replaceSource,
      ),
    );
  }

  Widget _buildVisualEditor(BuildContext context) {
    final parsed = widget.parser.parse(SourceParseContext(source: widget.controller.source));
    final theme = Theme.of(context);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 44),
                  child: parsed.blocks.isEmpty
                      ? _EmptyVisualDocument(onTap: () => _switchToSourceMode())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final block in parsed.blocks)
                              _SourceBlockEditor(
                                key: ValueKey(block.id),
                                block: block,
                                sourceText: _safeSourceFor(block),
                                onSourceCommit: (nextSource) {
                                  widget.controller.applyEdit(
                                    SourceEdit.replace(block.sourceRange, nextSource),
                                  );
                                },
                              ),
                            if (parsed.errors.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              _ParserNotes(errors: parsed.errors),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _safeSourceFor(SourceDocumentBlock block) {
    final source = widget.controller.source;
    final range = block.sourceRange.clamp(source.length);
    return source.substring(range.start, range.end);
  }

  void _switchToSourceMode() {
    widget.onConfigurationChanged?.call(
      widget.configuration.copyWith(surfaceMode: SourceEditorSurfaceMode.source),
    );
  }
}

class _EmptyVisualDocument extends StatelessWidget {
  const _EmptyVisualDocument({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_document, size: 36, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Start writing source', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Switch to source mode to create the first block.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBlockEditor extends StatefulWidget {
  const _SourceBlockEditor({
    super.key,
    required this.block,
    required this.sourceText,
    required this.onSourceCommit,
  });

  final SourceDocumentBlock block;
  final String sourceText;
  final ValueChanged<String> onSourceCommit;

  @override
  State<_SourceBlockEditor> createState() => _SourceBlockEditorState();
}

class _SourceBlockEditorState extends State<_SourceBlockEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editingSource = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.sourceText);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(_SourceBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.sourceText) {
      _controller.text = widget.sourceText;
    }
  }

  @override
  void dispose() {
    _handleCommit();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _handleCommit();
      if (mounted) setState(() => _editingSource = false);
    }
  }

  void _startSourceEdit() {
    if (_editingSource) return;
    setState(() {
      _editingSource = true;
      _controller.text = widget.sourceText;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _handleCommit() {
    if (_controller.text == widget.sourceText) return;
    widget.onSourceCommit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.block.type == SourceBlockType.spacer) {
      return const SizedBox(height: 8);
    }

    if (_editingSource || widget.block.isFallback) {
      return _buildSourceBlock(context, alwaysShowLabel: widget.block.isFallback);
    }

    return _buildRenderedBlock(context);
  }

  Widget _buildRenderedBlock(BuildContext context) {
    final theme = Theme.of(context);
    final block = widget.block;
    final style = _styleForBlock(theme, block);
    final text = block.text.trimRight();

    final content = switch (block.type) {
      SourceBlockType.heading => Padding(
          padding: EdgeInsets.only(top: block.level == 1 ? 20 : 12, bottom: 8),
          child: Text(text, style: style),
        ),
      SourceBlockType.comment => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(text, style: style),
        ),
      SourceBlockType.listItem => Padding(
          padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Icon(
                  Icons.circle,
                  size: 5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: style)),
            ],
          ),
        ),
      SourceBlockType.math => Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, textAlign: TextAlign.center, style: style),
        ),
      SourceBlockType.custom => _buildCustomBlock(context, block, text, style),
      _ => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(text, style: style),
        ),
    };

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _startSourceEdit,
        child: content,
      ),
    );
  }

  Widget _buildCustomBlock(
    BuildContext context,
    SourceDocumentBlock block,
    String text,
    TextStyle? style,
  ) {
    final align = block.metadata['align'];
    if (align == 'center') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text, textAlign: TextAlign.center, style: style),
      );
    }

    if (block.metadata['displayMode'] == 'structured') {
      return _buildStructuredMacroBlock(context, block, style);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(text, style: style),
    );
  }

  Widget _buildStructuredMacroBlock(
    BuildContext context,
    SourceDocumentBlock block,
    TextStyle? style,
  ) {
    final theme = Theme.of(context);
    final title = (block.metadata['title'] as String?)?.trim() ?? '';
    final subtitle = (block.metadata['subtitle'] as String?)?.trim();
    final meta = (block.metadata['meta'] as String?)?.trim();
    final body = (block.metadata['body'] as String?)?.trim();
    final kind = block.metadata['kind'] as String?;
    final compact = block.metadata['compact'] == true;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(body ?? subtitle ?? meta ?? block.text, style: style)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? block.text.split('\n').first : title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (meta != null && meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (body != null && body.isNotEmpty) ...[
            SizedBox(height: kind == 'cv-experience' ? 10 : 8),
            Text(body, style: style),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceBlock(BuildContext context, {required bool alwaysShowLabel}) {
    final theme = Theme.of(context);
    final block = widget.block;
    final sourceLabel = block.isFallback
        ? 'Source block · ${block.metadata['reason'] ?? 'unsupported'}'
        : 'Editing source';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: block.isFallback
            ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.42)
            : theme.colorScheme.primaryContainer.withOpacity(0.18),
        border: Border.all(
          color: block.isFallback
              ? theme.colorScheme.outlineVariant
              : theme.colorScheme.primary.withOpacity(0.35),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (alwaysShowLabel || _editingSource) ...[
              Row(
                children: [
                  Icon(
                    block.isFallback ? Icons.code : Icons.edit,
                    size: 15,
                    color: block.isFallback
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sourceLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: block.isFallback
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.42),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: 'Edit source...',
              ),
              onSubmitted: (_) => _handleCommit(),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _styleForBlock(ThemeData theme, SourceDocumentBlock block) {
    final level = block.level ?? 1;
    return switch (block.type) {
      SourceBlockType.heading => switch (level) {
          1 => theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          2 => theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.14,
            ),
          _ => theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
        },
      SourceBlockType.comment => theme.textTheme.bodyMedium?.copyWith(
          color: Colors.green.shade700,
          fontFamily: 'monospace',
        ),
      SourceBlockType.math => theme.textTheme.bodyLarge?.copyWith(
          fontFamily: 'monospace',
          height: 1.45,
        ),
      SourceBlockType.sourceFallback => theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          height: 1.35,
        ),
      SourceBlockType.custom => theme.textTheme.bodyLarge?.copyWith(height: 1.45),
      _ => theme.textTheme.bodyLarge?.copyWith(height: 1.58),
    };
  }
}

class _ParserNotes extends StatelessWidget {
  const _ParserNotes({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parser notes',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final error in errors)
            Text(error, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class SourceEditorToolbar extends StatelessWidget {
  const SourceEditorToolbar({
    super.key,
    required this.configuration,
    required this.onChanged,
  });

  final SourceEditorConfiguration configuration;
  final ValueChanged<SourceEditorConfiguration> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<SourceEditorSurfaceMode>(
          segments: const [
            ButtonSegment(
              value: SourceEditorSurfaceMode.visual,
              icon: Icon(Icons.auto_awesome),
              label: Text('Visual'),
            ),
            ButtonSegment(
              value: SourceEditorSurfaceMode.source,
              icon: Icon(Icons.code),
              label: Text('Source'),
            ),
          ],
          selected: {configuration.surfaceMode},
          onSelectionChanged: (value) {
            onChanged(configuration.copyWith(surfaceMode: value.single));
          },
        ),
        SegmentedButton<SourceEditorOutputMode>(
          segments: const [
            ButtonSegment(
              value: SourceEditorOutputMode.hidden,
              icon: Icon(Icons.edit_document),
              label: Text('Editor'),
            ),
            ButtonSegment(
              value: SourceEditorOutputMode.sideBySide,
              icon: Icon(Icons.splitscreen),
              label: Text('Editor + output'),
            ),
            ButtonSegment(
              value: SourceEditorOutputMode.outputOnly,
              icon: Icon(Icons.picture_as_pdf),
              label: Text('Output'),
            ),
          ],
          selected: {configuration.outputMode},
          onSelectionChanged: (value) {
            onChanged(configuration.copyWith(outputMode: value.single));
          },
        ),
      ],
    );
  }
}
