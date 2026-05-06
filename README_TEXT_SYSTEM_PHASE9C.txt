# Text System Phase 9C — Formatting over fluent selection

Phase 9C wires inline formatting commands into the new continuous fluent document surface.

## Added

- Document-range mark operations that can span multiple internal text units.
- `TextSystemController.toggleMarkForDocumentRange(...)`.
- Fluent buffer selection -> structured document range mapping.
- Fluent selection toolbar for:
  - bold
  - italic
  - underline
  - highlight
  - inline code
  - link marker placeholder
  - undo
  - redo
- Keyboard shortcuts inside the fluent surface:
  - Ctrl/Cmd+B
  - Ctrl/Cmd+I
  - Ctrl/Cmd+U
  - Ctrl/Cmd+Shift+H
  - Ctrl/Cmd+K
  - Ctrl/Cmd+Z
  - Ctrl/Cmd+Shift+Z

## Product boundary

This keeps the text-first UX direction. The user selects fluent text in one continuous editor. The engine maps that visible selection back into structured paragraphs/lists/headings underneath.

This phase does not implement structured copy/paste in the fluent surface yet; that belongs to Phase 9D.
