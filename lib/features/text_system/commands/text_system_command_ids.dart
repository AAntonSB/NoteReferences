/// Stable command ids for project-wide text-system behavior.
///
/// These ids are intentionally reusable across tiny text fields, notes, document
/// surfaces, and future premium/source-aware writer shells. User shortcut
/// rebinding should target these ids, not widget-specific callbacks.
class TextSystemCommandIds {
  const TextSystemCommandIds._();

  static const String bold = 'textSystem.bold';
  static const String italic = 'textSystem.italic';
  static const String highlight = 'textSystem.highlight';
  static const String link = 'textSystem.link';
  static const String copyRich = 'textSystem.copyRich';
  static const String pasteRich = 'textSystem.pasteRich';
  static const String undo = 'textSystem.undo';
  static const String redo = 'textSystem.redo';
  static const String save = 'textSystem.save';
}
