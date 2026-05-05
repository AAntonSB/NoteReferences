import 'text_system_command.dart';

class TextSystemCommandRegistry {
  TextSystemCommandRegistry([Iterable<TextSystemCommand> commands = const <TextSystemCommand>[]]) {
    for (final command in commands) {
      register(command);
    }
  }

  final Map<String, TextSystemCommand> _commands = <String, TextSystemCommand>{};

  List<TextSystemCommand> get commands => List.unmodifiable(_commands.values);

  List<String> get commandIds => List.unmodifiable(_commands.keys);

  bool contains(String id) => _commands.containsKey(id);

  List<TextSystemCommand> availableCommands(TextSystemCommandContext context) {
    return _commands.values
        .where((command) => command.availableIn(context))
        .toList(growable: false);
  }

  void register(TextSystemCommand command) {
    _commands[command.id] = command;
  }

  TextSystemCommand? byId(String id) => _commands[id];

  bool execute(String id, TextSystemCommandContext context) {
    final command = byId(id);
    if (command == null || !command.availableIn(context)) return false;
    command.execute();
    return true;
  }
}
