# Text System Phase 9B — Styled Fluent Editing

Phase 9B keeps the new fluent editor path on one continuous Flutter text editing surface, then improves how that one buffer is painted.

## Added

- `FluentDocumentTextStyler`
  - centralizes rich span rendering for the fluent editor buffer
  - styles headings, list markers, todo markers, quotes, code, and inline marks
  - preserves native composing underline behavior for IME/text input stability

- `FluentBufferSegment.prefixLength`
  - exposes the editable-buffer prefix span for visible markers such as `• `, `1. `, and `☐ `

- `FluentDocumentEditingController` now delegates `buildTextSpan` to the styler.

- The fluent document lab now exercises styled content:
  - heading
  - bold
  - italic
  - underline
  - highlight
  - link placeholder
  - bullet list
  - ordered list
  - todo
  - quote
  - code

## Scope boundary

Phase 9B does not add formatting commands yet. It only improves rendering of styles already present in the structured document model. Formatting over fluent selection comes next.

## Manual checks

Open:

`Home -> textsys test env -> Fluent document surface lab`

Then test:

1. Confirm the editor is still one continuous selectable text surface.
2. Select from a paragraph into a list/quote/code line.
3. Confirm the selection crosses styled regions normally.
4. Confirm inline marks render inside the fluent editor.
5. Edit text and confirm the structured preview still updates.
6. Confirm style painting does not make the editor feel like separate rows.
