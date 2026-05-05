Phase 6 — Project-wide Text System Core

This patch finishes the corrected Phase 6 direction: the app now has a reusable text-system foundation rather than a one-off workspace editor integration.

What was added

1. Text system core models
   - TextSystemDocument
   - TextSystemBlock
   - TextMark
   - TextSystemRange
   - TextClipboardFragment
   - TextOperation
   - TextTransaction
   - TextSystemController

2. Stable serialization
   - TextSystemDocument.toJson / fromJson
   - TextSystemBlock.toJson / fromJson
   - TextMark.toJson / fromJson
   - TextSystemRange.toJson / fromJson
   - TextClipboardFragment.toJson / fromJson
   - TextOperation.toJson / fromJson
   - TextTransaction.toJson / fromJson
   - TextSystemSnapshot.toJson / fromJson

3. Command/capability skeletons
   - TextSystemCommand
   - TextSystemCommandRegistry
   - TextSystemShortcutBinding
   - TextSystemCapability
   - TextSystemCapabilityRegistry

4. Persistence and autosave contracts
   - TextSystemPersistenceAdapter
   - InMemoryTextSystemPersistenceAdapter
   - TextSystemAutosaveController
   - TextSystemSaveState
   - TextSystemSaveStatus

5. Surface configuration contracts
   - TextSystemSurfaceConfig
   - TextSystemSurfaceKind
   - TextSystemEditorMode
   - TextSystemFeatureSet

6. Test environment upgrade
   - The textsys test env opens the Text Engine Core Lab.
   - The textsys test env now also opens the Persistence Safety Lab.
   - The core lab validates structured text, inline marks, rich internal copy/paste, undo/redo, snapshots, and transaction logging.
   - The persistence lab validates JSON round-tripping, save/load, autosave state, and surface feature contracts.

Design intent

The text system is intentionally format-neutral. It can back tiny text surfaces like todos and sidecar notes, ordinary rich text documents, and future premium writer shells. LaTeX remains a specialized source-aware branch rather than the global editing model.

Persistence and revision safety are treated as core infrastructure. This phase does not finalize the app storage backend, but it defines the storage boundary and proves that the structured document can be safely serialized, saved, loaded, and round-tripped.

Important limitation

The current labs still use Flutter TextField as editable input and render marks/JSON in separate inspection areas. Later phases should replace this with first-class polished surfaces that render and edit rich text directly.
