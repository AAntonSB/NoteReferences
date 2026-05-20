import 'dart:async';

import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../library/presentation/library_screen.dart';
import '../../notes/data/note_repository.dart';
import '../../planning/data/study_planning_repository.dart';
import '../../planning/domain/study_material_source.dart';
import '../../planning/presentation/create_project_screen.dart';
import '../../planning/presentation/dev_todo_drawer.dart';
import '../../planning/presentation/planning_create_hub_screen.dart';
import '../../planning/presentation/project_planning_screen.dart';
import '../../reader/presentation/reader_screen.dart';

/// Opens the redesigned Today dashboard from surfaces that still use the
/// previous top-level helper API.
Future<void> showTodayBriefingModal({
  required BuildContext context,
  AppDatabase? database,
  StudyPlanningRepository? planningRepository,
  NoteRepository? noteRepository,
  FutureOr<void> Function(TodoItem todo)? onOpenTodo,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 1240,
        height: 760,
        child: StudyHomeScreen(
          database: database,
          planningRepository: planningRepository,
          externalNoteRepository: noteRepository,
          onOpenTodo: onOpenTodo,
        ),
      ),
    ),
  );
}

/// Calendar/requirements modal used by Library and Reader shortcuts.
Future<void> showStudyCalendarModal({
  required BuildContext context,
  required StudyPlanningRepository planningRepository,
  NoteRepository? noteRepository,
  FutureOr<void> Function(TodoItem todo)? onOpenTodo,
}) async {
  await planningRepository.load();
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 1180,
        height: 760,
        child: _StudyCalendarModal(
          planningRepository: planningRepository,
          noteRepository: noteRepository,
          onOpenTodo: onOpenTodo,
        ),
      ),
    ),
  );
}

/// Redesigned Today page. The layout follows the sketch, while its data and
/// actions are connected back to the planning repository and note todo system.
class StudyHomeScreen extends StatefulWidget {
  const StudyHomeScreen({
    super.key,
    this.database,
    this.planningRepository,
    this.externalNoteRepository,
    this.onOpenTodo,
  });

  final AppDatabase? database;
  final StudyPlanningRepository? planningRepository;
  final NoteRepository? externalNoteRepository;
  final FutureOr<void> Function(TodoItem todo)? onOpenTodo;

  @override
  State<StudyHomeScreen> createState() => _StudyHomeScreenState();
}

class _StudyHomeScreenState extends State<StudyHomeScreen> {
  late final StudyPlanningRepository _planningRepository;
  late final bool _ownsPlanningRepository;
  late final NoteRepository? _noteRepository;
  late DateTime _now;
  Timer? _clockTimer;
  bool _planningLoaded = false;
  Object? _loadError;
  _DailySetupSnapshot? _dailySetup;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _planningRepository = widget.planningRepository ?? StudyPlanningRepository();
    _ownsPlanningRepository = widget.planningRepository == null;
    _noteRepository = widget.externalNoteRepository ??
        (widget.database == null ? null : NoteRepository(widget.database!));
    _planningRepository.addListener(_onPlanningChanged);
    unawaited(_loadPlanning());
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _planningRepository.removeListener(_onPlanningChanged);
    if (_ownsPlanningRepository) {
      _planningRepository.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPlanning() async {
    try {
      await _planningRepository.load();
      if (!mounted) return;
      setState(() {
        _planningLoaded = true;
        _loadError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load Today planning data: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _planningLoaded = true;
        _loadError = error;
      });
    }
  }

  void _onPlanningChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final noteRepository = _noteRepository;
    if (noteRepository == null) {
      return _buildScaffold(const <TodoItem>[]);
    }

    return StreamBuilder<List<TodoItem>>(
      stream: noteRepository.watchTodos(includeCompleted: true),
      builder: (context, snapshot) {
        return _buildScaffold(snapshot.data ?? const <TodoItem>[]);
      },
    );
  }

  Widget _buildScaffold(List<TodoItem> todos) {
    late final _TodayDashboardData data;
    final today = _DateText.dateOnly(_now);
    final activeDailySetup = _dailySetup != null && _DateText.sameDate(_dailySetup!.date, today)
        ? _dailySetup
        : null;
    data = _TodayDashboardData.fromRepositories(
      planningRepository: _planningRepository,
      todos: todos,
      now: _now,
      planningLoaded: _planningLoaded,
      loadError: _loadError,
      dailySetup: activeDailySetup,
      onOpenTodaySetup: () => _openTodaySetup(data),
      onCompleteRequirement: _completeRequirement,
      onResolveDebt: _resolveDebt,
      onCompleteTodo: _completeTodo,
      onOpenRelatedFile: _openRelatedFile,
      onOpenProject: _openProject,
      onCreatePlan: _createPlan,
      onOpenCalendar: _openCalendar,
    );

    final chroma = _TodayColors.monthChroma(_now.month);
    return _TodayChromaticScope(
      chroma: chroma,
      child: Scaffold(
        backgroundColor: chroma.canvas,
        body: SafeArea(
        child: Column(
          children: [
            _TodayTopNavigation(
              onOpenLibrary: _openLibrary,
              onOpenCalendar: _openCalendar,
              onCreatePlan: _createPlan,
              onCreateProject: _createProject,
              onOpenDevTodos: _openDevTodos,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                child: _TodayDashboard(
                  data: data,
                  onOpenLibrary: _openLibrary,
                  onOpenCalendar: _openCalendar,
                  onCreatePlan: _createPlan,
                  onCreateProject: _createProject,
                  onOpenDevTodos: _openDevTodos,
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _completeRequirement(StudyPlanRequirement requirement) async {
    await _planningRepository.completeRequirement(requirement);
  }

  Future<void> _resolveDebt(StudyPlanDebt debt) async {
    await _planningRepository.resolveDebt(debt);
  }

  Future<void> _completeTodo(TodoItem todo) async {
    final noteRepository = _noteRepository;
    if (noteRepository == null) return;
    await noteRepository.updateTodoCompleted(todoId: todo.id, isCompleted: true);
  }

  Future<void> _openRelatedFile(_RelatedFileLink link) async {
    final todo = link.todo;
    if (todo != null) {
      await _openTodoSource(todo);
      return;
    }

    final source = link.materialSource;
    if (source == null) {
      _showSnackBar('No related file is linked yet.');
      return;
    }
    await _openMaterialSource(source);
  }

  Future<void> _openTodoSource(TodoItem todo) async {
    final externalOpen = widget.onOpenTodo;
    if (externalOpen != null) {
      await Future<void>.value(externalOpen(todo));
      return;
    }

    final database = widget.database;
    final documentId = todo.note.documentId;
    if (database == null || documentId == null || documentId.trim().isEmpty) {
      _showSnackBar('This todo is not linked to a readable file yet.');
      return;
    }

    try {
      final documents = await database.getAllDocuments();
      PdfDocument? document;
      for (final candidate in documents) {
        if (candidate.documentId == documentId) {
          document = candidate;
          break;
        }
      }
      if (!mounted) return;
      if (document == null) {
        _showSnackBar('Could not find the linked document.');
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen.pdf(
            database: database,
            documentId: document!.documentId,
            filePath: document!.filePath,
            title: document!.name,
            planningRepository: _planningRepository,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Could not open linked file: $error');
    }
  }

  Future<void> _openMaterialSource(StudyMaterialSource source) async {
    final database = widget.database;
    final filePath = source.filePath?.trim();
    if (database == null || filePath == null || filePath.isEmpty) {
      _showSnackBar('This source does not have an openable file path yet.');
      return;
    }

    final documentId = source.libraryDocumentId?.trim().isNotEmpty == true
        ? source.libraryDocumentId!.trim()
        : filePath;
    final title = source.title.trim().isEmpty ? 'Related file' : source.title.trim();

    if (source.type == StudyMaterialSourceType.epubFile) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen.epub(
            database: database,
            documentId: documentId,
            filePath: filePath,
            title: title,
            planningRepository: _planningRepository,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReaderScreen.pdf(
          database: database,
          documentId: documentId,
          filePath: filePath,
          title: title,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _openLibrary() async {
    final database = widget.database;
    if (database == null) {
      _showSnackBar('Library needs the app database.');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          database: database,
          planningRepository: _planningRepository,
        ),
      ),
    );
  }

  Future<void> _openCalendar() async {
    await showStudyCalendarModal(
      context: context,
      planningRepository: _planningRepository,
      noteRepository: _noteRepository,
      onOpenTodo: _openTodoSource,
    );
  }

  Future<void> _createPlan() async {
    await _planningRepository.load();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlanningCreateHubScreen(
          planningRepository: _planningRepository,
          database: widget.database,
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(
          planningRepository: _planningRepository,
          database: widget.database,
        ),
      ),
    );
  }

  Future<void> _openProject(String projectId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectPlanningScreen(
          planningRepository: _planningRepository,
          projectId: projectId,
          database: widget.database,
        ),
      ),
    );
  }

  Future<void> _openDevTodos() async {
    await showDevTodoDrawer(
      context: context,
      planningRepository: _planningRepository,
    );
  }

  Future<void> _openTodaySetup(_TodayDashboardData data) async {
    final suggestedItems = _DailySetupItemVm.fromWorkSections(data.workSections);
    final snapshot = await showDialog<_DailySetupSnapshot>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: SizedBox(
          width: 1080,
          height: 780,
          child: _TodaySetupDialog(
            date: _DateText.dateOnly(_now),
            suggestedItems: suggestedItems,
            existingSetup: _dailySetup != null && _DateText.sameDate(_dailySetup!.date, _DateText.dateOnly(_now))
                ? _dailySetup
                : null,
          ),
        ),
      ),
    );
    if (snapshot == null || !mounted) return;
    setState(() => _dailySetup = snapshot);
    final database = widget.database;
    if (database == null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _TodayChromaticScope(
            chroma: _TodayColors.monthChroma(_now.month),
            child: _TodayWorkSessionScreen(
              setup: snapshot,
              onOpenCalendar: _openCalendar,
              onCreatePlan: _createPlan,
            ),
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LibraryScreen(
          database: database,
          planningRepository: _planningRepository,
          todayWorkSession: _libraryTodayWorkSessionFromSetup(snapshot),
        ),
      ),
    );
  }

  LibraryTodayWorkSession _libraryTodayWorkSessionFromSetup(_DailySetupSnapshot setup) {
    return LibraryTodayWorkSession(
      date: setup.date,
      createdAt: setup.createdAt,
      items: setup.includedItems.map((item) {
        return LibraryTodayWorkItem(
          id: item.id,
          title: item.title,
          description: _todayItemDescription(
            amount: item.detail,
            reason: item.reason,
            source: item.sourceLabel,
          ),
          sourceLabel: item.sourceLabel,
          sourceIcon: item.sourceIcon,
          onOpenSource: item.onOpenSource,
          onComplete: item.onComplete,
        );
      }).toList(growable: false),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _TodayDashboard extends StatelessWidget {
  const _TodayDashboard({
    required this.data,
    required this.onOpenLibrary,
    required this.onOpenCalendar,
    required this.onCreatePlan,
    required this.onCreateProject,
    required this.onOpenDevTodos,
  });

  final _TodayDashboardData data;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenCalendar;
  final Future<void> Function() onCreatePlan;
  final Future<void> Function() onCreateProject;
  final Future<void> Function() onOpenDevTodos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;
        final topRow = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 246, child: _TodayDateCard(now: data.now)),
                  const SizedBox(width: 12),
                  Expanded(child: _WeekOverviewCard(data: data)),
                ],
              )
            : Column(
                children: [
                  _TodayDateCard(now: data.now),
                  const SizedBox(height: 16),
                  _WeekOverviewCard(data: data),
                ],
              );

        final mainContent = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: _TodayMainColumn(data: data),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 360,
                    child: _TodaySideColumn(
                      data: data,
                      onOpenLibrary: onOpenLibrary,
                      onOpenCalendar: onOpenCalendar,
                      onCreatePlan: onCreatePlan,
                      onCreateProject: onCreateProject,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _TodayMainColumn(data: data),
                  const SizedBox(height: 16),
                  _TodaySideColumn(
                    data: data,
                    onOpenLibrary: onOpenLibrary,
                    onOpenCalendar: onOpenCalendar,
                    onCreatePlan: onCreatePlan,
                    onCreateProject: onCreateProject,
                  ),
                ],
              );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                topRow,
                const SizedBox(height: 24),
                if (!data.planningLoaded)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: _InlineStatusBanner(
                      icon: Icons.sync_rounded,
                      text: 'Loading planning data...',
                    ),
                  ),
                if (data.loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InlineStatusBanner(
                      icon: Icons.error_outline_rounded,
                      text: 'Could not load planning data: ${data.loadError}',
                    ),
                  ),
                mainContent,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TodayTopNavigation extends StatelessWidget {
  const _TodayTopNavigation({
    required this.onOpenLibrary,
    required this.onOpenCalendar,
    required this.onCreatePlan,
    required this.onCreateProject,
    required this.onOpenDevTodos,
  });

  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenCalendar;
  final Future<void> Function() onCreatePlan;
  final Future<void> Function() onCreateProject;
  final Future<void> Function() onOpenDevTodos;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: chroma.navSurface,
        border: Border(bottom: BorderSide(color: chroma.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: chroma.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.grid_view_rounded, size: 17, color: chroma.accent),
          ),
          const SizedBox(width: 10),
          const Text(
            'Notedesk',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _TodayColors.ink,
              letterSpacing: -.2,
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 24, color: chroma.border),
          const SizedBox(width: 16),
          Text(
            'Today',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: chroma.accent),
          ),
          const Spacer(),
          _TopNavAction(icon: Icons.bug_report_outlined, label: 'Todos', onTap: onOpenDevTodos),
          _TopNavAction(icon: Icons.notes_rounded, label: 'Plan work', onTap: onCreatePlan),
          _TopNavAction(icon: Icons.calendar_month_outlined, label: 'Calendar', onTap: onOpenCalendar),
          const SizedBox(width: 8),
          _NavPillButton(icon: Icons.add_rounded, label: 'Plan', onTap: onCreatePlan),
          const SizedBox(width: 8),
          _NavPillButton(
            icon: Icons.folder_outlined,
            label: 'Library',
            filled: false,
            onTap: onOpenLibrary,
          ),
          const SizedBox(width: 12),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: chroma.soft, shape: BoxShape.circle),
            child: Text('J', style: TextStyle(fontWeight: FontWeight.w800, color: chroma.accent)),
          ),
        ],
      ),
    );
  }
}

