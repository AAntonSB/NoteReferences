import 'package:flutter/material.dart';

import '../features/home/presentation/study_home_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/planning/data/study_planning_repository.dart';
import '../features/settings/data/app_settings_controller.dart';
import '../infrastructure/database/app_database.dart';

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  late final AppDatabase database;
  late final AppSettingsController settingsController;
  late final StudyPlanningRepository planningRepository;

  @override
  void initState() {
    super.initState();
    database = AppDatabase();
    settingsController = AppSettingsController();
    planningRepository = StudyPlanningRepository();
    settingsController.load();
  }

  @override
  void dispose() {
    planningRepository.dispose();
    settingsController.dispose();
    database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      controller: settingsController,
      child: MaterialApp(
        title: 'Note References',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: _LaunchWorkspace(
          database: database,
          planningRepository: planningRepository,
        ),
      ),
    );
  }
}

class _LaunchWorkspace extends StatefulWidget {
  final AppDatabase database;
  final StudyPlanningRepository planningRepository;

  const _LaunchWorkspace({
    required this.database,
    required this.planningRepository,
  });

  @override
  State<_LaunchWorkspace> createState() => _LaunchWorkspaceState();
}

class _LaunchWorkspaceState extends State<_LaunchWorkspace> {
  bool _shownInitialBriefing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showInitialBriefing());
  }

  Future<void> _showInitialBriefing() async {
    if (!mounted || _shownInitialBriefing) return;
    _shownInitialBriefing = true;
    await showTodayBriefingModal(
      context: context,
      database: widget.database,
      planningRepository: widget.planningRepository,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LibraryScreen(
      database: widget.database,
      planningRepository: widget.planningRepository,
    );
  }
}

// Backward-compatible wrapper for the generated widget test.
// Prefer NotesApp in app code.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const NotesApp();
  }
}
