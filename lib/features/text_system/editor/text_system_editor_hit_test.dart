import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/text_system_document_layout_index.dart';
import '../core/text_system_document_position.dart';
import 'text_system_editor_layout_snapshot.dart';

/// Editor-level target categories produced by hit testing.
///
/// These categories are intentionally broader than layout fragment kinds. The
/// owned editor can decide caret placement, object selection, drag behavior, and
/// toolbar state from these stable targets without knowing how the legacy paged
/// surface represents widgets internally.
enum TextSystemEditorHitTargetKind {
  none,
  page,
  text,
  inlineAtom,
  objectBlock,
  tableCell,
  structuralBreak,
  pageMargin,
  commentRail,
}

@immutable
class TextSystemEditorHitTestResult {
  const TextSystemEditorHitTestResult({
    required this.kind,
    required this.globalOffset,
    this.layoutHit,
    this.pageIndex,
    this.metadata = const <String, Object?>{},
  });

  factory TextSystemEditorHitTestResult.none(Offset globalOffset) {
    return TextSystemEditorHitTestResult(
      kind: TextSystemEditorHitTargetKind.none,
      globalOffset: globalOffset,
    );
  }

  factory TextSystemEditorHitTestResult.page({
    required Offset globalOffset,
    required int pageIndex,
  }) {
    return TextSystemEditorHitTestResult(
      kind: TextSystemEditorHitTargetKind.page,
      globalOffset: globalOffset,
      pageIndex: pageIndex,
    );
  }

  factory TextSystemEditorHitTestResult.fromLayoutHit(
    TextSystemDocumentLayoutHit hit,
  ) {
    final fragment = hit.fragment;
    return TextSystemEditorHitTestResult(
      kind: _kindForFragment(fragment),
      globalOffset: hit.globalOffset,
      layoutHit: hit,
      pageIndex: fragment.pageIndex,
      metadata: <String, Object?>{
        'fragmentId': fragment.id,
        'fragmentKind': fragment.kind.name,
        'isExactHit': hit.isExactHit,
      },
    );
  }

  final TextSystemEditorHitTargetKind kind;
  final Offset globalOffset;
  final TextSystemDocumentLayoutHit? layoutHit;
  final int? pageIndex;
  final Map<String, Object?> metadata;

  TextSystemDocumentPosition? get position => layoutHit?.position;
  TextSystemDocumentLayoutFragment? get fragment => layoutHit?.fragment;

  bool get hasDocumentPosition => position != null;
  bool get isNone => kind == TextSystemEditorHitTargetKind.none;
  bool get isText => kind == TextSystemEditorHitTargetKind.text;
  bool get isObjectLike =>
      kind == TextSystemEditorHitTargetKind.objectBlock ||
      kind == TextSystemEditorHitTargetKind.structuralBreak;
  bool get isInlineAtom => kind == TextSystemEditorHitTargetKind.inlineAtom;
  bool get isTableCell => kind == TextSystemEditorHitTargetKind.tableCell;

  Map<String, Object?> toDiagnosticsJson() {
    return <String, Object?>{
      'kind': kind.name,
      'globalOffset': <String, Object?>{
        'dx': globalOffset.dx,
        'dy': globalOffset.dy,
      },
      if (pageIndex != null) 'pageIndex': pageIndex,
      if (position != null) 'position': position!.toJson(),
      if (fragment != null) 'fragment': fragment!.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Stateless adapter from pointer/surface coordinates to editor hit targets.
class TextSystemEditorHitTester {
  const TextSystemEditorHitTester({
    required this.snapshot,
    this.defaultTolerance = 8.0,
  });

  final TextSystemEditorLayoutSnapshot snapshot;
  final double defaultTolerance;

  TextSystemEditorHitTestResult hitTest(
    Offset globalOffset, {
    double? tolerance,
  }) {
    final layoutHit = snapshot.layoutIndex.hitAtGlobalOffset(
      globalOffset,
      tolerance: tolerance ?? defaultTolerance,
    );
    if (layoutHit != null) {
      return TextSystemEditorHitTestResult.fromLayoutHit(layoutHit);
    }

    for (final page in snapshot.layoutIndex.pages) {
      if (page.containsGlobalOffset(globalOffset)) {
        return TextSystemEditorHitTestResult.page(
          globalOffset: globalOffset,
          pageIndex: page.pageIndex,
        );
      }
    }

    return TextSystemEditorHitTestResult.none(globalOffset);
  }
}

TextSystemEditorHitTargetKind _kindForFragment(
  TextSystemDocumentLayoutFragment fragment,
) {
  switch (fragment.kind) {
    case TextSystemDocumentLayoutFragmentKind.textLine:
    case TextSystemDocumentLayoutFragmentKind.textRun:
      return TextSystemEditorHitTargetKind.text;
    case TextSystemDocumentLayoutFragmentKind.inlineAtom:
      return TextSystemEditorHitTargetKind.inlineAtom;
    case TextSystemDocumentLayoutFragmentKind.tableCell:
      return TextSystemEditorHitTargetKind.tableCell;
    case TextSystemDocumentLayoutFragmentKind.figure:
    case TextSystemDocumentLayoutFragmentKind.table:
    case TextSystemDocumentLayoutFragmentKind.equation:
    case TextSystemDocumentLayoutFragmentKind.objectBlock:
      return TextSystemEditorHitTargetKind.objectBlock;
    case TextSystemDocumentLayoutFragmentKind.pageBreak:
    case TextSystemDocumentLayoutFragmentKind.sectionBreak:
      return TextSystemEditorHitTargetKind.structuralBreak;
    case TextSystemDocumentLayoutFragmentKind.pageMargin:
      return TextSystemEditorHitTargetKind.pageMargin;
    case TextSystemDocumentLayoutFragmentKind.commentRail:
      return TextSystemEditorHitTargetKind.commentRail;
    case TextSystemDocumentLayoutFragmentKind.page:
      return TextSystemEditorHitTargetKind.page;
    case TextSystemDocumentLayoutFragmentKind.unknown:
      return TextSystemEditorHitTargetKind.none;
  }
}
