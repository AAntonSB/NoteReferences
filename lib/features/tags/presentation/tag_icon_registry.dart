import 'package:flutter/material.dart';

class TagIconOption {
  final String key;
  final String label;
  final IconData icon;

  const TagIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });
}

const List<TagIconOption> tagIconOptions = [
  TagIconOption(key: 'tag', label: 'Tag', icon: Icons.sell_outlined),
  TagIconOption(key: 'book', label: 'Book', icon: Icons.menu_book_outlined),
  TagIconOption(
    key: 'theory',
    label: 'Theory',
    icon: Icons.psychology_alt_outlined,
  ),
  TagIconOption(key: 'method', label: 'Method', icon: Icons.science_outlined),
  TagIconOption(key: 'data', label: 'Data', icon: Icons.bar_chart_outlined),
  TagIconOption(key: 'question', label: 'Question', icon: Icons.help_outline),
  TagIconOption(
    key: 'important',
    label: 'Important',
    icon: Icons.priority_high,
  ),
  TagIconOption(key: 'idea', label: 'Idea', icon: Icons.lightbulb_outline),
  TagIconOption(
    key: 'review',
    label: 'Review',
    icon: Icons.rate_review_outlined,
  ),
  TagIconOption(key: 'todo', label: 'TODO', icon: Icons.task_alt),
  TagIconOption(
    key: 'quote',
    label: 'Quote',
    icon: Icons.format_quote_outlined,
  ),
  TagIconOption(key: 'archive', label: 'Archive', icon: Icons.archive_outlined),
];

const List<int> tagColorOptions = [
  0xFF64748B,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFDB2777,
  0xFFDC2626,
  0xFFEA580C,
  0xFFD97706,
  0xFF16A34A,
  0xFF059669,
  0xFF0891B2,
  0xFF4F46E5,
  0xFF525252,
];

IconData iconForTagKey(String iconKey) {
  for (final option in tagIconOptions) {
    if (option.key == iconKey) return option.icon;
  }

  return Icons.sell_outlined;
}

String labelForTagIconKey(String iconKey) {
  for (final option in tagIconOptions) {
    if (option.key == iconKey) return option.label;
  }

  return 'Tag';
}
