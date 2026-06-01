import 'dart:async';

import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';
import '../../planning/data/study_planning_repository.dart';

class StudyCalendarScreen extends StatefulWidget {
  const StudyCalendarScreen({
    super.key,
    required this.planningRepository,
    this.noteRepository,
    this.onOpenTodo,
  });

  final StudyPlanningRepository planningRepository;
  final NoteRepository? noteRepository;
  final FutureOr<void> Function(TodoItem todo)? onOpenTodo;

  @override
  State<StudyCalendarScreen> createState() => _StudyCalendarScreenState();
}

class _StudyCalendarScreenState extends State<StudyCalendarScreen> {
  late DateTime _today;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  String? _expandedItemId;
  String? _expandedGeneratedId;
  int _quickCreateRequest = 0;
  bool _createComposerOpen = false;
  bool _loaded = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _today = _CalendarDates.dateOnly(DateTime.now());
    _visibleMonth = DateTime(_today.year, _today.month);
    _selectedDate = _today;
    widget.planningRepository.addListener(_onPlanningChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.planningRepository.removeListener(_onPlanningChanged);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await widget.planningRepository.load();
      if (!mounted) return;
      setState(() => _loaded = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loaded = true;
      });
    }
  }

  void _onPlanningChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.noteRepository;
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: _CalendarColors.canvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: _CalendarColors.canvas,
        body: Center(
          child: Text(
            'Could not load calendar data.\n$_loadError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _CalendarColors.inkMuted),
          ),
        ),
      );
    }

    if (notes == null) {
      return _CalendarPageScaffold(
        child: _buildContent(context, const <TodoItem>[]),
      );
    }

    return StreamBuilder<List<TodoItem>>(
      stream: notes.watchTodos(includeCompleted: true),
      builder: (context, snapshot) {
        final openTodos = (snapshot.data ?? const <TodoItem>[])
            .where((todo) => !todo.isCompleted)
            .toList(growable: false);
        return _CalendarPageScaffold(child: _buildContent(context, openTodos));
      },
    );
  }

  Widget _buildContent(BuildContext context, List<TodoItem> openTodos) {
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month);
    final monthEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
    final gridStart = _CalendarDates.weekStart(monthStart);
    final gridEnd = _CalendarDates.weekEnd(monthEnd);
    final requirements = widget.planningRepository.requirementsForRange(
      rangeStart: gridStart,
      rangeEnd: gridEnd,
      now: DateTime.now(),
    );
    final entries = widget.planningRepository.planningEntriesForRange(
      rangeStart: gridStart,
      rangeEnd: gridEnd,
      includeDone: true,
    );
    final calendarItems = _CalendarItemIndex.build(
      requirements: requirements,
      planningEntries: entries,
      todos: openTodos,
      rangeStart: gridStart,
      rangeEnd: gridEnd,
    );
    final selectedItems = calendarItems.itemsFor(_selectedDate);
    final inboxEntries = widget.planningRepository.planningInboxEntries;
    final debts = widget.planningRepository.studyDebts(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final monthView = _CalendarMonthCard(
          visibleMonth: _visibleMonth,
          selectedDate: _selectedDate,
          today: _today,
          itemsByDay: calendarItems.itemsByDay,
          onPreviousMonth: _goToPreviousMonth,
          onNextMonth: _goToNextMonth,
          onToday: _goToToday,
          onSelectDate: _selectDate,
          onCreateForDate: _createForDate,
          createComposerOpen: _createComposerOpen,
        );
        final agenda = _CalendarAgendaPanel(
          selectedDate: _selectedDate,
          today: _today,
          items: selectedItems,
          inboxEntries: inboxEntries,
          debtCount: debts.length,
          expandedPlanningEntryId: _expandedItemId,
          expandedGeneratedId: _expandedGeneratedId,
          quickCreateRequest: _quickCreateRequest,
          createComposerOpen: _createComposerOpen,
          onAdd: () => _createForDate(_selectedDate),
          onCancelCreate: _cancelCreate,
          onTogglePlanningEntry: _togglePlanningEntry,
          onToggleGenerated: _toggleGenerated,
          onSavePlanningEntry: _savePlanningEntry,
          onCompletePlanningEntry: _completePlanningEntry,
          onMovePlanningEntry: _movePlanningEntry,
          onUnschedulePlanningEntry: _unschedulePlanningEntry,
          onArchivePlanningEntry: _archivePlanningEntry,
          onScheduleInboxEntry: (entry) => _movePlanningEntry(entry, _selectedDate),
          onCompleteRequirement: _completeRequirement,
          onArchiveRequirementPlan: _archiveRequirementPlan,
          onOpenTodo: _openTodo,
          onCreateQuick: _createQuickEntry,
        );

        if (compact) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _CalendarTopBar(onBack: () => Navigator.of(context).maybePop(), onToday: _goToToday, onAdd: () => _createForDate(_selectedDate), selectedDate: _selectedDate, creating: _createComposerOpen)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    SizedBox(height: 640, child: monthView),
                    const SizedBox(height: 16),
                    SizedBox(height: 760, child: agenda),
                  ]),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _CalendarTopBar(
              onBack: () => Navigator.of(context).maybePop(),
              onToday: _goToToday,
              onAdd: () => _createForDate(_selectedDate),
              selectedDate: _selectedDate,
              creating: _createComposerOpen,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 7, child: monthView),
                    const SizedBox(width: 18),
                    SizedBox(width: 430, child: agenda),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = _CalendarDates.dateOnly(date);
      _expandedItemId = null;
      _expandedGeneratedId = null;
      _createComposerOpen = false;
    });
  }

  void _goToToday() {
    setState(() {
      _today = _CalendarDates.dateOnly(DateTime.now());
      _selectedDate = _today;
      _visibleMonth = DateTime(_today.year, _today.month);
      _expandedItemId = null;
      _expandedGeneratedId = null;
      _createComposerOpen = false;
    });
  }

  void _goToPreviousMonth() {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1));
  }

  void _goToNextMonth() {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1));
  }

  Future<void> _createForDate(DateTime date) async {
    final day = _CalendarDates.dateOnly(date);
    setState(() {
      _selectedDate = day;
      _visibleMonth = DateTime(day.year, day.month);
      _expandedItemId = null;
      _expandedGeneratedId = null;
      _createComposerOpen = true;
      _quickCreateRequest++;
    });
  }

  Future<void> _createQuickEntry({
    required String title,
    required String kind,
    required String priority,
    required DateTime date,
    TimeOfDay? time,
    String? notes,
  }) async {
    final day = _CalendarDates.dateOnly(date);
    final startAt = time == null ? null : DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await widget.planningRepository.createPlanningEntry(
      title: title,
      notes: notes,
      kind: kind,
      priority: priority,
      date: kind == PlanningEntryKind.deadline ? null : day,
      dueAt: kind == PlanningEntryKind.deadline ? startAt ?? day : null,
      startAt: kind == PlanningEntryKind.deadline ? null : startAt,
      endAt: null,
      allDay: time == null,
    );
    if (mounted) {
      setState(() => _createComposerOpen = false);
    }
  }

  void _cancelCreate() {
    setState(() => _createComposerOpen = false);
  }

  void _togglePlanningEntry(PlanningEntry entry) {
    setState(() {
      _expandedGeneratedId = null;
      _expandedItemId = _expandedItemId == entry.id ? null : entry.id;
      _createComposerOpen = false;
      final calendarDate = entry.calendarDate;
      if (calendarDate != null) {
        _selectedDate = _CalendarDates.dateOnly(calendarDate);
        _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
      }
    });
  }

  void _toggleGenerated(StudyPlanRequirement requirement) {
    final id = _generatedRequirementId(requirement);
    setState(() {
      _expandedItemId = null;
      _expandedGeneratedId = _expandedGeneratedId == id ? null : id;
      _createComposerOpen = false;
      _selectedDate = _CalendarDates.dateOnly(requirement.date);
      _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
    });
  }

  Future<void> _savePlanningEntry({
    required PlanningEntry entry,
    required String title,
    required String? notes,
    required String kind,
    required String priority,
    required DateTime date,
    required TimeOfDay? time,
    required int? estimateMinutes,
  }) async {
    final day = _CalendarDates.dateOnly(date);
    final start = time == null ? null : DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await widget.planningRepository.updatePlanningEntry(
      entryId: entry.id,
      title: title,
      notes: notes == null || notes.trim().isEmpty ? null : notes.trim(),
      kind: kind,
      priority: priority,
      date: kind == PlanningEntryKind.deadline ? null : day,
      dueAt: kind == PlanningEntryKind.deadline ? start ?? day : null,
      startAt: kind == PlanningEntryKind.deadline ? null : start,
      endAt: null,
      allDay: time == null,
      estimateMinutes: estimateMinutes,
    );
    if (mounted) {
      setState(() {
        _selectedDate = day;
        _visibleMonth = DateTime(day.year, day.month);
      });
    }
  }

  Future<void> _completePlanningEntry(PlanningEntry entry) async {
    await widget.planningRepository.completePlanningEntry(entry.id, isDone: !entry.isDone);
  }

  Future<void> _movePlanningEntry(PlanningEntry entry, DateTime targetDate) async {
    final targetDay = _CalendarDates.dateOnly(targetDate);
    final originalStart = entry.startAt ?? entry.dueAt;
    final hasTime = !entry.allDay && originalStart != null;
    final movedStart = hasTime
        ? DateTime(targetDay.year, targetDay.month, targetDay.day, originalStart.hour, originalStart.minute)
        : targetDay;
    DateTime? movedEnd;
    if (hasTime && entry.startAt != null && entry.endAt != null && entry.endAt!.isAfter(entry.startAt!)) {
      movedEnd = movedStart.add(entry.endAt!.difference(entry.startAt!));
    }

    if (entry.isDeadline) {
      await widget.planningRepository.updatePlanningEntry(
        entryId: entry.id,
        date: null,
        dueAt: movedStart,
        startAt: null,
        endAt: null,
        allDay: !hasTime,
      );
    } else {
      await widget.planningRepository.updatePlanningEntry(
        entryId: entry.id,
        date: targetDay,
        dueAt: null,
        startAt: hasTime ? movedStart : null,
        endAt: movedEnd,
        allDay: !hasTime,
      );
    }
    if (mounted) {
      setState(() {
        _selectedDate = targetDay;
        _visibleMonth = DateTime(targetDay.year, targetDay.month);
      });
    }
  }

  Future<void> _unschedulePlanningEntry(PlanningEntry entry) async {
    await widget.planningRepository.updatePlanningEntry(
      entryId: entry.id,
      date: null,
      dueAt: null,
      startAt: null,
      endAt: null,
      allDay: true,
    );
    if (mounted) setState(() => _expandedItemId = null);
  }

  Future<void> _archivePlanningEntry(PlanningEntry entry) async {
    await widget.planningRepository.archivePlanningEntry(entry.id);
    if (mounted) setState(() => _expandedItemId = null);
  }

  Future<void> _completeRequirement(StudyPlanRequirement requirement) async {
    await widget.planningRepository.completeRequirement(requirement);
  }

  Future<void> _archiveRequirementPlan(StudyPlanRequirement requirement) async {
    await widget.planningRepository.archivePlan(requirement.plan.id);
    if (mounted) setState(() => _expandedGeneratedId = null);
  }

  Future<void> _openTodo(TodoItem todo) async {
    final open = widget.onOpenTodo;
    if (open != null) await Future<void>.value(open(todo));
  }
}

