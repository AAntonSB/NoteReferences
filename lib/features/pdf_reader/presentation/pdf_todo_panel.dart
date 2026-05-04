import 'dart:async';

import 'package:flutter/material.dart';

import '../../notes/data/note_repository.dart';

enum _TodoScopeFilter { allPdfs, currentPdf }

enum _TodoStatusFilter { active, all, completed }

enum _TodoDeadlineFilter { all, overdue, dueSoon, noDeadline, withDeadline }

enum _TodoPriorityFilter { all, low, medium, high }

enum _TodoSourceFilter { all, pdfText, pdfFreeform, sidecar, document }

enum _TodoSortMode { deadline, priority, updated, pdfName, source }

enum _TodoActionDropdownMode { actions, calendar }

class PdfTodoPanel extends StatefulWidget {
  final NoteRepository noteRepository;
  final String currentDocumentId;
  final ValueChanged<TodoItem> onJumpToTodo;
  final ValueChanged<TodoItem>? onConvertToProjectTask;
  final VoidCallback? onClose;

  const PdfTodoPanel({
    super.key,
    required this.noteRepository,
    required this.currentDocumentId,
    required this.onJumpToTodo,
    this.onConvertToProjectTask,
    this.onClose,
  });

  @override
  State<PdfTodoPanel> createState() => _PdfTodoPanelState();
}

