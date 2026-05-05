import 'package:flutter/widgets.dart';

class TextSystemCommandContext {
  const TextSystemCommandContext({
    required this.isEnabled,
    this.selectionLabel,
  });

  final bool isEnabled;
  final String? selectionLabel;
}

class TextSystemCommand {
  const TextSystemCommand({
    required this.id,
    required this.label,
    required this.execute,
    this.icon,
    this.defaultShortcutLabel,
    this.isAvailable,
  });

  final String id;
  final String label;
  final IconData? icon;
  final String? defaultShortcutLabel;
  final bool Function(TextSystemCommandContext context)? isAvailable;
  final void Function() execute;

  bool availableIn(TextSystemCommandContext context) =>
      isAvailable?.call(context) ?? context.isEnabled;
}
