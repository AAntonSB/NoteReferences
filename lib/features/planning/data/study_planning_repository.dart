import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/study_material_source.dart';

class StudyPlanningRepository extends ChangeNotifier {
  StudyPlanningRepository({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final List<StudyProject> _projects = <StudyProject>[];
  final List<StudyPlan> _plans = <StudyPlan>[];
  final List<SessionHandoff> _handoffs = <SessionHandoff>[];
  final List<WorkspaceDocument> _documents = <WorkspaceDocument>[];
  final List<DevTodo> _devTodos = <DevTodo>[];
  final List<PlanningEntry> _planningEntries = <PlanningEntry>[];
  final List<TodayPlanSnapshot> _todayPlans = <TodayPlanSnapshot>[];
  final Map<String, String> _pdfProjectIds = <String, String>{};
  final List<LibraryFolder> _libraryFolders = <LibraryFolder>[];
  final Map<String, String> _pdfFolderIds = <String, String>{};

  File? _storageFile;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  List<StudyProject> get projects => List.unmodifiable(
        _projects.where((project) => !project.isArchived),
      );

  List<StudyPlan> get plans => List.unmodifiable(
        _plans.where((plan) => !plan.isArchived),
      );

  List<SessionHandoff> get handoffs => List.unmodifiable(
        _handoffs.where((handoff) => !handoff.isArchived),
      );

  List<WorkspaceDocument> get documents => List.unmodifiable(
        _documents.where((document) => !document.isArchived),
      );

  List<DevTodo> get devTodos => List.unmodifiable(
        _devTodos.where((todo) => !todo.isArchived),
      );

  List<PlanningEntry> get planningEntries => List.unmodifiable(
        _planningEntries.where((entry) => !entry.isArchived),
      );

  List<PlanningEntry> get planningInboxEntries {
    final result = planningEntries
        .where((entry) => !entry.isDone && entry.calendarDate == null)
        .toList(growable: false);
    result.sort((a, b) {
      final priorityCompare = PlanningEntryPriority.rank(b.priority)
          .compareTo(PlanningEntryPriority.rank(a.priority));
      if (priorityCompare != 0) return priorityCompare;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return result;
  }

  List<TodayPlanSnapshot> get todayPlans => List.unmodifiable(_todayPlans);

  Map<String, String> get pdfProjectIds => Map.unmodifiable(_pdfProjectIds);

  List<LibraryFolder> get libraryFolders => List.unmodifiable(
        _libraryFolders.where((folder) => !folder.isArchived),
      );

  Map<String, String> get pdfFolderIds => Map.unmodifiable(_pdfFolderIds);

  Future<void> load() async {
    if (_loaded) return;

    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    _storageFile = File(p.join(directory.path, 'study_planning.json'));

    final file = _storageFile!;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final map = decoded.map((key, value) => MapEntry(key.toString(), value));
          final rawProjects = map['projects'];
          final rawPlans = map['plans'];
          final rawHandoffs = map['sessionHandoffs'];
          final rawDocuments = map['workspaceDocuments'] ?? map['documents'];
          final rawDevTodos = map['devTodos'];
          final rawPlanningEntries = map['planningEntries'];
          final rawTodayPlans = map['todayPlans'];
          final rawPdfProjects = map['pdfProjectIds'];
          final rawLibraryFolders = map['libraryFolders'];
          final rawPdfFolders = map['pdfFolderIds'];

          _projects
            ..clear()
            ..addAll(
              rawProjects is List
                  ? rawProjects
                      .whereType<Map>()
                      .map((item) => StudyProject.fromJson(_stringMap(item)))
                  : const <StudyProject>[],
            );
          _plans
            ..clear()
            ..addAll(
              rawPlans is List
                  ? rawPlans
                      .whereType<Map>()
                      .map((item) => StudyPlan.fromJson(_stringMap(item)))
                  : const <StudyPlan>[],
            );
          _handoffs
            ..clear()
            ..addAll(
              rawHandoffs is List
                  ? rawHandoffs
                      .whereType<Map>()
                      .map((item) => SessionHandoff.fromJson(_stringMap(item)))
                  : const <SessionHandoff>[],
            );
          _documents
            ..clear()
            ..addAll(
              rawDocuments is List
                  ? rawDocuments
                      .whereType<Map>()
                      .map((item) => WorkspaceDocument.fromJson(_stringMap(item)))
                  : const <WorkspaceDocument>[],
            );
          _devTodos
            ..clear()
            ..addAll(
              rawDevTodos is List
                  ? rawDevTodos
                      .whereType<Map>()
                      .map((item) => DevTodo.fromJson(_stringMap(item)))
                  : const <DevTodo>[],
            );
          _planningEntries
            ..clear()
            ..addAll(
              rawPlanningEntries is List
                  ? rawPlanningEntries
                      .whereType<Map>()
                      .map((item) => PlanningEntry.fromJson(_stringMap(item)))
                  : const <PlanningEntry>[],
            );
          _todayPlans
            ..clear()
            ..addAll(
              rawTodayPlans is List
                  ? rawTodayPlans
                      .whereType<Map>()
                      .map((item) => TodayPlanSnapshot.fromJson(_stringMap(item)))
                  : const <TodayPlanSnapshot>[],
            );
          _pdfProjectIds
            ..clear()
            ..addAll(
              rawPdfProjects is Map
                  ? rawPdfProjects.map(
                      (key, value) => MapEntry(key.toString(), value.toString()),
                    )
                  : const <String, String>{},
            );
          _libraryFolders
            ..clear()
            ..addAll(
              rawLibraryFolders is List
                  ? rawLibraryFolders
                      .whereType<Map>()
                      .map((item) => LibraryFolder.fromJson(_stringMap(item)))
                  : const <LibraryFolder>[],
            );
          _pdfFolderIds
            ..clear()
            ..addAll(
              rawPdfFolders is Map
                  ? rawPdfFolders.map(
                      (key, value) => MapEntry(key.toString(), value.toString()),
                    )
                  : const <String, String>{},
            );
        }
      } catch (error, stackTrace) {
        debugPrint('Could not read study planning data: $error');
        debugPrint('$stackTrace');
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<StudyProject> createProject({
    required String title,
    DateTime? deadline,
  }) async {
    final now = DateTime.now();
    final project = StudyProject(
      id: _uuid.v4(),
      title: title.trim(),
      type: 'Project',
      createdAt: now,
      updatedAt: now,
      deadline: deadline == null ? null : _dateOnly(deadline),
    );

    _projects.add(project);
    await _save();
    notifyListeners();
    return project;
  }

  Future<StudyPlan> createPlan({
    required String projectId,
    required String title,
    required String unitType,
    required DateTime startDate,
    required bool weekendsOff,
    String planKind = StudyPlanKind.progress,
    int? startUnit,
    int? endUnit,
    int? dailyTarget,
    int? timeStartMinutes,
    int? timeEndMinutes,
    DateTime? deadline,
    DateTime? taskDate,
    String? customUnitSingular,
    String? customUnitPlural,
    String? customUnitLabel,
    List<String>? checklistItems,
    StudyMaterialSource? materialSource,
  }) async {
    final now = DateTime.now();
    final normalizedKind = StudyPlanKind.normalize(planKind);

    final requestedStart = startUnit ?? 1;
    final normalizedStart = requestedStart < 1 ? 1 : requestedStart;
    final requestedEnd = endUnit ?? normalizedStart;
    final normalizedEnd = normalizedKind == StudyPlanKind.progress
        ? (requestedEnd < normalizedStart ? normalizedStart : requestedEnd)
        : 0;
    final requestedDailyTarget = dailyTarget ?? 1;
    final normalizedDailyTarget = normalizedKind == StudyPlanKind.recurring
        ? (requestedDailyTarget < 1 ? 1 : requestedDailyTarget)
        : null;
    final normalizedTimeStart = _normalizeMinuteOfDay(timeStartMinutes);
    final normalizedTimeEnd = _normalizeMinuteOfDay(timeEndMinutes);
    final effectiveTimeStart = normalizedTimeStart != null &&
            normalizedTimeEnd != null &&
            normalizedTimeEnd > normalizedTimeStart
        ? normalizedTimeStart
        : null;
    final effectiveTimeEnd = effectiveTimeStart == null ? null : normalizedTimeEnd;

    final cleanChecklist = (checklistItems ?? const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final normalizedStartDate = _dateOnly(startDate);
    final normalizedTaskDate = taskDate == null ? null : _dateOnly(taskDate);
    DateTime? effectiveDeadline;
    if (normalizedKind == StudyPlanKind.progress || normalizedKind == StudyPlanKind.checklist) {
      effectiveDeadline = _dateOnly(deadline ?? startDate);
    } else if (normalizedKind == StudyPlanKind.recurring) {
      effectiveDeadline = deadline == null ? null : _dateOnly(deadline);
    } else if (normalizedKind == StudyPlanKind.singleTask) {
      effectiveDeadline = _dateOnly(normalizedTaskDate ?? deadline ?? startDate);
    } else if (normalizedKind == StudyPlanKind.deadline) {
      effectiveDeadline = _dateOnly(deadline ?? normalizedTaskDate ?? startDate);
    } else {
      effectiveDeadline = deadline == null ? null : _dateOnly(deadline);
    }

    final plan = StudyPlan(
      id: _uuid.v4(),
      projectId: projectId,
      title: title.trim(),
      planKind: normalizedKind,
      unitType: unitType,
      customUnitSingular: _cleanOptional(customUnitSingular),
      customUnitPlural: _cleanOptional(customUnitPlural),
      customUnitLabel: _cleanOptional(customUnitLabel),
      materialSource: materialSource?.hasSource == true ? materialSource : null,
      startUnit: normalizedStart,
      endUnit: normalizedEnd,
      completedThroughUnit: normalizedKind == StudyPlanKind.progress ? normalizedStart - 1 : 0,
      dailyTarget: normalizedDailyTarget,
      timeStartMinutes: effectiveTimeStart,
      timeEndMinutes: effectiveTimeEnd,
      completedDateKeys: const <String>{},
      checklistItems: cleanChecklist,
      completedChecklistIndexes: const <int>{},
      startDate: normalizedStartDate,
      deadline: effectiveDeadline,
      taskDate: normalizedTaskDate ?? effectiveDeadline ?? normalizedStartDate,
      weekendsOff: weekendsOff,
      createdAt: now,
      updatedAt: now,
    );

    _plans.add(plan);
    await _save();
    notifyListeners();
    return plan;
  }


  Future<PlanningEntry> createPlanningEntry({
    required String title,
    String? notes,
    String kind = PlanningEntryKind.task,
    String priority = PlanningEntryPriority.normal,
    String? projectId,
    DateTime? date,
    DateTime? dueAt,
    DateTime? startAt,
    DateTime? endAt,
    bool allDay = true,
    int? estimateMinutes,
  }) async {
    final now = DateTime.now();
    final cleanTitle = title.trim().isEmpty ? 'Untitled planning item' : title.trim();
    final cleanProjectId = _cleanOptional(projectId);
    final entry = PlanningEntry(
      id: _uuid.v4(),
      title: cleanTitle,
      notes: _cleanOptional(notes),
      kind: PlanningEntryKind.normalize(kind),
      priority: PlanningEntryPriority.normalize(priority),
      status: PlanningEntryStatus.open,
      projectId: cleanProjectId == null || projectById(cleanProjectId) == null ? null : cleanProjectId,
      date: date == null ? null : _dateOnly(date),
      dueAt: dueAt,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      estimateMinutes: estimateMinutes == null || estimateMinutes <= 0 ? null : estimateMinutes,
      createdAt: now,
      updatedAt: now,
    );
    _planningEntries.add(entry);
    await _save();
    notifyListeners();
    return entry;
  }

  Future<void> updatePlanningEntry({
    required String entryId,
    String? title,
    Object? notes = _sentinel,
    String? kind,
    String? priority,
    Object? projectId = _sentinel,
    Object? date = _sentinel,
    Object? dueAt = _sentinel,
    Object? startAt = _sentinel,
    Object? endAt = _sentinel,
    bool? allDay,
    Object? estimateMinutes = _sentinel,
  }) async {
    final index = _planningEntries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    final existing = _planningEntries[index];
    final cleanProjectId = identical(projectId, _sentinel)
        ? existing.projectId
        : projectId is String
            ? _cleanOptional(projectId)
            : null;
    _planningEntries[index] = existing.copyWith(
      title: title == null ? null : (title.trim().isEmpty ? existing.title : title.trim()),
      notes: notes,
      kind: kind == null ? null : PlanningEntryKind.normalize(kind),
      priority: priority == null ? null : PlanningEntryPriority.normalize(priority),
      projectId: cleanProjectId == null || projectById(cleanProjectId) == null ? null : cleanProjectId,
      date: date,
      dueAt: dueAt,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      estimateMinutes: estimateMinutes,
      updatedAt: DateTime.now(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> completePlanningEntry(String entryId, {bool isDone = true}) async {
    final index = _planningEntries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    final now = DateTime.now();
    _planningEntries[index] = _planningEntries[index].copyWith(
      status: isDone ? PlanningEntryStatus.done : PlanningEntryStatus.open,
      completedAt: isDone ? now : null,
      clearCompletedAt: !isDone,
      updatedAt: now,
    );
    await _save();
    notifyListeners();
  }

  Future<void> archivePlanningEntry(String entryId) async {
    final index = _planningEntries.indexWhere((entry) => entry.id == entryId);
    if (index == -1) return;
    _planningEntries[index] = _planningEntries[index].copyWith(
      isArchived: true,
      updatedAt: DateTime.now(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> schedulePlanningEntry({
    required String entryId,
    required DateTime date,
  }) async {
    await updatePlanningEntry(entryId: entryId, date: _dateOnly(date));
  }

  Future<void> postponePlanningEntry({
    required String entryId,
    required DateTime date,
  }) async {
    await updatePlanningEntry(entryId: entryId, date: _dateOnly(date), dueAt: _dateOnly(date));
  }

  List<PlanningEntry> planningEntriesForDate(DateTime date) {
    final day = _dateOnly(date);
    final result = planningEntries.where((entry) {
      if (entry.isDone) return false;
      final calendarDate = entry.calendarDate;
      return calendarDate != null && _dateKey(calendarDate) == _dateKey(day);
    }).toList(growable: false);
    result.sort(PlanningEntry.compareForCalendar);
    return result;
  }

  List<PlanningEntry> planningEntriesForRange({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    bool includeDone = false,
  }) {
    final start = _dateOnly(rangeStart);
    final end = _dateOnly(rangeEnd);
    final result = planningEntries.where((entry) {
      if (!includeDone && entry.isDone) return false;
      final calendarDate = entry.calendarDate;
      if (calendarDate == null) return false;
      final day = _dateOnly(calendarDate);
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList(growable: false);
    result.sort(PlanningEntry.compareForCalendar);
    return result;
  }

  TodayPlanSnapshot? todayPlanForDate(DateTime date) {
    final key = _dateKey(date);
    for (final plan in _todayPlans) {
      if (_dateKey(plan.date) == key) return plan;
    }
    return null;
  }

  Future<TodayPlanSnapshot> saveTodayPlan({
    required DateTime date,
    required List<TodayPlanItem> items,
  }) async {
    final now = DateTime.now();
    final key = _dateKey(date);
    final index = _todayPlans.indexWhere((plan) => _dateKey(plan.date) == key);
    final existing = index == -1 ? null : _todayPlans[index];
    final snapshot = TodayPlanSnapshot(
      date: _dateOnly(date),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      items: items,
    );
    if (index == -1) {
      _todayPlans.add(snapshot);
    } else {
      _todayPlans[index] = snapshot;
    }
    await _save();
    notifyListeners();
    return snapshot;
  }

  List<SessionHandoff> handoffsForProject(String projectId) {
    return handoffs.where((handoff) => handoff.projectId == projectId && handoff.items.isNotEmpty).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<SessionHandoffEntry> activeHandoffEntries({String? projectId}) {
    final result = <SessionHandoffEntry>[];
    for (final handoff in handoffs) {
      if (projectId != null && handoff.projectId != projectId) continue;
      final project = projectById(handoff.projectId);
      if (project == null) continue;
      for (final item in handoff.items) {
        if (item.isDone) continue;
        result.add(SessionHandoffEntry(project: project, handoff: handoff, item: item));
      }
    }
    result.sort((a, b) {
      final projectCompare = a.project.title.toLowerCase().compareTo(b.project.title.toLowerCase());
      if (projectCompare != 0) return projectCompare;
      return b.handoff.updatedAt.compareTo(a.handoff.updatedAt);
    });
    return result;
  }

  Future<SessionHandoff> addSessionHandoffItems({
    required String projectId,
    required List<String> itemTexts,
  }) async {
    final cleanTexts = itemTexts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (cleanTexts.isEmpty) {
      final existing = handoffsForProject(projectId);
      if (existing.isNotEmpty) return existing.first;
      throw ArgumentError.value(itemTexts, 'itemTexts', 'At least one handoff item is required.');
    }

    final now = DateTime.now();
    final newItems = <SessionHandoffItem>[
      for (final text in cleanTexts)
        SessionHandoffItem(
          id: _uuid.v4(),
          text: text,
          createdAt: now,
        ),
    ];

    final index = _handoffs.indexWhere(
      (handoff) => !handoff.isArchived && handoff.projectId == projectId,
    );

    final SessionHandoff handoff;
    if (index == -1) {
      handoff = SessionHandoff(
        id: _uuid.v4(),
        projectId: projectId,
        createdAt: now,
        updatedAt: now,
        items: newItems,
      );
      _handoffs.add(handoff);
    } else {
      handoff = _handoffs[index].copyWith(
        updatedAt: now,
        items: <SessionHandoffItem>[..._handoffs[index].items, ...newItems],
      );
      _handoffs[index] = handoff;
    }

    await _save();
    notifyListeners();
    return handoff;
  }

  Future<void> updateSessionHandoffItemDone({
    required String handoffId,
    required String itemId,
    required bool isDone,
  }) async {
    final handoffIndex = _handoffs.indexWhere((handoff) => handoff.id == handoffId);
    if (handoffIndex == -1) return;

    final handoff = _handoffs[handoffIndex];
    final itemIndex = handoff.items.indexWhere((item) => item.id == itemId);
    if (itemIndex == -1) return;

    final now = DateTime.now();
    final items = <SessionHandoffItem>[...handoff.items];
    items[itemIndex] = items[itemIndex].copyWith(
      isDone: isDone,
      completedAt: isDone ? now : null,
      clearCompletedAt: !isDone,
    );
    _handoffs[handoffIndex] = handoff.copyWith(updatedAt: now, items: items);

    await _save();
    notifyListeners();
  }

  Future<void> deleteSessionHandoffItem({
    required String handoffId,
    required String itemId,
  }) async {
    final handoffIndex = _handoffs.indexWhere((handoff) => handoff.id == handoffId);
    if (handoffIndex == -1) return;

    final handoff = _handoffs[handoffIndex];
    final items = handoff.items.where((item) => item.id != itemId).toList(growable: false);
    _handoffs[handoffIndex] = handoff.copyWith(updatedAt: DateTime.now(), items: items);

    await _save();
    notifyListeners();
  }

  Future<StudyPlan?> convertHandoffItemToTodo({
    required String handoffId,
    required String itemId,
    DateTime? taskDate,
  }) async {
    final handoffIndex = _handoffs.indexWhere((handoff) => handoff.id == handoffId);
    if (handoffIndex == -1) return null;

    final handoff = _handoffs[handoffIndex];
    final itemIndex = handoff.items.indexWhere((item) => item.id == itemId);
    if (itemIndex == -1) return null;

    final item = handoff.items[itemIndex];
    final dueDate = _dateOnly(taskDate ?? DateTime.now().add(const Duration(days: 1)));
    final plan = await createPlan(
      projectId: handoff.projectId,
      title: item.text,
      unitType: 'task',
      planKind: StudyPlanKind.singleTask,
      startDate: dueDate,
      weekendsOff: false,
      taskDate: dueDate,
      deadline: dueDate,
    );

    final refreshedIndex = _handoffs.indexWhere((candidate) => candidate.id == handoffId);
    if (refreshedIndex == -1) return plan;
    final refreshed = _handoffs[refreshedIndex];
    final refreshedItemIndex = refreshed.items.indexWhere((candidate) => candidate.id == itemId);
    if (refreshedItemIndex == -1) return plan;

    final now = DateTime.now();
    final items = <SessionHandoffItem>[...refreshed.items];
    items[refreshedItemIndex] = items[refreshedItemIndex].copyWith(
      isDone: true,
      completedAt: now,
      convertedPlanId: plan.id,
    );
    _handoffs[refreshedIndex] = refreshed.copyWith(updatedAt: now, items: items);

    await _save();
    notifyListeners();
    return plan;
  }

  Future<void> completeRequirement(StudyPlanRequirement requirement) async {
    final index = _plans.indexWhere((plan) => plan.id == requirement.plan.id);
    if (index == -1) return;

    final existing = _plans[index];
    if (existing.isRecurring) {
      final nextDates = <String>{...existing.completedDateKeys, _dateKey(requirement.date)};
      _plans[index] = existing.copyWith(
        completedDateKeys: nextDates,
        updatedAt: DateTime.now(),
      );
    } else if (existing.isChecklist) {
      final checklistIndex = requirement.checklistIndex;
      if (checklistIndex == null) return;
      _plans[index] = existing.copyWith(
        completedChecklistIndexes: <int>{...existing.completedChecklistIndexes, checklistIndex},
        updatedAt: DateTime.now(),
      );
    } else if (existing.isSingleTask || existing.isDeadlineMarker) {
      _plans[index] = existing.copyWith(
        completedDateKeys: <String>{...existing.completedDateKeys, StudyPlan.singleCompletionKey},
        updatedAt: DateTime.now(),
      );
    } else {
      final nextCompleted = requirement.endUnit > existing.completedThroughUnit
          ? requirement.endUnit
          : existing.completedThroughUnit;

      // Progress plans are dynamically redistributed from the first available
      // day. Without also recording that this planned occurrence was completed
      // for its date, finishing today's reading can immediately pull tomorrow's
      // allocation into today. The date key prevents that same calendar day from
      // being re-used until the next rollover/recalculation.
      _plans[index] = existing.copyWith(
        completedThroughUnit: nextCompleted.clamp(
          existing.startUnit - 1,
          existing.endUnit,
        ).toInt(),
        completedDateKeys: <String>{
          ...existing.completedDateKeys,
          _dateKey(requirement.date),
        },
        updatedAt: DateTime.now(),
      );
    }

    await _save();
    notifyListeners();
  }

  Future<void> resolveDebt(StudyPlanDebt debt) async {
    final index = _plans.indexWhere((plan) => plan.id == debt.plan.id);
    if (index == -1) return;

    final existing = _plans[index];
    if (existing.isRecurring) {
      final today = _dateOnly(DateTime.now());
      final yesterday = today.subtract(const Duration(days: 1));
      final end = existing.deadline == null || existing.deadline!.isAfter(yesterday)
          ? yesterday
          : existing.deadline!;
      final resolvedDates = end.isBefore(existing.startDate)
          ? const <String>{}
          : _eligibleDays(existing, existing.startDate, end).map(_dateKey).toSet();
      _plans[index] = existing.copyWith(
        completedDateKeys: <String>{...existing.completedDateKeys, ...resolvedDates},
        updatedAt: DateTime.now(),
      );
    } else if (existing.isChecklist) {
      _plans[index] = existing.copyWith(
        completedChecklistIndexes: <int>{...existing.completedChecklistIndexes, ...debt.checklistIndexes},
        updatedAt: DateTime.now(),
      );
    } else if (existing.isSingleTask) {
      _plans[index] = existing.copyWith(
        completedDateKeys: <String>{...existing.completedDateKeys, StudyPlan.singleCompletionKey},
        updatedAt: DateTime.now(),
      );
    } else {
      final nextCompleted = existing.completedThroughUnit + debt.behindUnits;
      _plans[index] = existing.copyWith(
        completedThroughUnit: nextCompleted.clamp(
          existing.startUnit - 1,
          existing.endUnit,
        ).toInt(),
        updatedAt: DateTime.now(),
      );
    }

    await _save();
    notifyListeners();
  }

  Future<void> archiveProject(String projectId) async {
    final index = _projects.indexWhere((project) => project.id == projectId);
    if (index == -1) return;
    _projects[index] = _projects[index].copyWith(
      isArchived: true,
      updatedAt: DateTime.now(),
    );

    for (var i = 0; i < _plans.length; i++) {
      if (_plans[i].projectId == projectId) {
        _plans[i] = _plans[i].copyWith(isArchived: true, updatedAt: DateTime.now());
      }
    }

    for (var i = 0; i < _handoffs.length; i++) {
      if (_handoffs[i].projectId == projectId) {
        _handoffs[i] = _handoffs[i].copyWith(isArchived: true, updatedAt: DateTime.now());
      }
    }

    for (var i = 0; i < _documents.length; i++) {
      if (_documents[i].projectIds.contains(projectId)) {
        final nextProjectIds = _documents[i].projectIds.where((id) => id != projectId).toList(growable: false);
        _documents[i] = _documents[i].copyWith(projectIds: nextProjectIds, updatedAt: DateTime.now());
      }
    }

    _pdfProjectIds.removeWhere((_, linkedProjectId) => linkedProjectId == projectId);

    await _save();
    notifyListeners();
  }



  Future<LibraryFolder> createLibraryFolder({
    required String title,
    String? projectId,
    String? parentId,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Folder title cannot be empty.');
    }

    final cleanProjectId = projectId?.trim();
    final cleanParentId = parentId?.trim();
    final now = DateTime.now();
    final parent = cleanParentId == null || cleanParentId.isEmpty
        ? null
        : libraryFolderById(cleanParentId);
    final resolvedProjectId = parent?.projectId ??
        (cleanProjectId == null || cleanProjectId.isEmpty ? null : cleanProjectId);

    final folder = LibraryFolder(
      id: _uuid.v4(),
      title: cleanTitle,
      projectId: resolvedProjectId,
      parentId: parent?.id,
      createdAt: now,
      updatedAt: now,
    );
    _libraryFolders.add(folder);
    await _save();
    notifyListeners();
    return folder;
  }

  LibraryFolder? libraryFolderById(String id) {
    for (final folder in libraryFolders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  List<LibraryFolder> libraryFoldersForScope({String? projectId, String? parentId}) {
    final cleanProjectId = projectId?.trim();
    final cleanParentId = parentId?.trim();
    final result = libraryFolders.where((folder) {
      final projectMatches = cleanProjectId == null || cleanProjectId.isEmpty
          ? folder.projectId == null || folder.projectId!.isEmpty
          : folder.projectId == cleanProjectId;
      final parentMatches = cleanParentId == null || cleanParentId.isEmpty
          ? folder.parentId == null || folder.parentId!.isEmpty
          : folder.parentId == cleanParentId;
      return projectMatches && parentMatches;
    }).toList();
    result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return result;
  }

  List<LibraryFolder> libraryFolderDescendants(String folderId) {
    final result = <LibraryFolder>[];
    void collect(String parentId) {
      for (final folder in libraryFolders.where((item) => item.parentId == parentId)) {
        result.add(folder);
        collect(folder.id);
      }
    }
    collect(folderId.trim());
    return result;
  }

  String? folderIdForPdf(String documentId) => _pdfFolderIds[documentId.trim()];

  LibraryFolder? folderForPdf(String documentId) {
    final folderId = folderIdForPdf(documentId);
    return folderId == null ? null : libraryFolderById(folderId);
  }

  Future<void> assignPdfToFolder({
    required String documentId,
    required String folderId,
  }) async {
    final cleanDocumentId = documentId.trim();
    final folder = libraryFolderById(folderId.trim());
    if (cleanDocumentId.isEmpty || folder == null) return;

    _pdfFolderIds[cleanDocumentId] = folder.id;
    if (folder.projectId != null && folder.projectId!.isNotEmpty) {
      _pdfProjectIds[cleanDocumentId] = folder.projectId!;
    }
    await _save();
    notifyListeners();
  }

  Future<void> clearPdfFolder(String documentId) async {
    if (_pdfFolderIds.remove(documentId.trim()) == null) return;
    await _save();
    notifyListeners();
  }

  List<String> documentIdsForLibraryFolder(String folderId, {bool includeDescendants = true}) {
    final folderIds = <String>{folderId.trim()};
    if (includeDescendants) {
      folderIds.addAll(libraryFolderDescendants(folderId).map((folder) => folder.id));
    }
    return _pdfFolderIds.entries
        .where((entry) => folderIds.contains(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  Future<void> assignPdfToProject({
    required String documentId,
    required String projectId,
  }) async {
    final cleanDocumentId = documentId.trim();
    final cleanProjectId = projectId.trim();
    if (cleanDocumentId.isEmpty || projectById(cleanProjectId) == null) return;

    _pdfProjectIds[cleanDocumentId] = cleanProjectId;
    await _save();
    notifyListeners();
  }

  Future<void> clearPdfProject(String documentId) async {
    final cleanDocumentId = documentId.trim();
    final removedFolder = _pdfFolderIds.remove(cleanDocumentId) != null;
    final removedProject = _pdfProjectIds.remove(cleanDocumentId) != null;
    if (!removedFolder && !removedProject) return;
    await _save();
    notifyListeners();
  }

  StudyProject? projectForPdf(String documentId) {
    final projectId = _pdfProjectIds[documentId.trim()];
    return projectId == null ? null : projectById(projectId);
  }

  List<String> documentIdsForProject(String projectId) {
    return _pdfProjectIds.entries
        .where((entry) => entry.value == projectId)
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  List<WorkspaceDocument> documentsForProject(String projectId) {
    return documents.where((document) => document.projectIds.contains(projectId)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  WorkspaceDocument? documentById(String id) {
    for (final document in documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  Future<WorkspaceDocument> createDocument({
    required String title,
    required String kind,
    String? body,
    List<String> projectIds = const <String>[],
    List<String> tags = const <String>[],
    String? language,
    String? sourceUrl,
    String? versionLabel,
  }) async {
    final now = DateTime.now();
    final cleanTitle = title.trim().isEmpty ? 'Untitled document' : title.trim();
    final cleanBody = body ?? '';
    final version = DocumentVersion(
      id: _uuid.v4(),
      label: _cleanOptional(versionLabel) ?? 'Initial version',
      body: cleanBody,
      sourceUrl: _cleanOptional(sourceUrl),
      createdAt: now,
    );
    final document = WorkspaceDocument(
      id: _uuid.v4(),
      title: cleanTitle,
      kind: WorkspaceDocumentKind.normalize(kind),
      body: cleanBody,
      tags: _cleanStringList(tags),
      projectIds: _cleanProjectIds(projectIds),
      language: _cleanOptional(language),
      sourceUrl: _cleanOptional(sourceUrl),
      currentVersionId: version.id,
      versions: <DocumentVersion>[version],
      createdAt: now,
      updatedAt: now,
    );
    _documents.add(document);
    await _save();
    notifyListeners();
    return document;
  }

  Future<void> updateDocument({
    required String documentId,
    String? title,
    String? kind,
    String? body,
    List<String>? projectIds,
    List<String>? tags,
    String? language,
    String? sourceUrl,
    bool saveSnapshot = false,
    String? snapshotLabel,
  }) async {
    final index = _documents.indexWhere((document) => document.id == documentId);
    if (index == -1) return;

    final existing = _documents[index];
    final now = DateTime.now();
    final nextBody = body ?? existing.body;
    final nextSourceUrl = sourceUrl == null ? existing.sourceUrl : _cleanOptional(sourceUrl);
    var versions = existing.versions;
    var currentVersionId = existing.currentVersionId;

    if (saveSnapshot) {
      final version = DocumentVersion(
        id: _uuid.v4(),
        label: _cleanOptional(snapshotLabel) ?? 'Snapshot ${versions.length + 1}',
        body: nextBody,
        sourceUrl: nextSourceUrl,
        createdAt: now,
      );
      versions = <DocumentVersion>[...versions, version];
      currentVersionId = version.id;
    }

    _documents[index] = existing.copyWith(
      title: title == null ? null : (title.trim().isEmpty ? existing.title : title.trim()),
      kind: kind == null ? null : WorkspaceDocumentKind.normalize(kind),
      body: nextBody,
      projectIds: projectIds == null ? null : _cleanProjectIds(projectIds),
      tags: tags == null ? null : _cleanStringList(tags),
      language: language == null ? existing.language : _cleanOptional(language),
      sourceUrl: nextSourceUrl,
      currentVersionId: currentVersionId,
      versions: versions,
      updatedAt: now,
    );
    await _save();
    notifyListeners();
  }

  Future<void> archiveDocument(String documentId) async {
    final index = _documents.indexWhere((document) => document.id == documentId);
    if (index == -1) return;
    _documents[index] = _documents[index].copyWith(isArchived: true, updatedAt: DateTime.now());
    await _save();
    notifyListeners();
  }

  Future<DevTodo> createDevTodo({
    required String title,
    String? description,
    String area = 'General',
    String priority = 'Medium',
  }) async {
    final now = DateTime.now();
    final todo = DevTodo(
      id: _uuid.v4(),
      title: title.trim().isEmpty ? 'Untitled dev todo' : title.trim(),
      description: _cleanOptional(description),
      area: _cleanOptional(area) ?? 'General',
      priority: _cleanOptional(priority) ?? 'Medium',
      status: DevTodoStatus.open,
      createdAt: now,
      updatedAt: now,
    );
    _devTodos.add(todo);
    await _save();
    notifyListeners();
    return todo;
  }

  Future<void> updateDevTodo({
    required String todoId,
    String? title,
    String? description,
    String? area,
    String? priority,
    String? status,
  }) async {
    final index = _devTodos.indexWhere((todo) => todo.id == todoId);
    if (index == -1) return;
    final existing = _devTodos[index];
    _devTodos[index] = existing.copyWith(
      title: title == null ? null : (title.trim().isEmpty ? existing.title : title.trim()),
      description: description == null ? existing.description : _cleanOptional(description),
      area: area == null ? null : (_cleanOptional(area) ?? existing.area),
      priority: priority == null ? null : (_cleanOptional(priority) ?? existing.priority),
      status: status == null ? null : DevTodoStatus.normalize(status),
      updatedAt: DateTime.now(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> setDevTodoDone(String todoId, bool isDone) async {
    await updateDevTodo(
      todoId: todoId,
      status: isDone ? DevTodoStatus.done : DevTodoStatus.open,
    );
  }

  Future<void> archiveDevTodo(String todoId) async {
    final index = _devTodos.indexWhere((todo) => todo.id == todoId);
    if (index == -1) return;
    _devTodos[index] = _devTodos[index].copyWith(isArchived: true, updatedAt: DateTime.now());
    await _save();
    notifyListeners();
  }

  Future<void> archivePlan(String planId) async {
    final index = _plans.indexWhere((plan) => plan.id == planId);
    if (index == -1) return;
    _plans[index] = _plans[index].copyWith(
      isArchived: true,
      updatedAt: DateTime.now(),
    );
    await _save();
    notifyListeners();
  }

  StudyProject? projectById(String id) {
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  List<StudyPlan> plansForProject(String projectId) {
    return plans.where((plan) => plan.projectId == projectId).toList()
      ..sort((a, b) {
        final aDeadline = a.deadline ?? a.taskDate ?? DateTime(9999);
        final bDeadline = b.deadline ?? b.taskDate ?? DateTime(9999);
        final deadlineCompare = aDeadline.compareTo(bDeadline);
        if (deadlineCompare != 0) return deadlineCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
  }

  List<StudyPlanRequirement> requirementsForRange({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required DateTime now,
  }) {
    final result = <StudyPlanRequirement>[];
    final start = _dateOnly(rangeStart);
    final end = _dateOnly(rangeEnd);
    final today = _dateOnly(now);

    for (final plan in plans) {
      final project = projectById(plan.projectId);
      if (project == null || plan.isComplete) continue;

      final List<StudyPlanRequirement> allocation;
      if (plan.planKind == StudyPlanKind.recurring) {
        allocation = _recurringAllocation(plan, start, end);
      } else if (plan.planKind == StudyPlanKind.singleTask) {
        allocation = _singleTaskAllocation(plan, start, end);
      } else if (plan.planKind == StudyPlanKind.deadline) {
        allocation = _deadlineAllocation(plan, start, end);
      } else if (plan.planKind == StudyPlanKind.checklist) {
        allocation = _checklistAllocation(plan, start, end, today);
      } else {
        allocation = _dynamicAllocation(plan, today);
      }

      for (final requirement in allocation) {
        if (requirement.date.isBefore(start) || requirement.date.isAfter(end)) {
          continue;
        }
        result.add(requirement.withProject(project));
      }
    }

    result.sort((a, b) {
      final dateCompare = a.sortAt.compareTo(b.sortAt);
      if (dateCompare != 0) return dateCompare;
      if (a.isDeadlineMarker != b.isDeadlineMarker) return a.isDeadlineMarker ? 1 : -1;
      final projectCompare = a.projectTitle.toLowerCase().compareTo(
        b.projectTitle.toLowerCase(),
      );
      if (projectCompare != 0) return projectCompare;
      return a.plan.title.toLowerCase().compareTo(b.plan.title.toLowerCase());
    });
    return result;
  }

  List<StudyPlanDebt> studyDebts(DateTime now) {
    final today = _dateOnly(now);
    final result = <StudyPlanDebt>[];

    for (final plan in plans) {
      final project = projectById(plan.projectId);
      if (project == null || plan.isComplete) continue;

      if (plan.isRecurring) {
        final yesterday = today.subtract(const Duration(days: 1));
        if (yesterday.isBefore(plan.startDate)) continue;
        final end = plan.deadline == null || plan.deadline!.isAfter(yesterday)
            ? yesterday
            : plan.deadline!;
        final missedDays = _eligibleDays(plan, plan.startDate, end)
            .where((date) => !plan.completedDateKeys.contains(_dateKey(date)))
            .length;
        if (missedDays <= 0) continue;
        result.add(
          StudyPlanDebt(
            project: project,
            plan: plan,
            behindUnits: missedDays * plan.dailyTargetValue,
            originalPace: plan.dailyTargetValue.toDouble(),
            currentPace: plan.dailyTargetValue.toDouble(),
            isPastDeadline: plan.deadline != null && today.isAfter(plan.deadline!),
            missedDays: missedDays,
          ),
        );
        continue;
      }

      if (plan.isSingleTask) {
        final date = plan.taskDate ?? plan.startDate;
        if (_dateOnly(date).isBefore(today) && !plan.isComplete) {
          result.add(
            StudyPlanDebt(
              project: project,
              plan: plan,
              behindUnits: 1,
              originalPace: 1,
              currentPace: 1,
              isPastDeadline: true,
            ),
          );
        }
        continue;
      }

      if (plan.isDeadlineMarker) {
        continue;
      }

      if (plan.isChecklist) {
        final expectedIndexes = _expectedChecklistIndexes(plan, today.subtract(const Duration(days: 1)));
        final behindIndexes = expectedIndexes
            .where((index) => !plan.completedChecklistIndexes.contains(index))
            .toList(growable: false);
        if (behindIndexes.isEmpty) continue;
        result.add(
          StudyPlanDebt(
            project: project,
            plan: plan,
            behindUnits: behindIndexes.length,
            originalPace: _originalChecklistPace(plan),
            currentPace: _currentChecklistPace(plan, today),
            isPastDeadline: plan.deadline != null && today.isAfter(plan.deadline!),
            checklistIndexes: behindIndexes,
          ),
        );
        continue;
      }

      final expectedThroughYesterday = _expectedThroughDate(
        plan,
        today.subtract(const Duration(days: 1)),
      );
      final behindUnits = expectedThroughYesterday - plan.completedThroughUnit;
      final isPastDeadline = plan.deadline != null && today.isAfter(plan.deadline!);
      final overdueUnits = isPastDeadline ? plan.remainingUnits : 0;

      if (behindUnits <= 0 && overdueUnits <= 0) continue;

      final currentPace = _currentPace(plan, today);
      final originalPace = _originalPace(plan);

      result.add(
        StudyPlanDebt(
          project: project,
          plan: plan,
          behindUnits: behindUnits > 0 ? behindUnits : overdueUnits,
          originalPace: originalPace,
          currentPace: currentPace,
          isPastDeadline: isPastDeadline,
        ),
      );
    }

    result.sort((a, b) {
      if (a.isPastDeadline != b.isPastDeadline) return a.isPastDeadline ? -1 : 1;
      final aDeadline = a.plan.deadline ?? a.plan.taskDate ?? DateTime(9999);
      final bDeadline = b.plan.deadline ?? b.plan.taskDate ?? DateTime(9999);
      final deadlineCompare = aDeadline.compareTo(bDeadline);
      if (deadlineCompare != 0) return deadlineCompare;
      return b.behindUnits.compareTo(a.behindUnits);
    });

    return result;
  }

  Future<void> _save() async {
    final file = _storageFile;
    if (file == null) return;

    final data = jsonEncode({
      'projects': _projects.map((project) => project.toJson()).toList(),
      'plans': _plans.map((plan) => plan.toJson()).toList(),
      'sessionHandoffs': _handoffs.map((handoff) => handoff.toJson()).toList(),
      'workspaceDocuments': _documents.map((document) => document.toJson()).toList(),
      'devTodos': _devTodos.map((todo) => todo.toJson()).toList(),
      'planningEntries': _planningEntries.map((entry) => entry.toJson()).toList(),
      'todayPlans': _todayPlans.map((plan) => plan.toJson()).toList(),
      'pdfProjectIds': _pdfProjectIds,
      'libraryFolders': _libraryFolders.map((folder) => folder.toJson()).toList(),
      'pdfFolderIds': _pdfFolderIds,
    });
    await file.writeAsString(data);
  }

  List<StudyPlanRequirement> _dynamicAllocation(StudyPlan plan, DateTime today) {
    final remaining = plan.remainingUnits;
    if (remaining <= 0) return const <StudyPlanRequirement>[];

    final deadline = plan.deadline ?? today;
    final baseFirstDate = today.isAfter(plan.startDate) ? today : plan.startDate;
    var firstDate = baseFirstDate;
    while (!firstDate.isAfter(deadline) && plan.completedDateKeys.contains(_dateKey(firstDate))) {
      firstDate = firstDate.add(const Duration(days: 1));
    }

    final days = _eligibleDays(plan, firstDate, deadline)
        .where((date) => !plan.completedDateKeys.contains(_dateKey(date)))
        .toList(growable: false);
    if (days.isEmpty) {
      if (plan.completedDateKeys.contains(_dateKey(today))) {
        return const <StudyPlanRequirement>[];
      }
      return <StudyPlanRequirement>[
        StudyPlanRequirement(
          project: null,
          plan: plan,
          date: today,
          startUnit: plan.completedThroughUnit + 1,
          endUnit: plan.endUnit,
        ),
      ];
    }

    return _allocateUnits(plan, days, plan.completedThroughUnit + 1, plan.endUnit);
  }

  List<StudyPlanRequirement> _recurringAllocation(
    StudyPlan plan,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final effectiveStart = rangeStart.isAfter(plan.startDate) ? rangeStart : plan.startDate;
    final effectiveEnd = plan.deadline == null || rangeEnd.isBefore(plan.deadline!)
        ? rangeEnd
        : plan.deadline!;
    if (effectiveEnd.isBefore(effectiveStart)) return const <StudyPlanRequirement>[];

    return _eligibleDays(plan, effectiveStart, effectiveEnd)
        .where((date) => !plan.completedDateKeys.contains(_dateKey(date)))
        .map(
          (date) => StudyPlanRequirement(
            project: null,
            plan: plan,
            date: date,
            startUnit: 1,
            endUnit: plan.dailyTargetValue,
          ),
        )
        .toList();
  }

  List<StudyPlanRequirement> _singleTaskAllocation(
    StudyPlan plan,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final date = plan.taskDate ?? plan.startDate;
    if (date.isBefore(rangeStart) || date.isAfter(rangeEnd)) return const <StudyPlanRequirement>[];
    return <StudyPlanRequirement>[
      StudyPlanRequirement(
        project: null,
        plan: plan,
        date: date,
        startUnit: 1,
        endUnit: 1,
      ),
    ];
  }

  List<StudyPlanRequirement> _deadlineAllocation(
    StudyPlan plan,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final date = plan.deadline ?? plan.taskDate ?? plan.startDate;
    if (date.isBefore(rangeStart) || date.isAfter(rangeEnd)) return const <StudyPlanRequirement>[];
    return <StudyPlanRequirement>[
      StudyPlanRequirement(
        project: null,
        plan: plan,
        date: date,
        startUnit: 1,
        endUnit: 1,
      ),
    ];
  }

  List<StudyPlanRequirement> _checklistAllocation(
    StudyPlan plan,
    DateTime rangeStart,
    DateTime rangeEnd,
    DateTime today,
  ) {
    final items = plan.checklistItems;
    if (items.isEmpty) return const <StudyPlanRequirement>[];
    final deadline = plan.deadline ?? rangeEnd;
    final firstDate = today.isAfter(plan.startDate) ? today : plan.startDate;
    final effectiveStart = rangeStart.isAfter(firstDate) ? rangeStart : firstDate;
    final effectiveEnd = rangeEnd.isBefore(deadline) ? rangeEnd : deadline;
    if (effectiveEnd.isBefore(effectiveStart)) return const <StudyPlanRequirement>[];

    final remainingIndexes = <int>[
      for (var i = 0; i < items.length; i++)
        if (!plan.completedChecklistIndexes.contains(i)) i,
    ];
    if (remainingIndexes.isEmpty) return const <StudyPlanRequirement>[];

    final allDays = _eligibleDays(plan, firstDate, deadline);
    if (allDays.isEmpty) {
      return <StudyPlanRequirement>[
        for (final index in remainingIndexes)
          StudyPlanRequirement(
            project: null,
            plan: plan,
            date: today,
            startUnit: index + 1,
            endUnit: index + 1,
            checklistIndex: index,
          ),
      ];
    }

    final allocation = <StudyPlanRequirement>[];
    for (var i = 0; i < remainingIndexes.length; i++) {
      final date = allDays[(i * allDays.length) ~/ remainingIndexes.length];
      final index = remainingIndexes[i];
      if (date.isBefore(effectiveStart) || date.isAfter(effectiveEnd)) continue;
      allocation.add(
        StudyPlanRequirement(
          project: null,
          plan: plan,
          date: date,
          startUnit: index + 1,
          endUnit: index + 1,
          checklistIndex: index,
        ),
      );
    }
    return allocation;
  }

  int _expectedThroughDate(StudyPlan plan, DateTime date) {
    if (date.isBefore(plan.startDate)) return plan.startUnit - 1;
    final deadline = plan.deadline;
    if (deadline == null) return plan.completedThroughUnit;
    if (!date.isBefore(deadline)) return plan.endUnit;

    final days = _eligibleDays(plan, plan.startDate, deadline);
    if (days.isEmpty) return plan.startUnit - 1;

    final allocation = _allocateUnits(plan, days, plan.startUnit, plan.endUnit);
    var completed = plan.startUnit - 1;
    for (final requirement in allocation) {
      if (!requirement.date.isAfter(date)) {
        completed = requirement.endUnit;
      }
    }
    return completed;
  }

  List<int> _expectedChecklistIndexes(StudyPlan plan, DateTime date) {
    if (date.isBefore(plan.startDate) || plan.checklistItems.isEmpty) return const <int>[];
    final deadline = plan.deadline;
    if (deadline != null && !date.isBefore(deadline)) {
      return [for (var i = 0; i < plan.checklistItems.length; i++) i];
    }

    final end = deadline ?? date;
    final days = _eligibleDays(plan, plan.startDate, end);
    if (days.isEmpty) return const <int>[];

    final indexes = <int>[];
    for (var i = 0; i < plan.checklistItems.length; i++) {
      final allocatedDate = days[(i * days.length) ~/ plan.checklistItems.length];
      if (!allocatedDate.isAfter(date)) indexes.add(i);
    }
    return indexes;
  }

  double _originalPace(StudyPlan plan) {
    final deadline = plan.deadline;
    if (deadline == null) return plan.totalUnits.toDouble();
    final days = _eligibleDays(plan, plan.startDate, deadline);
    if (days.isEmpty) return plan.totalUnits.toDouble();
    return plan.totalUnits / days.length;
  }

  double _currentPace(StudyPlan plan, DateTime today) {
    final deadline = plan.deadline;
    if (deadline == null) return plan.remainingUnits.toDouble();
    final firstDate = today.isAfter(plan.startDate) ? today : plan.startDate;
    final days = _eligibleDays(plan, firstDate, deadline);
    if (days.isEmpty) return plan.remainingUnits.toDouble();
    return plan.remainingUnits / days.length;
  }

  double _originalChecklistPace(StudyPlan plan) {
    final deadline = plan.deadline;
    if (deadline == null) return plan.checklistItems.length.toDouble();
    final days = _eligibleDays(plan, plan.startDate, deadline);
    if (days.isEmpty) return plan.checklistItems.length.toDouble();
    return plan.checklistItems.length / days.length;
  }

  double _currentChecklistPace(StudyPlan plan, DateTime today) {
    final deadline = plan.deadline;
    if (deadline == null) return plan.remainingChecklistCount.toDouble();
    final firstDate = today.isAfter(plan.startDate) ? today : plan.startDate;
    final days = _eligibleDays(plan, firstDate, deadline);
    if (days.isEmpty) return plan.remainingChecklistCount.toDouble();
    return plan.remainingChecklistCount / days.length;
  }

  List<StudyPlanRequirement> _allocateUnits(
    StudyPlan plan,
    List<DateTime> days,
    int firstUnit,
    int lastUnit,
  ) {
    final total = lastUnit - firstUnit + 1;
    if (total <= 0 || days.isEmpty) return const <StudyPlanRequirement>[];

    final base = total ~/ days.length;
    final remainder = total % days.length;
    var cursor = firstUnit;
    final requirements = <StudyPlanRequirement>[];

    for (var i = 0; i < days.length; i++) {
      final amount = base + (i < remainder ? 1 : 0);
      if (amount <= 0) continue;
      final end = cursor + amount - 1;
      requirements.add(
        StudyPlanRequirement(
          project: null,
          plan: plan,
          date: days[i],
          startUnit: cursor,
          endUnit: end,
        ),
      );
      cursor = end + 1;
      if (cursor > lastUnit) break;
    }

    return requirements;
  }

  List<DateTime> _eligibleDays(StudyPlan plan, DateTime start, DateTime end) {
    final result = <DateTime>[];
    var cursor = _dateOnly(start);
    final last = _dateOnly(end);

    while (!cursor.isAfter(last)) {
      final isWeekend = cursor.weekday == DateTime.saturday ||
          cursor.weekday == DateTime.sunday;
      if (!plan.weekendsOff || !isWeekend) {
        result.add(cursor);
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    return result;
  }
}



int? _normalizeMinuteOfDay(int? value) {
  if (value == null) return null;
  if (value < 0 || value > 23 * 60 + 59) return null;
  return value;
}

String _formatMinuteOfDay(int value) {
  final minutes = value.clamp(0, 23 * 60 + 59).toInt();
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class PlanningEntryKind {
  static const String task = 'task';
  static const String deadline = 'deadline';
  static const String event = 'event';
  static const String reminder = 'reminder';

  static const List<String> values = <String>[task, deadline, event, reminder];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return task;
  }

  static String label(String value) {
    switch (normalize(value)) {
      case deadline:
        return 'Deadline';
      case event:
        return 'Event';
      case reminder:
        return 'Reminder';
      case task:
      default:
        return 'Task';
    }
  }
}

class PlanningEntryStatus {
  static const String open = 'open';
  static const String done = 'done';
  static const String archived = 'archived';

  static const List<String> values = <String>[open, done, archived];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return open;
  }
}

class PlanningEntryPriority {
  static const String low = 'low';
  static const String normal = 'normal';
  static const String high = 'high';

  static const List<String> values = <String>[low, normal, high];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return normal;
  }

  static int rank(String value) {
    switch (normalize(value)) {
      case high:
        return 3;
      case normal:
        return 2;
      case low:
        return 1;
      default:
        return 2;
    }
  }

  static String label(String value) {
    switch (normalize(value)) {
      case high:
        return 'High';
      case low:
        return 'Low';
      case normal:
      default:
        return 'Normal';
    }
  }
}

class PlanningEntry {
  final String id;
  final String title;
  final String? notes;
  final String kind;
  final String priority;
  final String status;
  final String? projectId;
  final DateTime? date;
  final DateTime? dueAt;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool allDay;
  final int? estimateMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final bool isArchived;

  const PlanningEntry({
    required this.id,
    required this.title,
    this.notes,
    required this.kind,
    required this.priority,
    required this.status,
    this.projectId,
    this.date,
    this.dueAt,
    this.startAt,
    this.endAt,
    this.allDay = true,
    this.estimateMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.isArchived = false,
  });

  bool get isDone => status == PlanningEntryStatus.done;
  bool get isDeadline => kind == PlanningEntryKind.deadline;
  bool get isEvent => kind == PlanningEntryKind.event;
  DateTime? get calendarDate => startAt ?? dueAt ?? date;
  bool get isInbox => calendarDate == null && !isDone && !isArchived;

  factory PlanningEntry.fromJson(Map<String, dynamic> json) {
    return PlanningEntry(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Untitled planning item',
      notes: _readString(json['notes']),
      kind: PlanningEntryKind.normalize(_readString(json['kind'])),
      priority: PlanningEntryPriority.normalize(_readString(json['priority'])),
      status: PlanningEntryStatus.normalize(_readString(json['status'])),
      projectId: _readString(json['projectId']),
      date: _readDate(json['date']),
      dueAt: _readDateTime(json['dueAt']),
      startAt: _readDateTime(json['startAt']),
      endAt: _readDateTime(json['endAt']),
      allDay: _readBool(json['allDay']) ?? true,
      estimateMinutes: _readInt(json['estimateMinutes']),
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updatedAt']) ?? DateTime.now(),
      completedAt: _readDateTime(json['completedAt']),
      isArchived: _readBool(json['isArchived']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'notes': notes,
      'kind': kind,
      'priority': priority,
      'status': status,
      'projectId': projectId,
      'date': date?.toIso8601String(),
      'dueAt': dueAt?.toIso8601String(),
      'startAt': startAt?.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
      'allDay': allDay,
      'estimateMinutes': estimateMinutes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'isArchived': isArchived,
    };
  }

  PlanningEntry copyWith({
    String? title,
    Object? notes = _sentinel,
    String? kind,
    String? priority,
    String? status,
    Object? projectId = _sentinel,
    Object? date = _sentinel,
    Object? dueAt = _sentinel,
    Object? startAt = _sentinel,
    Object? endAt = _sentinel,
    bool? allDay,
    Object? estimateMinutes = _sentinel,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? isArchived,
  }) {
    DateTime? readDateObject(Object? value, DateTime? fallback) {
      if (identical(value, _sentinel)) return fallback;
      if (value == null) return null;
      if (value is DateTime) return _dateOnly(value);
      return fallback;
    }

    DateTime? readDateTimeObject(Object? value, DateTime? fallback) {
      if (identical(value, _sentinel)) return fallback;
      if (value == null) return null;
      if (value is DateTime) return value;
      return fallback;
    }

    int? readIntObject(Object? value, int? fallback) {
      if (identical(value, _sentinel)) return fallback;
      if (value == null) return null;
      if (value is int) return value <= 0 ? null : value;
      return fallback;
    }

    return PlanningEntry(
      id: id,
      title: title ?? this.title,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
      kind: kind ?? this.kind,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      projectId: identical(projectId, _sentinel) ? this.projectId : projectId as String?,
      date: readDateObject(date, this.date),
      dueAt: readDateTimeObject(dueAt, this.dueAt),
      startAt: readDateTimeObject(startAt, this.startAt),
      endAt: readDateTimeObject(endAt, this.endAt),
      allDay: allDay ?? this.allDay,
      estimateMinutes: readIntObject(estimateMinutes, this.estimateMinutes),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  static int compareForCalendar(PlanningEntry a, PlanningEntry b) {
    final aDate = a.calendarDate;
    final bDate = b.calendarDate;
    if (aDate != null && bDate != null) {
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) return dateCompare;
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }
    final kindCompare = (a.isDeadline ? 0 : a.isEvent ? 1 : 2).compareTo(b.isDeadline ? 0 : b.isEvent ? 1 : 2);
    if (kindCompare != 0) return kindCompare;
    final priorityCompare = PlanningEntryPriority.rank(b.priority).compareTo(PlanningEntryPriority.rank(a.priority));
    if (priorityCompare != 0) return priorityCompare;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
}

class TodayPlanSnapshot {
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TodayPlanItem> items;

  const TodayPlanSnapshot({
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  factory TodayPlanSnapshot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return TodayPlanSnapshot(
      date: _readDate(json['date']) ?? DateTime.now(),
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updatedAt']) ?? DateTime.now(),
      items: rawItems is List
          ? rawItems.whereType<Map>().map((item) => TodayPlanItem.fromJson(_stringMap(item))).toList(growable: false)
          : const <TodayPlanItem>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class TodayPlanItem {
  final String id;
  final String title;
  final String? detail;
  final String reason;
  final String kind;
  final String priority;
  final bool included;
  final bool manual;
  final String? sourceLabel;

  const TodayPlanItem({
    required this.id,
    required this.title,
    this.detail,
    required this.reason,
    required this.kind,
    required this.priority,
    required this.included,
    required this.manual,
    this.sourceLabel,
  });

  factory TodayPlanItem.fromJson(Map<String, dynamic> json) {
    return TodayPlanItem(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Untitled item',
      detail: _readString(json['detail']),
      reason: _readString(json['reason']) ?? 'Saved in today plan',
      kind: _readString(json['kind']) ?? 'manualReminder',
      priority: _readString(json['priority']) ?? 'should',
      included: _readBool(json['included']) ?? true,
      manual: _readBool(json['manual']) ?? false,
      sourceLabel: _readString(json['sourceLabel']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'detail': detail,
      'reason': reason,
      'kind': kind,
      'priority': priority,
      'included': included,
      'manual': manual,
      'sourceLabel': sourceLabel,
    };
  }
}

class StudyPlanKind {
  static const String progress = 'progress';
  static const String recurring = 'recurring';
  static const String singleTask = 'singleTask';
  static const String deadline = 'deadline';
  static const String checklist = 'checklist';

  static const List<String> values = <String>[
    progress,
    recurring,
    singleTask,
    deadline,
    checklist,
  ];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return progress;
  }

  static String label(String value) {
    switch (value) {
      case recurring:
        return 'Build a routine';
      case singleTask:
        return 'Add one task';
      case deadline:
        return 'Mark a deadline';
      case checklist:
        return 'Checklist / topics';
      case progress:
      default:
        return 'Finish work by a date';
    }
  }
}


class LibraryFolder {
  final String id;
  final String title;
  final String? projectId;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;

  const LibraryFolder({
    required this.id,
    required this.title,
    required this.projectId,
    required this.parentId,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
  });

  factory LibraryFolder.fromJson(Map<String, dynamic> json) {
    return LibraryFolder(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Untitled folder',
      projectId: _readString(json['projectId']),
      parentId: _readString(json['parentId']),
      createdAt: _readDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDate(json['updatedAt']) ?? DateTime.now(),
      isArchived: _readBool(json['isArchived']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'projectId': projectId,
      'parentId': parentId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isArchived': isArchived,
    };
  }

  LibraryFolder copyWith({
    String? title,
    String? projectId,
    String? parentId,
    DateTime? updatedAt,
    bool? isArchived,
  }) {
    return LibraryFolder(
      id: id,
      title: title ?? this.title,
      projectId: projectId ?? this.projectId,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

class StudyProject {
  final String id;
  final String title;
  final String type;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deadline;
  final bool isArchived;

  const StudyProject({
    required this.id,
    required this.title,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    required this.deadline,
    this.isArchived = false,
  });

  factory StudyProject.fromJson(Map<String, dynamic> json) {
    return StudyProject(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Untitled project',
      type: _readString(json['type']) ?? 'Project',
      createdAt: _readDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDate(json['updatedAt']) ?? DateTime.now(),
      deadline: _readDate(json['deadline']),
      isArchived: _readBool(json['isArchived']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deadline': deadline?.toIso8601String(),
      'isArchived': isArchived,
    };
  }

  StudyProject copyWith({
    String? title,
    String? type,
    DateTime? updatedAt,
    DateTime? deadline,
    bool? isArchived,
  }) {
    return StudyProject(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deadline: deadline ?? this.deadline,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

class StudyPlan {
  static const String singleCompletionKey = 'done';

  final String id;
  final String projectId;
  final String title;
  final String planKind;
  final String unitType;
  final String? customUnitSingular;
  final String? customUnitPlural;
  final String? customUnitLabel;
  final StudyMaterialSource? materialSource;
  final int startUnit;
  final int endUnit;
  final int completedThroughUnit;
  final int? dailyTarget;
  final int? timeStartMinutes;
  final int? timeEndMinutes;
  final Set<String> completedDateKeys;
  final List<String> checklistItems;
  final Set<int> completedChecklistIndexes;
  final DateTime startDate;
  final DateTime? deadline;
  final DateTime? taskDate;
  final bool weekendsOff;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;

  const StudyPlan({
    required this.id,
    required this.projectId,
    required this.title,
    this.planKind = StudyPlanKind.progress,
    required this.unitType,
    this.customUnitSingular,
    this.customUnitPlural,
    this.customUnitLabel,
    this.materialSource,
    required this.startUnit,
    required this.endUnit,
    required this.completedThroughUnit,
    this.dailyTarget,
    this.timeStartMinutes,
    this.timeEndMinutes,
    this.completedDateKeys = const <String>{},
    this.checklistItems = const <String>[],
    this.completedChecklistIndexes = const <int>{},
    required this.startDate,
    required this.deadline,
    this.taskDate,
    required this.weekendsOff,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
  });

  bool get isRecurring => planKind == StudyPlanKind.recurring;
  bool get isRunning => isRecurring && deadline == null;
  bool get isSingleTask => planKind == StudyPlanKind.singleTask;
  bool get isDeadlineMarker => planKind == StudyPlanKind.deadline;
  bool get isChecklist => planKind == StudyPlanKind.checklist;
  bool get isTimeBased => unitType == 'minutes' || unitType == 'time';
  bool get hasTimeWindow => timeStartMinutes != null && timeEndMinutes != null && timeEndMinutes! > timeStartMinutes!;
  int get dailyTargetValue => dailyTarget == null || dailyTarget! < 1 ? 1 : dailyTarget!;
  int get totalUnits => isRecurring
      ? dailyTargetValue
      : isChecklist
          ? checklistItems.length
          : isSingleTask || isDeadlineMarker
              ? 1
              : endUnit - startUnit + 1;
  int get remainingChecklistCount => isChecklist
      ? (checklistItems.length - completedChecklistIndexes.length).clamp(0, checklistItems.length).toInt()
      : 0;
  int get remainingUnits => isRecurring
      ? dailyTargetValue
      : isChecklist
          ? remainingChecklistCount
          : isSingleTask || isDeadlineMarker
              ? (completedDateKeys.contains(singleCompletionKey) ? 0 : 1)
              : (endUnit - completedThroughUnit).clamp(0, totalUnits).toInt();
  bool get isComplete {
    if (isRecurring) return false;
    if (isChecklist) return checklistItems.isNotEmpty && completedChecklistIndexes.length >= checklistItems.length;
    if (isSingleTask || isDeadlineMarker) return completedDateKeys.contains(singleCompletionKey);
    return completedThroughUnit >= endUnit;
  }
  double get progress {
    if (isRecurring || totalUnits <= 0) return 0;
    if (isChecklist) return completedChecklistIndexes.length.clamp(0, totalUnits).toDouble() / totalUnits;
    if (isSingleTask || isDeadlineMarker) return isComplete ? 1 : 0;
    return (completedThroughUnit - startUnit + 1).clamp(0, totalUnits).toDouble() / totalUnits;
  }

  String get unitLabel {
    final customLabel = customUnitLabel?.trim();
    if (unitType == 'custom' && customLabel != null && customLabel.isNotEmpty) {
      return customLabel;
    }

    switch (unitType) {
      case 'pages':
        return 'pp.';
      case 'chapters':
        return 'ch.';
      case 'sections':
        return 'sec.';
      case 'exercises':
        return 'ex.';
      case 'task':
        return 'task';
      case 'deadline':
        return 'deadline';
      case 'topic':
        return 'topic';
      case 'minutes':
      case 'time':
        return 'min';
      default:
        return customUnitSingular?.trim().isNotEmpty == true
            ? customUnitSingular!.trim()
            : 'unit';
    }
  }

  String get unitNoun => unitNounForCount(2);

  String unitNounForCount(int count) {
    if (unitType == 'custom') {
      if (count == 1 && customUnitSingular?.trim().isNotEmpty == true) {
        return customUnitSingular!.trim();
      }
      if (customUnitPlural?.trim().isNotEmpty == true) {
        return customUnitPlural!.trim();
      }
    }

    switch (unitType) {
      case 'pages':
        return count == 1 ? 'page' : 'pages';
      case 'chapters':
        return count == 1 ? 'chapter' : 'chapters';
      case 'sections':
        return count == 1 ? 'section' : 'sections';
      case 'exercises':
        return count == 1 ? 'exercise' : 'exercises';
      case 'task':
        return count == 1 ? 'task' : 'tasks';
      case 'deadline':
        return count == 1 ? 'deadline' : 'deadlines';
      case 'topic':
        return count == 1 ? 'topic' : 'topics';
      case 'minutes':
      case 'time':
        return count == 1 ? 'minute' : 'minutes';
      default:
        return count == 1 ? 'unit' : 'units';
    }
  }


  String get timeAmountLabel {
    final minutes = dailyTargetValue;
    if (!isTimeBased) return '$minutes ${unitNounForCount(minutes)}';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours > 0 && remainder > 0) return '${hours}h ${remainder}m';
    if (hours > 0) return hours == 1 ? '1 hour' : '$hours hours';
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  String? get timeWindowLabel {
    if (!hasTimeWindow) return null;
    return '${_formatMinuteOfDay(timeStartMinutes!)}–${_formatMinuteOfDay(timeEndMinutes!)}';
  }

  DateTime dateWithStartTime(DateTime date) {
    final start = timeStartMinutes;
    if (start == null) return date;
    return DateTime(date.year, date.month, date.day, start ~/ 60, start % 60);
  }

  factory StudyPlan.fromJson(Map<String, dynamic> json) {
    final startUnit = _readInt(json['startUnit']) ?? 1;
    final endUnit = _readInt(json['endUnit']) ?? startUnit;
    final kind = StudyPlanKind.normalize(_readString(json['planKind']));
    final completedDates = json['completedDateKeys'];
    final rawChecklist = json['checklistItems'];
    final rawCompletedIndexes = json['completedChecklistIndexes'];
    final rawMaterialSource = json['materialSource'];
    return StudyPlan(
      id: _readString(json['id']) ?? '',
      projectId: _readString(json['projectId']) ?? '',
      title: _readString(json['title']) ?? 'Untitled plan',
      planKind: kind,
      unitType: _readString(json['unitType']) ?? 'pages',
      customUnitSingular: _readString(json['customUnitSingular']),
      customUnitPlural: _readString(json['customUnitPlural']),
      customUnitLabel: _readString(json['customUnitLabel']),
      materialSource: rawMaterialSource is Map
          ? StudyMaterialSource.fromJson(_stringMap(rawMaterialSource))
          : null,
      startUnit: startUnit,
      endUnit: kind == StudyPlanKind.progress ? endUnit : 0,
      completedThroughUnit: _readInt(json['completedThroughUnit']) ?? startUnit - 1,
      dailyTarget: _readInt(json['dailyTarget']),
      timeStartMinutes: _readInt(json['timeStartMinutes']),
      timeEndMinutes: _readInt(json['timeEndMinutes']),
      completedDateKeys: completedDates is List
          ? completedDates.map((value) => value.toString()).toSet()
          : const <String>{},
      checklistItems: rawChecklist is List
          ? rawChecklist.map((value) => value.toString()).where((value) => value.trim().isNotEmpty).toList()
          : const <String>[],
      completedChecklistIndexes: rawCompletedIndexes is List
          ? rawCompletedIndexes.map(_readInt).whereType<int>().toSet()
          : const <int>{},
      startDate: _readDate(json['startDate']) ?? DateTime.now(),
      deadline: _readDate(json['deadline']),
      taskDate: _readDate(json['taskDate']),
      weekendsOff: _readBool(json['weekendsOff']) ?? false,
      createdAt: _readDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDate(json['updatedAt']) ?? DateTime.now(),
      isArchived: _readBool(json['isArchived']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'title': title,
      'planKind': planKind,
      'unitType': unitType,
      'customUnitSingular': customUnitSingular,
      'customUnitPlural': customUnitPlural,
      'customUnitLabel': customUnitLabel,
      'materialSource': materialSource?.toJson(),
      'startUnit': startUnit,
      'endUnit': endUnit,
      'completedThroughUnit': completedThroughUnit,
      'dailyTarget': dailyTarget,
      'timeStartMinutes': timeStartMinutes,
      'timeEndMinutes': timeEndMinutes,
      'completedDateKeys': completedDateKeys.toList()..sort(),
      'checklistItems': checklistItems,
      'completedChecklistIndexes': completedChecklistIndexes.toList()..sort(),
      'startDate': startDate.toIso8601String(),
      'deadline': deadline?.toIso8601String(),
      'taskDate': taskDate?.toIso8601String(),
      'weekendsOff': weekendsOff,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isArchived': isArchived,
    };
  }

  StudyPlan copyWith({
    String? title,
    int? completedThroughUnit,
    int? dailyTarget,
    Set<String>? completedDateKeys,
    List<String>? checklistItems,
    Set<int>? completedChecklistIndexes,
    DateTime? updatedAt,
    bool? isArchived,
  }) {
    return StudyPlan(
      id: id,
      projectId: projectId,
      title: title ?? this.title,
      planKind: planKind,
      unitType: unitType,
      customUnitSingular: customUnitSingular,
      customUnitPlural: customUnitPlural,
      customUnitLabel: customUnitLabel,
      materialSource: materialSource,
      startUnit: startUnit,
      endUnit: endUnit,
      completedThroughUnit: completedThroughUnit ?? this.completedThroughUnit,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      timeStartMinutes: this.timeStartMinutes,
      timeEndMinutes: this.timeEndMinutes,
      completedDateKeys: completedDateKeys ?? this.completedDateKeys,
      checklistItems: checklistItems ?? this.checklistItems,
      completedChecklistIndexes: completedChecklistIndexes ?? this.completedChecklistIndexes,
      startDate: startDate,
      deadline: deadline,
      taskDate: taskDate,
      weekendsOff: weekendsOff,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

class StudyPlanRequirement {
  final StudyProject? project;
  final StudyPlan plan;
  final DateTime date;
  final int startUnit;
  final int endUnit;
  final int? checklistIndex;

  const StudyPlanRequirement({
    required this.project,
    required this.plan,
    required this.date,
    required this.startUnit,
    required this.endUnit,
    this.checklistIndex,
  });

  String get projectTitle => project?.title ?? 'Study plan';
  bool get isDeadlineMarker => plan.isDeadlineMarker;
  bool get isSingleTask => plan.isSingleTask;
  bool get isChecklistItem => plan.isChecklist;
  String? get timeLabel => plan.timeWindowLabel;
  DateTime get sortAt => plan.dateWithStartTime(date);

  String get rangeLabel {
    if (plan.isDeadlineMarker) return 'deadline';
    if (plan.isSingleTask) return 'task';
    if (plan.isChecklist) {
      final index = checklistIndex;
      if (index != null && index >= 0 && index < plan.checklistItems.length) {
        return plan.checklistItems[index];
      }
      return 'Checklist item';
    }
    if (plan.isRecurring) {
      if (plan.isTimeBased) return plan.timeAmountLabel;
      return '$unitCount ${plan.unitNounForCount(unitCount)}';
    }
    if (startUnit == endUnit) return '${plan.unitLabel} $startUnit';
    return '${plan.unitLabel} $startUnit–$endUnit';
  }

  int get unitCount => plan.isChecklist || plan.isSingleTask || plan.isDeadlineMarker
      ? 1
      : endUnit - startUnit + 1;

  StudyPlanRequirement withProject(StudyProject project) {
    return StudyPlanRequirement(
      project: project,
      plan: plan,
      date: date,
      startUnit: startUnit,
      endUnit: endUnit,
      checklistIndex: checklistIndex,
    );
  }
}

class StudyPlanDebt {
  final StudyProject project;
  final StudyPlan plan;
  final int behindUnits;
  final double originalPace;
  final double currentPace;
  final bool isPastDeadline;
  final int missedDays;
  final List<int> checklistIndexes;

  const StudyPlanDebt({
    required this.project,
    required this.plan,
    required this.behindUnits,
    required this.originalPace,
    required this.currentPace,
    required this.isPastDeadline,
    this.missedDays = 0,
    this.checklistIndexes = const <int>[],
  });
}

class SessionHandoff {
  final String id;
  final String projectId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SessionHandoffItem> items;
  final bool isArchived;

  const SessionHandoff({
    required this.id,
    required this.projectId,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.isArchived = false,
  });

  bool get hasOpenItems => items.any((item) => !item.isDone);

  factory SessionHandoff.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SessionHandoff(
      id: _readString(json['id']) ?? '',
      projectId: _readString(json['projectId']) ?? '',
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updatedAt']) ?? DateTime.now(),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => SessionHandoffItem.fromJson(_stringMap(item)))
              .where((item) => item.text.trim().isNotEmpty)
              .toList()
          : const <SessionHandoffItem>[],
      isArchived: _readBool(json['isArchived']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
      'isArchived': isArchived,
    };
  }

  SessionHandoff copyWith({
    DateTime? updatedAt,
    List<SessionHandoffItem>? items,
    bool? isArchived,
  }) {
    return SessionHandoff(
      id: id,
      projectId: projectId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

class SessionHandoffItem {
  final String id;
  final String text;
  final bool isDone;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? convertedPlanId;

  const SessionHandoffItem({
    required this.id,
    required this.text,
    this.isDone = false,
    required this.createdAt,
    this.completedAt,
    this.convertedPlanId,
  });

  factory SessionHandoffItem.fromJson(Map<String, dynamic> json) {
    return SessionHandoffItem(
      id: _readString(json['id']) ?? '',
      text: _readString(json['text']) ?? '',
      isDone: _readBool(json['isDone']) ?? false,
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
      completedAt: _readDateTime(json['completedAt']),
      convertedPlanId: _readString(json['convertedPlanId']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isDone': isDone,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'convertedPlanId': convertedPlanId,
    };
  }

  SessionHandoffItem copyWith({
    String? text,
    bool? isDone,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? convertedPlanId,
  }) {
    return SessionHandoffItem(
      id: id,
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      convertedPlanId: convertedPlanId ?? this.convertedPlanId,
    );
  }
}


class WorkspaceDocumentKind {
  static const String source = 'source';
  static const String working = 'working';
  static const String template = 'template';
  static const String link = 'link';
  static const String collection = 'collection';

  static const List<String> values = <String>[
    source,
    working,
    template,
    link,
    collection,
  ];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return working;
  }

  static String label(String value) {
    switch (normalize(value)) {
      case source:
        return 'Source document';
      case template:
        return 'Template';
      case link:
        return 'Link';
      case collection:
        return 'Collection';
      case working:
      default:
        return 'Working document';
    }
  }
}

class WorkspaceDocument {
  final String id;
  final String title;
  final String kind;
  final String body;
  final List<String> tags;
  final List<String> projectIds;
  final String? language;
  final String? sourceUrl;
  final String? currentVersionId;
  final List<DocumentVersion> versions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;

  const WorkspaceDocument({
    required this.id,
    required this.title,
    required this.kind,
    required this.body,
    this.tags = const <String>[],
    this.projectIds = const <String>[],
    this.language,
    this.sourceUrl,
    this.currentVersionId,
    this.versions = const <DocumentVersion>[],
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
  });

  DocumentVersion? get currentVersion {
    if (currentVersionId == null) return versions.isEmpty ? null : versions.last;
    for (final version in versions) {
      if (version.id == currentVersionId) return version;
    }
    return versions.isEmpty ? null : versions.last;
  }

  factory WorkspaceDocument.fromJson(Map<String, dynamic> json) {
    final rawVersions = json['versions'];
    return WorkspaceDocument(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Untitled document',
      kind: WorkspaceDocumentKind.normalize(_readString(json['kind'])),
      body: _readString(json['body']) ?? '',
      tags: _readStringList(json['tags']),
      projectIds: _readStringList(json['projectIds']),
      language: _readString(json['language']),
      sourceUrl: _readString(json['sourceUrl']),
      currentVersionId: _readString(json['currentVersionId']),
      versions: rawVersions is List
          ? rawVersions
              .whereType<Map>()
              .map((item) => DocumentVersion.fromJson(_stringMap(item)))
              .toList(growable: false)
          : const <DocumentVersion>[],
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updatedAt']) ?? DateTime.now(),
      isArchived: _readBool(json['isArchived']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'kind': kind,
      'body': body,
      'tags': tags,
      'projectIds': projectIds,
      'language': language,
      'sourceUrl': sourceUrl,
      'currentVersionId': currentVersionId,
      'versions': versions.map((version) => version.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isArchived': isArchived,
    };
  }

  WorkspaceDocument copyWith({
    String? title,
    String? kind,
    String? body,
    List<String>? tags,
    List<String>? projectIds,
    Object? language = _sentinel,
    Object? sourceUrl = _sentinel,
    String? currentVersionId,
    List<DocumentVersion>? versions,
    DateTime? updatedAt,
    bool? isArchived,
  }) {
    return WorkspaceDocument(
      id: id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      body: body ?? this.body,
      tags: tags ?? this.tags,
      projectIds: projectIds ?? this.projectIds,
      language: identical(language, _sentinel) ? this.language : language as String?,
      sourceUrl: identical(sourceUrl, _sentinel) ? this.sourceUrl : sourceUrl as String?,
      currentVersionId: currentVersionId ?? this.currentVersionId,
      versions: versions ?? this.versions,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

class DocumentVersion {
  final String id;
  final String label;
  final String body;
  final String? sourceUrl;
  final String? note;
  final DateTime createdAt;

  const DocumentVersion({
    required this.id,
    required this.label,
    required this.body,
    this.sourceUrl,
    this.note,
    required this.createdAt,
  });

  factory DocumentVersion.fromJson(Map<String, dynamic> json) {
    return DocumentVersion(
      id: _readString(json['id']) ?? '',
      label: _readString(json['label']) ?? 'Version',
      body: _readString(json['body']) ?? '',
      sourceUrl: _readString(json['sourceUrl']),
      note: _readString(json['note']),
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'body': body,
      'sourceUrl': sourceUrl,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class DevTodoStatus {
  static const String open = 'open';
  static const String inProgress = 'inProgress';
  static const String done = 'done';

  static const List<String> values = <String>[open, inProgress, done];

  static String normalize(String? value) {
    if (values.contains(value)) return value!;
    return open;
  }

  static String label(String value) {
    switch (normalize(value)) {
      case inProgress:
        return 'In progress';
      case done:
        return 'Done';
      case open:
      default:
        return 'Open';
    }
  }
}

class DevTodo {
  final String id;
  final String title;
  final String? description;
  final String area;
  final String priority;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;

  const DevTodo({
    required this.id,
    required this.title,
    this.description,
    required this.area,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
  });

  bool get isDone => status == DevTodoStatus.done;

  factory DevTodo.fromJson(Map<String, dynamic> json) {
    return DevTodo(
      id: _readString(json['id']) ?? '',
      title: _readString(json['title']) ?? 'Untitled dev todo',
      description: _readString(json['description']),
      area: _readString(json['area']) ?? 'General',
      priority: _readString(json['priority']) ?? 'Medium',
      status: DevTodoStatus.normalize(_readString(json['status'])),
      createdAt: _readDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _readDateTime(json['updatedAt']) ?? DateTime.now(),
      isArchived: _readBool(json['isArchived']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'area': area,
      'priority': priority,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isArchived': isArchived,
    };
  }

  DevTodo copyWith({
    String? title,
    Object? description = _sentinel,
    String? area,
    String? priority,
    String? status,
    DateTime? updatedAt,
    bool? isArchived,
  }) {
    return DevTodo(
      id: id,
      title: title ?? this.title,
      description: identical(description, _sentinel) ? this.description : description as String?,
      area: area ?? this.area,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}

const Object _sentinel = Object();

class SessionHandoffEntry {
  final StudyProject project;
  final SessionHandoff handoff;
  final SessionHandoffItem item;

  const SessionHandoffEntry({
    required this.project,
    required this.handoff,
    required this.item,
  });
}

Map<String, dynamic> _stringMap(Map<dynamic, dynamic> value) {
  return value.map((key, value) => MapEntry(key.toString(), value));
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _dateKey(DateTime value) {
  final date = _dateOnly(value);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String? _cleanOptional(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

List<String> _cleanStringList(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

List<String> _cleanProjectIds(Iterable<String> values) => _cleanStringList(values);

List<String> _readStringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

String? _readString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _readBool(Object? value) {
  if (value is bool) return value;
  if (value is String) return bool.tryParse(value);
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

DateTime? _readDate(Object? value) {
  if (value is DateTime) return _dateOnly(value);
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return _dateOnly(parsed);
  }
  return null;
}
