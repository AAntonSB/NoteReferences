import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../planning/data/study_planning_repository.dart';
import '../premium/premium_writer_screen.dart';

class TextSystemPremiumWriterLabScreen extends StatelessWidget {
  const TextSystemPremiumWriterLabScreen({
    super.key,
    this.database,
    this.planningRepository,
  });

  final AppDatabase? database;
  final StudyPlanningRepository? planningRepository;

  @override
  Widget build(BuildContext context) {
    return PremiumWriterScreen(
      screenTitle: 'Premium writer lab',
      showInspectorByDefault: true,
      database: database,
      planningRepository: planningRepository,
    );
  }
}