class _TopNavAction extends StatelessWidget {
  const _TopNavAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => unawaited(onTap()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: chroma.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: chroma.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavPillButton extends StatelessWidget {
  const _NavPillButton({required this.icon, required this.label, required this.onTap, this.filled = true});

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => unawaited(onTap()),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: filled ? chroma.soft : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: chroma.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: chroma.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: chroma.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayMainColumn extends StatelessWidget {
  const _TodayMainColumn({required this.data});

  final _TodayDashboardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TodayTasksPanel(data: data),
        const SizedBox(height: 16),
        _SchedulePressurePanel(
          pressures: data.schedulePressures,
          onOpenCalendar: data.onOpenCalendar,
        ),
      ],
    );
  }
}

class _TodaySideColumn extends StatelessWidget {
  const _TodaySideColumn({
    required this.data,
    required this.onOpenLibrary,
    required this.onOpenCalendar,
    required this.onCreatePlan,
    required this.onCreateProject,
  });

  final _TodayDashboardData data;
  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenCalendar;
  final Future<void> Function() onCreatePlan;
  final Future<void> Function() onCreateProject;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _QuickAccessPanel(
          onOpenLibrary: onOpenLibrary,
          onOpenCalendar: onOpenCalendar,
          onCreatePlan: onCreatePlan,
          onCreateProject: onCreateProject,
        ),
        const SizedBox(height: 16),
        _ActiveProjectsPanel(projects: data.projects, onCreateProject: onCreateProject),
      ],
    );
  }
}

class _TodayDateCard extends StatelessWidget {
  const _TodayDateCard({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final day = now.day.toString().padLeft(2, '0');
    final month = _DateText.month(now.month);
    final time = _DateText.time(now);
    final weekday = _DateText.weekday(now.weekday);

    // This block intentionally has no card chrome. It should feel like part of
    // the page header rather than a separate widget sitting inside a box.
    return SizedBox(
      height: 190,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 112,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  day,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 72,
                    height: .84,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -4.4,
                    color: _TodayColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  month,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: _TodayColors.monthAccent(now.month),
                    letterSpacing: -.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 27,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: _TodayColors.ink,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  weekday,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: _TodayColors.inkMuted,
                    letterSpacing: -.2,
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

class _WeekOverviewCard extends StatelessWidget {
  const _WeekOverviewCard({required this.data});

  final _TodayDashboardData data;

  @override
  Widget build(BuildContext context) {
    final currentWeek = data.weekDays.take(7).toList(growable: false);
    final nextWeek = data.weekDays.skip(7).take(7).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 1280.0;
        final wrapped = availableWidth < 980;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WeekRibbonRow(
              label: 'This week',
              days: currentWeek,
              wrapped: wrapped,
              availableWidth: availableWidth,
              saturated: true,
            ),
            const SizedBox(height: 22),
            _WeekRibbonRow(
              label: 'Next week',
              days: nextWeek,
              wrapped: wrapped,
              availableWidth: availableWidth,
              saturated: false,
            ),
          ],
        );
      },
    );
  }
}

class _WeekRibbonRow extends StatelessWidget {
  const _WeekRibbonRow({
    required this.label,
    required this.days,
    required this.wrapped,
    required this.availableWidth,
    required this.saturated,
  });

  final String label;
  final List<_WeekDayVm> days;
  final bool wrapped;
  final double availableWidth;
  final bool saturated;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final first = days.first.date;
    final last = days.last.date;
    final range = _formatRange(first, last);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekRibbonLabel(label: label, range: range),
        const SizedBox(height: 7),
        if (wrapped)
          _buildWrappedGrid()
        else
          SizedBox(
            height: 172,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final day in days) Expanded(child: _WeekDayTile(day: day, dayTint: _dayTintFor(day, saturated: saturated))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildWrappedGrid() {
    final columns = availableWidth < 560
        ? 2
        : availableWidth < 760
            ? 3
            : 4;
    final spacing = 10.0;
    final tileWidth = ((availableWidth - spacing * (columns - 1)) / columns).clamp(164.0, 280.0).toDouble();
    return Wrap(
      spacing: spacing,
      runSpacing: 10,
      children: [
        for (final day in days)
          SizedBox(
            width: tileWidth,
            height: 164,
            child: _WeekDayTile(day: day, dayTint: _dayTintFor(day, saturated: saturated)),
          ),
      ],
    );
  }

  Color _dayTintFor(_WeekDayVm day, {required bool saturated}) {
    return _TodayColors.monthWeekDayTint(
      day.date.month,
      alternateTone: day.date.weekday.isEven,
      saturated: saturated,
    );
  }

  static String _formatRange(DateTime first, DateTime last) {
    final firstLabel = '${first.day} ${_DateText.shortMonth(first.month)}';
    final lastLabel = '${last.day} ${_DateText.shortMonth(last.month)}';
    return '$firstLabel – $lastLabel';
  }
}

class _WeekRibbonLabel extends StatelessWidget {
  const _WeekRibbonLabel({required this.label, required this.range});

  final String label;
  final String range;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w900,
            color: _TodayColors.inkMuted,
            letterSpacing: .25,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  chroma.borderStrong.withOpacity(.9),
                  chroma.border.withOpacity(.15),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          range,
          style: const TextStyle(
            fontSize: 10.5,
            height: 1,
            fontWeight: FontWeight.w800,
            color: _TodayColors.inkFaint,
          ),
        ),
      ],
    );
  }
}

class _WeekDayTile extends StatelessWidget {
  const _WeekDayTile({required this.day, required this.dayTint});

  final _WeekDayVm day;
  final Color dayTint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 154;
        final weekday = compact ? _DateText.shortWeekday(day.date.weekday) : _DateText.weekday(day.date.weekday);
        final dateLabel = compact ? '${day.date.day}/${day.date.month}' : '${day.date.day} ${_DateText.shortMonth(day.date.month)}';
        final muted = day.isPast && !day.active;
        final visibleItems = day.items.take(2).toList(growable: false);
        final labelColor = day.active
            ? _TodayColors.monthAccent(day.date.month)
            : muted
                ? _TodayColors.inkFaint
                : _TodayColors.inkMuted;
        final backgroundColor = muted ? _TodayColors.pastDayWash : dayTint;
        final borderColor = Colors.transparent;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.symmetric(horizontal: compact ? 3 : 5),
          padding: EdgeInsets.fromLTRB(compact ? 8 : 11, 9, compact ? 8 : 11, 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: null,
          ),
          child: Stack(
            children: [
              if (day.hasDeadline && !day.active)
                Positioned(
                  left: 0,
                  top: 12,
                  bottom: 12,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: _TodayColors.deadline.withOpacity(.72),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WeekDayHeading(
                      weekday: weekday,
                      dateLabel: dateLabel,
                      active: day.active,
                      muted: muted,
                      labelColor: labelColor,
                      hasDeadline: day.hasDeadline,
                    ),
                    const SizedBox(height: 7),
                    Expanded(
                      child: visibleItems.isEmpty
                          ? Center(
                              child: Container(
                                width: compact ? 16 : 22,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: muted ? _TodayColors.border : _TodayChromaticScope.of(context).borderStrong,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            )
                          : ClipRect(
                              child: SingleChildScrollView(
                                primary: false,
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    for (var index = 0; index < visibleItems.length; index++) ...[
                                      _WeekWorkLine(
                                        item: visibleItems[index],
                                        compact: compact,
                                        faded: muted && !visibleItems[index].isDeadline,
                                      ),
                                      if (index != visibleItems.length - 1) const SizedBox(height: 7),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeekDayHeading extends StatelessWidget {
  const _WeekDayHeading({
    required this.weekday,
    required this.dateLabel,
    required this.active,
    required this.muted,
    required this.labelColor,
    required this.hasDeadline,
  });

  final String weekday;
  final String dateLabel;
  final bool active;
  final bool muted;
  final Color labelColor;
  final bool hasDeadline;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: active ? 38 : 31,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: labelColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  weekday,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.3,
                    height: 1,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                    color: labelColor,
                    letterSpacing: -.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 10.4,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: active
                      ? labelColor
                      : muted
                          ? _TodayColors.inkFaint
                          : _TodayColors.inkMuted,
                ),
              ),
              if (hasDeadline) ...[
                const SizedBox(width: 5),
                const Icon(Icons.flag_rounded, size: 11, color: _TodayColors.deadline),
              ],
            ],
          ),
          if (active) ...[
            const SizedBox(height: 6),
            Container(
              width: 34,
              height: 2,
              decoration: BoxDecoration(
                color: labelColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekWorkLine extends StatelessWidget {
  const _WeekWorkLine({required this.item, required this.compact, required this.faded});

  final _WeekWorkItemVm item;
  final bool compact;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final accent = item.isDeadline
        ? _TodayColors.deadline
        : item.isFinish
            ? _TodayColors.finish
            : chroma.accent;
    final titleColor = item.isDeadline
        ? _TodayColors.deadline
        : faded
            ? _TodayColors.inkFaint
            : _TodayColors.ink;
    final detailColor = item.isDeadline
        ? _TodayColors.deadline
        : item.isFinish
            ? _TodayColors.finish
            : faded
                ? _TodayColors.inkFaint
                : _TodayColors.inkMuted;

    final marker = item.isDeadline
        ? const Icon(Icons.flag_rounded, size: 11, color: _TodayColors.deadline)
        : item.isFinish
            ? const Icon(Icons.keyboard_double_arrow_down_rounded, size: 12, color: _TodayColors.finish)
            : Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 13,
            height: item.detail == null ? 20 : 36,
            child: Align(alignment: const Alignment(0, -.70), child: marker),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11.1,
                    height: 1.08,
                    fontWeight: item.isDeadline ? FontWeight.w900 : FontWeight.w800,
                    color: titleColor,
                  ),
                ),
                if (item.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 9.3 : 10.1,
                      height: 1.04,
                      fontWeight: FontWeight.w800,
                      color: detailColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayTasksPanel extends StatelessWidget {
  const _TodayTasksPanel({required this.data});

  final _TodayDashboardData data;

  @override
  Widget build(BuildContext context) {
    final plannedSection = data.workSections.firstWhere(
      (section) => section.kind == _TodayWorkSectionKind.planned,
      orElse: () => const _TodayWorkSectionVm(
        title: 'Planned for today',
        subtitle: null,
        icon: Icons.menu_book_rounded,
        kind: _TodayWorkSectionKind.planned,
        items: <_TodayWorkItemVm>[],
      ),
    );
    final plannedItems = plannedSection.items;
    final setup = data.dailySetup;
    final setupItems = setup?.includedItems ?? const <_DailySetupItemVm>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  setup == null
                      ? '${plannedItems.length} planned today'
                      : '${setupItems.length} item${setupItems.length == 1 ? '' : 's'} in today',
                  style: const TextStyle(
                    fontSize: 12.2,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: _TodayColors.inkFaint,
                    letterSpacing: .1,
                  ),
                ),
              ),
              _SetupTodayButton(onTap: data.onOpenTodaySetup),
            ],
          ),
          const SizedBox(height: 10),
          if (setup != null && setupItems.isNotEmpty)
            _SetupTodayList(items: setupItems)
          else if (plannedItems.isEmpty)
            _IntegratedEmptyToday(onSetupToday: data.onOpenTodaySetup)
          else
            _PlannedTodayList(items: plannedItems),
        ],
      ),
    );
  }
}

class _SetupTodayButton extends StatelessWidget {
  const _SetupTodayButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return TextButton.icon(
      onPressed: () => unawaited(onTap()),
      icon: const Icon(Icons.wb_twilight_rounded, size: 17),
      label: const Text('Setup today'),
      style: TextButton.styleFrom(
        foregroundColor: chroma.accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _PlannedTodayList extends StatelessWidget {
  const _PlannedTodayList({required this.items});

  final List<_TodayWorkItemVm> items;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(chroma.card, chroma.canvas, .32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color.lerp(chroma.border, chroma.canvas, .18)!),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++)
            _PlannedTodayRow(
              title: items[index].title,
              description: _todayItemDescription(amount: items[index].amount, reason: items[index].reason, source: items[index].sourceLabel),
              onComplete: items[index].onComplete,
              last: index == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _SetupTodayList extends StatelessWidget {
  const _SetupTodayList({required this.items});

  final List<_DailySetupItemVm> items;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(chroma.card, chroma.canvas, .32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color.lerp(chroma.border, chroma.canvas, .18)!),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++)
            _PlannedTodayRow(
              title: items[index].title,
              description: _todayItemDescription(amount: items[index].detail, reason: items[index].reason, source: items[index].sourceLabel),
              onComplete: items[index].onComplete,
              last: index == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _IntegratedEmptyToday extends StatelessWidget {
  const _IntegratedEmptyToday({required this.onSetupToday});

  final Future<void> Function() onSetupToday;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: Color.lerp(chroma.card, chroma.canvas, .32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color.lerp(chroma.border, chroma.canvas, .18)!),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rtl_rounded, color: chroma.accent, size: 20),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'No planned work is assigned today. Use setup to add reminders or create today manually.',
              style: TextStyle(fontSize: 12.3, height: 1.35, fontWeight: FontWeight.w700, color: _TodayColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannedTodayRow extends StatelessWidget {
  const _PlannedTodayRow({required this.title, required this.description, required this.onComplete, required this.last});

  final String title;
  final String description;
  final Future<void> Function()? onComplete;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: last ? Colors.transparent : chroma.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onComplete == null ? null : () => unawaited(onComplete!()),
              child: Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chroma.card,
                  border: Border.all(color: onComplete == null ? chroma.borderStrong : chroma.accent, width: 1.45),
                ),
                child: Icon(Icons.check_rounded, size: 14, color: onComplete == null ? chroma.borderStrong : chroma.accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.6, height: 1.2, fontWeight: FontWeight.w900, color: _TodayColors.ink),
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.7, height: 1.26, fontWeight: FontWeight.w700, color: _TodayColors.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _todayItemDescription({String? amount, required String reason, String? source}) {
  final parts = <String>[];
  if (amount != null && amount.trim().isNotEmpty) parts.add(amount.trim());
  if (reason.trim().isNotEmpty) parts.add(reason.trim());
  if (source != null && source.trim().isNotEmpty) parts.add(source.trim());
  return parts.join(' · ');
}

class _TodaySetupEntryCard extends StatelessWidget {
  const _TodaySetupEntryCard({required this.setup, required this.onOpenSetup, required this.suggestedCount});

  final _DailySetupSnapshot? setup;
  final Future<void> Function() onOpenSetup;
  final int suggestedCount;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final activeSetup = setup;
    final selected = activeSetup?.includedItems ?? const <_DailySetupItemVm>[];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => unawaited(onOpenSetup()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: Color.lerp(chroma.soft, chroma.card, .32),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: chroma.borderStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: chroma.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: chroma.border),
                ),
                child: Icon(activeSetup == null ? Icons.wb_twilight_rounded : Icons.checklist_rtl_rounded, size: 20, color: chroma.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            activeSetup == null ? 'Get started with today' : 'Today setup active',
                            style: const TextStyle(fontSize: 14, height: 1.15, fontWeight: FontWeight.w900, color: _TodayColors.ink),
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: chroma.accent),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeSetup == null
                          ? 'Review generated work, plan pressure, deadlines, and add reminders before you begin.'
                          : '${selected.length} selected · ${activeSetup.mustCount} must · ${activeSetup.shouldCount} should · ${activeSetup.extraCount} extra',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _TodayText.muted.copyWith(height: 1.25),
                    ),
                    if (activeSetup != null && selected.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final item in selected.take(4))
                            _TodaySetupMiniPill(item: item),
                          if (selected.length > 4)
                            _TodaySetupOverflowPill(count: selected.length - 4),
                        ],
                      ),
                    ] else if (activeSetup == null) ...[
                      const SizedBox(height: 9),
                      Text(
                        suggestedCount == 0 ? 'No generated items yet. You can still add manual reminders.' : '$suggestedCount suggested item${suggestedCount == 1 ? '' : 's'} ready to review.',
                        style: TextStyle(fontSize: 11.5, height: 1.15, fontWeight: FontWeight.w800, color: chroma.accent),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _TodaySetupCommitmentList extends StatelessWidget {
  const _TodaySetupCommitmentList({required this.setup});

  final _DailySetupSnapshot setup;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final selected = setup.includedItems;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: chroma.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: chroma.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 16, color: chroma.accent),
              const SizedBox(width: 7),
              const Expanded(
                child: Text('Today setup', style: TextStyle(fontSize: 12.4, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
              ),
              Text(
                '${selected.length} selected',
                style: const TextStyle(fontSize: 10.8, fontWeight: FontWeight.w900, color: _TodayColors.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final priority in [_DailySetupPriority.must, _DailySetupPriority.should, _DailySetupPriority.extra])
            _TodaySetupPriorityGroup(priority: priority, items: selected.where((item) => item.priority == priority).toList(growable: false)),
        ],
      ),
    );
  }
}

class _TodaySetupPriorityGroup extends StatelessWidget {
  const _TodaySetupPriorityGroup({required this.priority, required this.items});

  final _DailySetupPriority priority;
  final List<_DailySetupItemVm> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final color = _setupPriorityColor(context, priority);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(priority.label, style: TextStyle(fontSize: 10.8, height: 1, fontWeight: FontWeight.w900, color: color, letterSpacing: .2)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final item in items)
                _TodaySetupCommitmentChip(item: item, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodaySetupCommitmentChip extends StatelessWidget {
  const _TodaySetupCommitmentChip({required this.item, required this.color});

  final _DailySetupItemVm item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.white, .91),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color.lerp(color, Colors.white, .7)!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.kind.icon, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.detail == null ? item.title : '${item.title} · ${item.detail}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.2, height: 1, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySetupMiniPill extends StatelessWidget {
  const _TodaySetupMiniPill({required this.item});

  final _DailySetupItemVm item;

  @override
  Widget build(BuildContext context) {
    final color = _setupPriorityColor(context, item.priority);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.white, .88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Color.lerp(color, Colors.white, .62)!),
      ),
      child: Text(
        '${item.priority.label}: ${item.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.8, height: 1, fontWeight: FontWeight.w900, color: color),
      ),
    );
  }
}

class _TodaySetupOverflowPill extends StatelessWidget {
  const _TodaySetupOverflowPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: chroma.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chroma.border),
      ),
      child: Text('$count more', style: const TextStyle(fontSize: 10.8, height: 1, fontWeight: FontWeight.w900, color: _TodayColors.inkMuted)),
    );
  }
}