class _CalendarPageScaffold extends StatelessWidget {
  const _CalendarPageScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CalendarColors.canvas,
      body: SafeArea(child: child),
    );
  }
}

class _CalendarTopBar extends StatelessWidget {
  const _CalendarTopBar({required this.onBack, required this.onToday, required this.onAdd, required this.selectedDate, required this.creating});

  final VoidCallback onBack;
  final VoidCallback onToday;
  final VoidCallback onAdd;
  final DateTime selectedDate;
  final bool creating;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(
        children: [
          _IconCircleButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: onBack),
          const SizedBox(width: 14),
          const _CalendarGlyph(),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calendar', style: _CalendarText.title),
                SizedBox(height: 2),
                Text('Plan your time, tasks, deadlines, and study work in one place.', style: _CalendarText.muted),
              ],
            ),
          ),
          TextButton.icon(onPressed: onToday, icon: const Icon(Icons.today_rounded, size: 18), label: const Text('Today')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onAdd,
            icon: Icon(creating ? Icons.edit_calendar_rounded : Icons.add_rounded, size: 18),
            label: Text(creating ? 'Adding to ${_CalendarDates.shortWeekday(selectedDate.weekday)} ${selectedDate.day}' : 'Add'),
          ),
        ],
      ),
    );
  }
}

