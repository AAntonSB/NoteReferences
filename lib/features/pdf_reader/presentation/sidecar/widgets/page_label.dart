import 'package:flutter/material.dart';

class PageLabel extends StatelessWidget {
  final int pageNumber;
  final bool isCurrentPage;

  const PageLabel({
    super.key,
    required this.pageNumber,
    required this.isCurrentPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentPage
            ? theme.colorScheme.primary
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        'Page $pageNumber',
        style: theme.textTheme.labelSmall?.copyWith(
          color: isCurrentPage
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}