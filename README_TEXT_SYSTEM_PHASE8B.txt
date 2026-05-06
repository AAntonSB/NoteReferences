# Text System Phase 8B — Natural Document Keyboard Behavior

Phase 8B recreates the natural keyboard behavior patch in a smaller, safer form.

## Goal

Keep the document surface text-first while allowing the internal structured model to handle natural paragraph transitions.

The user should feel like they are editing text, not managing blocks.

## Added

- Natural Enter behavior in `DocumentTextSurface`
  - paragraph + Enter splits into a new paragraph
  - heading + Enter creates a paragraph below
  - bullet item + Enter creates another bullet item
  - numbered item + Enter creates another numbered item
  - todo + Enter creates another todo item
  - quote + Enter creates another quote
  - empty bullet/numbered/todo/quote + Enter exits to a paragraph

- Limited Backspace-at-start behavior
  - bullet/numbered/todo/quote at the start converts back to paragraph
  - paragraph at the start merges into the previous text unit

- Ordered-list renumbering after insert, exit, merge, or delete

- Focus handoff after structural text transitions

- `TextSystemNaturalKeyboardLabScreen`
  - available from `textsys test env`
  - validates Enter, Backspace-at-start, list continuation, and read-only rendering

## Not included

- cross-paragraph selection
- cross-paragraph rich copy/paste
- nested lists
- Tab / Shift+Tab indentation
- markdown shortcuts like typing `* `
- LaTeX work
- premium writer shell
- AI

## Manual checks

Open:

`Home -> textsys test env -> Natural keyboard lab`

Then test:

1. Put the cursor at the end of a paragraph and press Enter.
2. Put the cursor in the middle of a paragraph and press Enter.
3. Put the cursor at the end of a bullet item and press Enter.
4. Press Enter on an empty bullet item and confirm it exits to a paragraph.
5. Repeat with numbered items and confirm numbering updates.
6. Press Backspace at the start of a bullet/quote/todo and confirm it becomes a paragraph.
7. Press Backspace at the start of a paragraph and confirm it merges with the previous text unit.