class _TodaySetupDialog extends StatefulWidget {
  const _TodaySetupDialog({required this.date, required this.suggestedItems, required this.existingSetup});

  final DateTime date;
  final List<_DailySetupItemVm> suggestedItems;
  final _DailySetupSnapshot? existingSetup;

  @override
  State<_TodaySetupDialog> createState() => _TodaySetupDialogState();
}

class _TodaySetupDialogState extends State<_TodaySetupDialog> {
  late final TextEditingController _extraController;
  late final List<_DailySetupItemDraft> _items;

  @override
  void initState() {
    super.initState();
    _extraController = TextEditingController();
    final existing = widget.existingSetup;
    final sourceItems = existing != null && _DateText.sameDate(existing.date, widget.date)
        ? existing.items
        : widget.suggestedItems.where((item) => item.kind != _DailySetupItemKind.availableTodo).toList(growable: false);
    _items = sourceItems.map((item) {
      final draft = _DailySetupItemDraft.fromVm(item);
      draft.included = true;
      return draft;
    }).toList(growable: true);
  }

  @override
  void dispose() {
    _extraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final selectedCount = _items.where((item) => item.included).length;
    return Container(
      color: chroma.canvas,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: chroma.soft, borderRadius: BorderRadius.circular(15)),
                  child: Icon(Icons.wb_twilight_rounded, color: chroma.accent, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Setup today', style: _TodayText.sectionTitle.copyWith(fontSize: 20, letterSpacing: -.35)),
                      const SizedBox(height: 5),
                      Text(
                        'Add what you need to remember, review the planned work, then start today.',
                        style: _TodayText.muted.copyWith(fontSize: 13.1, height: 1.32),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: _TodayColors.inkMuted,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: _SetupQuickAdd(
              controller: _extraController,
              onAdd: _addManualReminder,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Today list',
                        style: const TextStyle(fontSize: 12.6, height: 1, fontWeight: FontWeight.w900, color: _TodayColors.inkFaint, letterSpacing: .15),
                      ),
                    ),
                    Text(
                      '$selectedCount active',
                      style: const TextStyle(fontSize: 11.5, height: 1, fontWeight: FontWeight.w900, color: _TodayColors.inkFaint),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: chroma.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: chroma.border),
                    ),
                    child: const Text(
                      'No planned items yet. Add reminders above to build today manually.',
                      style: TextStyle(fontSize: 12.4, height: 1.35, fontWeight: FontWeight.w700, color: _TodayColors.inkMuted),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: chroma.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: chroma.borderStrong),
                    ),
                    child: Column(
                      children: [
                        for (var index = 0; index < _items.length; index++)
                          _SetupTodayDraftRow(
                            item: _items[index],
                            last: index == _items.length - 1,
                            onChanged: () => setState(() {}),
                            onDelete: _items[index].manual ? () => setState(() => _items.removeAt(index)) : null,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            decoration: BoxDecoration(color: chroma.navSurface, border: Border(top: BorderSide(color: chroma.border))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Start today turns this setup into the working screen. It does not time-block your day.',
                    style: _TodayText.muted.copyWith(fontSize: 12.2, height: 1.25),
                  ),
                ),
                const SizedBox(width: 14),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start today'),
                  style: FilledButton.styleFrom(
                    backgroundColor: chroma.accent,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addManualReminder() {
    final text = _extraController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.insert(
        0,
        _DailySetupItemDraft(
          id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
          kind: _DailySetupItemKind.manualReminder,
          title: text,
          detail: null,
          reason: 'Added during today setup',
          included: true,
          priority: _DailySetupPriority.should,
          manual: true,
        ),
      );
      _extraController.clear();
    });
  }

  void _save() {
    final now = DateTime.now();
    Navigator.of(context).pop(
      _DailySetupSnapshot(
        date: widget.date,
        createdAt: widget.existingSetup?.createdAt ?? now,
        updatedAt: now,
        items: _items.map((item) => item.toVm()).toList(growable: false),
      ),
    );
  }
}

class _SetupQuickAdd extends StatelessWidget {
  const _SetupQuickAdd({required this.controller, required this.onAdd});

  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add something for today...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: chroma.borderStrong)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: chroma.accent, width: 1.5)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('Add'),
          style: FilledButton.styleFrom(
            backgroundColor: chroma.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _SetupTodayDraftRow extends StatelessWidget {
  const _SetupTodayDraftRow({required this.item, required this.last, required this.onChanged, this.onDelete});

  final _DailySetupItemDraft item;
  final bool last;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final description = _todayItemDescription(amount: item.detail, reason: item.reason, source: item.sourceLabel);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: last ? Colors.transparent : chroma.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: item.included,
              activeColor: chroma.accent,
              onChanged: (value) {
                item.included = value ?? false;
                item.priority = item.included ? _DailySetupPriority.should : _DailySetupPriority.notToday;
                onChanged();
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.4, height: 1.2, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.8, height: 1.25, fontWeight: FontWeight.w700, color: _TodayColors.inkMuted)),
                  ],
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: _TodayColors.inkFaint,
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayWorkSessionScreen extends StatefulWidget {
  const _TodayWorkSessionScreen({required this.setup, required this.onOpenCalendar, required this.onCreatePlan});

  final _DailySetupSnapshot setup;
  final Future<void> Function() onOpenCalendar;
  final Future<void> Function() onCreatePlan;

  @override
  State<_TodayWorkSessionScreen> createState() => _TodayWorkSessionScreenState();
}

class _TodayWorkSessionScreenState extends State<_TodayWorkSessionScreen> {
  late final Set<String> _doneIds;

  @override
  void initState() {
    super.initState();
    _doneIds = <String>{};
  }

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final items = widget.setup.includedItems;
    final remaining = items.length - _doneIds.length;
    return Scaffold(
      backgroundColor: chroma.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: _TodayColors.inkMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Today', style: _TodayText.sectionTitle.copyWith(fontSize: 22, letterSpacing: -.45)),
                        const SizedBox(height: 3),
                        Text(
                          remaining == 0 ? 'All selected items are checked off.' : '$remaining item${remaining == 1 ? '' : 's'} left from setup',
                          style: _TodayText.muted.copyWith(fontSize: 12.6, height: 1.25),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => unawaited(widget.onOpenCalendar()),
                    icon: const Icon(Icons.calendar_month_rounded, size: 17),
                    label: const Text('Calendar'),
                    style: TextButton.styleFrom(foregroundColor: chroma.accent, textStyle: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: chroma.card,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: chroma.borderStrong),
                          boxShadow: [BoxShadow(color: chroma.shadow, blurRadius: 22, offset: const Offset(0, 12))],
                        ),
                        child: Column(
                          children: [
                            for (var index = 0; index < items.length; index++)
                              _StartedTodayRow(
                                item: items[index],
                                done: _doneIds.contains(items[index].id),
                                last: index == items.length - 1,
                                onChanged: (done) async {
                                  setState(() {
                                    if (done) {
                                      _doneIds.add(items[index].id);
                                    } else {
                                      _doneIds.remove(items[index].id);
                                    }
                                  });
                                  if (done && items[index].onComplete != null) {
                                    await items[index].onComplete!();
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => unawaited(widget.onCreatePlan()),
                              icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                              label: const Text('Adjust plan'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.check_rounded, size: 17),
                              label: const Text('Leave work screen'),
                              style: FilledButton.styleFrom(backgroundColor: chroma.accent, foregroundColor: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartedTodayRow extends StatelessWidget {
  const _StartedTodayRow({required this.item, required this.done, required this.last, required this.onChanged});

  final _DailySetupItemVm item;
  final bool done;
  final bool last;
  final Future<void> Function(bool done) onChanged;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final description = _todayItemDescription(amount: item.detail, reason: item.reason, source: item.sourceLabel);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: last ? Colors.transparent : chroma.border))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: done,
              activeColor: chroma.accent,
              onChanged: (value) => unawaited(onChanged(value ?? false)),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: done ? _TodayColors.inkFaint : _TodayColors.ink,
                      decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.28, fontWeight: FontWeight.w700, color: _TodayColors.inkMuted)),
                  ],
                  if (item.onOpenSource != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => unawaited(item.onOpenSource!()),
                      icon: Icon(item.sourceIcon ?? Icons.description_outlined, size: 16),
                      label: const Text('Open source'),
                      style: TextButton.styleFrom(foregroundColor: chroma.accent, padding: EdgeInsets.zero, textStyle: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupSectionFrame extends StatelessWidget {
  const _SetupSectionFrame({required this.title, required this.subtitle, required this.icon, required this.child});

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: chroma.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chroma.borderStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionIcon(icon: icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
                      const SizedBox(height: 3),
                      Text(subtitle, style: _TodayText.muted.copyWith(fontSize: 11.8, height: 1.25)),
                    ],
                  ),
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

class _SetupDraftRow extends StatelessWidget {
  const _SetupDraftRow({required this.item, required this.last, required this.onChanged, this.onDelete});

  final _DailySetupItemDraft item;
  final bool last;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final priorityColor = _setupPriorityColor(context, item.priority);
    return Container(
      padding: EdgeInsets.only(bottom: last ? 0 : 10, top: last ? 0 : 0),
      margin: EdgeInsets.only(bottom: last ? 0 : 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: chroma.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.included,
            activeColor: priorityColor,
            onChanged: (value) {
              item.included = value ?? false;
              if (!item.included) item.priority = _DailySetupPriority.notToday;
              if (item.included && item.priority == _DailySetupPriority.notToday) item.priority = _DailySetupPriority.should;
              onChanged();
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(fontSize: 13.2, height: 1.2, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
                if (item.detail != null) ...[
                  const SizedBox(height: 3),
                  Text(item.detail!, style: TextStyle(fontSize: 12.1, height: 1.2, fontWeight: FontWeight.w800, color: priorityColor)),
                ],
                const SizedBox(height: 3),
                Text(item.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: _TodayText.muted.copyWith(fontSize: 11.5, height: 1.25)),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final priority in _DailySetupPriority.values)
                      _PriorityChoiceChip(
                        priority: priority,
                        selected: item.priority == priority,
                        onTap: () {
                          item.priority = priority;
                          item.included = priority != _DailySetupPriority.notToday;
                          onChanged();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Remove reminder',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: _TodayColors.inkFaint,
            ),
        ],
      ),
    );
  }
}

class _PriorityChoiceChip extends StatelessWidget {
  const _PriorityChoiceChip({required this.priority, required this.selected, required this.onTap});

  final _DailySetupPriority priority;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _setupPriorityColor(context, priority);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Color.lerp(color, Colors.white, .82) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Color.lerp(color, Colors.white, .45)! : _TodayChromaticScope.of(context).border),
        ),
        child: Text(priority.label, style: TextStyle(fontSize: 11.2, fontWeight: FontWeight.w900, color: selected ? color : _TodayColors.inkMuted)),
      ),
    );
  }
}

class _SetupSummaryChip extends StatelessWidget {
  const _SetupSummaryChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: chroma.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: chroma.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chroma.accent),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: _TodayColors.inkMuted)),
        ],
      ),
    );
  }
}

