import 'package:flutter/material.dart';

class NoteTypePresentation {
  final String label;
  final IconData icon;
  final Color accentColor;

  const NoteTypePresentation({
    required this.label,
    required this.icon,
    required this.accentColor,
  });

  factory NoteTypePresentation.fromType(String type, ThemeData theme) {
    final scheme = theme.colorScheme;

    switch (type) {
      case 'question':
        return NoteTypePresentation(
          label: 'Question',
          icon: Icons.help_outline,
          accentColor: scheme.tertiary,
        );
      case 'summary':
        return NoteTypePresentation(
          label: 'Summary',
          icon: Icons.subject,
          accentColor: scheme.secondary,
        );
      case 'definition':
        return NoteTypePresentation(
          label: 'Definition',
          icon: Icons.bookmark_border,
          accentColor: scheme.primary,
        );
      case 'todo':
        return NoteTypePresentation(
          label: 'TODO',
          icon: Icons.check_box_outlined,
          accentColor: scheme.error,
        );
      case 'task':
        return NoteTypePresentation(
          label: 'Task',
          icon: Icons.check_box_outlined,
          accentColor: scheme.error,
        );
      case 'citation':
        return NoteTypePresentation(
          label: 'Citation',
          icon: Icons.format_quote,
          accentColor: scheme.primary,
        );
      case 'highlight':
        return NoteTypePresentation(
          label: 'Highlight',
          icon: Icons.highlight,
          accentColor: Colors.amber.shade700,
        );
      case 'note':
      default:
        return NoteTypePresentation(
          label: 'Note',
          icon: Icons.notes,
          accentColor: scheme.outline,
        );
    }
  }
}
