import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'text_system_command_ids.dart';

/// Runtime shortcut binding for the project-wide text system.
///
/// Phase 7E keeps rebinding UI out of scope, but this model gives the settings
/// layer a stable place to override shortcuts later. Surfaces consume shortcut
/// profiles rather than hardcoding key combinations widget-by-widget.
class TextSystemShortcutBinding {
  const TextSystemShortcutBinding({
    required this.commandId,
    required this.activator,
    required this.label,
    this.description,
  });

  final String commandId;
  final ShortcutActivator activator;
  final String label;
  final String? description;
}

class TextSystemShortcutProfile {
  const TextSystemShortcutProfile({
    required this.id,
    required this.label,
    required this.bindings,
  });

  factory TextSystemShortcutProfile.defaults() {
    return const TextSystemShortcutProfile(
      id: 'text-system-default-shortcuts',
      label: 'Text system defaults',
      bindings: <TextSystemShortcutBinding>[
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.bold,
          activator: SingleActivator(LogicalKeyboardKey.keyB, control: true),
          label: 'Ctrl+B',
          description: 'Bold selected text on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.bold,
          activator: SingleActivator(LogicalKeyboardKey.keyB, meta: true),
          label: 'Cmd+B',
          description: 'Bold selected text on macOS.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.italic,
          activator: SingleActivator(LogicalKeyboardKey.keyI, control: true),
          label: 'Ctrl+I',
          description: 'Italicize selected text on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.italic,
          activator: SingleActivator(LogicalKeyboardKey.keyI, meta: true),
          label: 'Cmd+I',
          description: 'Italicize selected text on macOS.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.underline,
          activator: SingleActivator(LogicalKeyboardKey.keyU, control: true),
          label: 'Ctrl+U',
          description: 'Underline selected text on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.underline,
          activator: SingleActivator(LogicalKeyboardKey.keyU, meta: true),
          label: 'Cmd+U',
          description: 'Underline selected text on macOS.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.highlight,
          activator: SingleActivator(LogicalKeyboardKey.keyH, control: true, shift: true),
          label: 'Ctrl+Shift+H',
          description: 'Highlight selected text on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.highlight,
          activator: SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true),
          label: 'Cmd+Shift+H',
          description: 'Highlight selected text on macOS.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.link,
          activator: SingleActivator(LogicalKeyboardKey.keyK, control: true),
          label: 'Ctrl+K',
          description: 'Mark selected text as a link placeholder on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.link,
          activator: SingleActivator(LogicalKeyboardKey.keyK, meta: true),
          label: 'Cmd+K',
          description: 'Mark selected text as a link placeholder on macOS.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.undo,
          activator: SingleActivator(LogicalKeyboardKey.keyZ, control: true),
          label: 'Ctrl+Z',
          description: 'Undo on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.undo,
          activator: SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
          label: 'Cmd+Z',
          description: 'Undo on macOS.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.redo,
          activator: SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
          label: 'Ctrl+Shift+Z',
          description: 'Redo on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.redo,
          activator: SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
          label: 'Cmd+Shift+Z',
          description: 'Redo on macOS.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.redo,
          activator: SingleActivator(LogicalKeyboardKey.keyY, control: true),
          label: 'Ctrl+Y',
          description: 'Alternate redo on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.save,
          activator: SingleActivator(LogicalKeyboardKey.keyS, control: true),
          label: 'Ctrl+S',
          description: 'Manual save on Windows/Linux.',
        ),
        TextSystemShortcutBinding(
          commandId: TextSystemCommandIds.save,
          activator: SingleActivator(LogicalKeyboardKey.keyS, meta: true),
          label: 'Cmd+S',
          description: 'Manual save on macOS.',
        ),
      ],
    );
  }

  final String id;
  final String label;
  final List<TextSystemShortcutBinding> bindings;

  Map<ShortcutActivator, VoidCallback> toCallbackMap(void Function(String commandId) execute) {
    return <ShortcutActivator, VoidCallback>{
      for (final binding in bindings) binding.activator: () => execute(binding.commandId),
    };
  }

  List<TextSystemShortcutBinding> bindingsForCommand(String commandId) {
    return bindings.where((binding) => binding.commandId == commandId).toList(growable: false);
  }
}
