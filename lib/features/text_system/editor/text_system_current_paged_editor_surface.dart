import 'package:flutter/material.dart';

import '../core/text_system_controller.dart';
import '../core/text_system_document.dart';
import '../page/text_system_page_furniture.dart';
import '../page/text_system_page_setup.dart';
import '../page/text_system_paged_block_surface.dart';
import '../references/actions/text_system_reference_actions.dart';
import '../todos/text_system_embedded_todo.dart';

/// Stable entry point for the current production writer surface.
///
/// This adapter deliberately keeps the existing `TextField`-backed real-page
/// editor alive while the owned document editor is built beside it. New editor
/// work should depend on the `editor/` package boundary rather than importing
/// the large page-level implementation directly from application shells.
///
/// The wrapped implementation still owns the current editing behavior:
/// caret/selection restoration, per-fragment text fields, object interactions,
/// page furniture, references, footnotes, embedded TODOs, and margin comments.
class TextSystemCurrentPagedEditorSurface extends StatelessWidget {
  const TextSystemCurrentPagedEditorSurface({
    super.key,
    required this.textController,
    required this.document,
    required this.pageSetup,
    required this.pageMaxWidth,
    this.pageZoom = 1.0,
    this.onPageZoomChanged,
    this.pageFurniture = const TextSystemPageFurniture.defaults(),
    this.onPageFurnitureChanged,
    required this.focusMode,
    this.showMarginGuides = true,
    this.showMarginMarkers = false,
    this.showMarginAnnotations = true,
    this.showSurfaceToolbar = true,
    this.editable = true,
    this.scrollController,
    this.commandController,
    this.referenceActionRepository,
    this.embeddedTodoRepository,
    this.onOpenReferenceTarget,
  });

  final TextSystemController textController;
  final TextSystemDocument document;
  final TextSystemPageSetup pageSetup;
  final double pageMaxWidth;
  final double pageZoom;
  final ValueChanged<double>? onPageZoomChanged;
  final TextSystemPageFurniture pageFurniture;
  final ValueChanged<TextSystemPageFurniture>? onPageFurnitureChanged;
  final bool focusMode;
  final bool showMarginGuides;
  final bool showMarginMarkers;
  final bool showMarginAnnotations;
  final bool showSurfaceToolbar;
  final bool editable;
  final ScrollController? scrollController;
  final TextSystemPagedBlockCommandController? commandController;
  final TextSystemReferenceActionRepository? referenceActionRepository;
  final TextSystemEmbeddedTodoRepository? embeddedTodoRepository;
  final ValueChanged<TextSystemInlineReferenceMark>? onOpenReferenceTarget;

  @override
  Widget build(BuildContext context) {
    return TextSystemPagedBlockSurface(
      textController: textController,
      document: document,
      pageSetup: pageSetup,
      pageFurniture: pageFurniture,
      onPageFurnitureChanged: onPageFurnitureChanged,
      pageMaxWidth: pageMaxWidth,
      pageZoom: pageZoom,
      onPageZoomChanged: onPageZoomChanged,
      focusMode: focusMode,
      showMarginGuides: showMarginGuides,
      showMarginMarkers: showMarginMarkers,
      showMarginAnnotations: showMarginAnnotations,
      showSurfaceToolbar: showSurfaceToolbar,
      editable: editable,
      scrollController: scrollController,
      commandController: commandController,
      referenceActionRepository: referenceActionRepository,
      embeddedTodoRepository: embeddedTodoRepository,
      onOpenReferenceTarget: onOpenReferenceTarget,
    );
  }
}
