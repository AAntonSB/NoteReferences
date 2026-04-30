import 'package:flutter/material.dart';

class LinkedSelectionPreview extends StatelessWidget {
  final String selectedText;
  final bool compact;
  final VoidCallback? onTap;

  const LinkedSelectionPreview({
    super.key,
    required this.selectedText,
    required this.compact,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final child = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(
          alpha: compact ? 0.22 : 0.38,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote,
            size: compact ? 13 : 15,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              selectedText,
              maxLines: compact ? 2 : 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.open_in_new,
              size: compact ? 12 : 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}
