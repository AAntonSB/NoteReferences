import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/text_clipboard_fragment.dart';
import '../core/text_mark.dart';
import '../core/text_system_block.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_range.dart';
import '../persistence/text_system_autosave_controller.dart';
import 'text_system_selection_bridge.dart';
import 'text_system_surface_config.dart';

/// Shared controller used by concrete text-system surfaces.
///
/// This is Phase 7A's central bridge: it connects the UI text editing widget to
/// the project-wide [TextSystemController], selection handling, rich clipboard,
/// undo/redo, and optional autosave without each surface recoding that behavior.
class TextSystemSurfaceController extends ChangeNotifier {
  TextSystemSurfaceController({
    required this.textController,
    required this.config,
    required this.blockId,
    this.autosaveController,
    TextEditingController? editingController,
    FocusNode? focusNode,
  })  : editingController = editingController ?? TextEditingController(),
        focusNode = focusNode ?? FocusNode(),
        _ownsEditingController = editingController == null,
        _ownsFocusNode = focusNode == null {
    _lastKnownEditorText = currentBlock.text;
    this.editingController.text = _lastKnownEditorText;
    this.editingController.addListener(_handleEditorChanged);
    textController.addListener(_syncFromTextSystem);
  }

  final TextSystemController textController;
  final TextSystemSurfaceConfig config;
  final String blockId;
  final TextSystemAutosaveController? autosaveController;
  final TextEditingController editingController;
  final FocusNode focusNode;

  final bool _ownsEditingController;
  final bool _ownsFocusNode;

  bool _syncingFromTextSystem = false;
  late String _lastKnownEditorText;

  TextSystemBlock get currentBlock =>
      textController.document.blockById(blockId) ??
      TextSystemBlock.paragraph(id: blockId, text: '');

  bool get isReadOnly =>
      config.editorMode == TextSystemEditorMode.readOnly ||
      config.kind == TextSystemSurfaceKind.readOnly;

  bool get hasExpandedSelection => selectedRange != null && !selectedRange!.isCollapsed;
  bool get canUndo => config.features.undoRedo && textController.canUndo;
  bool get canRedo => config.features.undoRedo && textController.canRedo;
  bool get canFormatSelection => !isReadOnly && config.features.inlineFormatting && hasExpandedSelection;
  bool get canHighlightSelection => !isReadOnly && config.features.highlighting && hasExpandedSelection;
  bool get canUseRichClipboard => config.features.richClipboard;

  TextSystemRange? get selectedRange => TextSystemSelectionBridge.rangeFromSelection(
        editingController.selection,
        textLength: currentBlock.text.length,
      );

  TextSystemRange? get expandedSelection => TextSystemSelectionBridge.rangeFromSelection(
        editingController.selection,
        textLength: currentBlock.text.length,
        requireExpanded: true,
      );

  String get selectionLabel => TextSystemSelectionBridge.describeSelection(
        editingController.selection,
        textLength: currentBlock.text.length,
      );

  void requestFocus() => focusNode.requestFocus();

  void toggleMark(TextMarkKind kind) {
    if (isReadOnly) return;
    if (kind == TextMarkKind.highlight && !canHighlightSelection) return;
    if (kind != TextMarkKind.highlight && !canFormatSelection) return;

    final range = expandedSelection;
    if (range == null) return;
    textController.toggleMark(blockId, range, kind);
    requestFocus();
  }

  TextClipboardFragment copySelectionToInternalClipboard() {
    final range = expandedSelection;
    if (range == null) return const TextClipboardFragment(text: '');
    final fragment = textController.copyFragment(blockId, range);
    requestFocus();
    return fragment;
  }

  void pasteInternalClipboardAtSelection() {
    if (isReadOnly || !canUseRichClipboard) return;
    final range = selectedRange ?? TextSystemRange.collapsed(currentBlock.text.length);
    textController.insertFragment(
      blockId,
      range,
      textController.internalClipboard ?? const TextClipboardFragment(text: ''),
    );
    _placeCursor(range.start + (textController.internalClipboard?.text.length ?? 0));
    requestFocus();
  }

  void undo() {
    if (!canUndo) return;
    textController.undo();
    requestFocus();
  }

  void redo() {
    if (!canRedo) return;
    textController.redo();
    requestFocus();
  }

  Future<void> saveNow() async {
    await autosaveController?.saveNow(message: 'Manually saved from surface.');
  }

  void _handleEditorChanged() {
    if (_syncingFromTextSystem) return;

    final nextText = editingController.text;
    if (!isReadOnly && nextText != _lastKnownEditorText) {
      _lastKnownEditorText = nextText;
      textController.updateBlockText(blockId, nextText);
      return;
    }

    notifyListeners();
  }

  void _syncFromTextSystem() {
    final block = currentBlock;
    if (editingController.text != block.text) {
      _syncingFromTextSystem = true;
      final selection = editingController.selection;
      editingController.text = block.text;
      if (selection.isValid) {
        editingController.selection = TextSystemSelectionBridge.collapsedSelection(
          selection.extentOffset,
          textLength: block.text.length,
        );
      }
      _lastKnownEditorText = block.text;
      _syncingFromTextSystem = false;
    }
    notifyListeners();
  }

  void _placeCursor(int offset) {
    editingController.selection = TextSystemSelectionBridge.collapsedSelection(
      offset,
      textLength: editingController.text.length,
    );
  }

  @override
  void dispose() {
    textController.removeListener(_syncFromTextSystem);
    editingController.removeListener(_handleEditorChanged);
    if (_ownsEditingController) editingController.dispose();
    if (_ownsFocusNode) focusNode.dispose();
    super.dispose();
  }
}
