import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../data/study_planning_repository.dart';
import '../domain/planning_intent.dart';
import 'create_project_screen.dart';
import 'planning_entry_dialog.dart';
import 'work_composer_screen.dart';

class PlanningCreateHubScreen extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final StudyProject? initialProject;
  final AppDatabase? database;

  const PlanningCreateHubScreen({
    super.key,
    required this.planningRepository,
    this.initialProject,
    this.database,
  });

  @override
  State<PlanningCreateHubScreen> createState() => _PlanningCreateHubScreenState();
}

class _PlanningCreateHubScreenState extends State<PlanningCreateHubScreen> {
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.initialProject?.id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.planningRepository,
      builder: (context, _) {
        final projects = widget.planningRepository.projects;
        final selectedProject = _selectedProject(projects);

        return Scaffold(
          backgroundColor: theme.colorScheme.surfaceContainerLowest,
          appBar: AppBar(
            title: const Text('Plan work'),
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _PlanningHubHero(
                    selectedProject: selectedProject,
                    lockedToProject: widget.initialProject != null,
                    projectCount: projects.length,
                  ),
                  const SizedBox(height: 16),
                  if (widget.initialProject == null) ...[
                    _QuickInboxCard(onQuickAdd: _quickAddEntry),
                    const SizedBox(height: 16),
                    _ProjectPickerCard(
                      projects: projects,
                      selectedProjectId: _selectedProjectId ?? (projects.length == 1 ? projects.first.id : null),
                      onChanged: (value) => setState(() => _selectedProjectId = value),
                      onCreateProject: _createProject,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _PlanningShapeGrid(
                    selectedProject: selectedProject,
                    hasAnyProject: projects.isNotEmpty,
                    onChoose: _openComposerForIntent,
                    onCreateProject: _createProject,
                  ),
                  const SizedBox(height: 16),
                  _PlanningModelNote(theme: theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  StudyProject? _selectedProject(List<StudyProject> projects) {
    final explicit = _selectedProjectId;
    if (explicit != null) {
      for (final project in projects) {
        if (project.id == explicit) return project;
      }
    }
    if (widget.initialProject != null) return widget.initialProject;
    if (projects.length == 1) return projects.first;
    return null;
  }

  Future<void> _createProject() async {
    final project = await Navigator.of(context).push<StudyProject>(
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(
          planningRepository: widget.planningRepository,
          openPlanAfterCreate: false,
          database: widget.database,
        ),
      ),
    );

    if (!mounted || project == null) return;
    setState(() => _selectedProjectId = project.id);
  }

  Future<void> _quickAddEntry() async {
    final entry = await showPlanningEntryDialog(
      context: context,
      planningRepository: widget.planningRepository,
      projectId: null,
    );
    if (!mounted || entry == null) return;
    Navigator.of(context).pop(entry);
  }

  Future<void> _openComposerForIntent(PlanningIntentType intent) async {
    var project = _selectedProject(widget.planningRepository.projects);
    final projectRequired = intent != PlanningIntentType.addTask &&
        intent != PlanningIntentType.rememberDeadline;

    if (!projectRequired && project == null) {
      final entry = await showPlanningEntryDialog(
        context: context,
        planningRepository: widget.planningRepository,
        initialKind: intent == PlanningIntentType.rememberDeadline
            ? PlanningEntryKind.deadline
            : PlanningEntryKind.task,
      );
      if (!mounted || entry == null) return;
      Navigator.of(context).pop(entry);
      return;
    }

    if (project == null && projectRequired && widget.planningRepository.projects.isEmpty) {
      project = await Navigator.of(context).push<StudyProject>(
        MaterialPageRoute(
          builder: (_) => CreateProjectScreen(
            planningRepository: widget.planningRepository,
            openPlanAfterCreate: false,
            database: widget.database,
          ),
        ),
      );
      if (!mounted || project == null) return;
      final createdProjectId = project.id;
      setState(() => _selectedProjectId = createdProjectId);
    }

    project ??= _selectedProject(widget.planningRepository.projects);
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a project for structured study plans, or use Quick inbox for unassigned tasks.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final created = await Navigator.of(context).push<StudyPlan>(
      MaterialPageRoute(
        builder: (_) => WorkComposerScreen(
          planningRepository: widget.planningRepository,
          project: project!,
          initialIntent: intent,
          database: widget.database,
        ),
      ),
    );

    if (!mounted || created == null) return;
    Navigator.of(context).pop(created);
  }
}

class _PlanningHubHero extends StatelessWidget {
  final StudyProject? selectedProject;
  final bool lockedToProject;
  final int projectCount;

  const _PlanningHubHero({
    required this.selectedProject,
    required this.lockedToProject,
    required this.projectCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetText = selectedProject == null
        ? projectCount == 0
            ? 'Add a quick inbox item, or create a project for structured study plans.'
            : 'Add a quick inbox item, or pick a project for structured study plans.'
        : lockedToProject
            ? 'You are adding work to ${selectedProject!.title}.'
            : 'Selected project: ${selectedProject!.title}.';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer.withAlpha(210),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withAlpha(190),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.auto_awesome_motion_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What do you want to do?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  targetText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withAlpha(220),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _QuickInboxCard extends StatelessWidget {
  final VoidCallback onQuickAdd;

  const _QuickInboxCard({required this.onQuickAdd});

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.inbox_rounded, color: theme.colorScheme.onTertiaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick inbox', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(
                    'Capture a task, reminder, event, or deadline without deciding project structure first.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: onQuickAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add item'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectPickerCard extends StatelessWidget {
  final List<StudyProject> projects;
  final String? selectedProjectId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onCreateProject;

  const _ProjectPickerCard({
    required this.projects,
    required this.selectedProjectId,
    required this.onChanged,
    required this.onCreateProject,
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
            Text(
              'Where should this work live?',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Projects keep planned work, deadlines, documents, PDFs, and session handoffs together. Quick tasks can stay in the planning inbox.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            if (projects.isEmpty)
              _CreateFirstProjectButton(onCreateProject: onCreateProject)
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedProjectId,
                      decoration: const InputDecoration(
                        labelText: 'Project',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final project in projects)
                          DropdownMenuItem(
                            value: project.id,
                            child: Text(project.title, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: onChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: onCreateProject,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New project'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CreateFirstProjectButton extends StatelessWidget {
  final VoidCallback onCreateProject;

  const _CreateFirstProjectButton({required this.onCreateProject});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onCreateProject,
      icon: const Icon(Icons.dashboard_customize_rounded),
      label: const Text('Create your first project'),
    );
  }
}

class _PlanningShapeGrid extends StatelessWidget {
  final StudyProject? selectedProject;
  final bool hasAnyProject;
  final ValueChanged<PlanningIntentType> onChoose;
  final VoidCallback onCreateProject;

  const _PlanningShapeGrid({
    required this.selectedProject,
    required this.hasAnyProject,
    required this.onChoose,
    required this.onCreateProject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = _PlanningShapeCardData.values;

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose how to start',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pick the closest intent. The next screen asks only the details that matter and shows what will be created.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hasAnyProject)
                  FilledButton.tonalIcon(
                    onPressed: onCreateProject,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New project'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 720;
                final spacing = isNarrow ? 10.0 : 12.0;
                final width = isNarrow
                    ? constraints.maxWidth
                    : ((constraints.maxWidth - spacing) / 2).clamp(280.0, 460.0).toDouble();

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final card in cards)
                      SizedBox(
                        width: width,
                        child: _PlanningShapeCard(
                          data: card,
                          enabled: selectedProject != null || !hasAnyProject || card.projectOptional,
                          onTap: () => onChoose(card.intent),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanningShapeCard extends StatelessWidget {
  final _PlanningShapeCardData data;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanningShapeCard({
    required this.data,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled ? data.color(theme) : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : 0.55,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withAlpha(22),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(data.icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.examples,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanningModelNote extends StatelessWidget {
  final ThemeData theme;

  const _PlanningModelNote({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schema_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planning stays structured underneath.',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'These choices are user-facing entry points. Internally they still become progress plans, recurring work, tasks, deadlines, or checklists so Today, Calendar, debt, and future replanning can treat them consistently.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningShapeCardData {
  final PlanningIntentType intent;
  final String title;
  final String description;
  final String examples;
  final IconData icon;
  final Color Function(ThemeData theme) color;
  final bool projectOptional;

  const _PlanningShapeCardData({
    required this.intent,
    required this.title,
    required this.description,
    required this.examples,
    required this.icon,
    required this.color,
    this.projectOptional = false,
  });

  static final values = <_PlanningShapeCardData>[
    _PlanningShapeCardData(
      intent: PlanningIntentType.studyMaterial,
      title: 'Study material',
      description: 'Plan reading, chapters, exercises, or source material. Good when the work has a range or amount.',
      examples: 'Read pages 20–45 · Study chapter 4',
      icon: Icons.menu_book_rounded,
      color: (theme) => theme.colorScheme.primary,
    ),
    _PlanningShapeCardData(
      intent: PlanningIntentType.writeSomething,
      title: 'Write something',
      description: 'Plan writing work as sections, drafts, pages, or passes instead of treating it like generic tasks.',
      examples: 'Methods section · Thesis draft',
      icon: Icons.edit_note_rounded,
      color: (theme) => Colors.indigo.shade600,
    ),
    _PlanningShapeCardData(
      intent: PlanningIntentType.finishByDate,
      title: 'Finish work by a date',
      description: 'Use this when there is a measurable amount of work and a deadline. The app spreads it across study days.',
      examples: 'Problem set · Exercises 1–40',
      icon: Icons.timeline_rounded,
      color: (theme) => Colors.blueGrey.shade700,
    ),
    _PlanningShapeCardData(
      intent: PlanningIntentType.addTask,
      title: 'Add one task',
      description: 'A concrete action on a specific day. Good for submissions, emails, admin work, or one-off study tasks.',
      examples: 'Submit assignment · Email supervisor',
      icon: Icons.task_alt_rounded,
      color: (theme) => Colors.green.shade700,
      projectOptional: true,
    ),
    _PlanningShapeCardData(
      intent: PlanningIntentType.rememberDeadline,
      title: 'Remember a deadline',
      description: 'A fixed pressure point that should be visible in Today, Calendar, and project views without generating work by itself.',
      examples: 'Exam · Presentation · Canvas due date',
      icon: Icons.flag_rounded,
      color: (theme) => theme.colorScheme.error,
      projectOptional: true,
    ),
    _PlanningShapeCardData(
      intent: PlanningIntentType.reviewTopics,
      title: 'Review topics',
      description: 'Use named items instead of numbered ranges. Good for exam topics, articles, lectures, or revision lists.',
      examples: 'IS-LM · Phillips curve · Open economy',
      icon: Icons.checklist_rounded,
      color: (theme) => theme.colorScheme.tertiary,
    ),
    _PlanningShapeCardData(
      intent: PlanningIntentType.buildRoutine,
      title: 'Build a routine',
      description: 'Repeat the same amount of work on each study day until an optional end date.',
      examples: '3 cases per weekday · 20 flashcards daily',
      icon: Icons.repeat_rounded,
      color: (theme) => Colors.deepPurple.shade600,
    ),
  ];
}
