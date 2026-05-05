import '../commands/text_system_command.dart';

/// Feature module contract for the project-wide text system.
///
/// Capabilities keep small fields, normal notes, LaTeX mode, and the future
/// premium writer from hardcoding one another's UI and behavior.
abstract class TextSystemCapability {
  const TextSystemCapability();

  String get id;
  String get label;

  List<TextSystemCommand> buildCommands() => const <TextSystemCommand>[];
}
