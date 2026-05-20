import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../data/study_planning_repository.dart';
import '../domain/planning_intent.dart';
import '../domain/study_material_source.dart';
import 'create_project_screen.dart';
import 'project_planning_screen.dart';
import 'session_handoff_dialog.dart';
import 'work_composer_screen.dart';

Future<void> showProjectQuickAccessSheet({
  required BuildContext context,
  required StudyPlanningRepository planningRepository,
  String? sourceLabel,
  AppDatabase? database,
  StudyMaterialSource? initialMaterialSource,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _ProjectQuickAccessSheet(
      planningRepository: planningRepository,
      sourceLabel: sourceLabel,
      database: database,
      initialMaterialSource: initialMaterialSource,
    ),
  );
}

class _ProjectQuickAccessSheet extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final String? sourceLabel;
  final AppDatabase? database;
  final StudyMaterialSource? initialMaterialSource;

  const _ProjectQuickAccessSheet({
    required this.planningRepository,
    required this.sourceLabel,
    required this.database,
    required this.initialMaterialSource,
  });

  @override
  State<_ProjectQuickAccessSheet> createState() => _ProjectQuickAccessSheetState();
}

class _ProjectQuickAccessSheetState extends State<_ProjectQuickAccessSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.planningRepository,
      builder: (context, _) {
        final projects = widget.planningRepository.projects;
        final nextSessionItems = widget.planningRepository.activeHandoffEntries();

        return FractionallySizedBox(
          heightFactor: 0.88,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
                            'Study projects',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (widget.sourceLabel?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Opened from ${widget.sourceLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _createProject,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create project'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: projects.isEmpty
                      ? _EmptyProjectAccessState(onCreateProject: _createProject)
                      : ListView(
                          children: [
                            _QuickAccessSection(
                              title: 'Projects',
                              icon: Icons.dashboard_customize_rounded,
                              child: Column(
                                children: [
                                  for (final project in projects) ...[
                                    _ProjectAccessCard(
                                      project: project,
                                      planCount: widget.planningRepository.plansForProject(project.id).length,
                                      nextSessionCount: widget.planningRepository
                                          .activeHandoffEntries(projectId: project.id)
                                          .length,
                                      onOpen: () => _openProject(project),
                                      onEndSession: () => _captureSession(project),
                                      onPlanSource: widget.initialMaterialSource == null
                                          ? null
                                          : () => _planCurrentSource(project),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (nextSessionItems.isNotEmpty)
                              _QuickAccessSection(
                                title: 'Next session',
                                icon: Icons.next_plan_rounded,
                                child: Column(
                                  children: [
                                    for (final entry in nextSessionItems.take(8))
                                      _NextSessionAccessRow(
                                        entry: entry,
                                        onToggleDone: (value) => _toggleHandoffItem(entry, value),
                                        onConvertToTodo: () => _convertHandoffItemToTodo(entry),
                                        onOpenProject: () => _openProject(entry.project),
                                      ),
                                    if (nextSessionItems.length > 8)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          '+${nextSessionItems.length - 8} more next-session items',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createProject() async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(
          planningRepository: widget.planningRepository,
          openPlanAfterCreate: true,
          database: widget.database,
          initialMaterialSource: widget.initialMaterialSource,
        ),
      ),
    );
  }

  void _openProject(StudyProject project) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ProjectPlanningScreen(
          planningRepository: widget.planningRepository,
          projectId: project.id,
          database: widget.database,
        ),
      ),
    );
  }

  Future<void> _planCurrentSource(StudyProject project) async {
    final source = widget.initialMaterialSource;
    if (source == null) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push<StudyPlan>(
      MaterialPageRoute(
        builder: (_) => WorkComposerScreen(
          planningRepository: widget.planningRepository,
          project: project,
          initialIntent: PlanningIntentType.studyMaterial,
          database: widget.database,
          initialMaterialSource: source,
        ),
      ),
    );
  }

  Future<void> _captureSession(StudyProject project) async {
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

  Future<void> _toggleHandoffItem(SessionHandoffEntry entry, bool isDone) async {
    await widget.planningRepository.updateSessionHandoffItemDone(
      handoffId: entry.handoff.id,
      itemId: entry.item.id,
      isDone: isDone,
    );
  }

  Future<void> _convertHandoffItemToTodo(SessionHandoffEntry entry) async {
    final tomorrow = _dateOnly(DateTime.now().add(const Duration(days: 1)));
    final plan = await widget.planningRepository.convertHandoffItemToTodo(
      handoffId: entry.handoff.id,
      itemId: entry.item.id,
      taskDate: tomorrow,
    );

    if (!mounted || plan == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Converted “${entry.item.text}” to a task for tomorrow.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _EmptyProjectAccessState extends StatelessWidget {
  final VoidCallback onCreateProject;

  const _EmptyProjectAccessState({required this.onCreateProject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dashboard_customize_rounded, size: 44, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'No active projects yet',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create a project so plans, next-session notes, and calendar work have somewhere to live.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onCreateProject,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create project'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAccessSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _QuickAccessSection({
    required this.title,
    required this.icon,
    required this.child,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProjectAccessCard extends StatelessWidget {
  final StudyProject project;
  final int planCount;
  final int nextSessionCount;
  final VoidCallback onOpen;
  final VoidCallback onEndSession;
  final VoidCallback? onPlanSource;

  const _ProjectAccessCard({
    required this.project,
    required this.planCount,
    required this.nextSessionCount,
    required this.onOpen,
    required this.onEndSession,
    this.onPlanSource,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNextSession = nextSessionCount > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasNextSession
              ? theme.colorScheme.primaryContainer.withAlpha(90)
              : theme.colorScheme.surfaceContainerHighest.withAlpha(90),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasNextSession
                ? theme.colorScheme.primary.withAlpha(100)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MiniBadge(icon: Icons.route_rounded, label: '$planCount ${planCount == 1 ? 'item' : 'items'}'),
                      if (nextSessionCount > 0)
                        _MiniBadge(
                          icon: Icons.next_plan_rounded,
                          label: '$nextSessionCount next session',
                          isEmphasized: true,
                        ),
                      if (project.deadline != null)
                        _MiniBadge(icon: Icons.flag_rounded, label: _formatDate(project.deadline!)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'End session for this project',
              onPressed: onEndSession,
              icon: const Icon(Icons.next_plan_rounded),
            ),
            if (onPlanSource != null) ...[
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onPlanSource,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Plan PDF'),
              ),
            ],
            FilledButton.tonal(
              onPressed: onOpen,
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextSessionAccessRow extends StatelessWidget {
  final SessionHandoffEntry entry;
  final ValueChanged<bool> onToggleDone;
  final VoidCallback onConvertToTodo;
  final VoidCallback onOpenProject;

  const _NextSessionAccessRow({
    required this.entry,
    required this.onToggleDone,
    required this.onConvertToTodo,
    required this.onOpenProject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Checkbox(
              value: entry.item.isDone,
              onChanged: (value) => onToggleDone(value ?? false),
            ),
            Expanded(
              child: InkWell(
                onTap: onOpenProject,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.item.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.project.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Next-session actions',
              onSelected: (value) {
                if (value == 'todo') onConvertToTodo();
                if (value == 'project') onOpenProject();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'todo',
                  child: ListTile(
                    leading: Icon(Icons.task_alt_rounded),
                    title: Text('Make task for tomorrow'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'project',
                  child: ListTile(
                    leading: Icon(Icons.open_in_new_rounded),
                    title: Text('Open project'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isEmphasized;

  const _MiniBadge({
    required this.icon,
    required this.label,
    this.isEmphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isEmphasized
            ? theme.colorScheme.primary.withAlpha(22)
            : theme.colorScheme.surface.withAlpha(170),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isEmphasized
              ? theme.colorScheme.primary.withAlpha(80)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isEmphasized ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: isEmphasized ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}
