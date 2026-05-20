import 'package:flutter/foundation.dart';

import 'reader_anchor.dart';

@immutable
class ReaderSidecarBridgeState {
  final ReaderAnchor currentAnchor;
  final List<ReaderAnchor> visibleAnchors;
  final bool canCreateNote;
  final bool canCreateTodo;
  final bool canPlanWork;

  const ReaderSidecarBridgeState({
    required this.currentAnchor,
    this.visibleAnchors = const <ReaderAnchor>[],
    this.canCreateNote = false,
    this.canCreateTodo = false,
    this.canPlanWork = false,
  });

  ReaderSidecarBridgeState copyWith({
    ReaderAnchor? currentAnchor,
    List<ReaderAnchor>? visibleAnchors,
    bool? canCreateNote,
    bool? canCreateTodo,
    bool? canPlanWork,
  }) {
    return ReaderSidecarBridgeState(
      currentAnchor: currentAnchor ?? this.currentAnchor,
      visibleAnchors: visibleAnchors ?? this.visibleAnchors,
      canCreateNote: canCreateNote ?? this.canCreateNote,
      canCreateTodo: canCreateTodo ?? this.canCreateTodo,
      canPlanWork: canPlanWork ?? this.canPlanWork,
    );
  }
}
