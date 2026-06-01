import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';

Future<PlanningEntry?> showPlanningEntryDialog({
  required BuildContext context,
  required StudyPlanningRepository planningRepository,
  String? projectId,
  String initialKind = PlanningEntryKind.task,
  DateTime? initialDate,
  PlanningEntry? entry,
}) {
  return showDialog<PlanningEntry>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 560,
        child: _PlanningEntryDialog(
          planningRepository: planningRepository,
          projectId: projectId,
          initialKind: initialKind,
          initialDate: initialDate,
          entry: entry,
        ),
      ),
    ),
  );
}

class _PlanningEntryDialog extends StatefulWidget {
  const _PlanningEntryDialog({
    required this.planningRepository,
    required this.projectId,
    required this.initialKind,
    required this.initialDate,
    required this.entry,
  });

  final StudyPlanningRepository planningRepository;
  final String? projectId;
  final String initialKind;
  final DateTime? initialDate;
  final PlanningEntry? entry;

  @override
  State<_PlanningEntryDialog> createState() => _PlanningEntryDialogState();
}

class _PlanningEntryDialogState extends State<_PlanningEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _estimateController = TextEditingController();
  late String _kind;
  String _priority = PlanningEntryPriority.normal;
  DateTime? _date;
  TimeOfDay? _time;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.entry;
    if (existing != null) {
      _titleController.text = existing.title;
      _notesController.text = existing.notes ?? '';
      _estimateController.text = existing.estimateMinutes?.toString() ?? '';
      _kind = PlanningEntryKind.normalize(existing.kind);
      _priority = PlanningEntryPriority.normalize(existing.priority);
      final scheduled = existing.calendarDate;
      if (scheduled != null) {
        _date = _dateOnly(scheduled);
        if (!existing.allDay || scheduled.hour != 0 || scheduled.minute != 0) {
          _time = TimeOfDay.fromDateTime(scheduled);
        }
      }
      return;
    }

    _kind = PlanningEntryKind.normalize(widget.initialKind);
    _date = widget.initialDate == null ? null : _dateOnly(widget.initialDate!);
    if (widget.initialDate != null && (widget.initialDate!.hour != 0 || widget.initialDate!.minute != 0)) {
      _time = TimeOfDay.fromDateTime(widget.initialDate!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _estimateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveProjectId = widget.projectId ?? widget.entry?.projectId;
    final project = effectiveProjectId == null ? null : widget.planningRepository.projectById(effectiveProjectId);
    final editing = widget.entry != null;
    final title = editing
        ? 'Edit planning item'
        : _kind == PlanningEntryKind.deadline
            ? 'Add deadline'
            : 'Add planning item';
    final hasTime = _time != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _kind == PlanningEntryKind.deadline
                        ? Icons.flag_rounded
                        : _kind == PlanningEntryKind.event
                            ? Icons.event_available_rounded
                            : Icons.inbox_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(
                        editing
                            ? 'Change the title, type, date, time, estimate, or notes.'
                            : project == null
                                ? 'Saved to Planning inbox. You can schedule or attach it later.'
                                : 'Saved under ${project.title}.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _kind == PlanningEntryKind.deadline ? 'Deadline name' : 'Task / reminder',
                hintText: _kind == PlanningEntryKind.deadline ? 'Exam, submission, presentation…' : 'Email supervisor, buy milk, review notes…',
                border: const OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty ? 'Give it a title.' : null,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _kind,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: PlanningEntryKind.task, child: Text('Task')),
                      DropdownMenuItem(value: PlanningEntryKind.deadline, child: Text('Deadline')),
                      DropdownMenuItem(value: PlanningEntryKind.event, child: Text('Event')),
                      DropdownMenuItem(value: PlanningEntryKind.reminder, child: Text('Reminder')),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _kind = PlanningEntryKind.normalize(value)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: PlanningEntryPriority.low, child: Text('Low')),
                      DropdownMenuItem(value: PlanningEntryPriority.normal, child: Text('Normal')),
                      DropdownMenuItem(value: PlanningEntryPriority.high, child: Text('High')),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _priority = PlanningEntryPriority.normalize(value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(_date == null ? 'Leave unscheduled' : _dateLabel(_date!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || _date == null ? null : _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(_time == null ? 'Add time' : _timeLabel(_time!)),
                  ),
                ),
                if (_date != null || _time != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear schedule',
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _date = null;
                              _time = null;
                            }),
                    icon: const Icon(Icons.clear_rounded),
                  ),
                ],
              ],
            ),
            if (_date == null && hasTime) ...[
              const SizedBox(height: 8),
              Text(
                'Choose a date before adding a time.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _estimateController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estimate minutes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _scheduleHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.3),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(editing ? Icons.save_rounded : Icons.add_rounded),
                  label: Text(editing ? 'Save' : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _scheduleHint {
    if (_date == null) return 'Inbox items stay visible without forcing a project or calendar date.';
    if (_time == null) return 'Dated items appear in Today and Calendar as all-day items.';
    if (_kind == PlanningEntryKind.deadline) return 'Timed deadlines appear at the chosen time in Today and Calendar.';
    return 'Timed items appear at the chosen time in Today and Calendar.';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MondayFirstDatePickerDialog(
        initialDate: _date ?? now,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 6, 12, 31),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = _dateOnly(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_saving || _formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    try {
      final estimate = int.tryParse(_estimateController.text.trim());
      final scheduledAt = _time == null ? null : _combineDateAndTime(_date, _time);
      final estimatedEndAt = scheduledAt == null || estimate == null || estimate <= 0
          ? null
          : scheduledAt.add(Duration(minutes: estimate));
      final cleanNotes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
      final existing = widget.entry;
      if (existing == null) {
        final entry = await widget.planningRepository.createPlanningEntry(
          title: _titleController.text,
          notes: cleanNotes,
          kind: _kind,
          priority: _priority,
          projectId: widget.projectId,
          date: _kind == PlanningEntryKind.deadline ? null : _date,
          dueAt: _kind == PlanningEntryKind.deadline ? scheduledAt ?? _date : null,
          startAt: _kind == PlanningEntryKind.deadline ? null : scheduledAt,
          endAt: _kind == PlanningEntryKind.event ? estimatedEndAt : null,
          allDay: _time == null,
          estimateMinutes: estimate,
        );
        if (!mounted) return;
        Navigator.of(context).pop(entry);
        return;
      }

      await widget.planningRepository.updatePlanningEntry(
        entryId: existing.id,
        title: _titleController.text,
        notes: cleanNotes,
        kind: _kind,
        priority: _priority,
        date: _kind == PlanningEntryKind.deadline ? null : _date,
        dueAt: _kind == PlanningEntryKind.deadline ? scheduledAt ?? _date : null,
        startAt: _kind == PlanningEntryKind.deadline ? null : scheduledAt,
        endAt: _kind == PlanningEntryKind.event ? estimatedEndAt : null,
        allDay: _time == null,
        estimateMinutes: estimate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(existing);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save planning item: $error'), behavior: SnackBarBehavior.floating),
      );
      setState(() => _saving = false);
    }
  }
}

class _MondayFirstDatePickerDialog extends StatefulWidget {
  const _MondayFirstDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_MondayFirstDatePickerDialog> createState() => _MondayFirstDatePickerDialogState();
}

class _MondayFirstDatePickerDialogState extends State<_MondayFirstDatePickerDialog> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = _clampDate(_dateOnly(widget.initialDate));
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _calendarDaysForMonth(_visibleMonth);
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: _canMoveMonth(-1) ? () => setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1)) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_monthName(_visibleMonth.month)} ${_visibleMonth.year}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: _canMoveMonth(1) ? () => setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1)) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: const [
                  _DatePickerWeekdayLabel('Mon'),
                  _DatePickerWeekdayLabel('Tue'),
                  _DatePickerWeekdayLabel('Wed'),
                  _DatePickerWeekdayLabel('Thu'),
                  _DatePickerWeekdayLabel('Fri'),
                  _DatePickerWeekdayLabel('Sat'),
                  _DatePickerWeekdayLabel('Sun'),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: days.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemBuilder: (context, index) {
                  final day = days[index];
                  final enabled = !_dateOnly(day).isBefore(_dateOnly(widget.firstDate)) && !_dateOnly(day).isAfter(_dateOnly(widget.lastDate));
                  final inMonth = day.month == _visibleMonth.month;
                  final selected = _sameDate(day, _selectedDate);
                  final today = _sameDate(day, DateTime.now());
                  return _DatePickerDayButton(
                    date: day,
                    enabled: enabled,
                    inMonth: inMonth,
                    selected: selected,
                    today: today,
                    onPressed: enabled ? () => setState(() => _selectedDate = _dateOnly(day)) : null,
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      final today = _clampDate(_dateOnly(DateTime.now()));
                      setState(() {
                        _selectedDate = today;
                        _visibleMonth = DateTime(today.year, today.month);
                      });
                    },
                    child: const Text('Today'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selectedDate),
                    child: const Text('Choose'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _clampDate(DateTime value) {
    final date = _dateOnly(value);
    final first = _dateOnly(widget.firstDate);
    final last = _dateOnly(widget.lastDate);
    if (date.isBefore(first)) return first;
    if (date.isAfter(last)) return last;
    return date;
  }

  bool _canMoveMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    return !next.isBefore(firstMonth) && !next.isAfter(lastMonth);
  }
}

class _DatePickerWeekdayLabel extends StatelessWidget {
  const _DatePickerWeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _DatePickerDayButton extends StatelessWidget {
  const _DatePickerDayButton({
    required this.date,
    required this.enabled,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.onPressed,
  });

  final DateTime date;
  final bool enabled;
  final bool inMonth;
  final bool selected;
  final bool today;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : enabled
            ? inMonth
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant.withOpacity(.62)
            : theme.disabledColor;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : null,
          borderRadius: BorderRadius.circular(12),
          border: today && !selected ? Border.all(color: theme.colorScheme.primary, width: 1.4) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${date.day}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected || today ? FontWeight.w900 : FontWeight.w700,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

List<DateTime> _calendarDaysForMonth(DateTime month) {
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
  return days;
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime? _combineDateAndTime(DateTime? date, TimeOfDay? time) {
  if (date == null) return null;
  if (time == null) return _dateOnly(date);
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

String _dateLabel(DateTime value) {
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
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _timeLabel(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _monthName(int month) {
  const months = <String>[
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
  return months[month - 1];
}

bool _sameDate(DateTime a, DateTime b) {
  final left = _dateOnly(a);
  final right = _dateOnly(b);
  return left.year == right.year && left.month == right.month && left.day == right.day;
}
