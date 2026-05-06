# Text System Phase 9D — Fluent Copy/Paste

Phase 9D wires copy, cut, and paste into the new continuous `FluentDocumentSurface`.

## Goal

Keep the user-facing model fluent: select text across paragraphs/list rows and use ordinary copy/cut/paste actions. The engine preserves structure internally while also updating the OS clipboard with plain visible text.

## Added

- Fluent surface copy/cut/paste toolbar actions.
- Fluent surface keyboard shortcuts:
  - Ctrl/Cmd+C
  - Ctrl/Cmd+X
  - Ctrl/Cmd+V
- Structured internal copy:
  - stores a `TextSystemDocumentFragment`
  - also updates the existing flat rich clipboard fallback
  - writes selected visible text to the OS clipboard
- Structured internal paste:
  - inserts the internal document fragment through fluent document coordinates
  - preserves text-unit shape and inline marks inside the app
- Plain-text fallback paste:
  - reads OS clipboard text
  - creates a paragraph-based document fragment
  - inserts it through the same structured paste path
- `TextSystemDocumentFragment.fromPlainText(...)` helper.

## Scope boundary

This does not yet implement final natural Enter/Backspace semantics for the fluent surface. That belongs in Phase 9E.

## Manual checks

Open:

`Home -> textsys test env -> Fluent document surface lab`

Then test:

1. Select text across paragraphs/list rows.
2. Press Ctrl/Cmd+C or use the copy toolbar button.
3. Move the cursor elsewhere and press Ctrl/Cmd+V.
4. Confirm structure/marks survive in the read-only preview.
5. Copy external plain text and paste it into the fluent surface.
6. Confirm plain text fallback inserts paragraphs.
7. Try Ctrl/Cmd+X and undo.
