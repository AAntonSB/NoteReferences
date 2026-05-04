import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';
import 'workspace_document_editor_screen.dart';

/// Backwards-compatible shim for older project builds that still reference
/// WorkspaceItemEditorScreen. Workspace items were replaced by generic
/// WorkspaceDocument objects, so this screen now forwards to document editing.
class WorkspaceItemEditorScreen extends StatelessWidget {
  final StudyPlanningRepository planningRepository;
  final String itemId;

  const WorkspaceItemEditorScreen({
    super.key,
    required this.planningRepository,
    required this.itemId,
  });

  @override
  Widget build(BuildContext context) {
    return WorkspaceDocumentEditorScreen(
      planningRepository: planningRepository,
      documentId: itemId,
    );
  }
}
