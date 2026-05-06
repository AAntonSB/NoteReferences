# Text System Phase 9F — Fluent Editor Diagnostic Tool

Phase 9F adds a diagnostic/acceptance lab for the new `FluentDocumentSurface` path.

The goal is not to add another editor feature. The goal is to make failures inspectable and shareable so the fluent editor can be hardened deliberately.

## Added

- `TextSystemDocumentValidator`
  - validates document identity
  - validates text-unit ids
  - validates text-unit shape metadata
  - validates mark ranges
  - validates JSON round-trip safety
  - validates structured document fragments

- `TextSystemPhase9DiagnosticsLabScreen`
  - contains a fluent editor under test
  - shows a read-only structured preview mirror
  - shows live diagnostics
  - generates a plain-text diagnostic report
  - copies the report to the OS clipboard so it can be pasted back into chat

## Manual diagnosis workflow

1. Open `textsys test env`.
2. Open `Phase 9 diagnostics lab`.
3. Reproduce the issue in the fluent editor.
4. Click `Copy report`.
5. Paste the full report back into chat.

The report includes:

- visible text preview
- validation check lines
- document metrics
- save state
- undo/redo state
- selection offsets
- mapped document range
- buffer segment mapping
- structured clipboard state
- flat clipboard fallback state
- recent transaction labels
- machine-readable document JSON

## Product rule preserved

The tool diagnoses the fluent editor without changing the UX principle:

> The user edits fluent text. Structure remains underneath.
