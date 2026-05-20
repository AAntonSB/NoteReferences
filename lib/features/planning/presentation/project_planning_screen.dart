import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../data/study_planning_repository.dart';
import 'planning_create_hub_screen.dart';
import 'dev_todo_drawer.dart';
import 'create_workspace_document_screen.dart';
import 'session_handoff_dialog.dart';
import 'document_workspace_screen.dart';

enum _HandoffAction { convertToTodo, delete }

class ProjectPlanningScreen extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final String projectId;
  final AppDatabase? database;

  const ProjectPlanningScreen({
    super.key,
    required this.planningRepository,
    required this.projectId,
    this.database,
  });

  @override
  State<ProjectPlanningScreen> createState() => _ProjectPlanningScreenState();
}

class _ProjectPlanningScreenState extends State<ProjectPlanningScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.planningRepository,
      builder: (context, _) {
        final project = widget.planningRepository.projectById(widget.projectId);
        if (project == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Project')),
            body: const Center(child: Text('Project not found.')),
          );
        }

        final theme = Theme.of(context);
        final plans = widget.planningRepository.plansForProject(project.id);
        final handoffs = widget.planningRepository.handoffsForProject(project.id);
        final documents = widget.planningRepository.documentsForProject(project.id);

        return Scaffold(
          backgroundColor: theme.colorScheme.surfaceContainerLowest,
          appBar: AppBar(
            title: Text(project.title),
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Dev todos',
                onPressed: _openDevTodos,
                icon: const Icon(Icons.bug_report_outlined),
              ),
              IconButton(
                tooltip: 'Remove project',
                onPressed: () => _archiveProject(project),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              TextButton.icon(
                onPressed: () => _openEndSession(project),
                icon: const Icon(Icons.next_plan_rounded),
                label: const Text('End session'),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.tonalIcon(
                  onPressed: () => _addPlan(project),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Plan work'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _ProjectSummaryCard(project: project, plans: plans),
              const SizedBox(height: 16),
              _NextSessionCard(
                handoffs: handoffs,
                onCapture: () => _openEndSession(project),
                onToggleDone: _toggleHandoffItem,
                onConvertToTodo: _convertHandoffItemToTodo,
                onDelete: _deleteHandoffItem,
              ),
              const SizedBox(height: 16),
              _ProjectDocumentsSection(
                documents: documents,
                onAddDocument: () => _addDocument(project),
                onOpenDocument: _openWorkspaceDocument,
              ),
              const SizedBox(height: 16),
              Text(
                'Planned work',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (plans.isEmpty)
                _EmptyPlansCard(onAddPlan: () => _addPlan(project))
              else
                for (final plan in plans) ...[
                  _PlanCard(
                    plan: plan,
                    onArchive: () => _archivePlan(plan),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDevTodos() async {
    await showDevTodoDrawer(
      context: context,
      planningRepository: widget.planningRepository,
    );
  }

  Future<void> _openEndSession(StudyProject project) async {
    final items = await showDialog<List<String>>(
      context: context,
      builder: (_) => EndSessionDialog(projectTitle: project.title),
    );
    if (items == null || items.isEmpty) return;

    await widget.planningRepository.addSessionHandoffItems(
      projectId: project.id,
      itemTexts: items,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved ${items.length} next-session ${items.length == 1 ? 'item' : 'items'}.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleHandoffItem(
    SessionHandoff handoff,
    SessionHandoffItem item,
    bool isDone,
  ) async {
    await widget.planningRepository.updateSessionHandoffItemDone(
      handoffId: handoff.id,
      itemId: item.id,
      isDone: isDone,
    );
  }

  Future<void> _deleteHandoffItem(
    SessionHandoff handoff,
    SessionHandoffItem item,
  ) async {
    await widget.planningRepository.deleteSessionHandoffItem(
      handoffId: handoff.id,
      itemId: item.id,
    );
  }

  Future<void> _convertHandoffItemToTodo(
    SessionHandoff handoff,
    SessionHandoffItem item,
  ) async {
    final tomorrow = _dateOnly(DateTime.now().add(const Duration(days: 1)));
    final plan = await widget.planningRepository.convertHandoffItemToTodo(
      handoffId: handoff.id,
      itemId: item.id,
      taskDate: tomorrow,
    );

    if (!mounted || plan == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Converted “${item.text}” to a task for tomorrow.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addPlan(StudyProject project) async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => PlanningCreateHubScreen(
          planningRepository: widget.planningRepository,
          initialProject: project,
          database: widget.database,
        ),
      ),
    );
  }

  Future<void> _addDocument(StudyProject project) async {
    await Navigator.of(context).push<WorkspaceDocument>(
      MaterialPageRoute(
        builder: (_) => CreateWorkspaceDocumentScreen(
          planningRepository: widget.planningRepository,
          project: project,
        ),
      ),
    );
  }

  Future<void> _openWorkspaceDocument(WorkspaceDocument document) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DocumentWorkspaceScreen(
          planningRepository: widget.planningRepository,
          initialDocumentId: document.id,
          projectId: widget.projectId,
        ),
      ),
    );
  }

  Future<void> _archivePlan(StudyPlan plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove plan?'),
        content: Text('Remove “${plan.title}”? It will no longer generate daily requirements.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.planningRepository.archivePlan(plan.id);
  }

  Future<void> _archiveProject(StudyProject project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove project?'),
        content: Text('Remove “${project.title}” and all its plans? This keeps the planning data archived but removes it from Today and the calendar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove project'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.planningRepository.archiveProject(project.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}


class _ProjectDocumentsSection extends StatelessWidget {
  final List<WorkspaceDocument> documents;
  final VoidCallback onAddDocument;
  final ValueChanged<WorkspaceDocument> onOpenDocument;

  const _ProjectDocumentsSection({
    required this.documents,
    required this.onAddDocument,
    required this.onOpenDocument,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(130),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.description_outlined, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Documents', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        documents.isEmpty
                            ? 'Add job ads, CV drafts, letters, notes, templates, or source text.'
                            : '${documents.length} project ${documents.length == 1 ? 'document' : 'documents'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAddDocument,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New document'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (documents.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Documents are intentionally generic. A pasted job ad is a source document; a CV is a versioned working/template document; a personal letter is a working document.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              )
            else
              for (final document in documents) ...[
                _WorkspaceDocumentTile(document: document, onOpen: () => onOpenDocument(document)),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceDocumentTile extends StatelessWidget {
  final WorkspaceDocument document;
  final VoidCallback onOpen;

  const _WorkspaceDocumentTile({required this.document, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(_iconForDocument(document), color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _TinyPill(label: WorkspaceDocumentKind.label(document.kind)),
                        if (document.language?.isNotEmpty == true) _TinyPill(label: document.language!),
                        for (final tag in document.tags.take(3)) _TinyPill(label: tag),
                        if (document.versions.length > 1) _TinyPill(label: '${document.versions.length} versions'),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  final String label;

  const _TinyPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

IconData _iconForDocument(WorkspaceDocument document) {
  switch (WorkspaceDocumentKind.normalize(document.kind)) {
    case WorkspaceDocumentKind.source:
      return Icons.article_outlined;
    case WorkspaceDocumentKind.template:
      return Icons.dashboard_customize_outlined;
    case WorkspaceDocumentKind.link:
      return Icons.link_rounded;
    case WorkspaceDocumentKind.collection:
      return Icons.folder_outlined;
    case WorkspaceDocumentKind.working:
    default:
      return Icons.edit_document;
  }
}

class _NextSessionCard extends StatelessWidget {
  final List<SessionHandoff> handoffs;
  final VoidCallback onCapture;
  final void Function(SessionHandoff handoff, SessionHandoffItem item, bool isDone) onToggleDone;
  final void Function(SessionHandoff handoff, SessionHandoffItem item) onConvertToTodo;
  final void Function(SessionHandoff handoff, SessionHandoffItem item) onDelete;

  const _NextSessionCard({
    required this.handoffs,
    required this.onCapture,
    required this.onToggleDone,
    required this.onConvertToTodo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <({SessionHandoff handoff, SessionHandoffItem item})>[
      for (final handoff in handoffs)
        for (final item in handoff.items) (handoff: handoff, item: item),
    ];
    final openCount = items.where((entry) => !entry.item.isDone).length;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer.withAlpha(130),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.next_plan_rounded, color: theme.colorScheme.tertiary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next session',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        openCount == 0
                            ? 'Capture the thread you want to resume from.'
                            : '$openCount active ${openCount == 1 ? 'thought' : 'thoughts'} waiting.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onCapture,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Capture'),
                ),
              ],
            ),
            if (items.isEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'No handoff yet. When you stop working, write the questions, loose ends, and exact next steps future you should see first.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 14),
              for (final entry in items) ...[
                _NextSessionItemTile(
                  item: entry.item,
                  onChanged: (value) => onToggleDone(entry.handoff, entry.item, value),
                  onConvertToTodo: () => onConvertToTodo(entry.handoff, entry.item),
                  onDelete: () => onDelete(entry.handoff, entry.item),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _NextSessionItemTile extends StatelessWidget {
  final SessionHandoffItem item;
  final ValueChanged<bool> onChanged;
  final VoidCallback onConvertToTodo;
  final VoidCallback onDelete;

  const _NextSessionItemTile({
    required this.item,
    required this.onChanged,
    required this.onConvertToTodo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = item.isDone;

    return Container(
      decoration: BoxDecoration(
        color: done ? theme.colorScheme.surfaceContainerHighest.withAlpha(120) : theme.colorScheme.tertiaryContainer.withAlpha(70),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(done ? 110 : 180)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: done,
            onChanged: (value) => onChanged(value ?? true),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          Expanded(
            child: Text(
              item.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
              ),
            ),
          ),
          PopupMenuButton<_HandoffAction>(
            tooltip: 'Next-session actions',
            onSelected: (action) {
              switch (action) {
                case _HandoffAction.convertToTodo:
                  onConvertToTodo();
                  break;
                case _HandoffAction.delete:
                  onDelete();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _HandoffAction.convertToTodo,
                enabled: !done,
                child: const ListTile(
                  leading: Icon(Icons.task_alt_rounded),
                  title: Text('Convert to task for tomorrow'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _HandoffAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  final StudyProject project;
  final List<StudyPlan> plans;

  const _ProjectSummaryCard({required this.project, required this.plans});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activePlans = plans.where((plan) => !plan.isComplete).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Study project',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withAlpha(200),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            project.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(icon: Icons.route_rounded, label: '$activePlans active plans'),
              _MetricPill(icon: Icons.done_all_rounded, label: '${plans.where((plan) => plan.isComplete).length} complete'),
              if (project.deadline != null)
                _MetricPill(
                  icon: Icons.flag_rounded,
                  label: 'Deadline ${_formatDate(project.deadline!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final StudyPlan plan;
  final VoidCallback onArchive;

  const _PlanCard({required this.plan, required this.onArchive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = plan.progress.clamp(0.0, 1.0);
    final subtitle = _subtitleForPlan(plan);
    final detail = _detailForPlan(plan);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove plan',
                  onPressed: onArchive,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (plan.isRecurring || plan.isSingleTask || plan.isDeadlineMarker)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconForPlan(plan), size: 18, color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      StudyPlanKind.label(plan.planKind),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress, minHeight: 10),
              ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconForPlan(StudyPlan plan) {
  if (plan.isRecurring) return Icons.repeat_rounded;
  if (plan.isSingleTask) return Icons.task_alt_rounded;
  if (plan.isDeadlineMarker) return Icons.flag_rounded;
  if (plan.isChecklist) return Icons.fact_check_rounded;
  return Icons.route_rounded;
}

String _subtitleForPlan(StudyPlan plan) {
  if (plan.isRecurring) {
    return '${plan.dailyTargetValue} ${plan.unitNounForCount(plan.dailyTargetValue)} per study day · ${plan.deadline == null ? 'running indefinitely' : 'until ${_formatDate(plan.deadline!)}'}';
  }
  if (plan.isSingleTask) {
    return 'Single task · ${plan.taskDate == null ? 'no date' : _formatDate(plan.taskDate!)}';
  }
  if (plan.isDeadlineMarker) {
    final date = plan.deadline ?? plan.taskDate;
    return 'Deadline marker · ${date == null ? 'no date' : _formatDate(date)}';
  }
  if (plan.isChecklist) {
    return '${plan.checklistItems.length} checklist items · ${plan.deadline == null ? 'no deadline' : 'deadline ${_formatDate(plan.deadline!)}'}';
  }
  return '${plan.startUnit}–${plan.endUnit} ${plan.unitNounForCount(plan.totalUnits)} · ${plan.deadline == null ? 'no deadline' : 'deadline ${_formatDate(plan.deadline!)}'}';
}

String _detailForPlan(StudyPlan plan) {
  if (plan.isRecurring) {
    return '${plan.completedDateKeys.length} study days checked off. Missed days become study debt.';
  }
  if (plan.isSingleTask) {
    return plan.isComplete ? 'Complete' : 'If missed, this becomes unresolved study debt.';
  }
  if (plan.isDeadlineMarker) {
    return plan.isComplete ? 'Marked done' : 'Fixed calendar marker. It does not redistribute as work.';
  }
  if (plan.isChecklist) {
    if (plan.isComplete) return 'Complete';
    return '${plan.completedChecklistIndexes.length}/${plan.checklistItems.length} items complete. Missed items become study debt.';
  }
  return plan.isComplete
      ? 'Complete'
      : 'Completed through ${plan.unitLabel} ${plan.completedThroughUnit}. ${plan.remainingUnits} ${plan.unitNounForCount(plan.remainingUnits)} remaining.';
}

class _EmptyPlansCard extends StatelessWidget {
  final VoidCallback onAddPlan;

  const _EmptyPlansCard({required this.onAddPlan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.route_rounded, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            'No project items yet',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose what you want to do: finish work by a date, add a task, mark a deadline, build a routine, or plan a checklist.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAddPlan,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Plan work'),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurface),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
