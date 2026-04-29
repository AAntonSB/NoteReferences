import 'package:flutter/material.dart';

enum NoteCreationType {
  note(
    id: 'note',
    label: 'Text note',
    description: 'Quick thought',
    icon: Icons.notes,
  ),
  question(
    id: 'question',
    label: 'Question',
    description: 'Something to resolve later',
    icon: Icons.help_outline,
  ),
  summary(
    id: 'summary',
    label: 'Summary',
    description: 'Condense a page or section',
    icon: Icons.subject,
  ),
  definition(
    id: 'definition',
    label: 'Definition',
    description: 'Term, mechanism, or concept',
    icon: Icons.bookmark_border,
  ),
  task(
    id: 'task',
    label: 'Task',
    description: 'Follow-up action',
    icon: Icons.check_box_outlined,
  ),
  citation(
    id: 'citation',
    label: 'Citation note',
    description: 'Save evidence or quote',
    icon: Icons.format_quote,
  ),
  highlight(
    id: 'highlight',
    label: 'Highlight only',
    description: 'Mark selected source text',
    icon: Icons.highlight,
  );

  final String id;
  final String label;
  final String description;
  final IconData icon;

  const NoteCreationType({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });
}