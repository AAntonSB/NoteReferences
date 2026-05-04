import 'package:flutter/material.dart';

import '../data/study_planning_repository.dart';

Future<void> showDevTodoDrawer({
  required BuildContext context,
  required StudyPlanningRepository planningRepository,
}) async {
  await planningRepository.load();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DevTodoDrawer(planningRepository: planningRepository),
  );
}

class DevTodoDrawer extends StatefulWidget {
  final StudyPlanningRepository planningRepository;

  const DevTodoDrawer({super.key, required this.planningRepository});

  @override
  State<DevTodoDrawer> createState() => _DevTodoDrawerState();
}

class _DevTodoDrawerState extends State<DevTodoDrawer> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _area = 'General';
  String _priority = 'Medium';
  bool _isAdding = false;

  bool get _hasInput =>
      _titleController.text.trim().isNotEmpty || _descriptionController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_refresh);
    _descriptionController.addListener(_refresh);
  }

  @override
  void dispose() {
    _titleController.removeListener(_refresh);
    _descriptionController.removeListener(_refresh);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    if (_isAdding || !_hasInput) return;

    final titleText = _titleController.text.trim();
    final descriptionText = _descriptionController.text.trim();
    final fallbackTitle = descriptionText.split('\n').first.trim();
    final title = titleText.isNotEmpty
        ? titleText
        : fallbackTitle.isNotEmpty
            ? fallbackTitle
            : 'Untitled dev todo';

    setState(() => _isAdding = true);
    try {
      await widget.planningRepository.load();
      await widget.planningRepository.createDevTodo(
        title: title,
        description: descriptionText.isEmpty ? null : descriptionText,
        area: _area,
        priority: _priority,
      );
      _titleController.clear();
      _descriptionController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dev todo added.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add dev todo: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.planningRepository,
      builder: (context, _) {
        final todos = widget.planningRepository.devTodos.toList()
          ..sort((a, b) {
            if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
            return b.updatedAt.compareTo(a.updatedAt);
          });
        final openCount = todos.where((todo) => !todo.isDone).length;

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.88,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.bug_report_outlined, color: theme.colorScheme.onTertiaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dev todos', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                          Text(
                            '$openCount open testing ${openCount == 1 ? 'note' : 'notes'}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _titleController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Bug, issue, or feature note',
                            hintText: 'Example: Calendar item hover preview is too small',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _add(),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _descriptionController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Details',
                            hintText: 'Optional. Paste reproduction steps, notes, or design thoughts.',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _area,
                                decoration: const InputDecoration(labelText: 'Area', border: OutlineInputBorder(), isDense: true),
                                items: const ['General', 'Library', 'PDF reader', 'Calendar', 'Today', 'Projects', 'Documents', 'Todos']
                                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                                    .toList(),
                                onChanged: (value) => setState(() => _area = value ?? 'General'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _priority,
                                decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder(), isDense: true),
                                items: const ['Low', 'Medium', 'High']
                                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                                    .toList(),
                                onChanged: (value) => setState(() => _priority = value ?? 'Medium'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _hasInput && !_isAdding ? _add : null,
                          icon: _isAdding
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.add_rounded),
                          label: Text(_isAdding ? 'Adding...' : 'Add dev todo'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: todos.isEmpty
                      ? const Center(child: Text('No dev todos yet.'))
                      : ListView.separated(
                          itemCount: todos.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final todo = todos[index];
                            return Card(
                              elevation: 0,
                              color: todo.isDone ? theme.colorScheme.surfaceContainerHighest.withAlpha(90) : theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: theme.colorScheme.outlineVariant),
                              ),
                              child: ListTile(
                                leading: Checkbox(
                                  value: todo.isDone,
                                  onChanged: (value) => widget.planningRepository.setDevTodoDone(todo.id, value ?? true),
                                ),
                                title: Text(
                                  todo.title,
                                  style: TextStyle(
                                    decoration: todo.isDone ? TextDecoration.lineThrough : null,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (todo.description?.isNotEmpty == true) Text(todo.description!),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        Chip(label: Text(todo.area), visualDensity: VisualDensity.compact),
                                        Chip(label: Text(todo.priority), visualDensity: VisualDensity.compact),
                                        Chip(label: Text(DevTodoStatus.label(todo.status)), visualDensity: VisualDensity.compact),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () => widget.planningRepository.archiveDevTodo(todo.id),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
