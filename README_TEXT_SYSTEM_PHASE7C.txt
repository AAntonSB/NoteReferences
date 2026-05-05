# Text System Phase 7C — Simple Note Surface

Phase 7C adds the first practical lightweight multi-line note surface on top of the shared text-system infrastructure.

## Added

- `SimpleNoteSurface`
  - multi-line rich text note editor for sidecar notes, observations, comments, scratch notes, and light project notes
  - reuses `TextSystemSurfaceController`
  - reuses `TextSystemEditableSurfaceFrame`
  - reuses shared commands, shortcuts, undo/redo, rich internal clipboard, and autosave wiring
  - intentionally avoids document/premium-writer chrome

- `TextSystemSimpleNoteSurfaceLabScreen`
  - available from `textsys test env`
  - validates two independent note fields backed by the same text-system document
  - validates note editing -> read-only preview
  - validates rich copy/paste between note surfaces
  - validates autosave/transaction/mark state

## Scope boundary

This phase does not add the full document surface, heading/list commands, shortcut settings UI, source-aware LaTeX migration, or premium writer shell.

## Manual checks

Open:

`Home -> textsys test env -> Simple note surface lab`

Then test:

1. Edit both notes.
2. Select text and apply bold / italic / highlight.
3. Copy rich text from one note.
4. Paste it into the other note.
5. Confirm the read-only preview updates.
6. Confirm undo/redo works.
7. Confirm autosave and transaction counters update.
