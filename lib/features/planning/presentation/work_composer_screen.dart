import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../library/data/pdf_metadata_extractor.dart';
import '../data/study_material_outline_reader.dart';
import '../data/study_planning_repository.dart';
import '../domain/planning_draft.dart';
import '../domain/planning_intake_engine.dart';
import '../domain/planning_intent.dart';
import '../domain/study_material_source.dart';

enum _TimePlanInputMode { duration, window }

class WorkComposerScreen extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final StudyProject project;
  final PlanningIntentType initialIntent;
  final AppDatabase? database;
  final StudyMaterialSource? initialMaterialSource;

  const WorkComposerScreen({
    super.key,
    required this.planningRepository,
    required this.project,
    this.initialIntent = PlanningIntentType.studyMaterial,
    this.database,
    this.initialMaterialSource,
  });

  @override
  State<WorkComposerScreen> createState() => _WorkComposerScreenState();
}

class _WorkComposerScreenState extends State<WorkComposerScreen> {
  static const _engine = PlanningIntakeEngine();

  final _formKey = GlobalKey<FormState>();
  final _quickController = TextEditingController();
  final _titleController = TextEditingController();
  final _startUnitController = TextEditingController();
  final _endUnitController = TextEditingController();
  final _dailyTargetController = TextEditingController();
  final _timeHoursController = TextEditingController(text: '1');
  final _timeMinutesController = TextEditingController();
  final _timeStartController = TextEditingController();
  final _timeEndController = TextEditingController();
  final _checklistController = TextEditingController();
  final _customSingularController = TextEditingController();
  final _customPluralController = TextEditingController();
  final _customLabelController = TextEditingController();
  final _sourceTitleController = TextEditingController();
  final _sourceLinkController = TextEditingController();
  final _sourceStartPageController = TextEditingController();
  final _sourceEndPageController = TextEditingController();
  final _sourceNotesController = TextEditingController();
  final _chapterTitleController = TextEditingController();

