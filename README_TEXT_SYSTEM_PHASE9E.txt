# Text System Phase 9E — Natural editing rules for the fluent surface

Phase 9E adds natural paragraph/list editing behavior to the new continuous `FluentDocumentSurface`.

## Added

- `FluentDocumentNaturalEditingFormatter`
  - runs inside the single fluent `TextField`
  - keeps the user-facing model as one continuous text surface
  - normalizes common document-editing interactions before the buffer is mapped back to the structured model

## Supported interactions

- Press Enter at the end or middle of a bullet line to continue the bullet list.
- Press Enter at the end or middle of a numbered line to continue the numbered list.
- Press Enter at the end or middle of a todo line to continue the todo list.
- Press Enter on an empty bullet/numbered/todo line to exit back to a plain paragraph.
- Press Backspace at the start of bullet/numbered/todo content to convert the line back to plain text.
- Ordered list prefixes renumber after list continuation, exit, and paste-like edits.

## Scope boundary

This is still a first natural-editing pass. It does not add nested lists, indentation, tables, comments, LaTeX behavior, AI, or a custom render object. The important milestone is that the behavior now belongs to the continuous fluent editor instead of the old row-based document surface.

## Manual checks

Open:

`Home -> textsys test env -> Fluent document surface lab`

Then test:

1. Select across multiple paragraphs to confirm the editor is still one continuous surface.
2. Place the cursor after a bullet item and press Enter.
3. Place the cursor after a numbered item and press Enter.
4. Place the cursor on an empty bullet/numbered/todo line and press Enter to exit the list.
5. Place the cursor immediately after a bullet/numbered/todo marker and press Backspace to turn the row into plain text.
6. Confirm the structured read-only preview updates underneath.
