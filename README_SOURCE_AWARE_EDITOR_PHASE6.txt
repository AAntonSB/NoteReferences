# Source-aware editor — Phase 6 workspace integration

Phase 6 wires the reusable Phase 5 editor kernel into the app-level document workspace.

## What changed

- Workspace LaTeX documents now use `SourceDocumentController` as their canonical editing controller.
- LaTeX workspace rendering now goes through `SourceAwareEditor` + `LatexSourceParser` instead of the older bespoke `LatexHybridEditor` surface.
- The workspace LaTeX toolbar exposes the reusable editor modes:
  - Visual
  - Source
  - Editor + output
  - Output
- Manual PDF compilation now uses `SourceLatexCompileService`.
- Successful PDF builds store the latest compiled PDF path back onto the workspace document as a `pdf:<path>` tag, preserving the existing app behavior for attached/exported PDFs.
- Workspace sets now seed newly-created LaTeX CV/reference documents with source-aware CV macros:
  - `\role`
  - `\education`
  - `\project`
  - `\skillrow`

## Integration path

The workspace primitive remains generic:

- job ad = source document
- CV/reference = LaTeX source-aware document
- personal letter = working document
- PDF = manually compiled output attached to the document
- notes/templates/links = same `WorkspaceDocument` model

The important boundary is now preserved:

`WorkspaceDocument.body` stores canonical source text.

The visual editor never owns the document. It derives blocks from source and applies edits back to source ranges.

## Main files

- `lib/features/planning/presentation/workspace_document_editor_screen.dart`
- `lib/features/planning/presentation/document_workspace_screen.dart`
- `lib/features/source_editor/source_editor.dart`
- `lib/features/source_editor/latex/latex_compile_service.dart`
- `lib/features/source_editor/parsers/latex_source_parser.dart`

## Notes

The older `latex_document_tools.dart` file is left in the tree for now as legacy code/reference. The workspace document editor no longer imports it.
