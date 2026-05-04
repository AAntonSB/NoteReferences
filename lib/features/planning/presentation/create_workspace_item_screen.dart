import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';
import 'create_workspace_document_screen.dart';

/// Backwards-compatible shim for older project builds that still reference
/// CreateWorkspaceItemScreen. Workspace items were replaced by generic
/// WorkspaceDocument objects, so this screen now forwards to document creation.
class CreateWorkspaceItemScreen extends StatelessWidget {
  final StudyPlanningRepository planningRepository;
  final StudyProject project;

  const CreateWorkspaceItemScreen({
    super.key,
    required this.planningRepository,
    required this.project,
  });

  @override
  Widget build(BuildContext context) {
    return CreateWorkspaceDocumentScreen(
      planningRepository: planningRepository,
      project: project,
    );
  }
}