class _CalendarMonthCard extends StatelessWidget {
  const _CalendarMonthCard({
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.itemsByDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSelectDate,
    required this.onCreateForDate,
    required this.createComposerOpen,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final Map<String, List<_CalendarItem>> itemsByDay;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<DateTime> onCreateForDate;
  final bool createComposerOpen;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month);
    final last = DateTime(visibleMonth.year, visibleMonth.month + 1, 0);
    final gridStart = _CalendarDates.weekStart(first);
    final gridEnd = _CalendarDates.weekEnd(last);
    final days = <DateTime>[];
    var cursor = gridStart;
    while (!cursor.isAfter(gridEnd)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    return _CalendarCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_CalendarDates.monthName(visibleMonth.month)} ${visibleMonth.year}', style: _CalendarText.monthTitle),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(child: Text(_CalendarDates.fullDate(selectedDate), style: _CalendarText.muted, overflow: TextOverflow.ellipsis)),
                        if (createComposerOpen) ...[
                          const SizedBox(width: 8),
                          const _InlineStatusPill(icon: Icons.add_rounded, label: 'Adding here'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _IconCircleButton(icon: Icons.chevron_left_rounded, tooltip: 'Previous month', onTap: onPreviousMonth),
              const SizedBox(width: 6),
              _IconCircleButton(icon: Icons.chevron_right_rounded, tooltip: 'Next month', onTap: onNextMonth),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
                Expanded(
                  child: Center(
                    child: Text(
                      _CalendarDates.shortWeekday(weekday).toUpperCase(),
                      style: _CalendarText.weekday,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rows = days.length ~/ 7;
                final rowHeight = (constraints.maxHeight - (rows - 1) * 8) / rows;
                final tileHeight = rowHeight.clamp(78.0, 132.0).toDouble();
                return Column(
                  children: [
                    for (var row = 0; row < rows; row++) ...[
                      SizedBox(
                        height: tileHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var col = 0; col < 7; col++)
                              Expanded(
                                child: _CalendarDayTile(
                                  date: days[row * 7 + col],
                                  visibleMonth: visibleMonth.month,
                                  today: today,
                                  selectedDate: selectedDate,
                                  entries: itemsByDay[_CalendarDates.key(days[row * 7 + col])] ?? const <_CalendarItem>[],
                                  onSelectDate: onSelectDate,
                                  onCreateForDate: onCreateForDate,
                                  createComposerOpen: createComposerOpen,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (row != rows - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({
    required this.date,
    required this.visibleMonth,
    required this.today,
    required this.selectedDate,
    required this.entries,
    required this.onSelectDate,
    required this.onCreateForDate,
    required this.createComposerOpen,
  });

  final DateTime date;
  final int visibleMonth;
  final DateTime today;
  final DateTime selectedDate;
  final List<_CalendarItem> entries;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<DateTime> onCreateForDate;
  final bool createComposerOpen;

  @override
  Widget build(BuildContext context) {
    final inMonth = date.month == visibleMonth;
    final selected = _CalendarDates.sameDate(date, selectedDate);
    final isToday = _CalendarDates.sameDate(date, today);
    final creatingHere = selected && createComposerOpen;
    final accent = _CalendarColors.monthAccent(date.month);
    final visibleEntries = entries.take(3).toList(growable: false);
    final hidden = entries.length - visibleEntries.length;

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected
            ? Colors.white
            : inMonth
                ? _CalendarColors.monthTint(date.month, date.weekday.isEven)
                : _CalendarColors.outsideMonth,
        elevation: selected ? 9 : 0,
        shadowColor: _CalendarColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: creatingHere
                ? _CalendarColors.accent
                : selected
                    ? _CalendarColors.ink
                : isToday
                    ? accent
                    : Colors.transparent,
            width: creatingHere ? 2.2 : selected || isToday ? 1.3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelectDate(date),
          onDoubleTap: () => onCreateForDate(date),
          child: Opacity(
            opacity: inMonth ? 1 : .35,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: isToday ? 28 : null,
                        height: isToday ? 28 : null,
                        alignment: Alignment.center,
                        decoration: isToday ? BoxDecoration(color: accent, shape: BoxShape.circle) : null,
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: isToday ? Colors.white : _CalendarColors.ink,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _DayAddButton(
                        count: entries.length,
                        active: creatingHere,
                        onTap: () => onCreateForDate(date),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in visibleEntries) _MonthEntryLine(entry: entry),
                        if (hidden > 0)
                          Text('+ $hidden more', maxLines: 1, overflow: TextOverflow.ellipsis, style: _CalendarText.more),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthEntryLine extends StatelessWidget {
  const _MonthEntryLine({required this.entry});

  final _CalendarItem entry;

  @override
  Widget build(BuildContext context) {
    final color = entry.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.timeLabel == null ? entry.title : '${entry.timeLabel}  ${entry.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, height: 1.05, color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarAgendaPanel extends StatelessWidget {
  const _CalendarAgendaPanel({
    required this.selectedDate,
    required this.today,
    required this.items,
    required this.inboxEntries,
    required this.debtCount,
    required this.expandedPlanningEntryId,
    required this.expandedGeneratedId,
    required this.quickCreateRequest,
    required this.createComposerOpen,
    required this.onAdd,
    required this.onCancelCreate,
    required this.onTogglePlanningEntry,
    required this.onToggleGenerated,
    required this.onSavePlanningEntry,
    required this.onCompletePlanningEntry,
    required this.onMovePlanningEntry,
    required this.onUnschedulePlanningEntry,
    required this.onArchivePlanningEntry,
    required this.onScheduleInboxEntry,
    required this.onCompleteRequirement,
    required this.onArchiveRequirementPlan,
    required this.onOpenTodo,
    required this.onCreateQuick,
  });

  final DateTime selectedDate;
  final DateTime today;
  final List<_CalendarItem> items;
  final List<PlanningEntry> inboxEntries;
  final int debtCount;
  final String? expandedPlanningEntryId;
  final String? expandedGeneratedId;
  final int quickCreateRequest;
  final bool createComposerOpen;
  final VoidCallback onAdd;
  final VoidCallback onCancelCreate;
  final ValueChanged<PlanningEntry> onTogglePlanningEntry;
  final ValueChanged<StudyPlanRequirement> onToggleGenerated;
  final Future<void> Function({
    required PlanningEntry entry,
    required String title,
    required String? notes,
    required String kind,
    required String priority,
    required DateTime date,
    required TimeOfDay? time,
    required int? estimateMinutes,
  }) onSavePlanningEntry;
  final ValueChanged<PlanningEntry> onCompletePlanningEntry;
  final Future<void> Function(PlanningEntry entry, DateTime targetDate) onMovePlanningEntry;
  final ValueChanged<PlanningEntry> onUnschedulePlanningEntry;
  final ValueChanged<PlanningEntry> onArchivePlanningEntry;
  final ValueChanged<PlanningEntry> onScheduleInboxEntry;
  final ValueChanged<StudyPlanRequirement> onCompleteRequirement;
  final ValueChanged<StudyPlanRequirement> onArchiveRequirementPlan;
  final ValueChanged<TodoItem> onOpenTodo;
  final Future<void> Function({
    required String title,
    required String kind,
    required String priority,
    required DateTime date,
    TimeOfDay? time,
    String? notes,
  }) onCreateQuick;

  @override
  Widget build(BuildContext context) {
    final isToday = _CalendarDates.sameDate(selectedDate, today);
    final scheduledCount = items.length;
    final hasInbox = inboxEntries.isNotEmpty || debtCount > 0;

    return _CalendarCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _CalendarColors.monthAccent(selectedDate.month).withOpacity(.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text('${selectedDate.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _CalendarColors.monthAccent(selectedDate.month))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isToday ? 'Today' : _CalendarDates.weekdayName(selectedDate.weekday), style: _CalendarText.sectionTitle),
                      const SizedBox(height: 3),
                      Text('${_CalendarDates.fullDate(selectedDate)} · $scheduledCount planned', style: _CalendarText.muted),
                    ],
                  ),
                ),
                _IconCircleButton(icon: Icons.add_rounded, tooltip: 'Add to this day', onTap: onAdd),
              ],
            ),
          ),
          const Divider(height: 1, color: _CalendarColors.border),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (createComposerOpen)
                        _QuickCreateCard(
                          date: selectedDate,
                          focusRequest: quickCreateRequest,
                          onCancel: onCancelCreate,
                          onCreate: onCreateQuick,
                        )
                      else
                        _CreatePromptCard(
                          date: selectedDate,
                          onAdd: onAdd,
                        ),
                      const SizedBox(height: 14),
                      _AgendaSectionHeader(title: 'Scheduled', trailing: scheduledCount == 0 ? 'Clear' : '$scheduledCount items'),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        const _CalendarEmptyState(
                          icon: Icons.calendar_today_outlined,
                          title: 'Nothing planned here',
                          message: 'Add a task, event, reminder, or deadline to this date.',
                        )
                      else
                        for (final item in items) ...[
                          _CalendarAgendaItemCard(
                            item: item,
                            expandedPlanningEntryId: expandedPlanningEntryId,
                            expandedGeneratedId: expandedGeneratedId,
                            selectedDate: selectedDate,
                            onTogglePlanningEntry: onTogglePlanningEntry,
                            onToggleGenerated: onToggleGenerated,
                            onSavePlanningEntry: onSavePlanningEntry,
                            onCompletePlanningEntry: onCompletePlanningEntry,
                            onMovePlanningEntry: onMovePlanningEntry,
                            onUnschedulePlanningEntry: onUnschedulePlanningEntry,
                            onArchivePlanningEntry: onArchivePlanningEntry,
                            onCompleteRequirement: onCompleteRequirement,
                            onArchiveRequirementPlan: onArchiveRequirementPlan,
                            onOpenTodo: onOpenTodo,
                          ),
                          const SizedBox(height: 8),
                        ],
                      const SizedBox(height: 8),
                      _AgendaSectionHeader(title: 'Needs scheduling', trailing: hasInbox ? '${inboxEntries.length + debtCount} open' : 'All clear'),
                      const SizedBox(height: 8),
                      if (!hasInbox)
                        const _CalendarEmptyState(
                          icon: Icons.check_circle_outline_rounded,
                          title: 'Nothing loose',
                          message: 'Inbox items and missed generated work will appear here.',
                        )
                      else ...[
                        if (debtCount > 0)
                          _AttentionRow(
                            icon: Icons.warning_amber_rounded,
                            title: '$debtCount generated plan item${debtCount == 1 ? '' : 's'} behind',
                            subtitle: 'Review the study plan distribution before the deadline.',
                          ),
                        for (final entry in inboxEntries.take(8))
                          _InboxEntryRow(entry: entry, onSchedule: () => onScheduleInboxEntry(entry)),
                      ],
                    ]),
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

class _CreatePromptCard extends StatelessWidget {
  const _CreatePromptCard({required this.date, required this.onAdd});

  final DateTime date;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _CalendarColors.subtleSurface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _CalendarColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: _CalendarColors.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.add_rounded, color: _CalendarColors.accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add something to ${_CalendarDates.shortWeekday(date.weekday)} ${date.day}', style: _CalendarText.itemTitle),
                    const SizedBox(height: 3),
                    const Text('Task, event, reminder, or deadline', style: _CalendarText.itemSubtitle),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _CalendarColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickCreateCard extends StatefulWidget {
  const _QuickCreateCard({
    required this.date,
    required this.focusRequest,
    required this.onCancel,
    required this.onCreate,
  });

  final DateTime date;
  final int focusRequest;
  final VoidCallback onCancel;
  final Future<void> Function({
    required String title,
    required String kind,
    required String priority,
    required DateTime date,
    TimeOfDay? time,
    String? notes,
  }) onCreate;

  @override
  State<_QuickCreateCard> createState() => _QuickCreateCardState();
}

class _QuickCreateCardState extends State<_QuickCreateCard> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  String _kind = PlanningEntryKind.task;
  String _priority = PlanningEntryPriority.normal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _QuickCreateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRequest != widget.focusRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _CalendarColors.accent, width: 1.7),
        boxShadow: const [BoxShadow(color: _CalendarColors.shadow, blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _InlineStatusPill(icon: Icons.edit_calendar_rounded, label: 'Creating'),
              const SizedBox(width: 8),
              Expanded(child: Text(_CalendarDates.fullDate(widget.date), maxLines: 1, overflow: TextOverflow.ellipsis, style: _CalendarText.mutedStrong)),
              TextButton(onPressed: _saving ? null : widget.onCancel, child: const Text('Cancel')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  focusNode: _titleFocus,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _CalendarColors.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'What do you want to plan?',
                    prefixIcon: const Icon(Icons.add_task_rounded, size: 19),
                    filled: true,
                    fillColor: _CalendarColors.subtleSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _CalendarColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _CalendarColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _CalendarColors.accent, width: 1.5)),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _time,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '15:00',
                    filled: true,
                    fillColor: _CalendarColors.subtleSurface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _CalendarColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _CalendarColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _CalendarColors.accent, width: 1.5)),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in PlanningEntryKind.values)
                _ChoicePill(label: PlanningEntryKind.label(kind), selected: _kind == kind, onTap: () => setState(() => _kind = kind)),
              _ChoicePill(label: 'High priority', selected: _priority == PlanningEntryPriority.high, onTap: () => setState(() => _priority = _priority == PlanningEntryPriority.high ? PlanningEntryPriority.normal : PlanningEntryPriority.high)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onCreate(
        title: title,
        kind: _kind,
        priority: _priority,
        date: widget.date,
        time: _CalendarDates.tryParseTime(_time.text),
      );
      if (!mounted) return;
      _title.clear();
      _time.clear();
      setState(() {
        _kind = PlanningEntryKind.task;
        _priority = PlanningEntryPriority.normal;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _InlineStatusPill extends StatelessWidget {
  const _InlineStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _CalendarColors.accent.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _CalendarColors.accent.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _CalendarColors.accent),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: _CalendarColors.accent)),
        ],
      ),
    );
  }
}

class _DayAddButton extends StatelessWidget {
  const _DayAddButton({required this.count, required this.active, required this.onTap});

  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? _CalendarColors.accent : _CalendarColors.ink.withOpacity(.045),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: count > 0 ? 7 : 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 13, color: active ? Colors.white : _CalendarColors.inkMuted),
              if (count > 0) ...[
                const SizedBox(width: 3),
                Text('$count', style: TextStyle(fontSize: 10, height: 1, fontWeight: FontWeight.w900, color: active ? Colors.white : _CalendarColors.inkMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarAgendaItemCard extends StatelessWidget {
  const _CalendarAgendaItemCard({
    required this.item,
    required this.expandedPlanningEntryId,
    required this.expandedGeneratedId,
    required this.selectedDate,
    required this.onTogglePlanningEntry,
    required this.onToggleGenerated,
    required this.onSavePlanningEntry,
    required this.onCompletePlanningEntry,
    required this.onMovePlanningEntry,
    required this.onUnschedulePlanningEntry,
    required this.onArchivePlanningEntry,
    required this.onCompleteRequirement,
    required this.onArchiveRequirementPlan,
    required this.onOpenTodo,
  });

  final _CalendarItem item;
  final String? expandedPlanningEntryId;
  final String? expandedGeneratedId;
  final DateTime selectedDate;
  final ValueChanged<PlanningEntry> onTogglePlanningEntry;
  final ValueChanged<StudyPlanRequirement> onToggleGenerated;
  final Future<void> Function({
    required PlanningEntry entry,
    required String title,
    required String? notes,
    required String kind,
    required String priority,
    required DateTime date,
    required TimeOfDay? time,
    required int? estimateMinutes,
  }) onSavePlanningEntry;
  final ValueChanged<PlanningEntry> onCompletePlanningEntry;
  final Future<void> Function(PlanningEntry entry, DateTime targetDate) onMovePlanningEntry;
  final ValueChanged<PlanningEntry> onUnschedulePlanningEntry;
  final ValueChanged<PlanningEntry> onArchivePlanningEntry;
  final ValueChanged<StudyPlanRequirement> onCompleteRequirement;
  final ValueChanged<StudyPlanRequirement> onArchiveRequirementPlan;
  final ValueChanged<TodoItem> onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final entry = item.planningEntry;
    final requirement = item.requirement;
    final todo = item.todo;
    final expandedEntry = entry != null && expandedPlanningEntryId == entry.id;
    final expandedRequirement = requirement != null && expandedGeneratedId == _generatedRequirementId(requirement);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: expandedEntry || expandedRequirement ? Colors.white : _CalendarColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: expandedEntry || expandedRequirement ? _CalendarColors.accent : _CalendarColors.border),
        boxShadow: expandedEntry || expandedRequirement ? const [BoxShadow(color: _CalendarColors.shadow, blurRadius: 18, offset: Offset(0, 10))] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              if (entry != null) onTogglePlanningEntry(entry);
              if (requirement != null) onToggleGenerated(requirement);
              if (todo != null) onOpenTodo(todo);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
              child: Row(
                children: [
                  Container(width: 7, height: 34, decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(99))),
                  const SizedBox(width: 11),
                  if (item.timeLabel != null)
                    SizedBox(width: 58, child: Text(item.timeLabel!, style: _CalendarText.time)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: item.isDone ? _CalendarText.itemTitleDone : _CalendarText.itemTitle),
                        const SizedBox(height: 3),
                        Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: _CalendarText.itemSubtitle),
                      ],
                    ),
                  ),
                  Icon(expandedEntry || expandedRequirement ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: _CalendarColors.inkFaint),
                ],
              ),
            ),
          ),
          if (expandedEntry && entry != null)
            _PlanningEntryInlineEditor(
              entry: entry,
              selectedDate: selectedDate,
              onSave: onSavePlanningEntry,
              onComplete: () => onCompletePlanningEntry(entry),
              onMove: (date) => onMovePlanningEntry(entry, date),
              onUnschedule: () => onUnschedulePlanningEntry(entry),
              onRemove: () => onArchivePlanningEntry(entry),
            ),
          if (expandedRequirement && requirement != null)
            _GeneratedRequirementEditor(
              requirement: requirement,
              onComplete: () => onCompleteRequirement(requirement),
              onRemovePlan: () => onArchiveRequirementPlan(requirement),
            ),
        ],
      ),
    );
  }
}

