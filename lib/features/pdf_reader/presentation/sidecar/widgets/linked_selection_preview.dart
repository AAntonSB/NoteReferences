import 'package:flutter/material.dart';

class LinkedSelectionPreview extends StatelessWidget {
  final String selectedText;
  final bool compact;
  final int? pageNumber;
  final bool sourceIsCurrentPage;
  final VoidCallback? onTap;

  const LinkedSelectionPreview({
    super.key,
    required this.selectedText,
    required this.compact,
    this.pageNumber,
    this.sourceIsCurrentPage = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pageLabel = pageNumber == null ? 'Linked source' : 'p. $pageNumber';
    final canJump = onTap != null && !sourceIsCurrentPage;

    if (compact) {
      final marker = Container(
        margin: const EdgeInsets.only(top: 3, bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.34,
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.34),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              canJump ? Icons.open_in_new : Icons.link,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.76),
            ),
            const SizedBox(width: 4),
            Text(
              canJump ? '$pageLabel · source' : pageLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

      if (onTap == null) return marker;

      return Tooltip(
        message: canJump ? 'Jump to source' : 'Source is on this page',
        child: MouseRegion(
          cursor: canJump ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canJump ? onTap : null,
            child: marker,
          ),
        ),
      );
    }

    final child = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.48,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              pageLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              selectedText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          ),
          if (canJump) ...[
            const SizedBox(width: 4),
            Icon(Icons.open_in_new, size: 14, color: theme.colorScheme.primary),
          ],
        ],
      ),
    );

    if (onTap == null || !canJump) return child;

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
