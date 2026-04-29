import 'package:flutter/material.dart';

import '../note_creation_type.dart';
import '../note_type_presentation.dart';

class CreateNoteMenuItem extends StatelessWidget {
  final NoteCreationType type;

  const CreateNoteMenuItem({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = NoteTypePresentation.fromType(type.id, theme);

    return Row(
      children: [
        Icon(
          type.icon,
          size: 20,
          color: presentation.accentColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type.label),
              const SizedBox(height: 2),
              Text(
                type.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}