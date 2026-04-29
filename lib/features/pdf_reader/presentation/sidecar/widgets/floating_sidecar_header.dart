import 'package:flutter/material.dart';

class FloatingSidecarHeader extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final bool hasSelectedText;
  final String syncMode;
  final bool debugEnabled;
  final bool outlineOpen;
  final VoidCallback onToggleDebug;
  final VoidCallback onToggleOutline;

  const FloatingSidecarHeader({
    super.key,
    required this.currentPage,
    required this.pageCount,
    required this.hasSelectedText,
    required this.syncMode,
    required this.debugEnabled,
    required this.outlineOpen,
    required this.onToggleDebug,
    required this.onToggleOutline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topRight,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surface.withOpacity(0.92),
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 6, right: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: outlineOpen ? 'Hide notes outline' : 'Show notes outline',
                onPressed: onToggleOutline,
                icon: Icon(
                  outlineOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                  size: 18,
                ),
              ),
              if (hasSelectedText) ...[
                Icon(
                  Icons.format_quote,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
              ],
              if (debugEnabled) ...[
                Text(
                  '$syncMode · Page $currentPage / $pageCount',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: debugEnabled ? 'Disable debug view' : 'Enable debug view',
                onPressed: onToggleDebug,
                icon: Icon(
                  debugEnabled ? Icons.bug_report : Icons.bug_report_outlined,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}