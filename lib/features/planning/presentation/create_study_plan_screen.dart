import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';

class CreateStudyPlanScreen extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final StudyProject project;

  const CreateStudyPlanScreen({
    super.key,
    required this.planningRepository,
    required this.project,
  });

  @override
  State<CreateStudyPlanScreen> createState() => _CreateStudyPlanScreenState();
}

class _CreateStudyPlanScreenState extends State<CreateStudyPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _startUnitController = TextEditingController(text: '1');
  final _endUnitController = TextEditingController();
  final _dailyTargetController = TextEditingController(text: '1');
  final _customSingularController = TextEditingController();
  final _customPluralController = TextEditingController();
  final _customLabelController = TextEditingController();
  final _checklistController = TextEditingController();

  String _planKind = StudyPlanKind.progress;
  String _unitType = 'pages';
  late DateTime _startDate;
  DateTime? _deadline;
  DateTime? _taskDate;
  bool _weekendsOff = false;
  bool _saving = false;

  static const _unitTypes = <String, String>{
    'pages': 'Pages',
    'chapters': 'Chapters',
    'sections': 'Sections',
    'exercises': 'Exercises',
    'custom': 'Define my own unit',
  };

  static const _kindDescriptions = <String, String>{
    StudyPlanKind.progress: 'Finish a total by a date, e.g. pages 1–356 before the exam.',
    StudyPlanKind.recurring: 'Do the same amount every study day, e.g. 3 cases per weekday.',
    StudyPlanKind.singleTask: 'One concrete action on one date, e.g. submit assignment.',
    StudyPlanKind.deadline: 'A fixed pressure point, e.g. exam or assignment deadline.',
    StudyPlanKind.checklist: 'A list of named items/topics distributed across days.',
  };

  bool get _usesUnits =>
      _planKind == StudyPlanKind.progress || _planKind == StudyPlanKind.recurring;
  bool get _usesDeadline =>
      _planKind == StudyPlanKind.progress || _planKind == StudyPlanKind.checklist;
  bool get _usesTaskDate =>
      _planKind == StudyPlanKind.singleTask || _planKind == StudyPlanKind.deadline;
  bool get _usesWeekends =>
      _planKind == StudyPlanKind.progress ||
      _planKind == StudyPlanKind.recurring ||
      _planKind == StudyPlanKind.checklist;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _deadline = widget.project.deadline ?? _startDate.add(const Duration(days: 21));
    _taskDate = widget.project.deadline ?? _startDate;
    _titleController.text = _defaultTitleForState();
    _checklistController.text = 'Topic 1\nTopic 2\nTopic 3';

    for (final controller in [
      _titleController,
      _startUnitController,
      _endUnitController,
      _dailyTargetController,
      _customSingularController,
      _customPluralController,
      _customLabelController,
      _checklistController,
    ]) {
      controller.addListener(_refreshPreview);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _startUnitController.dispose();
    _endUnitController.dispose();
    _dailyTargetController.dispose();
    _customSingularController.dispose();
    _customPluralController.dispose();
    _customLabelController.dispose();
    _checklistController.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _previewText();

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Add to project'),
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _ProjectHeader(project: widget.project),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What kind of commitment is this?',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose the commitment that best matches the real work. The app will turn it into calendar requirements and behind-schedule signals.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _planKind,
                          decoration: const InputDecoration(
                            labelText: 'Item type',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final kind in StudyPlanKind.values)
                              DropdownMenuItem(
                                value: kind,
                                child: Text(StudyPlanKind.label(kind)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _planKind = value;
                              if (_knownDefaultTitles.contains(_titleController.text.trim())) {
                                _titleController.text = _defaultTitleForState();
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _kindDescriptions[_planKind]!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: _planKind == StudyPlanKind.deadline
                                ? 'Deadline name'
                                : _planKind == StudyPlanKind.singleTask
                                    ? 'Task name'
                                    : 'Name',
                            hintText: _hintForKind(),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Give it a name.';
                            }
                            return null;
                          },
                        ),
                        if (_usesUnits) ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: _unitType,
                            decoration: const InputDecoration(
                              labelText: 'What unit should the calendar talk about?',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final entry in _unitTypes.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _unitType = value;
                                if (_knownDefaultTitles.contains(_titleController.text.trim())) {
                                  _titleController.text = _defaultTitleForState();
                                }
                              });
                            },
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: _unitType == 'custom'
                                ? Padding(
                                    key: const ValueKey('custom-units'),
                                    padding: const EdgeInsets.only(top: 14),
                                    child: _CustomUnitDefinitionCard(
                                      singularController: _customSingularController,
                                      pluralController: _customPluralController,
                                      labelController: _customLabelController,
                                      singularValidator: _validateCustomSingular,
                                      pluralValidator: _validateCustomPlural,
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey('built-in-units')),
                          ),
                        ],
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: _fieldsForKind(),
                        ),
                        if (_usesDeadline || _usesTaskDate || _planKind == StudyPlanKind.recurring) ...[
                          const SizedBox(height: 14),
                          _dateControls(),
                        ],
                        if (_planKind == StudyPlanKind.recurring) ...[
                          const SizedBox(height: 6),
                          SwitchListTile.adaptive(
                            value: _deadline == null,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Run indefinitely'),
                            subtitle: const Text(
                              'Use this for ongoing work until you remove the project or archive the plan.',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _deadline = value
                                    ? null
                                    : widget.project.deadline ?? _startDate.add(const Duration(days: 21));
                              });
                            },
                          ),
                        ],
                        if (_usesWeekends) ...[
                          SwitchListTile.adaptive(
                            value: _weekendsOff,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Keep weekends free'),
                            subtitle: const Text(
                              'The plan will generate work only on weekdays.',
                            ),
                            onChanged: (value) => setState(() => _weekendsOff = value),
                          ),
                        ],
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: preview == null
                              ? const SizedBox.shrink()
                              : _PreviewBox(text: preview),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(_planKind == StudyPlanKind.singleTask
                                ? 'Create task'
                                : _planKind == StudyPlanKind.deadline
                                    ? 'Create deadline'
                                    : _planKind == StudyPlanKind.checklist
                                        ? 'Create checklist'
                                        : 'Create plan'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldsForKind() {
    switch (_planKind) {
      case StudyPlanKind.recurring:
        return _RecurringFields(
          key: const ValueKey('recurring-fields'),
          dailyTargetController: _dailyTargetController,
          unitNoun: _nounForCount(2),
          validateDailyTarget: _validateDailyTarget,
        );
      case StudyPlanKind.singleTask:
        return const _BehaviorNote(
          key: ValueKey('single-task-note'),
          icon: Icons.task_alt_rounded,
          text: 'A single task appears once on the chosen day. If it is not checked off, it moves into Study Debt for you to decide what to do with it.',
        );
      case StudyPlanKind.deadline:
        return const _BehaviorNote(
          key: ValueKey('deadline-note'),
          icon: Icons.flag_rounded,
          text: 'A deadline is a marker, not workload. It appears on the calendar and adds pressure/context without being redistributed as debt.',
        );
      case StudyPlanKind.checklist:
        return _ChecklistFields(
          key: const ValueKey('checklist-fields'),
          controller: _checklistController,
          validator: _validateChecklist,
        );
      case StudyPlanKind.progress:
      default:
        return _ProgressFields(
          key: const ValueKey('progress-fields'),
          startUnitController: _startUnitController,
          endUnitController: _endUnitController,
          startLabel: _startLabel(),
          endLabel: _endLabel(),
          validateUnit: _validateUnit,
          validateEndUnit: _validateEndUnit,
        );
    }
  }

  Widget _dateControls() {
    if (_usesTaskDate) {
      return _DatePickerTile(
        label: _planKind == StudyPlanKind.deadline ? 'Deadline date' : 'Task date',
        value: _taskDate,
        onPick: () => _pickDate(target: _DateTarget.task),
        emptyLabel: 'Pick date',
      );
    }

    return Row(
      children: [
        Expanded(
          child: _DatePickerTile(
            label: 'Start date',
            value: _startDate,
            onPick: () => _pickDate(target: _DateTarget.start),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DatePickerTile(
            label: _planKind == StudyPlanKind.recurring ? 'End date' : 'Deadline',
            value: _deadline,
            onPick: () => _pickDate(target: _DateTarget.deadline),
            onClear: _planKind == StudyPlanKind.recurring
                ? () => setState(() => _deadline = null)
                : null,
            emptyLabel: _planKind == StudyPlanKind.recurring
                ? 'Running project'
                : 'Pick deadline',
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required _DateTarget target}) async {
    final now = DateTime.now();
    final DateTime initial;
    if (target == _DateTarget.start) {
      initial = _startDate;
    } else if (target == _DateTarget.deadline) {
      initial = _deadline ?? widget.project.deadline ?? _startDate.add(const Duration(days: 21));
    } else {
      initial = _taskDate ?? widget.project.deadline ?? _startDate;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;

    setState(() {
      final normalized = DateTime(picked.year, picked.month, picked.day);
      switch (target) {
        case _DateTarget.start:
          _startDate = normalized;
          if (_deadline != null && _deadline!.isBefore(_startDate)) {
            _deadline = _startDate;
          }
          break;
        case _DateTarget.deadline:
          _deadline = normalized;
          if (_startDate.isAfter(_deadline!)) _startDate = _deadline!;
          break;
        case _DateTarget.task:
          _taskDate = normalized;
          break;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_planKind == StudyPlanKind.progress || _planKind == StudyPlanKind.checklist) && _deadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This type needs a deadline.')),
      );
      return;
    }
    if (_usesTaskDate && _taskDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a date.')),
      );
      return;
    }

    setState(() => _saving = true);

    final plan = await widget.planningRepository.createPlan(
      projectId: widget.project.id,
      title: _titleController.text,
      planKind: _planKind,
      unitType: _unitTypeForSave(),
      startUnit: _planKind == StudyPlanKind.progress
          ? int.parse(_startUnitController.text.trim())
          : null,
      endUnit: _planKind == StudyPlanKind.progress
          ? int.parse(_endUnitController.text.trim())
          : null,
      dailyTarget: _planKind == StudyPlanKind.recurring
          ? int.parse(_dailyTargetController.text.trim())
          : null,
      startDate: _startDate,
      deadline: _planKind == StudyPlanKind.singleTask
          ? _taskDate
          : _planKind == StudyPlanKind.deadline
              ? _taskDate
              : _deadline,
      taskDate: _usesTaskDate ? _taskDate : null,
      weekendsOff: _usesWeekends ? _weekendsOff : false,
      customUnitSingular: _unitType == 'custom' && _usesUnits ? _customSingularController.text : null,
      customUnitPlural: _unitType == 'custom' && _usesUnits ? _customPluralController.text : null,
      customUnitLabel: _unitType == 'custom' && _usesUnits
          ? (_customLabelController.text.trim().isEmpty
              ? _customSingularController.text
              : _customLabelController.text)
          : null,
      checklistItems: _planKind == StudyPlanKind.checklist ? _checklistItems() : null,
    );

    if (!mounted) return;
    Navigator.of(context).pop(plan);
  }

  String _unitTypeForSave() {
    if (_planKind == StudyPlanKind.singleTask) return 'task';
    if (_planKind == StudyPlanKind.deadline) return 'deadline';
    if (_planKind == StudyPlanKind.checklist) return 'topic';
    return _unitType;
  }

  List<String> _checklistItems() {
    return _checklistController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _hintForKind() {
    switch (_planKind) {
      case StudyPlanKind.recurring:
        return 'Daily case practice';
      case StudyPlanKind.singleTask:
        return 'Submit assignment';
      case StudyPlanKind.deadline:
        return 'Exam';
      case StudyPlanKind.checklist:
        return 'Review exam topics';
      case StudyPlanKind.progress:
      default:
        return 'Read textbook';
    }
  }

  String _defaultTitleForState() {
    switch (_planKind) {
      case StudyPlanKind.recurring:
        return 'Daily ${_nounForCount(1)} practice';
      case StudyPlanKind.singleTask:
        return 'New task';
      case StudyPlanKind.deadline:
        return 'Deadline';
      case StudyPlanKind.checklist:
        return 'Checklist';
      case StudyPlanKind.progress:
      default:
        switch (_unitType) {
          case 'pages':
            return 'Read pages';
          case 'chapters':
            return 'Read chapters';
          case 'sections':
            return 'Finish sections';
          case 'exercises':
            return 'Solve exercises';
          default:
            return 'Complete custom units';
        }
    }
  }

  Set<String> get _knownDefaultTitles => const {
        'Read pages',
        'Read chapters',
        'Finish sections',
        'Solve exercises',
        'Complete units',
        'Complete custom units',
        'Daily page practice',
        'Daily chapter practice',
        'Daily section practice',
        'Daily exercise practice',
        'Daily unit practice',
        'New task',
        'Deadline',
        'Checklist',
      };

  String _startLabel() {
    switch (_unitType) {
      case 'pages':
        return 'First page';
      case 'chapters':
        return 'First chapter';
      case 'sections':
        return 'First section';
      case 'exercises':
        return 'First exercise';
      default:
        return 'First ${_customSingularOrFallback()}';
    }
  }

  String _endLabel() {
    switch (_unitType) {
      case 'pages':
        return 'Last page';
      case 'chapters':
        return 'Last chapter';
      case 'sections':
        return 'Last section';
      case 'exercises':
        return 'Last exercise';
      default:
        return 'Last ${_customSingularOrFallback()}';
    }
  }

  String? _previewText() {
    if (_planKind == StudyPlanKind.recurring) {
      final target = int.tryParse(_dailyTargetController.text.trim());
      if (target == null || target < 1) return null;
      final noun = _nounForCount(target);
      final period = _deadline == null
          ? 'from ${_formatDate(_startDate)} until you remove it'
          : 'from ${_formatDate(_startDate)} to ${_formatDate(_deadline!)}';
      final weekendText = _weekendsOff ? 'weekdays only' : 'every calendar day';
      return 'The calendar will create “${_titleOrDefault()} · $target $noun” $weekendText, $period. If you do not check a day off, it becomes study debt instead of silently disappearing.';
    }

    if (_planKind == StudyPlanKind.singleTask) {
      final date = _taskDate == null ? 'the chosen date' : _formatDate(_taskDate!);
      return 'The calendar will show “${_titleOrDefault()}” once on $date. If it is missed, it moves into Study Debt as an unresolved task.';
    }

    if (_planKind == StudyPlanKind.deadline) {
      final date = _taskDate == null ? 'the chosen date' : _formatDate(_taskDate!);
      return 'The calendar will show “${_titleOrDefault()}” as a deadline marker on $date. It adds context and pressure but is not redistributed as work.';
    }

    if (_planKind == StudyPlanKind.checklist) {
      final items = _checklistItems();
      if (items.isEmpty || _deadline == null) return null;
      final days = _eligibleDays(_startDate, _deadline!, _weekendsOff);
      if (days.isEmpty) return 'No eligible study days. Turn weekends on or change the dates.';
      final perDay = items.length / days.length;
      return '${items.length} checklist items across ${days.length} study days → about ${_formatPace(perDay)} items per study day. The calendar will place named items like “${items.first}”. Missed items become visible study debt.';
    }

    final start = int.tryParse(_startUnitController.text.trim());
    final end = int.tryParse(_endUnitController.text.trim());
    if (start == null || end == null || start < 1 || end < start || _deadline == null) {
      return null;
    }

    final days = _eligibleDays(_startDate, _deadline!, _weekendsOff);
    if (days.isEmpty) {
      return 'No eligible study days. Turn weekends on or change the dates.';
    }

    final total = end - start + 1;
    final perDay = total / days.length;
    final noun = _nounForCount(total);
    final shortLabel = _shortUnitLabel();
    final exampleEnd = (start + perDay.ceil() - 1).clamp(start, end).toInt();
    final exampleRange = start == exampleEnd
        ? '$shortLabel $start'
        : '$shortLabel $start–$exampleEnd';

    return '$total $noun across ${days.length} study days → about ${_formatPace(perDay)} ${_nounForCount(perDay.round().clamp(1, 999999).toInt())} per study day. The calendar will say things like “${_titleOrDefault()} · $exampleRange”. If you miss a day, the remaining pace increases instead of dumping everything onto tomorrow.';
  }

  String _titleOrDefault() {
    final value = _titleController.text.trim();
    return value.isEmpty ? _defaultTitleForState() : value;
  }

  String? _validateUnit(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1) return 'Use a number above 0.';
    return null;
  }

  String? _validateEndUnit(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    final start = int.tryParse(_startUnitController.text.trim());
    if (parsed == null || parsed < 1) return 'Use a number above 0.';
    if (start != null && parsed < start) return 'End must be after start.';
    return null;
  }

  String? _validateDailyTarget(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1) return 'Use a number above 0.';
    return null;
  }

  String? _validateChecklist(String? value) {
    final lines = value
            ?.split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .length ??
        0;
    if (lines == 0) return 'Add at least one item.';
    return null;
  }

  String? _validateCustomSingular(String? value) {
    if (_unitType != 'custom' || !_usesUnits) return null;
    if (value == null || value.trim().isEmpty) {
      return 'Name one unit.';
    }
    return null;
  }

  String? _validateCustomPlural(String? value) {
    if (_unitType != 'custom' || !_usesUnits) return null;
    if (value == null || value.trim().isEmpty) {
      return 'Name multiple units.';
    }
    return null;
  }

  String _customSingularOrFallback() {
    final value = _customSingularController.text.trim();
    return value.isEmpty ? 'unit' : value;
  }

  String _customPluralOrFallback() {
    final value = _customPluralController.text.trim();
    if (value.isNotEmpty) return value;
    final singular = _customSingularController.text.trim();
    if (singular.isNotEmpty) return '${singular}s';
    return 'units';
  }

  String _shortUnitLabel() {
    if (_unitType == 'custom') {
      final label = _customLabelController.text.trim();
      if (label.isNotEmpty) return label;
      return _customSingularOrFallback();
    }

    switch (_unitType) {
      case 'pages':
        return 'pp.';
      case 'chapters':
        return 'ch.';
      case 'sections':
        return 'sec.';
      case 'exercises':
        return 'ex.';
      default:
        return 'unit';
    }
  }

  String _nounForCount(int count) {
    if (_unitType == 'custom') {
      return count == 1 ? _customSingularOrFallback() : _customPluralOrFallback();
    }

    switch (_unitType) {
      case 'pages':
        return count == 1 ? 'page' : 'pages';
      case 'chapters':
        return count == 1 ? 'chapter' : 'chapters';
      case 'sections':
        return count == 1 ? 'section' : 'sections';
      case 'exercises':
        return count == 1 ? 'exercise' : 'exercises';
      default:
        return count == 1 ? 'unit' : 'units';
    }
  }
}

enum _DateTarget { start, deadline, task }

class _ProgressFields extends StatelessWidget {
  final TextEditingController startUnitController;
  final TextEditingController endUnitController;
  final String startLabel;
  final String endLabel;
  final FormFieldValidator<String> validateUnit;
  final FormFieldValidator<String> validateEndUnit;

  const _ProgressFields({
    super.key,
    required this.startUnitController,
    required this.endUnitController,
    required this.startLabel,
    required this.endLabel,
    required this.validateUnit,
    required this.validateEndUnit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: startUnitController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: startLabel,
              border: const OutlineInputBorder(),
            ),
            validator: validateUnit,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: endUnitController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: endLabel,
              border: const OutlineInputBorder(),
            ),
            validator: validateEndUnit,
          ),
        ),
      ],
    );
  }
}

