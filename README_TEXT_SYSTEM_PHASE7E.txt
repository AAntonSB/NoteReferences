# Text System Phase 7E — Command and Shortcut Hardening

Phase 7E completes the Basic Text Surfaces phase by hardening the command and shortcut layer used by all lightweight text-system surfaces.

## Added / changed

- Centralized shortcut profile
  - `TextSystemShortcutBinding`
  - `TextSystemShortcutProfile.defaults()`
  - shortcut dispatcher now consumes a profile instead of hardcoding bindings locally
  - prepares the future settings page for shortcut rebinding

- Command registry hardening
  - `commandIds`
  - `contains(id)`
  - `availableCommands(context)`

- Expanded stable command ids
  - underline
  - strikethrough
  - inline code
  - link marker placeholder

- Default command hardening
  - toolbar and keyboard paths execute the same command registry
  - copy/paste availability now respects rich clipboard capability
  - link command now applies/removes a link-style mark instead of being a no-op
  - link remains a placeholder mark; the internal link resolver/backlink graph is intentionally future work

- Surface infrastructure refinement
  - `TextSystemEditableSurfaceFrame` accepts an optional shortcut profile
  - `TextSystemKeyboardDispatcher` uses the active shortcut profile
  - `TextSystemSurfaceToolbar` exposes extra inline formatting commands on non-compact surfaces

- New reusable reference UI
  - `TextSystemShortcutReferencePanel`
  - lists command labels, shortcut bindings, and current availability

- New test env page
  - `TextSystemCommandShortcutLabScreen`
  - validates commands, shortcuts, availability, link marker placeholder, undo/redo, save, and rich clipboard behavior

## Scope boundary

Phase 7E does not add a settings screen for rebinding shortcuts. It creates the runtime model that a settings screen can later edit.

Phase 7E also does not add smart list continuation. In Phase 7D, lists are block conversions/rendering; Enter-to-continue-list behavior belongs to a later UX pass.

## Manual checks

Open:

`Home -> textsys test env -> Command and shortcut lab`

Then test:

1. Select text.
2. Run Bold / Italic / Underline / Highlight / Link marker from the toolbar.
3. Try Ctrl/Cmd+B, Ctrl/Cmd+I, Ctrl/Cmd+U, Ctrl/Cmd+Shift+H, Ctrl/Cmd+K.
4. Confirm unavailable commands are disabled when no text is selected.
5. Copy rich text and paste it back.
6. Undo and redo.
7. Save manually.
8. Confirm the shortcut reference panel reflects command availability.

## Phase 7 acceptance

Phase 7 can be considered complete when the app has:

- inline text surface
- read-only text surface
- simple note surface
- document text surface
- shared formatting behavior
- shared rich clipboard behavior
- shared undo/redo behavior
- shared autosave hook behavior
- shared command ids
- shared shortcut profile
- test environment coverage for each surface
