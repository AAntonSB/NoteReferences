import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/strategic_horizon.dart';

class StrategicPlanningDevScreen extends StatefulWidget {
  const StrategicPlanningDevScreen({super.key});

  @override
  State<StrategicPlanningDevScreen> createState() => _StrategicPlanningDevScreenState();
}

class _StrategicPlanningDevScreenState extends State<StrategicPlanningDevScreen> {
  static const double _monthWidth = 104;
  static const double _canvasHeight = 660;
  static const double _timelineHeaderHeight = 76;
  static const double _nodeHeight = 78;
  static const double _nodeMinWidth = 188;
  static const double _nodeHorizontalInset = 12;

  late final FutureMapTimeframe _timeframe;
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final List<FutureMapNode> _nodes = <FutureMapNode>[];
  final List<FutureMapConnection> _connections = <FutureMapConnection>[];
  String? _selectedNodeId;
  String? _connectionDraftFromId;

  @override
  void initState() {
    super.initState();
    _timeframe = FutureMapTimeframe.fiveYearsFrom(DateTime.now());
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  FutureMapNode? get _selectedNode {
    final selectedId = _selectedNodeId;
    if (selectedId == null) return null;
    for (final node in _nodes) {
      if (node.id == selectedId) return node;
    }
    return null;
  }

  FutureMapNode? _nodeById(String id) {
    for (final node in _nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<FutureMapNode> get _placedNodes => _nodes.where((node) => node.isPlaced).toList(growable: false);
  List<FutureMapNode> get _unplacedNodes => _nodes.where((node) => !node.isPlaced).toList(growable: false);

  double get _contentWidth => _timeframe.monthCount * _monthWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Future Map'),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_connectionDraftFromId != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: () => setState(() => _connectionDraftFromId = null),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel connection'),
              ),
            ),
          TextButton.icon(
            onPressed: _nodes.isEmpty && _connections.isEmpty ? null : _clearMap,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Clear'),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: () => _openNodeDialog(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create block'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, viewport) {
            final wide = viewport.maxWidth >= 1180;
            final horizontalPadding = viewport.maxWidth < 720 ? 12.0 : 20.0;
            final map = _FutureTimeframeCard(
              timeframe: _timeframe,
              nodes: _placedNodes,
              connections: _connections,
              selectedNodeId: _selectedNodeId,
              connectionDraftFromId: _connectionDraftFromId,
              contentWidth: _contentWidth,
              monthWidth: _monthWidth,
              headerHeight: _timelineHeaderHeight,
              canvasHeight: _canvasHeight,
              nodeHeight: _nodeHeight,
              nodeMinWidth: _nodeMinWidth,
              horizontalInset: _nodeHorizontalInset,
              horizontalController: _horizontalController,
              verticalController: _verticalController,
              onCreateAt: _openNodeDialogAt,
              onSelectNode: _handleNodeTap,
              onMoveNode: _moveNode,
              onEditNode: _openNodeDialog,
            );
            final inspector = _FutureMapInspector(
              node: _selectedNode,
              nodeCount: _nodes.length,
              connectionCount: _connections.length,
              connectionsForNode: _connectionsFor(_selectedNodeId),
              nodeTitleFor: (id) => _nodeById(id)?.title ?? 'Missing block',
              timeframe: _timeframe,
              connectionDraftFromId: _connectionDraftFromId,
              onCreate: () => _openNodeDialog(),
              onEdit: _selectedNode == null
                  ? null
                  : () {
                      _openNodeDialog(existing: _selectedNode);
                    },
              onDuplicate: _selectedNode == null ? null : () => _duplicateNode(_selectedNode!),
              onDelete: _selectedNode == null ? null : () => _deleteNode(_selectedNode!),
              onStartConnection: _selectedNode == null ? null : () => _startConnection(_selectedNode!),
              onCancelConnection: _connectionDraftFromId == null ? null : () => setState(() => _connectionDraftFromId = null),
              onPlaceNode: _selectedNode == null ? null : () => _placeNodeAtStart(_selectedNode!),
            );
            final tray = _UnplacedTrayCard(
              nodes: _unplacedNodes,
              selectedNodeId: _selectedNodeId,
              connectionDraftFromId: _connectionDraftFromId,
              onCreate: () => _openNodeDialog(),
              onSelectNode: _handleNodeTap,
              onEditNode: (node) => _openNodeDialog(existing: node),
              onPlaceNode: _placeNodeAtStart,
            );

            return ListView(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 28),
              children: [
                _FutureMapHeader(
                  timeframe: _timeframe,
                  nodeCount: _nodes.length,
                  connectionCount: _connections.length,
                  connectionDraftFrom: _connectionDraftFromId == null ? null : _nodeById(_connectionDraftFromId!)?.title,
                  onCreate: () => _openNodeDialog(),
                  onJumpToNow: _jumpToNow,
                ),
                const SizedBox(height: 16),
                tray,
                const SizedBox(height: 16),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: map),
                      const SizedBox(width: 16),
                      SizedBox(width: 380, child: inspector),
                    ],
                  )
                else ...[
                  map,
                  const SizedBox(height: 16),
                  inspector,
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<FutureMapConnection> _connectionsFor(String? nodeId) {
    if (nodeId == null) return const <FutureMapConnection>[];
    return _connections
        .where((connection) => connection.fromNodeId == nodeId || connection.toNodeId == nodeId)
        .toList(growable: false);
  }

  void _jumpToNow() {
    _horizontalController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _clearMap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear future map?'),
          content: const Text('This removes the in-memory blocks and connections on this dev screen. Nothing is persisted yet.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _nodes.clear();
      _connections.clear();
      _selectedNodeId = null;
      _connectionDraftFromId = null;
    });
  }

  void _handleNodeTap(FutureMapNode node) {
    final fromId = _connectionDraftFromId;
    if (fromId != null && fromId != node.id) {
      _openConnectionDialog(fromId: fromId, toId: node.id);
      return;
    }

    setState(() {
      _selectedNodeId = node.id;
      if (fromId == node.id) {
        _connectionDraftFromId = null;
      }
    });
  }

  void _startConnection(FutureMapNode node) {
    setState(() {
      _selectedNodeId = node.id;
      _connectionDraftFromId = node.id;
    });
  }

  Future<void> _openNodeDialogAt(Offset position) {
    final monthIndex = (position.dx / _monthWidth).floor().clamp(0, _timeframe.monthCount - 1).toInt();
    final y = (position.dy - _timelineHeaderHeight).clamp(20.0, _canvasHeight - _nodeHeight - 20);
    return _openNodeDialog(
      initialMonthIndex: monthIndex,
      initialY: y.toDouble(),
      initialTimeMode: FutureMapTimeMode.targetMonth,
    );
  }

  Future<void> _openNodeDialog({
    FutureMapNode? existing,
    int? initialMonthIndex,
    double? initialY,
    FutureMapTimeMode? initialTimeMode,
  }) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    var type = existing?.type ?? FutureMapNodeType.goal;
    var timeMode = existing?.timeMode ?? initialTimeMode ?? FutureMapTimeMode.unscheduled;
    var startMonthIndex = existing?.startMonth == null
        ? (initialMonthIndex ?? 0).clamp(0, _timeframe.monthCount - 1).toInt()
        : _timeframe.indexOf(existing!.startMonth!);
    var endMonthIndex = existing?.effectiveEndMonth == null
        ? math.min(_timeframe.monthCount - 1, startMonthIndex + 2).toInt()
        : _timeframe.indexOf(existing!.effectiveEndMonth!);

    final result = await showDialog<FutureMapNode>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedStart = _timeframe.monthAtIndex(startMonthIndex);
            final selectedEnd = _timeframe.monthAtIndex(math.max(startMonthIndex, endMonthIndex).toInt());
            return AlertDialog(
              title: Text(existing == null ? 'Create future block' : 'Edit future block'),
              content: SizedBox(
                width: 610,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        existing == null
                            ? 'Create a real block. It can stay unplaced until the timing is clearer, or it can be placed directly on the five-year timeframe.'
                            : 'Update this block. Timing is optional: future states and goals do not need fake precision.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'Example: Have kids, financially safe, stable housing...',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<FutureMapNodeType>(
                        value: type,
                        decoration: const InputDecoration(
                          labelText: 'Block type',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final value in FutureMapNodeType.values)
                            DropdownMenuItem<FutureMapNodeType>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => type = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        type.helperText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<FutureMapTimeMode>(
                        value: timeMode,
                        decoration: const InputDecoration(
                          labelText: 'Time placement',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final value in FutureMapTimeMode.values)
                            DropdownMenuItem<FutureMapTimeMode>(
                              value: value,
                              child: Text(value.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => timeMode = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timeMode.helperText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                      if (timeMode.isPlaced) ...[
                        const SizedBox(height: 12),
                        if (timeMode.usesRange)
                          Row(
                            children: [
                              Expanded(
                                child: _MonthDropdown(
                                  label: 'From',
                                  value: startMonthIndex,
                                  timeframe: _timeframe,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      startMonthIndex = value;
                                      if (endMonthIndex < startMonthIndex) {
                                        endMonthIndex = startMonthIndex;
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MonthDropdown(
                                  label: 'To',
                                  value: math.max(startMonthIndex, endMonthIndex).toInt(),
                                  timeframe: _timeframe,
                                  onChanged: (value) {
                                    setDialogState(() => endMonthIndex = math.max(startMonthIndex, value).toInt());
                                  },
                                ),
                              ),
                            ],
                          )
                        else
                          _MonthDropdown(
                            label: timeMode == FutureMapTimeMode.anchoredDate ? 'Fixed month' : 'Month',
                            value: startMonthIndex,
                            timeframe: _timeframe,
                            onChanged: (value) {
                              setDialogState(() {
                                startMonthIndex = value;
                                endMonthIndex = value;
                              });
                            },
                          ),
                        const SizedBox(height: 8),
                        Text(
                          timeMode.usesRange
                              ? '${timeMode.label}: ${selectedStart.fullLabel} → ${selectedEnd.fullLabel}.'
                              : '${timeMode.label}: ${selectedStart.fullLabel}.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'What belongs in this block? What should it represent?',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    final placed = timeMode.isPlaced;
                    final startMonth = placed ? _timeframe.monthAtIndex(startMonthIndex) : null;
                    final endMonth = placed && timeMode.usesRange
                        ? _timeframe.monthAtIndex(math.max(startMonthIndex, endMonthIndex).toInt())
                        : startMonth;
                    final x = placed ? (startMonthIndex * _monthWidth) + _nodeHorizontalInset : existing?.x ?? _nodeHorizontalInset;
                    final defaultY = 48.0 + ((_nodes.length % 6) * 94.0);
                    final node = FutureMapNode(
                      id: existing?.id ?? 'future-node-${DateTime.now().microsecondsSinceEpoch}',
                      type: type,
                      title: title,
                      notes: notesController.text.trim(),
                      timeMode: timeMode,
                      startMonth: startMonth,
                      endMonth: endMonth,
                      x: existing == null || existing.startMonth != startMonth ? x.toDouble() : existing.x,
                      y: existing?.y ?? (initialY ?? defaultY).clamp(20.0, _canvasHeight - _nodeHeight - 20).toDouble(),
                      createdAt: existing?.createdAt ?? DateTime.now(),
                    );
                    Navigator.of(dialogContext).pop(node);
                  },
                  child: Text(existing == null ? 'Create' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    notesController.dispose();

    if (result == null || !mounted) return;
    setState(() {
      final existingIndex = _nodes.indexWhere((node) => node.id == result.id);
      if (existingIndex == -1) {
        _nodes.add(result);
      } else {
        _nodes[existingIndex] = result;
      }
      _selectedNodeId = result.id;
    });
  }

  Future<void> _openConnectionDialog({required String fromId, required String toId}) async {
    final from = _nodeById(fromId);
    final to = _nodeById(toId);
    if (from == null || to == null) return;

    final labelController = TextEditingController();
    var type = FutureMapConnectionType.leadsTo;

    final result = await showDialog<FutureMapConnection>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Connect blocks'),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${from.title}  →  ${to.title}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<FutureMapConnectionType>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Connection type',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final value in FutureMapConnectionType.values)
                          DropdownMenuItem<FutureMapConnectionType>(
                            value: value,
                            child: Text(value.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => type = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      type.helperText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: 'Optional label',
                        hintText: type.label,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final connection = FutureMapConnection(
                      id: 'future-edge-${DateTime.now().microsecondsSinceEpoch}',
                      fromNodeId: fromId,
                      toNodeId: toId,
                      type: type,
                      label: labelController.text.trim(),
                      createdAt: DateTime.now(),
                    );
                    Navigator.of(dialogContext).pop(connection);
                  },
                  child: const Text('Connect'),
                ),
              ],
            );
          },
        );
      },
    );

    labelController.dispose();

    if (result == null || !mounted) return;
    setState(() {
      _connections.add(result);
      _selectedNodeId = toId;
      _connectionDraftFromId = null;
    });
  }

  void _moveNode(FutureMapNode node, Offset delta) {
    final index = _nodes.indexWhere((candidate) => candidate.id == node.id);
    if (index == -1) return;

    final previous = _nodes[index];
    if (!previous.isPlaced) return;
    final durationWidth = _nodeWidthFor(previous.durationMonths);
    final maxX = math.max(_nodeHorizontalInset, _contentWidth - durationWidth - _nodeHorizontalInset).toDouble();
    final rawX = (previous.x + delta.dx).clamp(_nodeHorizontalInset, maxX).toDouble();
    final snappedMonthIndex = ((rawX - _nodeHorizontalInset) / _monthWidth).round().clamp(0, _timeframe.monthCount - 1).toInt();
    final snappedX = (snappedMonthIndex * _monthWidth) + _nodeHorizontalInset;
    final y = (previous.y + delta.dy).clamp(20.0, _canvasHeight - _nodeHeight - 20).toDouble();
    final newStart = _timeframe.monthAtIndex(snappedMonthIndex);
    final newEnd = previous.timeMode.usesRange ? newStart.add(previous.durationMonths - 1) : newStart;

    setState(() {
      _nodes[index] = previous.copyWith(
        x: snappedX,
        y: y,
        startMonth: newStart,
        endMonth: newEnd,
      );
    });
  }

  double _nodeWidthFor(int durationMonths) {
    return math.max(_nodeMinWidth, (durationMonths * _monthWidth) - 18).toDouble();
  }

  void _placeNodeAtStart(FutureMapNode node) {
    final index = _nodes.indexWhere((candidate) => candidate.id == node.id);
    if (index == -1) return;
    setState(() {
      _nodes[index] = node.copyWith(
        timeMode: FutureMapTimeMode.targetMonth,
        startMonth: _timeframe.start,
        endMonth: _timeframe.start,
        x: _nodeHorizontalInset,
        y: node.y.clamp(20.0, _canvasHeight - _nodeHeight - 20).toDouble(),
      );
      _selectedNodeId = node.id;
    });
  }

  void _duplicateNode(FutureMapNode node) {
    final copiedStart = node.startMonth == null ? null : node.startMonth!.add(1);
    final copiedEnd = node.effectiveEndMonth == null ? null : node.effectiveEndMonth!.add(1);
    final placedCopyFits = copiedStart != null && _timeframe.contains(copiedStart);
    final copy = FutureMapNode(
      id: 'future-node-${DateTime.now().microsecondsSinceEpoch}',
      type: node.type,
      title: '${node.title} copy',
      notes: node.notes,
      timeMode: placedCopyFits ? node.timeMode : FutureMapTimeMode.unscheduled,
      startMonth: placedCopyFits ? copiedStart : null,
      endMonth: placedCopyFits && copiedEnd != null && _timeframe.contains(copiedEnd) ? copiedEnd : copiedStart,
      x: placedCopyFits ? math.min(_contentWidth - _nodeMinWidth, node.x + _monthWidth).toDouble() : node.x,
      y: (node.y + 28).clamp(20.0, _canvasHeight - _nodeHeight - 20).toDouble(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _nodes.add(copy);
      _selectedNodeId = copy.id;
    });
  }

  void _deleteNode(FutureMapNode node) {
    setState(() {
      _nodes.removeWhere((candidate) => candidate.id == node.id);
      _connections.removeWhere((connection) => connection.fromNodeId == node.id || connection.toNodeId == node.id);
      if (_connectionDraftFromId == node.id) _connectionDraftFromId = null;
      _selectedNodeId = _nodes.isEmpty ? null : _nodes.last.id;
    });
  }
}

