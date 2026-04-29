import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../../notes/data/note_repository.dart';
import 'sidecar/note_creation_type.dart';

typedef PdfSelectionCreateNoteCallback = void Function({
  required NoteCreationType creationType,
  required int pageNumber,
  required double normalizedY,
});

typedef PdfSelectionHighlightCallback = void Function({
  required int pageNumber,
});

class PdfSelectionActionOverlay extends StatelessWidget {
  final String? selectedText;
  final List<PdfSourceRect> selectedSourceRects;
  final Rect pageRectInViewer;
  final pdfrx.PdfPage page;
  final PdfSelectionCreateNoteCallback onCreateNote;
  final PdfSelectionHighlightCallback onCreateHighlight;

  const PdfSelectionActionOverlay({
    super.key,
    required this.selectedText,
    required this.selectedSourceRects,
    required this.pageRectInViewer,
    required this.page,
    required this.onCreateNote,
    required this.onCreateHighlight,
  });

  bool get _hasSelection {
    return selectedText != null &&
        selectedText!.trim().isNotEmpty &&
        selectedSourceRects.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSelection) {
      return const SizedBox.shrink();
    }

    final rectsForPage = selectedSourceRects
        .where(
          (rect) => rect.pageNumber == page.pageNumber && rect.isValid,
        )
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

    const paletteWidth = 318.0;
    const paletteHeight = 42.0;

    final pageWidth = math.max(1.0, pageRectInViewer.width);
    final pageHeight = math.max(1.0, pageRectInViewer.height);

    final left = firstRect.left
        .clamp(
          8.0,
          math.max(8.0, pageWidth - paletteWidth - 8.0),
        )
        .toDouble();

    final top = (firstRect.top - paletteHeight - 8)
        .clamp(
          8.0,
          math.max(8.0, pageHeight - paletteHeight - 8.0),
        )
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
              onHighlight: () {
                onCreateHighlight(pageNumber: page.pageNumber);
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
        Offset(
          -pageRectInViewer.left,
          -pageRectInViewer.top,
        ),
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
  final VoidCallback onHighlight;
  final ValueChanged<NoteCreationType> onCreateNote;

  const _SelectionPalette({
    required this.onHighlight,
    required this.onCreateNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(999),
      color: theme.colorScheme.surface.withOpacity(0.96),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PaletteButton(
              tooltip: 'Highlight selection',
              icon: Icons.highlight,
              onPressed: onHighlight,
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
          ],
        ),
      ),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _PaletteButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}