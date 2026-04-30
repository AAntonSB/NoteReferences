import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

class PdfSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final pdfrx.PdfTextSearcher textSearcher;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  const PdfSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.textSearcher,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  KeyEventResult _handleKeyEvent(
    BuildContext context,
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        onPrevious();
      } else {
        onNext();
      }

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      child: Container(
        width: 460,
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: ListenableBuilder(
          listenable: textSearcher,
          builder: (context, _) {
            final matchCount = textSearcher.matches.length;
            final currentIndex = textSearcher.currentIndex;

            final matchText = controller.text.trim().isEmpty
                ? ''
                : textSearcher.isSearching
                ? 'Searching…'
                : matchCount == 0
                ? 'No matches'
                : '${(currentIndex ?? 0) + 1} / $matchCount';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 19,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Focus(
                        onKeyEvent: (node, event) {
                          return _handleKeyEvent(context, node, event);
                        },
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: onQueryChanged,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Search PDF',
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (matchText.isNotEmpty)
                      Text(
                        matchText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Previous match',
                      onPressed: matchCount == 0 ? null : onPrevious,
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Next match',
                      onPressed: matchCount == 0 ? null : onNext,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Close PDF search',
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
                if (textSearcher.isSearching)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: LinearProgressIndicator(
                      value: textSearcher.searchProgress,
                      minHeight: 2,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