class _FutureMapHeader extends StatelessWidget {
  final FutureMapTimeframe timeframe;
  final int nodeCount;
  final int connectionCount;
  final String? connectionDraftFrom;
  final VoidCallback onCreate;
  final VoidCallback onJumpToNow;

  const _FutureMapHeader({
    required this.timeframe,
    required this.nodeCount,
    required this.connectionCount,
    required this.connectionDraftFrom,
    required this.onCreate,
    required this.onJumpToNow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _FutureCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconBadge(icon: Icons.account_tree_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Future Map foundation',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${timeframe.label} · $nodeCount block${nodeCount == 1 ? '' : 's'} · $connectionCount connection${connectionCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Create goals, future states, conditions, steps, fallbacks, obstacles, life events, and reviews. Timing is optional: unclear futures can stay unplaced until you know where they belong.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              if (connectionDraftFrom != null) ...[
                const SizedBox(height: 12),
                _InlineStatus(
                  icon: Icons.route_rounded,
                  text: 'Connecting from “$connectionDraftFrom”. Click another block to choose the target.',
                ),
              ],
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: onJumpToNow,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Now'),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create block'),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 16),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 24),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _UnplacedTrayCard extends StatelessWidget {
  final List<FutureMapNode> nodes;
  final String? selectedNodeId;
  final String? connectionDraftFromId;
  final VoidCallback onCreate;
  final ValueChanged<FutureMapNode> onSelectNode;
  final ValueChanged<FutureMapNode> onEditNode;
  final ValueChanged<FutureMapNode> onPlaceNode;

  const _UnplacedTrayCard({
    required this.nodes,
    required this.selectedNodeId,
    required this.connectionDraftFromId,
    required this.onCreate,
    required this.onSelectNode,
    required this.onEditNode,
    required this.onPlaceNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FutureCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconBadge(icon: Icons.inventory_2_outlined, color: theme.colorScheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unplaced futures',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Use this tray for goals and future states whose timing is still unclear.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (nodes.isEmpty)
            Text(
              'No unplaced blocks yet. Create a Goal or Future state and leave it as “Not placed yet” when the timing is not realistic to know.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final node in nodes)
                  _UnplacedNodeChip(
                    node: node,
                    selected: node.id == selectedNodeId,
                    connectingFrom: node.id == connectionDraftFromId,
                    onTap: () => onSelectNode(node),
                    onEdit: () => onEditNode(node),
                    onPlace: () => onPlaceNode(node),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _UnplacedNodeChip extends StatelessWidget {
  final FutureMapNode node;
  final bool selected;
  final bool connectingFrom;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPlace;

  const _UnplacedNodeChip({
    required this.node,
    required this.selected,
    required this.connectingFrom,
    required this.onTap,
    required this.onEdit,
    required this.onPlace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _nodeColor(theme, node.type);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onDoubleTap: onEdit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 290,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(36) : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: connectingFrom ? theme.colorScheme.primary : selected ? accent : theme.colorScheme.outlineVariant,
            width: selected || connectingFrom ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(_nodeIcon(node.type), color: accent, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${node.type.label} · Not placed yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'place') onPlace();
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                PopupMenuItem<String>(value: 'place', child: Text('Place at now')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FutureTimeframeCard extends StatelessWidget {
  final FutureMapTimeframe timeframe;
  final List<FutureMapNode> nodes;
  final List<FutureMapConnection> connections;
  final String? selectedNodeId;
  final String? connectionDraftFromId;
  final double contentWidth;
  final double monthWidth;
  final double headerHeight;
  final double canvasHeight;
  final double nodeHeight;
  final double nodeMinWidth;
  final double horizontalInset;
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final ValueChanged<Offset> onCreateAt;
  final ValueChanged<FutureMapNode> onSelectNode;
  final void Function(FutureMapNode node, Offset delta) onMoveNode;
  final Future<void> Function({FutureMapNode? existing, int? initialMonthIndex, double? initialY, FutureMapTimeMode? initialTimeMode}) onEditNode;

  const _FutureTimeframeCard({
    required this.timeframe,
    required this.nodes,
    required this.connections,
    required this.selectedNodeId,
    required this.connectionDraftFromId,
    required this.contentWidth,
    required this.monthWidth,
    required this.headerHeight,
    required this.canvasHeight,
    required this.nodeHeight,
    required this.nodeMinWidth,
    required this.horizontalInset,
    required this.horizontalController,
    required this.verticalController,
    required this.onCreateAt,
    required this.onSelectNode,
    required this.onMoveNode,
    required this.onEditNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalHeight = headerHeight + canvasHeight;

    return _FutureCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Timeframe canvas',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Double-click empty space to create a placed block. Drag blocks to reposition them. Use Connect from the inspector to draw arrows.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _LegendPill(icon: Icons.account_tree_rounded, label: 'Click target to connect'),
              ],
            ),
          ),
          const Divider(height: 1),
          Scrollbar(
            controller: horizontalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: horizontalController,
              scrollDirection: Axis.horizontal,
              child: Scrollbar(
                controller: verticalController,
                notificationPredicate: (notification) => notification.depth == 1,
                child: SingleChildScrollView(
                  controller: verticalController,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTapDown: (details) => onCreateAt(details.localPosition),
                    child: SizedBox(
                      width: contentWidth,
                      height: totalHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _TimeGrid(
                            timeframe: timeframe,
                            monthWidth: monthWidth,
                            headerHeight: headerHeight,
                            canvasHeight: canvasHeight,
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _ConnectionPainter(
                                  nodes: nodes,
                                  connections: connections,
                                  selectedNodeId: selectedNodeId,
                                  connectionDraftFromId: connectionDraftFromId,
                                  headerHeight: headerHeight,
                                  nodeHeight: nodeHeight,
                                  nodeMinWidth: nodeMinWidth,
                                  monthWidth: monthWidth,
                                  theme: theme,
                                ),
                              ),
                            ),
                          ),
                          if (nodes.isEmpty)
                            Positioned(
                              left: 34,
                              top: headerHeight + 44,
                              child: _EmptyMapHint(onCreate: () => onCreateAt(Offset(34, headerHeight + 72))),
                            ),
                          for (final node in nodes)
                            Positioned(
                              left: node.x,
                              top: headerHeight + node.y,
                              width: math.max(nodeMinWidth, (node.durationMonths * monthWidth) - 18).toDouble(),
                              height: nodeHeight,
                              child: _FutureNodeCard(
                                node: node,
                                selected: node.id == selectedNodeId,
                                connectingFrom: node.id == connectionDraftFromId,
                                onSelect: () => onSelectNode(node),
                                onEdit: () {
                                  onEditNode(existing: node);
                                },
                                onMove: (delta) => onMoveNode(node, delta),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeGrid extends StatelessWidget {
  final FutureMapTimeframe timeframe;
  final double monthWidth;
  final double headerHeight;
  final double canvasHeight;

  const _TimeGrid({
    required this.timeframe,
    required this.monthWidth,
    required this.headerHeight,
    required this.canvasHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = timeframe.months;
    final yearGroups = <_YearSpan>[];
    var index = 0;
    while (index < months.length) {
      final year = months[index].year;
      final start = index;
      while (index < months.length && months[index].year == year) {
        index++;
      }
      yearGroups.add(_YearSpan(year: year, startIndex: start, count: index - start));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: theme.colorScheme.surface),
        ),
        for (var i = 0; i < months.length; i++) ...[
          Positioned(
            left: i * monthWidth,
            top: 0,
            width: monthWidth,
            height: headerHeight + canvasHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: i == 0
                    ? theme.colorScheme.primaryContainer.withAlpha(46)
                    : months[i].month == 1
                        ? theme.colorScheme.surfaceContainerHighest.withAlpha(90)
                        : Colors.transparent,
                border: Border(
                  right: BorderSide(
                    color: months[i].month == 1
                        ? theme.colorScheme.outlineVariant.withAlpha(210)
                        : theme.colorScheme.outlineVariant.withAlpha(105),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: i * monthWidth,
            top: 36,
            width: monthWidth,
            height: headerHeight - 36,
            child: Center(
              child: Text(
                months[i].compactLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: i == 0 ? FontWeight.w900 : FontWeight.w700,
                  color: i == 0 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
        for (final group in yearGroups)
          Positioned(
            left: group.startIndex * monthWidth,
            top: 0,
            width: group.count * monthWidth,
            height: 36,
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outlineVariant),
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Text(
                '${group.year}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          top: headerHeight,
          width: monthWidth,
          height: canvasHeight,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 3),
                ),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  margin: const EdgeInsets.only(left: 8, top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'NOW',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        for (var y = 120.0; y < canvasHeight; y += 120)
          Positioned(
            left: 0,
            top: headerHeight + y,
            right: 0,
            child: Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant.withAlpha(85),
            ),
          ),
      ],
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  final List<FutureMapNode> nodes;
  final List<FutureMapConnection> connections;
  final String? selectedNodeId;
  final String? connectionDraftFromId;
  final double headerHeight;
  final double nodeHeight;
  final double nodeMinWidth;
  final double monthWidth;
  final ThemeData theme;

  _ConnectionPainter({
    required this.nodes,
    required this.connections,
    required this.selectedNodeId,
    required this.connectionDraftFromId,
    required this.headerHeight,
    required this.nodeHeight,
    required this.nodeMinWidth,
    required this.monthWidth,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final byId = <String, FutureMapNode>{for (final node in nodes) node.id: node};
    for (final connection in connections) {
      final from = byId[connection.fromNodeId];
      final to = byId[connection.toNodeId];
      if (from == null || to == null) continue;
      _paintConnection(canvas, from, to, connection);
    }
  }

  void _paintConnection(Canvas canvas, FutureMapNode from, FutureMapNode to, FutureMapConnection connection) {
    final color = _connectionColor(theme, connection.type).withAlpha(
      from.id == selectedNodeId || to.id == selectedNodeId ? 235 : 145,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = from.id == selectedNodeId || to.id == selectedNodeId ? 2.8 : 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fromWidth = math.max(nodeMinWidth, (from.durationMonths * monthWidth) - 18).toDouble();
    final toWidth = math.max(nodeMinWidth, (to.durationMonths * monthWidth) - 18).toDouble();
    final fromOnLeft = from.x + fromWidth / 2 <= to.x + toWidth / 2;
    final start = Offset(
      fromOnLeft ? from.x + fromWidth : from.x,
      headerHeight + from.y + nodeHeight / 2,
    );
    final end = Offset(
      fromOnLeft ? to.x : to.x + toWidth,
      headerHeight + to.y + nodeHeight / 2,
    );
    final distance = (end.dx - start.dx).abs();
    final bend = math.max(42.0, math.min(140.0, distance * 0.35)).toDouble();
    final cp1 = Offset(start.dx + (fromOnLeft ? bend : -bend), start.dy);
    final cp2 = Offset(end.dx - (fromOnLeft ? bend : -bend), end.dy);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    if (connection.type.isDashed) {
      _drawDashedPath(canvas, path, paint);
    } else {
      canvas.drawPath(path, paint);
    }
    _drawArrowHead(canvas, start, end, color);

    final label = connection.label.isEmpty ? connection.type.label : connection.label;
    if (label.isNotEmpty) {
      final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2 - 12);
      final paragraphStyle = TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      );
      final painter = TextPainter(
        text: TextSpan(text: label, style: paragraphStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 130);
      final rect = Rect.fromLTWH(midpoint.dx - painter.width / 2 - 6, midpoint.dy - 4, painter.width + 12, painter.height + 8);
      final background = Paint()..color = theme.colorScheme.surface.withAlpha(215);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(999)), background);
      painter.paint(canvas, Offset(midpoint.dx - painter.width / 2, midpoint.dy));
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 10.0;
      const gap = 7.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final tip = end;
    const size = 8.0;
    final p1 = Offset(
      tip.dx - size * math.cos(angle - math.pi / 6),
      tip.dy - size * math.sin(angle - math.pi / 6),
    );
    final p2 = Offset(
      tip.dx - size * math.cos(angle + math.pi / 6),
      tip.dy - size * math.sin(angle + math.pi / 6),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.connections != connections ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.connectionDraftFromId != connectionDraftFromId ||
        oldDelegate.theme != theme;
  }
}

class _FutureNodeCard extends StatelessWidget {
  final FutureMapNode node;
  final bool selected;
  final bool connectingFrom;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final ValueChanged<Offset> onMove;

  const _FutureNodeCard({
    required this.node,
    required this.selected,
    required this.connectingFrom,
    required this.onSelect,
    required this.onEdit,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _nodeColor(theme, node.type);

    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onEdit,
      onPanStart: (_) => onSelect(),
      onPanUpdate: (details) => onMove(details.delta),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(42) : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: connectingFrom ? theme.colorScheme.primary : selected ? accent : theme.colorScheme.outlineVariant,
            width: selected || connectingFrom ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(selected || connectingFrom ? 30 : 16),
              blurRadius: selected || connectingFrom ? 24 : 14,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withAlpha(32),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_nodeIcon(node.type), size: 20, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${node.type.label} · ${_timeText(node)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.drag_indicator_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant.withAlpha(160)),
          ],
        ),
      ),
    );
  }

  String _timeText(FutureMapNode node) {
    final start = node.startMonth;
    if (start == null) return 'Not placed yet';
    if (!node.timeMode.usesRange || node.durationMonths == 1) return '${node.timeMode.label}: ${start.fullLabel}';
    return '${node.timeMode.label}: ${start.fullLabel} → ${node.effectiveEndMonth?.fullLabel ?? start.fullLabel}';
  }
}

class _FutureMapInspector extends StatelessWidget {
  final FutureMapNode? node;
  final int nodeCount;
  final int connectionCount;
  final List<FutureMapConnection> connectionsForNode;
  final String Function(String id) nodeTitleFor;
  final FutureMapTimeframe timeframe;
  final String? connectionDraftFromId;
  final VoidCallback onCreate;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onStartConnection;
  final VoidCallback? onCancelConnection;
  final VoidCallback? onPlaceNode;

  const _FutureMapInspector({
    required this.node,
    required this.nodeCount,
    required this.connectionCount,
    required this.connectionsForNode,
    required this.nodeTitleFor,
    required this.timeframe,
    required this.connectionDraftFromId,
    required this.onCreate,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onStartConnection,
    required this.onCancelConnection,
    required this.onPlaceNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = node;

    return _FutureCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconBadge(icon: Icons.info_outline_rounded, color: theme.colorScheme.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selected == null ? 'Map inspector' : 'Selected block',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (selected == null) ...[
            Text(
              nodeCount == 0
                  ? 'The map is empty. Create a Goal first, leave it unplaced if the timing is unclear, then connect conditions and steps as the structure becomes clearer.'
                  : 'Select a block to inspect, edit, connect, duplicate, or place it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create first block'),
            ),
          ] else ...[
            _TypeHeader(node: selected),
            const SizedBox(height: 14),
            _InspectorRow(label: 'Time', value: _timeLabel(selected)),
            _InspectorRow(label: 'Mode', value: selected.timeMode.label),
            _InspectorRow(label: 'Links', value: '${connectionsForNode.length} related connection${connectionsForNode.length == 1 ? '' : 's'}'),
            if (selected.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Notes',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                selected.notes,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'No notes yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (connectionsForNode.isNotEmpty) ...[
              Text(
                'Connections',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final connection in connectionsForNode.take(5))
                _ConnectionSummary(
                  connection: connection,
                  selectedNodeId: selected.id,
                  nodeTitleFor: nodeTitleFor,
                ),
              if (connectionsForNode.length > 5)
                Text(
                  '+${connectionsForNode.length - 5} more',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: onStartConnection,
                  icon: const Icon(Icons.route_rounded),
                  label: const Text('Connect from this'),
                ),
                if (!selected.isPlaced)
                  OutlinedButton.icon(
                    onPressed: onPlaceNode,
                    icon: const Icon(Icons.place_rounded),
                    label: const Text('Place at now'),
                  ),
                OutlinedButton.icon(
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Duplicate'),
                ),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ),
            if (connectionDraftFromId != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onCancelConnection,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel connection mode'),
              ),
            ],
          ],
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Current foundation',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          _RoadmapBullet(text: '$nodeCount block${nodeCount == 1 ? '' : 's'} in memory.'),
          _RoadmapBullet(text: '$connectionCount connection${connectionCount == 1 ? '' : 's'} in memory.'),
          const _RoadmapBullet(text: 'Persistence comes after the interaction model feels right.'),
        ],
      ),
    );
  }

  String _timeLabel(FutureMapNode node) {
    final start = node.startMonth;
    if (start == null) return 'Not placed yet';
    if (!node.timeMode.usesRange || node.durationMonths == 1) return start.fullLabel;
    return '${start.fullLabel} → ${node.effectiveEndMonth?.fullLabel ?? start.fullLabel}';
  }
}

class _ConnectionSummary extends StatelessWidget {
  final FutureMapConnection connection;
  final String selectedNodeId;
  final String Function(String id) nodeTitleFor;

  const _ConnectionSummary({
    required this.connection,
    required this.selectedNodeId,
    required this.nodeTitleFor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outgoing = connection.fromNodeId == selectedNodeId;
    final otherTitle = nodeTitleFor(outgoing ? connection.toNodeId : connection.fromNodeId);
    final color = _connectionColor(theme, connection.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(outgoing ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded, size: 17, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${outgoing ? connection.type.label : 'From'}: $otherTitle',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeHeader extends StatelessWidget {
  final FutureMapNode node;

  const _TypeHeader({required this.node});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _nodeColor(theme, node.type);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_nodeIcon(node.type), color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  node.type.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  final String label;
  final String value;

  const _InspectorRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthDropdown extends StatelessWidget {
  final String label;
  final int value;
  final FutureMapTimeframe timeframe;
  final ValueChanged<int> onChanged;

  const _MonthDropdown({
    required this.label,
    required this.value,
    required this.timeframe,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (var i = 0; i < timeframe.monthCount; i++)
          DropdownMenuItem<int>(
            value: i,
            child: Text(timeframe.monthAtIndex(i).fullLabel),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }
}

class _EmptyMapHint extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyMapHint({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 440,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withAlpha(235),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _IconBadge(icon: Icons.add_road_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Place something on the timeframe',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Double-click here to create a placed block, or create an unplaced Goal in the tray above when the timing is still unclear.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create placed block'),
          ),
        ],
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineStatus({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(140),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LegendPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _RoadmapBullet extends StatelessWidget {
  final String text;

  const _RoadmapBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FutureCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool clip;

  const _FutureCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(170)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _YearSpan {
  final int year;
  final int startIndex;
  final int count;

  const _YearSpan({required this.year, required this.startIndex, required this.count});
}

IconData _nodeIcon(FutureMapNodeType type) {
  switch (type) {
    case FutureMapNodeType.goal:
      return Icons.flag_rounded;
    case FutureMapNodeType.futureState:
      return Icons.auto_awesome_rounded;
    case FutureMapNodeType.condition:
      return Icons.checklist_rtl_rounded;
    case FutureMapNodeType.step:
      return Icons.directions_walk_rounded;
    case FutureMapNodeType.fallback:
      return Icons.alt_route_rounded;
    case FutureMapNodeType.obstacle:
      return Icons.warning_amber_rounded;
    case FutureMapNodeType.lifeEvent:
      return Icons.favorite_rounded;
    case FutureMapNodeType.review:
      return Icons.rate_review_rounded;
  }
}

Color _nodeColor(ThemeData theme, FutureMapNodeType type) {
  switch (type) {
    case FutureMapNodeType.goal:
      return theme.colorScheme.primary;
    case FutureMapNodeType.futureState:
      return Colors.deepPurple;
    case FutureMapNodeType.condition:
      return theme.colorScheme.tertiary;
    case FutureMapNodeType.step:
      return theme.colorScheme.secondary;
    case FutureMapNodeType.fallback:
      return Colors.indigo;
    case FutureMapNodeType.obstacle:
      return theme.colorScheme.error;
    case FutureMapNodeType.lifeEvent:
      return Colors.pink;
    case FutureMapNodeType.review:
      return Colors.teal;
  }
}

Color _connectionColor(ThemeData theme, FutureMapConnectionType type) {
  switch (type) {
    case FutureMapConnectionType.leadsTo:
      return theme.colorScheme.primary;
    case FutureMapConnectionType.requires:
      return Colors.deepPurple;
    case FutureMapConnectionType.supports:
      return Colors.teal;
    case FutureMapConnectionType.blocks:
      return theme.colorScheme.error;
    case FutureMapConnectionType.threatens:
      return Colors.orange;
    case FutureMapConnectionType.fallbackIfFailed:
      return Colors.indigo;
    case FutureMapConnectionType.alternativePath:
      return Colors.blueGrey;
    case FutureMapConnectionType.reviewAfter:
      return Colors.cyan;
    case FutureMapConnectionType.partOf:
      return theme.colorScheme.tertiary;
  }
}
