import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';
import 'create_study_plan_screen.dart';

class CreateProjectScreen extends StatefulWidget {
  final StudyPlanningRepository planningRepository;
  final bool openPlanAfterCreate;

  const CreateProjectScreen({
    super.key,
    required this.planningRepository,
    this.openPlanAfterCreate = true,
  });

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  DateTime? _deadline;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Create project'),
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _IntroCard(theme: theme),
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
                          'Project details',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _titleController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Project name',
                            hintText: 'Macroeconomics II',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Give the project a name.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _DatePickerTile(
                          label: 'Main deadline / exam date',
                          value: _deadline,
                          onPick: _pickDeadline,
                          onClear: _deadline == null
                              ? null
                              : () => setState(() => _deadline = null),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'After this, add a plan such as “read pages 1–356 by the exam”. No PDF is required.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.3,
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
                                  : const Icon(Icons.arrow_forward_rounded),
                              label: Text(widget.openPlanAfterCreate ? 'Create and add plan' : 'Create'),
                            ),
                          ],
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

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 21)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() => _deadline = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final project = await widget.planningRepository.createProject(
      title: _titleController.text,
      deadline: _deadline,
    );

    if (!mounted) return;

    if (!widget.openPlanAfterCreate) {
      Navigator.of(context).pop(project);
      return;
    }

    final createdPlan = await Navigator.of(context).push<StudyPlan>(
      MaterialPageRoute(
        builder: (_) => CreateStudyPlanScreen(
          planningRepository: widget.planningRepository,
          project: project,
        ),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop(createdPlan ?? project);
  }
}

class _IntroCard extends StatelessWidget {
  final ThemeData theme;

  const _IntroCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.dashboard_customize_rounded,
              size: 34,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Projects are simple containers. Plans create the daily work.',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A project can be a course, exam, paper, or any study goal. You can add plans to it now and connect PDFs later.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withAlpha(210),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _DatePickerTile({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear date',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
              IconButton(
                tooltip: 'Choose date',
                onPressed: onPick,
                icon: const Icon(Icons.calendar_month_rounded),
              ),
            ],
          ),
        ),
        child: Text(
          value == null ? 'No deadline yet' : _formatDate(value!),
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
