import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../planning/data/study_planning_repository.dart';
import '../premium/premium_writer_screen.dart';

class TextSystemTestEnvScreen extends StatelessWidget {
  const TextSystemTestEnvScreen({
    super.key,
    this.database,
    this.planningRepository,
  });

  final AppDatabase? database;
  final StudyPlanningRepository? planningRepository;

  @override
  Widget build(BuildContext context) {
    return PremiumWriterScreen(
      screenTitle: 'Premium Writer',
      showInspectorByDefault: true,
      database: database,
      planningRepository: planningRepository,
    );
  }
}
