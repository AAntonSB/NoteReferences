import 'package:flutter/material.dart';

import '../data/app_settings_controller.dart';

enum _SettingsSection {
  sidecar;

  String get label {
    switch (this) {
      case _SettingsSection.sidecar:
        return 'Sidecar';
    }
  }

  IconData get icon {
    switch (this) {
      case _SettingsSection.sidecar:
        return Icons.view_sidebar_outlined;
    }
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection _selectedSection = _SettingsSection.sidecar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 36),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
        child: Row(
          children: [
            SizedBox(
              width: 220,
              child: Material(
                color: theme.colorScheme.surfaceContainerLowest,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 4, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Settings',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    for (final section in _SettingsSection.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _SettingsSectionTile(
                          section: section,
                          selected: section == _selectedSection,
                          onTap: () {
                            setState(() {
                              _selectedSection = section;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: switch (_selectedSection) {
                  _SettingsSection.sidecar => const _SidecarSettingsSection(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSectionTile extends StatelessWidget {
  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  const _SettingsSectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.72)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                section.icon,
                size: 20,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidecarSettingsSection extends StatelessWidget {
  const _SidecarSettingsSection();

  @override
  Widget build(BuildContext context) {
    final controller = AppSettingsScope.of(context);
    final settings = controller.settings;
    final theme = Theme.of(context);

    return ListView(
      key: const ValueKey('sidecar-settings-section'),
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      children: [
        Text('Sidecar', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Tune how margin notes behave while you read.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Draggable header for notes'),
                  subtitle: const Text(
                    'Show a small hover handle above sidecar notes.',
                  ),
                  value: settings.sidecarDraggableHeaderEnabled,
                  onChanged: (value) {
                    controller.setSidecarDraggableHeaderEnabled(value);
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: DropdownButtonFormField<SidecarDragKeybind>(
                    initialValue: settings.sidecarDragKeybind,
                    decoration: const InputDecoration(
                      labelText: 'Drag keybind',
                      helperText:
                          'Hold this key and drag the note body to move it.',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final option in SidecarDragKeybind.values)
                        DropdownMenuItem(
                          value: option,
                          child: Text(option.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      controller.setSidecarDragKeybind(value);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
