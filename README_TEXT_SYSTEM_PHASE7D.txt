# Text System Phase 7D — DocumentTextSurface

Phase 7D adds the first regular document-shaped surface on top of the shared text-system engine.

## Added

- `DocumentTextSurface`
  - document-style title editing
  - multiple text-system blocks
  - per-block rich text editing through the shared Phase 7A surface infrastructure
  - document spacing and document-shaped chrome
  - block conversion controls for paragraph, H1/H2/H3, bullet list item, numbered list item, quote, and todo
  - block add/remove/move controls
  - shared command toolbar, keyboard dispatch, undo/redo, rich clipboard, and autosave handoff

- `TextSystemDocumentSurfaceLabScreen`
  - available from `textsys test env`
  - validates title editing, multi-block editing, block type conversion, headings/lists, rich marks, internal rich copy/paste, autosave, transactions, and read-only preview

## Scope boundary

This is still the light text-system layer. It does not add the premium writer shell, outline panel, source/LaTeX mode, export/preview pipeline, shortcut settings UI, advanced nested lists, tables, images, comments, or revision history UI.

## Manual checks

Open:

`Home -> textsys test env -> Document text surface lab`

Then test:

1. Edit the document title.
2. Edit multiple blocks.
3. Convert blocks between paragraph, H1/H2/H3, bullet list, numbered list, quote, and todo.
4. Add, remove, and move blocks.
5. Select text and apply bold / italic / highlight.
6. Copy rich text from one block and paste it into another block.
7. Confirm the read-only preview updates.
8. Confirm autosave, revision, transaction, block type, and clipboard state update.
