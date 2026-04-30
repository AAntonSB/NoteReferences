import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../notes/data/note_repository.dart';
import 'pdf_reader_toolbar.dart';
import 'sidecar/note_creation_type.dart';

typedef PdfSelectionCreateNoteCallback =
    void Function({
      required NoteCreationType creationType,
      required int pageNumber,
      required double normalizedY,
    });

typedef PdfSelectionHighlightCallback =
    void Function({required int pageNumber});

typedef PdfSelectionDocumentReferenceCallback =
    void Function({required int pageNumber});

typedef PdfSelectionTodoCallback = void Function({required int pageNumber});

class PdfSelectionActionOverlay extends StatelessWidget {
  final String? selectedText;
  final List<PdfSourceRect> selectedSourceRects;
  final Rect pageRectInViewer;
  final pdfrx.PdfPage page;
  final PdfReaderTool activeTool;
  final int activeHighlightColorValue;
  final PdfSelectionCreateNoteCallback onCreateNote;
  final PdfSelectionHighlightCallback onCreateHighlight;
  final PdfSelectionDocumentReferenceCallback onAddToDocumentNote;
  final PdfSelectionTodoCallback onCreateTodo;

  const PdfSelectionActionOverlay({
    super.key,
    required this.selectedText,
    required this.selectedSourceRects,
    required this.pageRectInViewer,
    required this.page,
    required this.activeTool,
    required this.activeHighlightColorValue,
    required this.onCreateNote,
    required this.onCreateHighlight,
    required this.onAddToDocumentNote,
    required this.onCreateTodo,
  });

  bool get _hasSelection {
    return selectedText != null &&
        selectedText!.trim().isNotEmpty &&
        selectedSourceRects.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSelection || activeTool == PdfReaderTool.eraser) {
      return const SizedBox.shrink();
    }

    final rectsForPage = selectedSourceRects
        .where((rect) => rect.pageNumber == page.pageNumber && rect.isValid)
        .toList();

    if (rectsForPage.isEmpty) {
      return const SizedBox.shrink();
    }

    final localRects = _toLocalRects(rectsForPage);

    if (localRects.isEmpty) {
      return const SizedBox.shrink();
    }

    localRects.sort((a, b) {
      final topCompare = a.top.compareTo(b.top);
      if (topCompare != 0) return topCompare;
      return a.left.compareTo(b.left);
    });

    final firstRect = localRects.first;

    final paletteWidth = _SelectionPalette.estimatedWidth(activeTool);
    const paletteHeight = 42.0;

    final pageWidth = math.max(1.0, pageRectInViewer.width);
    final pageHeight = math.max(1.0, pageRectInViewer.height);

    final left = firstRect.left
        .clamp(8.0, math.max(8.0, pageWidth - paletteWidth - 8.0))
        .toDouble();

    final top = (firstRect.top - paletteHeight - 8)
        .clamp(8.0, math.max(8.0, pageHeight - paletteHeight - 8.0))
        .toDouble();

