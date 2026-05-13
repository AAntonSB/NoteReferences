import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../canvas/data/canvas_import_repository.dart';
import '../../library/presentation/library_screen.dart';
import '../../notes/data/note_repository.dart';
import '../../pdf_reader/presentation/pdf_reader_screen.dart';
import '../../planning/data/study_planning_repository.dart';
import '../../planning/presentation/create_project_screen.dart';
import '../../planning/presentation/create_study_plan_screen.dart';
import '../../planning/presentation/project_planning_screen.dart';
import '../../text_system/presentation/text_system_test_env_screen.dart';

Future<void> showTodayBriefingModal({
  required BuildContext context,
  required AppDatabase database,
  StudyPlanningRepository? planningRepository,
}) {
  final size = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: size.width.clamp(720.0, 960.0).toDouble(),
          height: size.height.clamp(560.0, 820.0).toDouble(),
          child: StudyHomeScreen(
            database: database,
            planningRepository: planningRepository,
            modal: true,
          ),
        ),
      );
    },
  );
}

Future<void> showStudyCalendarModal({
  required BuildContext context,
  required NoteRepository noteRepository,
  required StudyPlanningRepository planningRepository,
  Future<void> Function(TodoItem todo)? onOpenTodo,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog.fullscreen(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: StudyCalendarOverviewScreen(
              noteRepository: noteRepository,
              planningRepository: planningRepository,
              modal: true,
              onOpenTodo: onOpenTodo,
            ),
          ),
        ),
      );
    },
  );
}

class StudyHomeScreen extends StatefulWidget {
  final AppDatabase database;
  final StudyPlanningRepository? planningRepository;
  final bool modal;

  const StudyHomeScreen({
    super.key,
    required this.database,
    this.planningRepository,
    this.modal = false,
  });