Color _setupPriorityColor(BuildContext context, _DailySetupPriority priority) {
  final chroma = _TodayChromaticScope.of(context);
  switch (priority) {
    case _DailySetupPriority.must:
      return _TodayColors.deadline;
    case _DailySetupPriority.should:
      return chroma.accent;
    case _DailySetupPriority.extra:
      return _TodayColors.finish;
    case _DailySetupPriority.notToday:
      return _TodayColors.inkFaint;
  }
}

class _TodayWorkSection extends StatelessWidget {
  const _TodayWorkSection({required this.section});

  final _TodayWorkSectionVm section;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final accent = _sectionAccent(context, section.kind);
    return Container(
      decoration: BoxDecoration(
        color: _sectionBackground(context, section.kind),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _sectionBorder(context, section.kind)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned(top: 0, bottom: 0, left: 0, width: 5, child: ColoredBox(color: accent)),
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color.lerp(accent, Colors.white, .86),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(section.icon, size: 17, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section.title,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                                color: _TodayColors.ink,
                              ),
                            ),
                            if (section.subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                section.subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _TodayText.muted.copyWith(fontSize: 11.5, height: 1.25),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: chroma.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _sectionBorder(context, section.kind)),
                    ),
                    child: Column(
                      children: [
                        for (var index = 0; index < section.items.length; index++)
                          _TodayWorkItemRow(
                            item: section.items[index],
                            accent: accent,
                            last: index == section.items.length - 1,
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
  }

  Color _sectionAccent(BuildContext context, _TodayWorkSectionKind kind) {
    final chroma = _TodayChromaticScope.of(context);
    switch (kind) {
      case _TodayWorkSectionKind.critical:
        return _TodayColors.deadline;
      case _TodayWorkSectionKind.pressure:
        return _TodayColors.finish;
      case _TodayWorkSectionKind.available:
        return _TodayColors.inkMuted;
      case _TodayWorkSectionKind.planned:
        return chroma.accent;
    }
  }

  Color _sectionBackground(BuildContext context, _TodayWorkSectionKind kind) {
    final chroma = _TodayChromaticScope.of(context);
    switch (kind) {
      case _TodayWorkSectionKind.critical:
        return _TodayColors.deadlineSoft;
      case _TodayWorkSectionKind.pressure:
        return Color.lerp(_TodayColors.finishSoft, chroma.surface, .58)!;
      case _TodayWorkSectionKind.available:
        return Color.lerp(_TodayColors.pastDayWash, chroma.surface, .52)!;
      case _TodayWorkSectionKind.planned:
        return chroma.surface;
    }
  }

  Color _sectionBorder(BuildContext context, _TodayWorkSectionKind kind) {
    final chroma = _TodayChromaticScope.of(context);
    switch (kind) {
      case _TodayWorkSectionKind.critical:
        return _TodayColors.deadlineBorder;
      case _TodayWorkSectionKind.pressure:
        return _TodayColors.finishBorder;
      case _TodayWorkSectionKind.available:
        return Color.lerp(_TodayColors.border, chroma.border, .5)!;
      case _TodayWorkSectionKind.planned:
        return chroma.border;
    }
  }
}

class _TodayWorkItemRow extends StatelessWidget {
  const _TodayWorkItemRow({required this.item, required this.accent, required this.last});

  final _TodayWorkItemVm item;
  final Color accent;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: last ? Colors.transparent : chroma.border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final content = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: item.onComplete == null ? null : () => unawaited(item.onComplete!()),
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: item.onComplete == null ? chroma.borderStrong : accent, width: 1.5),
                    ),
                    child: Icon(Icons.check_rounded, size: 14, color: item.onComplete == null ? chroma.borderStrong : accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.18,
                                fontWeight: FontWeight.w900,
                                color: _TodayColors.ink,
                              ),
                            ),
                          ),
                          if (!compact && item.amount != null) ...[
                            const SizedBox(width: 12),
                            _WorkAmountChip(text: item.amount!, color: accent),
                          ],
                        ],
                      ),
                      if (compact && item.amount != null) ...[
                        const SizedBox(height: 6),
                        _WorkAmountInline(text: item.amount!, color: accent),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        item.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w700, color: _TodayColors.inkMuted),
                      ),
                      if (item.sourceLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.sourceLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w700, color: _TodayColors.inkFaint),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );

            final buttons = Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: compact ? WrapAlignment.start : WrapAlignment.end,
              children: [
                if (item.onOpenSource != null)
                  _InlineActionButton(
                    icon: item.sourceIcon ?? Icons.description_outlined,
                    label: 'Open source',
                    color: accent,
                    onTap: item.onOpenSource!,
                  ),
                if (item.onComplete != null)
                  _InlineActionButton(
                    icon: Icons.done_rounded,
                    label: item.completeLabel,
                    color: accent,
                    onTap: item.onComplete!,
                  ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  if (item.onOpenSource != null || item.onComplete != null) ...[
                    const SizedBox(height: 10),
                    Padding(padding: const EdgeInsets.only(left: 34), child: buttons),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: content),
                if (item.onOpenSource != null || item.onComplete != null) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: buttons,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkAmountChip extends StatelessWidget {
  const _WorkAmountChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.white, .88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Color.lerp(color, Colors.white, .66)!),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, height: 1.0, fontWeight: FontWeight.w900, color: color),
      ),
    );
  }
}

class _WorkAmountInline extends StatelessWidget {
  const _WorkAmountInline({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, height: 1.15, fontWeight: FontWeight.w900, color: color),
    );
  }
}

class _InlineActionButton extends StatelessWidget {
  const _InlineActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => unawaited(onTap()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Color.lerp(color, Colors.white, .91),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Color.lerp(color, Colors.white, .70)!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, height: 1.0, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}


class _SchedulePressurePanel extends StatelessWidget {
  const _SchedulePressurePanel({required this.pressures, required this.onOpenCalendar});

  final List<_SchedulePressureVm> pressures;
  final Future<void> Function() onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _SectionIcon(icon: Icons.auto_graph_rounded),
              const SizedBox(width: 10),
              const Expanded(child: Text('Schedule pressure', style: _TodayText.sectionTitle)),
              TextButton.icon(
                onPressed: () => unawaited(onOpenCalendar()),
                icon: const Icon(Icons.calendar_month_rounded, size: 16),
                label: const Text('Calendar'),
                style: TextButton.styleFrom(
                  foregroundColor: chroma.accent,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Unfinished planned work is not discarded. The remaining workload is redistributed across the future plan.',
            style: _TodayText.muted,
          ),
          const SizedBox(height: 14),
          if (pressures.isEmpty)
            const _EmptyStateRow(
              icon: Icons.check_circle_outline_rounded,
              title: 'No unfinished planned work',
              subtitle: 'Your current plan is on pace. Deadlines and future workload still appear in the calendar above.',
            )
          else
            Container(
              decoration: BoxDecoration(
                color: chroma.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: chroma.border),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < pressures.length; index++)
                    _SchedulePressureRow(
                      pressure: pressures[index],
                      last: index == pressures.length - 1,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SchedulePressureRow extends StatelessWidget {
  const _SchedulePressureRow({required this.pressure, required this.last});

  final _SchedulePressureVm pressure;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final markerColor = pressure.urgent ? _TodayColors.deadline : _TodayColors.finish;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: last ? Colors.transparent : _TodayColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: markerColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pressure.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.w900, color: _TodayColors.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  pressure.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _TodayText.muted,
                ),
                const SizedBox(height: 6),
                Text(
                  pressure.pace,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: pressure.urgent ? _TodayColors.deadline : _TodayColors.inkMuted,
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

class _QuickAccessPanel extends StatelessWidget {
  const _QuickAccessPanel({
    required this.onOpenLibrary,
    required this.onOpenCalendar,
    required this.onCreatePlan,
    required this.onCreateProject,
  });

  final Future<void> Function() onOpenLibrary;
  final Future<void> Function() onOpenCalendar;
  final Future<void> Function() onCreatePlan;
  final Future<void> Function() onCreateProject;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        children: [
          const _PanelHeader(icon: Icons.bolt_rounded, title: 'Quick access'),
          const SizedBox(height: 14),
          _QuickAccessTile(icon: Icons.menu_book_outlined, title: 'Library', subtitle: 'Open PDFs, EPUBs, and notes', onTap: onOpenLibrary),
          const SizedBox(height: 9),
          _QuickAccessTile(icon: Icons.calendar_month_outlined, title: 'Calendar', subtitle: 'Review plan distribution', onTap: onOpenCalendar),
          const SizedBox(height: 9),
          _QuickAccessTile(icon: Icons.checklist_rounded, title: 'Create plan', subtitle: 'Turn work into daily steps', onTap: onCreatePlan),
          const SizedBox(height: 9),
          _QuickAccessTile(icon: Icons.grid_view_rounded, title: 'Create project', subtitle: 'Start a new work stream', onTap: onCreateProject),
        ],
      ),
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return InkWell(
      onTap: () => unawaited(onTap()),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: chroma.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: chroma.border)),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: chroma.soft, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: chroma.accent, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _TodayColors.inkFaint)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_rounded, color: _TodayColors.ink, size: 19),
          ],
        ),
      ),
    );
  }
}

class _ActiveProjectsPanel extends StatelessWidget {
  const _ActiveProjectsPanel({required this.projects, required this.onCreateProject});

  final List<_ProjectVm> projects;
  final Future<void> Function() onCreateProject;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        children: [
          Row(
            children: [
              const _SectionIcon(icon: Icons.work_outline_rounded),
              const SizedBox(width: 10),
              const Expanded(child: Text('Active projects', style: _TodayText.sectionTitle)),
              TextButton(
                onPressed: projects.isEmpty ? null : () => unawaited(projects.first.onOpen()),
                style: TextButton.styleFrom(foregroundColor: chroma.accent, textStyle: const TextStyle(fontWeight: FontWeight.w900)),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: chroma.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: chroma.border)),
            child: projects.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: _EmptyStateRow(
                      icon: Icons.work_outline_rounded,
                      title: 'No active projects yet',
                      subtitle: 'Create a project to connect today to longer-term work.',
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < projects.length; i++) _ProjectRow(project: projects[i], last: i == projects.length - 1),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(onCreateProject()),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create project'),
              style: OutlinedButton.styleFrom(
                foregroundColor: chroma.accent,
                side: BorderSide(color: chroma.borderStrong),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.last});

  final _ProjectVm project;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final percent = (project.progress * 100).round();
    return InkWell(
      onTap: () => unawaited(project.onOpen()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: last ? Colors.transparent : _TodayColors.border))),
        child: Row(
          children: [
            Icon(Icons.folder_rounded, color: chroma.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
                  const SizedBox(height: 3),
                  Text(project.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _TodayColors.inkFaint)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: project.progress, minHeight: 4, color: chroma.accent, backgroundColor: chroma.border),
              ),
            ),
            const SizedBox(width: 8),
            Text('$percent%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _TodayColors.inkMuted)),
          ],
        ),
      ),
    );
  }
}


class _StudyCalendarModal extends StatelessWidget {
  const _StudyCalendarModal({
    required this.planningRepository,
    this.noteRepository,
    this.onOpenTodo,
  });

