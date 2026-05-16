import 'dart:async';

/// High-level writer commands used by the Premium Writer shell.
///
/// This registry is intentionally above any concrete editor surface. The
/// document header should ask for a writer command; the active surface decides
/// later how to execute selection-sensitive commands such as bold, citation, or
/// page breaks. Phase 15M-I wires only safe shell-level commands and records the
/// remaining command ids as migration targets.
enum TextSystemWriterCommandId {
  save,
  toggleFocusMode,
  toggleDocumentMap,
  toggleInspector,
  objectNavigator,
  toggleWidePage,
  toggleMarginGuides,
  togglePageBreakLabels,
  toggleMarginMarkers,
  hideMasterHeader,
  undo,
  redo,
  copy,
  cut,
  paste,
  style,
  bold,
  italic,
  underline,
  inlineCode,
  inlineMath,
  crossReference,
  highlight,
  bulletList,
  numberedList,
  documentTodo,
  align,
  pageBreak,
  sectionBreak,
  footnote,
  appTodo,
  table,
  figure,
  equation,
  addCitation,
  sourceManager,
  linkSource,
  linkDocument,
  linkProject,
  linkTodo,
  externalLink,
  pageSetup,
  headerFooter,
  pageNumbers,
  comment,
  checkReferences,
  documentTodos,
  stats,
  versionHistory,
  splitView,
}

typedef TextSystemWriterCommandExecutor = FutureOr<void> Function();
typedef TextSystemWriterCommandPredicate = bool Function();
typedef TextSystemWriterCommandMessage = String? Function();

class TextSystemWriterCommandState {
  const TextSystemWriterCommandState({
    required this.enabled,
    this.selected = false,
    this.disabledReason,
  });

  final bool enabled;
  final bool selected;
  final String? disabledReason;

  static const disabled = TextSystemWriterCommandState(enabled: false);
}

class TextSystemWriterCommandBinding {
  const TextSystemWriterCommandBinding({
    required this.id,
    required this.label,
    required this.description,
    this.execute,
    this.isEnabled,
    this.isSelected,
    this.disabledReason,
  });

  final TextSystemWriterCommandId id;
  final String label;
  final String description;
  final TextSystemWriterCommandExecutor? execute;
  final TextSystemWriterCommandPredicate? isEnabled;
  final TextSystemWriterCommandPredicate? isSelected;
  final TextSystemWriterCommandMessage? disabledReason;

  TextSystemWriterCommandState get state {
    final enabled = execute != null && (isEnabled?.call() ?? true);
    return TextSystemWriterCommandState(
      enabled: enabled,
      selected: isSelected?.call() ?? false,
      disabledReason: enabled ? null : disabledReason?.call(),
    );
  }
}

class TextSystemWriterCommandRegistry {
  TextSystemWriterCommandRegistry({Iterable<TextSystemWriterCommandBinding> bindings = const []}) {
    for (final binding in bindings) {
      register(binding);
    }
  }

  final Map<TextSystemWriterCommandId, TextSystemWriterCommandBinding> _bindings =
      <TextSystemWriterCommandId, TextSystemWriterCommandBinding>{};

  void register(TextSystemWriterCommandBinding binding) {
    _bindings[binding.id] = binding;
  }

  void registerAll(Iterable<TextSystemWriterCommandBinding> bindings) {
    for (final binding in bindings) {
      register(binding);
    }
  }

  bool contains(TextSystemWriterCommandId id) => _bindings.containsKey(id);

  TextSystemWriterCommandBinding? binding(TextSystemWriterCommandId id) => _bindings[id];

  TextSystemWriterCommandState state(TextSystemWriterCommandId id) =>
      _bindings[id]?.state ?? const TextSystemWriterCommandState(enabled: false, disabledReason: 'Command is not registered yet.');

  bool canExecute(TextSystemWriterCommandId id) => state(id).enabled;

  bool isSelected(TextSystemWriterCommandId id) => state(id).selected;

  String label(TextSystemWriterCommandId id) => _bindings[id]?.label ?? id.name;

  String description(TextSystemWriterCommandId id) => _bindings[id]?.description ?? 'Writer command.';

  Future<void> execute(TextSystemWriterCommandId id) async {
    final binding = _bindings[id];
    if (binding == null) return;
    final commandState = binding.state;
    if (!commandState.enabled) return;
    await Future<void>.sync(binding.execute!);
  }
}

TextSystemWriterCommandBinding disabledTextSystemWriterCommand({
  required TextSystemWriterCommandId id,
  required String label,
  required String description,
  String disabledReason = 'This command is still handled by the real-page toolbar during the UI migration.',
}) {
  return TextSystemWriterCommandBinding(
    id: id,
    label: label,
    description: description,
    disabledReason: () => disabledReason,
  );
}
