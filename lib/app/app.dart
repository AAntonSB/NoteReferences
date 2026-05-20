import 'package:flutter/material.dart';

import '../features/home/presentation/study_home_screen.dart';
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
        home: StudyHomeScreen(
          database: database,
          planningRepository: planningRepository,
        ),
      ),
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