  final StudyPlanningRepository planningRepository;
  final NoteRepository? noteRepository;
  final FutureOr<void> Function(TodoItem todo)? onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final notes = noteRepository;
    if (notes == null) {
      return _buildBody(context, const <TodoItem>[]);
    }
    return StreamBuilder<List<TodoItem>>(
      stream: notes.watchTodos(includeCompleted: true),
      builder: (context, snapshot) => _buildBody(context, snapshot.data ?? const <TodoItem>[]),
    );
  }

  Widget _buildBody(BuildContext context, List<TodoItem> todos) {
    final chroma = _TodayChromaticScope.of(context);
    final now = DateTime.now();
    final today = _DateText.dateOnly(now);
    final firstMonth = DateTime(today.year, today.month);
    final lastMonth = DateTime(today.year, today.month + 5);
    final rangeStart = firstMonth;
    final rangeEnd = DateTime(lastMonth.year, lastMonth.month + 1, 0);
    final months = <DateTime>[
      for (var index = 0; index < 6; index++) DateTime(today.year, today.month + index),
    ];

    final requirements = planningRepository.requirementsForRange(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
    );
    final debts = planningRepository.studyDebts(now);
    final openTodos = todos.where((todo) => !todo.isCompleted).toList(growable: false);
    final entriesByDate = _calendarEntriesByDate(
      requirements: requirements,
      todos: openTodos,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );

    return Scaffold(
      backgroundColor: chroma.canvas,
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _SectionIcon(icon: Icons.calendar_month_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Calendar', style: _TodayText.sectionTitle),
                      SizedBox(height: 3),
                      Text(
                        'Scrollable plan view with deadlines, planned finishes, reading work, and source todos.',
                        style: _TodayText.muted,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 920;
                  final calendar = _SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: CustomScrollView(
                      slivers: [
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final month = months[index];
                              return Padding(
                                padding: EdgeInsets.only(bottom: index == months.length - 1 ? 0 : 24),
                                child: _CalendarMonthSection(
                                  month: month,
                                  today: today,
                                  entriesByDate: entriesByDate,
                                ),
                              );
                            },
                            childCount: months.length,
                          ),
                        ),
                      ],
                    ),
                  );
                  final sidebar = _CalendarSidebar(
                    debts: debts,
                    openTodos: openTodos,
                    onOpenTodo: onOpenTodo,
                  );

                  if (compact) {
                    return Column(
                      children: [
                        Expanded(child: calendar),
                        const SizedBox(height: 14),
                        SizedBox(height: 220, child: sidebar),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 7, child: calendar),
                      const SizedBox(width: 16),
                      SizedBox(width: 340, child: sidebar),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<_CalendarEntryVm>> _calendarEntriesByDate({
    required List<StudyPlanRequirement> requirements,
    required List<TodoItem> todos,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final map = <String, List<_CalendarEntryVm>>{};
    void add(DateTime date, _CalendarEntryVm entry) {
      final normalized = _DateText.dateOnly(date);
      if (normalized.isBefore(rangeStart) || normalized.isAfter(rangeEnd)) return;
      map.putIfAbsent(_DateText.dateKey(normalized), () => <_CalendarEntryVm>[]).add(entry);
    }

    for (final requirement in requirements) {
      final plannedFinish = !requirement.isDeadlineMarker &&
          requirement.plan.deadline != null &&
          _DateText.sameDate(requirement.plan.deadline!, requirement.date);
      add(
        requirement.date,
        _CalendarEntryVm(
          title: requirement.isDeadlineMarker ? requirement.plan.title : requirement.plan.title,
          detail: requirement.isDeadlineMarker ? requirement.projectTitle : requirement.rangeLabel,
          isDeadline: requirement.isDeadlineMarker,
          isFinish: plannedFinish,
        ),
      );
    }

    for (final todo in todos) {
      final deadline = todo.deadline;
      if (deadline == null) continue;
      add(
        deadline,
        _CalendarEntryVm(
          title: todo.title,
          detail: todo.pdfLabel,
          isDeadline: true,
          isFinish: false,
          onTap: () async {
            final open = onOpenTodo;
            if (open != null) await Future<void>.value(open(todo));
          },
        ),
      );
    }

    for (final entries in map.values) {
      entries.sort((a, b) {
        final rankA = a.isDeadline ? 0 : (a.isFinish ? 1 : 2);
        final rankB = b.isDeadline ? 0 : (b.isFinish ? 1 : 2);
        final rankCompare = rankA.compareTo(rankB);
        if (rankCompare != 0) return rankCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }
    return map;
  }
}

class _CalendarSidebar extends StatelessWidget {
  const _CalendarSidebar({required this.debts, required this.openTodos, required this.onOpenTodo});

  final List<StudyPlanDebt> debts;
  final List<TodoItem> openTodos;
  final FutureOr<void> Function(TodoItem todo)? onOpenTodo;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: ListView(
        children: [
          Row(
            children: [
              const Expanded(child: Text('Needs attention', style: _TodayText.sectionTitle)),
              _CountPill('${debts.length + openTodos.length} open'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Unfinished plans remain visible here so the future distribution can be recalculated instead of silently discarded.',
            style: _TodayText.muted,
          ),
          const SizedBox(height: 16),
          if (debts.isEmpty && openTodos.isEmpty)
            const _EmptyStateRow(
              icon: Icons.task_alt_rounded,
              title: 'No unfinished work or source todos',
              subtitle: 'Missed planned work and file-linked todos will appear here.',
            ),
          for (final debt in debts.take(10))
            _CompactRequirementRow(
              title: debt.plan.title,
              subtitle: '${debt.project.title} • ${debt.behindUnits} ${debt.plan.unitNounForCount(debt.behindUnits)} behind',
              icon: debt.isPastDeadline ? Icons.error_outline_rounded : Icons.auto_graph_rounded,
              onTap: () => Future<void>.value(),
            ),
          if (debts.isNotEmpty && openTodos.isNotEmpty) const Divider(height: 22, color: _TodayColors.border),
          for (final todo in openTodos.take(12))
            _CompactRequirementRow(
              title: todo.title,
              subtitle: todo.deadline == null
                  ? todo.pdfLabel
                  : '${todo.pdfLabel} • due ${_DateText.monthDay(todo.deadline!)}',
              icon: todo.deadline == null ? Icons.description_outlined : Icons.flag_rounded,
              onTap: () async {
                final open = onOpenTodo;
                if (open != null) await Future<void>.value(open(todo));
              },
            ),
        ],
      ),
    );
  }
}

class _CalendarMonthSection extends StatelessWidget {
  const _CalendarMonthSection({required this.month, required this.today, required this.entriesByDate});

  final DateTime month;
  final DateTime today;
  final Map<String, List<_CalendarEntryVm>> entriesByDate;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    final gridStart = first.subtract(Duration(days: first.weekday - DateTime.monday));
    final gridEnd = last.add(Duration(days: DateTime.sunday - last.weekday));
    final days = <DateTime>[];
    var cursor = gridStart;
    while (!cursor.isAfter(gridEnd)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              _DateText.month(month.month),
              style: TextStyle(
                fontSize: 23,
                height: 1,
                fontWeight: FontWeight.w900,
                color: _TodayColors.monthAccent(month.month),
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              month.year.toString(),
              style: const TextStyle(
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w900,
                color: _TodayColors.inkFaint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 1, color: _TodayColors.border)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
              Expanded(
                child: Center(
                  child: Text(
                    _DateText.shortWeekday(weekday),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: _TodayColors.inkFaint,
                      letterSpacing: .4,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < days.length ~/ 7; row++) ...[
          SizedBox(
            height: 112,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _CalendarDayCell(
                      date: days[row * 7 + column],
                      visibleMonth: month.month,
                      today: today,
                      entries: entriesByDate[_DateText.dateKey(days[row * 7 + column])] ?? const <_CalendarEntryVm>[],
                    ),
                  ),
              ],
            ),
          ),
          if (row != days.length ~/ 7 - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({required this.date, required this.visibleMonth, required this.today, required this.entries});

  final DateTime date;
  final int visibleMonth;
  final DateTime today;
  final List<_CalendarEntryVm> entries;

  @override
  Widget build(BuildContext context) {
    final inMonth = date.month == visibleMonth;
    final isToday = _DateText.sameDate(date, today);
    final isPast = _DateText.dateOnly(date).isBefore(today);
    final tint = _TodayColors.monthWeekDayTint(
      date.month,
      alternateTone: date.weekday.isEven,
      saturated: inMonth,
    );
    final visibleEntries = entries.take(3).toList(growable: false);
    final hiddenCount = entries.length - visibleEntries.length;
    final accent = _TodayColors.monthAccent(date.month);

    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: inMonth ? tint : _TodayColors.pastDayWash,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isToday ? accent : Colors.transparent, width: isToday ? 1.2 : 1),
      ),
      child: Opacity(
        opacity: inMonth ? (isPast && !isToday ? .58 : 1) : .34,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  date.day.toString(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: isToday ? accent : _TodayColors.inkMuted,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Expanded(
              child: entries.isEmpty
                  ? const SizedBox.shrink()
                  : ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in visibleEntries) _CalendarEntryLine(entry: entry),
                          if (hiddenCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                '$hiddenCount more',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: _TodayColors.inkFaint,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarEntryLine extends StatelessWidget {
  const _CalendarEntryLine({required this.entry});

  final _CalendarEntryVm entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.isDeadline
        ? _TodayColors.deadline
        : entry.isFinish
            ? _TodayColors.finish
            : _TodayColors.ink;
    final marker = entry.isDeadline
        ? Icons.flag_rounded
        : entry.isFinish
            ? Icons.keyboard_double_arrow_down_rounded
            : Icons.circle;
    final line = InkWell(
      onTap: entry.onTap == null ? null : () => unawaited(entry.onTap!()),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(marker, size: entry.isDeadline || entry.isFinish ? 10 : 5, color: color),
            SizedBox(width: entry.isDeadline || entry.isFinish ? 4 : 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.2,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  if (entry.detail != null)
                    Text(
                      entry.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.4,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        color: entry.isDeadline || entry.isFinish ? color : _TodayColors.inkMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return line;
  }
}

class _CalendarEntryVm {
  const _CalendarEntryVm({
    required this.title,
    this.detail,
    required this.isDeadline,
    required this.isFinish,
    this.onTap,
  });

  final String title;
  final String? detail;
  final bool isDeadline;
  final bool isFinish;
  final Future<void> Function()? onTap;
}

class _CompactRequirementRow extends StatelessWidget {
  const _CompactRequirementRow({required this.title, required this.subtitle, required this.icon, required this.onTap});

  final String title;
  final String subtitle;
  final IconData icon;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return InkWell(
      onTap: () => unawaited(Future<void>.value(onTap())),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 18, color: chroma.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _TodayColors.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayDashboardData {
  const _TodayDashboardData({
    required this.now,
    required this.planningLoaded,
    required this.loadError,
    required this.dailySetup,
    required this.onOpenTodaySetup,
    required this.weekDays,
    required this.todayDeadlines,
    required this.tasks,
    required this.workSections,
    required this.planBlocks,
    required this.schedulePressures,
    required this.projects,
    required this.relatedFile,
    required this.openTaskCount,
    required this.onCreatePlan,
    required this.onOpenCalendar,
  });

  final DateTime now;
  final bool planningLoaded;
  final Object? loadError;
  final _DailySetupSnapshot? dailySetup;
  final Future<void> Function() onOpenTodaySetup;
  final List<_WeekDayVm> weekDays;
  final List<_DeadlineSignalVm> todayDeadlines;
  final List<_TodayTaskVm> tasks;
  final List<_TodayWorkSectionVm> workSections;
  final List<_PlanBlock> planBlocks;
  final List<_SchedulePressureVm> schedulePressures;
  final List<_ProjectVm> projects;
  final _RelatedFileLink? relatedFile;
  final int openTaskCount;
  final Future<void> Function() onCreatePlan;
  final Future<void> Function() onOpenCalendar;

  static _TodayDashboardData fromRepositories({
    required StudyPlanningRepository planningRepository,
    required List<TodoItem> todos,
    required DateTime now,
    required bool planningLoaded,
    required Object? loadError,
    required _DailySetupSnapshot? dailySetup,
    required Future<void> Function() onOpenTodaySetup,
    required Future<void> Function(StudyPlanRequirement requirement) onCompleteRequirement,
    required Future<void> Function(StudyPlanDebt debt) onResolveDebt,
    required Future<void> Function(TodoItem todo) onCompleteTodo,
    required Future<void> Function(_RelatedFileLink link) onOpenRelatedFile,
    required Future<void> Function(String projectId) onOpenProject,
    required Future<void> Function() onCreatePlan,
    required Future<void> Function() onOpenCalendar,
  }) {
    final today = _DateText.dateOnly(now);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    const visibleDayCount = 14;
    final openTodos = todos.where((todo) => !todo.isCompleted).toList(growable: false);
    final weekDays = <_WeekDayVm>[];
    final todayDeadlines = <_DeadlineSignalVm>[];

    for (var index = 0; index < visibleDayCount; index++) {
      final date = weekStart.add(Duration(days: index));
      final requirements = planningRepository.requirementsForRange(rangeStart: date, rangeEnd: date, now: now);
      final dayTodos = todos.where((todo) => todo.deadline != null && _DateText.sameDate(todo.deadline!, date)).toList(growable: false);
      final openDayTodos = dayTodos.where((todo) => !todo.isCompleted).toList(growable: false);
      final doneTodoCount = dayTodos.where((todo) => todo.isCompleted).length;
      final items = _weekWorkItemsForDate(
        date: date,
        requirements: requirements,
        todos: openDayTodos,
        planningRepository: planningRepository,
      );
      final studyUnits = requirements.fold<int>(0, (sum, requirement) => sum + requirement.unitCount);
      final workloadUnits = studyUnits + openDayTodos.length;
      if (_DateText.sameDate(date, today)) {
        todayDeadlines.addAll(items
            .where((item) => item.isDeadline)
            .map((item) => _DeadlineSignalVm(title: item.label, date: date)));
      }
      weekDays.add(
        _WeekDayVm(
          date: date,
          active: _DateText.sameDate(date, today),
          isPast: date.isBefore(today),
          taskCount: requirements.length + openDayTodos.length,
          doneCount: doneTodoCount,
          workloadUnits: workloadUnits,
          items: items,
        ),
      );
    }

    final todayRequirements = planningRepository.requirementsForRange(rangeStart: today, rangeEnd: today, now: now);
    final debts = planningRepository.studyDebts(now);
    final todayTodos = openTodos.where((todo) {
      final deadline = todo.deadline;
      if (deadline == null) return false;
      return !_DateText.dateOnly(deadline).isAfter(today);
    }).toList(growable: false);
    final undatedTodos = openTodos.where((todo) => todo.deadline == null).toList(growable: false);

    final tasks = <_TodayTaskVm>[];
    for (final debt in debts.take(2)) {
      tasks.add(
        _TodayTaskVm(
          title: debt.plan.title,
          subtitle: '${debt.behindUnits} ${debt.plan.unitNounForCount(debt.behindUnits)} behind',
          tag: debt.project.title,
          onComplete: () => onResolveDebt(debt),
        ),
      );
    }
    for (final requirement in todayRequirements) {
      tasks.add(
        _TodayTaskVm(
          title: _requirementTitle(requirement),
          subtitle: requirement.projectTitle,
          tag: _requirementTag(requirement),
          onComplete: () => onCompleteRequirement(requirement),
        ),
      );
      if (tasks.length >= 6) break;
    }
    for (final todo in [...todayTodos, ...undatedTodos]) {
      if (tasks.length >= 6) break;
      tasks.add(
        _TodayTaskVm(
          title: todo.title,
          subtitle: todo.pdfLabel,
          tag: _todoTag(todo),
          onComplete: () => onCompleteTodo(todo),
        ),
      );
    }

    final workSections = _buildTodayWorkSections(
      today: today,
      debts: debts,
      requirements: todayRequirements,
      todayTodos: todayTodos,
      undatedTodos: undatedTodos,
      onCompleteRequirement: onCompleteRequirement,
      onResolveDebt: onResolveDebt,
      onCompleteTodo: onCompleteTodo,
      onOpenRelatedFile: onOpenRelatedFile,
    );
    final openWorkItemCount = workSections.fold<int>(0, (sum, section) => sum + section.items.length);

    final planBlocks = _buildPlanBlocks(
      debts: debts,
      requirements: todayRequirements,
      openTodos: openTodos,
    );
    final schedulePressures = _buildSchedulePressures(debts);

    final projects = planningRepository.projects.map((project) {
      final plans = planningRepository.plansForProject(project.id);
      final todayCount = todayRequirements.where((item) => item.plan.projectId == project.id).length;
      final progress = plans.isEmpty
          ? 0.0
          : plans.map((plan) => plan.progress).fold<double>(0, (sum, value) => sum + value) / plans.length;
      return _ProjectVm(
        id: project.id,
        title: project.title,
        subtitle: '$todayCount required today • ${plans.length} active ${plans.length == 1 ? 'plan' : 'plans'}',
        progress: progress.clamp(0, 1).toDouble(),
        onOpen: () => onOpenProject(project.id),
      );
    }).take(4).toList(growable: false);

    final related = _firstRelatedFile(
      requirements: todayRequirements,
      todos: openTodos,
      onOpenRelatedFile: onOpenRelatedFile,
    );

    return _TodayDashboardData(
      now: now,
      planningLoaded: planningLoaded,
      loadError: loadError,
      dailySetup: dailySetup,
      onOpenTodaySetup: onOpenTodaySetup,
      weekDays: weekDays,
      todayDeadlines: todayDeadlines,
      tasks: tasks,
      workSections: workSections,
      planBlocks: planBlocks,
      schedulePressures: schedulePressures,
      projects: projects,
      relatedFile: related,
      openTaskCount: openWorkItemCount,
      onCreatePlan: onCreatePlan,
      onOpenCalendar: onOpenCalendar,
    );
  }

  static List<_TodayWorkSectionVm> _buildTodayWorkSections({
    required DateTime today,
    required List<StudyPlanDebt> debts,
    required List<StudyPlanRequirement> requirements,
    required List<TodoItem> todayTodos,
    required List<TodoItem> undatedTodos,
    required Future<void> Function(StudyPlanRequirement requirement) onCompleteRequirement,
    required Future<void> Function(StudyPlanDebt debt) onResolveDebt,
    required Future<void> Function(TodoItem todo) onCompleteTodo,
    required Future<void> Function(_RelatedFileLink link) onOpenRelatedFile,
  }) {
    final deadlineRequirements = requirements.where((item) => item.isDeadlineMarker).toList(growable: false);
    final plannedRequirements = requirements.where((item) => !item.isDeadlineMarker).toList(growable: false);

    final criticalItems = <_TodayWorkItemVm>[];
    for (final todo in todayTodos) {
      final deadlineDate = todo.deadline == null ? null : _DateText.dateOnly(todo.deadline!);
      final overdue = deadlineDate != null && deadlineDate.isBefore(today);
      final sourceLink = _relatedLinkForTodo(todo, onOpenRelatedFile);
      criticalItems.add(
        _TodayWorkItemVm(
          title: todo.title,
          amount: overdue ? 'Overdue' : 'Due today',
          reason: overdue ? 'Deadline passed · ${_DateText.monthDay(deadlineDate!)}' : 'Deadline today',
          sourceLabel: todo.pdfLabel == 'No source' ? null : todo.pdfLabel,
          sourceIcon: sourceLink?.icon,
          onOpenSource: sourceLink == null ? null : () => onOpenRelatedFile(sourceLink),
          onComplete: () => onCompleteTodo(todo),
          completeLabel: 'Done',
        ),
      );
    }
    for (final requirement in deadlineRequirements) {
      final sourceLink = _relatedLinkForRequirement(requirement, onOpenRelatedFile);
      criticalItems.add(
        _TodayWorkItemVm(
          title: requirement.plan.title,
          amount: 'Deadline marker',
          reason: 'Plan deadline · ${requirement.projectTitle}',
          sourceLabel: sourceLink?.subtitle,
          sourceIcon: sourceLink?.icon,
          onOpenSource: sourceLink == null ? null : () => onOpenRelatedFile(sourceLink),
          onComplete: () => onCompleteRequirement(requirement),
          completeLabel: 'Done',
        ),
      );
    }

    final pressureItems = debts.map((debt) {
      final noun = debt.plan.unitNounForCount(debt.behindUnits);
      final oldPace = _formatPace(debt.originalPace, debt.plan.unitNounForCount(debt.originalPace.round().clamp(1, 999999).toInt()));
      final newPace = _formatPace(debt.currentPace, debt.plan.unitNounForCount(debt.currentPace.round().clamp(1, 999999).toInt()));
      final missedText = debt.missedDays > 0
          ? '${debt.missedDays} missed ${debt.missedDays == 1 ? 'day' : 'days'}'
          : 'unfinished planned work';
      return _TodayWorkItemVm(
        title: debt.plan.title,
        amount: '${debt.behindUnits} $noun behind',
        reason: '$missedText · future pace $oldPace/day → $newPace/day',
        sourceLabel: debt.project.title,
        onComplete: () => onResolveDebt(debt),
        completeLabel: 'Resolve',
      );
    }).toList(growable: false);

    final groupedRequirements = <String, List<StudyPlanRequirement>>{};
    for (final requirement in plannedRequirements) {
      groupedRequirements.putIfAbsent(requirement.plan.id, () => <StudyPlanRequirement>[]).add(requirement);
    }
    final plannedItems = <_TodayWorkItemVm>[];
    for (final group in groupedRequirements.values) {
      if (group.isEmpty) continue;
      final first = group.first;
      final sourceLink = _relatedLinkForRequirement(first, onOpenRelatedFile);
      plannedItems.add(
        _TodayWorkItemVm(
          title: first.plan.title,
          amount: _requirementGroupDetail(group),
          reason: 'Planned today · ${first.projectTitle}',
          sourceLabel: sourceLink?.subtitle,
          sourceIcon: sourceLink?.icon,
          onOpenSource: sourceLink == null ? null : () => onOpenRelatedFile(sourceLink),
          onComplete: () async {
            for (final requirement in group) {
              await onCompleteRequirement(requirement);
            }
          },
          completeLabel: 'Done today',
        ),
      );
    }

    final availableItems = undatedTodos.take(5).map((todo) {
      final sourceLink = _relatedLinkForTodo(todo, onOpenRelatedFile);
      return _TodayWorkItemVm(
        title: todo.title,
        amount: null,
        reason: 'Available todo · not scheduled for a specific day',
        sourceLabel: todo.pdfLabel == 'No source' ? null : todo.pdfLabel,
        sourceIcon: sourceLink?.icon,
        onOpenSource: sourceLink == null ? null : () => onOpenRelatedFile(sourceLink),
        onComplete: () => onCompleteTodo(todo),
        completeLabel: 'Done',
      );
    }).toList(growable: false);

    return <_TodayWorkSectionVm>[
      _TodayWorkSectionVm(
        title: 'Critical today',
        subtitle: 'Hard deadlines and due items. This is the only section that should feel urgent.',
        icon: Icons.flag_rounded,
        kind: _TodayWorkSectionKind.critical,
        items: criticalItems,
      ),
      _TodayWorkSectionVm(
        title: 'Plan pressure',
        subtitle: 'Unfinished planned work changes the future distribution. It is factual, not punitive.',
        icon: Icons.trending_up_rounded,
        kind: _TodayWorkSectionKind.pressure,
        items: pressureItems,
      ),
      _TodayWorkSectionVm(
        title: 'Planned for today',
        subtitle: 'Work assigned to today by your active plans, grouped by source or plan.',
        icon: Icons.menu_book_rounded,
        kind: _TodayWorkSectionKind.planned,
        items: plannedItems,
      ),
      _TodayWorkSectionVm(
        title: 'Available if there is room',
        subtitle: 'Open todos without a fixed date. They should not compete with planned work.',
        icon: Icons.inbox_rounded,
        kind: _TodayWorkSectionKind.available,
        items: availableItems,
      ),
    ];
  }

  static _RelatedFileLink? _relatedLinkForRequirement(
    StudyPlanRequirement requirement,
    Future<void> Function(_RelatedFileLink link) onOpenRelatedFile,
  ) {
    final source = requirement.plan.materialSource;
    if (source?.hasSource != true) return null;
    return _RelatedFileLink(
      title: source!.title,
      subtitle: '${source.typeLabel} • ${requirement.projectTitle}',
      icon: source.type == StudyMaterialSourceType.epubFile ? Icons.menu_book_outlined : Icons.description_outlined,
      materialSource: source,
      onOpen: onOpenRelatedFile,
    );
  }

  static _RelatedFileLink? _relatedLinkForTodo(
    TodoItem todo,
    Future<void> Function(_RelatedFileLink link) onOpenRelatedFile,
  ) {
    if (todo.documentName?.trim().isNotEmpty != true && todo.note.documentId?.trim().isNotEmpty != true) {
      return null;
    }
    return _RelatedFileLink(
      title: todo.pdfLabel,
      subtitle: todo.pageNumber == null ? 'PDF todo • ${todo.priority}' : 'PDF todo • page ${todo.pageNumber}',
      icon: Icons.picture_as_pdf_outlined,
      todo: todo,
      onOpen: onOpenRelatedFile,
    );
  }

  static List<_WeekWorkItemVm> _weekWorkItemsForDate({
    required DateTime date,
    required List<StudyPlanRequirement> requirements,
    required List<TodoItem> todos,
    required StudyPlanningRepository planningRepository,
  }) {
    final deadlineItems = <_WeekWorkItemVm>[];
    final finishItems = <_WeekWorkItemVm>[];
    final workItems = <_WeekWorkItemVm>[];
    final seenKeys = <String>{};

    void addDeadline(String label, {String? key, String? detail}) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) return;
      final dedupeKey = '${key ?? trimmed.toLowerCase()}-${_DateText.dateKey(date)}';
      if (!seenKeys.add(dedupeKey)) return;
      final cleanDetail = detail?.trim();
      final effectiveDetail = cleanDetail == null || cleanDetail.isEmpty || cleanDetail.toLowerCase() == trimmed.toLowerCase() ? null : cleanDetail;
      deadlineItems.add(_WeekWorkItemVm.deadline(trimmed, detail: effectiveDetail));
    }

    void addFinish(String label, {String? key, String? detail}) {
      final trimmed = label.trim();
      if (trimmed.isEmpty) return;
      final dedupeKey = '${key ?? trimmed.toLowerCase()}-${_DateText.dateKey(date)}';
      if (!seenKeys.add(dedupeKey)) return;
      finishItems.add(_WeekWorkItemVm.finish(trimmed, detail: detail ?? 'Planned finish'));
    }

    for (final todo in todos) {
      addDeadline(todo.title, key: 'todo-${todo.id}', detail: todo.pdfLabel == 'No source' ? 'Deadline' : todo.pdfLabel);
    }

    for (final requirement in requirements.where((item) => item.isDeadlineMarker)) {
      addDeadline(requirement.plan.title, key: 'deadline-plan-${requirement.plan.id}');
    }

    for (final plan in planningRepository.plans) {
      if (plan.isComplete) continue;
      if (plan.isDeadlineMarker) {
        final deadline = plan.deadline ?? plan.taskDate;
        if (deadline != null && _DateText.sameDate(deadline, date)) {
          addDeadline(plan.title, key: 'deadline-plan-${plan.id}');
        }
        continue;
      }
      if (!plan.isSingleTask) {
        final target = plan.deadline;
        if (target != null && _DateText.sameDate(target, date)) {
          addFinish(plan.title, key: 'finish-plan-${plan.id}', detail: 'Planned finish');
        }
      }
    }

    for (final project in planningRepository.projects) {
      final deadline = project.deadline;
      if (!project.isArchived && deadline != null && _DateText.sameDate(deadline, date)) {
        addDeadline(project.title, key: 'project-${project.id}', detail: 'Project deadline');
      }
    }

    final groupedRequirements = <String, List<StudyPlanRequirement>>{};
    for (final requirement in requirements.where((item) => !item.isDeadlineMarker)) {
      groupedRequirements.putIfAbsent(requirement.plan.id, () => <StudyPlanRequirement>[]).add(requirement);
    }

    for (final group in groupedRequirements.values) {
      if (group.isEmpty) continue;
      final first = group.first;
      workItems.add(
        _WeekWorkItemVm.work(
          first.plan.title,
          detail: _requirementGroupDetail(group),
          units: group.fold<int>(0, (sum, item) => sum + item.unitCount),
          unitNoun: first.plan.unitNounForCount(group.fold<int>(0, (sum, item) => sum + item.unitCount)),
        ),
      );
    }

    const maxItems = 2;
    final importantItems = <_WeekWorkItemVm>[...deadlineItems, ...finishItems];
    final items = <_WeekWorkItemVm>[];
    items.addAll(importantItems.take(maxItems));

    if (items.length < maxItems) {
      final remainingSlots = maxItems - items.length;
      if (workItems.length <= remainingSlots) {
        items.addAll(workItems);
      } else {
        if (remainingSlots >= 2) {
          items.add(workItems.first);
          final groupedRemainder = workItems.skip(1).toList(growable: false);
          if (groupedRemainder.isNotEmpty) items.add(_summarizeWorkItems(groupedRemainder));
        } else if (workItems.isNotEmpty) {
          items.add(_summarizeWorkItems(workItems));
        }
      }
    }

    return items;
  }

  static String _requirementGroupDetail(List<StudyPlanRequirement> group) {
    if (group.isEmpty) return '';
    final first = group.first;
    final totalUnits = group.fold<int>(0, (sum, item) => sum + item.unitCount);

    if (first.isChecklistItem) {
      if (group.length == 1) return first.rangeLabel;
      return '$totalUnits checklist ${totalUnits == 1 ? 'item' : 'items'}';
    }

    if (first.isSingleTask) return 'Task';

    if (first.plan.isRecurring) {
      return '$totalUnits ${first.plan.unitNounForCount(totalUnits)}';
    }

    final minUnit = group.map((item) => item.startUnit).reduce((a, b) => a < b ? a : b);
    final maxUnit = group.map((item) => item.endUnit).reduce((a, b) => a > b ? a : b);
    if (minUnit == maxUnit) return '${first.plan.unitLabel} $minUnit';
    return '${first.plan.unitLabel} $minUnit–$maxUnit';
  }

  static _WeekWorkItemVm _summarizeWorkItems(List<_WeekWorkItemVm> items) {
    final sourceCount = items.length;
    final unitItems = items.where((item) => item.units > 0 && item.unitNoun != null).toList(growable: false);
    String detail;
    if (unitItems.isNotEmpty && unitItems.every((item) => item.unitNoun == unitItems.first.unitNoun)) {
      final units = unitItems.fold<int>(0, (sum, item) => sum + item.units);
      final noun = unitItems.first.unitNoun!;
      detail = '$units $noun · $sourceCount ${sourceCount == 1 ? 'source' : 'sources'}';
    } else {
      detail = '$sourceCount ${sourceCount == 1 ? 'source' : 'sources'}';
    }
    return _WeekWorkItemVm.work('Reading', detail: detail);
  }

  static String _requirementTitle(StudyPlanRequirement requirement) {
    final range = requirement.rangeLabel;
    if (range == 'task' || range == 'deadline') return requirement.plan.title;
    return '${requirement.plan.title} — $range';
  }

  static String _requirementTag(StudyPlanRequirement requirement) {
    if (requirement.isDeadlineMarker) return 'Deadline';
    if (requirement.isSingleTask) return 'Task';
    if (requirement.isChecklistItem) return 'Checklist';
    return requirement.plan.unitNounForCount(requirement.unitCount);
  }

  static String _todoTag(TodoItem todo) {
    if (todo.deadline != null) return 'Deadline';
    if (todo.sourceType.contains('pdf') || todo.documentName != null) return 'PDF';
    return todo.priority;
  }

  static List<_PlanBlock> _buildPlanBlocks({
    required List<StudyPlanDebt> debts,
    required List<StudyPlanRequirement> requirements,
    required List<TodoItem> openTodos,
  }) {
    final first = debts.isNotEmpty
        ? 'Catch up: ${debts.first.plan.title}'
        : requirements.isNotEmpty
            ? _requirementTitle(requirements.first)
            : 'No fixed morning block yet';
    final second = requirements.length > 1
        ? _requirementTitle(requirements[1])
        : openTodos.isNotEmpty
            ? openTodos.first.title
            : 'Add a task from your plans';
    final third = requirements.length > 2
        ? _requirementTitle(requirements[2])
        : 'Open space for reading, writing, or review';
    final unscheduledCount = (requirements.length > 3 ? requirements.length - 3 : 0) + openTodos.length + (debts.length > 1 ? debts.length - 1 : 0);

    return <_PlanBlock>[
      _PlanBlock('Morning', first),
      _PlanBlock('Afternoon', second),
      _PlanBlock('Evening', third),
      _PlanBlock('Unscheduled', unscheduledCount == 0 ? 'No remaining candidates' : '$unscheduledCount task candidates'),
    ];
  }


  static List<_SchedulePressureVm> _buildSchedulePressures(List<StudyPlanDebt> debts) {
    return debts.map((debt) {
      final noun = debt.plan.unitNounForCount(debt.behindUnits);
      final oldPace = _formatPace(debt.originalPace, debt.plan.unitNounForCount(debt.originalPace.round().clamp(1, 999999).toInt()));
      final newPace = _formatPace(debt.currentPace, debt.plan.unitNounForCount(debt.currentPace.round().clamp(1, 999999).toInt()));
      final missedPrefix = debt.missedDays > 0
          ? '${debt.missedDays} missed ${debt.missedDays == 1 ? 'day' : 'days'}'
          : '${debt.behindUnits} $noun unfinished';
      final paceText = debt.currentPace > debt.originalPace
          ? 'Future pace increased: $newPace/day instead of $oldPace/day'
          : 'Remaining work has been redistributed into the plan';
      return _SchedulePressureVm(
        title: debt.plan.title,
        subtitle: '${debt.project.title} • $missedPrefix',
        pace: paceText,
        urgent: debt.isPastDeadline,
      );
    }).toList(growable: false);
  }

  static String _formatPace(double value, String noun) {
    final rounded = value.roundToDouble() == value ? value.toInt().toString() : value.toStringAsFixed(1);
    return '$rounded $noun';
  }

  static _RelatedFileLink? _firstRelatedFile({
    required List<StudyPlanRequirement> requirements,
    required List<TodoItem> todos,
    required Future<void> Function(_RelatedFileLink link) onOpenRelatedFile,
  }) {
    for (final todo in todos) {
      if (todo.documentName?.trim().isNotEmpty == true || todo.note.documentId?.trim().isNotEmpty == true) {
        late final _RelatedFileLink link;
        link = _RelatedFileLink(
          title: todo.pdfLabel,
          subtitle: todo.pageNumber == null ? 'PDF todo • ${todo.priority}' : 'PDF todo • page ${todo.pageNumber}',
          icon: Icons.picture_as_pdf_outlined,
          todo: todo,
          onOpen: onOpenRelatedFile,
        );
        return link;
      }
    }

    for (final requirement in requirements) {
      final source = requirement.plan.materialSource;
      if (source?.hasSource == true) {
        late final _RelatedFileLink link;
        link = _RelatedFileLink(
          title: source!.title,
          subtitle: '${source.typeLabel} • ${requirement.projectTitle}',
          icon: source.type == StudyMaterialSourceType.epubFile ? Icons.menu_book_outlined : Icons.description_outlined,
          materialSource: source,
          onOpen: onOpenRelatedFile,
        );
        return link;
      }
    }
    return null;
  }
}

class _WeekDayVm {
  const _WeekDayVm({
    required this.date,
    required this.active,
    required this.isPast,
    required this.taskCount,
    required this.doneCount,
    required this.workloadUnits,
    required this.items,
  });

  final DateTime date;
  final bool active;
  final bool isPast;
  final int taskCount;
  final int doneCount;
  final int workloadUnits;
  final List<_WeekWorkItemVm> items;

  bool get hasDeadline => items.any((item) => item.isDeadline);
  bool get hasFinish => items.any((item) => item.isFinish);
}

enum _WeekWorkKind { work, deadline, finish }

class _WeekWorkItemVm {
  const _WeekWorkItemVm._({
    required this.label,
    required this.kind,
    this.detail,
    this.units = 0,
    this.unitNoun,
  });

  factory _WeekWorkItemVm.work(String label, {String? detail, int units = 0, String? unitNoun}) {
    return _WeekWorkItemVm._(
      label: label,
      kind: _WeekWorkKind.work,
      detail: detail,
      units: units,
      unitNoun: unitNoun,
    );
  }

  factory _WeekWorkItemVm.deadline(String label, {String? detail}) {
    return _WeekWorkItemVm._(label: label, kind: _WeekWorkKind.deadline, detail: detail);
  }

  factory _WeekWorkItemVm.finish(String label, {String? detail}) {
    return _WeekWorkItemVm._(label: label, kind: _WeekWorkKind.finish, detail: detail);
  }

  final String label;
  final _WeekWorkKind kind;
  final String? detail;
  final int units;
  final String? unitNoun;

  bool get isDeadline => kind == _WeekWorkKind.deadline;
  bool get isFinish => kind == _WeekWorkKind.finish;
}

class _DeadlineSignalVm {
  const _DeadlineSignalVm({required this.title, required this.date});

  final String title;
  final DateTime date;
}

enum _TodayWorkSectionKind { critical, pressure, planned, available }

class _TodayWorkSectionVm {
  const _TodayWorkSectionVm({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.kind,
    required this.items,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final _TodayWorkSectionKind kind;
  final List<_TodayWorkItemVm> items;
}

class _TodayWorkItemVm {
  const _TodayWorkItemVm({
    required this.title,
    required this.reason,
    this.amount,
    this.sourceLabel,
    this.sourceIcon,
    this.onOpenSource,
    this.onComplete,
    this.completeLabel = 'Done',
  });

  final String title;
  final String reason;
  final String? amount;
  final String? sourceLabel;
  final IconData? sourceIcon;
  final Future<void> Function()? onOpenSource;
  final Future<void> Function()? onComplete;
  final String completeLabel;
}


enum _DailySetupItemKind { plannedWork, planPressure, deadline, availableTodo, manualReminder }

extension _DailySetupItemKindIcon on _DailySetupItemKind {
  IconData get icon {
    switch (this) {
      case _DailySetupItemKind.deadline:
        return Icons.flag_rounded;
      case _DailySetupItemKind.planPressure:
        return Icons.trending_up_rounded;
      case _DailySetupItemKind.plannedWork:
        return Icons.menu_book_rounded;
      case _DailySetupItemKind.availableTodo:
        return Icons.inbox_rounded;
      case _DailySetupItemKind.manualReminder:
        return Icons.edit_note_rounded;
    }
  }
}

enum _DailySetupPriority { must, should, extra, notToday }

extension _DailySetupPriorityLabel on _DailySetupPriority {
  String get label {
    switch (this) {
      case _DailySetupPriority.must:
        return 'Must';
      case _DailySetupPriority.should:
        return 'Should';
      case _DailySetupPriority.extra:
        return 'Extra';
      case _DailySetupPriority.notToday:
        return 'Not today';
    }
  }
}

class _DailySetupSnapshot {
  const _DailySetupSnapshot({required this.date, required this.createdAt, required this.updatedAt, required this.items});

  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<_DailySetupItemVm> items;

  List<_DailySetupItemVm> get includedItems => items.where((item) => item.included).toList(growable: false);
  int get mustCount => includedItems.where((item) => item.priority == _DailySetupPriority.must).length;
  int get shouldCount => includedItems.where((item) => item.priority == _DailySetupPriority.should).length;
  int get extraCount => includedItems.where((item) => item.priority == _DailySetupPriority.extra).length;
}

class _DailySetupItemVm {
  const _DailySetupItemVm({
    required this.id,
    required this.kind,
    required this.title,
    required this.reason,
    required this.included,
    required this.priority,
    this.detail,
    this.sourceLabel,
    this.sourceIcon,
    this.onOpenSource,
    this.onComplete,
    this.completeLabel = 'Done',
    this.manual = false,
  });

  final String id;
  final _DailySetupItemKind kind;
  final String title;
  final String? detail;
  final String reason;
  final bool included;
  final _DailySetupPriority priority;
  final String? sourceLabel;
  final IconData? sourceIcon;
  final Future<void> Function()? onOpenSource;
  final Future<void> Function()? onComplete;
  final String completeLabel;
  final bool manual;

  static List<_DailySetupItemVm> fromWorkSections(List<_TodayWorkSectionVm> sections) {
    final items = <_DailySetupItemVm>[];
    for (final section in sections) {
      for (var index = 0; index < section.items.length; index++) {
        final workItem = section.items[index];
        final kind = _kindForSection(section.kind);
        items.add(
          _DailySetupItemVm(
            id: '${section.kind.name}-$index-${workItem.title.hashCode}',
            kind: kind,
            title: workItem.title,
            detail: workItem.amount,
            reason: workItem.reason,
            included: section.kind != _TodayWorkSectionKind.available,
            priority: _priorityForSection(section.kind),
            sourceLabel: workItem.sourceLabel,
            sourceIcon: workItem.sourceIcon,
            onOpenSource: workItem.onOpenSource,
            onComplete: workItem.onComplete,
            completeLabel: workItem.completeLabel,
          ),
        );
      }
    }
    return items;
  }

  static _DailySetupItemKind _kindForSection(_TodayWorkSectionKind kind) {
    switch (kind) {
      case _TodayWorkSectionKind.critical:
        return _DailySetupItemKind.deadline;
      case _TodayWorkSectionKind.pressure:
        return _DailySetupItemKind.planPressure;
      case _TodayWorkSectionKind.planned:
        return _DailySetupItemKind.plannedWork;
      case _TodayWorkSectionKind.available:
        return _DailySetupItemKind.availableTodo;
    }
  }

  static _DailySetupPriority _priorityForSection(_TodayWorkSectionKind kind) {
    switch (kind) {
      case _TodayWorkSectionKind.critical:
        return _DailySetupPriority.must;
      case _TodayWorkSectionKind.pressure:
      case _TodayWorkSectionKind.planned:
        return _DailySetupPriority.should;
      case _TodayWorkSectionKind.available:
        return _DailySetupPriority.extra;
    }
  }
}

class _DailySetupItemDraft {
  _DailySetupItemDraft({
    required this.id,
    required this.kind,
    required this.title,
    required this.reason,
    required this.included,
    required this.priority,
    required this.manual,
    this.detail,
    this.sourceLabel,
    this.sourceIcon,
    this.onOpenSource,
    this.onComplete,
    this.completeLabel = 'Done',
  });

  factory _DailySetupItemDraft.fromVm(_DailySetupItemVm item) {
    return _DailySetupItemDraft(
      id: item.id,
      kind: item.kind,
      title: item.title,
      detail: item.detail,
      reason: item.reason,
      included: item.included,
      priority: item.priority,
      manual: item.manual,
      sourceLabel: item.sourceLabel,
      sourceIcon: item.sourceIcon,
      onOpenSource: item.onOpenSource,
      onComplete: item.onComplete,
      completeLabel: item.completeLabel,
    );
  }

  final String id;
  final _DailySetupItemKind kind;
  final String title;
  final String? detail;
  final String reason;
  final bool manual;
  final String? sourceLabel;
  final IconData? sourceIcon;
  final Future<void> Function()? onOpenSource;
  final Future<void> Function()? onComplete;
  final String completeLabel;
  bool included;
  _DailySetupPriority priority;

  _DailySetupItemVm toVm() {
    return _DailySetupItemVm(
      id: id,
      kind: kind,
      title: title,
      detail: detail,
      reason: reason,
      included: included,
      priority: priority,
      manual: manual,
      sourceLabel: sourceLabel,
      sourceIcon: sourceIcon,
      onOpenSource: onOpenSource,
      onComplete: onComplete,
      completeLabel: completeLabel,
    );
  }
}

class _TodayTaskVm {
  const _TodayTaskVm({required this.title, required this.tag, this.subtitle, this.onComplete});

  final String title;
  final String tag;
  final String? subtitle;
  final Future<void> Function()? onComplete;
}

class _RelatedFileLink {
  const _RelatedFileLink({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onOpen,
    this.todo,
    this.materialSource,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final TodoItem? todo;
  final StudyMaterialSource? materialSource;
  final Future<void> Function(_RelatedFileLink link) onOpen;
}


class _SchedulePressureVm {
  const _SchedulePressureVm({
    required this.title,
    required this.subtitle,
    required this.pace,
    required this.urgent,
  });

  final String title;
  final String subtitle;
  final String pace;
  final bool urgent;
}

class _PlanBlock {
  const _PlanBlock(this.label, this.value);

  final String label;
  final String value;
}

class _ProjectVm {
  const _ProjectVm({required this.id, required this.title, required this.subtitle, required this.progress, required this.onOpen});

  final String id;
  final String title;
  final String subtitle;
  final double progress;
  final Future<void> Function() onOpen;
}

class _InlineStatusBanner extends StatelessWidget {
  const _InlineStatusBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: chroma.soft, borderRadius: BorderRadius.circular(14), border: Border.all(color: chroma.border)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: chroma.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: _TodayText.muted)),
        ],
      ),
    );
  }
}

class _EmptyStateRow extends StatelessWidget {
  const _EmptyStateRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: chroma.accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _TodayColors.ink)),
              const SizedBox(height: 4),
              Text(subtitle, style: _TodayText.muted),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SectionIcon(icon: icon),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: _TodayText.sectionTitle)),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: chroma.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: chroma.borderStrong),
        boxShadow: [BoxShadow(color: chroma.shadow, blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: child,
    );
  }
}

class _SectionIcon extends StatelessWidget {
  const _SectionIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: chroma.soft, borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, size: 16, color: chroma.accent),
    );
  }
}

class _SmallRoundButton extends StatelessWidget {
  const _SmallRoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: chroma.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: chroma.border)),
        child: Icon(icon, size: 18, color: chroma.accent),
      ),
    );
  }
}

