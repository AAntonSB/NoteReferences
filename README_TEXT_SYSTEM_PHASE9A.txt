# Text System Phase 9A — Fluent Document Surface

Phase 9A starts the new document-editor path.

The row-based `DocumentTextSurface` remains useful as a basic/transitional surface, but it cannot be the final serious document editor because each paragraph/list item is a separate text field. That fragments selection.

Phase 9A adds an experimental continuous surface:

- `FluentDocumentSurface`
- `FluentDocumentEditingController`
- `FluentDocumentBuffer`
- `FluentBufferSegment`
- `FluentDocumentBufferMapper`

## Principle

The user edits fluent text. Internal structure stays underneath.

## What this phase proves

- A whole structured document can be projected into one Flutter text editing buffer.
- Selection can cross paragraphs because the visible editor is one `TextField`/`EditableText` surface.
- Buffer offsets can be mapped back to internal text-system blocks.
- Plain edits in the continuous buffer update the structured `TextSystemDocument`.
- The read-only structured preview updates from the same document.

## Deliberate limitations

This first spike is intentionally modest.

It does not yet provide:

- production-grade rich formatting commands over fluent selection
- advanced list behavior
- structured copy/paste from the visible selection
- perfect preservation of marks after arbitrary edits
- non-editable rendered list decorations
- LaTeX integration
- premium writer shell
- AI

The goal is to prove the core surface architecture before layering those systems on top.

## Manual check

Open:

`Home -> textsys test env -> Fluent document surface lab`

Then test:

1. Drag-select from the first paragraph into the list and final paragraph.
2. Confirm selection is continuous, not row-limited.
3. Type into the continuous document.
4. Confirm the structured preview updates.
5. Inspect the buffer diagnostics to see visible offsets mapped to internal structure.
