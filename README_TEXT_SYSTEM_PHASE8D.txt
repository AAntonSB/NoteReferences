# Text System Phase 8D — Cross-paragraph Structured Copy/Paste Foundation

Phase 8D builds on the Phase 8C fluent document range model.

The user-facing principle remains:

> The user edits fluent text. The engine maps that text to internal structure underneath.

## Added

- `TextSystemDocumentFragmentEditResult`
  - reports the result of replacing a fluent document range with a structured fragment

- `TextSystemDocumentFragmentOps`
  - replaces a document-level range with a structured `TextSystemDocumentFragment`
  - supports inserting at a collapsed document position
  - supports replacing a range that spans multiple internal text units
  - preserves copied text marks where possible
  - keeps pasted paragraph/list/heading shape in the internal fragment

- `TextSystemController.copyDocumentFragmentByOffsets(...)`
  - convenience helper for simulated fluent selections

- `TextSystemController.replaceDocumentRangeWithFragment(...)`
  - transaction-safe structured fragment insertion

- `TextSystemController.pasteDocumentClipboardAtRange(...)`
- `TextSystemController.pasteDocumentClipboardAtPosition(...)`

- `TextOperationType.insertDocumentFragment`
  - serializable transaction operation for structured document paste actions

- `TextSystemStructuredClipboardLabScreen`
  - available from `textsys test env`
  - validates copying a cross-paragraph range
  - validates pasting that structured fragment at another document offset
  - validates replacing another range with the structured clipboard
  - shows document clipboard, transaction, undo/redo, and last-paste state

## Scope boundary

8D does not replace the visible editor with one continuous text surface yet. It provides the internal copy/paste foundation required for that future step.

Not included:

- full native cross-paragraph visible selection
- OS-level HTML/RTF clipboard integration
- nested lists
- LaTeX copy/paste conversion
- AI

## Manual check

Open:

`textsys test env -> Structured copy/paste lab`

Then:

1. Choose a copy range that spans more than one paragraph/list item.
2. Press **Copy range**.
3. Choose a paste offset.
4. Press **Paste at offset**.
5. Confirm marks and structure survive in the read-only preview.
6. Use undo/redo to confirm the operation is transaction-safe.