class _PillLabel extends StatelessWidget {
  const _PillLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    final deadline = label.toLowerCase() == 'deadline';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: deadline ? _TodayColors.deadlineSoft : chroma.soft,
        borderRadius: BorderRadius.circular(999),
        border: deadline ? Border.all(color: _TodayColors.deadlineBorder) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: deadline ? _TodayColors.deadline : _TodayColors.inkMuted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final chroma = _TodayChromaticScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: chroma.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: chroma.border)),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _TodayColors.inkMuted)),
    );
  }
}

class _DateText {
  const _DateText._();

  static DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  static String dateKey(DateTime date) {
    final normalized = dateOnly(date);
    return '${normalized.year}-${normalized.month.toString().padLeft(2, '0')}-${normalized.day.toString().padLeft(2, '0')}';
  }

  static String month(int month) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return months[month - 1];
  }

  static String shortMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  static String weekday(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  static String shortWeekday(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  static String time(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String monthDay(DateTime date) => '${date.day} ${shortMonth(date.month)}';

  static bool sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _TodayText {
  const _TodayText._();

  static const sectionTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -.2, color: _TodayColors.ink);

  static const muted = TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: _TodayColors.inkMuted);
}


class _TodayChroma {
  const _TodayChroma({
    required this.accent,
    required this.soft,
    required this.surface,
    required this.card,
    required this.navSurface,
    required this.canvas,
    required this.border,
    required this.borderStrong,
    required this.shadow,
  });

  final Color accent;
  final Color soft;
  final Color surface;
  final Color card;
  final Color navSurface;
  final Color canvas;
  final Color border;
  final Color borderStrong;
  final Color shadow;
}

class _TodayChromaticScope extends InheritedWidget {
  const _TodayChromaticScope({required this.chroma, required super.child});

  final _TodayChroma chroma;

  static _TodayChroma of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TodayChromaticScope>();
    return scope?.chroma ?? _TodayColors.monthChroma(DateTime.now().month);
  }

  @override
  bool updateShouldNotify(_TodayChromaticScope oldWidget) => chroma != oldWidget.chroma;
}

