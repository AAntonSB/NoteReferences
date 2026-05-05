Phase 4 — Custom LaTeX macro registry

Adds a reusable macro registry for the new isolated source-aware editor subsystem.

Included:
- lib/features/source_editor/latex/latex_macro_registry.dart
- LatexSourceParser now accepts an optional LatexMacroRegistry.
- Default macro renderers for:
  - \\role{title}{dates}{organization}{location}{description}
  - \\education{degree}{dates}{institution}{location}{description?}
  - \\project{name}{context}{description}
  - \\skillrow{category}{skills}
  - \\cvitem{label}{content}
- SourceAwareEditor renders structured macro blocks more cleanly.

The subsystem is still isolated and does not replace the production document editor.
Source remains canonical: clicking a macro block still edits the underlying source block.