class _PdfTodoPanelState extends State<PdfTodoPanel> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _panelKey = GlobalKey();

  TodoItem? _actionTodo;
  Rect? _actionAnchorRect;
  _TodoActionDropdownMode _actionDropdownMode = _TodoActionDropdownMode.actions;

  _TodoScopeFilter _scopeFilter = _TodoScopeFilter.allPdfs;
  _TodoStatusFilter _statusFilter = _TodoStatusFilter.active;
  _TodoDeadlineFilter _deadlineFilter = _TodoDeadlineFilter.all;
  _TodoPriorityFilter _priorityFilter = _TodoPriorityFilter.all;
  _TodoSourceFilter _sourceFilter = _TodoSourceFilter.all;
  _TodoSortMode _sortMode = _TodoSortMode.deadline;

  bool _filtersExpanded = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _clearTodoActionDropdown();
    _searchController.dispose();
    super.dispose();
  }

  bool get _includeCompletedInStream {
    return _statusFilter != _TodoStatusFilter.active;
  }

  String? get _streamDocumentId {
    return _scopeFilter == _TodoScopeFilter.currentPdf
        ? widget.currentDocumentId
        : null;
  }

  bool get _hasActiveFilters {
    return _query.isNotEmpty ||
        _scopeFilter != _TodoScopeFilter.allPdfs ||
        _statusFilter != _TodoStatusFilter.active ||
        _deadlineFilter != _TodoDeadlineFilter.all ||
        _priorityFilter != _TodoPriorityFilter.all ||
        _sourceFilter != _TodoSourceFilter.all ||
        _sortMode != _TodoSortMode.deadline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: KeyedSubtree(
        key: _panelKey,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: StreamBuilder<List<TodoItem>>(
                stream: widget.noteRepository.watchTodos(
                  documentId: _streamDocumentId,
                  includeCompleted: _includeCompletedInStream,
                ),
                builder: (context, snapshot) {
                  final rawTodos = snapshot.data ?? const <TodoItem>[];
                  final visibleTodos = _sortTodos(_filterTodos(rawTodos));
                  final stats = _TodoStats.from(rawTodos);
                  final groups = _groupByPdf(visibleTodos);

                  return Column(
                    children: [
                      _buildHeader(context, stats),
                      _buildPrimaryControls(),
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: _buildAdvancedFilters(),
                        crossFadeState: _filtersExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 160),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child:
                            snapshot.connectionState == ConnectionState.waiting
                            ? const Center(child: CircularProgressIndicator())
                            : groups.isEmpty
                            ? _TodoEmptyState(
                                query: _query,
                                hasFilters: _hasActiveFilters,
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  12,
                                ),
                                itemCount: groups.length,
                                itemBuilder: (context, index) {
                                  final group = groups[index];
                                  return _TodoPdfGroupCard(
                                    title: group.pdfName,
                                    todos: group.todos,
                                    noteRepository: widget.noteRepository,
                                    onJumpToTodo: widget.onJumpToTodo,
                                    onOpenActions: _openTodoActionDropdown,
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_actionTodo != null && _actionAnchorRect != null)
              Positioned.fill(child: _buildTodoActionOverlay(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoActionOverlay(BuildContext context) {
    final todo = _actionTodo;
    final anchorRect = _actionAnchorRect;

    if (todo == null || anchorRect == null) {
      return const SizedBox.shrink();
    }

    final panelRenderObject = _panelKey.currentContext?.findRenderObject();

    if (panelRenderObject is! RenderBox) {
      return const SizedBox.shrink();
    }

    final panelSize = panelRenderObject.size;
    final isCalendar = _actionDropdownMode == _TodoActionDropdownMode.calendar;
    final dropdownWidth = isCalendar ? 360.0 : 240.0;
    final estimatedHeight = isCalendar
        ? 430.0
        : todo.deadline == null
        ? (widget.onConvertToProjectTask == null ? 106.0 : 146.0)
        : (widget.onConvertToProjectTask == null ? 146.0 : 186.0);

    final left = (anchorRect.right - dropdownWidth)
        .clamp(8.0, panelSize.width - dropdownWidth - 8.0)
        .toDouble();

    var top = anchorRect.bottom + 8.0;
    if (top + estimatedHeight > panelSize.height - 8.0) {
      top = anchorRect.top - estimatedHeight - 8.0;
    }
    top = top.clamp(8.0, panelSize.height - estimatedHeight - 8.0).toDouble();

    final arrowCenterX = (anchorRect.center.dx - left)
        .clamp(14.0, dropdownWidth - 14.0)
        .toDouble();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeTodoActionDropdown,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: dropdownWidth,
          height: isCalendar ? estimatedHeight : null,
          child: _TodoFloatingDropdownChrome(
            arrowCenterX: arrowCenterX,
            child: isCalendar
                ? _TodoDeadlineCalendarView(
                    todo: todo,
                    noteRepository: widget.noteRepository,
                    onCancel: () {
                      setState(() {
                        _actionDropdownMode = _TodoActionDropdownMode.actions;
                      });
                    },
                    onDeadlineChanged: _closeTodoActionDropdown,
                  )
                : _TodoActionDropdown(
                    hasDeadline: todo.deadline != null,
                    onSetDeadline: () {
                      setState(() {
                        _actionDropdownMode = _TodoActionDropdownMode.calendar;
                      });
                    },
                    onClearDeadline: () {
                      unawaited(
                        widget.noteRepository.updateTodoDeadline(
                          todoId: todo.id,
                          deadline: null,
                        ),
                      );
                      _closeTodoActionDropdown();
                    },
                    onConvertToProjectTask: widget.onConvertToProjectTask == null
                        ? null
                        : () {
                            final callback = widget.onConvertToProjectTask;
                            if (callback != null) callback(todo);
                            _closeTodoActionDropdown();
                          },
                    onArchive: () {
                      unawaited(widget.noteRepository.archiveTodo(todo.id));
                      _closeTodoActionDropdown();
                    },
                  ),
          ),
        ),
      ],
    );
  }

  void _openTodoActionDropdown({
    required BuildContext anchorContext,
    required TodoItem todo,
  }) {
    final panelRenderObject = _panelKey.currentContext?.findRenderObject();
    final anchorRenderObject = anchorContext.findRenderObject();

    if (panelRenderObject is! RenderBox || anchorRenderObject is! RenderBox) {
      return;
    }

    final anchorOffset = anchorRenderObject.localToGlobal(
      Offset.zero,
      ancestor: panelRenderObject,
    );
    final nextAnchorRect = anchorOffset & anchorRenderObject.size;

    final isSameTodoOpen =
        _actionTodo?.id == todo.id &&
        _actionDropdownMode == _TodoActionDropdownMode.actions;

    setState(() {
      if (isSameTodoOpen) {
        _clearTodoActionDropdown();
      } else {
        _actionTodo = todo;
        _actionAnchorRect = nextAnchorRect;
        _actionDropdownMode = _TodoActionDropdownMode.actions;
      }
    });
  }

  void _closeTodoActionDropdown() {
    setState(_clearTodoActionDropdown);
  }

  void _clearTodoActionDropdown() {
    _actionTodo = null;
    _actionAnchorRect = null;
    _actionDropdownMode = _TodoActionDropdownMode.actions;
  }

  Widget _buildHeader(BuildContext context, _TodoStats stats) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Icon(Icons.task_alt, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'TODOs',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _InlineStat(label: 'Active', value: stats.activeCount),
          const SizedBox(width: 8),
          _InlineStat(
            label: 'Overdue',
            value: stats.overdueCount,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          _InlineStat(
            label: 'Soon',
            value: stats.dueSoonCount,
            color: Colors.orange.shade700,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Close',
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 19),
              hintText: 'Search TODOs or PDFs...',
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SegmentedButton<_TodoStatusFilter>(
                segments: const [
                  ButtonSegment<_TodoStatusFilter>(
                    value: _TodoStatusFilter.active,
                    label: Text('Active'),
                  ),
                  ButtonSegment<_TodoStatusFilter>(
                    value: _TodoStatusFilter.all,
                    label: Text('All'),
                  ),
                  ButtonSegment<_TodoStatusFilter>(
                    value: _TodoStatusFilter.completed,
                    label: Text('Done'),
                  ),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (selection) {
                  setState(() {
                    _statusFilter = selection.first;
                  });
                },
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _filtersExpanded = !_filtersExpanded;
                  });
                },
                icon: Icon(
                  _filtersExpanded
                      ? Icons.expand_less
                      : Icons.filter_alt_outlined,
                  size: 18,
                ),
                label: Text(_filtersExpanded ? 'Hide filters' : 'Filters'),
              ),
              const SizedBox(width: 4),
              _SortMenu(
                sortMode: _sortMode,
                onChanged: (value) {
                  setState(() {
                    _sortMode = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              SegmentedButton<_TodoScopeFilter>(
                segments: const [
                  ButtonSegment<_TodoScopeFilter>(
                    value: _TodoScopeFilter.allPdfs,
                    label: Text('All PDFs'),
                    icon: Icon(Icons.library_books_outlined),
                  ),
                  ButtonSegment<_TodoScopeFilter>(
                    value: _TodoScopeFilter.currentPdf,
                    label: Text('Current PDF'),
                    icon: Icon(Icons.picture_as_pdf_outlined),
                  ),
                ],
                selected: {_scopeFilter},
                onSelectionChanged: (selection) {
                  setState(() {
                    _scopeFilter = selection.first;
                  });
                },
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterMenuChip<_TodoDeadlineFilter>(
                  label: 'Deadline',
                  value: _deadlineFilter,
                  entries: const {
                    _TodoDeadlineFilter.all: 'Any',
                    _TodoDeadlineFilter.overdue: 'Overdue',
                    _TodoDeadlineFilter.dueSoon: 'Due soon',
                    _TodoDeadlineFilter.withDeadline: 'Has due date',
                    _TodoDeadlineFilter.noDeadline: 'No due date',
                  },
                  onChanged: (value) {
                    setState(() {
                      _deadlineFilter = value;
                    });
                  },
                ),
                _FilterMenuChip<_TodoPriorityFilter>(
                  label: 'Priority',
                  value: _priorityFilter,
                  entries: const {
                    _TodoPriorityFilter.all: 'Any',
                    _TodoPriorityFilter.high: 'High',
                    _TodoPriorityFilter.medium: 'Medium',
                    _TodoPriorityFilter.low: 'Low',
                  },
                  onChanged: (value) {
                    setState(() {
                      _priorityFilter = value;
                    });
                  },
                ),
                _FilterMenuChip<_TodoSourceFilter>(
                  label: 'Source',
                  value: _sourceFilter,
                  entries: const {
                    _TodoSourceFilter.all: 'Any',
                    _TodoSourceFilter.pdfText: 'PDF text',
                    _TodoSourceFilter.pdfFreeform: 'PDF page',
                    _TodoSourceFilter.sidecar: 'Sidecar',
                    _TodoSourceFilter.document: 'Document',
                  },
                  onChanged: (value) {
                    setState(() {
                      _sourceFilter = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _scopeFilter = _TodoScopeFilter.allPdfs;
      _statusFilter = _TodoStatusFilter.active;
      _deadlineFilter = _TodoDeadlineFilter.all;
      _priorityFilter = _TodoPriorityFilter.all;
      _sourceFilter = _TodoSourceFilter.all;
      _sortMode = _TodoSortMode.deadline;
    });
  }

  List<TodoItem> _filterTodos(List<TodoItem> todos) {
    return todos.where((todo) {
      if (!_matchesStatus(todo)) return false;
      if (!_matchesDeadline(todo)) return false;
      if (!_matchesPriority(todo)) return false;
      if (!_matchesSource(todo)) return false;
      if (!_matchesSearch(todo)) return false;
      return true;
    }).toList();
  }

  bool _matchesStatus(TodoItem todo) {
    switch (_statusFilter) {
      case _TodoStatusFilter.active:
        return !todo.isCompleted;
      case _TodoStatusFilter.completed:
        return todo.isCompleted;
      case _TodoStatusFilter.all:
        return true;
    }
  }

  bool _matchesDeadline(TodoItem todo) {
    switch (_deadlineFilter) {
      case _TodoDeadlineFilter.all:
        return true;
      case _TodoDeadlineFilter.overdue:
        return todo.isOverdue;
      case _TodoDeadlineFilter.dueSoon:
        return todo.isDueSoon;
      case _TodoDeadlineFilter.noDeadline:
        return todo.deadline == null;
      case _TodoDeadlineFilter.withDeadline:
        return todo.deadline != null;
    }
  }

  bool _matchesPriority(TodoItem todo) {
    switch (_priorityFilter) {
      case _TodoPriorityFilter.all:
        return true;
      case _TodoPriorityFilter.low:
        return todo.priority == kTodoPriorityLow;
      case _TodoPriorityFilter.medium:
        return todo.priority == kTodoPriorityMedium;
      case _TodoPriorityFilter.high:
        return todo.priority == kTodoPriorityHigh;
    }
  }

  bool _matchesSource(TodoItem todo) {
    switch (_sourceFilter) {
      case _TodoSourceFilter.all:
        return true;
      case _TodoSourceFilter.pdfText:
        return todo.sourceType == kTodoSourcePdfTextSelection;
      case _TodoSourceFilter.pdfFreeform:
        return todo.sourceType == kTodoSourcePdfFreeform;
      case _TodoSourceFilter.sidecar:
        return todo.sourceType == kTodoSourceSidecarNote;
      case _TodoSourceFilter.document:
        return todo.sourceType == kTodoSourceDocumentNote;
    }
  }

  bool _matchesSearch(TodoItem todo) {
    if (_query.isEmpty) return true;

    final haystack = [
      todo.pdfLabel,
      todo.title,
      todo.body ?? '',
      todo.priority,
      todo.sourceType,
      _sourceLabel(todo.sourceType),
      if (todo.deadline != null) _formatIsoDate(todo.deadline!),
      if (todo.pageNumber != null) 'page ${todo.pageNumber}',
    ].join(' ').toLowerCase();

    return haystack.contains(_query);
  }

  List<TodoItem> _sortTodos(List<TodoItem> todos) {
    final sorted = todos.toList();

    sorted.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }

      final primary = switch (_sortMode) {
        _TodoSortMode.deadline => _compareDeadline(a, b),
        _TodoSortMode.priority => _comparePriority(a, b),
        _TodoSortMode.updated => b.note.updatedAt.compareTo(a.note.updatedAt),
        _TodoSortMode.pdfName => _comparePdfName(a, b),
        _TodoSortMode.source => _sourceLabel(
          a.sourceType,
        ).compareTo(_sourceLabel(b.sourceType)),
      };

      if (primary != 0) return primary;

      final deadlineCompare = _compareDeadline(a, b);
      if (deadlineCompare != 0) return deadlineCompare;

      final priorityCompare = _comparePriority(a, b);
      if (priorityCompare != 0) return priorityCompare;

      return b.note.updatedAt.compareTo(a.note.updatedAt);
    });

    return sorted;
  }

  int _compareDeadline(TodoItem a, TodoItem b) {
    final aDeadline = a.deadline;
    final bDeadline = b.deadline;

    if (aDeadline != null && bDeadline != null) {
      return aDeadline.compareTo(bDeadline);
    }

    if (aDeadline != null) return -1;
    if (bDeadline != null) return 1;
    return 0;
  }

  int _comparePriority(TodoItem a, TodoItem b) {
    return _priorityRank(b.priority).compareTo(_priorityRank(a.priority));
  }

  int _comparePdfName(TodoItem a, TodoItem b) {
    return a.pdfLabel.toLowerCase().compareTo(b.pdfLabel.toLowerCase());
  }

  List<_TodoGroup> _groupByPdf(List<TodoItem> todos) {
    final grouped = <String, List<TodoItem>>{};
    for (final todo in todos) {
      grouped.putIfAbsent(todo.pdfLabel, () => []).add(todo);
    }

    final groups = [
      for (final entry in grouped.entries)
        _TodoGroup(pdfName: entry.key, todos: entry.value),
    ];

    groups.sort((a, b) {
      final aUrgency = _groupUrgency(a.todos);
      final bUrgency = _groupUrgency(b.todos);
      if (aUrgency != bUrgency) return bUrgency.compareTo(aUrgency);

      return a.pdfName.toLowerCase().compareTo(b.pdfName.toLowerCase());
    });

    return groups;
  }

  int _groupUrgency(List<TodoItem> todos) {
    var highest = 0;
    for (final todo in todos) {
      final urgency = _todoUrgency(todo);
      highest = highest < urgency ? urgency : highest;
    }
    return highest;
  }

  int _todoUrgency(TodoItem todo) {
    if (todo.isCompleted) return 0;
    if (todo.isOverdue) return 5;
    if (todo.isDueSoon) return 4;
    return _priorityRank(todo.priority);
  }
}

class _TodoDeadlineCalendarView extends StatefulWidget {
  final TodoItem todo;
  final NoteRepository noteRepository;
  final VoidCallback onCancel;
  final VoidCallback onDeadlineChanged;

  const _TodoDeadlineCalendarView({
    required this.todo,
    required this.noteRepository,
    required this.onCancel,
    required this.onDeadlineChanged,
  });

  @override
  State<_TodoDeadlineCalendarView> createState() =>
      _TodoDeadlineCalendarViewState();
}

class _TodoDeadlineCalendarViewState extends State<_TodoDeadlineCalendarView> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();

    final initial = widget.todo.deadline ?? DateTime.now();
    _visibleMonth = DateTime(initial.year, initial.month);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _calendarDaysForMonth(_visibleMonth);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to actions',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onCancel,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.todo.deadline == null
                          ? 'Set deadline'
                          : 'Change deadline',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.todo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.todo.deadline != null)
                TextButton(
                  onPressed: () async {
                    await widget.noteRepository.updateTodoDeadline(
                      todoId: widget.todo.id,
                      deadline: null,
                    );
                    widget.onDeadlineChanged();
                  },
                  child: const Text('Clear'),
                ),
              IconButton(
                tooltip: 'Cancel',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () {
                  setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month - 1,
                    );
                  });
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _monthLabel(_visibleMonth),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () {
                  setState(() {
                    _visibleMonth = DateTime(
                      _visibleMonth.year,
                      _visibleMonth.month + 1,
                    );
                  });
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: const [
              _CalendarWeekdayLabel('Mon'),
              _CalendarWeekdayLabel('Tue'),
              _CalendarWeekdayLabel('Wed'),
              _CalendarWeekdayLabel('Thu'),
              _CalendarWeekdayLabel('Fri'),
              _CalendarWeekdayLabel('Sat'),
              _CalendarWeekdayLabel('Sun'),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (context, index) {
                final day = days[index];
                final isInMonth = day.month == _visibleMonth.month;
                final isToday = _sameDate(day, DateTime.now());
                final isSelected =
                    widget.todo.deadline != null &&
                    _sameDate(day, widget.todo.deadline!);

                return _CalendarDayButton(
                  day: day,
                  isInMonth: isInMonth,
                  isToday: isToday,
                  isSelected: isSelected,
                  onPressed: () async {
                    await widget.noteRepository.updateTodoDeadline(
                      todoId: widget.todo.id,
                      deadline: DateTime(day.year, day.month, day.day),
                    );
                    widget.onDeadlineChanged();
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<DateTime> _calendarDaysForMonth(DateTime month) {
    final first = DateTime(month.year, month.month);
    final startOffset = first.weekday - DateTime.monday;
    final firstVisible = first.subtract(Duration(days: startOffset));

    return [
      for (var index = 0; index < 42; index++)
        firstVisible.add(Duration(days: index)),
    ];
  }

  String _monthLabel(DateTime month) {
    return '${_monthName(month.month)} ${month.year}';
  }

  String _monthName(int month) {
    switch (month) {
      case 1:
        return 'January';
      case 2:
        return 'February';
      case 3:
        return 'March';
      case 4:
        return 'April';
      case 5:
        return 'May';
      case 6:
        return 'June';
      case 7:
        return 'July';
      case 8:
        return 'August';
      case 9:
        return 'September';
      case 10:
        return 'October';
      case 11:
        return 'November';
      case 12:
      default:
        return 'December';
    }
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _CalendarWeekdayLabel extends StatelessWidget {
  final String label;

  const _CalendarWeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Center(
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CalendarDayButton extends StatelessWidget {
  final DateTime day;
  final bool isInMonth;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onPressed;

  const _CalendarDayButton({
    required this.day,
    required this.isInMonth,
    required this.isToday,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final foreground = isSelected
        ? theme.colorScheme.onPrimary
        : isInMonth
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55);

    final background = isSelected
        ? theme.colorScheme.primary
        : isToday
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : Colors.transparent;

    return Material(
      color: background,
      shape: Border.all(
        color: isToday || isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
      ),
      child: InkWell(
        onTap: onPressed,
        child: Center(
          child: Text(
            '${day.day}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: isSelected || isToday ? FontWeight.w700 : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _TodoPdfGroupCard extends StatelessWidget {
  final String title;
  final List<TodoItem> todos;
  final NoteRepository noteRepository;
  final ValueChanged<TodoItem> onJumpToTodo;
  final void Function({
    required BuildContext anchorContext,
    required TodoItem todo,
  })
  onOpenActions;

  const _TodoPdfGroupCard({
    required this.title,
    required this.todos,
    required this.noteRepository,
    required this.onJumpToTodo,
    required this.onOpenActions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = todos.where((todo) => !todo.isCompleted).length;
    final overdueCount = todos.where((todo) => todo.isOverdue).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined, size: 16),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (overdueCount > 0)
                  _MiniChip(
                    label: '$overdueCount overdue',
                    color: theme.colorScheme.error,
                  ),
                if (overdueCount > 0) const SizedBox(width: 6),
                _MiniChip(label: '$activeCount active'),
              ],
            ),
            const SizedBox(height: 6),
            for (final todo in todos)
              _TodoRow(
                todo: todo,
                noteRepository: noteRepository,
                onJumpToTodo: onJumpToTodo,
                onOpenActions: onOpenActions,
              ),
          ],
        ),
      ),
    );
  }
}

class _TodoRow extends StatefulWidget {
  final TodoItem todo;
  final NoteRepository noteRepository;
  final ValueChanged<TodoItem> onJumpToTodo;
  final void Function({
    required BuildContext anchorContext,
    required TodoItem todo,
  })
  onOpenActions;

  const _TodoRow({
    required this.todo,
    required this.noteRepository,
    required this.onJumpToTodo,
    required this.onOpenActions,
  });

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  TodoItem get todo => widget.todo;
  NoteRepository get noteRepository => widget.noteRepository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priorityColor = Color(TodoItem.colorForPriority(todo.priority));
    final dueStatus = _DueStatus.from(todo.deadline, todo.isCompleted);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: todo.isCompleted
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : priorityColor.withValues(alpha: 0.08),
        border: Border.all(
          color: todo.isCompleted
              ? theme.colorScheme.outlineVariant
              : priorityColor.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 58,
            color: todo.isCompleted
                ? theme.colorScheme.outlineVariant
                : priorityColor,
          ),
          Checkbox(
            value: todo.isCompleted,
            onChanged: (value) {
              unawaited(
                noteRepository.updateTodoCompleted(
                  todoId: todo.id,
                  isCompleted: value ?? false,
                ),
              );
            },
          ),
          Tooltip(
            message: _sourceLabel(todo.sourceType),
            child: Icon(_sourceIcon(todo.sourceType), size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  todo.title,
                  maxLines: todo.deadline == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    decoration: todo.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    color: todo.isCompleted
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
                if (todo.deadline != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          dueStatus.icon,
                          size: 13,
                          color: dueStatus.color(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dueStatus.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: dueStatus.color(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PriorityMenu(
            priority: todo.priority,
            compact: true,
            onChanged: (priority) {
              unawaited(
                noteRepository.updateTodoPriority(
                  todoId: todo.id,
                  priority: priority,
                ),
              );
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: todo.hasPdfSource ? 'Jump to source' : 'No PDF source',
            onPressed: todo.hasPdfSource
                ? () => widget.onJumpToTodo(todo)
                : null,
            icon: const Icon(Icons.open_in_new, size: 19),
          ),
          Builder(
            builder: (buttonContext) {
              return IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'TODO actions',
                onPressed: () {
                  widget.onOpenActions(
                    anchorContext: buttonContext,
                    todo: todo,
                  );
                },
                icon: const Icon(Icons.more_vert, size: 20),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TodoFloatingDropdownChrome extends StatelessWidget {
  final double arrowCenterX;
  final Widget child;

  const _TodoFloatingDropdownChrome({
    required this.arrowCenterX,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -5,
          left: arrowCenterX - 6,
          child: Transform.rotate(
            angle: 0.7853981633974483,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  left: BorderSide(color: theme.colorScheme.outlineVariant),
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

class _TodoActionDropdown extends StatelessWidget {
  final bool hasDeadline;
  final VoidCallback onSetDeadline;
  final VoidCallback onClearDeadline;
  final VoidCallback? onConvertToProjectTask;
  final VoidCallback onArchive;

  const _TodoActionDropdown({
    required this.hasDeadline,
    required this.onSetDeadline,
    required this.onClearDeadline,
    required this.onConvertToProjectTask,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TodoDropdownAction(
            icon: Icons.event_outlined,
            label: hasDeadline ? 'Change deadline' : 'Set deadline',
            onPressed: onSetDeadline,
          ),
          if (hasDeadline)
            _TodoDropdownAction(
              icon: Icons.event_busy_outlined,
              label: 'Clear deadline',
              onPressed: onClearDeadline,
            ),
          if (onConvertToProjectTask != null)
            _TodoDropdownAction(
              icon: Icons.dashboard_customize_outlined,
              label: 'Make project task',
              onPressed: onConvertToProjectTask!,
            ),
          const Divider(height: 1),
          _TodoDropdownAction(
            icon: Icons.archive_outlined,
            label: 'Archive',
            onPressed: onArchive,
          ),
        ],
      ),
    );
  }
}

class _TodoDropdownAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _TodoDropdownAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

class _PriorityMenu extends StatelessWidget {
  final String priority;
  final ValueChanged<String> onChanged;
  final bool compact;

  const _PriorityMenu({
    required this.priority,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = _priorityLabel(priority);
    final color = Color(TodoItem.colorForPriority(priority));

    return PopupMenuButton<String>(
      tooltip: 'Priority',
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: kTodoPriorityLow, child: Text('Low priority')),
        PopupMenuItem(
          value: kTodoPriorityMedium,
          child: Text('Medium priority'),
        ),
        PopupMenuItem(value: kTodoPriorityHigh, child: Text('High priority')),
      ],
      child: compact
          ? Tooltip(
              message: '$normalized priority',
              child: CircleAvatar(radius: 6, backgroundColor: color),
            )
          : Chip(
              visualDensity: VisualDensity.compact,
              avatar: CircleAvatar(radius: 5, backgroundColor: color),
              label: Text(normalized),
              side: BorderSide(color: color.withValues(alpha: 0.55)),
            ),
    );
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case kTodoPriorityLow:
        return 'Low';
      case kTodoPriorityHigh:
        return 'High';
      case kTodoPriorityMedium:
      default:
        return 'Medium';
    }
  }
}

class _SortMenu extends StatelessWidget {
  final _TodoSortMode sortMode;
  final ValueChanged<_TodoSortMode> onChanged;

  const _SortMenu({required this.sortMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TodoSortMode>(
      tooltip: 'Sort TODOs',
      initialValue: sortMode,
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _TodoSortMode.deadline,
          child: Text('Sort by deadline'),
        ),
        PopupMenuItem(
          value: _TodoSortMode.priority,
          child: Text('Sort by priority'),
        ),
        PopupMenuItem(
          value: _TodoSortMode.updated,
          child: Text('Sort by updated'),
        ),
        PopupMenuItem(
          value: _TodoSortMode.pdfName,
          child: Text('Sort by PDF name'),
        ),
        PopupMenuItem(
          value: _TodoSortMode.source,
          child: Text('Sort by source'),
        ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.sort, size: 18),
        label: Text(_sortLabel(sortMode)),
      ),
    );
  }

  String _sortLabel(_TodoSortMode mode) {
    switch (mode) {
      case _TodoSortMode.deadline:
        return 'Deadline';
      case _TodoSortMode.priority:
        return 'Priority';
      case _TodoSortMode.updated:
        return 'Updated';
      case _TodoSortMode.pdfName:
        return 'PDF';
      case _TodoSortMode.source:
        return 'Source';
    }
  }
}

class _FilterMenuChip<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> entries;
  final ValueChanged<T> onChanged;

  const _FilterMenuChip({
    required this.label,
    required this.value,
    required this.entries,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = entries[value] ?? label;

    return PopupMenuButton<T>(
      tooltip: label,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) {
        return [
          for (final entry in entries.entries)
            PopupMenuItem(value: entry.key, child: Text(entry.value)),
        ];
      },
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.filter_list, size: 16),
        label: Text('$label: $selectedLabel'),
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final int value;
  final Color? color;

  const _InlineStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;

    return Text(
      '$label $value',
      style: theme.textTheme.labelMedium?.copyWith(color: effectiveColor),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color? color;

  const _MiniChip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.outline;

    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      side: BorderSide(color: effectiveColor.withValues(alpha: 0.55)),
    );
  }
}

class _TodoEmptyState extends StatelessWidget {
  final String query;
  final bool hasFilters;

  const _TodoEmptyState({required this.query, required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = query.isNotEmpty || hasFilters
        ? 'No TODOs match the current search and filters.'
        : 'No TODOs yet. Select PDF text and choose TODO.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DueStatus {
  final String label;
  final IconData icon;
  final bool isOverdue;
  final bool isDueSoon;

  const _DueStatus({
    required this.label,
    required this.icon,
    required this.isOverdue,
    required this.isDueSoon,
  });

  factory _DueStatus.from(DateTime? deadline, bool isCompleted) {
    if (deadline == null) {
      return const _DueStatus(
        label: 'Add due',
        icon: Icons.event_outlined,
        isOverdue: false,
        isDueSoon: false,
      );
    }

    final now = DateTime.now();
    final date = DateTime(deadline.year, deadline.month, deadline.day);
    final today = DateTime(now.year, now.month, now.day);
    final delta = date.difference(today).inDays;

    if (!isCompleted && delta < 0) {
      return const _DueStatus(
        label: 'Overdue',
        icon: Icons.warning_amber_outlined,
        isOverdue: true,
        isDueSoon: false,
      );
    }

    if (delta == 0) {
      return const _DueStatus(
        label: 'Today',
        icon: Icons.today_outlined,
        isOverdue: false,
        isDueSoon: true,
      );
    }

    if (delta == 1) {
      return const _DueStatus(
        label: 'Tomorrow',
        icon: Icons.event_outlined,
        isOverdue: false,
        isDueSoon: true,
      );
    }

    return _DueStatus(
      label: _formatIsoDate(deadline),
      icon: Icons.event_outlined,
      isOverdue: false,
      isDueSoon: !isCompleted && delta <= 2,
    );
  }

  Color color(BuildContext context) {
    final theme = Theme.of(context);
    if (isOverdue) return theme.colorScheme.error;
    if (isDueSoon) return Colors.orange.shade700;
    return theme.colorScheme.outlineVariant;
  }
}

class _TodoStats {
  final int activeCount;
  final int completedCount;
  final int overdueCount;
  final int dueSoonCount;

  const _TodoStats({
    required this.activeCount,
    required this.completedCount,
    required this.overdueCount,
    required this.dueSoonCount,
  });

  factory _TodoStats.from(List<TodoItem> todos) {
    return _TodoStats(
      activeCount: todos.where((todo) => !todo.isCompleted).length,
      completedCount: todos.where((todo) => todo.isCompleted).length,
      overdueCount: todos.where((todo) => todo.isOverdue).length,
      dueSoonCount: todos.where((todo) => todo.isDueSoon).length,
    );
  }
}

class _TodoGroup {
  final String pdfName;
  final List<TodoItem> todos;

  const _TodoGroup({required this.pdfName, required this.todos});
}

int _priorityRank(String priority) {
  switch (priority) {
    case kTodoPriorityHigh:
      return 3;
    case kTodoPriorityMedium:
      return 2;
    case kTodoPriorityLow:
    default:
      return 1;
  }
}

IconData _sourceIcon(String sourceType) {
  switch (sourceType) {
    case kTodoSourcePdfTextSelection:
      return Icons.format_quote;
    case kTodoSourcePdfFreeform:
      return Icons.picture_as_pdf_outlined;
    case kTodoSourceSidecarNote:
      return Icons.view_sidebar_outlined;
    case kTodoSourceDocumentNote:
      return Icons.article_outlined;
    default:
      return Icons.task_alt;
  }
}

String _sourceLabel(String sourceType) {
  switch (sourceType) {
    case kTodoSourcePdfTextSelection:
      return 'PDF text';
    case kTodoSourcePdfFreeform:
      return 'PDF page';
    case kTodoSourceSidecarNote:
      return 'Sidecar';
    case kTodoSourceDocumentNote:
      return 'Document';
    default:
      return 'TODO';
  }
}

String _formatIsoDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