class _PlanningEntryInlineEditor extends StatefulWidget {
  const _PlanningEntryInlineEditor({
    required this.entry,
    required this.selectedDate,
    required this.onSave,
    required this.onComplete,
    required this.onMove,
    required this.onUnschedule,
    required this.onRemove,
  });

  final PlanningEntry entry;
  final DateTime selectedDate;
  final Future<void> Function({
    required PlanningEntry entry,
    required String title,
    required String? notes,
    required String kind,
    required String priority,
    required DateTime date,
    required TimeOfDay? time,
    required int? estimateMinutes,
  }) onSave;
  final VoidCallback onComplete;
  final ValueChanged<DateTime> onMove;
  final VoidCallback onUnschedule;
  final VoidCallback onRemove;

  @override
  State<_PlanningEntryInlineEditor> createState() => _PlanningEntryInlineEditorState();
}

class _PlanningEntryInlineEditorState extends State<_PlanningEntryInlineEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _time;
  late final TextEditingController _estimate;
  late String _kind;
  late String _priority;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.entry.title);
    _notes = TextEditingController(text: widget.entry.notes ?? '');
    _time = TextEditingController(text: _timeText(widget.entry));
    _estimate = TextEditingController(text: widget.entry.estimateMinutes?.toString() ?? '');
    _kind = widget.entry.kind;
    _priority = widget.entry.priority;
  }

  @override
  void didUpdateWidget(covariant _PlanningEntryInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id || oldWidget.entry.updatedAt != widget.entry.updatedAt) {
      _title.text = widget.entry.title;
      _notes.text = widget.entry.notes ?? '';
      _time.text = _timeText(widget.entry);
      _estimate.text = widget.entry.estimateMinutes?.toString() ?? '';
      _kind = widget.entry.kind;
      _priority = widget.entry.priority;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _time.dispose();
    _estimate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tomorrow = _CalendarDates.dateOnly(DateTime.now().add(const Duration(days: 1)));
    final nextWeek = _CalendarDates.dateOnly(DateTime.now().add(const Duration(days: 7)));
    return Container(
      decoration: const BoxDecoration(
        color: _CalendarColors.editor,
        border: Border(top: BorderSide(color: _CalendarColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title', isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _notes, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes', isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 100, child: TextField(controller: _time, decoration: const InputDecoration(labelText: 'Time', hintText: '15:00', isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              SizedBox(width: 110, child: TextField(controller: _estimate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes', isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final kind in PlanningEntryKind.values)
                      _ChoicePill(label: PlanningEntryKind.label(kind), selected: _kind == kind, onTap: () => setState(() => _kind = kind)),
                    _ChoicePill(label: 'High', selected: _priority == PlanningEntryPriority.high, onTap: () => setState(() => _priority = _priority == PlanningEntryPriority.high ? PlanningEntryPriority.normal : PlanningEntryPriority.high)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.check_rounded, size: 18), label: const Text('Save')),
              OutlinedButton.icon(onPressed: widget.onComplete, icon: Icon(widget.entry.isDone ? Icons.undo_rounded : Icons.check_circle_outline_rounded, size: 18), label: Text(widget.entry.isDone ? 'Reopen' : 'Done')),
              OutlinedButton.icon(onPressed: () => widget.onMove(widget.selectedDate), icon: const Icon(Icons.ads_click_rounded, size: 18), label: const Text('Selected day')),
              OutlinedButton.icon(onPressed: () => widget.onMove(tomorrow), icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: const Text('Tomorrow')),
              OutlinedButton.icon(onPressed: () => widget.onMove(nextWeek), icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 18), label: const Text('Next week')),
              OutlinedButton.icon(onPressed: widget.onUnschedule, icon: const Icon(Icons.inbox_rounded, size: 18), label: const Text('Inbox')),
              TextButton.icon(onPressed: widget.onRemove, icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Remove')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        entry: widget.entry,
        title: title,
        notes: _notes.text,
        kind: _kind,
        priority: _priority,
        date: widget.selectedDate,
        time: _CalendarDates.tryParseTime(_time.text),
        estimateMinutes: int.tryParse(_estimate.text.trim()),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _timeText(PlanningEntry entry) {
    final value = entry.startAt ?? entry.dueAt;
    if (value == null || entry.allDay) return '';
    return _CalendarDates.time(value);
  }
}

class _GeneratedRequirementEditor extends StatelessWidget {
  const _GeneratedRequirementEditor({required this.requirement, required this.onComplete, required this.onRemovePlan});

  final StudyPlanRequirement requirement;
  final VoidCallback onComplete;
  final VoidCallback onRemovePlan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: const BoxDecoration(color: _CalendarColors.editor, border: Border(top: BorderSide(color: _CalendarColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(requirement.projectTitle, style: _CalendarText.itemSubtitle),
          const SizedBox(height: 4),
          Text(requirement.isDeadlineMarker ? 'Deadline marker' : requirement.rangeLabel, style: _CalendarText.muted),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(onPressed: onComplete, icon: const Icon(Icons.check_circle_outline_rounded, size: 18), label: const Text('Mark done')),
              OutlinedButton.icon(onPressed: onRemovePlan, icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Remove generated plan')),
            ],
          ),
        ],
      ),
    );
  }
}

class _InboxEntryRow extends StatelessWidget {
  const _InboxEntryRow({required this.entry, required this.onSchedule});

  final PlanningEntry entry;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(color: _CalendarColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: _CalendarColors.border)),
      child: Row(
        children: [
          const Icon(Icons.inbox_rounded, size: 18, color: _CalendarColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _CalendarText.itemTitle),
                const SizedBox(height: 2),
                Text('${PlanningEntryKind.label(entry.kind)} · ${PlanningEntryPriority.label(entry.priority)}', style: _CalendarText.itemSubtitle),
              ],
            ),
          ),
          TextButton(onPressed: onSchedule, child: const Text('Schedule')),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _CalendarColors.warningSurface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _CalendarColors.warningBorder)),
      child: Row(
        children: [
          Icon(icon, color: _CalendarColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _CalendarText.itemTitle),
                const SizedBox(height: 2),
                Text(subtitle, style: _CalendarText.itemSubtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaSectionHeader extends StatelessWidget {
  const _AgendaSectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: _CalendarText.sectionSmall)),
        Text(trailing, style: _CalendarText.mutedStrong),
      ],
    );
  }
}

