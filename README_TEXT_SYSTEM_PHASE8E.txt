# Text System Phase 8E — Light Editor Acceptance Pass

Phase 8E closes the fluent text UX foundation phase with a consolidated acceptance lab.

## Added

- `TextSystemPhase8AcceptanceLabScreen`
  - editable `DocumentTextSurface`
  - read-only rendering of the same document
  - acceptance checks for JSON round-trip, document-level ranges, structured clipboard, structured paste, undo/redo, persistence save/load, and the text-first UX rule

- `textsys test env` entry:
  - **Phase 8 acceptance lab**

## Product rule preserved

The user edits fluent text. Internal structure is allowed only where it preserves text fidelity, persistence safety, rendering, copy/paste, and future format adapters.

Phase 8 intentionally does not add:

- AI
- floating selection toolbar
- structural rearrange mode
- block handles
- LaTeX/PDF work
- premium writer shell

## Manual checks

Open:

`Home -> textsys test env -> Phase 8 acceptance lab`

Then:

1. Edit the document.
2. Run the acceptance checks.
3. Confirm all checks pass.
4. Save manually.
5. Snapshot the document.
6. Confirm undo/redo still works after the structured paste check.

If this builds locally and the lab checks pass, Phase 8 can be considered complete.
