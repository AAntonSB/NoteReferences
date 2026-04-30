import 'dart:async';

import 'package:flutter/material.dart';

import '../data/tag_repository.dart';
import 'tag_icon_registry.dart';

class TagManagerDialog extends StatefulWidget {
  final TagRepository tagRepository;

  const TagManagerDialog({super.key, required this.tagRepository});

  @override
  State<TagManagerDialog> createState() => _TagManagerDialogState();
}

class _TagManagerDialogState extends State<TagManagerDialog> {
  bool _showArchived = false;
  bool _isCreating = false;
  String? _errorMessage;

  Future<Map<int, TagUsageSummary>>? _usageFuture;

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  void _refreshUsage() {
    _usageFuture = widget.tagRepository
        .getUsageSummariesWithLegacyDocumentTags();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.sell_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manage tags', style: theme.textTheme.titleLarge),
                        Text(
                          'Create reusable tags with icons and colors. PDF assignment comes next.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _isCreating ? null : _openCreateDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New tag'),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    selected: _showArchived,
                    onSelected: (value) {
                      setState(() {
                        _showArchived = value;
                      });
                    },
                    avatar: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Show archived'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(_refreshUsage);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh counts'),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    title: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: StreamBuilder<List<AppTag>>(
                stream: widget.tagRepository.watchTags(
                  includeArchived: _showArchived,
                ),
                builder: (context, snapshot) {
                  final tags = snapshot.data ?? const <AppTag>[];

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (tags.isEmpty) {
                    return const _EmptyTagsState();
                  }

                  return FutureBuilder<Map<int, TagUsageSummary>>(
                    future: _usageFuture,
                    builder: (context, usageSnapshot) {
                      final usage = usageSnapshot.data ?? const {};

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                        itemCount: tags.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final tag = tags[index];
                          return _TagManagerRow(
                            tag: tag,
                            usage: usage[tag.id] ?? TagUsageSummary.empty,
                            onEdit: () => _openEditDialog(tag),
                            onArchive: tag.isArchived
                                ? () => _restoreTag(tag)
                                : () => _archiveTag(tag),
                            archiveLabel: tag.isArchived
                                ? 'Restore'
                                : 'Archive',
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    final result = await showDialog<_EditableTagResult>(
      context: context,
      builder: (context) => const _EditTagDialog(),
    );

    if (result == null) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      await widget.tagRepository.createTag(
        name: result.name,
        description: result.description,
        colorValue: result.colorValue,
        iconKey: result.iconKey,
      );
      setState(_refreshUsage);
    } catch (error) {
      _showError('Could not create tag: $error');
    } finally {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
      });
    }
  }

  Future<void> _openEditDialog(AppTag tag) async {
    final result = await showDialog<_EditableTagResult>(
      context: context,
      builder: (context) => _EditTagDialog(tag: tag),
    );

    if (result == null) return;

    try {
      await widget.tagRepository.updateTag(
        tagId: tag.id,
        name: result.name,
        description: result.description,
        colorValue: result.colorValue,
        iconKey: result.iconKey,
        parentTagId: tag.parentTagId,
        sortOrder: tag.sortOrder,
      );
      setState(_refreshUsage);
    } catch (error) {
      _showError('Could not update tag: $error');
    }
  }

  Future<void> _archiveTag(AppTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive “${tag.name}”?'),
        content: const Text(
          'The tag will be hidden from normal tag pickers. Existing assignments are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.tagRepository.archiveTag(tag.id);
      setState(_refreshUsage);
    } catch (error) {
      _showError('Could not archive tag: $error');
    }
  }

  Future<void> _restoreTag(AppTag tag) async {
    try {
      await widget.tagRepository.restoreTag(tag.id);
      setState(_refreshUsage);
    } catch (error) {
      _showError('Could not restore tag: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
    });
  }
}

class _TagManagerRow extends StatelessWidget {
  final AppTag tag;
  final TagUsageSummary usage;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final String archiveLabel;