class _TodayColors {
  const _TodayColors._();

  static const canvas = Color(0xFFFCFAFF);
  static const ink = Color(0xFF19172F);
  static const inkMuted = Color(0xFF504E73);
  static const inkFaint = Color(0xFF817E9B);
  static const accent = Color(0xFF5551B8);
  static const border = Color(0xFFE5E0F1);
  static const borderStrong = Color(0xFFD8D1EC);
  static const softPurple = Color(0xFFF0EDFF);
  static const cardTint = Color(0xFFFBF9FF);
  static const activeWeekTile = Color(0xFFF0EBFF);
  static const currentWeekWash = Color(0x0B5A50CF);
  static const nextWeekWash = Color(0x0B2F80ED);

  // Calendar-week tints. Each week of the month has exactly two paper
  // tones, alternating by day, so the user can learn the month rhythm without
  // turning the ribbon into a rainbow.
  static const monthWeekOneA = Color(0xFFFBF8F0);
  static const monthWeekOneB = Color(0xFFF6F0E3);
  static const monthWeekTwoA = Color(0xFFF5F8F1);
  static const monthWeekTwoB = Color(0xFFEEF3E7);
  static const monthWeekThreeA = Color(0xFFF7F5EF);
  static const monthWeekThreeB = Color(0xFFF0ECE2);
  static const monthWeekFourA = Color(0xFFF8F4F7);
  static const monthWeekFourB = Color(0xFFF1EAF0);
  static const monthWeekFiveA = Color(0xFFFAF4EE);
  static const monthWeekFiveB = Color(0xFFF3EAE2);