  late PlanningDraft _draft;
  bool _planByTime = false;
  _TimePlanInputMode _timePlanInputMode = _TimePlanInputMode.duration;
  bool _saving = false;
  bool _updatingControllers = false;
  _StudyMaterialSourceType _materialSource = _StudyMaterialSourceType.noSourceYet;
  StudyMaterialSource? _resolvedMaterialSource;
  bool _loadingLibrarySource = false;
  bool _loadingReaderSource = false;
  final _newChecklistItemController = TextEditingController();
  List<String> _userChapterTitles = <String>[];
  Set<String> _selectedDetectedChapterKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _draft = _engine.draftFromIntent(widget.initialIntent, _context());
    _syncControllersFromDraft();
    _applyInitialMaterialSourceIfNeeded();
    for (final controller in [
      _titleController,
      _startUnitController,
      _endUnitController,
      _dailyTargetController,
      _timeHoursController,
      _timeMinutesController,
      _timeStartController,
      _timeEndController,
      _checklistController,
      _customSingularController,
      _customPluralController,
      _customLabelController,
    ]) {
      controller.addListener(_refreshDraftFromControllers);
    }
  }

  @override
  void dispose() {
    _quickController.dispose();
    _titleController.dispose();
    _startUnitController.dispose();
    _endUnitController.dispose();
    _dailyTargetController.dispose();
    _timeHoursController.dispose();
    _timeMinutesController.dispose();
    _timeStartController.dispose();
    _timeEndController.dispose();
    _checklistController.dispose();
    _customSingularController.dispose();
    _customPluralController.dispose();
    _customLabelController.dispose();
    _sourceTitleController.dispose();
    _sourceLinkController.dispose();
    _sourceStartPageController.dispose();
    _sourceEndPageController.dispose();
    _sourceNotesController.dispose();
    _chapterTitleController.dispose();
    _newChecklistItemController.dispose();
    super.dispose();
  }

  PlanningIntakeContext _context() {
    return PlanningIntakeContext(project: widget.project, now: DateTime.now());
  }

  String _screenTitle() {
    switch (_draft.intent) {
      case PlanningIntentType.studyMaterial:
        return 'Plan study material';
      case PlanningIntentType.writeSomething:
        return 'Plan writing';
      case PlanningIntentType.finishByDate:
        return 'Plan work-through';
      case PlanningIntentType.addTask:
        return 'Add task';
      case PlanningIntentType.rememberDeadline:
        return 'Add deadline';
      case PlanningIntentType.reviewTopics:
        return 'Build topic checklist';
      case PlanningIntentType.buildRoutine:
        return 'Build routine';
    }
  }

  String _formIntroText() {
    switch (_draft.intent) {
      case PlanningIntentType.studyMaterial:
        return 'Choose the material first, then decide how progress should be measured and spread across study days.';
      case PlanningIntentType.writeSomething:
        return 'Writing usually mixes research, drafting, revision, formatting, and references. Start with the output target for now.';
      case PlanningIntentType.finishByDate:
        return 'Use this when you need to move through a measurable amount of work between two dates.';
      case PlanningIntentType.addTask:
        return 'Use this for one concrete thing that should appear on a chosen day.';
      case PlanningIntentType.rememberDeadline:
        return 'Use this for an important due date or milestone. It adds calendar pressure without creating workload by itself.';
      case PlanningIntentType.reviewTopics:
        return 'Build a named set of topics/items that can be distributed across the chosen dates.';
      case PlanningIntentType.buildRoutine:
        return 'Use this for repeated work that should keep appearing on eligible study days.';
    }
  }

  void _syncControllersFromDraft() {
    _updatingControllers = true;
    _titleController.text = _draft.title;
    _startUnitController.text = _draft.startUnit.toString();
    _endUnitController.text = _draft.endUnit.toString();
    _dailyTargetController.text = _draft.dailyTarget.toString();
    _checklistController.text = _draft.checklistItems.join('\n');
    _customSingularController.text = _draft.customUnitSingular ?? '';
    _customPluralController.text = _draft.customUnitPlural ?? '';
    _customLabelController.text = _draft.customUnitLabel ?? '';
    _updatingControllers = false;
  }

  void _applyInitialMaterialSourceIfNeeded() {
    final source = widget.initialMaterialSource;
    if (source == null || widget.initialIntent != PlanningIntentType.studyMaterial) return;
    _applyResolvedMaterialSource(source, forcePages: true, notify: false);
  }

  void _applyResolvedMaterialSource(
    StudyMaterialSource source, {
    bool forcePages = false,
    bool notify = true,
  }) {
    void apply() {
      _resolvedMaterialSource = source;
      _materialSource = _sourceTypeFromStorage(source.type);
      _sourceTitleController.text = source.title;
      final currentTitle = _titleController.text.trim();
      if (_draft.intent == PlanningIntentType.studyMaterial &&
          (currentTitle.isEmpty || currentTitle == PlanningIntentType.studyMaterial.defaultTitle)) {
        _titleController.text = source.title;
        _draft = _draft.copyWith(title: source.title);
      }
      _sourceLinkController.text = source.url ?? '';
      _sourceStartPageController.text = source.startPage?.toString() ?? '';
      _sourceEndPageController.text = source.endPage?.toString() ?? '';
      _sourceNotesController.text = source.notes ?? '';
      _userChapterTitles = <String>[];
      _selectedDetectedChapterKeys = <String>{};

      final startPage = source.startPage ?? (source.pageCount == null ? null : 1);
      final endPage = source.endPage ?? source.pageCount;
      if (forcePages && startPage != null && endPage != null && endPage >= startPage) {
        _startUnitController.text = startPage.toString();
        _endUnitController.text = endPage.toString();
        _draft = _draft.copyWith(
          unitType: 'pages',
          startUnit: startPage,
          endUnit: endPage,
        );
        _draft = _draft.copyWith(questions: _engine.questionsFor(_draft));
      }
    }

    if (notify && mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  _StudyMaterialSourceType _sourceTypeFromStorage(String type) {
    switch (StudyMaterialSourceType.normalize(type)) {
      case StudyMaterialSourceType.currentFile:
        return _StudyMaterialSourceType.currentFile;
      case StudyMaterialSourceType.libraryFile:
        return _StudyMaterialSourceType.libraryFile;
      case StudyMaterialSourceType.pdfFile:
      case StudyMaterialSourceType.epubFile:
        return _StudyMaterialSourceType.readerFile;
      case StudyMaterialSourceType.physicalBook:
        return _StudyMaterialSourceType.physicalBook;
      case StudyMaterialSourceType.articleOrWebsite:
        return _StudyMaterialSourceType.articleOrWebsite;
      case StudyMaterialSourceType.noSourceYet:
      default:
        return _StudyMaterialSourceType.noSourceYet;
    }
  }

  bool get _pagesUnavailableForCurrentSource =>
      _draft.intent == PlanningIntentType.studyMaterial &&
      _resolvedMaterialSource?.type == StudyMaterialSourceType.epubFile &&
      _resolvedMaterialSource?.pageCount == null;

  List<StudyMaterialSegment> _detectedChapterSegments([StudyMaterialSource? source]) {
    final resolved = source ?? _resolvedMaterialSource;
    return resolved?.segments
            .where((segment) => segment.type == StudyMaterialSegmentType.chapter)
            .where((segment) => segment.title.trim().isNotEmpty)
            .toList(growable: false) ??
        const <StudyMaterialSegment>[];
  }

  String _detectedChapterKey(StudyMaterialSegment segment, int index) {
    final id = segment.id.trim();
    if (id.isNotEmpty) return id;
    return 'detected-$index-${segment.title.trim().toLowerCase()}-${segment.href ?? segment.startPage ?? ''}';
  }

  List<StudyMaterialSegment> _selectedDetectedChapterSegments([StudyMaterialSource? source]) {
    final detected = _detectedChapterSegments(source);
    final selected = <StudyMaterialSegment>[];
    for (var i = 0; i < detected.length; i++) {
      if (_selectedDetectedChapterKeys.contains(_detectedChapterKey(detected[i], i))) {
        selected.add(detected[i]);
      }
    }
    return selected;
  }

  void _refreshDraftFromControllers() {
    if (!mounted || _updatingControllers) return;
    setState(() {
      _draft = _draft.copyWith(
        title: _titleController.text.trim(),
        startUnit: int.tryParse(_startUnitController.text.trim()) ?? _draft.startUnit,
        endUnit: int.tryParse(_endUnitController.text.trim()) ?? _draft.endUnit,
        dailyTarget: int.tryParse(_dailyTargetController.text.trim()) ?? _draft.dailyTarget,
        checklistItems: _checklistItems(),
        customUnitSingular: _customSingularController.text.trim().isEmpty
            ? null
            : _customSingularController.text.trim(),
        clearCustomUnitSingular: _customSingularController.text.trim().isEmpty,
        customUnitPlural: _customPluralController.text.trim().isEmpty
            ? null
            : _customPluralController.text.trim(),
        clearCustomUnitPlural: _customPluralController.text.trim().isEmpty,
        customUnitLabel: _customLabelController.text.trim().isEmpty
            ? null
            : _customLabelController.text.trim(),
        clearCustomUnitLabel: _customLabelController.text.trim().isEmpty,
      );
      _draft = _draft.copyWith(questions: _engine.questionsFor(_draft));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(_screenTitle()),
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _ComposerPathHeader(
                  project: widget.project,
                  draft: _draft,
                ),
                const SizedBox(height: 16),
                _DetailsCard(child: _buildForm(context)),
                const SizedBox(height: 16),
                _PreviewPanel(draft: _draft, previewLines: _previewLines()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _screenTitle(),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formIntroText(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (_draft.questions.isNotEmpty) ...[
                const SizedBox(width: 12),
                _MissingBadge(count: _draft.questions.length),
              ],
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: _titleLabel(),
              hintText: _titleHint(),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Give this work a name.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _adaptiveFields(),
          if (_draft.usesStartDate || _draft.usesSingleDate) ...[
            const SizedBox(height: 14),
            _dateControls(),
          ],
          if (_draft.usesWeekends) ...[
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: !_draft.weekendsOff,
              contentPadding: EdgeInsets.zero,
              title: Text(_draft.weekendsOff ? 'Weekends are excluded' : 'Weekends are included'),
              subtitle: Text(
                _draft.weekendsOff
                    ? 'Turn this on to count Saturday and Sunday as eligible study days.'
                    : 'Turn this off to keep Saturday and Sunday out of this plan.',
              ),
              onChanged: (value) => setState(() => _draft = _draft.copyWith(weekendsOff: !value)),
            ),
          ],
          if (_draft.usesDueDate &&
              _draft.dueDate != null &&
              !(_planByTime && _draft.storageKind == StudyPlanKind.progress)) ...[
            const SizedBox(height: 10),
            _ScheduleDistributionPreview(
              startDate: _draft.startDate,
              dueDate: _draft.dueDate!,
              weekendsOff: _draft.weekendsOff,
              totalUnits: _planByTime && _draft.storageKind == StudyPlanKind.progress
                  ? (_timePlanMinutes() ?? 0)
                  : _draft.storageKind == StudyPlanKind.checklist
                      ? _checklistItems().length
                      : _draft.totalUnits,
              unitLabel: _planByTime && _draft.storageKind == StudyPlanKind.progress
                  ? 'minutes each study day'
                  : _draft.storageKind == StudyPlanKind.checklist
                      ? (_checklistItems().length == 1 ? 'item' : 'items')
                      : _nounForCount(_draft.totalUnits),
            ),
          ],
          if (_draft.questions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _MissingDetailsCard(questions: _draft.questions),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'This will still become structured planning data for Today, Calendar, debt, and future replanning.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_draft.intent.actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adaptiveFields() {
    switch (_draft.storageKind) {
      case StudyPlanKind.recurring:
        return Column(
          children: [
            _unitControls(forRoutine: true),
            const SizedBox(height: 14),
            _DailyTargetCard(
              controller: _dailyTargetController,
              unitLabel: _nounForCount(_draft.dailyTarget),
              validator: _validatePositiveNumber,
            ),
          ],
        );
      case StudyPlanKind.singleTask:
        return const _BehaviorNote(
          icon: Icons.task_alt_rounded,
          title: 'One concrete action',
          text: 'A task appears on one day. If it is not completed, it becomes visible study debt instead of disappearing.',
        );
      case StudyPlanKind.deadline:
        return const _BehaviorNote(
          icon: Icons.flag_rounded,
          title: 'A pressure point, not workload',
          text: 'A deadline is shown in Today, Calendar, and project views. It does not generate work unless you add preparation work separately.',
        );
      case StudyPlanKind.checklist:
        return _ChecklistBuilderCard(
          items: _checklistItems(),
          addController: _newChecklistItemController,
          onAdd: _addChecklistItemsFromInput,
          onRemove: _removeChecklistItem,
        );
      case StudyPlanKind.progress:
      default:
        if (_draft.intent == PlanningIntentType.studyMaterial) {
          return _studyMaterialFields();
        }
        if (_draft.intent == PlanningIntentType.writeSomething) {
          return _writingFields();
        }
        return _workThroughFields();
    }
  }

  Widget _studyMaterialFields() {
    return Column(
      children: [
        _StudyMaterialSourceCard(
          selectedType: _materialSource,
          hasCurrentFile: widget.initialMaterialSource != null,
          canChooseLibraryFile: widget.database != null,
          currentFileTitle: widget.initialMaterialSource?.title,
          loadingLibrarySource: _loadingLibrarySource,
          loadingReaderSource: _loadingReaderSource,
          onChanged: _handleMaterialSourceChoice,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _materialSource == _StudyMaterialSourceType.noSourceYet
              ? const SizedBox.shrink(key: ValueKey('no-material-source-details'))
              : Padding(
                  key: ValueKey('material-source-details-${_materialSource.name}'),
                  padding: const EdgeInsets.only(top: 14),
                  child: _MaterialSourceDetailsCard(
                    type: _materialSource,
                    titleController: _sourceTitleController,
                    linkController: _sourceLinkController,
                    startPageController: _sourceStartPageController,
                    endPageController: _sourceEndPageController,
                    notesController: _sourceNotesController,
                    resolvedSource: _resolvedMaterialSource,
                    onChanged: _handleMaterialSourceDetailsChanged,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        _planModeCard(),
        const SizedBox(height: 14),
        if (_planByTime)
          _timePlanCard()
        else ...[
          _unitControls(title: 'How should progress be measured?', helper: _studyMeasurementHelper()),
          const SizedBox(height: 14),
          if (_draft.unitType == 'chapters')
            _ChapterStructureCard(
              chapters: _chapterTitles(),
              detectedSegments: _detectedChapterSegments(),
              selectedDetectedKeys: _selectedDetectedChapterKeys,
              keyForDetected: _detectedChapterKey,
              addController: _chapterTitleController,
              onAdd: _addChapterTitlesFromInput,
              onRemove: _removeChapterTitle,
              onToggleDetected: _toggleDetectedChapter,
              onSelectAllDetected: _selectAllDetectedChapters,
              onClearDetected: _clearDetectedChapters,
              sourceTitle: _sourceTitleController.text.trim().isEmpty ? null : _sourceTitleController.text.trim(),
            )
          else
            _RangePlannerCard(
              startController: _startUnitController,
              endController: _endUnitController,
              startLabel: _startUnitLabel(),
              endLabel: _endUnitLabel(),
              totalUnits: _draft.totalUnits,
              totalLabel: _nounForCount(_draft.totalUnits),
              shortLabel: _unitShortLabel(),
              explanation: _rangeExplanation(),
              startValidator: _validatePositiveNumber,
              endValidator: _rangeEndValidator,
            ),
        ],
      ],
    );
  }

  Widget _writingFields() {
    return Column(
      children: [
        const _BehaviorNote(
          icon: Icons.edit_note_rounded,
          title: 'Writing has phases',
          text: 'A full writing workflow should eventually split research, outlining, drafting, revision, formatting, and references. This first version plans the measurable output target.',
        ),
        const SizedBox(height: 14),
        _planModeCard(),
        const SizedBox(height: 14),
        if (_planByTime)
          _timePlanCard()
        else ...[
          _unitControls(title: 'What output should be tracked?', helper: 'Use sections, words, pages, revision passes, or define your own output unit.'),
          const SizedBox(height: 14),
          _RangePlannerCard(
            startController: _startUnitController,
            endController: _endUnitController,
            startLabel: _startUnitLabel(),
            endLabel: _endUnitLabel(),
            totalUnits: _draft.totalUnits,
            totalLabel: _nounForCount(_draft.totalUnits),
            shortLabel: _unitShortLabel(),
            explanation: _rangeExplanation(),
            startValidator: _validatePositiveNumber,
            endValidator: _rangeEndValidator,
          ),
        ],
      ],
    );
  }

  Widget _workThroughFields() {
    return Column(
      children: [
        _planModeCard(),
        const SizedBox(height: 14),
        if (_planByTime)
          _timePlanCard()
        else ...[
          _unitControls(title: 'How should the work be measured?', helper: 'Choose the measurable unit that best matches this work. Custom units are first-class.'),
          const SizedBox(height: 14),
          _RangePlannerCard(
            startController: _startUnitController,
            endController: _endUnitController,
            startLabel: _startUnitLabel(),
            endLabel: _endUnitLabel(),
            totalUnits: _draft.totalUnits,
            totalLabel: _nounForCount(_draft.totalUnits),
            shortLabel: _unitShortLabel(),
            explanation: _rangeExplanation(),
            startValidator: _validatePositiveNumber,
            endValidator: _rangeEndValidator,
          ),
        ],
      ],
    );
  }

  Widget _planModeCard() {
    return _PlanModeCard(
      byTime: _planByTime,
      onChanged: (value) {
        setState(() {
          _planByTime = value;
          if (_planByTime && _timeHoursController.text.trim().isEmpty && _timeMinutesController.text.trim().isEmpty) {
            _timeHoursController.text = '1';
          }
        });
      },
    );
  }

  Widget _timePlanCard() {
    return _TimePlanCard(
      inputMode: _timePlanInputMode,
      hoursController: _timeHoursController,
      minutesController: _timeMinutesController,
      startController: _timeStartController,
      endController: _timeEndController,
      onInputModeChanged: (mode) {
        final flexibleDuration = _durationPlanMinutes();
        setState(() {
          _timePlanInputMode = mode;
          if (mode == _TimePlanInputMode.window) {
            _ensureTimeWindowDefaults(flexibleDuration ?? 60);
          }
        });
      },
      onChanged: () => setState(() {}),
    );
  }

  int? _durationPlanMinutes() {
    final hours = int.tryParse(_timeHoursController.text.trim().isEmpty ? '0' : _timeHoursController.text.trim());
    final minutes = int.tryParse(_timeMinutesController.text.trim().isEmpty ? '0' : _timeMinutesController.text.trim());
    if (hours == null || minutes == null || hours < 0 || minutes < 0 || minutes > 59) return null;
    final total = hours * 60 + minutes;
    return total > 0 ? total : null;
  }

  void _ensureTimeWindowDefaults(int durationMinutes) {
    final normalizedDuration = durationMinutes.clamp(15, 8 * 60).toInt();
    final existingStart = _parseMinuteOfDay(_timeStartController.text);
    final start = existingStart ?? 8 * 60;
    final end = (start + normalizedDuration).clamp(start + 15, 23 * 60 + 59).toInt();
    if (_timeStartController.text.trim().isEmpty) {
      _timeStartController.text = _formatMinuteOfDay(start);
    }
    if (_timeEndController.text.trim().isEmpty) {
      _timeEndController.text = _formatMinuteOfDay(end);
    }
  }

  int? _timePlanMinutes() {
    if (_timePlanInputMode == _TimePlanInputMode.window) {
      final start = _parseMinuteOfDay(_timeStartController.text);
      final end = _parseMinuteOfDay(_timeEndController.text);
      if (start == null || end == null || end <= start) return null;
      return end - start;
    }
    return _durationPlanMinutes();
  }

  int? _timeWindowStartMinutes() {
    if (_timePlanInputMode != _TimePlanInputMode.window) return null;
    return _parseMinuteOfDay(_timeStartController.text);
  }

  int? _timeWindowEndMinutes() {
    if (_timePlanInputMode != _TimePlanInputMode.window) return null;
    return _parseMinuteOfDay(_timeEndController.text);
  }

  int? _parseMinuteOfDay(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.replaceAll('.', ':').split(':');
    if (parts.isEmpty || parts.length > 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = parts.length == 2 ? int.tryParse(parts[1]) : 0;
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String _formatMinutesForPlan(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours > 0 && remainder > 0) return '${hours}h ${remainder}m';
    if (hours > 0) return hours == 1 ? '1 hour' : '$hours hours';
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  String? _timeWindowPreview() {
    final start = _timeWindowStartMinutes();
    final end = _timeWindowEndMinutes();
    if (start == null || end == null || end <= start) return null;
    return '${_formatMinuteOfDay(start)}–${_formatMinuteOfDay(end)}';
  }

  String _formatMinuteOfDay(int value) {
    final minutes = value.clamp(0, 23 * 60 + 59).toInt();
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  String? _rangeEndValidator(String? value) {
    final end = int.tryParse(value?.trim() ?? '');
    final start = int.tryParse(_startUnitController.text.trim());
    if (end == null || end < 1) return 'Use a number above 0.';
    if (start != null && end < start) return 'End must be after start.';
    return null;
  }

  String _studyMeasurementHelper() {
    if (_pagesUnavailableForCurrentSource) {
      return 'This EPUB exposes a table of contents, not stable page numbers. Use Chapters to pick exact TOC entries, or define custom chunks.';
    }
    switch (_draft.unitType) {
      case 'pages':
        return 'Best for readings because pages can be distributed evenly and reviewed precisely.';
      case 'chapters':
        return 'Use chapters only when the material provides chapter boundaries or you explicitly define the chapter chunks. The app will not infer or equalize unknown chapters.';
      case 'exercises':
        return 'Useful for problem sets when exercises are roughly comparable. For varied exercises, consider defining difficulty later.';
      case 'custom':
        return 'Use articles, cases, lectures, flashcards, sources, or any other progress unit.';
      default:
        return 'Choose the progress unit that reflects how this material should be worked through.';
    }
  }

  String _rangeExplanation() {
    switch (_draft.unitType) {
      case 'pages':
        return 'Enter the first and last page. The app will compute the total and distribute the pages across the selected study days.';
      case 'chapters':
        return 'Chapters must be material-defined or user-defined. If the app does not know the chapter structure, add the chapters yourself or switch to pages.';
      case 'sections':
        return 'Sections are useful when they are clearly bounded pieces of work. For writing, they may represent project-level chunks rather than equal effort.';
      case 'exercises':
        return 'Exercises can differ in difficulty. This treats them as equal for now; later we can add difficulty or time estimates per exercise.';
      default:
        return 'Define the first and last unit. Custom units are treated as measurable work, not as a fallback category.';
    }
  }

  Widget _unitControls({bool forRoutine = false, String? title, String? helper}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UnitSetupCard(
          selectedType: _draft.unitType,
          forRoutine: forRoutine,
          title: title,
          helper: helper,
          disabledUnits: _pagesUnavailableForCurrentSource ? const <String>{'pages'} : const <String>{},
          disabledReasons: _pagesUnavailableForCurrentSource
              ? const <String, String>{
                  'pages': 'This EPUB has no real page map. Use chapters/TOC entries or custom chunks.',
                }
              : const <String, String>{},
          onChanged: _setUnitType,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _draft.unitType == 'custom'
              ? Padding(
                  key: const ValueKey('custom-units'),
                  padding: const EdgeInsets.only(top: 14),
                  child: _CustomUnitCard(
                    singularController: _customSingularController,
                    pluralController: _customPluralController,
                    labelController: _customLabelController,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('built-in-units')),
        ),
      ],
    );
  }

  void _setUnitType(String value) {
    if (value == 'pages' && _pagesUnavailableForCurrentSource) {
      _showSnack('This EPUB does not expose real page numbers. Select table-of-contents entries as chapters, or define your own chunks.');
      return;
    }

    setState(() {
      var next = _draft.copyWith(
        unitType: value,
        customUnitSingular: value == 'custom' ? _draft.intent.singularUnitFallback : null,
        clearCustomUnitSingular: value != 'custom',
        customUnitPlural: value == 'custom' ? _draft.intent.pluralUnitFallback : null,
        clearCustomUnitPlural: value != 'custom',
        customUnitLabel: value == 'custom' ? _draft.intent.shortUnitFallback : null,
        clearCustomUnitLabel: value != 'custom',
      );
      next = next.copyWith(questions: _engine.questionsFor(next));
      _draft = next;
      if (value == 'chapters') {
        _syncChapterRangeFromTitles();
      } else if (value == 'pages') {
        final source = _resolvedMaterialSource;
        final startPage = source?.startPage ?? (source?.pageCount == null ? null : 1);
        final endPage = source?.endPage ?? source?.pageCount;
        if (startPage != null && endPage != null && endPage >= startPage) {
          _startUnitController.text = startPage.toString();
          _endUnitController.text = endPage.toString();
          var pageDraft = _draft.copyWith(startUnit: startPage, endUnit: endPage);
          pageDraft = pageDraft.copyWith(questions: _engine.questionsFor(pageDraft));
          _draft = pageDraft;
        } else {
          _syncControllersFromDraft();
        }
      } else {
        _syncControllersFromDraft();
      }
    });
  }

  void _applyRangePreset(_RangePreset preset) {
    setState(() {
      _startUnitController.text = preset.start.toString();
      _endUnitController.text = preset.end.toString();
      var next = _draft.copyWith(startUnit: preset.start, endUnit: preset.end);
      next = next.copyWith(questions: _engine.questionsFor(next));
      _draft = next;
    });
  }

  void _extendRangeEnd(int delta) {
    final start = int.tryParse(_startUnitController.text.trim()) ?? _draft.startUnit;
    final end = int.tryParse(_endUnitController.text.trim()) ?? _draft.endUnit;
    final nextEnd = (end + delta).clamp(start, 999999).toInt();
    setState(() {
      _endUnitController.text = nextEnd.toString();
      var next = _draft.copyWith(startUnit: start, endUnit: nextEnd);
      next = next.copyWith(questions: _engine.questionsFor(next));
      _draft = next;
    });
  }

  void _setDailyTarget(int target) {
    setState(() {
      _dailyTargetController.text = target.toString();
      var next = _draft.copyWith(dailyTarget: target);
      next = next.copyWith(questions: _engine.questionsFor(next));
      _draft = next;
    });
  }

  List<_RangePreset> _rangePresets() {
    switch (_draft.unitType) {
      case 'pages':
        return const <_RangePreset>[
          _RangePreset('10 pages', 1, 10),
          _RangePreset('20 pages', 1, 20),
          _RangePreset('40 pages', 1, 40),
        ];
      case 'chapters':
        return const <_RangePreset>[
          _RangePreset('1 chapter', 1, 1),
          _RangePreset('3 chapters', 1, 3),
          _RangePreset('5 chapters', 1, 5),
        ];
      case 'sections':
        return const <_RangePreset>[
          _RangePreset('3 sections', 1, 3),
          _RangePreset('5 sections', 1, 5),
          _RangePreset('8 sections', 1, 8),
        ];
      case 'exercises':
        return const <_RangePreset>[
          _RangePreset('5 exercises', 1, 5),
          _RangePreset('10 exercises', 1, 10),
          _RangePreset('20 exercises', 1, 20),
        ];
      default:
        return const <_RangePreset>[
          _RangePreset('1 item', 1, 1),
          _RangePreset('3 items', 1, 3),
          _RangePreset('5 items', 1, 5),
        ];
    }
  }

  List<int> _dailyTargetPresets() {
    switch (_draft.unitType) {
      case 'pages':
        return const <int>[5, 10, 20];
      case 'chapters':
        return const <int>[1, 2, 3];
      case 'exercises':
        return const <int>[3, 5, 10];
      default:
        return const <int>[1, 2, 3];
    }
  }


  Widget _dateControls() {
    if (_draft.usesSingleDate) {
      return _DatePickerTile(
        label: _draft.storageKind == StudyPlanKind.deadline ? 'Deadline date' : 'Planned day',
        value: _draft.taskDate,
        emptyLabel: 'Pick date',
        onPick: () => _pickDate(_DateTarget.task),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        final startTile = _DatePickerTile(
          label: 'Start planning on',
          value: _draft.startDate,
          onPick: () => _pickDate(_DateTarget.start),
        );
        final dueTile = _DatePickerTile(
          label: _draft.usesRoutine ? 'Optional end date' : 'Done by',
          value: _draft.dueDate,
          emptyLabel: _draft.usesRoutine ? 'Running routine' : 'Pick date',
          onPick: () => _pickDate(_DateTarget.due),
          onClear: _draft.usesRoutine && _draft.dueDate != null
              ? () => setState(() => _draft = _draft.copyWith(clearDueDate: true))
              : null,
        );
        if (narrow) {
          return Column(
            children: [
              startTile,
              const SizedBox(height: 12),
              dueTile,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: startTile),
            const SizedBox(width: 12),
            Expanded(child: dueTile),
          ],
        );
      },
    );
  }

  void _applyQuickInput(String value) {
    final parsed = _engine.parseQuickInput(value, _context());
    setState(() {
      _draft = parsed;
      _syncControllersFromDraft();
    });
  }

  void _changeIntent(PlanningIntentType intent) {
    setState(() {
      _draft = _engine.draftFromIntent(intent, _context());
      _syncControllersFromDraft();
    });
  }

  Future<void> _pickDate(_DateTarget target) async {
    final now = DateTime.now();
    final initial = switch (target) {
      _DateTarget.start => _draft.startDate,
      _DateTarget.due => _draft.dueDate ?? widget.project.deadline ?? _draft.startDate.add(const Duration(days: 7)),
      _DateTarget.task => _draft.taskDate ?? widget.project.deadline ?? _draft.startDate,
    };

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;

    final normalized = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      switch (target) {
        case _DateTarget.start:
          _draft = _draft.copyWith(startDate: normalized);
          if (_draft.dueDate != null && _draft.dueDate!.isBefore(normalized)) {
            _draft = _draft.copyWith(dueDate: normalized);
          }
          break;
        case _DateTarget.due:
          _draft = _draft.copyWith(dueDate: normalized);
          if (_draft.startDate.isAfter(normalized)) {
            _draft = _draft.copyWith(startDate: normalized);
          }
          break;
        case _DateTarget.task:
          _draft = _draft.copyWith(taskDate: normalized);
          break;
      }
      _draft = _draft.copyWith(questions: _engine.questionsFor(_draft));
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_draft.storageKind == StudyPlanKind.checklist && _checklistItems().isEmpty) {
      _showSnack('Add at least one topic or checklist item.');
      return;
    }
    if (_draft.intent == PlanningIntentType.studyMaterial &&
        _draft.storageKind == StudyPlanKind.progress &&
        !_planByTime &&
        _draft.unitType == 'chapters' &&
        !_hasChapterStructure()) {
      _showSnack('Add the chapter structure first, or switch to pages. The app will not guess unknown chapters.');
      return;
    }
    if (_draft.usesDueDate && _draft.dueDate == null) {
      _showSnack('Pick a done-by date.');
      return;
    }
    if (_draft.usesSingleDate && _draft.taskDate == null) {
      _showSnack('Pick a date.');
      return;
    }
    final timePlanMinutes = _planByTime && _draft.storageKind == StudyPlanKind.progress ? _timePlanMinutes() : null;
    final timeWindowStart = _planByTime && _draft.storageKind == StudyPlanKind.progress ? _timeWindowStartMinutes() : null;
    final timeWindowEnd = _planByTime && _draft.storageKind == StudyPlanKind.progress ? _timeWindowEndMinutes() : null;
    if (_planByTime && _draft.storageKind == StudyPlanKind.progress) {
      if (timePlanMinutes == null) {
        _showSnack(_timePlanInputMode == _TimePlanInputMode.window
            ? 'Enter a valid time window, for example 09:00 to 11:00.'
            : 'Enter a valid daily duration.');
        return;
      }
      if (_timePlanInputMode == _TimePlanInputMode.window &&
          (timeWindowStart == null || timeWindowEnd == null || timeWindowEnd <= timeWindowStart)) {
        _showSnack('The end time must be after the start time.');
        return;
      }
    }

    setState(() => _saving = true);

    final plan = await widget.planningRepository.createPlan(
      projectId: widget.project.id,
      title: _titleController.text.trim(),
      planKind: _planByTime && _draft.storageKind == StudyPlanKind.progress
          ? StudyPlanKind.recurring
          : _draft.storageKind,
      unitType: _planByTime && _draft.storageKind == StudyPlanKind.progress
          ? 'minutes'
          : _unitTypeForSave(),
      startUnit: _draft.storageKind == StudyPlanKind.progress && !_planByTime
          ? int.parse(_startUnitController.text.trim())
          : null,
      endUnit: _draft.storageKind == StudyPlanKind.progress && !_planByTime
          ? int.parse(_endUnitController.text.trim())
          : null,
      dailyTarget: _planByTime && _draft.storageKind == StudyPlanKind.progress
          ? timePlanMinutes
          : _draft.storageKind == StudyPlanKind.recurring
              ? int.parse(_dailyTargetController.text.trim())
              : null,
      timeStartMinutes: timeWindowStart,
      timeEndMinutes: timeWindowEnd,
      startDate: _draft.startDate,
      deadline: _draft.storageKind == StudyPlanKind.singleTask
          ? _draft.taskDate
          : _draft.storageKind == StudyPlanKind.deadline
              ? _draft.taskDate
              : _draft.dueDate,
      taskDate: _draft.usesSingleDate ? _draft.taskDate : null,
      weekendsOff: _draft.usesWeekends ? _draft.weekendsOff : false,
      customUnitSingular: !_planByTime && _draft.unitType == 'custom' && _draft.usesUnits
          ? _customSingularController.text.trim()
          : null,
      customUnitPlural: !_planByTime && _draft.unitType == 'custom' && _draft.usesUnits
          ? _customPluralController.text.trim()
          : null,
      customUnitLabel: !_planByTime && _draft.unitType == 'custom' && _draft.usesUnits
          ? (_customLabelController.text.trim().isEmpty
              ? _customSingularController.text.trim()
              : _customLabelController.text.trim())
          : null,
      checklistItems: _draft.storageKind == StudyPlanKind.checklist ? _checklistItems() : null,
      materialSource: _draft.intent == PlanningIntentType.studyMaterial ? _materialSourceForSave() : null,
    );

    if (!mounted) return;
    Navigator.of(context).pop(plan);
  }

  void _addChecklistItemsFromInput() {
    final raw = _newChecklistItemController.text.trim();
    if (raw.isEmpty) return;
    final nextItems = <String>[
      ..._checklistItems(),
      ...raw
          .split(RegExp(r'[\n;]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
    ];
    setState(() {
      _newChecklistItemController.clear();
      _updatingControllers = true;
      _checklistController.text = nextItems.join('\n');
      _updatingControllers = false;
      _draft = _draft.copyWith(
        checklistItems: nextItems,
        questions: _engine.questionsFor(_draft.copyWith(checklistItems: nextItems)),
      );
    });
  }

  void _removeChecklistItem(int index) {
    final items = _checklistItems();
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    setState(() {
      _updatingControllers = true;
      _checklistController.text = items.join('\n');
      _updatingControllers = false;
      _draft = _draft.copyWith(
        checklistItems: items,
        questions: _engine.questionsFor(_draft.copyWith(checklistItems: items)),
      );
    });
  }

  List<String> _manualChapterTitles() {
    return _userChapterTitles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _chapterTitles() {
    return <String>[
      for (final segment in _selectedDetectedChapterSegments()) segment.title.trim(),
      ..._manualChapterTitles(),
    ].where((title) => title.isNotEmpty).toList(growable: false);
  }

  bool _hasChapterStructure() => _chapterTitles().isNotEmpty;

  bool _trySelectDetectedChaptersFromInput(String raw) {
    final detected = _detectedChapterSegments();
    if (detected.isEmpty) return false;
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\d+(?:[-–]\d+)?(?:,\d+(?:[-–]\d+)?)*$').hasMatch(compact)) {
      return false;
    }

    final nextKeys = <String>{..._selectedDetectedChapterKeys};
    var changed = false;
    for (final token in compact.split(',')) {
      if (token.contains('-') || token.contains('–')) {
        final pieces = token.split(RegExp(r'[-–]'));
        if (pieces.length != 2) return false;
        final start = int.tryParse(pieces[0]);
        final end = int.tryParse(pieces[1]);
        if (start == null || end == null) return false;
        final low = start <= end ? start : end;
        final high = start <= end ? end : start;
        for (var number = low; number <= high; number++) {
          final index = number - 1;
          if (index < 0 || index >= detected.length) continue;
          changed = nextKeys.add(_detectedChapterKey(detected[index], index)) || changed;
        }
      } else {
        final number = int.tryParse(token);
        if (number == null) return false;
        final index = number - 1;
        if (index < 0 || index >= detected.length) continue;
        changed = nextKeys.add(_detectedChapterKey(detected[index], index)) || changed;
      }
    }
    if (!changed) return true;
    _selectedDetectedChapterKeys = nextKeys;
    _syncChapterRangeFromTitles();
    return true;
  }

  void _addChapterTitlesFromInput() {
    final raw = _chapterTitleController.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      if (_trySelectDetectedChaptersFromInput(raw)) {
        _chapterTitleController.clear();
        return;
      }
      final additions = raw
          .split(RegExp(r'[\n;]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (additions.isEmpty) return;
      _chapterTitleController.clear();
      _userChapterTitles = <String>[..._manualChapterTitles(), ...additions];
      _syncChapterRangeFromTitles();
    });
  }

  void _removeChapterTitle(int index) {
    final selected = _selectedDetectedChapterSegments();
    if (index < selected.length) {
      final detected = _detectedChapterSegments();
      for (var i = 0; i < detected.length; i++) {
        if (detected[i].id == selected[index].id && detected[i].title == selected[index].title) {
          _toggleDetectedChapter(detected[i], i, false);
          return;
        }
      }
    }
    final manualIndex = index - selected.length;
    final chapters = _manualChapterTitles();
    if (manualIndex < 0 || manualIndex >= chapters.length) return;
    chapters.removeAt(manualIndex);
    setState(() {
      _userChapterTitles = chapters;
      _syncChapterRangeFromTitles();
    });
  }

  void _toggleDetectedChapter(StudyMaterialSegment segment, int index, bool selected) {
    setState(() {
      final key = _detectedChapterKey(segment, index);
      final next = <String>{..._selectedDetectedChapterKeys};
      if (selected) {
        next.add(key);
      } else {
        next.remove(key);
      }
      _selectedDetectedChapterKeys = next;
      _syncChapterRangeFromTitles();
    });
  }

  void _selectAllDetectedChapters() {
    final detected = _detectedChapterSegments();
    setState(() {
      _selectedDetectedChapterKeys = <String>{
        for (var i = 0; i < detected.length; i++) _detectedChapterKey(detected[i], i),
      };
      _syncChapterRangeFromTitles();
    });
  }

  void _clearDetectedChapters() {
    setState(() {
      _selectedDetectedChapterKeys = <String>{};
      _syncChapterRangeFromTitles();
    });
  }

  void _syncChapterRangeFromTitles() {
    final count = _chapterTitles().length;
    if (count <= 0) {
      _startUnitController.text = '1';
      _endUnitController.text = '1';
      var next = _draft.copyWith(startUnit: 1, endUnit: 1);
      next = next.copyWith(questions: _engine.questionsFor(next));
      _draft = next;
      return;
    }
    _startUnitController.text = '1';
    _endUnitController.text = count.toString();
    var next = _draft.copyWith(startUnit: 1, endUnit: count);
    next = next.copyWith(questions: _engine.questionsFor(next));
    _draft = next;
  }

  List<StudyMaterialSegment> _chapterSegmentsForSave(StudyMaterialSource? resolved) {
    final selectedDetected = _selectedDetectedChapterSegments(resolved);
    final manual = _manualChapterTitles();
    return <StudyMaterialSegment>[
      ...selectedDetected,
      for (var i = 0; i < manual.length; i++)
        StudyMaterialSegment(
          id: 'user-chapter-${i + 1}',
          title: manual[i],
          type: StudyMaterialSegmentType.chapter,
          structureConfidence: StudyMaterialStructureConfidence.userDefined,
        ),
    ];
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _handleMaterialSourceChoice(_StudyMaterialSourceType value) {
    if (value == _StudyMaterialSourceType.libraryFile && widget.database != null) {
      _chooseLibraryPdf();
      return;
    }
    if (value == _StudyMaterialSourceType.readerFile) {
      _chooseReaderFile();
      return;
    }
    _setMaterialSourceType(value);
  }

  void _handleMaterialSourceDetailsChanged() {
    final resolved = _resolvedMaterialSource;
    if (resolved != null && _materialSource == _sourceTypeFromStorage(resolved.type)) {
      final link = _sourceLinkController.text.trim();
      final startPage = int.tryParse(_sourceStartPageController.text.trim());
      final endPage = int.tryParse(_sourceEndPageController.text.trim());
      final notes = _sourceNotesController.text.trim();
      _resolvedMaterialSource = resolved.copyWith(
        title: _sourceTitleController.text.trim().isEmpty
            ? resolved.title
            : _sourceTitleController.text.trim(),
        url: link.isEmpty ? null : link,
        clearUrl: link.isEmpty,
        startPage: startPage,
        clearStartPage: startPage == null,
        endPage: endPage,
        clearEndPage: endPage == null,
        notes: notes.isEmpty ? null : notes,
        clearNotes: notes.isEmpty,
      );
    }

    final startPage = int.tryParse(_sourceStartPageController.text.trim());
    final endPage = int.tryParse(_sourceEndPageController.text.trim());
    if (_draft.intent == PlanningIntentType.studyMaterial &&
        _draft.unitType == 'pages' &&
        startPage != null &&
        endPage != null &&
        endPage >= startPage) {
      _startUnitController.text = startPage.toString();
      _endUnitController.text = endPage.toString();
      _draft = _draft.copyWith(startUnit: startPage, endUnit: endPage);
      _draft = _draft.copyWith(questions: _engine.questionsFor(_draft));
    }

    setState(() {});
  }

  void _setMaterialSourceType(_StudyMaterialSourceType value) {
    setState(() {
      _materialSource = value;
      if (value == _StudyMaterialSourceType.noSourceYet ||
          value == _StudyMaterialSourceType.physicalBook ||
          value == _StudyMaterialSourceType.articleOrWebsite) {
        _resolvedMaterialSource = null;
      }
      if (value == _StudyMaterialSourceType.currentFile && widget.initialMaterialSource != null) {
        _applyResolvedMaterialSource(widget.initialMaterialSource!, forcePages: true, notify: false);
        return;
      }
      if (value == _StudyMaterialSourceType.readerFile && _resolvedMaterialSource != null) {
        return;
      }
      if (value != _StudyMaterialSourceType.noSourceYet &&
          _sourceTitleController.text.trim().isEmpty) {
        final title = _titleController.text.trim();
        _sourceTitleController.text = title.isEmpty ? value.label : title;
      }
      if (value != _StudyMaterialSourceType.articleOrWebsite) {
        _sourceLinkController.clear();
      }
      if (!value.canHavePages) {
        _sourceStartPageController.clear();
        _sourceEndPageController.clear();
      }
    });
  }

  Future<void> _chooseLibraryPdf() async {
    final database = widget.database;
    if (database == null) {
      _setMaterialSourceType(_StudyMaterialSourceType.libraryFile);
      _showSnack('Library picking is available when the composer has access to the PDF library.');
      return;
    }

    setState(() {
      _loadingLibrarySource = true;
    });

    List<PdfDocument> documents;
    try {
      documents = await database.getAllDocuments();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingLibrarySource = false);
      _showSnack('Could not load the PDF library: $error');
      return;
    }

    if (!mounted) return;
    setState(() => _loadingLibrarySource = false);

    documents.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (documents.isEmpty) {
      _setMaterialSourceType(_StudyMaterialSourceType.libraryFile);
      _showSnack('No PDFs found in the library yet.');
      return;
    }

    final selected = await showDialog<PdfDocument>(
      context: context,
      builder: (_) => _PdfMaterialSourcePickerDialog(documents: documents),
    );
    if (selected == null) return;

    if (!mounted) return;
    setState(() => _loadingLibrarySource = true);
    final source = await _inspectLibraryPdf(selected);
    if (!mounted) return;

    setState(() => _loadingLibrarySource = false);
    _applyResolvedMaterialSource(source, forcePages: source.pageCount != null);
    if (source.segments.isNotEmpty) {
      final fromToc = source.structureConfidence == StudyMaterialStructureConfidence.parsedToc;
      _showSnack(
        fromToc
            ? 'Detected ${source.segments.length} outline entr${source.segments.length == 1 ? 'y' : 'ies'} from a visible table of contents.'
            : 'Detected ${source.segments.length} PDF outline entr${source.segments.length == 1 ? 'y' : 'ies'} from bookmarks.',
      );
    }
  }

  Future<StudyMaterialSource> _inspectLibraryPdf(PdfDocument document) async {
    try {
      final file = File(document.filePath);
      if (await file.exists()) {
        final inspected = (await StudyMaterialOutlineReader().read(file)).source;
        return inspected.copyWith(
          type: StudyMaterialSourceType.libraryFile,
          title: document.name,
          libraryDocumentId: document.documentId,
          filePath: document.filePath,
          notes: _libraryPdfSourceNote(
            document,
            inspected.pageCount,
            outlineCount: inspected.segments.length,
            structureConfidence: inspected.structureConfidence,
          ),
          paginationSource: inspected.paginationSource,
          pageMarkers: inspected.pageMarkers,
          segments: inspected.segments,
        );
      }
    } catch (_) {
      // Fall back to the older metadata path below.
    }

    final pageCount = await _readPdfPageCount(document);
    return StudyMaterialSource(
      type: StudyMaterialSourceType.libraryFile,
      title: document.name,
      libraryDocumentId: document.documentId,
      filePath: document.filePath,
      pageCount: pageCount,
      startPage: pageCount == null ? null : 1,
      endPage: pageCount,
      notes: _libraryPdfSourceNote(document, pageCount),
    );
  }

  Future<void> _chooseReaderFile() async {
    setState(() {
      _materialSource = _StudyMaterialSourceType.readerFile;
      _resolvedMaterialSource = null;
      _loadingReaderSource = true;
    });

    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf', 'epub'],
        allowMultiple: false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingReaderSource = false);
      _showSnack('Could not open the file picker: $error');
      return;
    }

    final path = result?.files.single.path;
    if (path == null) {
      if (mounted) setState(() => _loadingReaderSource = false);
      return;
    }

    try {
      final result = await StudyMaterialOutlineReader().read(File(path));
      if (!mounted) return;
      setState(() => _loadingReaderSource = false);
      final source = result.source;
      final sourceHasPages = source.startPage != null && source.endPage != null && source.pageCount != null;
      final forcePages = (source.type == StudyMaterialSourceType.pdfFile ||
              source.type == StudyMaterialSourceType.epubFile) &&
          sourceHasPages;
      _applyResolvedMaterialSource(source, forcePages: forcePages);
      if (source.type == StudyMaterialSourceType.epubFile && !sourceHasPages) {
        _setUnitType('chapters');
      }
      _showSnack(result.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingReaderSource = false);
      _showSnack('Could not inspect this file: $error');
    }
  }

  Future<int?> _readPdfPageCount(PdfDocument document) async {
    try {
      final file = File(document.filePath);
      if (!await file.exists()) return null;
      final metadata = await PdfMetadataExtractor().extract(file);
      return metadata.pageCount;
    } catch (_) {
      return null;
    }
  }

  String? _libraryPdfSourceNote(
    PdfDocument document,
    int? pageCount, {
    int outlineCount = 0,
    String structureConfidence = StudyMaterialStructureConfidence.none,
  }) {
    final details = <String>[];
    if (document.authors?.trim().isNotEmpty == true) {
      details.add('Authors: ${document.authors!.trim()}');
    }
    if (pageCount != null) {
      details.add('$pageCount PDF pages detected');
    }
    if (outlineCount > 0) {
      final source = structureConfidence == StudyMaterialStructureConfidence.parsedToc
          ? 'visible table-of-contents entries parsed'
          : 'PDF bookmark outline entries detected';
      details.add('$outlineCount $source');
    }
    if (document.originalFileName.trim().isNotEmpty) {
      details.add('File: ${document.originalFileName.trim()}');
    }
    return details.isEmpty ? null : details.join(' · ');
  }

  StudyMaterialSource? _materialSourceForSave() {
    if (_materialSource == _StudyMaterialSourceType.noSourceYet) return null;
    final title = _sourceTitleController.text.trim().isEmpty
        ? _materialSource.label
        : _sourceTitleController.text.trim();
    final sourceCanSavePages = _materialSource.canHavePages &&
        (_resolvedMaterialSource?.type != StudyMaterialSourceType.epubFile ||
            _resolvedMaterialSource?.pageCount != null);
    final startPage = sourceCanSavePages
        ? int.tryParse(_sourceStartPageController.text.trim())
        : null;
    final endPage = sourceCanSavePages
        ? int.tryParse(_sourceEndPageController.text.trim())
        : null;
    final normalizedStartPage = startPage != null && startPage > 0 ? startPage : null;
    final normalizedEndPage = endPage != null && endPage > 0 ? endPage : null;
    final resolved = _resolvedMaterialSource;
    final link = _sourceLinkController.text.trim();
    final notes = _sourceNotesController.text.trim();
    final savedSegments = _chapterSegmentsForSave(resolved);
    final hasUserDefinedStructure = savedSegments.any(
      (segment) => segment.structureConfidence == StudyMaterialStructureConfidence.userDefined,
    );

    return StudyMaterialSource(
      type: _materialSource == _StudyMaterialSourceType.readerFile
          ? StudyMaterialSourceType.normalize(resolved?.type ?? _materialSource.storageType)
          : _materialSource.storageType,
      title: title,
      libraryDocumentId: resolved?.libraryDocumentId,
      filePath: resolved?.filePath,
      url: _materialSource == _StudyMaterialSourceType.articleOrWebsite && link.isNotEmpty
          ? link
          : resolved?.url,
      pageCount: resolved?.pageCount,
      startPage: normalizedStartPage,
      endPage: normalizedEndPage,
      notes: notes.isEmpty ? resolved?.notes : notes,
      structureConfidence: hasUserDefinedStructure
          ? StudyMaterialStructureConfidence.userDefined
          : resolved?.structureConfidence ??
              (_chapterTitles().isNotEmpty
                  ? StudyMaterialStructureConfidence.userDefined
                  : StudyMaterialStructureConfidence.none),
      structureMessage: hasUserDefinedStructure
          ? 'Chapter/chunk structure was defined or edited by the user.'
          : resolved?.structureMessage,
      paginationSource: resolved?.paginationSource ?? StudyMaterialPaginationSource.none,
      pageMarkers: resolved?.pageMarkers ?? const <StudyMaterialSegment>[],
      segments: savedSegments,
    );
  }

  String _materialSourcePreviewLine() {
    if (_materialSource == _StudyMaterialSourceType.noSourceYet) {
      return 'No material source is attached yet.';
    }
    final source = _materialSourceForSave();
    if (source == null) return 'No material source is attached yet.';
    final range = source.startPage != null && source.endPage != null
        ? ' · pages ${source.startPage}–${source.endPage}'
        : '';
    final pageCount = source.pageCount == null ? '' : ' · ${source.pageCount} pages';
    final chapterCount = source.segments.where((segment) => segment.type == StudyMaterialSegmentType.chapter).length;
    final chapters = chapterCount == 0 ? '' : ' · $chapterCount outline item${chapterCount == 1 ? '' : 's'}';
    return 'Attach source: ${source.typeLabel} · ${source.title}$range$pageCount$chapters.';
  }

  String _unitTypeForSave() {
    switch (_draft.storageKind) {
      case StudyPlanKind.singleTask:
        return 'task';
      case StudyPlanKind.deadline:
        return 'deadline';
      case StudyPlanKind.checklist:
        return 'topic';
      default:
        return _draft.unitType;
    }
  }

  List<String> _checklistItems() {
    return _checklistController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  List<String> _previewLines() {
    final title = _titleController.text.trim().isEmpty ? _draft.intent.defaultTitle : _titleController.text.trim();
    switch (_draft.storageKind) {
      case StudyPlanKind.singleTask:
        return <String>[
          'Create one task: “$title”.',
          'Planned day: ${_formatNullableDate(_draft.taskDate)}.',
          'If missed, it appears as study debt.',
        ];
      case StudyPlanKind.deadline:
        return <String>[
          'Create one deadline marker: “$title”.',
          'Date: ${_formatNullableDate(_draft.taskDate)}.',
          'It adds context and pressure, but does not generate workload.',
        ];
      case StudyPlanKind.recurring:
        final target = int.tryParse(_dailyTargetController.text.trim()) ?? _draft.dailyTarget;
        final period = _draft.dueDate == null
            ? 'from ${_formatDate(_draft.startDate)} until you remove it'
            : 'from ${_formatDate(_draft.startDate)} to ${_formatDate(_draft.dueDate!)}';
        return <String>[
          'Create repeating work: “$title”.',
          'Amount: $target ${_nounForCount(target)} per study day.',
          'Runs $period.',
          _draft.weekendsOff ? 'Weekends are excluded.' : 'Weekends are included.',
        ];
      case StudyPlanKind.checklist:
        final items = _checklistItems();
        final days = _draft.dueDate == null ? 0 : _eligibleDays(_draft.startDate, _draft.dueDate!, _draft.weekendsOff).length;
        return <String>[
          'Create a named checklist plan: “$title”.',
          '${items.length} item${items.length == 1 ? '' : 's'} across ${days == 0 ? 'the chosen' : days} study day${days == 1 ? '' : 's'}.',
          if (items.isNotEmpty) 'First item: ${items.first}.',
          _draft.weekendsOff ? 'Weekends are excluded.' : 'Weekends are included.',
        ];
      case StudyPlanKind.progress:
      default:
        final days = _draft.dueDate == null ? 0 : _eligibleDays(_draft.startDate, _draft.dueDate!, _draft.weekendsOff).length;
        if (_planByTime) {
          final minutes = _timePlanMinutes();
          final window = _timeWindowPreview();
          return <String>[
            'Create a time-based plan: “$title”.',
            if (_draft.intent == PlanningIntentType.studyMaterial) _materialSourcePreviewLine(),
            minutes == null
                ? 'Choose a daily duration or a valid time window.'
                : 'Amount: ${_formatMinutesForPlan(minutes)} per study day.',
            if (window != null) 'Calendar block: $window on each eligible study day.',
            'Runs from ${_formatDate(_draft.startDate)} to ${_formatNullableDate(_draft.dueDate)}${days == 0 ? '' : ' across $days study day${days == 1 ? '' : 's'}'}.',
            _draft.weekendsOff ? 'Weekends are excluded.' : 'Weekends are included.',
          ];
        }
        final start = int.tryParse(_startUnitController.text.trim()) ?? _draft.startUnit;
        final end = int.tryParse(_endUnitController.text.trim()) ?? _draft.endUnit;
        final total = (end - start + 1).clamp(1, 999999).toInt();
        if (_draft.intent == PlanningIntentType.studyMaterial && _draft.unitType == 'chapters') {
          final chapters = _chapterTitles();
          return <String>[
            'Create a chapter-based study plan: “$title”.',
            _materialSourcePreviewLine(),
            if (chapters.isEmpty)
              'Add material-defined or user-defined chapters before saving. The app will not guess unknown chapter structure.'
            else
              '${chapters.length} explicit chapter chunk${chapters.length == 1 ? '' : 's'} will be saved with the source.',
            if (chapters.isNotEmpty) 'First outline item: ${chapters.first}.',
            if (chapters.isNotEmpty && days == 0)
              'The app will distribute the explicit chapter chunks over the chosen study days.'
            else if (chapters.isNotEmpty)
              'About ${_formatPace(chapters.length / days.clamp(1, 999999))} chapter chunk${(chapters.length / days.clamp(1, 999999)) == 1 ? '' : 's'} per study day.',
            _draft.weekendsOff ? 'Weekends are excluded.' : 'Weekends are included.',
          ];
        }
        return <String>[
          'Create a work plan: “$title”.',
          if (_draft.intent == PlanningIntentType.studyMaterial) _materialSourcePreviewLine(),
          '$total ${_nounForCount(total)} from ${_unitShortLabel()} $start to ${_unitShortLabel()} $end.',
          '${days == 0 ? 'The app will distribute this over the chosen study days.' : 'About ${_formatPace(total / days.clamp(1, 999999))} ${_nounForCount((total / days.clamp(1, 999999)).ceil())} per study day.'}',
          _draft.weekendsOff ? 'Weekends are excluded.' : 'Weekends are included.',
        ];
    }
  }

  String? _validatePositiveNumber(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1) return 'Use a number above 0.';
    return null;
  }

  String _titleLabel() {
    switch (_draft.storageKind) {
      case StudyPlanKind.singleTask:
        return 'Task';
      case StudyPlanKind.deadline:
        return 'Deadline';
      case StudyPlanKind.recurring:
        return 'Routine name';
      case StudyPlanKind.checklist:
        return 'Checklist name';
      default:
        if (_draft.intent == PlanningIntentType.studyMaterial) return 'Material or assignment name';
        if (_draft.intent == PlanningIntentType.writeSomething) return 'Writing target';
        return 'Work name';
    }
  }

  String _titleHint() {
    switch (_draft.intent) {
      case PlanningIntentType.studyMaterial:
        return 'Read chapter 4';
      case PlanningIntentType.finishByDate:
        return 'Finish problem set';
      case PlanningIntentType.addTask:
        return 'Email supervisor';
      case PlanningIntentType.rememberDeadline:
        return 'Exam';
      case PlanningIntentType.reviewTopics:
        return 'Review macro topics';
      case PlanningIntentType.buildRoutine:
        return 'Daily flashcards';
      case PlanningIntentType.writeSomething:
        return 'Write methods section';
    }
  }

  String _startUnitLabel() {
    switch (_draft.unitType) {
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

  String _endUnitLabel() {
    switch (_draft.unitType) {
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

  String _unitShortLabel() {
    if (_draft.unitType == 'custom') {
      final label = _customLabelController.text.trim();
      if (label.isNotEmpty) return label;
      return _customSingularOrFallback();
    }
    switch (_draft.unitType) {
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
    if (_draft.unitType == 'custom') {
      return count == 1 ? _customSingularOrFallback() : _customPluralOrFallback();
    }
    switch (_draft.unitType) {
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

  String _customSingularOrFallback() {
    final value = _customSingularController.text.trim();
    if (value.isNotEmpty) return value;
    return _draft.intent.singularUnitFallback;
  }

  String _customPluralOrFallback() {
    final value = _customPluralController.text.trim();
    if (value.isNotEmpty) return value;
    final singular = _customSingularController.text.trim();
    if (singular.isNotEmpty) return '${singular}s';
    return _draft.intent.pluralUnitFallback;
  }
}

enum _DateTarget { start, due, task }

class _ComposerHero extends StatelessWidget {
  final StudyProject project;
  final TextEditingController quickController;
  final ValueChanged<String> onSubmitted;

  const _ComposerHero({
    required this.project,
    required this.quickController,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer.withAlpha(220),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withAlpha(200),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 4),
                    Text(
                      'Adding work to ${project.title}. Type it quickly or choose a guided path below.',
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
          const SizedBox(height: 16),
          TextField(
            controller: quickController,
            textInputAction: TextInputAction.done,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.surface.withAlpha(230),
              prefixIcon: const Icon(Icons.bolt_rounded),
              suffixIcon: IconButton(
                tooltip: 'Use quick input',
                onPressed: () => onSubmitted(quickController.text),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              hintText: 'Try: Read pages 20-45 by Friday /90m',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _ExamplePill(text: 'Write thesis section by Friday'),
              _ExamplePill(text: 'Exam deadline on Monday'),
              _ExamplePill(text: 'Daily flashcards'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExamplePill extends StatelessWidget {
  final String text;

  const _ExamplePill({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(130),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _IntentSelector extends StatelessWidget {
  final PlanningIntentType selectedIntent;
  final ValueChanged<PlanningIntentType> onChanged;

  const _IntentSelector({
    required this.selectedIntent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intents = <PlanningIntentType>[
      PlanningIntentType.studyMaterial,
      PlanningIntentType.writeSomething,
      PlanningIntentType.finishByDate,
      PlanningIntentType.addTask,
      PlanningIntentType.rememberDeadline,
      PlanningIntentType.reviewTopics,
      PlanningIntentType.buildRoutine,
    ];

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
            Text(
              'Choose a guided path',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final intent in intents)
                  ChoiceChip(
                    selected: selectedIntent == intent,
                    label: Text(intent.label),
                    avatar: Icon(_intentIcon(intent), size: 18),
                    onSelected: (_) => onChanged(intent),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final Widget child;

  const _DetailsCard({required this.child});

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
        child: child,
      ),
    );
  }
}


enum _StudyMaterialSourceType { currentFile, libraryFile, readerFile, physicalBook, articleOrWebsite, noSourceYet }

extension _StudyMaterialSourceTypeX on _StudyMaterialSourceType {
  String get label {
    switch (this) {
      case _StudyMaterialSourceType.currentFile:
        return 'Current file';
      case _StudyMaterialSourceType.libraryFile:
        return 'Library file';
      case _StudyMaterialSourceType.readerFile:
        return 'PDF / EPUB';
      case _StudyMaterialSourceType.physicalBook:
        return 'Physical book';
      case _StudyMaterialSourceType.articleOrWebsite:
        return 'Article / website';
      case _StudyMaterialSourceType.noSourceYet:
        return 'No source yet';
    }
  }

  String get storageType {
    switch (this) {
      case _StudyMaterialSourceType.currentFile:
        return StudyMaterialSourceType.currentFile;
      case _StudyMaterialSourceType.libraryFile:
        return StudyMaterialSourceType.libraryFile;
      case _StudyMaterialSourceType.readerFile:
        return StudyMaterialSourceType.pdfFile;
      case _StudyMaterialSourceType.physicalBook:
        return StudyMaterialSourceType.physicalBook;
      case _StudyMaterialSourceType.articleOrWebsite:
        return StudyMaterialSourceType.articleOrWebsite;
      case _StudyMaterialSourceType.noSourceYet:
        return StudyMaterialSourceType.noSourceYet;
    }
  }

  bool get canHavePages =>
      this == _StudyMaterialSourceType.currentFile ||
      this == _StudyMaterialSourceType.libraryFile ||
      this == _StudyMaterialSourceType.readerFile ||
      this == _StudyMaterialSourceType.physicalBook;
}

class _ComposerPathHeader extends StatelessWidget {
  final StudyProject project;
  final PlanningDraft draft;

  const _ComposerPathHeader({
    required this.project,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _intentIcon(draft.intent);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(150),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.intent.label,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Project: ${project.title}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
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

class _StudyMaterialSourceCard extends StatelessWidget {
  final _StudyMaterialSourceType selectedType;
  final bool hasCurrentFile;
  final bool canChooseLibraryFile;
  final bool loadingLibrarySource;
  final bool loadingReaderSource;
  final String? currentFileTitle;
  final ValueChanged<_StudyMaterialSourceType> onChanged;

  const _StudyMaterialSourceCard({
    required this.selectedType,
    required this.hasCurrentFile,
    required this.canChooseLibraryFile,
    required this.loadingLibrarySource,
    required this.loadingReaderSource,
    required this.onChanged,
    this.currentFileTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <_StudyMaterialSourceOption>[
      _StudyMaterialSourceOption(
        type: _StudyMaterialSourceType.currentFile,
        label: 'Current file',
        helper: hasCurrentFile
            ? 'Use ${currentFileTitle ?? 'the active PDF'} and its page range.'
            : 'Available when planning from an open PDF.',
        icon: Icons.picture_as_pdf_rounded,
      ),
      _StudyMaterialSourceOption(
        type: _StudyMaterialSourceType.libraryFile,
        label: 'Choose file',
        helper: canChooseLibraryFile
            ? 'Pick a PDF from the library and prefill page metadata.'
            : 'Available when the PDF library is connected.',
        icon: Icons.folder_open_rounded,
      ),
      const _StudyMaterialSourceOption(
        type: _StudyMaterialSourceType.readerFile,
        label: 'Insert PDF / EPUB',
        helper: 'Inspect a reader file and import its explicit outline.',
        icon: Icons.auto_stories_rounded,
      ),
      const _StudyMaterialSourceOption(
        type: _StudyMaterialSourceType.physicalBook,
        label: 'Physical book',
        helper: 'Add pages or explicit chapter names manually.',
        icon: Icons.menu_book_rounded,
      ),
      const _StudyMaterialSourceOption(
        type: _StudyMaterialSourceType.articleOrWebsite,
        label: 'Article / website',
        helper: 'Use a link, article, lecture note, or short source.',
        icon: Icons.article_rounded,
      ),
      const _StudyMaterialSourceOption(
        type: _StudyMaterialSourceType.noSourceYet,
        label: 'No source yet',
        helper: 'Plan the work now and attach material later.',
        icon: Icons.add_link_rounded,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.source_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What material are you working through?',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'This is separate from the measurement method. A book, PDF, or article can later provide richer page/chapter metadata.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in options)
                    SizedBox(
                      width: narrow ? constraints.maxWidth : (constraints.maxWidth - 20) / 3,
                      child: _StudyMaterialSourceChoice(
                        option: option,
                        selected: selectedType == option.type,
                        disabled: option.type == _StudyMaterialSourceType.currentFile && !hasCurrentFile,
                        loading: (option.type == _StudyMaterialSourceType.libraryFile && loadingLibrarySource) ||
                            (option.type == _StudyMaterialSourceType.readerFile && loadingReaderSource),
                        onTap: () => onChanged(option.type),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _SourceCapabilityNote(type: selectedType),
        ],
      ),
    );
  }
}

class _StudyMaterialSourceOption {
  final _StudyMaterialSourceType type;
  final String label;
  final String helper;
  final IconData icon;

  const _StudyMaterialSourceOption({
    required this.type,
    required this.label,
    required this.helper,
    required this.icon,
  });
}

class _StudyMaterialSourceChoice extends StatelessWidget {
  final _StudyMaterialSourceOption option;
  final bool selected;
  final bool disabled;
  final bool loading;
  final VoidCallback onTap;

  const _StudyMaterialSourceChoice({
    required this.option,
    required this.selected,
    required this.disabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: disabled || loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? theme.colorScheme.primary.withAlpha(180) : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              loading
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      option.icon,
                      size: 20,
                      color: disabled
                          ? theme.colorScheme.onSurfaceVariant.withAlpha(120)
                          : selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? 'Loading…' : option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.helper,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: disabled
                            ? theme.colorScheme.onSurfaceVariant.withAlpha(140)
                            : selected
                                ? theme.colorScheme.onPrimaryContainer.withAlpha(210)
                                : theme.colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, size: 18, color: theme.colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialSourceDetailsCard extends StatelessWidget {
  final _StudyMaterialSourceType type;
  final TextEditingController titleController;
  final TextEditingController linkController;
  final TextEditingController startPageController;
  final TextEditingController endPageController;
  final TextEditingController notesController;
  final StudyMaterialSource? resolvedSource;
  final VoidCallback onChanged;

  const _MaterialSourceDetailsCard({
    required this.type,
    required this.titleController,
    required this.linkController,
    required this.startPageController,
    required this.endPageController,
    required this.notesController,
    required this.resolvedSource,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dataset_linked_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Source details',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  type.label,
                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          if (resolvedSource != null) ...[
            const SizedBox(height: 10),
            _ResolvedSourceSummary(source: resolvedSource!),
            if (resolvedSource!.segments.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SourceOutlinePreview(source: resolvedSource!),
            ],
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: titleController,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: _sourceTitleLabel(type),
              hintText: _sourceTitleHint(type),
              border: const OutlineInputBorder(),
            ),
          ),
          if (type == _StudyMaterialSourceType.articleOrWebsite) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: linkController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Link',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (type.canHavePages && (resolvedSource?.type != StudyMaterialSourceType.epubFile || resolvedSource?.pageCount != null)) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                final startField = TextFormField(
                  controller: startPageController,
                  onChanged: (_) => onChanged(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Start page',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                  validator: _optionalPositiveNumber,
                );
                final endField = TextFormField(
                  controller: endPageController,
                  onChanged: (_) => onChanged(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'End page',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final end = int.tryParse(value?.trim() ?? '');
                    final start = int.tryParse(startPageController.text.trim());
                    if ((value ?? '').trim().isEmpty) return null;
                    if (end == null || end < 1) return 'Use a page above 0.';
                    if (start != null && start > 0 && end < start) return 'End must be after start.';
                    return null;
                  },
                );
                if (narrow) {
                  return Column(
                    children: [
                      startField,
                      const SizedBox(height: 12),
                      endField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: startField),
                    const SizedBox(width: 12),
                    Expanded(child: endField),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: notesController,
            onChanged: (_) => onChanged(),
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _sourceNotesLabel(type),
              hintText: _sourceNotesHint(type),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _sourcePersistenceHint(type),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static String? _optionalPositiveNumber(String? value) {
    if ((value ?? '').trim().isEmpty) return null;
    final parsed = int.tryParse(value!.trim());
    if (parsed == null || parsed < 1) return 'Use a page above 0.';
    return null;
  }

  static String _sourceTitleLabel(_StudyMaterialSourceType type) {
    switch (type) {
      case _StudyMaterialSourceType.physicalBook:
        return 'Book title';
      case _StudyMaterialSourceType.articleOrWebsite:
        return 'Article / website title';
      case _StudyMaterialSourceType.libraryFile:
        return 'File title';
      case _StudyMaterialSourceType.readerFile:
        return 'Reader file title';
      case _StudyMaterialSourceType.currentFile:
        return 'Current file title';
      case _StudyMaterialSourceType.noSourceYet:
        return 'Source title';
    }
  }

  static String _sourceTitleHint(_StudyMaterialSourceType type) {
    switch (type) {
      case _StudyMaterialSourceType.physicalBook:
        return 'Book, chapter packet, or printed material';
      case _StudyMaterialSourceType.articleOrWebsite:
        return 'Article, website, lecture note, or reading';
      case _StudyMaterialSourceType.libraryFile:
        return 'PDF name';
      case _StudyMaterialSourceType.readerFile:
        return 'PDF or EPUB name';
      case _StudyMaterialSourceType.currentFile:
        return 'Current PDF or EPUB';
      case _StudyMaterialSourceType.noSourceYet:
        return 'Optional';
    }
  }

  static String _sourceNotesLabel(_StudyMaterialSourceType type) {
    switch (type) {
      case _StudyMaterialSourceType.physicalBook:
        return 'Chapter notes / edition notes';
      case _StudyMaterialSourceType.articleOrWebsite:
        return 'Source notes';
      default:
        return 'Material notes';
    }
  }

  static String _sourceNotesHint(_StudyMaterialSourceType type) {
    switch (type) {
      case _StudyMaterialSourceType.physicalBook:
        return 'Optional explicit chapter names, edition info, or reading notes.';
      case _StudyMaterialSourceType.articleOrWebsite:
        return 'Optional reading notes, citation info, or estimated length.';
      default:
        return 'Optional notes about page ranges, chapters, or what to focus on.';
    }
  }

  static String _sourcePersistenceHint(_StudyMaterialSourceType type) {
    switch (type) {
      case _StudyMaterialSourceType.currentFile:
        return 'This source is saved with the plan now. A later phase can connect it to the active reader context automatically.';
      case _StudyMaterialSourceType.libraryFile:
        return 'This source is saved with the plan now, including the library document link and page metadata when available.';
      case _StudyMaterialSourceType.readerFile:
        return 'The reader file path is saved with the plan. Structure is imported only from bookmarks, EPUB TOC metadata, or a high-confidence visible TOC parse; no chapters are guessed.';
      case _StudyMaterialSourceType.physicalBook:
        return 'Physical sources stay manual by design: title, optional page range, and notes are saved with the plan.';
      case _StudyMaterialSourceType.articleOrWebsite:
        return 'The title, link, and notes are saved with the plan so the source can be opened or enriched later.';
      case _StudyMaterialSourceType.noSourceYet:
        return '';
    }
  }
}

class _ResolvedSourceSummary extends StatelessWidget {
  final StudyMaterialSource source;

  const _ResolvedSourceSummary({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      _SourceMetaChip(icon: Icons.link_rounded, label: source.libraryDocumentId == null ? source.typeLabel : 'Linked PDF'),
      if (source.pageCount != null)
        _SourceMetaChip(
          icon: source.type == StudyMaterialSourceType.epubFile ? Icons.auto_stories_rounded : Icons.description_rounded,
          label: source.type == StudyMaterialSourceType.epubFile && source.hasRealPageMap
              ? '${source.pageCount} real EPUB pages'
              : '${source.pageCount} pages',
        ),
      if (source.hasRealPageMap)
        _SourceMetaChip(icon: Icons.my_location_rounded, label: source.paginationLabel),
      if (source.startPage != null && source.endPage != null)
        _SourceMetaChip(
          icon: Icons.linear_scale_rounded,
          label: source.type == StudyMaterialSourceType.epubFile
              ? 'pages ${source.startPage}–${source.endPage}'
              : 'pp. ${source.startPage}–${source.endPage}',
        ),
      if (StudyMaterialStructureConfidence.isTrusted(source.structureConfidence))
        _SourceMetaChip(
          icon: source.structureConfidence == StudyMaterialStructureConfidence.parsedToc
              ? Icons.fact_check_outlined
              : Icons.verified_outlined,
          label: StudyMaterialStructureConfidence.label(source.structureConfidence),
        ),
      if (source.segments.where((segment) => segment.type == StudyMaterialSegmentType.chapter).isNotEmpty)
        _SourceMetaChip(
          icon: Icons.library_books_rounded,
          label: '${source.segments.where((segment) => segment.type == StudyMaterialSegmentType.chapter).length} outline item${source.segments.where((segment) => segment.type == StudyMaterialSegmentType.chapter).length == 1 ? '' : 's'}',
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: chips),
          ],
        ],
      ),
    );
  }
}


class _SourceOutlinePreview extends StatelessWidget {
  final StudyMaterialSource source;

  const _SourceOutlinePreview({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = source.segments;
    final visible = _previewSegments(segments);
    final hiddenCount = segments.length - visible.length;
    final parsedToc = source.structureConfidence == StudyMaterialStructureConfidence.parsedToc;
    final explicit = source.structureConfidence == StudyMaterialStructureConfidence.explicitMetadata;
    final largeOutline = segments.length > 18;
    final topLevelCount = segments.where((segment) => (segment.level ?? 0) == 0).length;
    final withPageCount = segments.where((segment) => segment.startPage != null).length;
    final title = parsedToc
        ? 'Parsed table of contents'
        : explicit
            ? 'Detected outline'
            : 'Material structure';
    final subtitle = largeOutline
        ? 'Large sources are summarized here. Choose Chapters below to select the exact entries you want to plan; the app will not use every entry unless you select it.'
        : parsedToc
            ? 'Imported only because the visible TOC pattern passed reliability checks. Review before using.'
            : source.structureMessage;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _SourceMetaChip(
                icon: largeOutline ? Icons.view_agenda_outlined : Icons.format_list_bulleted_rounded,
                label: '${segments.length} entr${segments.length == 1 ? 'y' : 'ies'}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (topLevelCount > 0)
                _SourceMetaChip(
                  icon: Icons.layers_outlined,
                  label: '$topLevelCount top-level',
                ),
              if (withPageCount > 0)
                _SourceMetaChip(
                  icon: Icons.article_outlined,
                  label: '$withPageCount with pages',
                ),
              _SourceMetaChip(
                icon: parsedToc ? Icons.fact_check_outlined : Icons.verified_outlined,
                label: StudyMaterialStructureConfidence.label(source.structureConfidence),
              ),
            ],
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withAlpha(170),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(150)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  largeOutline ? 'Preview' : 'Outline entries',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < visible.length; i++) ...[
                  _OutlinePreviewRow(segment: visible[i]),
                  if (i != visible.length - 1) const SizedBox(height: 7),
                ],
                if (hiddenCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '+$hiddenCount more hidden in this compact preview',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
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

  static List<StudyMaterialSegment> _previewSegments(List<StudyMaterialSegment> segments) {
    if (segments.length <= 8) return segments;
    final topLevel = segments.where((segment) => (segment.level ?? 0) == 0).toList(growable: false);
    if (topLevel.length >= 2) return topLevel.take(6).toList(growable: false);
    final firstChildren = segments.where((segment) => (segment.level ?? 0) <= 1).toList(growable: false);
    if (firstChildren.length >= 4) return firstChildren.take(6).toList(growable: false);
    return segments.take(6).toList(growable: false);
  }
}

class _OutlinePreviewRow extends StatelessWidget {
  final StudyMaterialSegment segment;

  const _OutlinePreviewRow({required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = (segment.level ?? 0).clamp(0, 3);
    return Padding(
      padding: EdgeInsets.only(left: (level * 10).toDouble()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(180),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segment.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (segment.startPage != null || segment.href != null)
                  Text(
                    segment.startPage != null ? 'Starts on page ${segment.startPage}' : segment.href!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SourceMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(180),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PdfMaterialSourcePickerDialog extends StatefulWidget {
  final List<PdfDocument> documents;

  const _PdfMaterialSourcePickerDialog({required this.documents});

  @override
  State<_PdfMaterialSourcePickerDialog> createState() => _PdfMaterialSourcePickerDialogState();
}

class _PdfMaterialSourcePickerDialogState extends State<_PdfMaterialSourcePickerDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final documents = widget.documents.where((document) {
      if (query.isEmpty) return true;
      return document.name.toLowerCase().contains(query) ||
          document.originalFileName.toLowerCase().contains(query) ||
          (document.authors ?? '').toLowerCase().contains(query);
    }).toList(growable: false);

    return AlertDialog(
      title: const Text('Choose PDF from library'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                labelText: 'Search PDFs',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: documents.isEmpty
                  ? Center(
                      child: Text(
                        'No PDFs match your search.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: documents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final document = documents[index];
                        final subtitleParts = <String>[
                          if (document.authors?.trim().isNotEmpty == true) document.authors!.trim(),
                          document.originalFileName,
                        ];
                        return Material(
                          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            leading: Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.primary),
                            title: Text(
                              document.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(
                              subtitleParts.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).pop(document),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _SourceCapabilityNote extends StatelessWidget {
  final _StudyMaterialSourceType type;

  const _SourceCapabilityNote({required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = switch (type) {
      _StudyMaterialSourceType.currentFile => 'When opened from a PDF reader, this can attach the active PDF and prefill the page range.',
      _StudyMaterialSourceType.libraryFile => 'Pick a PDF from the library to save its document id, file path, title, and detected page count with the plan.',
      _StudyMaterialSourceType.readerFile => 'Insert a PDF or EPUB. PDFs use page count and bookmark outlines; EPUBs use their structured table of contents when present. The app will not invent missing chapters.',
      _StudyMaterialSourceType.physicalBook => 'For physical books, the app should stay manual but lightweight: title, page range, explicit chapter names, page ranges, and your own notes.',
      _StudyMaterialSourceType.articleOrWebsite => 'Save a title, link, and notes so this reading has a real source object instead of just a generic title.',
      _StudyMaterialSourceType.noSourceYet => 'You can still create a plan now. The source can be attached later from the library, PDF reader, or project workspace.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(90),
        borderRadius: BorderRadius.circular(16),
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

class _ScheduleDistributionPreview extends StatelessWidget {
  final DateTime startDate;
  final DateTime dueDate;
  final bool weekendsOff;
  final int totalUnits;
  final String unitLabel;

  const _ScheduleDistributionPreview({
    required this.startDate,
    required this.dueDate,
    required this.weekendsOff,
    required this.totalUnits,
    required this.unitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeDays = _eligibleDays(startDate, dueDate, weekendsOff).length.clamp(1, 999999).toInt();
    final weekdayDays = _eligibleDays(startDate, dueDate, true).length.clamp(1, 999999).toInt();
    final allDays = _eligibleDays(startDate, dueDate, false).length.clamp(1, 999999).toInt();
    final activePace = totalUnits <= 0 ? 0.0 : totalUnits / activeDays;
    final weekdayPace = totalUnits <= 0 ? 0.0 : totalUnits / weekdayDays;
    final allDayPace = totalUnits <= 0 ? 0.0 : totalUnits / allDays;
    final activeLabel = weekendsOff ? 'Weekends excluded' : 'Weekends included';
    final activeMeta = weekendsOff
        ? '$weekdayDays eligible weekday${weekdayDays == 1 ? '' : 's'}'
        : '$allDays eligible day${allDays == 1 ? '' : 's'}';
    final alternateHint = allDays == weekdayDays
        ? 'Weekend settings do not change this date range.'
        : weekendsOff
            ? 'Including weekends would make this about ${_formatPace(allDayPace)} / day across $allDays days.'
            : 'Excluding weekends would make this about ${_formatPace(weekdayPace)} / day across $weekdayDays weekdays.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withAlpha(55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Schedule preview',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ActivePaceTile(
            label: activeLabel,
            value: '${_formatPace(activePace)} / day',
            meta: activeMeta,
            summary: '$totalUnits $unitLabel over $activeDays study day${activeDays == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 10),
          Text(
            alternateHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivePaceTile extends StatelessWidget {
  final String label;
  final String value;
  final String meta;
  final String summary;

  const _ActivePaceTile({
    required this.label,
    required this.value,
    required this.meta,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(95)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(140),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.calendar_month_rounded, size: 19, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(summary, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        meta,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _ChapterStructureCard extends StatelessWidget {
  final List<String> chapters;
  final List<StudyMaterialSegment> detectedSegments;
  final Set<String> selectedDetectedKeys;
  final String Function(StudyMaterialSegment segment, int index) keyForDetected;
  final TextEditingController addController;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(StudyMaterialSegment segment, int index, bool selected) onToggleDetected;
  final VoidCallback onSelectAllDetected;
  final VoidCallback onClearDetected;
  final String? sourceTitle;

  const _ChapterStructureCard({
    required this.chapters,
    required this.detectedSegments,
    required this.selectedDetectedKeys,
    required this.keyForDetected,
    required this.addController,
    required this.onAdd,
    required this.onRemove,
    required this.onToggleDetected,
    required this.onSelectAllDetected,
    required this.onClearDetected,
    this.sourceTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.library_books_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chapter structure',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Chapters are valid only when they come from the material or when you define them yourself. Unknown chapters are never guessed or treated as known structure.',
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
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detectedSegments.isEmpty
                        ? 'No material chapter structure is known yet. Add the chapters/chunks you explicitly want the plan to use, or switch to pages when real page numbers are available.'
                        : 'Select the exact entries you were assigned from ${sourceTitle ?? 'this material'}. You can also type outline numbers like 3, 6, 18, or add your own named chunks.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (detectedSegments.isNotEmpty) ...[
            _DetectedChapterPicker(
              segments: detectedSegments,
              selectedKeys: selectedDetectedKeys,
              keyForDetected: keyForDetected,
              onToggle: onToggleDetected,
              onSelectAll: onSelectAllDetected,
              onClear: onClearDetected,
            ),
            const SizedBox(height: 12),
          ],
          if (chapters.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.error.withAlpha(90)),
              ),
              child: Text(
                'Add chapters before saving, or choose Pages. The app will not create a chapter plan from unknown structure.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            )
          else
            _CompactChapterList(
              chapters: chapters,
              onRemove: onRemove,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: addController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  decoration: InputDecoration(
                    labelText: detectedSegments.isEmpty ? 'Add chapter or explicit chunk' : 'Select by number or add chunk',
                    hintText: detectedSegments.isEmpty ? 'e.g. Chapter 4, Introduction, Cases 1–3' : 'e.g. 3, 6, 18 or Cases 1–3',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetectedChapterPicker extends StatelessWidget {
  final List<StudyMaterialSegment> segments;
  final Set<String> selectedKeys;
  final String Function(StudyMaterialSegment segment, int index) keyForDetected;
  final void Function(StudyMaterialSegment segment, int index, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  const _DetectedChapterPicker({
    required this.segments,
    required this.selectedKeys,
    required this.keyForDetected,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = selectedKeys.length;
    final listHeight = segments.length <= 6 ? null : 320.0;
    final list = ListView.separated(
      shrinkWrap: segments.length <= 6,
      physics: segments.length <= 6 ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      itemCount: segments.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: theme.colorScheme.outlineVariant.withAlpha(130)),
      itemBuilder: (context, index) {
        final segment = segments[index];
        final key = keyForDetected(segment, index);
        final selected = selectedKeys.contains(key);
        final meta = segment.startPage != null
            ? 'page ${segment.startPage}'
            : (segment.href == null || segment.href!.trim().isEmpty ? null : segment.href);
        return CheckboxListTile(
          value: selected,
          onChanged: (value) => onToggle(segment, index, value ?? false),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(110),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '#${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  segment.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          subtitle: meta == null
              ? null
              : Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
        );
      },
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_list_numbered_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select from detected outline',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '$selectedCount / ${segments.length} selected',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Use the numbers when your assignment says things like “read chapter 3, 6, and 18”. The app uses only the entries you select.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: onSelectAll,
                icon: const Icon(Icons.select_all_rounded),
                label: const Text('Select all'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: selectedCount == 0 ? null : onClear,
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (listHeight == null) list else SizedBox(height: listHeight, child: list),
        ],
      ),
    );
  }
}

class _CompactChapterList extends StatelessWidget {
  final List<String> chapters;
  final ValueChanged<int> onRemove;

  const _CompactChapterList({required this.chapters, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = chapters.length > 14 ? 10 : chapters.length;
    final hiddenCount = chapters.length - visibleCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.library_books_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${chapters.length} explicit chapter/chunk${chapters.length == 1 ? '' : 's'} selected',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (hiddenCount > 0)
                Text(
                  'showing $visibleCount',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < visibleCount; i++) ...[
          _ChecklistItemRow(
            index: i + 1,
            text: chapters[i],
            onRemove: () => onRemove(i),
          ),
          if (i != visibleCount - 1) const SizedBox(height: 8),
        ],
        if (hiddenCount > 0) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              '+$hiddenCount more explicit chunks hidden in this compact editor. A later outline-review screen should handle large-source bulk editing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChecklistBuilderCard extends StatelessWidget {
  final List<String> items;
  final TextEditingController addController;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _ChecklistBuilderCard({
    required this.items,
    required this.addController,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Topics / checklist items',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Add items one at a time. You can also paste multiple lines or semicolon-separated items into the field.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                'No topics yet. Add the first item below.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _ChecklistItemRow(
                    index: i + 1,
                    text: items[i],
                    onRemove: () => onRemove(i),
                  ),
                  if (i != items.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: addController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  decoration: const InputDecoration(
                    labelText: 'Add topic or item',
                    hintText: 'e.g. Lecture 3, OLG model, practice questions',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChecklistItemRow extends StatelessWidget {
  final int index;
  final String text;
  final VoidCallback onRemove;

  const _ChecklistItemRow({
    required this.index,
    required this.text,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(130),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$index',
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          IconButton(
            tooltip: 'Remove item',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final PlanningDraft draft;
  final List<String> previewLines;

  const _PreviewPanel({required this.draft, required this.previewLines});

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
                Icon(Icons.preview_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Plan preview',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Before saving, this shows what the app will create.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            for (final line in previewLines) ...[
              _PreviewLine(text: line),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(100),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${draft.intent.label} will appear in Today, Calendar, project planning, and future replanning.',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  final String text;

  const _PreviewLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _MissingBadge extends StatelessWidget {
  final int count;

  const _MissingBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count detail${count == 1 ? '' : 's'}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MissingDetailsCard extends StatelessWidget {
  final List<PlanningDraftQuestion> questions;

  const _MissingDetailsCard({required this.questions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withAlpha(100),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.tertiary.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Missing details',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final question in questions) ...[
            Text('• ${question.text}', style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
            if (question.helperText != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
                child: Text(
                  question.helperText!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BehaviorNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _BehaviorNote({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  text,
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

class _UnitOption {
  final String value;
  final String label;
  final String helper;
  final IconData icon;

  const _UnitOption({
    required this.value,
    required this.label,
    required this.helper,
    required this.icon,
  });
}

class _RangePreset {
  final String label;
  final int start;
  final int end;

  const _RangePreset(this.label, this.start, this.end);
}

class _UnitSetupCard extends StatelessWidget {
  final String selectedType;
  final bool forRoutine;
  final String? title;
  final String? helper;
  final Set<String> disabledUnits;
  final Map<String, String> disabledReasons;
  final ValueChanged<String> onChanged;

  const _UnitSetupCard({
    required this.selectedType,
    required this.forRoutine,
    required this.onChanged,
    this.title,
    this.helper,
    this.disabledUnits = const <String>{},
    this.disabledReasons = const <String, String>{},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <_UnitOption>[
      const _UnitOption(
        value: 'pages',
        label: 'Pages',
        helper: 'Readings, books, PDFs',
        icon: Icons.menu_book_rounded,
      ),
      const _UnitOption(
        value: 'chapters',
        label: 'Chapters',
        helper: 'Known or defined chunks',
        icon: Icons.library_books_rounded,
      ),
      const _UnitOption(
        value: 'sections',
        label: 'Sections',
        helper: 'Writing, reports, articles',
        icon: Icons.segment_rounded,
      ),
      const _UnitOption(
        value: 'exercises',
        label: 'Exercises',
        helper: 'Problem sets and practice',
        icon: Icons.functions_rounded,
      ),
      _UnitOption(
        value: 'custom',
        label: forRoutine ? 'Custom routine' : 'Custom',
        helper: forRoutine ? 'Flashcards, cases, reps' : 'Anything measurable',
        icon: Icons.tune_rounded,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? (forRoutine ? 'What repeats?' : 'How should this be measured?'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      helper ?? (forRoutine
                          ? 'Choose the thing that should appear on each study day.'
                          : 'Choose the unit that best represents the work. The range and preview adapt automatically.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in options)
                    SizedBox(
                      width: narrow ? constraints.maxWidth : (constraints.maxWidth - 20) / 3,
                      child: _UnitChoiceCard(
                        option: disabledReasons.containsKey(option.value)
                            ? _UnitOption(
                                value: option.value,
                                label: option.label,
                                helper: disabledReasons[option.value]!,
                                icon: option.icon,
                              )
                            : option,
                        selected: selectedType == option.value,
                        disabled: disabledUnits.contains(option.value),
                        onTap: () => onChanged(option.value),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _UnitChoiceCard extends StatelessWidget {
  final _UnitOption option;
  final bool selected;
  final bool disabled;
  final bool loading;
  final VoidCallback onTap;

  const _UnitChoiceCard({
    required this.option,
    required this.selected,
    required this.onTap,
    this.disabled = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface;
    final border = selected ? theme.colorScheme.primary.withAlpha(180) : theme.colorScheme.outlineVariant;
    final foreground = selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: disabled || loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected ? theme.colorScheme.primary.withAlpha(35) : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(option.icon, size: 18, color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loading ? 'Loading…' : option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.helper,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: disabled
                            ? theme.colorScheme.onSurfaceVariant.withAlpha(140)
                            : selected
                                ? theme.colorScheme.onPrimaryContainer.withAlpha(210)
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, size: 18, color: theme.colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RangePlannerCard extends StatelessWidget {
  final TextEditingController startController;
  final TextEditingController endController;
  final String startLabel;
  final String endLabel;
  final int totalUnits;
  final String totalLabel;
  final String shortLabel;
  final String explanation;
  final String? Function(String?)? startValidator;
  final String? Function(String?)? endValidator;

  const _RangePlannerCard({
    required this.startController,
    required this.endController,
    required this.startLabel,
    required this.endLabel,
    required this.totalUnits,
    required this.totalLabel,
    required this.shortLabel,
    required this.explanation,
    required this.startValidator,
    required this.endValidator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startText = startController.text.trim().isEmpty ? '?' : startController.text.trim();
    final endText = endController.text.trim().isEmpty ? '?' : endController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(150),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.route_rounded, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount of work',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalUnits $totalLabel • $shortLabel $startText–$endText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final startField = TextFormField(
                controller: startController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: startLabel,
                  prefixIcon: const Icon(Icons.first_page_rounded),
                  border: const OutlineInputBorder(),
                ),
                validator: startValidator,
              );
              final endField = TextFormField(
                controller: endController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: endLabel,
                  prefixIcon: const Icon(Icons.last_page_rounded),
                  border: const OutlineInputBorder(),
                ),
                validator: endValidator,
              );
              if (narrow) {
                return Column(
                  children: [
                    startField,
                    const SizedBox(height: 12),
                    endField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: startField),
                  const SizedBox(width: 12),
                  Expanded(child: endField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}


class _PlanModeCard extends StatelessWidget {
  final bool byTime;
  final ValueChanged<bool> onChanged;

  const _PlanModeCard({
    required this.byTime,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How should this plan be created?',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Plan by measurable output, or reserve a fixed amount of study time across the calendar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.format_list_numbered_rounded),
                label: Text('Quantity'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.schedule_rounded),
                label: Text('Time'),
              ),
            ],
            selected: {byTime},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}

class _TimePlanCard extends StatelessWidget {
  final _TimePlanInputMode inputMode;
  final TextEditingController hoursController;
  final TextEditingController minutesController;
  final TextEditingController startController;
  final TextEditingController endController;
  final ValueChanged<_TimePlanInputMode> onInputModeChanged;
  final VoidCallback onChanged;

  const _TimePlanCard({
    required this.inputMode,
    required this.hoursController,
    required this.minutesController,
    required this.startController,
    required this.endController,
    required this.onInputModeChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(130),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.schedule_rounded, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plan time on the calendar',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose flexible daily effort, or place the work at a concrete time of day.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _TimePlanModeTile(
                  selected: inputMode == _TimePlanInputMode.duration,
                  icon: Icons.hourglass_bottom_rounded,
                  title: 'Flexible duration',
                  subtitle: 'Example: 90 minutes each study day. The app does not reserve a clock time.',
                  onTap: () => onInputModeChanged(_TimePlanInputMode.duration),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimePlanModeTile(
                  selected: inputMode == _TimePlanInputMode.window,
                  icon: Icons.calendar_view_day_rounded,
                  title: 'Fixed time of day',
                  subtitle: 'Example: 08:00–09:00. The app places a real block in the calendar.',
                  onTap: () => onInputModeChanged(_TimePlanInputMode.window),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: inputMode == _TimePlanInputMode.duration
                ? _durationFields(context)
                : _timeWindowFields(context),
          ),
        ],
      ),
    );
  }

  Widget _durationFields(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('duration-plan-fields'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: hoursController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Hours per day',
                  hintText: '1',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  hintText: '30',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TimePlanHint(
          icon: Icons.info_outline_rounded,
          text: 'Flexible duration appears as an amount of planned work on each eligible day. Use Fixed time of day when you want 08:00–09:00, 13:00–14:30, and so on.',
          color: theme.colorScheme.primary,
        ),
      ],
    );
  }

  Widget _timeWindowFields(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('window-plan-fields'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: startController,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'Start time',
                  hintText: '08:00',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: endController,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'End time',
                  hintText: '09:00',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _TimeWindowPresetChip(label: 'Start of day', range: '08:00–09:00', onTap: () => _applyPreset('08:00', '09:00')),
            _TimeWindowPresetChip(label: 'Deep work', range: '09:00–11:00', onTap: () => _applyPreset('09:00', '11:00')),
            _TimeWindowPresetChip(label: 'After lunch', range: '13:00–14:30', onTap: () => _applyPreset('13:00', '14:30')),
            _TimeWindowPresetChip(label: 'Evening', range: '18:00–19:00', onTap: () => _applyPreset('18:00', '19:00')),
          ],
        ),
        const SizedBox(height: 10),
        _TimePlanHint(
          icon: Icons.event_available_rounded,
          text: 'Fixed time creates actual calendar blocks on every eligible day between the selected dates.',
          color: theme.colorScheme.primary,
        ),
      ],
    );
  }

  void _applyPreset(String start, String end) {
    startController.text = start;
    endController.text = end;
    onChanged();
  }
}

class _TimePlanModeTile extends StatelessWidget {
  const _TimePlanModeTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer.withAlpha(130) : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? theme.colorScheme.primary.withOpacity(.55) : theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.22,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeWindowPresetChip extends StatelessWidget {
  const _TimeWindowPresetChip({required this.label, required this.range, required this.onTap});

  final String label;
  final String range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(Icons.schedule_rounded, size: 15, color: theme.colorScheme.primary),
      label: Text('$label · $range'),
      onPressed: onTap,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      backgroundColor: theme.colorScheme.surface,
      labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _TimePlanHint extends StatelessWidget {
  const _TimePlanHint({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _DailyTargetCard extends StatelessWidget {
  final TextEditingController controller;
  final String unitLabel;
  final String? Function(String?)? validator;

  const _DailyTargetCard({
    required this.controller,
    required this.unitLabel,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How much each study day?',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Type the exact amount that should appear on each eligible study day.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Daily amount',
              helperText: 'Example: 3 cases, 20 flashcards, 1 article.',
              suffixText: unitLabel,
              border: const OutlineInputBorder(),
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }
}

class _UnitQuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _UnitQuickActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      backgroundColor: theme.colorScheme.secondaryContainer.withAlpha(120),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      labelStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}


class _CustomUnitCard extends StatelessWidget {
  final TextEditingController singularController;
  final TextEditingController pluralController;
  final TextEditingController labelController;

  const _CustomUnitCard({
    required this.singularController,
    required this.pluralController,
    required this.labelController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Name the work unit',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Use a preset or name the unit yourself. This only controls how the plan is displayed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _UnitQuickActionChip(
                label: 'Sections',
                icon: Icons.segment_rounded,
                onTap: () {
                  singularController.text = 'section';
                  pluralController.text = 'sections';
                  labelController.text = 'sec.';
                },
              ),
              _UnitQuickActionChip(
                label: 'Words',
                icon: Icons.text_fields_rounded,
                onTap: () {
                  singularController.text = 'word';
                  pluralController.text = 'words';
                  labelController.text = 'words';
                },
              ),
              _UnitQuickActionChip(
                label: 'Articles',
                icon: Icons.article_rounded,
                onTap: () {
                  singularController.text = 'article';
                  pluralController.text = 'articles';
                  labelController.text = 'art.';
                },
              ),
              _UnitQuickActionChip(
                label: 'Flashcards',
                icon: Icons.style_rounded,
                onTap: () {
                  singularController.text = 'flashcard';
                  pluralController.text = 'flashcards';
                  labelController.text = 'cards';
                },
              ),
              _UnitQuickActionChip(
                label: 'Cases',
                icon: Icons.balance_rounded,
                onTap: () {
                  singularController.text = 'case';
                  pluralController.text = 'cases';
                  labelController.text = 'case';
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final singularField = TextFormField(
                controller: singularController,
                decoration: const InputDecoration(
                  labelText: 'One unit',
                  hintText: 'section',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Name one unit.';
                  return null;
                },
              );
              final pluralField = TextFormField(
                controller: pluralController,
                decoration: const InputDecoration(
                  labelText: 'Multiple units',
                  hintText: 'sections',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Name multiple units.';
                  return null;
                },
              );
              if (narrow) {
                return Column(children: [singularField, const SizedBox(height: 12), pluralField]);
              }
              return Row(
                children: [
                  Expanded(child: singularField),
                  const SizedBox(width: 12),
                  Expanded(child: pluralField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: labelController,
            decoration: const InputDecoration(
              labelText: 'Short calendar label',
              hintText: 'sec.',
              helperText: 'Used in labels such as “sec. 1–3”.',
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
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null ? emptyLabel : _formatDate(value!),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (onClear != null)
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

IconData _intentIcon(PlanningIntentType intent) {
  switch (intent) {
    case PlanningIntentType.studyMaterial:
      return Icons.menu_book_rounded;
    case PlanningIntentType.finishByDate:
      return Icons.timeline_rounded;
    case PlanningIntentType.addTask:
      return Icons.task_alt_rounded;
    case PlanningIntentType.rememberDeadline:
      return Icons.flag_rounded;
    case PlanningIntentType.reviewTopics:
      return Icons.checklist_rounded;
    case PlanningIntentType.buildRoutine:
      return Icons.repeat_rounded;
    case PlanningIntentType.writeSomething:
      return Icons.edit_note_rounded;
  }
}

List<DateTime> _eligibleDays(DateTime start, DateTime end, bool weekendsOff) {
  final result = <DateTime>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!cursor.isAfter(last)) {
    final isWeekend = cursor.weekday == DateTime.saturday || cursor.weekday == DateTime.sunday;
    if (!weekendsOff || !isWeekend) result.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  return result;
}

String _formatPace(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _formatNullableDate(DateTime? value) => value == null ? 'not set yet' : _formatDate(value);

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
