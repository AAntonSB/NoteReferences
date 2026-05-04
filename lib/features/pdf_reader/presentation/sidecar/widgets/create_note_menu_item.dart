import 'package:flutter/material.dart';

import '../note_creation_type.dart';
import '../note_type_presentation.dart';

class CreateNoteMenuItem extends StatelessWidget {
  final NoteCreationType type;

  const CreateNoteMenuItem({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = NoteTypePresentation.fromType(type.id, theme);

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: presentation.accentColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Icon(type.icon, size: 15, color: presentation.accentColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            type.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}