class _RecurringFields extends StatelessWidget {
  final TextEditingController dailyTargetController;
  final String unitNoun;
  final FormFieldValidator<String> validateDailyTarget;

  const _RecurringFields({
    super.key,
    required this.dailyTargetController,
    required this.unitNoun,
    required this.validateDailyTarget,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: dailyTargetController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'How many $unitNoun per study day?',
        hintText: '3',
        helperText: 'Example: 3 cases/day, 2 past papers/day, 5 flashcards/day.',
        border: const OutlineInputBorder(),
      ),
      validator: validateDailyTarget,
    );
  }
}

class _ChecklistFields extends StatelessWidget {
  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  const _ChecklistFields({
    super.key,
    required this.controller,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: 5,
      maxLines: 10,
      decoration: const InputDecoration(
        labelText: 'Checklist items / topics',
        hintText: 'IS-LM\nPhillips curve\nMundell-Fleming',
        helperText: 'One item per line. The calendar will distribute the named items across study days.',
        border: OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}

class _BehaviorNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BehaviorNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  final StudyProject project;

  const _ProjectHeader({required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(
            Icons.dashboard_customize_rounded,
            color: theme.colorScheme.onPrimaryContainer,
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  project.deadline == null
                      ? 'Running project'
                      : 'Project · deadline ${_formatDate(project.deadline!)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withAlpha(210),
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

class _CustomUnitDefinitionCard extends StatelessWidget {
  final TextEditingController singularController;
  final TextEditingController pluralController;
  final TextEditingController labelController;
  final FormFieldValidator<String> singularValidator;
  final FormFieldValidator<String> pluralValidator;

  const _CustomUnitDefinitionCard({
    required this.singularController,
    required this.pluralController,
    required this.labelController,
    required this.singularValidator,
    required this.pluralValidator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.edit_note_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tell the app how to talk about this plan.',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Use this for topics, articles, lectures, cases, problem sets, past papers, flashcards, or any other unit you want to see on the calendar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: singularController,
                  decoration: const InputDecoration(
                    labelText: 'One unit is called',
                    hintText: 'case',
                    border: OutlineInputBorder(),
                  ),
                  validator: singularValidator,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: pluralController,
                  decoration: const InputDecoration(
                    labelText: 'Multiple units are called',
                    hintText: 'cases',
                    border: OutlineInputBorder(),
                  ),
                  validator: pluralValidator,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: labelController,
            decoration: const InputDecoration(
              labelText: 'Short calendar label',
              hintText: 'case, art., lec., topic',
              helperText: 'Optional. Used in finite plans like “case 1–3”.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String emptyLabel;

  const _DatePickerTile({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
    this.emptyLabel = 'No date',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null ? emptyLabel : _formatDate(value!),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (onClear != null && value != null)
              IconButton(
                tooltip: 'Clear date',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final String text;

  const _PreviewBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(80)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

List<DateTime> _eligibleDays(DateTime start, DateTime end, bool weekendsOff) {
  final result = <DateTime>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!cursor.isAfter(last)) {
    final weekend = cursor.weekday == DateTime.saturday || cursor.weekday == DateTime.sunday;
    if (!weekendsOff || !weekend) result.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  return result;
}

String _formatPace(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
