import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../source_editor/presentation/latex_source_editor_lab_screen.dart';
import '../../source_editor/presentation/source_editor_lab_screen.dart';
import 'text_engine_core_lab_screen.dart';
import 'text_system_persistence_lab_screen.dart';
import 'text_system_surface_infrastructure_lab_screen.dart';
import 'text_system_basic_surfaces_lab_screen.dart';
import 'text_system_simple_note_surface_lab_screen.dart';
import 'text_system_document_surface_lab_screen.dart';
import 'text_system_command_shortcut_lab_screen.dart';
import 'text_system_fluent_text_polish_lab_screen.dart';
import 'text_system_natural_keyboard_lab_screen.dart';
import 'text_system_document_selection_lab_screen.dart';
import 'text_system_structured_clipboard_lab_screen.dart';
import 'text_system_phase8_acceptance_lab_screen.dart';
import 'text_system_fluent_document_surface_lab_screen.dart';
import 'text_system_phase9_diagnostics_lab_screen.dart';

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

  Future<void> _openCoreTextEngineLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextEngineCoreLabScreen()),
    );
  }

  Future<void> _openPersistenceLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemPersistenceLabScreen()),
    );
  }

  Future<void> _openSurfaceInfrastructureLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemSurfaceInfrastructureLabScreen()),
    );
  }

  Future<void> _openBasicSurfacesLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemBasicSurfacesLabScreen()),
    );
  }

  Future<void> _openSimpleNoteSurfaceLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemSimpleNoteSurfaceLabScreen()),
    );
  }

  Future<void> _openDocumentSurfaceLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemDocumentSurfaceLabScreen()),
    );
  }

  Future<void> _openCommandShortcutLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemCommandShortcutLabScreen()),
    );
  }

  Future<void> _openFluentTextPolishLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemFluentTextPolishLabScreen()),
    );
  }

  Future<void> _openNaturalKeyboardLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemNaturalKeyboardLabScreen()),
    );
  }

  Future<void> _openDocumentSelectionLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemDocumentSelectionLabScreen()),
    );
  }

  Future<void> _openStructuredClipboardLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemStructuredClipboardLabScreen()),
    );
  }


  Future<void> _openFluentDocumentSurfaceLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemFluentDocumentSurfaceLabScreen()),
    );
  }


  Future<void> _openPhase9DiagnosticsLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemPhase9DiagnosticsLabScreen()),
    );
  }

  Future<void> _openPhase8AcceptanceLab() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TextSystemPhase8AcceptanceLabScreen()),
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
              _TestSurfaceCard(
                icon: Icons.text_fields_rounded,
                title: 'Core text engine surface',
                description:
                    'Phase 6 native text-system surface: structured text, formatting marks, internal rich copy/paste, undo/redo, snapshots, and transaction logging.',
                actionLabel: 'Open core lab',
                onPressed: _openCoreTextEngineLab,
              ),
              _TestSurfaceCard(
                icon: Icons.health_and_safety_rounded,
                title: 'Persistence safety lab',
                description:
                    'Phase 6 completion surface: document JSON, save/load contract, autosave state, and surface configuration validation.',
                actionLabel: 'Open safety lab',
                onPressed: _openPersistenceLab,
              ),
              _TestSurfaceCard(
                icon: Icons.dashboard_customize_rounded,
                title: 'Surface infrastructure lab',
                description:
                    'Phase 7A shared surface layer: selection bridge, surface controller, toolbar, keyboard dispatcher, command registry, and autosave handoff.',
                actionLabel: 'Open surface lab',
                onPressed: _openSurfaceInfrastructureLab,
              ),
              _TestSurfaceCard(
                icon: Icons.short_text_rounded,
                title: 'Basic text surfaces lab',
                description:
                    'Phase 7B concrete lightweight surfaces: InlineTextSurface for compact editing and ReadOnlyTextSurface for non-mutating structured rendering.',
                actionLabel: 'Open 7B lab',
                onPressed: _openBasicSurfacesLab,
              ),
              _TestSurfaceCard(
                icon: Icons.sticky_note_2_rounded,
                title: 'Simple note surface lab',
                description:
                    'Phase 7C lightweight multi-line note surface for sidecar notes, observations, comments, and compact project notes.',
                actionLabel: 'Open 7C lab',
                onPressed: _openSimpleNoteSurfaceLab,
              ),
              _TestSurfaceCard(
                icon: Icons.article_rounded,
                title: 'Document text surface lab',
                description:
                    'Phase 7D regular document surface: title editing, multiple blocks, document spacing, headings, basic lists, and read-only preview.',
                actionLabel: 'Open 7D lab',
                onPressed: _openDocumentSurfaceLab,
              ),
              _TestSurfaceCard(
                icon: Icons.keyboard_command_key_rounded,
                title: 'Command and shortcut lab',
                description:
                    'Phase 7E hardening pass: shared command ids, shortcut profile, availability rules, link marker placeholder, and final Phase 7 acceptance checks.',
                actionLabel: 'Open 7E lab',
                onPressed: _openCommandShortcutLab,
              ),
              _TestSurfaceCard(
                icon: Icons.edit_note_rounded,
                title: 'Fluent text polish lab',
                description:
                    'Phase 8A text-first UX polish: quieter frames, calmer input chrome, clear save state, and document text that does not feel like visible block management.',
                actionLabel: 'Open 8A lab',
                onPressed: _openFluentTextPolishLab,
              ),
              _TestSurfaceCard(
                icon: Icons.keyboard_return_rounded,
                title: 'Natural keyboard lab',
                description:
                    'Phase 8B text-first keyboard behavior: Enter and Backspace create natural paragraph/list transitions while structure stays internal.',
                actionLabel: 'Open 8B lab',
                onPressed: _openNaturalKeyboardLab,
              ),
              _TestSurfaceCard(
                icon: Icons.text_fields_rounded,
                title: 'Fluent document selection lab',
                description:
                    'Phase 8C document-level selection foundation: maps fluent text offsets to internal text units and extracts structured cross-paragraph fragments.',
                actionLabel: 'Open 8C lab',
                onPressed: _openDocumentSelectionLab,
              ),
              _TestSurfaceCard(
                icon: Icons.content_paste_go_rounded,
                title: 'Structured copy/paste lab',
                description:
                    'Phase 8D cross-paragraph copy/paste foundation: stores structured document fragments and inserts them back through fluent document offsets.',
                actionLabel: 'Open 8D lab',
                onPressed: _openStructuredClipboardLab,
              ),
              _TestSurfaceCard(
                icon: Icons.verified_rounded,
                title: 'Phase 8 acceptance lab',
                description:
                    'Phase 8E final pass: validates fluent-text foundations, rich preservation, persistence safety, structured copy/paste, and the no-block-management UX rule.',
                actionLabel: 'Open 8E lab',
                onPressed: _openPhase8AcceptanceLab,
              ),
              _TestSurfaceCard(
                icon: Icons.article_rounded,
                title: 'Fluent document surface lab',
                description:
                    'Phase 9A–9E fluent editor lab: continuous editing, styling, selection formatting, copy/paste, and natural editing rules.',
                actionLabel: 'Open 9E lab',
                onPressed: _openFluentDocumentSurfaceLab,
              ),

              _TestSurfaceCard(
                icon: Icons.health_and_safety_rounded,
                title: 'Phase 9 diagnostics lab',
                description:
                    'Phase 9F diagnostic tool: validates the fluent editor, checks model integrity, and copies a shareable report for debugging together.',
                actionLabel: 'Open 9F lab',
                onPressed: _openPhase9DiagnosticsLab,
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
              value: 'Text engine core + persistence contracts',
            ),
            const _CheckpointRow(
              label: 'Phase 7',
              value: 'Basic text surfaces',
            ),
            const _CheckpointRow(
              label: 'Phase 8',
              value: 'Fluent text UX foundations',
            ),
            const _CheckpointRow(
              label: 'Phase 9',
              value: 'Fluent document surface + styled continuous editing',
              active: true,
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