  @override
  State<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends State<StudyHomeScreen> {
  late final NoteRepository _noteRepository;
  late final StudyPlanningRepository _planningRepository;
  late final bool _ownsPlanningRepository;
  bool _planningLoaded = false;

  @override
  void initState() {
    super.initState();
    _noteRepository = NoteRepository(widget.database);
    _ownsPlanningRepository = widget.planningRepository == null;
    _planningRepository = widget.planningRepository ?? StudyPlanningRepository();
    _loadPlanning();
  }

  @override
  void dispose() {
    if (_ownsPlanningRepository) {
      _planningRepository.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPlanning() async {
    await _planningRepository.load();
    if (!mounted) return;
    setState(() => _planningLoaded = true);
  }

  Future<void> _openTextSystemTestEnv() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TextSystemTestEnvScreen(
          database: widget.database,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Today briefing'),
        centerTitle: false,
        automaticallyImplyLeading: !widget.modal,
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton.icon(
            onPressed: _openTextSystemTestEnv,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('textsys test env'),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: _planningLoaded ? _openCalendarOverview : null,
            icon: const Icon(Icons.calendar_month_rounded),
            label: const Text('Calendar'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: _planningLoaded ? _createProject : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Project'),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: _openLibrary,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Library'),
            ),
          ),
          if (widget.modal)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Close briefing',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
        ],
      ),
      body: !_planningLoaded
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _planningRepository,
              builder: (context, _) {
                return StreamBuilder<List<TodoItem>>(
                  stream: _noteRepository.watchTodos(includeCompleted: false),
                  builder: (context, todoSnapshot) {
                    final todos = todoSnapshot.data ?? const <TodoItem>[];

                    return StreamBuilder<List<PdfDocument>>(
                      stream: widget.database.watchAllDocuments(),
                      builder: (context, documentSnapshot) {
                        final documents = documentSnapshot.data ?? const <PdfDocument>[];
                        final data = _StudyHomeData.from(
                          todos: todos,
                          documents: documents,
                          planningRepository: _planningRepository,
                          now: DateTime.now(),
                        );

                        if (todoSnapshot.connectionState == ConnectionState.waiting &&
                            documentSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        return RefreshIndicator(
                          onRefresh: () async {
                            await _planningRepository.load();
                            setState(() {});
                          },
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                            children: [
                              if (!data.hasActiveProjects)
                                _NoActiveProjectsStart(
                                  onCreateProject: _createProject,
                                )
                              else ...[
                                _HeroPlanCard(
                                  data: data,
                                  onOpenCalendar: _openCalendarOverview,
                                ),
                                const SizedBox(height: 16),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final wide = constraints.maxWidth >= 980;
                                    if (!wide) {
                                      return Column(
                                        children: [
                                          _RequiredTodaySection(
                                            items: data.requiredToday,
                                            onToggleCompleted: _markRequirementCompleted,
                                            onOpenSource: _openRequirementSource,
                                          ),
                                          const SizedBox(height: 16),
                                          if (data.nextSessionItems.isNotEmpty) ...[
                                            _NextSessionSection(
                                              items: data.nextSessionItems,
                                              onToggleCompleted: _markNextSessionCompleted,
                                              onConvertToTodo: _convertNextSessionToTodo,
                                              onOpenProject: _openNextSessionProject,
                                            ),
                                            const SizedBox(height: 16),
                                          ],
                                          if (data.shouldShowDebtSection) ...[
                                            _StudyDebtSection(
                                              items: data.studyDebt,
                                              onToggleCompleted: _markDebtCompleted,
                                              onOpenSource: _openDebtSource,
                                            ),
                                            const SizedBox(height: 16),
                                          ],
                                          _ThisWeekSection(
                                            days: data.weekDays,
                                            onOpenSource: _openRequirementSource,
                                          ),
                                          const SizedBox(height: 16),
                                          _ActiveProjectsSection(
                                            projects: data.projects,
                                            onOpenProject: _openStudyProject,
                                            onAddPlan: _addPlanToProject,
                                            onCreateProject: _createProject,
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 6,
                                          child: Column(
                                            children: [
                                              _RequiredTodaySection(
                                                items: data.requiredToday,
                                                onToggleCompleted: _markRequirementCompleted,
                                                onOpenSource: _openRequirementSource,
                                              ),
                                              const SizedBox(height: 16),
                                              if (data.nextSessionItems.isNotEmpty) ...[
                                                _NextSessionSection(
                                                  items: data.nextSessionItems,
                                                  onToggleCompleted: _markNextSessionCompleted,
                                                  onConvertToTodo: _convertNextSessionToTodo,
                                                  onOpenProject: _openNextSessionProject,
                                                ),
                                                const SizedBox(height: 16),
                                              ],
                                              _ThisWeekSection(
                                                days: data.weekDays,
                                                onOpenSource: _openRequirementSource,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            children: [
                                              if (data.shouldShowDebtSection) ...[
                                                _StudyDebtSection(
                                                  items: data.studyDebt,
                                                  onToggleCompleted: _markDebtCompleted,
                                                  onOpenSource: _openDebtSource,
                                                ),
                                                const SizedBox(height: 16),
                                              ],
                                              _ActiveProjectsSection(
                                                projects: data.projects,
                                                onOpenProject: _openStudyProject,
                                                onAddPlan: _addPlanToProject,
                                                onCreateProject: _createProject,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _markRequirementCompleted(_RequirementItem item, bool completed) async {
    if (!completed) return;

    final todo = item.todo;
    if (todo != null) {
      await _noteRepository.updateTodoCompleted(todoId: todo.id, isCompleted: true);
    }

    final planRequirement = item.planRequirement;
    if (planRequirement != null) {
      await _planningRepository.completeRequirement(planRequirement);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Completed “${item.title}”.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _markDebtCompleted(_DebtItem item, bool completed) async {
    if (!completed) return;

    final todo = item.todo;
    if (todo != null) {
      await _noteRepository.updateTodoCompleted(todoId: todo.id, isCompleted: true);
    }

    final debt = item.planDebt;
    if (debt != null) {
      await _planningRepository.resolveDebt(debt);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Updated “${item.title}”.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _markNextSessionCompleted(_NextSessionItem item, bool completed) async {
    await _planningRepository.updateSessionHandoffItemDone(
      handoffId: item.handoffId,
      itemId: item.itemId,
      isDone: completed,
    );
  }

  Future<void> _convertNextSessionToTodo(_NextSessionItem item) async {
    final tomorrow = _dateOnly(DateTime.now().add(const Duration(days: 1)));
    final plan = await _planningRepository.convertHandoffItemToTodo(
      handoffId: item.handoffId,
      itemId: item.itemId,
      taskDate: tomorrow,
    );
    if (!mounted || plan == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Converted “${item.title}” to tomorrow.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openNextSessionProject(_NextSessionItem item) async {
    _openStudyProject(item.projectId);
  }

  Future<void> _openRequirementSource(_RequirementItem item) async {
    final todo = item.todo;
    if (todo != null) {
      await _openTodoSource(todo);
      return;
    }

    final projectId = item.planRequirement?.project?.id;
    if (projectId != null) {
      _openStudyProject(projectId);
    }
  }

  Future<void> _openDebtSource(_DebtItem item) async {
    final todo = item.todo;
    if (todo != null) {
      await _openTodoSource(todo);
      return;
    }

    final projectId = item.planDebt?.project.id;
    if (projectId != null) {
      _openStudyProject(projectId);
    }
  }

  Future<void> _openTodoSource(TodoItem todo) async {
    final documentId = todo.note.documentId;
    if (documentId == null || documentId.trim().isEmpty) {
      _showMessage('This item is not linked to a PDF yet.');
      return;
    }

    final documents = await widget.database.getAllDocuments();
    PdfDocument? document;
    for (final candidate in documents) {
      if (candidate.documentId == documentId) {
        document = candidate;
        break;
      }
    }

    if (!mounted) return;

    if (document == null) {
      _showMessage('Could not find the linked document.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfReaderScreen(
          database: widget.database,
          documentId: document!.documentId,
          filePath: document!.filePath,
          title: document!.name,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  void _openStudyProject(String projectId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectPlanningScreen(
          planningRepository: _planningRepository,
          projectId: projectId,
        ),
      ),
    );
  }

  Future<void> _addPlanToProject(String projectId) async {
    final project = _planningRepository.projectById(projectId);
    if (project == null) return;

    await Navigator.of(context).push<StudyPlan>(
      MaterialPageRoute(
        builder: (_) => CreateStudyPlanScreen(
          planningRepository: _planningRepository,
          project: project,
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(
          planningRepository: _planningRepository,
          openPlanAfterCreate: true,
        ),
      ),
    );
  }

  void _openLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          database: widget.database,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _openCalendarOverview() async {
    await showStudyCalendarModal(
      context: context,
      noteRepository: _noteRepository,
      planningRepository: _planningRepository,
      onOpenTodo: _openTodoSource,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class StudyCalendarOverviewScreen extends StatefulWidget {
  final NoteRepository noteRepository;
  final StudyPlanningRepository planningRepository;
  final bool modal;
  final Future<void> Function(TodoItem todo)? onOpenTodo;
  const StudyCalendarOverviewScreen({
    super.key,
    required this.noteRepository,
    required this.planningRepository,
    this.modal = false,
    this.onOpenTodo,
  });

  @override
  State<StudyCalendarOverviewScreen> createState() => _StudyCalendarOverviewScreenState();
}

class _StudyCalendarOverviewScreenState extends State<StudyCalendarOverviewScreen> {
  late DateTime _visibleMonth;
  late final CanvasImportRepository _canvasRepository;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _canvasRepository = CanvasImportRepository();
    _loadCanvas();
  }

  @override
  void dispose() {
    _canvasRepository.dispose();
    super.dispose();
  }

  Future<void> _loadCanvas() async {
    await _canvasRepository.load();
    if (mounted) setState(() {});
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() => _visibleMonth = DateTime(now.year, now.month));
  }

  void _showPreviousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
  }

  void _showNextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
  }

  Future<void> _openCanvasImport() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CanvasImportSheet(repository: _canvasRepository),
    );
  }

  Future<void> _openCalendarItem(_CalendarItem item) async {
    final todo = item.todo;
    if (todo != null) {
      final opener = widget.onOpenTodo;
      if (opener != null) {
        if (widget.modal && mounted) {
          Navigator.of(context).maybePop();
        }
        await opener(todo);
        return;
      }
      if (!mounted) return;
      final linkedDocumentId = todo.note.documentId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            linkedDocumentId == null || linkedDocumentId.trim().isEmpty
                ? 'This todo is not linked to a PDF.'
                : 'This todo is linked to a PDF, but no document opener was provided here.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final requirement = item.planRequirement;
    if (requirement != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${requirement.projectTitle}: ${requirement.rangeLabel}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Calendar'),
        automaticallyImplyLeading: !widget.modal,
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton.icon(
            onPressed: _jumpToToday,
            icon: const Icon(Icons.today_rounded),
            label: const Text('Today'),
          ),
          TextButton.icon(
            onPressed: _openCanvasImport,
            icon: const Icon(Icons.cloud_sync_rounded),
            label: const Text('Canvas'),
          ),
          IconButton(
            tooltip: 'Previous month',
            onPressed: _showPreviousMonth,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Center(
            child: Text(
              '${_monthName(_visibleMonth.month)} ${_visibleMonth.year}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: _showNextMonth,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          if (widget.modal)
            IconButton(
              tooltip: 'Close calendar',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([widget.planningRepository, _canvasRepository]),
        builder: (context, _) {
          return StreamBuilder<List<TodoItem>>(
            stream: widget.noteRepository.watchTodos(includeCompleted: false),
            builder: (context, snapshot) {
              final todos = snapshot.data ?? const <TodoItem>[];
              final today = _dateOnly(DateTime.now());
              final displayMonths = [
                for (var offset = 0; offset < 18; offset++)
                  DateTime(_visibleMonth.year, _visibleMonth.month + offset),
              ];
              final rangeStart = DateTime(displayMonths.first.year, displayMonths.first.month);
              final rangeEnd = DateTime(displayMonths.last.year, displayMonths.last.month + 1, 0);
              final visibleMonthStart = DateTime(_visibleMonth.year, _visibleMonth.month);
              final visibleMonthEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
              final visibleMonthRequirements = widget.planningRepository.requirementsForRange(
                rangeStart: visibleMonthStart,
                rangeEnd: visibleMonthEnd,
                now: DateTime.now(),
              );
              final allRequirements = widget.planningRepository.requirementsForRange(
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                now: DateTime.now(),
              );
              final visibleCanvasEvents = _canvasRepository.events.where((event) {
                final date = _dateOnly(event.startAt);
                return !date.isBefore(visibleMonthStart) && !date.isAfter(visibleMonthEnd);
              }).toList(growable: false);
              final rangeCanvasEvents = _canvasRepository.events.where((event) {
                final date = _dateOnly(event.startAt);
                return !date.isBefore(rangeStart) && !date.isAfter(rangeEnd);
              }).toList(growable: false);
              final debts = widget.planningRepository.studyDebts(DateTime.now());
              final calendarIndex = _CalendarIndex.fromSources(
                todos: todos,
                planRequirements: allRequirements,
                canvasEvents: rangeCanvasEvents,
              );
              final deadlineDates = _deadlineDatesForCalendar(
                planningRepository: widget.planningRepository,
                todos: todos,
                canvasEvents: rangeCanvasEvents,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
              );
              final weekStyles = _weekStylesForMonths(
                months: displayMonths,
                deadlineDates: deadlineDates,
              );

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _CalendarOverviewLegend(
                        todos: todos,
                        planRequirements: visibleMonthRequirements,
                        debts: debts,
                        visibleMonth: _visibleMonth,
                        canvasEvents: visibleCanvasEvents,
                        canvasConfigured: _canvasRepository.isConfigured,
                        lastCanvasSync: _canvasRepository.lastSyncedAt,
                        onOpenCanvasImport: _openCanvasImport,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _SoftCard(
                        child: Row(
                          children: [
                            _IconBubble(icon: Icons.palette_rounded, color: theme.colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Each week now has its own tint. Weeks intensify as deadlines approach, and deadline weeks become the most visually urgent.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    sliver: SliverList.builder(
                      itemCount: displayMonths.length + 1,
                      itemBuilder: (context, index) {
                        if (index == displayMonths.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _SoftCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _IconBubble(icon: Icons.route_rounded, color: theme.colorScheme.primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Overview, not time blocking',
                                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'This calendar shows exact requirements: generated study plans, repeating daily work, single tasks, deadlines, checklist items, todos, Canvas events, and visible debt. It does not need to guess how long studying will take.',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final month = displayMonths[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _CalendarMonthBlock(
                            month: month,
                            today: today,
                            calendarIndex: calendarIndex,
                            weekStyles: weekStyles,
                            onOpenItem: _openCalendarItem,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CanvasImportSheet extends StatefulWidget {
  final CanvasImportRepository repository;

  const _CanvasImportSheet({required this.repository});

  @override
  State<_CanvasImportSheet> createState() => _CanvasImportSheetState();
}

class _CanvasImportSheetState extends State<_CanvasImportSheet> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  late bool _includeAssignments;
  bool _isSyncing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final settings = widget.repository.settings;
    _baseUrlController = TextEditingController(text: settings.baseUrl);
    _tokenController = TextEditingController(text: settings.accessToken);
    _includeAssignments = settings.includeUpcomingAssignments;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveAndSync() async {
    setState(() {
      _isSyncing = true;
      _message = null;
    });

    try {
      final settings = CanvasImportSettings(
        baseUrl: _baseUrlController.text,
        accessToken: _tokenController.text,
        includeUpcomingAssignments: _includeAssignments,
      );
      await widget.repository.saveSettings(settings);
      final now = DateTime.now();
      final count = await widget.repository.syncCalendarEvents(
        rangeStart: now.subtract(const Duration(days: 14)),
        rangeEnd: DateTime(now.year, now.month + 7, now.day),
      );
      if (!mounted) return;
      setState(() => _message = 'Synced $count Canvas items into the calendar.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _clear() async {
    await widget.repository.clear();
    if (!mounted) return;
    _baseUrlController.clear();
    _tokenController.clear();
    setState(() {
      _includeAssignments = true;
      _message = 'Canvas settings and imported events cleared.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import from Canvas',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Add your Canvas base URL and an access token. The app imports Canvas calendar events for lectures and optionally upcoming assignment deadlines.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Canvas URL',
                  hintText: 'https://your-school.instructure.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: 'Access token',
                  hintText: 'Canvas API token',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include upcoming assignments as deadlines'),
                value: _includeAssignments,
                onChanged: (value) => setState(() => _includeAssignments = value),
              ),
              if (widget.repository.lastSyncedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Last sync: ${_shortDate(widget.repository.lastSyncedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _message!.startsWith('Synced') || _message!.startsWith('Canvas settings')
                        ? Colors.green.shade700
                        : theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSyncing ? null : _saveAndSync,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(_isSyncing ? 'Syncing…' : 'Save and sync'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _isSyncing ? null : _clear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BriefingIdentity {
  final Color leading;
  final Color trailing;
  final Color accent;
  final Color onColor;
  final IconData icon;

  const _BriefingIdentity({
    required this.leading,
    required this.trailing,
    required this.accent,
    required this.onColor,
    required this.icon,
  });

  factory _BriefingIdentity.fromData(ThemeData theme, _StudyHomeData data) {
    if (data.studyDebt.isNotEmpty) {
      return _BriefingIdentity(
        leading: theme.colorScheme.errorContainer,
        trailing: theme.colorScheme.tertiaryContainer,
        accent: theme.colorScheme.error,
        onColor: theme.colorScheme.onErrorContainer,
        icon: Icons.error_outline_rounded,
      );
    }

    if (data.requiredToday.isEmpty) {
      final cleanTint = Color.alphaBlend(Colors.green.withAlpha(42), theme.colorScheme.primaryContainer);
      return _BriefingIdentity(
        leading: cleanTint,
        trailing: theme.colorScheme.surfaceContainerHighest,
        accent: Colors.green.shade700,
        onColor: theme.colorScheme.onPrimaryContainer,
        icon: Icons.check_circle_outline_rounded,
      );
    }

    return _BriefingIdentity(
      leading: theme.colorScheme.primaryContainer,
      trailing: theme.colorScheme.secondaryContainer,
      accent: theme.colorScheme.primary,
      onColor: theme.colorScheme.onPrimaryContainer,
      icon: Icons.today_rounded,
    );
  }
}

class _NoActiveProjectsStart extends StatelessWidget {
  final VoidCallback onCreateProject;

  const _NoActiveProjectsStart({required this.onCreateProject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconBubble(icon: Icons.dashboard_customize_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No active projects yet',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Create a project first. Then add plans that generate today’s concrete work.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCreateProject,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('You have no active projects yet, create one here.'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _HomeSection(
          title: 'Today’s work',
          icon: Icons.checklist_rounded,
          trailing: const _CountBadge(count: 0),
          child: const _EmptyState(
            icon: Icons.inbox_rounded,
            title: 'None yet, no active plan.',
            message: 'Create a project and add a plan to start generating daily requirements.',
          ),
        ),
      ],
    );
  }
}

class _HeroPlanCard extends StatelessWidget {
  final _StudyHomeData data;
  final VoidCallback onOpenCalendar;

  const _HeroPlanCard({required this.data, required this.onOpenCalendar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = _BriefingIdentity.fromData(theme, data);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [identity.leading, identity.trailing],
        ),
        boxShadow: [
          BoxShadow(
            color: identity.accent.withAlpha(22),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(170),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: identity.accent.withAlpha(70)),
              ),
              child: Icon(identity.icon, color: identity.accent, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _formatLongDate(data.today),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: identity.onColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequiredTodaySection extends StatelessWidget {
  final List<_RequirementItem> items;
  final _RequirementToggleCallback onToggleCompleted;
  final _RequirementOpenCallback onOpenSource;

  const _RequiredTodaySection({
    required this.items,
    required this.onToggleCompleted,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    return _HomeSection(
      title: 'Today’s work',
      icon: Icons.checklist_rounded,
      trailing: _CountBadge(count: items.length),
      child: items.isEmpty
          ? const _EmptyState(
              icon: Icons.done_all_rounded,
              title: 'Nothing planned for today',
              message: 'When project plans or todos land on today, they will appear here.',
            )
          : Column(
              children: [
                for (final item in items)
                  _RequirementChecklistTile(
                    item: item,
                    tone: _TileTone.today,
                    onToggleCompleted: onToggleCompleted,
                    onOpenSource: onOpenSource,
                  ),
              ],
            ),
    );
  }
}

class _NextSessionSection extends StatelessWidget {
  final List<_NextSessionItem> items;
  final _NextSessionToggleCallback onToggleCompleted;
  final _NextSessionActionCallback onConvertToTodo;
  final _NextSessionActionCallback onOpenProject;

  const _NextSessionSection({
    required this.items,
    required this.onToggleCompleted,
    required this.onConvertToTodo,
    required this.onOpenProject,
  });

  @override
  Widget build(BuildContext context) {
    return _HomeSection(
      title: 'Next session',
      icon: Icons.next_plan_rounded,
      trailing: _CountBadge(count: items.length),
      child: Column(
        children: [
          for (final item in items)
            _NextSessionTile(
              item: item,
              onToggleCompleted: onToggleCompleted,
              onConvertToTodo: onConvertToTodo,
              onOpenProject: onOpenProject,
            ),
        ],
      ),
    );
  }
}

class _NextSessionTile extends StatelessWidget {
  final _NextSessionItem item;
  final _NextSessionToggleCallback onToggleCompleted;
  final _NextSessionActionCallback onConvertToTodo;
  final _NextSessionActionCallback onOpenProject;

  const _NextSessionTile({
    required this.item,
    required this.onToggleCompleted,
    required this.onConvertToTodo,
    required this.onOpenProject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.tertiaryContainer.withAlpha(55),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => onOpenProject(item),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 6, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: false,
                  onChanged: (value) => onToggleCompleted(item, value ?? true),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      _InlineMeta(icon: Icons.dashboard_customize_rounded, label: item.projectLabel),
                    ],
                  ),
                ),
                PopupMenuButton<_NextSessionMenuAction>(
                  tooltip: 'Next-session actions',
                  onSelected: (action) {
                    switch (action) {
                      case _NextSessionMenuAction.convertToTodo:
                        onConvertToTodo(item);
                        break;
                      case _NextSessionMenuAction.openProject:
                        onOpenProject(item);
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _NextSessionMenuAction.convertToTodo,
                      child: ListTile(
                        leading: Icon(Icons.task_alt_rounded),
                        title: Text('Convert to task for tomorrow'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _NextSessionMenuAction.openProject,
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
        ),
      ),
    );
  }
}

enum _NextSessionMenuAction { convertToTodo, openProject }

class _StudyDebtSection extends StatelessWidget {
  final List<_DebtItem> items;
  final _DebtToggleCallback onToggleCompleted;
  final _DebtOpenCallback onOpenSource;

  const _StudyDebtSection({
    required this.items,
    required this.onToggleCompleted,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    return _HomeSection(
      title: 'Behind schedule',
      icon: Icons.error_outline_rounded,
      trailing: _CountBadge(count: items.length, isWarning: items.isNotEmpty),
      child: items.isEmpty
          ? const _EmptyState(
              icon: Icons.done_all_rounded,
              title: 'Nothing behind schedule',
              message: 'Clean start today.',
            )
          : Column(
              children: [
                for (final item in items)
                  _DebtChecklistTile(
                    item: item,
                    onToggleCompleted: onToggleCompleted,
                    onOpenSource: onOpenSource,
                  ),
              ],
            ),
    );
  }
}

class _ThisWeekSection extends StatelessWidget {
  final List<_WeekDayPlan> days;
  final _RequirementOpenCallback onOpenSource;

  const _ThisWeekSection({required this.days, required this.onOpenSource});

  @override
  Widget build(BuildContext context) {
    return _HomeSection(
      title: 'This week',
      icon: Icons.view_week_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useGrid = constraints.maxWidth >= 720;
          final children = [
            for (final day in days) _WeekDayCard(day: day, onOpenSource: onOpenSource),
          ];

          if (!useGrid) {
            return Column(
              children: [
                for (final child in children) ...[
                  child,
                  if (child != children.last) const SizedBox(height: 10),
                ],
              ],
            );
          }

          return GridView.count(
            crossAxisCount: 7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.78,
            children: children,
          );
        },
      ),
    );
  }
}

class _ActiveProjectsSection extends StatelessWidget {
  final List<_ProjectStatus> projects;
  final ValueChanged<String> onOpenProject;
  final ValueChanged<String> onAddPlan;
  final VoidCallback onCreateProject;

  const _ActiveProjectsSection({
    required this.projects,
    required this.onOpenProject,
    required this.onAddPlan,
    required this.onCreateProject,
  });

  @override
  Widget build(BuildContext context) {
    return _HomeSection(
      title: 'Active projects',
      icon: Icons.dashboard_customize_rounded,
      child: projects.isEmpty
          ? _CreateProjectCard(onTap: onCreateProject)
          : Column(
              children: [
                for (final project in projects) ...[
                  _ProjectCard(
                    project: project,
                    onTap: () => onOpenProject(project.id),
                    onAddPlan: () => onAddPlan(project.id),
                  ),
                  const SizedBox(height: 10),
                ],
                _CreateProjectCard(onTap: onCreateProject),
              ],
            ),
    );
  }
}

class _WeekDayCard extends StatelessWidget {
  final _WeekDayPlan day;
  final _RequirementOpenCallback onOpenSource;

  const _WeekDayCard({required this.day, required this.onOpenSource});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDebt = day.debtCount > 0;
    final hasItems = day.items.isNotEmpty;
    final borderColor = day.isToday
        ? theme.colorScheme.primary
        : hasDebt
            ? theme.colorScheme.error.withAlpha(130)
            : theme.colorScheme.outlineVariant;
    final background = day.isToday
        ? theme.colorScheme.primaryContainer.withAlpha(110)
        : hasDebt
            ? theme.colorScheme.errorContainer.withAlpha(90)
            : theme.colorScheme.surface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(10),
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
                      _weekdayShort(day.date),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${day.date.day}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              if (hasItems) _TinyCountBadge(label: '${day.items.length}', isWarning: hasDebt),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasItems)
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'Open',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: day.items.length > 4 ? 4 : day.items.length,
                itemBuilder: (context, index) {
                  final item = day.items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onOpenSource(item),
                      child: Text(
                        item.compactLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (day.items.length > 4)
            Text(
              '+${day.items.length - 4} more',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _RequirementChecklistTile extends StatelessWidget {
  final _RequirementItem item;
  final _TileTone tone;
  final _RequirementToggleCallback onToggleCompleted;
  final _RequirementOpenCallback onOpenSource;

  const _RequirementChecklistTile({
    required this.item,
    required this.tone,
    required this.onToggleCompleted,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDebt = tone == _TileTone.debt;
    final color = isDebt ? theme.colorScheme.error : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withAlpha(isDebt ? 18 : 12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => onOpenSource(item),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: false,
                  onChanged: (value) => onToggleCompleted(item, value ?? true),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          _DueChip(deadline: item.date, isDebt: isDebt),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _InlineMeta(icon: item.icon, label: item.projectLabel),
                          _InlineMeta(icon: Icons.route_rounded, label: item.detailLabel),
                        ],
                      ),
                      if (item.body != null && item.body!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.body!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_new_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebtChecklistTile extends StatelessWidget {
  final _DebtItem item;
  final _DebtToggleCallback onToggleCompleted;
  final _DebtOpenCallback onOpenSource;

  const _DebtChecklistTile({
    required this.item,
    required this.onToggleCompleted,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final requirement = _RequirementItem.fromDebt(item);
    return _RequirementChecklistTile(
      item: requirement,
      tone: _TileTone.debt,
      onToggleCompleted: (ignored, completed) => onToggleCompleted(item, completed),
      onOpenSource: (ignored) => onOpenSource(item),
    );
  }
}

class _CreateProjectCard extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateProjectCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.primaryContainer.withAlpha(80),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.primary.withAlpha(100)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Create a new project',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final _ProjectStatus project;
  final VoidCallback onTap;
  final VoidCallback onAddPlan;

  const _ProjectCard({required this.project, required this.onTap, required this.onAddPlan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = project.debtCount > 0
        ? theme.colorScheme.error
        : project.requiredTodayCount > 0
            ? theme.colorScheme.primary
            : Colors.green.shade700;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              _IconBubble(icon: Icons.dashboard_customize_rounded, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      project.statusLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onAddPlan,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Item'),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarOverviewLegend extends StatelessWidget {
  final List<TodoItem> todos;
  final List<StudyPlanRequirement> planRequirements;
  final List<StudyPlanDebt> debts;
  final List<CanvasCalendarEvent> canvasEvents;
  final DateTime visibleMonth;
  final bool canvasConfigured;
  final DateTime? lastCanvasSync;
  final VoidCallback onOpenCanvasImport;

  const _CalendarOverviewLegend({
    required this.todos,
    required this.planRequirements,
    required this.debts,
    required this.canvasEvents,
    required this.visibleMonth,
    required this.canvasConfigured,
    required this.lastCanvasSync,
    required this.onOpenCanvasImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthTodos = todos.where((todo) {
      final deadline = todo.deadline;
      if (deadline == null) return false;
      return deadline.year == visibleMonth.year && deadline.month == visibleMonth.month;
    }).toList();

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetricPill(
                icon: Icons.assignment_turned_in_rounded,
                label: '${planRequirements.length + monthTodos.length + canvasEvents.length} requirements this month',
              ),
              _MetricPill(
                icon: Icons.school_rounded,
                label: '${canvasEvents.length} Canvas items',
                foreground: canvasConfigured ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              _MetricPill(
                icon: Icons.warning_amber_rounded,
                label: '${debts.length} debt signals',
                foreground: debts.isEmpty ? Colors.green.shade700 : theme.colorScheme.error,
              ),
              const _MetricPill(icon: Icons.palette_rounded, label: 'Week-tinted days'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  canvasConfigured
                      ? 'Canvas import is configured${lastCanvasSync == null ? '' : ' · last sync ${_shortDate(lastCanvasSync!)}'}.'
                      : 'Canvas import is optional. Connect it to show lectures and Canvas deadlines here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenCanvasImport,
                icon: const Icon(Icons.cloud_sync_rounded),
                label: Text(canvasConfigured ? 'Sync Canvas' : 'Connect Canvas'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarMonthBlock extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final _CalendarIndex calendarIndex;
  final Map<String, _WeekStyle> weekStyles;
  final Future<void> Function(_CalendarItem item) onOpenItem;

  const _CalendarMonthBlock({
    required this.month,
    required this.today,
    required this.calendarIndex,
    required this.weekStyles,
    required this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _calendarDaysForMonth(month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '${_monthName(month.month)} ${month.year}',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.12,
          ),
          itemBuilder: (context, index) {
            final day = days[index];
            final items = calendarIndex.itemsFor(day);
            final isInVisibleMonth = day.month == month.month;
            final isToday = _sameDate(day, today);
            final debtCount = items.where((item) => item.isDebt).length;
            final weekStart = _startOfWeek(day);
            final weekStyle = weekStyles[_dateKey(weekStart)] ?? _WeekStyle(themeIndex: 0, deadlinePressure: 0);

            return _CalendarDayCell(
              day: day,
              items: items,
              isToday: isToday,
              isMuted: !isInVisibleMonth,
              debtCount: debtCount,
              weekStyle: weekStyle,
              onOpenItem: onOpenItem,
            );
          },
        ),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime day;
  final List<_CalendarItem> items;
  final bool isToday;
  final bool isMuted;
  final int debtCount;
  final _WeekStyle weekStyle;
  final Future<void> Function(_CalendarItem item) onOpenItem;

  const _CalendarDayCell({
    required this.day,
    required this.items,
    required this.isToday,
    required this.isMuted,
    required this.debtCount,
    required this.weekStyle,
    required this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWork = items.isNotEmpty;
    final hasDeadline = items.any((item) => item.isDeadline);
    final color = debtCount > 0
        ? theme.colorScheme.error
        : hasDeadline || weekStyle.deadlinePressure >= 3
            ? theme.colorScheme.error
            : hasWork
                ? theme.colorScheme.primary
                : _weekTint(theme, weekStyle.themeIndex);
    final background = _calendarDayBackground(
      theme: theme,
      weekStyle: weekStyle,
      hasWork: hasWork,
      hasDebt: debtCount > 0,
      hasDeadline: hasDeadline,
      isMuted: isMuted,
    );

    return Tooltip(
      message: items.isEmpty ? 'No requirements' : items.map((item) => item.label).join('\n'),
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isToday ? theme.colorScheme.primary : color.withAlpha(115),
            width: isToday ? 2 : 1,
          ),
          boxShadow: weekStyle.deadlinePressure >= 3 && !isMuted
              ? [
                  BoxShadow(
                    color: theme.colorScheme.error.withAlpha(22),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 5,
                color: color.withAlpha(weekStyle.deadlinePressure > 0 ? 175 : 110),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${day.day}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: isMuted ? theme.colorScheme.onSurfaceVariant.withAlpha(150) : theme.colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      if (weekStyle.deadlinePressure > 0)
                        Icon(
                          Icons.flag_rounded,
                          size: 14,
                          color: color.withAlpha(isMuted ? 120 : 210),
                        ),
                      if (items.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _TinyCountBadge(label: '${items.length}', isWarning: debtCount > 0 || hasDeadline),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final item in items.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Tooltip(
                        message: _calendarItemTooltip(item),
                        waitDuration: const Duration(milliseconds: 350),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onOpenItem(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.isDocumentLinked
                                  ? theme.colorScheme.primary.withAlpha(isMuted ? 14 : 24)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: item.isDocumentLinked
                                  ? Border.all(color: theme.colorScheme.primary.withAlpha(isMuted ? 45 : 90))
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item.isDocumentLinked) ...[
                                  Icon(
                                    Icons.picture_as_pdf_rounded,
                                    size: 11,
                                    color: theme.colorScheme.primary.withAlpha(isMuted ? 130 : 220),
                                  ),
                                  const SizedBox(width: 3),
                                ],
                                Flexible(
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: item.isDocumentLinked ? FontWeight.w900 : FontWeight.w700,
                                      color: isMuted
                                          ? theme.colorScheme.onSurfaceVariant.withAlpha(150)
                                          : item.isDocumentLinked
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (items.length > 3)
                    Text(
                      '+${items.length - 3}',
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _HomeSection({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBubble(icon: icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  final Widget child;

  const _SoftCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withAlpha(10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _EmptyState({required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? foreground;

  const _MetricPill({required this.icon, required this.label, this.foreground});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = foreground ?? theme.colorScheme.onSurface;

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
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final bool isWarning;

  const _CountBadge({required this.count, this.isWarning = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isWarning ? theme.colorScheme.error : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TinyCountBadge extends StatelessWidget {
  final String label;
  final bool isWarning;

  const _TinyCountBadge({required this.label, this.isWarning = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isWarning ? theme.colorScheme.error : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBubble({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: color.withAlpha(22), borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _DueChip extends StatelessWidget {
  final DateTime deadline;
  final bool isDebt;

  const _DueChip({required this.deadline, required this.isDebt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDebt ? theme.colorScheme.error : theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(18), borderRadius: BorderRadius.circular(999)),
      child: Text(
        _shortDate(deadline),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InlineMeta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _StudyHomeData {
  final DateTime today;
  final List<_RequirementItem> requiredToday;
  final List<_DebtItem> studyDebt;
  final List<_NextSessionItem> nextSessionItems;
  final List<_WeekDayPlan> weekDays;
  final List<_ProjectStatus> projects;
  final int thisWeekCount;
  final bool hasActiveProjects;

  const _StudyHomeData({
    required this.today,
    required this.requiredToday,
    required this.studyDebt,
    required this.nextSessionItems,
    required this.weekDays,
    required this.projects,
    required this.thisWeekCount,
    required this.hasActiveProjects,
  });

  bool get shouldShowDebtSection => studyDebt.isNotEmpty || (requiredToday.isEmpty && nextSessionItems.isEmpty);

  factory _StudyHomeData.from({
    required List<TodoItem> todos,
    required List<PdfDocument> documents,
    required StudyPlanningRepository planningRepository,
    required DateTime now,
  }) {
    final today = _dateOnly(now);
    final weekDates = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    final weekEnd = weekDates.last;
    final activeTodos = todos.where((todo) => !todo.isCompleted).toList();

    final planRequirements = planningRepository.requirementsForRange(
      rangeStart: today,
      rangeEnd: weekEnd,
      now: now,
    );
    final planDebts = planningRepository.studyDebts(now);
    final nextSessionItems = <_NextSessionItem>[
      for (final entry in planningRepository.activeHandoffEntries())
        _NextSessionItem.fromEntry(entry),
    ];

    final requiredToday = <_RequirementItem>[
      for (final requirement in planRequirements.where((item) => _sameDate(item.date, today)))
        _RequirementItem.fromPlanRequirement(requirement),
      for (final todo in activeTodos.where((todo) => todo.deadline != null && _sameDate(todo.deadline!, today)))
        _RequirementItem.fromTodo(todo),
    ]..sort((a, b) => a.sortLabel.compareTo(b.sortLabel));

    final studyDebt = <_DebtItem>[
      for (final debt in planDebts) _DebtItem.fromPlanDebt(debt),
      for (final todo in activeTodos.where((todo) {
        final deadline = todo.deadline;
        return deadline != null && _dateOnly(deadline).isBefore(today);
      }))
        _DebtItem.fromTodo(todo),
    ]..sort((a, b) => a.sortLabel.compareTo(b.sortLabel));

    final weekDays = [
      for (final date in weekDates)
        _WeekDayPlan(
          date: date,
          isToday: _sameDate(date, today),
          items: <_RequirementItem>[
            for (final requirement in planRequirements.where((item) => _sameDate(item.date, date)))
              _RequirementItem.fromPlanRequirement(requirement),
            for (final todo in activeTodos.where((todo) => todo.deadline != null && _sameDate(todo.deadline!, date)))
              _RequirementItem.fromTodo(todo),
          ]..sort((a, b) => a.sortLabel.compareTo(b.sortLabel)),
          debtCount: _sameDate(date, today) ? studyDebt.length : 0,
        ),
    ];

    final projects = _ProjectStatus.fromPlanning(
      planningRepository: planningRepository,
      requiredToday: requiredToday,
      debts: studyDebt,
    );

    final thisWeekCount = weekDays.fold<int>(0, (sum, day) => sum + day.items.length);

    return _StudyHomeData(
      today: today,
      requiredToday: requiredToday,
      studyDebt: studyDebt,
      nextSessionItems: nextSessionItems,
      weekDays: weekDays,
      projects: projects,
      thisWeekCount: thisWeekCount,
      hasActiveProjects: planningRepository.projects.isNotEmpty,
    );
  }
}

class _NextSessionItem {
  final String handoffId;
  final String itemId;
  final String projectId;
  final String projectLabel;
  final String title;

  const _NextSessionItem({
    required this.handoffId,
    required this.itemId,
    required this.projectId,
    required this.projectLabel,
    required this.title,
  });

  factory _NextSessionItem.fromEntry(SessionHandoffEntry entry) {
    return _NextSessionItem(
      handoffId: entry.handoff.id,
      itemId: entry.item.id,
      projectId: entry.project.id,
      projectLabel: entry.project.title,
      title: entry.item.text,
    );
  }
}

class _RequirementItem {
  final String id;
  final String title;
  final String projectLabel;
  final String detailLabel;
  final String? body;
  final DateTime date;
  final IconData icon;
  final TodoItem? todo;
  final StudyPlanRequirement? planRequirement;

  const _RequirementItem({
    required this.id,
    required this.title,
    required this.projectLabel,
    required this.detailLabel,
    required this.body,
    required this.date,
    required this.icon,
    required this.todo,
    required this.planRequirement,
  });

  String get compactLabel => '$projectLabel: $title';
  String get sortLabel => '$projectLabel $title'.toLowerCase();

  factory _RequirementItem.fromPlanRequirement(StudyPlanRequirement requirement) {
    return _RequirementItem(
      id: 'plan-${requirement.plan.id}-${_shortDate(requirement.date)}',
      title: _titleForPlanRequirement(requirement),
      projectLabel: requirement.projectTitle,
      detailLabel: _detailForPlanRequirement(requirement),
      body: _bodyForPlanRequirement(requirement),
      date: requirement.date,
      icon: _iconForPlanRequirement(requirement),
      todo: null,
      planRequirement: requirement,
    );
  }

  factory _RequirementItem.fromTodo(TodoItem todo) {
    return _RequirementItem(
      id: 'todo-${todo.id}',
      title: todo.title,
      projectLabel: todo.pdfLabel,
      detailLabel: _priorityLabel(todo.priority),
      body: todo.body,
      date: todo.deadline ?? DateTime.now(),
      icon: Icons.task_alt_rounded,
      todo: todo,
      planRequirement: null,
    );
  }

  factory _RequirementItem.fromDebt(_DebtItem debt) {
    final todo = debt.todo;
    if (todo != null) return _RequirementItem.fromTodo(todo);

    final planDebt = debt.planDebt!;
    return _RequirementItem(
      id: 'debt-${planDebt.plan.id}',
      title: debt.title,
      projectLabel: debt.projectLabel,
      detailLabel: debt.detailLabel,
      body: debt.body,
      date: DateTime.now(),
      icon: Icons.account_balance_wallet_rounded,
      todo: null,
      planRequirement: null,
    );
  }
}

IconData _iconForPlanRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) return Icons.flag_rounded;
  if (requirement.plan.isSingleTask) return Icons.task_alt_rounded;
  if (requirement.plan.isChecklist) return Icons.fact_check_rounded;
  if (requirement.plan.isRecurring) return Icons.repeat_rounded;
  return Icons.route_rounded;
}

String _titleForPlanRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) return requirement.plan.title;
  if (requirement.plan.isSingleTask) return requirement.plan.title;
  if (requirement.plan.isChecklist) return '${requirement.plan.title} · ${requirement.rangeLabel}';
  return '${requirement.plan.title} · ${requirement.rangeLabel}';
}

String _detailForPlanRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) return 'Deadline';
  if (requirement.plan.isSingleTask) return 'Single task';
  if (requirement.plan.isChecklist) return 'Checklist item';
  return '${requirement.unitCount} ${requirement.plan.unitNounForCount(requirement.unitCount)}';
}

String _bodyForPlanRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) {
    return 'Deadline marker. It appears on the calendar as a fixed pressure point.';
  }
  if (requirement.plan.isSingleTask) {
    return 'Single task. If missed, it becomes unresolved study debt.';
  }
  if (requirement.plan.isChecklist) {
    return 'Checklist item. If missed, it stays visible as study debt.';
  }
  if (requirement.plan.isRecurring) {
    return 'Recurring plan. If missed, it becomes visible study debt.';
  }
  return 'Generated from plan. If missed, the remaining pace is recalculated.';
}

class _DebtItem {
  final String id;
  final String title;
  final String projectLabel;
  final String detailLabel;
  final String? body;
  final String sortLabel;
  final TodoItem? todo;
  final StudyPlanDebt? planDebt;

  const _DebtItem({
    required this.id,
    required this.title,
    required this.projectLabel,
    required this.detailLabel,
    required this.body,
    required this.sortLabel,
    required this.todo,
    required this.planDebt,
  });

  factory _DebtItem.fromPlanDebt(StudyPlanDebt debt) {
    final unitNoun = debt.plan.unitNounForCount(debt.behindUnits);
    if (debt.plan.isRecurring) {
      final dayNoun = debt.missedDays == 1 ? 'day' : 'days';
      return _DebtItem(
        id: 'plan-debt-${debt.plan.id}',
        title: '${debt.plan.title} · ${debt.missedDays} missed $dayNoun',
        projectLabel: debt.project.title,
        detailLabel: '${debt.behindUnits} $unitNoun unresolved',
        body: 'Recurring plan debt. Checking this off resolves the missed study days that have accumulated so far.',
        sortLabel: '${debt.project.title} ${debt.plan.title}'.toLowerCase(),
        todo: null,
        planDebt: debt,
      );
    }

    if (debt.plan.isSingleTask) {
      return _DebtItem(
        id: 'plan-debt-${debt.plan.id}',
        title: debt.plan.title,
        projectLabel: debt.project.title,
        detailLabel: 'Unresolved single task',
        body: 'This task was planned for an earlier day. Checking it off marks it done.',
        sortLabel: '${debt.project.title} ${debt.plan.title}'.toLowerCase(),
        todo: null,
        planDebt: debt,
      );
    }

    if (debt.plan.isChecklist) {
      final itemNoun = debt.behindUnits == 1 ? 'item' : 'items';
      final firstItem = debt.checklistIndexes.isNotEmpty &&
              debt.checklistIndexes.first >= 0 &&
              debt.checklistIndexes.first < debt.plan.checklistItems.length
          ? debt.plan.checklistItems[debt.checklistIndexes.first]
          : null;
      return _DebtItem(
        id: 'plan-debt-${debt.plan.id}',
        title: '${debt.plan.title} · ${debt.behindUnits} missed $itemNoun',
        projectLabel: debt.project.title,
        detailLabel: firstItem == null ? 'Checklist debt' : 'Includes “$firstItem”',
        body: 'Checklist debt. Checking this off resolves the missed named items in this plan.',
        sortLabel: '${debt.project.title} ${debt.plan.title}'.toLowerCase(),
        todo: null,
        planDebt: debt,
      );
    }

    final title = debt.isPastDeadline
        ? '${debt.plan.title} · deadline passed'
        : '${debt.plan.title} · behind by ${debt.behindUnits} $unitNoun';
    final body = 'Original pace ${_formatPace(debt.originalPace)} $unitNoun/day. Current pace ${_formatPace(debt.currentPace)} $unitNoun/day.';
    return _DebtItem(
      id: 'plan-debt-${debt.plan.id}',
      title: title,
      projectLabel: debt.project.title,
      detailLabel: '${debt.behindUnits} $unitNoun behind',
      body: body,
      sortLabel: '${debt.project.title} ${debt.plan.title}'.toLowerCase(),
      todo: null,
      planDebt: debt,
    );
  }

  factory _DebtItem.fromTodo(TodoItem todo) {
    return _DebtItem(
      id: 'todo-debt-${todo.id}',
      title: todo.title,
      projectLabel: todo.pdfLabel,
      detailLabel: todo.deadline == null ? 'Unresolved' : 'Due ${_shortDate(todo.deadline!)}',
      body: todo.body,
      sortLabel: '${todo.pdfLabel} ${todo.title}'.toLowerCase(),
      todo: todo,
      planDebt: null,
    );
  }
}

class _WeekDayPlan {
  final DateTime date;
  final bool isToday;
  final List<_RequirementItem> items;
  final int debtCount;

  const _WeekDayPlan({
    required this.date,
    required this.isToday,
    required this.items,
    required this.debtCount,
  });
}

class _ProjectStatus {
  final String id;
  final String title;
  final int activePlanCount;
  final int requiredTodayCount;
  final int debtCount;

  const _ProjectStatus({
    required this.id,
    required this.title,
    required this.activePlanCount,
    required this.requiredTodayCount,
    required this.debtCount,
  });

  String get statusLabel {
    if (debtCount > 0) return '$debtCount debt · $activePlanCount active plans';
    if (requiredTodayCount > 0) return '$requiredTodayCount required today · $activePlanCount active plans';
    if (activePlanCount > 0) return '$activePlanCount active plans';
    return 'No plans yet';
  }

  static List<_ProjectStatus> fromPlanning({
    required StudyPlanningRepository planningRepository,
    required List<_RequirementItem> requiredToday,
    required List<_DebtItem> debts,
  }) {
    final result = <_ProjectStatus>[];
    for (final project in planningRepository.projects) {
      final plans = planningRepository.plansForProject(project.id).where((plan) => !plan.isComplete).toList();
      final todayCount = requiredToday.where((item) => item.planRequirement?.project?.id == project.id).length;
      final debtCount = debts.where((item) => item.planDebt?.project.id == project.id).length;
      result.add(
        _ProjectStatus(
          id: project.id,
          title: project.title,
          activePlanCount: plans.length,
          requiredTodayCount: todayCount,
          debtCount: debtCount,
        ),
      );
    }

    result.sort((a, b) {
      final debtCompare = b.debtCount.compareTo(a.debtCount);
      if (debtCompare != 0) return debtCompare;
      final todayCompare = b.requiredTodayCount.compareTo(a.requiredTodayCount);
      if (todayCompare != 0) return todayCompare;
      final activeCompare = b.activePlanCount.compareTo(a.activePlanCount);
      if (activeCompare != 0) return activeCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return result;
  }
}

class _CalendarIndex {
  final Map<String, List<_CalendarItem>> _itemsByDate;

  const _CalendarIndex(this._itemsByDate);

  factory _CalendarIndex.fromSources({
    required List<TodoItem> todos,
    required List<StudyPlanRequirement> planRequirements,
    required List<CanvasCalendarEvent> canvasEvents,
  }) {
    final today = _dateOnly(DateTime.now());
    final map = <String, List<_CalendarItem>>{};

    void add(DateTime date, _CalendarItem item) {
      final key = _dateKey(date);
      map.putIfAbsent(key, () => <_CalendarItem>[]).add(item);
    }

    for (final requirement in planRequirements) {
      add(
        requirement.date,
        _CalendarItem(
          label: _calendarLabelForRequirement(requirement),
          isDebt: false,
          isDeadline: requirement.plan.isDeadlineMarker,
          sortRank: requirement.plan.isDeadlineMarker ? 20 : 10,
          planRequirement: requirement,
        ),
      );
    }

    for (final todo in todos) {
      final deadline = todo.deadline;
      if (deadline == null) continue;
      add(
        deadline,
        _CalendarItem(
          label: '${todo.pdfLabel}: ${todo.title}',
          isDebt: _dateOnly(deadline).isBefore(today),
          isDeadline: true,
          sortRank: 30,
          todo: todo,
        ),
      );
    }

    for (final event in canvasEvents) {
      add(
        event.startAt,
        _CalendarItem(
          label: '${event.courseLabel}: ${event.timeLabel} ${event.title}',
          isDebt: false,
          isDeadline: event.isDeadline,
          sortRank: event.isDeadline ? 35 : 5,
          canvasEvent: event,
        ),
      );
    }

    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final rankCompare = a.sortRank.compareTo(b.sortRank);
        if (rankCompare != 0) return rankCompare;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    }

    return _CalendarIndex(map);
  }

  List<_CalendarItem> itemsFor(DateTime date) {
    return _itemsByDate[_dateKey(date)] ?? const <_CalendarItem>[];
  }
}

class _CalendarItem {
  final String label;
  final bool isDebt;
  final bool isDeadline;
  final int sortRank;
  final StudyPlanRequirement? planRequirement;
  final TodoItem? todo;
  final CanvasCalendarEvent? canvasEvent;

  const _CalendarItem({
    required this.label,
    required this.isDebt,
    required this.isDeadline,
    required this.sortRank,
    this.planRequirement,
    this.todo,
    this.canvasEvent,
  });

  bool get isDocumentLinked {
    final documentId = todo?.note.documentId;
    return documentId != null && documentId.trim().isNotEmpty;
  }
}

String _calendarItemTooltip(_CalendarItem item) {
  final lines = <String>[item.label];
  final todo = item.todo;
  if (todo != null) {
    final documentId = todo.note.documentId;
    lines.add(item.isDocumentLinked ? 'Linked PDF: ${todo.pdfLabel}' : 'PDF todo');
    if (documentId != null && documentId.trim().isNotEmpty) {
      lines.add('Click to open the document');
    }
    final body = todo.body?.trim();
    if (body != null && body.isNotEmpty) lines.add(body);
    return lines.join('\n');
  }

  final requirement = item.planRequirement;
  if (requirement != null) {
    lines.add(requirement.projectTitle);
    lines.add(requirement.rangeLabel);
    return lines.join('\n');
  }

  final event = item.canvasEvent;
  if (event != null) {
    lines.add(event.courseLabel);
    lines.add(event.isDeadline ? 'Canvas deadline' : 'Canvas event');
    if (event.htmlUrl != null && event.htmlUrl!.trim().isNotEmpty) {
      lines.add(event.htmlUrl!);
    }
    return lines.join('\n');
  }

  return lines.join('\n');
}

class _WeekStyle {
  final int themeIndex;
  final int deadlinePressure;

  const _WeekStyle({required this.themeIndex, required this.deadlinePressure});
}

Map<String, _WeekStyle> _weekStylesForMonths({
  required List<DateTime> months,
  required List<DateTime> deadlineDates,
}) {
  if (months.isEmpty) return const <String, _WeekStyle>{};

  final firstWeek = _startOfWeek(DateTime(months.first.year, months.first.month));
  final lastMonth = months.last;
  final lastWeek = _startOfWeek(DateTime(lastMonth.year, lastMonth.month + 1, 0));
  final result = <String, _WeekStyle>{};
  var cursor = firstWeek;

  while (!cursor.isAfter(lastWeek)) {
    final weekIndex = cursor.difference(DateTime(2000, 1, 3)).inDays ~/ 7;
    final pressure = _deadlinePressureForWeek(cursor, deadlineDates);
    result[_dateKey(cursor)] = _WeekStyle(
      themeIndex: weekIndex.abs() % 4,
      deadlinePressure: pressure,
    );
    cursor = cursor.add(const Duration(days: 7));
  }

  return result;
}

int _deadlinePressureForWeek(DateTime weekStart, List<DateTime> deadlineDates) {
  var pressure = 0;
  for (final deadline in deadlineDates) {
    final deadlineWeek = _startOfWeek(deadline);
    final weeksUntil = deadlineWeek.difference(weekStart).inDays ~/ 7;
    if (weeksUntil < 0 || weeksUntil > 2) continue;
    final nextPressure = switch (weeksUntil) {
      0 => 3,
      1 => 2,
      2 => 1,
      _ => 0,
    };
    if (nextPressure > pressure) pressure = nextPressure;
  }
  return pressure;
}

List<DateTime> _deadlineDatesForCalendar({
  required StudyPlanningRepository planningRepository,
  required List<TodoItem> todos,
  required List<CanvasCalendarEvent> canvasEvents,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  bool inRange(DateTime date) {
    final value = _dateOnly(date);
    return !value.isBefore(rangeStart) && !value.isAfter(rangeEnd);
  }

  final dates = <DateTime>[];
  for (final project in planningRepository.projects) {
    final deadline = project.deadline;
    if (deadline != null && inRange(deadline)) dates.add(_dateOnly(deadline));
  }
  for (final plan in planningRepository.plans) {
    final deadline = plan.deadline ?? plan.taskDate;
    if (deadline != null && inRange(deadline)) dates.add(_dateOnly(deadline));
  }
  for (final todo in todos) {
    final deadline = todo.deadline;
    if (deadline != null && inRange(deadline)) dates.add(_dateOnly(deadline));
  }
  for (final event in canvasEvents) {
    if (event.isDeadline && inRange(event.startAt)) dates.add(_dateOnly(event.startAt));
  }

  dates.sort();
  return dates;
}

Color _calendarDayBackground({
  required ThemeData theme,
  required _WeekStyle weekStyle,
  required bool hasWork,
  required bool hasDebt,
  required bool hasDeadline,
  required bool isMuted,
}) {
  final Color tint;
  final int alpha;

  if (hasDebt) {
    tint = theme.colorScheme.errorContainer;
    alpha = 190;
  } else if (hasDeadline || weekStyle.deadlinePressure >= 3) {
    tint = theme.colorScheme.errorContainer;
    alpha = 165;
  } else if (weekStyle.deadlinePressure == 2) {
    tint = theme.colorScheme.tertiaryContainer;
    alpha = hasWork ? 150 : 120;
  } else if (weekStyle.deadlinePressure == 1) {
    tint = theme.colorScheme.secondaryContainer;
    alpha = hasWork ? 130 : 95;
  } else {
    tint = _weekTint(theme, weekStyle.themeIndex);
    alpha = hasWork ? 95 : 54;
  }

  final base = Color.alphaBlend(tint.withAlpha(alpha), theme.colorScheme.surface);
  if (!isMuted) return base;
  return Color.alphaBlend(theme.colorScheme.surface.withAlpha(120), base);
}

Color _weekTint(ThemeData theme, int index) {
  switch (index % 4) {
    case 0:
      return theme.colorScheme.primaryContainer;
    case 1:
      return theme.colorScheme.secondaryContainer;
    case 2:
      return theme.colorScheme.tertiaryContainer;
    default:
      return theme.colorScheme.surfaceContainerHighest;
  }
}

String _calendarLabelForRequirement(StudyPlanRequirement requirement) {
  if (requirement.plan.isDeadlineMarker) {
    return '${requirement.projectTitle}: ⚑ ${requirement.plan.title}';
  }
  if (requirement.plan.isSingleTask) {
    return '${requirement.projectTitle}: ${requirement.plan.title}';
  }
  if (requirement.plan.isChecklist) {
    return '${requirement.projectTitle}: ${requirement.rangeLabel}';
  }
  return '${requirement.projectTitle}: ${requirement.plan.title} · ${requirement.rangeLabel}';
}

DateTime _startOfWeek(DateTime date) {
  final day = _dateOnly(date);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String _dateKey(DateTime value) {
  final date = _dateOnly(value);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

enum _TileTone { today, debt }

typedef _RequirementToggleCallback = Future<void> Function(_RequirementItem item, bool completed);
typedef _RequirementOpenCallback = Future<void> Function(_RequirementItem item);
typedef _DebtToggleCallback = Future<void> Function(_DebtItem item, bool completed);
typedef _DebtOpenCallback = Future<void> Function(_DebtItem item);
typedef _NextSessionToggleCallback = Future<void> Function(_NextSessionItem item, bool completed);
typedef _NextSessionActionCallback = Future<void> Function(_NextSessionItem item);


List<DateTime> _calendarDaysForMonth(DateTime month) {
  final first = DateTime(month.year, month.month);
  final daysBefore = first.weekday - DateTime.monday;
  final start = first.subtract(Duration(days: daysBefore));
  return [for (var i = 0; i < 42; i++) start.add(Duration(days: i))];
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _sameDate(DateTime a, DateTime b) {
  final left = _dateOnly(a);
  final right = _dateOnly(b);
  return left.year == right.year && left.month == right.month && left.day == right.day;
}

String _priorityLabel(String priority) {
  switch (priority) {
    case kTodoPriorityHigh:
      return 'High priority';
    case kTodoPriorityLow:
      return 'Low priority';
    case kTodoPriorityMedium:
    default:
      return 'Medium priority';
  }
}

String _weekdayShort(DateTime date) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[date.weekday - 1];
}

String _formatLongDate(DateTime value) {
  return '${_weekdayName(value)}, ${_monthName(value.month)} ${value.day}';
}

String _weekdayName(DateTime date) {
  const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  return names[date.weekday - 1];
}

String _monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}

String _shortDate(DateTime value) {
  final date = _dateOnly(value);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String _formatPace(double value) {
  if (value >= 10) return value.toStringAsFixed(0);
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}
