# Text System Phase 8A — Fluent Text Surface Polish

Phase 8A starts the UX polish phase for the light/common text system. 

The guiding rule is:

> Structured internally, fluent externally.

The text system can keep paragraphs, headings, lists, todos, and quotes as internal blocks, but the user should feel like they are editing text, not managing blocks.

## Added / changed

- Added `TextSystemSurfaceFrameStyle`
  - `outlined` for explicit panels/labs
  - `subtle` for lightweight inline/note surfaces
  - `plain` for fluent document text

- Updated `TextSystemEditableSurfaceFrame`
  - supports calmer frame styles
  - reduces visual chrome where surfaces are embedded in text flow

- Updated `InlineTextSurface`
  - quieter default frame
  - calmer placeholder and text styling

- Updated `SimpleNoteSurface`
  - removes nested filled input chrome
  - keeps the note feeling like a writing area, not a form field inside a form field

- Updated `DocumentTextSurface`
  - document paragraphs now render in plain frame style by default
  - per-paragraph toolbars/status bars are hidden by default
  - a single document-level save/revision status is shown
  - copy uses user-facing language such as paragraph/list/style rather than block management language
  - the document reads more like one continuous text

- Updated `ReadOnlyTextSurface`
  - supports frame styles
  - calmer empty state and title presentation

- Added `TextSystemFluentTextPolishLabScreen`
  - available from `textsys test env`
  - compares inline, simple note, document, and read-only surfaces after the polish pass

## Deliberately not included

- no AI
- no floating selection toolbar
- no structural rearrange mode
- no drag handles
- no LaTeX/PDF work
- no premium writer shell
- no advanced list-enter/backspace behavior yet
- no full document-level cross-paragraph selection implementation yet

## Manual checks

Open:

`Home -> textsys test env -> Fluent text polish lab`

Check:

1. Inline text feels compact and quiet.
2. Simple note feels like a note, not a nested form field.
3. Document text no longer feels like a stack of visible block cards by default.
4. Read-only preview looks intentional and calm.
5. Save/revision status is visible without dominating the writing area.
6. Existing 7B/7C/7D/7E labs still open.
