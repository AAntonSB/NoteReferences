import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../notes/data/note_repository.dart';
import '../../../../settings/data/app_settings_controller.dart';
import '../note_type_presentation.dart';
import 'linked_selection_preview.dart';
import 'margin_note_toolbar.dart';

class MarginNoteCard extends StatefulWidget {
  final NoteWithAnchor item;
  final bool autofocus;
  final bool isRevealed;
  final VoidCallback onFocusConsumed;
  final VoidCallback? onJumpToSource;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<NoteMetadata> onMetadataChanged;
  final ValueChanged<bool>? onTodoCompletedChanged;
  final ValueChanged<bool>? onEditingChanged;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<Offset>? onDragDelta;
  final VoidCallback? onDragEnd;
  final VoidCallback onArchiveIfEmpty;
  final VoidCallback onArchive;
  final AppSettings appSettings;

  const MarginNoteCard({
    super.key,
    required this.item,
    required this.autofocus,
    required this.isRevealed,
    required this.onFocusConsumed,
    required this.onChanged,
    required this.onTypeChanged,
    required this.onMetadataChanged,
    required this.onArchiveIfEmpty,
    required this.onArchive,
    required this.appSettings,
    this.onJumpToSource,
    this.onTodoCompletedChanged,
    this.onEditingChanged,
    this.onHoverChanged,
    this.onDragDelta,
    this.onDragEnd,
  });

  @override
  State<MarginNoteCard> createState() => _MarginNoteCardState();
}

