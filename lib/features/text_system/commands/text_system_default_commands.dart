import 'package:flutter/material.dart';

import '../core/text_mark.dart';
import '../surfaces/text_system_surface_controller.dart';
import 'text_system_command.dart';
import 'text_system_command_ids.dart';
import 'text_system_command_registry.dart';

class TextSystemDefaultCommands {
  const TextSystemDefaultCommands._();

  static TextSystemCommandRegistry forSurface(TextSystemSurfaceController surface) {
    return TextSystemCommandRegistry(<TextSystemCommand>[
      TextSystemCommand(
        id: TextSystemCommandIds.bold,
        label: 'Bold',
        icon: Icons.format_bold_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+B',
        isAvailable: (_) => surface.canFormatSelection,
        execute: () => surface.toggleMark(TextMarkKind.bold),
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.italic,
        label: 'Italic',
        icon: Icons.format_italic_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+I',
        isAvailable: (_) => surface.canFormatSelection,
        execute: () => surface.toggleMark(TextMarkKind.italic),
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.underline,
        label: 'Underline',
        icon: Icons.format_underlined_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+U',
        isAvailable: (_) => surface.canFormatSelection,
        execute: () => surface.toggleMark(TextMarkKind.underline),
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.strikethrough,
        label: 'Strikethrough',
        icon: Icons.strikethrough_s_rounded,
        isAvailable: (_) => surface.canFormatSelection,
        execute: () => surface.toggleMark(TextMarkKind.strikethrough),
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.inlineCode,
        label: 'Inline code',
        icon: Icons.code_rounded,
        isAvailable: (_) => surface.canFormatSelection,
        execute: () => surface.toggleMark(TextMarkKind.code),
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.highlight,
        label: 'Highlight',
        icon: Icons.border_color_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+Shift+H',
        isAvailable: (_) => surface.canHighlightSelection,
        execute: () => surface.toggleMark(TextMarkKind.highlight),
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.link,
        label: 'Link marker',
        icon: Icons.link_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+K',
        isAvailable: (_) => surface.canLinkSelection,
        execute: () => surface.toggleMark(TextMarkKind.link),
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.copyRich,
        label: 'Copy rich',
        icon: Icons.copy_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+C',
        isAvailable: (_) => surface.hasExpandedSelection && surface.canUseRichClipboard,
        execute: () {
          surface.copySelectionToInternalClipboard();
        },
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.pasteRich,
        label: 'Paste rich',
        icon: Icons.content_paste_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+V',
        isAvailable: (_) => surface.canUseRichClipboard && surface.textController.internalClipboard != null,
        execute: surface.pasteInternalClipboardAtSelection,
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.undo,
        label: 'Undo',
        icon: Icons.undo_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+Z',
        isAvailable: (_) => surface.canUndo,
        execute: surface.undo,
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.redo,
        label: 'Redo',
        icon: Icons.redo_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+Shift+Z',
        isAvailable: (_) => surface.canRedo,
        execute: surface.redo,
      ),
      TextSystemCommand(
        id: TextSystemCommandIds.save,
        label: 'Save',
        icon: Icons.save_rounded,
        defaultShortcutLabel: 'Ctrl/Cmd+S',
        isAvailable: (_) => surface.autosaveController != null,
        execute: () {
          surface.saveNow();
        },
      ),
    ]);
  }
}