  const _TagManagerRow({
    required this.tag,
    required this.usage,
    required this.onEdit,
    required this.onArchive,
    required this.archiveLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagColor = Color(tag.colorValue);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tag.isArchived
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : tagColor.withValues(alpha: 0.08),
        border: Border.all(
          color: tag.isArchived
              ? theme.colorScheme.outlineVariant
              : tagColor.withValues(alpha: 0.34),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tagColor.withValues(
            alpha: tag.isArchived ? 0.15 : 0.22,
          ),
          foregroundColor: tagColor,
          child: Icon(iconForTagKey(tag.iconKey)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                tag.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  decoration: tag.isArchived
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            if (tag.isArchived) ...[
              const SizedBox(width: 8),
              const _SmallTagBadge(label: 'Archived'),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (tag.description != null) Text(tag.description!),
              _SmallTagBadge(label: '${usage.totalCount} uses'),
              if (usage.documentCount > 0)
                _SmallTagBadge(label: '${usage.documentCount} PDFs'),
              if (usage.noteCount > 0)
                _SmallTagBadge(label: '${usage.noteCount} notes'),
              if (usage.todoCount > 0)
                _SmallTagBadge(label: '${usage.todoCount} TODOs'),
              if (usage.highlightCount > 0)
                _SmallTagBadge(label: '${usage.highlightCount} highlights'),
            ],
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Edit tag',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: archiveLabel,
              onPressed: onArchive,
              icon: Icon(
                tag.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditTagDialog extends StatefulWidget {
  final AppTag? tag;

  const _EditTagDialog({this.tag});

  @override
  State<_EditTagDialog> createState() => _EditTagDialogState();
}

class _EditTagDialogState extends State<_EditTagDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  late int _colorValue;
  late String _iconKey;

  @override
  void initState() {
    super.initState();

    final tag = widget.tag;
    _nameController = TextEditingController(text: tag?.name ?? '');
    _descriptionController = TextEditingController(
      text: tag?.description ?? '',
    );
    _colorValue = tag?.colorValue ?? kDefaultTagColorValue;
    _iconKey = tag?.iconKey ?? kDefaultTagIconKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = Color(_colorValue);

    return AlertDialog(
      title: Text(widget.tag == null ? 'Create tag' : 'Edit tag'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text('Icon', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in tagIconOptions)
                    ChoiceChip(
                      selected: _iconKey == option.key,
                      onSelected: (_) {
                        setState(() {
                          _iconKey = option.key;
                        });
                      },
                      avatar: Icon(option.icon, size: 18),
                      label: Text(option.label),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Color', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final colorValue in tagColorOptions)
                    _ColorChoice(
                      color: Color(colorValue),
                      selected: _colorValue == colorValue,
                      onTap: () {
                        setState(() {
                          _colorValue = colorValue;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: selectedColor.withValues(alpha: 0.12),
                  border: Border.all(
                    color: selectedColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconForTagKey(_iconKey), color: selectedColor),
                      const SizedBox(width: 8),
                      Text(
                        _nameController.text.trim().isEmpty
                            ? 'Tag preview'
                            : _nameController.text.trim(),
                        style: TextStyle(
                          color: selectedColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.tag == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    Navigator.of(context).pop(
      _EditableTagResult(
        name: name,
        description: _descriptionController.text.trim(),
        colorValue: _colorValue,
        iconKey: _iconKey,
      ),
    );
  }
}

class _EditableTagResult {
  final String name;
  final String description;
  final int colorValue;
  final String iconKey;

  const _EditableTagResult({
    required this.name,
    required this.description,
    required this.colorValue,
    required this.iconKey,
  });
}

class _ColorChoice extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            width: selected ? 3 : 1,
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 18, color: theme.colorScheme.surface)
            : null,
      ),
    );
  }
}

class _SmallTagBadge extends StatelessWidget {
  final String label;

  const _SmallTagBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _EmptyTagsState extends StatelessWidget {
  const _EmptyTagsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sell_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No tags yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Create your first tag. Later we will assign these to PDFs, notes, TODOs, and highlights.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
