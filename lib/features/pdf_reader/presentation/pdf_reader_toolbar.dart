import 'package:flutter/material.dart';

const int kDefaultPdfHighlightColorValue = 0xFFFFD54F;
const double kDefaultPdfHighlightOpacity = 0.22;

class PdfHighlightColorOption {
  final String label;
  final int colorValue;

  const PdfHighlightColorOption({
    required this.label,
    required this.colorValue,
  });

  Color get color => Color(colorValue);
}

const List<PdfHighlightColorOption> pdfHighlightColorOptions = [
  PdfHighlightColorOption(label: 'Yellow', colorValue: 0xFFFFD54F),
  PdfHighlightColorOption(label: 'Green', colorValue: 0xFF81C784),
  PdfHighlightColorOption(label: 'Blue', colorValue: 0xFF64B5F6),
  PdfHighlightColorOption(label: 'Pink', colorValue: 0xFFF48FB1),
  PdfHighlightColorOption(label: 'Purple', colorValue: 0xFFBA68C8),
];

enum PdfReaderTool { cursor, highlight, note, citation, eraser }

extension PdfReaderToolPresentation on PdfReaderTool {
  String get label {
    switch (this) {
      case PdfReaderTool.cursor:
        return 'Cursor';
      case PdfReaderTool.highlight:
        return 'Highlight';
      case PdfReaderTool.note:
        return 'Note';
      case PdfReaderTool.citation:
        return 'Citation';
      case PdfReaderTool.eraser:
        return 'Eraser';
    }
  }

  String get tooltip {
    switch (this) {
      case PdfReaderTool.cursor:
        return 'Cursor mode: select text, tap highlights, and reveal notes';
      case PdfReaderTool.highlight:
        return 'Highlight mode: create regular PDF highlights';
      case PdfReaderTool.note:
        return 'Note mode: create sidecar notes from selected text';
      case PdfReaderTool.citation:
        return 'Citation mode: create citation notes from selected text';
      case PdfReaderTool.eraser:
        return 'Eraser mode: tap highlights to remove them';
    }
  }

  IconData get icon {
    switch (this) {
      case PdfReaderTool.cursor:
        return Icons.mouse_outlined;
      case PdfReaderTool.highlight:
        return Icons.highlight;
      case PdfReaderTool.note:
        return Icons.sticky_note_2_outlined;
      case PdfReaderTool.citation:
        return Icons.format_quote;
      case PdfReaderTool.eraser:
        return Icons.auto_fix_off_outlined;
    }
  }
}

class PdfReaderToolbar extends StatelessWidget {
  final PdfReaderTool activeTool;
  final int activeHighlightColorValue;
  final bool hasActiveSelection;
  final ValueChanged<PdfReaderTool> onToolChanged;
  final ValueChanged<int> onHighlightColorChanged;
  final VoidCallback onOpenPdfSearch;
  final VoidCallback onOpenNotesOutlineSearch;
  final ValueChanged<BuildContext> onOpenTodos;
  final int activeTodoCount;

  const PdfReaderToolbar({
    super.key,
    required this.activeTool,
    required this.activeHighlightColorValue,
    required this.hasActiveSelection,
    required this.onToolChanged,
    required this.onHighlightColorChanged,
    required this.onOpenPdfSearch,
    required this.onOpenNotesOutlineSearch,
    required this.onOpenTodos,
    this.activeTodoCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.72,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolButton(
                    tool: PdfReaderTool.cursor,
                    activeTool: activeTool,
                    onToolChanged: onToolChanged,
                  ),
                  _HighlightToolButton(
                    activeTool: activeTool,
                    activeColorValue: activeHighlightColorValue,
                    onToolChanged: onToolChanged,
                    onColorChanged: onHighlightColorChanged,
                  ),
                  _ToolButton(
                    tool: PdfReaderTool.note,
                    activeTool: activeTool,
                    onToolChanged: onToolChanged,
                  ),
                  _ToolButton(
                    tool: PdfReaderTool.citation,
                    activeTool: activeTool,
                    onToolChanged: onToolChanged,
                  ),
                  _ToolButton(
                    tool: PdfReaderTool.eraser,
                    activeTool: activeTool,
                    onToolChanged: onToolChanged,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (hasActiveSelection)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Text selection is active',
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.format_quote, size: 15),
                  label: const Text('Selection'),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
            ),
          _HeaderIconButton(
            tooltip: 'Search PDF (Ctrl+F)',
            icon: Icons.search,
            onPressed: onOpenPdfSearch,
          ),
          _HeaderIconButton(
            tooltip: 'Search notes outline (Ctrl+Shift+F)',
            icon: Icons.manage_search_outlined,
            onPressed: onOpenNotesOutlineSearch,
          ),
          _HeaderTodoButton(
            activeTodoCount: activeTodoCount,
            onPressed: onOpenTodos,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final PdfReaderTool tool;
  final PdfReaderTool activeTool;
  final ValueChanged<PdfReaderTool> onToolChanged;

  const _ToolButton({
    required this.tool,
    required this.activeTool,
    required this.onToolChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = tool == activeTool;

    return _ToolbarButtonShell(
      isActive: isActive,
      tooltip: tool.tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: tool.tooltip,
        onPressed: () => onToolChanged(tool),
        icon: Icon(tool.icon, size: 18),
      ),
    );
  }
}

class _HighlightToolButton extends StatelessWidget {
  final PdfReaderTool activeTool;
  final int activeColorValue;
  final ValueChanged<PdfReaderTool> onToolChanged;
  final ValueChanged<int> onColorChanged;

  const _HighlightToolButton({
    required this.activeTool,
    required this.activeColorValue,
    required this.onToolChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = activeTool == PdfReaderTool.highlight;

    return _ToolbarButtonShell(
      isActive: isActive,
      tooltip: PdfReaderTool.highlight.tooltip,
      child: PopupMenuButton<int>(
        tooltip: PdfReaderTool.highlight.tooltip,
        initialValue: activeColorValue,
        onOpened: () => onToolChanged(PdfReaderTool.highlight),
        onSelected: (value) {
          onColorChanged(value);
          onToolChanged(PdfReaderTool.highlight);
        },
        itemBuilder: (context) {
          return [
            for (final option in pdfHighlightColorOptions)
              PopupMenuItem<int>(
                value: option.colorValue,
                child: Row(
                  children: [
                    _ColorDot(color: option.color),
                    const SizedBox(width: 10),
                    Text(option.label),
                  ],
                ),
              ),
          ];
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PdfReaderTool.highlight.icon, size: 18),
              const SizedBox(width: 5),
              _ColorDot(color: Color(activeColorValue), size: 10),
              const SizedBox(width: 1),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButtonShell extends StatelessWidget {
  final bool isActive;
  final String tooltip;
  final Widget child;

  const _ToolbarButtonShell({
    required this.isActive,
    required this.tooltip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: IconTheme.merge(
          data: IconThemeData(
            color: isActive
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
    );
  }
}

class _HeaderTodoButton extends StatelessWidget {
  final int activeTodoCount;
  final ValueChanged<BuildContext> onPressed;

  const _HeaderTodoButton({
    required this.activeTodoCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _HeaderIconButton(
          tooltip: 'Active TODOs',
          icon: Icons.task_alt,
          onPressed: () => onPressed(context),
        ),
        if (activeTodoCount > 0)
          Positioned(
            right: 2,
            top: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                child: Text(
                  activeTodoCount > 99 ? '99+' : '$activeTodoCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onError,
                    fontSize: 10,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final double size;

  const _ColorDot({required this.color, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