  static const todayWash = Color(0xFFF2EEFF);
  static const pastDayWash = Color(0xFFF4F3F6);
  static const doneGreen = Color(0xFF20B15A);
  static const finish = Color(0xFF3866A8);
  static const finishSoft = Color(0xFFEFF5FF);
  static const finishBorder = Color(0xFFBFD1EF);
  static const deadline = Color(0xFFC03744);
  static const deadlineSoft = Color(0xFFFFF1F3);
  static const deadlineBorder = Color(0xFFF0B9C0);
  static const checkbox = Color(0xFFB7B2CC);


  static _TodayChroma monthChroma(int month) {
    final accent = monthAccent(month);
    final base = monthWeekDayTint(month, alternateTone: false, saturated: false);
    final baseAlt = monthWeekDayTint(month, alternateTone: true, saturated: false);
    return _TodayChroma(
      accent: accent,
      soft: _tint(accent, .90),
      surface: _blend(_tint(base, .42), Colors.white, .52),
      card: _blend(_tint(base, .66), Colors.white, .70).withOpacity(.95),
      navSurface: _blend(_tint(baseAlt, .76), Colors.white, .78),
      canvas: _blend(_tint(base, .72), const Color(0xFFFCFBF7), .72),
      border: _blend(accent, const Color(0xFFE8E1D6), .84),
      borderStrong: _blend(accent, const Color(0xFFDCD3C8), .72),
      shadow: accent.withOpacity(.10),
    );
  }

  static Color _tint(Color color, double amount) => Color.lerp(color, Colors.white, amount)!;

  static Color _blend(Color a, Color b, double amount) => Color.lerp(a, b, amount)!;

  static Color monthAccent(int month) {
    switch (month) {
      case 1:
        return const Color(0xFF4F6C8C); // January: winter blue slate
      case 2:
        return const Color(0xFF7A5F8B); // February: winter plum
      case 3:
        return const Color(0xFF5E8A68); // March: early spring green
      case 4:
        return const Color(0xFF7B8E48); // April: leaf olive
      case 5:
        return const Color(0xFF4F8B78); // May: fresh sage teal
      case 6:
        return const Color(0xFFA98339); // June: warm ochre
      case 7:
        return const Color(0xFFB46F46); // July: sun clay
      case 8:
        return const Color(0xFF8B7B43); // August: dry grass
      case 9:
        return const Color(0xFF9A6E3D); // September: amber
      case 10:
        return const Color(0xFF9A5B43); // October: rust
      case 11:
        return const Color(0xFF7A5A63); // November: muted berry
      case 12:
      default:
        return const Color(0xFF55726B); // December: evergreen slate
    }
  }

  static Color monthWeekDayTint(
    int month, {
    required bool alternateTone,
    required bool saturated,
  }) {
    final set = _seasonSet(month);
    final tone = alternateTone ? 1 : 0;
    switch (_seasonForMonth(month)) {
      case _CalendarSeason.winter:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFF2F5F6) : const Color(0xFFE9EEF1))
              : (tone == 0 ? const Color(0xFFF7F9FA) : const Color(0xFFF1F4F6));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF3F1F6) : const Color(0xFFEBE7F0))
            : (tone == 0 ? const Color(0xFFF8F7FA) : const Color(0xFFF2F0F6));
      case _CalendarSeason.spring:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFF1F6EF) : const Color(0xFFE8F1E5))
              : (tone == 0 ? const Color(0xFFF7FAF5) : const Color(0xFFF1F6EE));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF4F4EA) : const Color(0xFFECECD9))
            : (tone == 0 ? const Color(0xFFFAFAF5) : const Color(0xFFF4F4EA));
      case _CalendarSeason.summer:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFFAF4E7) : const Color(0xFFF3E8D2))
              : (tone == 0 ? const Color(0xFFFCF9F1) : const Color(0xFFF8F1E5));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF9EFE7) : const Color(0xFFF0DFD2))
            : (tone == 0 ? const Color(0xFFFCF7F3) : const Color(0xFFF8EEE7));
      case _CalendarSeason.autumn:
        if (set == 0) {
          return saturated
              ? (tone == 0 ? const Color(0xFFFAF1E9) : const Color(0xFFF0E2D5))
              : (tone == 0 ? const Color(0xFFFCF8F4) : const Color(0xFFF6EEE7));
        }
        return saturated
            ? (tone == 0 ? const Color(0xFFF8EEEE) : const Color(0xFFEEDDDD))
            : (tone == 0 ? const Color(0xFFFCF7F7) : const Color(0xFFF5EDED));
    }
  }

  static _CalendarSeason _seasonForMonth(int month) {
    if (month == 12 || month == 1 || month == 2) return _CalendarSeason.winter;
    if (month >= 3 && month <= 5) return _CalendarSeason.spring;
    if (month >= 6 && month <= 8) return _CalendarSeason.summer;
    return _CalendarSeason.autumn;
  }

  static int _seasonSet(int month) {
    switch (month) {
      case 1:
      case 3:
      case 5:
      case 6:
      case 8:
      case 9:
      case 11:
        return 0;
      case 2:
      case 4:
      case 7:
      case 10:
      case 12:
      default:
        return 1;
    }
  }
}

enum _CalendarSeason { winter, spring, summer, autumn }
