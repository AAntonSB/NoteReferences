import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../source_editor/presentation/latex_source_editor_lab_screen.dart';
import '../../source_editor/presentation/source_editor_lab_screen.dart';

class TextSystemTestEnvScreen extends StatefulWidget {
  const TextSystemTestEnvScreen({super.key});

  @override
  State<TextSystemTestEnvScreen> createState() => _TextSystemTestEnvScreenState();
}

class _TextSystemTestEnvScreenState extends State<TextSystemTestEnvScreen> {
  final TextEditingController _scratchpadController = TextEditingController(
    text: 'Textsys scratchpad\n\nUse this page as the stable test environment for each text-system phase.\n\nPhase 6 starts by separating the reusable text system from any one workflow or screen.',
  );

  @override
  void dispose() {
    _scratchpadController.dispose();
    super.dispose();
  }

  Future<void> _copyScratchpad() async {
    await Clipboard.setData(ClipboardData(text: _scratchpadController.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scratchpad text copied.')),
    );
  }

  Future<void> _openPlainSourceLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SourceEditorLabScreen()),
    );
  }

  Future<void> _openLatexSourceLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LatexSourceEditorLabScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('textsys test env'),
        centerTitle: false,
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          _HeaderCard(
            title: 'Project-wide text system lab',
            subtitle:
                'Permanent test bench for the reusable text engine. Each phase should add or improve a test surface here before the feature is used elsewhere in the app.',
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final scratchpad = _ScratchpadCard(
                controller: _scratchpadController,
                onCopy: _copyScratchpad,
              );
              final roadmap = const _PhaseRoadmapCard();

              if (!wide) {
                return Column(
                  children: [
                    scratchpad,
                    const SizedBox(height: 16),
                    roadmap,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: scratchpad),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: roadmap),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('Test surfaces', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _TestSurfaceCard(
                icon: Icons.notes_rounded,
                title: 'Plain source-aware lab',
                description:
                    'Existing source-aware editor lab. Useful as a regression check while Phase 6 extracts the general text system.',
                actionLabel: 'Open plain lab',
                onPressed: _openPlainSourceLab,
              ),
              _TestSurfaceCard(
                icon: Icons.functions_rounded,
                title: 'LaTeX source-aware lab',
                description:
                    'Existing LaTeX visual/source/render lab. This remains the advanced source-aware branch of the text system.',
                actionLabel: 'Open LaTeX lab',
                onPressed: _openLatexSourceLab,
              ),
              const _TestSurfaceCard(
                icon: Icons.text_fields_rounded,
                title: 'Core text engine surface',
                description:
                    'Placeholder for the Phase 6 native text-system surface: structured text, formatting marks, selection, undo/redo, and safe persistence.',
                actionLabel: 'Coming in Phase 6',
              ),
              const _TestSurfaceCard(
                icon: Icons.article_outlined,
                title: 'Premium writer surface',
                description:
                    'Reserved for the long-form writing environment: outline, focus mode, shortcuts, revision safety, and export/preview slots.',
                actionLabel: 'Future phase',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScratchpadCard extends StatelessWidget {
  const _ScratchpadCard({required this.controller, required this.onCopy});

  final TextEditingController controller;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Phase 6 scratchpad',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy text'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This deliberately starts simple. It gives us a stable place to replace Flutter’s basic text field with the reusable Text Engine surface as Phase 6 progresses.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 10,
              maxLines: 18,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Scratchpad text',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseRoadmapCard extends StatelessWidget {
  const _PhaseRoadmapCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phase checkpoints', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            const _CheckpointRow(
              label: 'Phase 6',
              value: 'Text engine core + stable test env',
              active: true,
            ),
            const _CheckpointRow(
              label: 'Phase 7',
              value: 'Basic text surfaces',
            ),
            const _CheckpointRow(
              label: 'Phase 8',
              value: 'Persistence and revision safety',
            ),
            const _CheckpointRow(
              label: 'Phase 9',
              value: 'Commands and custom shortcuts',
            ),
            const _CheckpointRow(
              label: 'Phase 10',
              value: 'LaTeX-aware editor on text system',
            ),
            const _CheckpointRow(
              label: 'Phase 11',
              value: 'Premium writer surface',
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({
    required this.label,
    required this.value,
    this.active = false,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: active ? colorScheme.primary : colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestSurfaceCard extends StatelessWidget {
  const _TestSurfaceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 320,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onPressed,
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
