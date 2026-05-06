# Text System Phase 8C — Fluent Document Selection Foundation

Phase 8C adds the internal vocabulary needed for future fluent document selection.

The product principle is unchanged:

> The user edits fluent text. The system may understand structure underneath, but that structure must not constrain ordinary selection, copy, paste, formatting, or writing.

## Added

- `TextSystemDocumentPosition`
  - internal cursor position mapped to a text unit and offset

- `TextSystemDocumentRange`
  - internal half-open range spanning document positions

- `TextSystemDocumentOffsetRange`
  - flattened absolute offset range for document-level reasoning

- `TextSystemDocumentFragment`
  - structured internal copy payload that preserves paragraph/list/heading shape and marks
  - can also flatten to the existing `TextClipboardFragment` fallback

- `TextSystemDocumentSelectionMapper`
  - maps flattened document offsets to internal positions
  - maps internal positions back to flattened offsets
  - extracts plain text for a document-level range
  - extracts structured fragments across paragraphs, headings, and list items

- `TextSystemController.copyDocumentFragment(...)`
  - stores a structured document fragment internally
  - also stores a flattened rich clipboard fallback

- `TextSystemDocumentSelectionLabScreen`
  - available from `textsys test env`
  - demonstrates range mapping across internal text units without changing the user-facing editing surface yet

## Scope boundary

This phase does not replace the current document surface with a single continuous editor yet.
It also does not implement cross-paragraph selection in Flutter text fields.

Instead, it creates the model layer that makes those future features possible without making the current UI more block-oriented.

## Manual checks

Open:

`Home -> textsys test env -> Fluent document selection lab`

Then test:

1. Move the document range slider.
2. Confirm the selected text updates as one fluent text range.
3. Confirm ranges can cross headings, paragraphs, and list items.
4. Confirm the structured fragment JSON preserves text unit types and marks.
5. Click "Copy range" and confirm the internal structured clipboard updates.