class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _CalendarColors.subtleSurface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _CalendarColors.border)),
      child: Row(
        children: [
          Icon(icon, color: _CalendarColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _CalendarText.itemTitle),
                const SizedBox(height: 2),
                Text(message, style: _CalendarText.itemSubtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _CalendarColors.border),
        boxShadow: const [BoxShadow(color: _CalendarColors.shadow, blurRadius: 28, offset: Offset(0, 18))],
      ),
      child: child,
    );
  }
}

class _CalendarGlyph extends StatelessWidget {
  const _CalendarGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: _CalendarColors.accent.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
      child: const Icon(Icons.calendar_month_rounded, color: _CalendarColors.accent, size: 21),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _CalendarColors.subtleSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _CalendarColors.border)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: _CalendarColors.ink)),
        ),
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _CalendarColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? _CalendarColors.ink : _CalendarColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? Colors.white : _CalendarColors.inkMuted)),
      ),
    );
  }
}

class _CalendarItemIndex {
  const _CalendarItemIndex(this.itemsByDay);

  final Map<String, List<_CalendarItem>> itemsByDay;

  static _CalendarItemIndex build({
    required List<StudyPlanRequirement> requirements,
    required List<PlanningEntry> planningEntries,
    required List<TodoItem> todos,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final map = <String, List<_CalendarItem>>{};

    void add(DateTime date, _CalendarItem item) {
      final day = _CalendarDates.dateOnly(date);
      if (day.isBefore(rangeStart) || day.isAfter(rangeEnd)) return;
      map.putIfAbsent(_CalendarDates.key(day), () => <_CalendarItem>[]).add(item);
    }

    for (final requirement in requirements) {
      add(requirement.date, _CalendarItem.fromRequirement(requirement));
    }

    for (final entry in planningEntries) {
      final date = entry.calendarDate;
      if (date == null) continue;
      add(date, _CalendarItem.fromPlanningEntry(entry));
    }

    for (final todo in todos) {
      final deadline = todo.deadline;
      if (deadline == null) continue;
      add(deadline, _CalendarItem.fromTodo(todo));
    }

    for (final dayItems in map.values) {
      dayItems.sort((a, b) {
        final rankCompare = a.rank.compareTo(b.rank);
        if (rankCompare != 0) return rankCompare;
        final timeCompare = _CalendarDates.compareNullable(a.sortAt, b.sortAt);
        if (timeCompare != 0) return timeCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    return _CalendarItemIndex(map);
  }

  List<_CalendarItem> itemsFor(DateTime date) => itemsByDay[_CalendarDates.key(date)] ?? const <_CalendarItem>[];
}

class _CalendarItem {
  const _CalendarItem({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.rank,
    this.timeLabel,
    this.sortAt,
    this.isDone = false,
    this.planningEntry,
    this.requirement,
    this.todo,
  });

  final String title;
  final String subtitle;
  final Color color;
  final int rank;
  final String? timeLabel;
  final DateTime? sortAt;
  final bool isDone;
  final PlanningEntry? planningEntry;
  final StudyPlanRequirement? requirement;
  final TodoItem? todo;

  factory _CalendarItem.fromPlanningEntry(PlanningEntry entry) {
    final time = _CalendarDates.timeRangeForEntry(entry);
    return _CalendarItem(
      title: entry.title,
      subtitle: '${PlanningEntryKind.label(entry.kind)} · ${PlanningEntryPriority.label(entry.priority)}${entry.notes == null ? '' : ' · ${entry.notes}'}',
      color: entry.isDone
          ? _CalendarColors.done
          : entry.isDeadline
              ? _CalendarColors.deadline
              : entry.isEvent
                  ? _CalendarColors.event
                  : _CalendarColors.task,
      rank: entry.isDeadline ? 0 : entry.isEvent ? 1 : 2,
      timeLabel: time,
      sortAt: entry.calendarDate,
      isDone: entry.isDone,
      planningEntry: entry,
    );
  }

  factory _CalendarItem.fromRequirement(StudyPlanRequirement requirement) {
    final finish = !requirement.isDeadlineMarker && requirement.plan.deadline != null && _CalendarDates.sameDate(requirement.plan.deadline!, requirement.date);
    return _CalendarItem(
      title: requirement.plan.title,
      subtitle: requirement.isDeadlineMarker ? requirement.projectTitle : '${requirement.projectTitle} · ${requirement.rangeLabel}',
      color: requirement.isDeadlineMarker
          ? _CalendarColors.deadline
          : finish
              ? _CalendarColors.finish
              : _CalendarColors.study,
      rank: requirement.isDeadlineMarker ? 0 : finish ? 1 : 3,
      timeLabel: requirement.timeLabel,
      sortAt: requirement.sortAt,
      requirement: requirement,
    );
  }

  factory _CalendarItem.fromTodo(TodoItem todo) {
    return _CalendarItem(
      title: todo.title,
      subtitle: todo.pdfLabel,
      color: _CalendarColors.deadline,
      rank: 0,
      sortAt: todo.deadline,
      todo: todo,
    );
  }
}

class _CalendarDates {
  static DateTime dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  static String key(DateTime date) {
    final day = dateOnly(date);
    return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }

  static bool sameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime weekStart(DateTime value) => dateOnly(value).subtract(Duration(days: dateOnly(value).weekday - DateTime.monday));

  static DateTime weekEnd(DateTime value) => weekStart(value).add(const Duration(days: 6));

  static int compareNullable(DateTime? a, DateTime? b) {
    if (a != null && b != null) return a.compareTo(b);
    if (a != null) return -1;
    if (b != null) return 1;
    return 0;
  }

  static String monthName(int month) {
    const names = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return names[(month - 1).clamp(0, 11)];
  }

  static String shortWeekday(int weekday) {
    const names = <int, String>{1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    return names[weekday] ?? 'Mon';
  }

  static String weekdayName(int weekday) {
    const names = <int, String>{1: 'Monday', 2: 'Tuesday', 3: 'Wednesday', 4: 'Thursday', 5: 'Friday', 6: 'Saturday', 7: 'Sunday'};
    return names[weekday] ?? 'Monday';
  }

  static String fullDate(DateTime date) => '${weekdayName(date.weekday)}, ${date.day} ${monthName(date.month)}';

  static String time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? tryParseTime(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll('.', ':');
    final parts = normalized.split(':');
    if (parts.isEmpty || parts.length > 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = parts.length == 2 ? int.tryParse(parts[1]) : 0;
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String? timeRangeForEntry(PlanningEntry entry) {
    final start = entry.startAt ?? entry.dueAt;
    if (start == null || entry.allDay) return null;
    final end = entry.endAt;
    if (end != null && end.isAfter(start)) return '${time(start)}–${time(end)}';
    return time(start);
  }
}

String _generatedRequirementId(StudyPlanRequirement requirement) {
  return '${requirement.plan.id}:${_CalendarDates.key(requirement.date)}:${requirement.startUnit}:${requirement.endUnit}:${requirement.checklistIndex ?? -1}';
}

class _CalendarColors {
  static const Color canvas = Color(0xFFF6F4EE);
  static const Color card = Color(0xFFFEFDF9);
  static const Color subtleSurface = Color(0xFFF8F6F1);
  static const Color editor = Color(0xFFFBFAF6);
  static const Color border = Color(0xFFE2DED2);
  static const Color ink = Color(0xFF191A23);
  static const Color inkMuted = Color(0xFF666979);
  static const Color inkFaint = Color(0xFF9A9AA7);
  static const Color accent = Color(0xFF2F776A);
  static const Color task = Color(0xFF1D315F);
  static const Color event = Color(0xFF5E5AA8);
  static const Color study = Color(0xFF2F776A);
  static const Color deadline = Color(0xFFB55445);
  static const Color finish = Color(0xFFC1842B);
  static const Color done = Color(0xFF78948B);
  static const Color warning = Color(0xFFC1842B);
  static const Color warningSurface = Color(0xFFFFF6E1);
  static const Color warningBorder = Color(0xFFEBCB8A);
  static const Color outsideMonth = Color(0xFFEDEAE2);
  static const Color shadow = Color(0x1F1A1A1A);

  static Color monthAccent(int month) {
    switch (month) {
      case 12:
      case 1:
      case 2:
        return const Color(0xFF557FA3);
      case 3:
      case 4:
      case 5:
        return const Color(0xFF2F776A);
      case 6:
      case 7:
      case 8:
        return const Color(0xFFC1842B);
      default:
        return const Color(0xFFB55445);
    }
  }

  static Color monthTint(int month, bool alternate) {
    final accent = monthAccent(month);
    return Color.lerp(accent, Colors.white, alternate ? .90 : .94) ?? card;
  }
}

class _CalendarText {
  static const TextStyle title = TextStyle(fontSize: 20, height: 1, fontWeight: FontWeight.w900, color: _CalendarColors.ink, letterSpacing: -.35);
  static const TextStyle monthTitle = TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w900, color: _CalendarColors.ink, letterSpacing: -.7);
  static const TextStyle sectionTitle = TextStyle(fontSize: 21, height: 1, fontWeight: FontWeight.w900, color: _CalendarColors.ink, letterSpacing: -.3);
  static const TextStyle sectionSmall = TextStyle(fontSize: 13, height: 1, fontWeight: FontWeight.w900, color: _CalendarColors.ink, letterSpacing: -.1);
  static const TextStyle muted = TextStyle(fontSize: 12.5, height: 1.25, fontWeight: FontWeight.w600, color: _CalendarColors.inkMuted);
  static const TextStyle mutedStrong = TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w900, color: _CalendarColors.inkFaint);
  static const TextStyle weekday = TextStyle(fontSize: 11, height: 1, fontWeight: FontWeight.w900, color: _CalendarColors.inkFaint, letterSpacing: .5);
  static const TextStyle count = TextStyle(fontSize: 10, height: 1, fontWeight: FontWeight.w900, color: _CalendarColors.inkMuted);
  static const TextStyle more = TextStyle(fontSize: 10, height: 1.1, fontWeight: FontWeight.w900, color: _CalendarColors.inkFaint);
  static const TextStyle time = TextStyle(fontSize: 12, height: 1, fontWeight: FontWeight.w900, color: _CalendarColors.inkMuted);
  static const TextStyle itemTitle = TextStyle(fontSize: 13.5, height: 1.1, fontWeight: FontWeight.w900, color: _CalendarColors.ink);
  static const TextStyle itemTitleDone = TextStyle(fontSize: 13.5, height: 1.1, fontWeight: FontWeight.w900, color: _CalendarColors.inkFaint, decoration: TextDecoration.lineThrough);
  static const TextStyle itemSubtitle = TextStyle(fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w700, color: _CalendarColors.inkMuted);
}