class _MarginNoteCardState extends State<MarginNoteCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  Timer? _debounce;

  bool _isHovered = false;
  bool _isEditing = false;
  bool _isShiftDragging = false;
  bool _isHandleDragging = false;

  late String _localNoteType;
  late NoteMetadata _localMetadata;

  static const Duration _autosaveDelay = Duration(milliseconds: 650);

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.item.body);
    _focusNode = FocusNode();
    _localNoteType = widget.item.noteType;
    _localMetadata = widget.item.metadata;

    _isEditing = widget.autofocus || widget.item.body.trim().isEmpty;

    _focusNode.addListener(_handleFocusChange);

    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        widget.onEditingChanged?.call(true);
      });
    }

    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _enterEditing();
        widget.onFocusConsumed();
      });
    }
  }

  @override
  void didUpdateWidget(covariant MarginNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.item.note.id != widget.item.note.id) {
      _controller.text = widget.item.body;
      _localNoteType = widget.item.noteType;
      _localMetadata = widget.item.metadata;
      _isEditing = widget.item.body.trim().isEmpty;

      if (_isEditing) {
        widget.onEditingChanged?.call(true);
      }
    } else {
      final databaseBodyChanged = widget.item.body != oldWidget.item.body;
      final notCurrentlyEditing = !_focusNode.hasFocus;

      if (notCurrentlyEditing &&
          databaseBodyChanged &&
          _controller.text != widget.item.body) {
        _controller.text = widget.item.body;
      }

      if (widget.item.noteType != oldWidget.item.noteType &&
          widget.item.noteType != _localNoteType) {
        _localNoteType = widget.item.noteType;
      }

      if (widget.item.anchor.geometryJson !=
          oldWidget.item.anchor.geometryJson) {
        _localMetadata = widget.item.metadata;
      }
    }

    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _enterEditing();
        widget.onFocusConsumed();
      });
    }
  }

  @override
  void dispose() {
    _flushPendingSave();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _enterEditing() {
    if (!_isEditing) {
      setState(() {
        _isEditing = true;
      });

      widget.onEditingChanged?.call(true);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _focusNode.requestFocus();
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _exitEditing() {
    _flushPendingSave();

    widget.onEditingChanged?.call(false);

    if (_controller.text.trim().isEmpty) {
      widget.onArchiveIfEmpty();
      return;
    }

    if (mounted) {
      setState(() {
        _isEditing = false;
      });
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _exitEditing();
    }
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(_autosaveDelay, () {
      widget.onChanged(value);
    });
  }

  void _flushPendingSave() {
    _debounce?.cancel();
    _debounce = null;

    widget.onChanged(_controller.text);
  }

  void _changeNoteType(String noteType) {
    setState(() {
      _localNoteType = noteType;
    });

    widget.onTypeChanged(noteType);
  }

  Future<void> _editDetails() async {
    final result = await showDialog<NoteMetadata>(
      context: context,
      builder: (context) {
        return _NoteDetailsDialog(
          initialMetadata: _localMetadata,
          hasSourceAnchor: widget.item.sourceRects.isNotEmpty,
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _localMetadata = result;
    });

    widget.onMetadataChanged(result);
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focusNode.unfocus();
      _exitEditing();
      return KeyEventResult.handled;
    }

    final isControlEnter =
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed;

    if (isControlEnter) {
      _focusNode.unfocus();
      _exitEditing();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Map<String, dynamic> _todoMetadata() {
    final json = widget.item.firstBlock?.contentJson;
    if (json == null || json.trim().isEmpty) return {};

    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return {};
    }

    return {};
  }

  bool get _isTodo {
    return _localNoteType == kTodoNoteType;
  }

  bool get _todoCompleted {
    final value = _todoMetadata()['isCompleted'];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return false;
  }

  String get _todoPriority {
    final value = _todoMetadata()['priority'];
    if (value == kTodoPriorityLow || value == kTodoPriorityHigh) {
      return value as String;
    }
    return kTodoPriorityMedium;
  }

  Color _todoPriorityColor(ThemeData theme) {
    switch (_todoPriority) {
      case kTodoPriorityHigh:
        return theme.colorScheme.error;
      case kTodoPriorityLow:
        return theme.colorScheme.primary;
      case kTodoPriorityMedium:
      default:
        return Colors.orange.shade700;
    }
  }

  bool get _dragKeyPressed {
    final keyboard = HardwareKeyboard.instance;

    switch (widget.appSettings.sidecarDragKeybind) {
      case SidecarDragKeybind.shift:
        return keyboard.isShiftPressed;
      case SidecarDragKeybind.alt:
        return keyboard.isAltPressed;
      case SidecarDragKeybind.control:
        return keyboard.isControlPressed;
    }
  }

  void _handleShiftDragStart(DragStartDetails details) {
    _isShiftDragging = _dragKeyPressed && widget.onDragDelta != null;
    if (_isShiftDragging && _isEditing) {
      _focusNode.unfocus();
    }

    if (_isShiftDragging && mounted) {
      setState(() {});
    }
  }

  void _handleShiftDragUpdate(DragUpdateDetails details) {
    if (!_isShiftDragging) return;
    widget.onDragDelta?.call(details.delta);
  }

  void _handleShiftDragEnd([Object? _]) {
    if (!_isShiftDragging) return;
    _isShiftDragging = false;
    if (mounted) {
      setState(() {});
    }
    widget.onDragEnd?.call();
  }

  void _handleDirectDragStart() {
    if (widget.onDragDelta == null) return;

    if (_isEditing) {
      _focusNode.unfocus();
    }

    if (!_isHandleDragging) {
      setState(() {
        _isHandleDragging = true;
      });
    }
  }

  void _handleDirectDragUpdate(Offset delta) {
    if (widget.onDragDelta == null) return;
    if (!_isHandleDragging) {
      _handleDirectDragStart();
    }

    widget.onDragDelta?.call(delta);
  }

  void _handleDirectDragEnd() {
    if (!_isHandleDragging) return;

    setState(() {
      _isHandleDragging = false;
    });

    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = NoteTypePresentation.fromType(_localNoteType, theme);

    final isTodo = _isTodo;
    final isTodoCompleted = _todoCompleted;
    final todoColor = _todoPriorityColor(theme);

    final selectedText = widget.item.anchor.selectedText?.trim();
    final hasSelectedText = selectedText != null && selectedText.isNotEmpty;

    final showChrome = _isHovered || _isEditing || widget.isRevealed || _isHandleDragging || _isShiftDragging;
    final bodyText = _controller.text;
    final bodyTextTrimmed = bodyText.trim();
    final isCreatingEmptyNote = _isEditing && bodyTextTrimmed.isEmpty;
    final showActionHeader = !isCreatingEmptyNote && showChrome;

    final borderColor = widget.isRevealed
        ? theme.colorScheme.primary
        : isCreatingEmptyNote
        ? presentation.accentColor.withValues(alpha: 0.72)
        : _isEditing
        ? (isTodo ? todoColor : presentation.accentColor)
        : showChrome
        ? theme.colorScheme.outlineVariant
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) {
        if (_isHovered) return;

        setState(() {
          _isHovered = true;
        });

        widget.onHoverChanged?.call(true);
      },
      onExit: (_) {
        if (!_isHovered) return;

        setState(() {
          _isHovered = false;
        });

        widget.onHoverChanged?.call(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _handleShiftDragStart,
        onPanUpdate: _handleShiftDragUpdate,
        onPanEnd: (_) => _handleShiftDragEnd(),
        onPanCancel: _handleShiftDragEnd,
        onTap: () {
          if (_dragKeyPressed) return;
          if (!_isEditing) {
            _enterEditing();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isTodo
                ? todoColor.withValues(alpha: showChrome ? 0.09 : 0.055)
                : showChrome
                ? theme.colorScheme.surface.withValues(alpha: 0.96)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: widget.isRevealed || _isShiftDragging ? 1.6 : 1,
            ),
            boxShadow: widget.isRevealed
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MouseRegion(
                    cursor: widget.onDragDelta == null
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => _handleDirectDragStart(),
                      onPanUpdate: (details) {
                        _handleDirectDragUpdate(details.delta);
                      },
                      onPanEnd: (_) => _handleDirectDragEnd(),
                      onPanCancel: _handleDirectDragEnd,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: showChrome ? 4 : 3,
                        constraints: const BoxConstraints(minHeight: 32),
                        decoration: BoxDecoration(
                          color: widget.isRevealed
                              ? theme.colorScheme.primary
                              : isTodo
                              ? todoColor
                              : presentation.accentColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 5, 7, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isTodo)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 4,
                                bottom: 6,
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isTodoCompleted,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged:
                                        widget.onTodoCompletedChanged == null
                                        ? null
                                        : (value) {
                                            widget.onTodoCompletedChanged!(
                                              value ?? false,
                                            );
                                          },
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.flag_outlined,
                                    size: 14,
                                    color: todoColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _todoPriority.toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: todoColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isTodoCompleted)
                                    Text(
                                      'Done',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          if (hasSelectedText)
                            LinkedSelectionPreview(
                              selectedText: selectedText,
                              compact: !showChrome,
                              pageNumber:
                                  widget.item.sidecarPlacement.pageNumber,
                              sourceIsCurrentPage: true,
                              onTap: widget.onJumpToSource,
                            ),
                          if (_localMetadata.tags.isNotEmpty && showChrome)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final tag in _localMetadata.tags.take(5))
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        tag,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (_isEditing)
                            Focus(
                              onKeyEvent: _handleEditorKeyEvent,
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                keyboardType: TextInputType.multiline,
                                minLines: 1,
                                maxLines: null,
                                onChanged: _onTextChanged,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Type here...',
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.25,
                                ),
                              ),
                            )
                          else
                            Text(
                              bodyTextTrimmed.isEmpty
                                  ? 'Click to write...'
                                  : bodyText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: bodyTextTrimmed.isEmpty
                                    ? theme.colorScheme.onSurfaceVariant
                                    : isTodoCompleted
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onSurface,
                                fontStyle: bodyTextTrimmed.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                decoration: isTodoCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                height: 1.25,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (showActionHeader)
                Positioned(
                  top: 4,
                  right: 6,
                  child: MouseRegion(
                    onEnter: (_) {
                      if (_isHovered) return;
                      setState(() {
                        _isHovered = true;
                      });
                    },
                    child: MarginNoteToolbar(
                      presentation: presentation,
                      currentType: _localNoteType,
                      showActions: true,
                      showMoveHandle:
                          widget.appSettings.sidecarDraggableHeaderEnabled,
                      onTypeChanged: _changeNoteType,
                      onArchive: widget.onArchive,
                      onEditDetails: _editDetails,
                      onDragStart: _handleDirectDragStart,
                      onDragDelta: _handleDirectDragUpdate,
                      onDragEnd: _handleDirectDragEnd,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

}

class _NoteDetailsDialog extends StatefulWidget {
  final NoteMetadata initialMetadata;
  final bool hasSourceAnchor;

  const _NoteDetailsDialog({
    required this.initialMetadata,
    required this.hasSourceAnchor,
  });

  @override
  State<_NoteDetailsDialog> createState() => _NoteDetailsDialogState();
}

class _NoteDetailsDialogState extends State<_NoteDetailsDialog> {
  late final TextEditingController _tagsController;
  late String _status;
  late String _importance;
  late bool _highlightEnabled;

  @override
  void initState() {
    super.initState();

    _tagsController = TextEditingController(
      text: widget.initialMetadata.tags.join(', '),
    );
    _status = widget.initialMetadata.status;
    _importance = widget.initialMetadata.importance;
    _highlightEnabled = widget.initialMetadata.highlightEnabled;
  }

  @override
  void dispose() {
    _tagsController.dispose();
    super.dispose();
  }

  List<String> _parseTags() {
    return _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  void _save() {
    Navigator.of(context).pop(
      NoteMetadata(
        tags: _parseTags(),
        status: _status,
        importance: _importance,
        highlightEnabled: _highlightEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Note details'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'methods, theory, important',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'open', child: Text('Open')),
                DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
              ],
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  _status = value;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _importance,
              decoration: const InputDecoration(labelText: 'Importance'),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'key', child: Text('Key')),
                DropdownMenuItem(value: 'low', child: Text('Low')),
              ],
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  _importance = value;
                });
              },
            ),
            if (widget.hasSourceAnchor) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show source highlight'),
                value: _highlightEnabled,
                onChanged: (value) {
                  setState(() {
                    _highlightEnabled = value;
                  });
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