    final normalizedY = (firstRect.center.dy / pageHeight)
        .clamp(0.02, 0.94)
        .toDouble();

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: _SelectionPalette(
              activeTool: activeTool,
              activeHighlightColorValue: activeHighlightColorValue,
              onHighlight: () {
                onCreateHighlight(pageNumber: page.pageNumber);
              },
              onAddToDocumentNote: () {
                onAddToDocumentNote(pageNumber: page.pageNumber);
              },
              onCreateTodo: () {
                onCreateTodo(pageNumber: page.pageNumber);
              },
              onCreateNote: (type) {
                onCreateNote(
                  creationType: type,
                  pageNumber: page.pageNumber,
                  normalizedY: normalizedY,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Rect> _toLocalRects(List<PdfSourceRect> sourceRects) {
    final output = <Rect>[];

    for (final sourceRect in sourceRects) {
      final pdfRect = pdfrx.PdfRect(
        sourceRect.left,
        sourceRect.top,
        sourceRect.right,
        sourceRect.bottom,
      );

      final rectInViewer = pdfRect.toRectInDocument(
        page: page,
        pageRect: pageRectInViewer,
      );

      final localRect = rectInViewer.shift(
        Offset(-pageRectInViewer.left, -pageRectInViewer.top),
      );

      final normalized = Rect.fromLTRB(
        math.min(localRect.left, localRect.right),
        math.min(localRect.top, localRect.bottom),
        math.max(localRect.left, localRect.right),
        math.max(localRect.top, localRect.bottom),
      );

      if (normalized.width <= 0 || normalized.height <= 0) {
        continue;
      }

      output.add(normalized);
    }

    return output;
  }
}

class _SelectionPalette extends StatelessWidget {
  final PdfReaderTool activeTool;
  final int activeHighlightColorValue;
  final VoidCallback onHighlight;
  final VoidCallback onAddToDocumentNote;
  final VoidCallback onCreateTodo;
  final ValueChanged<NoteCreationType> onCreateNote;

  const _SelectionPalette({
    required this.activeTool,
    required this.activeHighlightColorValue,
    required this.onHighlight,
    required this.onAddToDocumentNote,
    required this.onCreateTodo,
    required this.onCreateNote,
  });

  static double estimatedWidth(PdfReaderTool activeTool) {
    switch (activeTool) {
      case PdfReaderTool.highlight:
        return 158;
      case PdfReaderTool.note:
      case PdfReaderTool.citation:
        return 150;
      case PdfReaderTool.cursor:
        return 418;
      case PdfReaderTool.eraser:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(999),
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: _buildButtons()),
      ),
    );
  }

  List<Widget> _buildButtons() {
    switch (activeTool) {
      case PdfReaderTool.highlight:
        return [
          _PaletteButton(
            tooltip: 'Highlight selection',
            icon: Icons.highlight,
            label: 'Highlight',
            colorValue: activeHighlightColorValue,
            onPressed: onHighlight,
          ),
        ];
      case PdfReaderTool.note:
        return [
          _PaletteButton(
            tooltip: 'Create note from selection',
            icon: Icons.notes,
            label: 'Note',
            onPressed: () => onCreateNote(NoteCreationType.note),
          ),
        ];
      case PdfReaderTool.citation:
        return [
          _PaletteButton(
            tooltip: 'Create citation from selection',
            icon: Icons.format_quote,
            label: 'Citation',
            onPressed: () => onCreateNote(NoteCreationType.citation),
          ),
        ];
      case PdfReaderTool.cursor:
        return [
          _PaletteButton(
            tooltip: 'Highlight selection',
            icon: Icons.highlight,
            colorValue: activeHighlightColorValue,
            onPressed: onHighlight,
          ),
          _PaletteButton(
            tooltip: 'Add selection to document note',
            icon: Icons.article_outlined,
            onPressed: onAddToDocumentNote,
          ),
          _PaletteButton(
            tooltip: 'Create TODO from selection',
            icon: Icons.task_alt,
            onPressed: onCreateTodo,
          ),
          _PaletteButton(
            tooltip: 'Create note',
            icon: Icons.notes,
            onPressed: () => onCreateNote(NoteCreationType.note),
          ),
          _PaletteButton(
            tooltip: 'Create question',
            icon: Icons.help_outline,
            onPressed: () => onCreateNote(NoteCreationType.question),
          ),
          _PaletteButton(
            tooltip: 'Create citation',
            icon: Icons.format_quote,
            onPressed: () => onCreateNote(NoteCreationType.citation),
          ),
          _PaletteButton(
            tooltip: 'Create summary',
            icon: Icons.subject,
            onPressed: () => onCreateNote(NoteCreationType.summary),
          ),
          _PaletteButton(
            tooltip: 'Create definition',
            icon: Icons.bookmark_border,
            onPressed: () => onCreateNote(NoteCreationType.definition),
          ),
        ];
      case PdfReaderTool.eraser:
        return const [];
    }
  }
}

class _PaletteButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final String? label;
  final int? colorValue;
  final VoidCallback onPressed;

  const _PaletteButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
    this.colorValue,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorValue == null ? null : Color(colorValue!);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: label == null
              ? const EdgeInsets.symmetric(horizontal: 8)
              : const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(34, 34),
        ),
        onPressed: onPressed,
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            if (color != null) ...[
              const SizedBox(width: 4),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ],
        ),
        label: label == null ? const SizedBox.shrink() : Text(label!),
      ),
    );
  }
}
