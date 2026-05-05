# Text System Phase 7B — Inline + Read-only Surfaces

Phase 7B turns the Phase 7A shared surface infrastructure into the first two concrete lightweight surfaces.

## Added

- `InlineTextSurface`
  - compact rich-text editing surface for todos, captions, short comments, side labels, and small fields
  - uses `TextSystemSurfaceController`
  - uses `TextSystemEditableSurfaceFrame`
  - supports optional compact toolbar and status bar
  - keeps command, shortcut, undo/redo, rich clipboard, and autosave behavior shared

- `ReadOnlyTextSurface`
  - non-mutating structured text renderer
  - suitable for previews, search snippets, revision display, collapsed notes, and read-only views
  - listens to the same `TextSystemController` without exposing editing controls

- `TextSystemRichTextRenderer`
  - shared renderer for text-system blocks and marks
  - renders bold, italic, underline, strikethrough, highlight, code, and link marks
  - renders paragraph, heading, list item, todo, quote, divider, and fallback blocks

- `TextSystemBasicSurfacesLabScreen`
  - available from `textsys test env`
  - validates edit -> read-only render
  - validates shared rich clipboard state and autosave/transaction visibility

## Scope boundary

This phase does not add the simple note surface, document surface, shortcut settings UI, internal backlink system, or premium writer shell. Those remain future Phase 7 substeps.

## Manual checks

Open:

`Home -> textsys test env -> Basic text surfaces lab`

Then test:

1. Edit the source inline field.
2. Select text and apply bold / italic / highlight.
3. Copy rich text from the source field.
4. Paste into the target field.
5. Confirm the read-only preview updates.
6. Confirm revision, transaction, autosave, and internal clipboard state update.
7. Confirm the read-only preview does not mutate the document.
