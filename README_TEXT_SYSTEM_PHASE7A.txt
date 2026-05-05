Phase 7A — Basic Text Surfaces: shared infrastructure

Goal
----
Create the reusable surface layer that future text-system shapes will share.
This patch does not build the final InlineTextSurface, SimpleNoteSurface,
DocumentTextSurface, or ReadOnlyTextSurface yet. It creates the shared contracts
and widgets that keep those surfaces from becoming separate hand-written editors.

Added
-----
- TextSystemSurfaceController
  Bridges TextEditingController, TextSystemController, selection state,
  formatting commands, rich internal clipboard, undo/redo, and optional autosave.

- TextSystemSelectionBridge
  Converts Flutter TextSelection objects to TextSystemRange and back.

- TextSystemKeyboardDispatcher
  Dispatches Ctrl/Cmd shortcuts through stable text-system command ids.

- TextSystemSurfaceToolbar
  Shared toolbar driven by command registry + surface feature switches.

- TextSystemSurfaceStatusBar
  Shared save/revision/selection status readout.

- TextSystemEditableSurfaceFrame
  Shared editable shell for future inline, note, and document surfaces.

- TextSystemCommandIds and TextSystemDefaultCommands
  Stable command ids for formatting, rich copy/paste, undo/redo, and save.

- TextLinkTarget
  Future-proof link target model. Internal links/backlinks are not implemented
  yet, but the link model now has room for app-native targets.

- Surface config updates
  Adds simpleNote/readOnly factories and feature flags for links/lists so Phase 7
  can reserve those features without building the full systems too early.

Test environment
----------------
The textsys test env now includes a "Surface infrastructure lab". Use it to test:
- selection bridge readouts
- toolbar command availability
- Ctrl/Cmd+B, Ctrl/Cmd+I, Ctrl/Cmd+Shift+H
- Ctrl/Cmd+Z / Ctrl+Y / Ctrl/Cmd+Shift+Z
- Ctrl/Cmd+S save handoff
- autosave status handoff
- revision + transaction updates

Next
----
Phase 7B should build the first concrete surfaces on top of this layer:
- InlineTextSurface
- ReadOnlyTextSurface
