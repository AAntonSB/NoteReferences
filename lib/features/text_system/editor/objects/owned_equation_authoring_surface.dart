import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'owned_equation_source_model.dart';
import 'owned_equation_structure_model.dart';
import 'owned_equation_tool_registry.dart';

/// Focused authoring surface for display equations in the owned Premium Writer.
///
/// The document still owns the LaTeX source and the parent editor still owns
/// input/selection. This widget owns the active visual environment: source
/// structure, syntax colour, quick authoring affordances, and a debounced live
/// rendered preview. Keeping the active surface separate from the rendered
/// document equation prevents display math from feeling like a stretched
/// paragraph or an object card.
class OwnedEquationAuthoringSurface extends StatefulWidget {
  const OwnedEquationAuthoringSurface({
    super.key,
    required this.sourceText,
    required this.sourceSpan,
    required this.sourceTextStyle,
    required this.previewTextStyle,
    required this.textScaler,
    this.numbered = false,
    this.numberLabel,
    this.equationLabel,
    this.onToggleNumbered,
    this.onEditLabel,
    this.onCopyReference,
    this.onInsertFraction,
    this.onInsertSuperscript,
    this.onInsertSubscript,
    this.onInsertText,
    this.onInsertDerivative,
    this.onInsertMatrix,
    this.onInsertAligned,
    this.onInsertCases,
    this.onInsertMatrixRow,
    this.onInsertMatrixColumn,
    this.onInsertAlignedLine,
    this.onInsertAlignmentMarker,
    this.onInsertCasesRow,
    this.structureContext,
    this.onInsertSymbol,
    this.onFormatSource,
    this.onJumpNextSlot,
    this.onJumpPreviousSlot,
    this.activeSourceOffset,
    this.activeSourceRangeStart,
    this.activeSourceRangeEnd,
    this.onAcceptCommandCompletion,
    this.onPreviewSourceOffset,
    this.onPreviewSourceRange,
    this.onStructureCellSelected,
    this.commandCompletionUsageCounts = const <String, int>{},
    this.highlightedCommandCompletionIndex = 0,
  });

  final String sourceText;
  final InlineSpan sourceSpan;
  final TextStyle sourceTextStyle;
  final TextStyle previewTextStyle;
  final TextScaler textScaler;
  final bool numbered;
  final String? numberLabel;
  final String? equationLabel;
  final VoidCallback? onToggleNumbered;
  final VoidCallback? onEditLabel;
  final VoidCallback? onCopyReference;

  final VoidCallback? onInsertFraction;
  final VoidCallback? onInsertSuperscript;
  final VoidCallback? onInsertSubscript;
  final VoidCallback? onInsertText;
  final VoidCallback? onInsertDerivative;
  final VoidCallback? onInsertMatrix;
  final VoidCallback? onInsertAligned;
  final VoidCallback? onInsertCases;
  final VoidCallback? onInsertMatrixRow;
  final VoidCallback? onInsertMatrixColumn;
  final VoidCallback? onInsertAlignedLine;
  final VoidCallback? onInsertAlignmentMarker;
  final VoidCallback? onInsertCasesRow;
  final OwnedEquationStructureContext? structureContext;
  final ValueChanged<String>? onInsertSymbol;
  final VoidCallback? onFormatSource;
  final VoidCallback? onJumpNextSlot;
  final VoidCallback? onJumpPreviousSlot;
  final int? activeSourceOffset;
  final int? activeSourceRangeStart;
  final int? activeSourceRangeEnd;
  final void Function(String completion, int caretOffset)? onAcceptCommandCompletion;
  final ValueChanged<int>? onPreviewSourceOffset;
  final void Function(int startOffset, int endOffset)? onPreviewSourceRange;
  final void Function(OwnedEquationStructureContext contextInfo, int rowIndex, int columnIndex)? onStructureCellSelected;
  final Map<String, int> commandCompletionUsageCounts;
  final int highlightedCommandCompletionIndex;

  static const double sourceLeftInset = 18.0;
  static const double sourceTopInset = 178.0;

  @override
  State<OwnedEquationAuthoringSurface> createState() => _OwnedEquationAuthoringSurfaceState();
}

class _OwnedEquationAuthoringSurfaceState extends State<OwnedEquationAuthoringSurface> {
  Timer? _previewTimer;
  late OwnedEquationSourceModel _previewModel;
  _EquationPreviewSourceSelection? _previewHoverSelection;
  final GlobalKey _previewFrameKey = GlobalKey(debugLabel: 'ownedEquationPreviewFrame');
  final GlobalKey _previewMathKey = GlobalKey(debugLabel: 'ownedEquationPreviewMath');
  Rect? _previewMathPaintRect;

  @override
  void initState() {
    super.initState();
    _previewModel = OwnedEquationSourceModel.analyze(widget.sourceText);
  }

  @override
  void didUpdateWidget(covariant OwnedEquationAuthoringSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceText != widget.sourceText) {
      _previewMathPaintRect = null;
      _previewTimer?.cancel();
      _previewTimer = Timer(const Duration(milliseconds: 110), () {
        if (!mounted) return;
        setState(() => _previewModel = OwnedEquationSourceModel.analyze(widget.sourceText));
      });
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final source = widget.sourceText.trim().isEmpty ? r'\[\]' : widget.sourceText;
    final currentModel = OwnedEquationSourceModel.analyze(source);
    final previewModel = _previewModel.rawSource == widget.sourceText ? _previewModel : currentModel;
    final preview = previewModel.displayBody.trim().isEmpty ? currentModel.displayBody : previewModel.displayBody;
    final previewUnsafe = _hasPreviewUnsafeSyntax(source) ||
        _hasPreviewUnsafeSyntax(currentModel.displayBody) ||
        _hasPreviewUnsafeSyntax(preview);
    final previewRenderable = !currentModel.hasErrors && !previewUnsafe;
    final diagnostics = currentModel.diagnostics;
    final structureContext = OwnedEquationStructureContext.fromModel(
      currentModel.structure,
      widget.activeSourceOffset,
    );
    final editingContext = _EquationEditingContext.fromModel(
      model: currentModel,
      structureContext: structureContext,
      activeSourceOffset: widget.activeSourceOffset,
      activeRangeStart: widget.activeSourceRangeStart,
      activeRangeEnd: widget.activeSourceRangeEnd,
    );
    final subexpressionTargets = currentModel.structure.visualTargets(
      activeOffset: widget.activeSourceOffset,
    );
    final commandPrefix = OwnedEquationCommandPrefix.fromSource(
      widget.sourceText,
      widget.activeSourceOffset,
    );
    final commandCompletions = OwnedEquationCommandCompletion.matchesFor(
      commandPrefix,
      source: widget.sourceText,
      activeOffset: widget.activeSourceOffset,
      usageCounts: widget.commandCompletionUsageCounts,
    );
    final shouldShowCompletions = commandPrefix != null &&
        commandCompletions.isNotEmpty &&
        !OwnedEquationCommandCompletion.isExactCompletedCommand(commandPrefix);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 660;
        final previewHeight = _previewHeightFor(
          model: currentModel,
          compact: compact,
          constraints: constraints,
        );
        final completionDropdownVisibleCount = math.min(commandCompletions.length, 3).toDouble();
        final completionDropdownHeight = 8.0 + completionDropdownVisibleCount * 21.0;
        final completionDropdownWidth = compact ? 142.0 : 154.0;
        final completionAnchor = shouldShowCompletions
            ? _completionDropdownAnchor(
                constraints: constraints,
                compact: compact,
                previewHeight: previewHeight,
                dropdownWidth: completionDropdownWidth,
                dropdownHeight: completionDropdownHeight,
              )
            : Offset.zero;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
            border: Border.symmetric(
              horizontal: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.72)),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: OwnedEquationAuthoringSurface.sourceTopInset - 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OwnedEquationAuthoringSurface.sourceLeftInset,
                    7,
                    OwnedEquationAuthoringSurface.sourceLeftInset,
                    0,
                  ),
                  child: _EquationAuthoringHeader(
                    compact: compact,
                    onInsertFraction: widget.onInsertFraction,
                    onInsertSuperscript: widget.onInsertSuperscript,
                    onInsertSubscript: widget.onInsertSubscript,
                    onInsertText: widget.onInsertText,
                    onInsertDerivative: widget.onInsertDerivative,
                    onInsertMatrix: widget.onInsertMatrix,
                    onInsertAligned: widget.onInsertAligned,
                    onInsertCases: widget.onInsertCases,
                    onInsertMatrixRow: widget.onInsertMatrixRow,
                    onInsertMatrixColumn: widget.onInsertMatrixColumn,
                    onInsertAlignedLine: widget.onInsertAlignedLine,
                    onInsertAlignmentMarker: widget.onInsertAlignmentMarker,
                    onInsertCasesRow: widget.onInsertCasesRow,
                    structureContext: structureContext,
                    editingContext: editingContext,
                    subexpressionTargets: subexpressionTargets,
                    activeSourceOffset: widget.activeSourceOffset,
                    onJumpToSourceOffset: widget.onPreviewSourceOffset,
                    onStructureCellSelected: widget.onStructureCellSelected,
                    onInsertSymbol: widget.onInsertSymbol,
                    numbered: widget.numbered,
                    numberLabel: widget.numberLabel,
                    equationLabel: widget.equationLabel,
                    onToggleNumbered: widget.onToggleNumbered,
                    onEditLabel: widget.onEditLabel,
                    onCopyReference: widget.onCopyReference,
                    onFormatSource: widget.onFormatSource,
                    onJumpToDiagnostic: _jumpToDiagnostic,
                  ),
                ),
              ),
              Positioned(
                left: OwnedEquationAuthoringSurface.sourceLeftInset,
                right: OwnedEquationAuthoringSurface.sourceLeftInset,
                top: OwnedEquationAuthoringSurface.sourceTopInset,
                bottom: previewHeight + 18,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                    border: Border(
                      left: BorderSide(color: colorScheme.primary.withValues(alpha: 0.60), width: 2),
                      bottom: BorderSide(color: colorScheme.primary.withValues(alpha: 0.30)),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRect(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 2,
                              right: 6,
                              bottom: diagnostics.isEmpty ? 0 : 28,
                            ),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: RichText(
                                textAlign: TextAlign.start,
                                textScaler: widget.textScaler,
                                text: widget.sourceSpan,
                                maxLines: compact ? 4 : 3,
                                overflow: TextOverflow.fade,
                                softWrap: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (diagnostics.isNotEmpty)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 4,
                          height: 22,
                          child: _EquationDiagnosticsStrip(
                            diagnostics: diagnostics,
                            onJumpToDiagnostic: _jumpToDiagnostic,
                            onFormatSource: widget.onFormatSource,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: OwnedEquationAuthoringSurface.sourceLeftInset,
                right: OwnedEquationAuthoringSurface.sourceLeftInset,
                bottom: 8,
                height: previewHeight,
                child: LayoutBuilder(
                  builder: (context, previewConstraints) {
                    final previewSize = Size(previewConstraints.maxWidth, previewHeight);
                    final previewMappingEnabled = false;
                    final inkLayout = !previewMappingEnabled
                        ? null
                        : _EquationPreviewSourceMap.ownedInkLayoutForModel(
                            model: currentModel,
                            previewSize: previewSize,
                            textStyle: widget.previewTextStyle,
                            textScaler: widget.textScaler,
                          );
                    final activeSelection = _activePreviewSelection();
                    final activePreviewRects = activeSelection == null
                        ? const <Rect>[]
                        : inkLayout?.previewRectsForSourceSelection(activeSelection) ?? const <Rect>[];
                    final hoverPreviewRects = _previewHoverSelection == null
                        ? const <Rect>[]
                        : inkLayout?.previewRectsForSourceSelection(_previewHoverSelection!) ?? const <Rect>[];
                    final diagnosticSelection = editingContext.diagnosticPreviewSelection;
                    final diagnosticPreviewRects = diagnosticSelection == null
                        ? const <Rect>[]
                        : inkLayout?.previewRectsForSourceSelection(diagnosticSelection) ?? const <Rect>[];

                    void jumpToPreviewSource(Offset localPosition) {
                      if (!previewMappingEnabled) return;
                      final target = _EquationPreviewSourceMap.sourceSelectionForPreviewTap(
                        model: currentModel,
                        localPosition: localPosition,
                        previewSize: previewSize,
                        mathRect: _previewMathPaintRect,
                        textStyle: widget.previewTextStyle,
                        textScaler: widget.textScaler,
                      );
                      if (target.isRange) {
                        widget.onPreviewSourceRange?.call(target.start, target.end);
                        return;
                      }
                      widget.onPreviewSourceOffset?.call(target.start);
                    }

                    return MouseRegion(
                      cursor: widget.onPreviewSourceOffset == null && widget.onPreviewSourceRange == null
                          ? MouseCursor.defer
                          : SystemMouseCursors.precise,
                      onHover: (event) {
                        if (!previewMappingEnabled ||
                            (widget.onPreviewSourceOffset == null && widget.onPreviewSourceRange == null)) {
                          return;
                        }
                        final target = _EquationPreviewSourceMap.sourceSelectionForPreviewTap(
                          model: currentModel,
                          localPosition: event.localPosition,
                          previewSize: previewSize,
                          mathRect: _previewMathPaintRect,
                          textStyle: widget.previewTextStyle,
                          textScaler: widget.textScaler,
                        );
                        final currentHover = _previewHoverSelection;
                        if (currentHover == null ||
                            currentHover.start != target.start ||
                            currentHover.end != target.end) {
                          setState(() => _previewHoverSelection = target);
                        }
                      },
                      onExit: (_) {
                        if (_previewHoverSelection != null) {
                          setState(() => _previewHoverSelection = null);
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapDown: widget.onPreviewSourceOffset == null && widget.onPreviewSourceRange == null
                            ? null
                            : (details) => jumpToPreviewSource(details.localPosition),
                        child: DecoratedBox(
                          key: _previewFrameKey,
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: 10,
                                top: 6,
                                child: Text(
                                  previewRenderable ? 'Live preview' : 'Live preview · source has errors',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: previewRenderable ? colorScheme.onSurfaceVariant : colorScheme.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: ClipRect(
                                  child: !previewRenderable
                                      ? Center(
                                          child: _EquationPreviewErrorPlaceholder(
                                            message: 'Resolve source errors to update preview',
                                            color: colorScheme.error,
                                            textStyle: theme.textTheme.bodySmall,
                                          ),
                                        )
                                      : ExcludeSemantics(
                                          child: _EquationTeXPreview(
                                            source: preview,
                                            textStyle: widget.previewTextStyle,
                                            color: colorScheme.onSurface,
                                            errorColor: colorScheme.error,
                                          ),
                                        ),
                                ),
                              ),
                              if (activePreviewRects.isNotEmpty || hoverPreviewRects.isNotEmpty || diagnosticPreviewRects.isNotEmpty)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _EquationPreviewHighlightPainter(
                                        activeRects: activePreviewRects,
                                        hoverRects: hoverPreviewRects,
                                        diagnosticRects: diagnosticPreviewRects,
                                        activeColor: colorScheme.primary,
                                        hoverColor: colorScheme.tertiary,
                                        diagnosticColor: colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ),
                              if (previewMappingEnabled &&
                                  _previewHoverSelection != null &&
                                  (widget.onPreviewSourceOffset != null || widget.onPreviewSourceRange != null))
                                Positioned(
                                  right: widget.numbered ? 46 : 10,
                                  top: 6,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer.withValues(alpha: 0.52),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      child: Text(
                                        'click → source',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                right: widget.numbered ? 46 : 10,
                                top: 6,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer.withValues(alpha: 0.48),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.16)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    child: Text(
                                      'TeX preview',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSecondaryContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.numbered)
                                Positioned(
                                  right: 12,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: Text(
                                      widget.numberLabel ?? '(1)',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (shouldShowCompletions)
                Positioned(
                  left: completionAnchor.dx,
                  top: completionAnchor.dy,
                  width: completionDropdownWidth,
                  height: completionDropdownHeight,
                  child: _EquationCompletionDropdown(
                    prefix: commandPrefix!,
                    completions: commandCompletions,
                    highlightedIndex: widget.highlightedCommandCompletionIndex,
                    usageCounts: widget.commandCompletionUsageCounts,
                    onAccept: widget.onAcceptCommandCompletion,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }


  bool _hasPreviewUnsafeSyntax(String source) {
    if (source.isEmpty) return false;

    // flutter_math_fork is very sensitive to scripts without a visible base,
    // especially inside fractions/roots. Treat these as non-renderable preview
    // states and keep them in the source diagnostics layer instead of letting
    // the math renderer create RenderLine overflow stripes.
    if (_hasGroupLeadingScript(source)) return true;
    if (RegExp(r'(^|[=+\-*/,;&|])\s*[\^_]').hasMatch(source)) return true;
    if (RegExp(r'\\(?:frac|dfrac|tfrac|sqrt)\s*\{\s*[\^_]').hasMatch(source)) return true;

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char != '^' && char != '_') continue;
      final previous = _previousMeaningfulCharacter(source, i - 1);
      if (previous == null) return true;
      if (!_isValidScriptBaseEnd(previous)) return true;
    }
    return false;
  }

  bool _hasGroupLeadingScript(String source) {
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char != '{' && char != '[' && char != '(' && char != '&') continue;
      var cursor = i + 1;
      while (cursor < source.length) {
        final unit = source.codeUnitAt(cursor);
        if (unit != 32 && unit != 9 && unit != 10 && unit != 13) break;
        cursor++;
      }
      if (cursor < source.length && (source[cursor] == '^' || source[cursor] == '_')) {
        return true;
      }
    }
    return false;
  }

  String? _previousMeaningfulCharacter(String source, int start) {
    for (var i = start; i >= 0; i--) {
      final unit = source.codeUnitAt(i);
      if (unit == 32 || unit == 9 || unit == 10 || unit == 13) continue;
      return source[i];
    }
    return null;
  }

  bool _isValidScriptBaseEnd(String previous) {
    final unit = previous.codeUnitAt(0);
    final isAsciiLetter = (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
    final isDigit = unit >= 48 && unit <= 57;
    return isAsciiLetter ||
        isDigit ||
        previous == '}' ||
        previous == ']' ||
        previous == ')' ||
        previous == '\'' ||
        previous == '\\';
  }

  void _schedulePreviewMathRectUpdate({required bool enabled}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!enabled) {
        if (_previewMathPaintRect != null) {
          setState(() => _previewMathPaintRect = null);
        }
        return;
      }

      final frameContext = _previewFrameKey.currentContext;
      final mathContext = _previewMathKey.currentContext;
      final frameObject = frameContext?.findRenderObject();
      final mathObject = mathContext?.findRenderObject();
      if (frameObject is! RenderBox || mathObject is! RenderBox || !frameObject.attached || !mathObject.attached) {
        return;
      }

      final topLeft = frameObject.globalToLocal(mathObject.localToGlobal(Offset.zero));
      final bottomRight = frameObject.globalToLocal(
        mathObject.localToGlobal(Offset(mathObject.size.width, mathObject.size.height)),
      );
      final bounds = Offset.zero & frameObject.size;
      final next = Rect.fromPoints(topLeft, bottomRight).intersect(bounds);
      if (next.isEmpty || next.width < 2 || next.height < 2) return;
      final previous = _previewMathPaintRect;
      if (_rectsAreClose(previous, next)) return;
      setState(() => _previewMathPaintRect = next);
    });
  }

  bool _rectsAreClose(Rect? a, Rect b) {
    if (a == null) return false;
    return (a.left - b.left).abs() < 0.75 &&
        (a.top - b.top).abs() < 0.75 &&
        (a.width - b.width).abs() < 1.25 &&
        (a.height - b.height).abs() < 1.25;
  }

  void _jumpToDiagnostic(OwnedEquationDiagnostic diagnostic) {
    final safeStart = diagnostic.start.clamp(0, widget.sourceText.length).toInt();
    final safeEnd = diagnostic.end.clamp(safeStart, widget.sourceText.length).toInt();
    if (safeEnd > safeStart && widget.onPreviewSourceRange != null) {
      widget.onPreviewSourceRange!(safeStart, safeEnd);
      return;
    }
    widget.onPreviewSourceOffset?.call(safeStart);
  }

  _EquationPreviewSourceSelection? _activePreviewSelection() {
    final start = widget.activeSourceRangeStart;
    final end = widget.activeSourceRangeEnd;
    if (start != null && end != null && end > start) {
      return _EquationPreviewSourceSelection(start: start, end: end);
    }

    // Do not reverse-project a collapsed source caret into the rendered preview.
    // The rendered math is laid out by flutter_math_fork, while our current
    // source->preview map is a lightweight semantic approximation. For a lone
    // caret this approximation can look falsely precise and appear offset,
    // especially around fractions, roots and nested scripts. Preview->source
    // navigation remains active; source->preview highlighting is reserved for
    // real source ranges where the visual affordance is less misleading.
    return null;
  }

  double _previewHeightFor({
    required OwnedEquationSourceModel model,
    required bool compact,
    required BoxConstraints constraints,
  }) {
    final structure = model.structure;
    var maxRows = 1;
    var hasEnvironment = false;
    for (final environment in structure.environments) {
      hasEnvironment = true;
      maxRows = math.max(maxRows, environment.rowCount).toInt();
    }

    final body = model.displayBody;
    final hasTallOperator = body.contains(r'\frac') ||
        body.contains(r'\dfrac') ||
        body.contains(r'\tfrac') ||
        body.contains(r'\sqrt') ||
        body.contains(r'\sum') ||
        body.contains(r'\int');
    final base = compact ? 82.0 : 90.0;
    final structureAllowance = hasEnvironment ? 28.0 + math.max(0, maxRows - 1) * 20.0 : 0.0;
    final tallOperatorAllowance = hasTallOperator ? 18.0 : 0.0;
    final desired = base + structureAllowance + tallOperatorAllowance;

    // Keep the source lane usable. The preview should grow enough to show the
    // complete rendered equation, but if the page fragment is unusually tight it
    // must scale down inside its own bounds rather than escaping the authoring
    // surface.
    final maxBySurface = constraints.maxHeight.isFinite
        ? math.max(base, constraints.maxHeight - OwnedEquationAuthoringSurface.sourceTopInset - 72.0)
        : desired;
    return desired.clamp(base, math.min(190.0, maxBySurface)).toDouble();
  }

  Offset _completionDropdownAnchor({
    required BoxConstraints constraints,
    required bool compact,
    required double previewHeight,
    required double dropdownWidth,
    required double dropdownHeight,
  }) {
    final activeOffset = widget.activeSourceOffset?.clamp(0, widget.sourceText.length).toInt() ?? 0;
    final laneTextWidth = math.max(
      1.0,
      constraints.maxWidth - OwnedEquationAuthoringSurface.sourceLeftInset * 2 - 10,
    );
    final painter = TextPainter(
      text: widget.sourceSpan,
      textDirection: TextDirection.ltr,
      textScaler: widget.textScaler,
      maxLines: compact ? 4 : 3,
    )..layout(maxWidth: laneTextWidth);

    final caretOffset = painter.getOffsetForCaret(
      TextPosition(offset: activeOffset),
      Rect.zero,
    );
    final lineHeight = math.max(18.0, painter.preferredLineHeight);
    final laneTop = OwnedEquationAuthoringSurface.sourceTopInset;
    final laneBottom = constraints.maxHeight.isFinite
        ? math.max(laneTop + dropdownHeight + 8, constraints.maxHeight - previewHeight - 18)
        : laneTop + 118;

    final minLeft = OwnedEquationAuthoringSurface.sourceLeftInset + 4;
    final maxLeft = math.max(
      minLeft,
      constraints.maxWidth - OwnedEquationAuthoringSurface.sourceLeftInset - dropdownWidth,
    );
    final left = (OwnedEquationAuthoringSurface.sourceLeftInset + 4 + caretOffset.dx)
        .clamp(minLeft, maxLeft)
        .toDouble();

    var top = laneTop + 6 + caretOffset.dy + lineHeight;
    if (top + dropdownHeight > laneBottom - 4) {
      top = laneTop + 6 + caretOffset.dy - dropdownHeight - 4;
    }
    final minTop = laneTop + 4;
    final maxTop = math.max(minTop, laneBottom - dropdownHeight - 4);
    top = top.clamp(minTop, maxTop).toDouble();

    return Offset(left, top);
  }

}


class _EquationPreviewSourceMap {
  const _EquationPreviewSourceMap._();

  static int sourceOffsetForPreviewTap({
    required OwnedEquationSourceModel model,
    required Offset localPosition,
    required Size previewSize,
    Rect? mathRect,
    TextStyle? textStyle,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return sourceSelectionForPreviewTap(
      model: model,
      localPosition: localPosition,
      previewSize: previewSize,
      mathRect: mathRect,
      textStyle: textStyle,
      textScaler: textScaler,
    ).start;
  }

  static _EquationPreviewSourceSelection sourceSelectionForPreviewTap({
    required OwnedEquationSourceModel model,
    required Offset localPosition,
    required Size previewSize,
    Rect? mathRect,
    TextStyle? textStyle,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final displayBody = model.displayBody;
    final rawBodyStart = model.bodyStartOffset.clamp(0, model.rawSource.length).toInt();
    final rawBodyEnd = model.bodyEndOffset.clamp(rawBodyStart, model.rawSource.length).toInt();
    final rawBody = model.rawSource.substring(rawBodyStart, rawBodyEnd);
    final leadingTrim = rawBody.length - rawBody.trimLeft().length;
    final fallbackSourceBaseOffset = (rawBodyStart + leadingTrim).clamp(0, model.rawSource.length).toInt();
    if (displayBody.isEmpty) {
      return _EquationPreviewSourceSelection.collapsed(fallbackSourceBaseOffset);
    }

    final targets = _semanticPreviewTokenTargets(
      model: model,
      previewSize: previewSize,
      mathRect: mathRect,
      textStyle: textStyle,
      textScaler: textScaler,
    );
    if (targets.isEmpty) {
      return _EquationPreviewSourceSelection.collapsed(fallbackSourceBaseOffset);
    }

    _EquationPreviewSourceTokenTarget? best;
    var bestDistance = double.infinity;
    for (final target in targets) {
      final distance = target.distanceTo(localPosition);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = target;
      }
      if (distance == 0) break;
    }
    return best?.selection ?? _EquationPreviewSourceSelection.collapsed(fallbackSourceBaseOffset);
  }

  static List<Rect> previewRectsForSourceSelection({
    required OwnedEquationSourceModel model,
    required Size previewSize,
    Rect? mathRect,
    TextStyle? textStyle,
    TextScaler textScaler = TextScaler.noScaling,
    required _EquationPreviewSourceSelection selection,
  }) {
    final displayBody = model.displayBody;
    final rawBodyStart = model.bodyStartOffset.clamp(0, model.rawSource.length).toInt();
    final rawBodyEnd = model.bodyEndOffset.clamp(rawBodyStart, model.rawSource.length).toInt();
    final rawBody = model.rawSource.substring(rawBodyStart, rawBodyEnd);
    final leadingTrim = rawBody.length - rawBody.trimLeft().length;
    final fallbackSourceBaseOffset = (rawBodyStart + leadingTrim).clamp(0, model.rawSource.length).toInt();
    if (displayBody.isEmpty) return const <Rect>[];

    final targets = _semanticPreviewTokenTargets(
      model: model,
      previewSize: previewSize,
      mathRect: mathRect,
      textStyle: textStyle,
      textScaler: textScaler,
    );
    if (targets.isEmpty) return const <Rect>[];

    final selectedTargets = targets
        .where((target) => target.intersects(selection.start, selection.end))
        .toList(growable: false);
    if (selectedTargets.isNotEmpty) {
      return selectedTargets.map((target) => target.rect).take(12).toList(growable: false);
    }

    if (!selection.isCollapsed) return const <Rect>[];
    _EquationPreviewSourceTokenTarget? containing;
    var smallestWidth = double.infinity;
    for (final target in targets) {
      if (!target.containsOffset(selection.start)) continue;
      final width = math.max(1.0, target.end - target.start).toDouble();
      if (width < smallestWidth) {
        smallestWidth = width;
        containing = target;
      }
    }
    if (containing != null) return <Rect>[containing.rect];
    return const <Rect>[];
  }


  static _OwnedEquationInkLayout? ownedInkLayoutForModel({
    required OwnedEquationSourceModel model,
    required Size previewSize,
    TextStyle? textStyle,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final children = model.structure.root.children;
    if (children.isEmpty) return null;

    final style = textStyle ?? const TextStyle(fontSize: 22);
    final baseFontSize = (style.fontSize ?? 22.0).clamp(14.0, 34.0).toDouble();
    final semantic = _semanticSequenceBox(
      nodes: children,
      source: model.rawSource,
      style: style,
      textScaler: textScaler,
      baseFontSize: baseFontSize,
    );
    if (semantic.targets.isEmpty || semantic.width <= 0 || semantic.height <= 0) {
      return null;
    }

    final viewport = _mathViewportFor(previewSize, null);
    if (viewport.isEmpty || viewport.width <= 1 || viewport.height <= 1) return null;

    final widthScale = viewport.width / math.max(1.0, semantic.width);
    final heightScale = viewport.height / math.max(1.0, semantic.height);
    var scale = math.min(widthScale, heightScale);
    scale = scale.clamp(0.58, 1.24).toDouble();
    if (semantic.width * scale > viewport.width) {
      scale = viewport.width / math.max(1.0, semantic.width);
    }
    if (semantic.height * scale > viewport.height) {
      scale = math.min(scale, viewport.height / math.max(1.0, semantic.height));
    }

    final scaledWidth = semantic.width * scale;
    final scaledHeight = semantic.height * scale;
    final origin = Offset(
      viewport.center.dx - scaledWidth / 2,
      viewport.center.dy - scaledHeight / 2,
    );

    Rect transformRect(Rect rect, {double inflate = 0}) {
      return Rect.fromLTRB(
        origin.dx + rect.left * scale,
        origin.dy + rect.top * scale,
        origin.dx + rect.right * scale,
        origin.dy + rect.bottom * scale,
      ).inflate(inflate).intersect(Offset.zero & previewSize);
    }

    Offset transformOffset(Offset offset) => Offset(
          origin.dx + offset.dx * scale,
          origin.dy + offset.dy * scale,
        );

    return _OwnedEquationInkLayout(
      size: previewSize,
      viewport: viewport,
      scale: scale,
      origin: origin,
      targets: <_EquationPreviewSourceTokenTarget>[
        for (final target in semantic.targets)
          _EquationPreviewSourceTokenTarget(
            start: target.start,
            end: target.end,
            rect: transformRect(target.rect, inflate: 1.5),
          ),
      ].where((target) => !target.rect.isEmpty && target.rect.width > 0 && target.rect.height > 0).toList(growable: false),
      glyphs: <_OwnedEquationInkGlyph>[
        for (final glyph in semantic.glyphs)
          _OwnedEquationInkGlyph(
            text: glyph.text,
            rect: transformRect(glyph.rect),
            baseline: glyph.baseline * scale,
            fontSize: glyph.fontSize * scale,
            italic: glyph.italic,
            bold: glyph.bold,
            sourceStart: glyph.sourceStart,
            sourceEnd: glyph.sourceEnd,
          ),
      ],
      lines: <_OwnedEquationInkLine>[
        for (final line in semantic.lines)
          _OwnedEquationInkLine(
            start: transformOffset(line.start),
            end: transformOffset(line.end),
            strokeWidth: math.max(1.0, line.strokeWidth * scale),
          ),
      ],
    );
  }

  static List<_EquationPreviewSourceTokenTarget> _semanticPreviewTokenTargets({
    required OwnedEquationSourceModel model,
    required Size previewSize,
    Rect? mathRect,
    TextStyle? textStyle,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return ownedInkLayoutForModel(
          model: model,
          previewSize: previewSize,
          textStyle: textStyle,
          textScaler: textScaler,
        )?.targets ??
        const <_EquationPreviewSourceTokenTarget>[];
  }

  static _SemanticEquationPreviewBox _semanticSequenceBox({
    required List<OwnedEquationStructureNode> nodes,
    required String source,
    required TextStyle style,
    required TextScaler textScaler,
    required double baseFontSize,
    double fontScale = 1.0,
  }) {
    final boxes = <_SemanticEquationPreviewBox>[];
    for (final node in nodes) {
      final box = _semanticBoxForNode(
        node: node,
        source: source,
        style: style,
        textScaler: textScaler,
        baseFontSize: baseFontSize,
        fontScale: fontScale,
      );
      if (box.width > 0 && box.height > 0) boxes.add(box);
    }
    if (boxes.isEmpty) {
      final height = baseFontSize * fontScale * 1.12;
      return _SemanticEquationPreviewBox(width: 1, height: height, baseline: height * 0.78);
    }

    var width = 0.0;
    var baseline = 0.0;
    var descent = 0.0;
    final gaps = <double>[];
    for (var i = 0; i < boxes.length; i++) {
      final node = nodes[i];
      final previous = i == 0 ? null : nodes[i - 1];
      final gap = i == 0 ? 0.0 : _semanticGapBefore(previous, node, baseFontSize * fontScale);
      gaps.add(gap);
      width += gap + boxes[i].width;
      baseline = math.max(baseline, boxes[i].baseline);
      descent = math.max(descent, boxes[i].height - boxes[i].baseline);
    }

    final height = math.max(baseFontSize * fontScale * 1.05, baseline + descent);
    final targets = <_EquationPreviewSourceTokenTarget>[];
    final glyphs = <_OwnedEquationInkGlyph>[];
    final lines = <_OwnedEquationInkLine>[];
    var cursor = 0.0;
    for (var i = 0; i < boxes.length; i++) {
      cursor += gaps[i];
      final box = boxes[i];
      final top = baseline - box.baseline;
      targets.addAll(_shiftSemanticTargets(box.targets, dx: cursor, dy: top));
      glyphs.addAll(_shiftSemanticGlyphs(box.glyphs, dx: cursor, dy: top));
      lines.addAll(_shiftSemanticLines(box.lines, dx: cursor, dy: top));
      cursor += box.width;
    }
    return _SemanticEquationPreviewBox(
      width: math.max(1.0, width),
      height: math.max(1.0, height),
      baseline: baseline,
      targets: targets,
      glyphs: glyphs,
      lines: lines,
    );
  }

  static double _semanticGapBefore(
    OwnedEquationStructureNode? previous,
    OwnedEquationStructureNode current,
    double fontSize,
  ) {
    if (previous == null) return 0;
    final currentIsScript = current.kind == OwnedEquationStructureKind.superscript ||
        current.kind == OwnedEquationStructureKind.subscript;
    final previousIsScript = previous.kind == OwnedEquationStructureKind.superscript ||
        previous.kind == OwnedEquationStructureKind.subscript;
    if (currentIsScript || previousIsScript) return fontSize * 0.015;
    if (current.kind == OwnedEquationStructureKind.operatorToken ||
        previous.kind == OwnedEquationStructureKind.operatorToken) {
      return fontSize * 0.20;
    }
    return fontSize * 0.035;
  }

  static _SemanticEquationPreviewBox _semanticBoxForNode({
    required OwnedEquationStructureNode node,
    required String source,
    required TextStyle style,
    required TextScaler textScaler,
    required double baseFontSize,
    double fontScale = 1.0,
  }) {
    switch (node.kind) {
      case OwnedEquationStructureKind.fraction:
        final numeratorNode = node.children.isNotEmpty ? node.children.first : null;
        final denominatorNode = node.children.length > 1 ? node.children[1] : null;
        final numerator = numeratorNode == null
            ? _semanticPlaceholderBox(node.contentStart ?? node.sourceStart, baseFontSize, fontScale)
            : _semanticSequenceBox(
                nodes: numeratorNode.children,
                source: source,
                style: style,
                textScaler: textScaler,
                baseFontSize: baseFontSize,
                fontScale: fontScale * 0.82,
              );
        final denominator = denominatorNode == null
            ? _semanticPlaceholderBox(node.contentEnd ?? node.sourceEnd, baseFontSize, fontScale)
            : _semanticSequenceBox(
                nodes: denominatorNode.children,
                source: source,
                style: style,
                textScaler: textScaler,
                baseFontSize: baseFontSize,
                fontScale: fontScale * 0.82,
              );
        final padding = baseFontSize * fontScale * 0.26;
        final gap = baseFontSize * fontScale * 0.13;
        final line = math.max(1.0, baseFontSize * fontScale * 0.045);
        final width = math.max(numerator.width, denominator.width) + padding * 2;
        final numeratorDx = (width - numerator.width) / 2;
        final denominatorDx = (width - denominator.width) / 2;
        final denominatorTop = numerator.height + gap + line + gap;
        final lineY = numerator.height + gap + line / 2;
        final targets = <_EquationPreviewSourceTokenTarget>[
          ..._shiftSemanticTargets(numerator.targets, dx: numeratorDx, dy: 0),
          ..._shiftSemanticTargets(denominator.targets, dx: denominatorDx, dy: denominatorTop),
        ];
        final glyphs = <_OwnedEquationInkGlyph>[
          ..._shiftSemanticGlyphs(numerator.glyphs, dx: numeratorDx, dy: 0),
          ..._shiftSemanticGlyphs(denominator.glyphs, dx: denominatorDx, dy: denominatorTop),
        ];
        final lines = <_OwnedEquationInkLine>[
          ..._shiftSemanticLines(numerator.lines, dx: numeratorDx, dy: 0),
          _OwnedEquationInkLine(
            start: Offset(padding * 0.58, lineY),
            end: Offset(width - padding * 0.58, lineY),
            strokeWidth: line,
          ),
          ..._shiftSemanticLines(denominator.lines, dx: denominatorDx, dy: denominatorTop),
        ];
        return _SemanticEquationPreviewBox(
          width: width,
          height: denominatorTop + denominator.height,
          baseline: denominatorTop + denominator.baseline,
          targets: targets,
          glyphs: glyphs,
          lines: lines,
        );
      case OwnedEquationStructureKind.squareRoot:
        final group = node.children.isNotEmpty ? node.children.first : null;
        final content = group == null
            ? _semanticPlaceholderBox(node.contentStart ?? node.sourceStart, baseFontSize, fontScale)
            : _semanticSequenceBox(
                nodes: group.children,
                source: source,
                style: style,
                textScaler: textScaler,
                baseFontSize: baseFontSize,
                fontScale: fontScale * 0.92,
              );
        final radicalWidth = baseFontSize * fontScale * 0.70;
        final topInset = baseFontSize * fontScale * 0.10;
        final width = radicalWidth + content.width + baseFontSize * fontScale * 0.10;
        final height = content.height + topInset;
        final commandEnd = math.min(node.sourceEnd, node.sourceStart + (node.command == null ? 1 : node.command!.length + 1));
        return _SemanticEquationPreviewBox(
          width: width,
          height: height,
          baseline: topInset + content.baseline,
          targets: <_EquationPreviewSourceTokenTarget>[
            _EquationPreviewSourceTokenTarget(
              start: node.sourceStart,
              end: commandEnd,
              rect: Rect.fromLTWH(0, 0, radicalWidth, height),
            ),
            ..._shiftSemanticTargets(content.targets, dx: radicalWidth, dy: topInset),
          ],
          glyphs: <_OwnedEquationInkGlyph>[
            _OwnedEquationInkGlyph(
              text: '√',
              rect: Rect.fromLTWH(0, topInset * 0.35, radicalWidth, height - topInset * 0.35),
              baseline: height * 0.83,
              fontSize: baseFontSize * fontScale * 1.16,
              italic: false,
              bold: false,
              sourceStart: node.sourceStart,
              sourceEnd: commandEnd,
            ),
            ..._shiftSemanticGlyphs(content.glyphs, dx: radicalWidth, dy: topInset),
          ],
          lines: <_OwnedEquationInkLine>[
            _OwnedEquationInkLine(
              start: Offset(radicalWidth * 0.58, topInset + 1.0),
              end: Offset(width, topInset + 1.0),
              strokeWidth: math.max(1.0, baseFontSize * fontScale * 0.035),
            ),
            ..._shiftSemanticLines(content.lines, dx: radicalWidth, dy: topInset),
          ],
        );
      case OwnedEquationStructureKind.superscript:
      case OwnedEquationStructureKind.subscript:
        final child = node.children.isNotEmpty
            ? _semanticSequenceBox(
                nodes: node.children.first.children,
                source: source,
                style: style,
                textScaler: textScaler,
                baseFontSize: baseFontSize,
                fontScale: fontScale * 0.68,
              )
            : _semanticTextRangeBox(
                source: source,
                start: node.contentStart ?? node.sourceStart,
                end: node.contentEnd ?? node.sourceEnd,
                style: style,
                textScaler: textScaler,
                baseFontSize: baseFontSize,
                fontScale: fontScale * 0.68,
              );
        if (node.kind == OwnedEquationStructureKind.superscript) {
          return _SemanticEquationPreviewBox(
            width: child.width,
            height: child.height + baseFontSize * fontScale * 0.24,
            baseline: child.height + baseFontSize * fontScale * 0.18,
            targets: child.targets,
            glyphs: child.glyphs,
            lines: child.lines,
          );
        }
        final subscriptDy = baseFontSize * fontScale * 0.22;
        return _SemanticEquationPreviewBox(
          width: child.width,
          height: child.height + baseFontSize * fontScale * 0.24,
          baseline: baseFontSize * fontScale * 0.18,
          targets: _shiftSemanticTargets(child.targets, dx: 0, dy: subscriptDy),
          glyphs: _shiftSemanticGlyphs(child.glyphs, dx: 0, dy: subscriptDy),
          lines: _shiftSemanticLines(child.lines, dx: 0, dy: subscriptDy),
        );
      case OwnedEquationStructureKind.group:
        return _semanticSequenceBox(
          nodes: node.children,
          source: source,
          style: style,
          textScaler: textScaler,
          baseFontSize: baseFontSize,
          fontScale: fontScale,
        );
      case OwnedEquationStructureKind.textRun:
      case OwnedEquationStructureKind.operatorToken:
      case OwnedEquationStructureKind.symbol:
        return _semanticTextRangeBox(
          source: source,
          start: node.sourceStart,
          end: node.sourceEnd,
          style: style,
          textScaler: textScaler,
          baseFontSize: baseFontSize,
          fontScale: fontScale,
          italic: node.kind == OwnedEquationStructureKind.textRun,
        );
      case OwnedEquationStructureKind.command:
      case OwnedEquationStructureKind.textCommand:
        if (node.kind == OwnedEquationStructureKind.textCommand && node.children.isNotEmpty) {
          return _semanticSequenceBox(
            nodes: node.children.first.children,
            source: source,
            style: style,
            textScaler: textScaler,
            baseFontSize: baseFontSize,
            fontScale: fontScale,
          );
        }
        final label = _semanticCommandGlyph(node.command);
        return _semanticLiteralBox(
          text: label,
          sourceStart: node.sourceStart,
          sourceEnd: node.sourceEnd,
          style: style,
          textScaler: textScaler,
          baseFontSize: baseFontSize,
          fontScale: fontScale,
          italic: label.runes.length == 1 && _isMathItalicChar(label),
        );
      case OwnedEquationStructureKind.environment:
        return _semanticEnvironmentBox(
          node: node,
          source: source,
          style: style,
          textScaler: textScaler,
          baseFontSize: baseFontSize,
          fontScale: fontScale,
        );
      case OwnedEquationStructureKind.root:
        return _semanticSequenceBox(
          nodes: node.children,
          source: source,
          style: style,
          textScaler: textScaler,
          baseFontSize: baseFontSize,
          fontScale: fontScale,
        );
    }
  }

  static _SemanticEquationPreviewBox _semanticEnvironmentBox({
    required OwnedEquationStructureNode node,
    required String source,
    required TextStyle style,
    required TextScaler textScaler,
    required double baseFontSize,
    required double fontScale,
  }) {
    final environment = _environmentForNode(OwnedEquationStructureModel.parse(source), node);
    if (environment == null || environment.rows.isEmpty) {
      return _semanticTextRangeBox(
        source: source,
        start: node.contentStart ?? node.sourceStart,
        end: node.contentEnd ?? node.sourceEnd,
        style: style,
        textScaler: textScaler,
        baseFontSize: baseFontSize,
        fontScale: fontScale,
      );
    }
    final rowBoxes = <List<_SemanticEquationPreviewBox>>[];
    final columnWidths = List<double>.filled(environment.columnCount, 1.0);
    for (final row in environment.rows) {
      final boxes = <_SemanticEquationPreviewBox>[];
      for (var column = 0; column < environment.columnCount; column++) {
        final cell = column < row.cells.length ? row.cells[column] : null;
        final box = cell == null
            ? _semanticPlaceholderBox(row.end, baseFontSize, fontScale * 0.82)
            : _semanticTextRangeBox(
                source: source,
                start: cell.start,
                end: cell.end,
                style: style,
                textScaler: textScaler,
                baseFontSize: baseFontSize,
                fontScale: fontScale * 0.82,
              );
        boxes.add(box);
        columnWidths[column] = math.max(columnWidths[column], box.width);
      }
      rowBoxes.add(boxes);
    }
    final columnGap = baseFontSize * fontScale * 0.75;
    final rowGap = baseFontSize * fontScale * 0.22;
    final rowHeights = <double>[
      for (final row in rowBoxes)
        row.map((box) => box.height).fold<double>(baseFontSize * fontScale, (previous, value) => math.max(previous, value)),
    ];
    final width = columnWidths.fold<double>(0, (sum, value) => sum + value) + columnGap * math.max(0, columnWidths.length - 1) + baseFontSize * fontScale * 0.55;
    final height = rowHeights.fold<double>(0, (sum, value) => sum + value) + rowGap * math.max(0, rowHeights.length - 1);
    final targets = <_EquationPreviewSourceTokenTarget>[];
    final glyphs = <_OwnedEquationInkGlyph>[];
    final lines = <_OwnedEquationInkLine>[];
    var y = 0.0;
    for (var rowIndex = 0; rowIndex < rowBoxes.length; rowIndex++) {
      var x = baseFontSize * fontScale * 0.28;
      for (var columnIndex = 0; columnIndex < rowBoxes[rowIndex].length; columnIndex++) {
        final box = rowBoxes[rowIndex][columnIndex];
        final cellTop = y + (rowHeights[rowIndex] - box.height) / 2;
        final cellLeft = x + (columnWidths[columnIndex] - box.width) / 2;
        targets.addAll(_shiftSemanticTargets(box.targets, dx: cellLeft, dy: cellTop));
        glyphs.addAll(_shiftSemanticGlyphs(box.glyphs, dx: cellLeft, dy: cellTop));
        lines.addAll(_shiftSemanticLines(box.lines, dx: cellLeft, dy: cellTop));
        x += columnWidths[columnIndex] + columnGap;
      }
      y += rowHeights[rowIndex] + rowGap;
    }
    return _SemanticEquationPreviewBox(
      width: width,
      height: height,
      baseline: height * 0.56,
      targets: targets,
      glyphs: glyphs,
      lines: lines,
    );
  }

  static _SemanticEquationPreviewBox _semanticPlaceholderBox(int offset, double baseFontSize, double fontScale) {
    final fontSize = baseFontSize * fontScale;
    final height = fontSize;
    final width = fontSize * 0.55;
    return _SemanticEquationPreviewBox(
      width: width,
      height: height,
      baseline: height * 0.78,
      targets: <_EquationPreviewSourceTokenTarget>[
        _EquationPreviewSourceTokenTarget(
          start: offset,
          end: offset,
          rect: Rect.fromLTWH(0, 0, width, height),
        ),
      ],
      glyphs: <_OwnedEquationInkGlyph>[
        _OwnedEquationInkGlyph(
          text: '□',
          rect: Rect.fromLTWH(0, 0, width, height),
          baseline: height * 0.78,
          fontSize: fontSize * 0.78,
          italic: false,
          bold: false,
          sourceStart: offset,
          sourceEnd: offset,
        ),
      ],
    );
  }

  static _SemanticEquationPreviewBox _semanticTextRangeBox({
    required String source,
    required int start,
    required int end,
    required TextStyle style,
    required TextScaler textScaler,
    required double baseFontSize,
    required double fontScale,
    bool italic = false,
  }) {
    final safeStart = start.clamp(0, source.length).toInt();
    final safeEnd = end.clamp(safeStart, source.length).toInt();
    final targets = <_EquationPreviewSourceTokenTarget>[];
    final glyphs = <_OwnedEquationInkGlyph>[];
    var x = 0.0;
    final fontSize = baseFontSize * fontScale;
    final height = fontSize * 1.10;
    final baseline = height * 0.76;
    for (var i = safeStart; i < safeEnd; i++) {
      final char = source[i];
      if (char.trim().isEmpty || char == '{' || char == '}' || char == '[' || char == ']') continue;
      final glyphItalic = italic || _isMathItalicChar(char);
      final measuredWidth = _measureSemanticText(
        char,
        style,
        textScaler,
        fontSize,
        italic: glyphItalic,
      );
      final italicCorrection = glyphItalic ? fontSize * 0.035 : 0.0;
      final width = math.max(4.0, measuredWidth + italicCorrection);
      final rect = Rect.fromLTWH(x, 0, width, height);
      targets.add(_EquationPreviewSourceTokenTarget(
        start: i,
        end: i + 1,
        rect: rect,
      ));
      glyphs.add(_OwnedEquationInkGlyph(
        text: char,
        rect: rect,
        baseline: baseline,
        fontSize: fontSize,
        italic: glyphItalic,
        bold: false,
        sourceStart: i,
        sourceEnd: i + 1,
      ));
      x += width;
    }
    if (targets.isEmpty) return _semanticPlaceholderBox(safeStart, baseFontSize, fontScale);
    return _SemanticEquationPreviewBox(
      width: math.max(1.0, x),
      height: height,
      baseline: baseline,
      targets: targets,
      glyphs: glyphs,
    );
  }

  static _SemanticEquationPreviewBox _semanticLiteralBox({
    required String text,
    required int sourceStart,
    required int sourceEnd,
    required TextStyle style,
    required TextScaler textScaler,
    required double baseFontSize,
    required double fontScale,
    bool italic = false,
  }) {
    final fontSize = baseFontSize * fontScale;
    final width = math.max(5.0, _measureSemanticText(text, style, textScaler, fontSize, italic: italic));
    final height = fontSize * 1.10;
    final baseline = height * 0.76;
    final rect = Rect.fromLTWH(0, 0, width, height);
    return _SemanticEquationPreviewBox(
      width: width,
      height: height,
      baseline: baseline,
      targets: <_EquationPreviewSourceTokenTarget>[
        _EquationPreviewSourceTokenTarget(
          start: sourceStart,
          end: sourceEnd,
          rect: rect,
        ),
      ],
      glyphs: <_OwnedEquationInkGlyph>[
        _OwnedEquationInkGlyph(
          text: text,
          rect: rect,
          baseline: baseline,
          fontSize: fontSize,
          italic: italic,
          bold: false,
          sourceStart: sourceStart,
          sourceEnd: sourceEnd,
        ),
      ],
    );
  }

  static String _semanticCommandGlyph(String? command) {
    switch (command) {
      case 'alpha':
        return 'α';
      case 'beta':
        return 'β';
      case 'gamma':
        return 'γ';
      case 'delta':
        return 'δ';
      case 'Delta':
        return 'Δ';
      case 'lambda':
        return 'λ';
      case 'mu':
        return 'μ';
      case 'sigma':
        return 'σ';
      case 'pi':
        return 'π';
      case 'infty':
        return '∞';
      case 'sum':
        return '∑';
      case 'int':
        return '∫';
      case 'leq':
        return '≤';
      case 'geq':
        return '≥';
      case 'neq':
        return '≠';
      case 'approx':
        return '≈';
      default:
        return command == null || command.isEmpty ? '□' : command;
    }
  }

  static double _measureSemanticText(
    String text,
    TextStyle style,
    TextScaler textScaler,
    double fontSize, {
    bool italic = false,
  }) {
    final effectiveStyle = _ownedEquationInkTextStyle(
      style,
      fontSize: fontSize,
      italic: italic,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  static bool _isMathItalicChar(String char) {
    if (char.length != 1) return false;
    final unit = char.codeUnitAt(0);
    return (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  }

  static List<_EquationPreviewSourceTokenTarget> _shiftSemanticTargets(
    List<_EquationPreviewSourceTokenTarget> targets, {
    required double dx,
    required double dy,
  }) {
    return <_EquationPreviewSourceTokenTarget>[
      for (final target in targets)
        _EquationPreviewSourceTokenTarget(
          start: target.start,
          end: target.end,
          rect: target.rect.shift(Offset(dx, dy)),
        ),
    ];
  }

  static List<_OwnedEquationInkGlyph> _shiftSemanticGlyphs(
    List<_OwnedEquationInkGlyph> glyphs, {
    required double dx,
    required double dy,
  }) {
    return <_OwnedEquationInkGlyph>[
      for (final glyph in glyphs)
        glyph.shift(dx: dx, dy: dy),
    ];
  }

  static List<_OwnedEquationInkLine> _shiftSemanticLines(
    List<_OwnedEquationInkLine> lines, {
    required double dx,
    required double dy,
  }) {
    return <_OwnedEquationInkLine>[
      for (final line in lines)
        line.shift(dx: dx, dy: dy),
    ];
  }


  static Rect _mathViewportFor(Size previewSize, Rect? measuredMathRect) {
    final bounds = Offset.zero & previewSize;
    if (measuredMathRect != null && measuredMathRect.width > 4 && measuredMathRect.height > 4) {
      final measured = measuredMathRect.inflate(1.5).intersect(bounds);
      if (!measured.isEmpty && measured.width > 4 && measured.height > 4) {
        return measured;
      }
    }

    const horizontalPreviewPadding = 28.0;
    const titleStripHeight = 22.0;
    const topMathPadding = 2.0;
    const bottomMathPadding = 8.0;
    final left = horizontalPreviewPadding;
    final right = math.max(left + 1.0, previewSize.width - horizontalPreviewPadding);
    final top = titleStripHeight + topMathPadding;
    final bottom = math.max(top + 1.0, previewSize.height - bottomMathPadding);
    return Rect.fromLTRB(left, top, right, bottom).intersect(bounds);
  }

  static List<_EquationPreviewUnitLayout> _layoutForUnits(
    List<_EquationPreviewVisualUnit> units,
    Size previewSize, {
    Rect? mathRect,
  }) {
    final totalWidth = units.fold<double>(0, (sum, unit) => sum + unit.width);
    final viewport = _mathViewportFor(previewSize, mathRect);
    final mathLeft = viewport.left;
    final mathRight = math.max(mathLeft + 1.0, viewport.right);
    final mathTop = viewport.top;
    final mathBottom = math.max(mathTop + 1.0, viewport.bottom);
    final mathWidth = math.max(1.0, mathRight - mathLeft);
    final scale = totalWidth <= mathWidth ? 1.0 : mathWidth / totalWidth;
    final scaledTotalWidth = totalWidth * scale;
    final startLeft = mathLeft + (mathWidth - scaledTotalWidth) / 2;
    final mathCenterY = mathTop + (mathBottom - mathTop) * 0.54;
    var cursor = startLeft;
    return <_EquationPreviewUnitLayout>[
      for (final unit in units)
        (() {
          final scaledWidth = math.max(1.0, unit.width * scale);
          final entry = _EquationPreviewUnitLayout(
            unit: unit,
            left: cursor,
            right: cursor + scaledWidth,
            top: mathTop,
            bottom: mathBottom,
            mathCenterY: mathCenterY,
            scale: scale,
          );
          cursor += scaledWidth;
          return entry;
        })(),
    ];
  }


  static List<_EquationPreviewSourceTokenTarget> _previewTokenTargets({
    required List<_EquationPreviewVisualUnit> units,
    required Size previewSize,
    Rect? mathRect,
    required String body,
    required int sourceBaseOffset,
  }) {
    final layout = _layoutForUnits(units, previewSize, mathRect: mathRect);
    final targets = <_EquationPreviewSourceTokenTarget>[];
    for (final entry in layout) {
      targets.addAll(_tokenTargetsForUnit(
        entry: entry,
        body: body,
        sourceBaseOffset: sourceBaseOffset,
      ));
    }
    return targets;
  }

  static List<_EquationPreviewSourceTokenTarget> _tokenTargetsForUnit({
    required _EquationPreviewUnitLayout entry,
    required String body,
    required int sourceBaseOffset,
  }) {
    final unit = entry.unit;
    final fullRect = entry.rect;

    if (unit.isFraction) {
      final mid = entry.mathCenterY;
      final numeratorRect = Rect.fromLTRB(
        fullRect.left + 4,
        fullRect.top,
        fullRect.right - 4,
        math.max(fullRect.top + 1, mid - 2),
      );
      final denominatorRect = Rect.fromLTRB(
        fullRect.left + 4,
        math.min(fullRect.bottom - 1, mid + 2),
        fullRect.right - 4,
        fullRect.bottom,
      );
      return <_EquationPreviewSourceTokenTarget>[
        ..._tokenTargetsForRange(
          body: body,
          sourceBaseOffset: sourceBaseOffset,
          start: unit.numeratorStart!,
          end: unit.numeratorEnd!,
          rect: numeratorRect,
        ),
        ..._tokenTargetsForRange(
          body: body,
          sourceBaseOffset: sourceBaseOffset,
          start: unit.denominatorStart!,
          end: unit.denominatorEnd!,
          rect: denominatorRect,
        ),
      ];
    }

    if (unit.environment != null) {
      return _tokenTargetsForEnvironment(
        environment: unit.environment!,
        body: body,
        sourceBaseOffset: sourceBaseOffset,
        rect: fullRect,
      );
    }

    final kind = unit.kind;
    if (kind == OwnedEquationStructureKind.squareRoot) {
      final radicalRect = Rect.fromLTRB(
        fullRect.left,
        fullRect.top,
        math.min(fullRect.right, fullRect.left + 14 * entry.scale),
        fullRect.bottom,
      );
      final contentRect = Rect.fromLTRB(
        math.min(fullRect.right, fullRect.left + 14 * entry.scale),
        fullRect.top,
        fullRect.right,
        fullRect.bottom,
      );
      final targets = _tokenTargetsForRange(
        body: body,
        sourceBaseOffset: sourceBaseOffset,
        start: unit.contentStart ?? unit.start,
        end: unit.contentEnd ?? unit.end,
        rect: contentRect,
      );
      if (targets.isNotEmpty) return targets;
      return <_EquationPreviewSourceTokenTarget>[
        _EquationPreviewSourceTokenTarget(
          start: sourceBaseOffset + unit.start,
          end: sourceBaseOffset + math.min(unit.end, unit.start + 5),
          rect: radicalRect,
        ),
      ];
    }

    if (kind == OwnedEquationStructureKind.superscript) {
      final scriptRect = Rect.fromLTRB(
        fullRect.left,
        fullRect.top,
        fullRect.right,
        fullRect.top + (fullRect.height * 0.58),
      );
      return _tokenTargetsForRange(
        body: body,
        sourceBaseOffset: sourceBaseOffset,
        start: unit.contentStart ?? unit.start,
        end: unit.contentEnd ?? unit.end,
        rect: scriptRect,
      );
    }

    if (kind == OwnedEquationStructureKind.subscript) {
      final scriptRect = Rect.fromLTRB(
        fullRect.left,
        fullRect.top + (fullRect.height * 0.42),
        fullRect.right,
        fullRect.bottom,
      );
      return _tokenTargetsForRange(
        body: body,
        sourceBaseOffset: sourceBaseOffset,
        start: unit.contentStart ?? unit.start,
        end: unit.contentEnd ?? unit.end,
        rect: scriptRect,
      );
    }

    return _tokenTargetsForRange(
      body: body,
      sourceBaseOffset: sourceBaseOffset,
      start: unit.contentStart ?? unit.start,
      end: unit.contentEnd ?? unit.end,
      rect: fullRect,
    );
  }

  static List<_EquationPreviewSourceTokenTarget> _tokenTargetsForEnvironment({
    required OwnedEquationEnvironmentStructure environment,
    required String body,
    required int sourceBaseOffset,
    required Rect rect,
  }) {
    final targets = <_EquationPreviewSourceTokenTarget>[];
    final rowCount = math.max(1, environment.rowCount);
    final columnCount = math.max(1, environment.columnCount);
    final rowHeight = rect.height / rowCount;
    final columnWidth = rect.width / columnCount;
    for (var rowIndex = 0; rowIndex < environment.rows.length; rowIndex++) {
      final row = environment.rows[rowIndex];
      for (var columnIndex = 0; columnIndex < math.max(1, row.cells.length); columnIndex++) {
        final left = rect.left + columnIndex * columnWidth;
        final top = rect.top + rowIndex * rowHeight;
        final cellRect = Rect.fromLTRB(left, top, left + columnWidth, top + rowHeight);
        if (columnIndex >= row.cells.length) continue;
        final cell = row.cells[columnIndex];
        final cellTargets = _tokenTargetsForRange(
          body: body,
          sourceBaseOffset: sourceBaseOffset,
          start: cell.start,
          end: cell.end,
          rect: cellRect.deflate(1),
          fallback: cell.caretOffset,
        );
        targets.addAll(cellTargets);
      }
    }
    return targets;
  }

  static List<_EquationPreviewSourceTokenTarget> _tokenTargetsForRange({
    required String body,
    required int sourceBaseOffset,
    required int start,
    required int end,
    required Rect rect,
    int? fallback,
  }) {
    final safeStart = start.clamp(0, body.length).toInt();
    final safeEnd = end.clamp(safeStart, body.length).toInt();
    final tokens = <_EquationPreviewSourceToken>[];
    var i = safeStart;
    while (i < safeEnd) {
      final unit = body.codeUnitAt(i);
      final char = body[i];
      if (char == '{' || char == '}' || char == '[' || char == ']' || _isWhitespace(unit)) {
        i++;
        continue;
      }
      if (char == '\\') {
        final commandStart = i;
        i++;
        while (i < safeEnd && _isCommandLetter(body.codeUnitAt(i))) {
          i++;
        }
        tokens.add(_EquationPreviewSourceToken(commandStart, math.max(commandStart + 1, i)));
        continue;
      }
      tokens.add(_EquationPreviewSourceToken(i, i + 1));
      i++;
    }

    if (tokens.isEmpty) {
      final offset = sourceBaseOffset + (fallback ?? safeStart).clamp(0, body.length).toInt();
      final collapsedRect = Rect.fromCenter(
        center: rect.center,
        width: math.max(8.0, math.min(18.0, rect.width)).toDouble(),
        height: math.max(14.0, math.min(24.0, rect.height)).toDouble(),
      );
      return <_EquationPreviewSourceTokenTarget>[
        _EquationPreviewSourceTokenTarget(start: offset, end: offset, rect: collapsedRect),
      ];
    }

    final tokenWidth = rect.width / tokens.length;
    return <_EquationPreviewSourceTokenTarget>[
      for (var index = 0; index < tokens.length; index++)
        _EquationPreviewSourceTokenTarget(
          start: sourceBaseOffset + tokens[index].start,
          end: sourceBaseOffset + tokens[index].end,
          rect: Rect.fromLTRB(
            rect.left + tokenWidth * index,
            rect.top,
            rect.left + tokenWidth * (index + 1),
            rect.bottom,
          ).deflate(math.min(1.0, tokenWidth / 5)),
        ),
    ];
  }


  static List<_EquationPreviewVisualUnit> _visualUnitsForModel(
    OwnedEquationStructureModel structure,
  ) {
    final units = <_EquationPreviewVisualUnit>[];
    for (final child in structure.root.children) {
      final unit = _visualUnitForNode(structure, child);
      if (unit != null && unit.width > 0) units.add(unit);
    }
    return units;
  }

  static _EquationPreviewVisualUnit? _visualUnitForNode(
    OwnedEquationStructureModel structure,
    OwnedEquationStructureNode node,
  ) {
    switch (node.kind) {
      case OwnedEquationStructureKind.fraction:
        final numerator = node.children.isNotEmpty ? node.children.first : null;
        final denominator = node.children.length > 1 ? node.children[1] : null;
        final numeratorWidth = numerator == null ? 12.0 : _visualWidthForNode(structure, numerator);
        final denominatorWidth = denominator == null ? 12.0 : _visualWidthForNode(structure, denominator);
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: math.max(28.0, math.max(numeratorWidth, denominatorWidth) + 16.0),
          numeratorStart: numerator?.contentStart,
          numeratorEnd: numerator?.contentEnd,
          denominatorStart: denominator?.contentStart,
          denominatorEnd: denominator?.contentEnd,
        );
      case OwnedEquationStructureKind.squareRoot:
      case OwnedEquationStructureKind.textCommand:
        final group = node.children.isNotEmpty ? node.children.first : null;
        final contentWidth = group == null ? 14.0 : _visualWidthForNode(structure, group);
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: math.max(18.0, contentWidth + (node.kind == OwnedEquationStructureKind.squareRoot ? 16.0 : 2.0)),
          contentStart: group?.contentStart ?? node.contentStart,
          contentEnd: group?.contentEnd ?? node.contentEnd,
        );
      case OwnedEquationStructureKind.environment:
        final environment = _environmentForNode(structure, node);
        final rows = environment?.rowCount ?? 1;
        final columns = environment?.columnCount ?? 1;
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: math.max(34.0, math.min(220.0, columns * 28.0 + rows * 4.0 + 18.0)),
          contentStart: node.contentStart,
          contentEnd: node.contentEnd,
          environment: environment,
        );
      case OwnedEquationStructureKind.superscript:
      case OwnedEquationStructureKind.subscript:
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: math.max(8.0, _visualWidthForRange(structure.rawSource, node.contentStart, node.contentEnd) * 0.72 + 4.0),
          contentStart: node.contentStart,
          contentEnd: node.contentEnd,
        );
      case OwnedEquationStructureKind.group:
        final width = node.children.isEmpty
            ? _visualWidthForRange(structure.rawSource, node.contentStart, node.contentEnd)
            : node.children
                .map((child) => _visualWidthForNode(structure, child))
                .fold<double>(0, (sum, value) => sum + value);
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: math.max(1.0, width),
          contentStart: node.contentStart,
          contentEnd: node.contentEnd,
        );
      case OwnedEquationStructureKind.command:
        final command = node.command == null ? '' : '\\${node.command}';
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: _commandVisualWidth(command),
          contentStart: node.contentStart,
          contentEnd: node.contentEnd,
        );
      case OwnedEquationStructureKind.textRun:
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: math.max(10.0, (node.sourceEnd - node.sourceStart) * 9.0),
          contentStart: node.contentStart,
          contentEnd: node.contentEnd,
        );
      case OwnedEquationStructureKind.operatorToken:
      case OwnedEquationStructureKind.symbol:
        return _EquationPreviewVisualUnit(
          kind: node.kind,
          start: node.sourceStart,
          end: node.sourceEnd,
          width: 9.0,
          contentStart: node.contentStart,
          contentEnd: node.contentEnd,
        );
      case OwnedEquationStructureKind.root:
        return null;
    }
  }

  static double _visualWidthForNode(
    OwnedEquationStructureModel structure,
    OwnedEquationStructureNode node,
  ) {
    final unit = _visualUnitForNode(structure, node);
    if (unit != null) return unit.width;
    return _visualWidthForRange(structure.rawSource, node.contentStart, node.contentEnd);
  }

  static double _visualWidthForRange(String source, int? start, int? end) {
    final safeStart = (start ?? 0).clamp(0, source.length).toInt();
    final safeEnd = (end ?? safeStart).clamp(safeStart, source.length).toInt();
    if (safeEnd <= safeStart) return 10.0;
    return _visualWidthForSource(source.substring(safeStart, safeEnd));
  }

  static OwnedEquationEnvironmentStructure? _environmentForNode(
    OwnedEquationStructureModel structure,
    OwnedEquationStructureNode node,
  ) {
    for (final environment in structure.environments) {
      if (environment.beginStart == node.sourceStart &&
          environment.endEnd == node.sourceEnd &&
          environment.environment == node.environment) {
        return environment;
      }
    }
    return null;
  }

  static List<_EquationPreviewVisualUnit> _visualUnitsFor(String body) {
    final units = <_EquationPreviewVisualUnit>[];
    var i = 0;
    while (i < body.length) {
      final unit = body.codeUnitAt(i);
      final char = body[i];
      if (_isWhitespace(unit)) {
        final start = i;
        while (i < body.length && _isWhitespace(body.codeUnitAt(i))) {
          i++;
        }
        units.add(_EquationPreviewVisualUnit(start: start, end: i, width: 5.0));
        continue;
      }

      if (char == '\\') {
        final start = i;
        i++;
        while (i < body.length && _isCommandLetter(body.codeUnitAt(i))) {
          i++;
        }
        final command = body.substring(start, i);
        if (command == r'\frac') {
          final numerator = _readBalancedGroup(body, i);
          final denominator = numerator == null ? null : _readBalancedGroup(body, numerator.end);
          if (numerator != null && denominator != null) {
            final numeratorWidth = _visualWidthForSource(body.substring(numerator.contentStart, numerator.contentEnd));
            final denominatorWidth = _visualWidthForSource(body.substring(denominator.contentStart, denominator.contentEnd));
            final fractionWidth = math.max(26.0, math.max(numeratorWidth, denominatorWidth) + 16.0);
            units.add(_EquationPreviewVisualUnit(
              start: start,
              end: denominator.end,
              width: fractionWidth,
              numeratorStart: numerator.contentStart,
              numeratorEnd: numerator.contentEnd,
              denominatorStart: denominator.contentStart,
              denominatorEnd: denominator.contentEnd,
            ));
            i = denominator.end;
            continue;
          }
        }

        if (command == r'\sqrt' || command == r'\text' || command == r'\mathrm' || command == r'\mathbf') {
          final group = _readBalancedGroup(body, i);
          if (group != null) {
            final content = body.substring(group.contentStart, group.contentEnd);
            units.add(_EquationPreviewVisualUnit(
              kind: command == r'\sqrt' ? OwnedEquationStructureKind.squareRoot : OwnedEquationStructureKind.textCommand,
              start: start,
              end: group.end,
              width: math.max(18.0, _visualWidthForSource(content) + (command == r'\sqrt' ? 16.0 : 2.0)),
              contentStart: group.contentStart,
              contentEnd: group.contentEnd,
            ));
            i = group.end;
            continue;
          }
        }

        units.add(_EquationPreviewVisualUnit(
          start: start,
          end: i,
          width: _commandVisualWidth(command),
          contentStart: start,
          contentEnd: i,
        ));
        continue;
      }

      if (_isAlphaNumeric(unit)) {
        final start = i;
        while (i < body.length && _isAlphaNumeric(body.codeUnitAt(i))) {
          i++;
        }
        units.add(_EquationPreviewVisualUnit(
          start: start,
          end: i,
          width: math.max(10.0, (i - start) * 9.0),
          contentStart: start,
          contentEnd: i,
        ));
        continue;
      }

      if (char == '{' || char == '}' || char == '[' || char == ']') {
        units.add(_EquationPreviewVisualUnit(start: i, end: i + 1, width: 1.0));
        i++;
        continue;
      }

      units.add(_EquationPreviewVisualUnit(
        start: i,
        end: i + 1,
        width: char == '^' || char == '_' ? 3.0 : 9.0,
        contentStart: i,
        contentEnd: i + 1,
      ));
      i++;
    }
    return units.where((unit) => unit.width > 0).toList(growable: false);
  }

  static double _visualWidthForSource(String source) {
    if (source.isEmpty) return 10.0;
    return _visualUnitsFor(source).fold<double>(0, (sum, unit) => sum + unit.width).clamp(10.0, 180.0).toDouble();
  }

  static double _commandVisualWidth(String command) {
    if (command == r'\quad') return 24.0;
    if (command == r'\qquad') return 42.0;
    if (command == r'\int') return 24.0;
    if (command == r'\sum') return 24.0;
    if (command == r'\infty') return 18.0;
    if (command == r'\prime') return 6.0;
    if (command == r'\left' || command == r'\right') return 2.0;
    if (command.length <= 2) return 8.0;
    return 13.0;
  }

  static _BalancedSourceGroup? _readBalancedGroup(String source, int offset) {
    var i = offset;
    while (i < source.length && _isWhitespace(source.codeUnitAt(i))) {
      i++;
    }
    if (i >= source.length || source[i] != '{') return null;
    var depth = 0;
    for (var j = i; j < source.length; j++) {
      final char = source[j];
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) return _BalancedSourceGroup(i, j + 1);
      }
    }
    return null;
  }

  static bool _isWhitespace(int unit) => unit == 32 || unit == 9 || unit == 10 || unit == 13;

  static bool _isAlphaNumeric(int unit) {
    return (unit >= 48 && unit <= 57) || (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  }

  static bool _isCommandLetter(int unit) {
    return (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  }
}




TextStyle _ownedEquationInkTextStyle(
  TextStyle base, {
  required double fontSize,
  bool italic = false,
  bool bold = false,
  Color? color,
}) {
  // Active preview math uses an academic serif stack instead of inheriting the
  // app/body font. Cambria Math is present on Windows and gives the owned ink
  // renderer a much closer display-math feel while preserving our exact hit
  // boxes. The fallbacks keep the renderer usable on other platforms.
  return base.copyWith(
    color: color ?? base.color,
    fontFamily: 'Cambria Math',
    fontFamilyFallback: const <String>[
      'STIX Two Math',
      'STIX Two Text',
      'Latin Modern Math',
      'Cambria',
      'Times New Roman',
      'Georgia',
    ],
    fontSize: fontSize,
    height: 1.0,
    letterSpacing: italic ? -0.16 : -0.08,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
  );
}

class _OwnedEquationInkLayout {
  const _OwnedEquationInkLayout({
    required this.size,
    required this.viewport,
    required this.scale,
    required this.origin,
    required this.targets,
    required this.glyphs,
    required this.lines,
  });

  final Size size;
  final Rect viewport;
  final double scale;
  final Offset origin;
  final List<_EquationPreviewSourceTokenTarget> targets;
  final List<_OwnedEquationInkGlyph> glyphs;
  final List<_OwnedEquationInkLine> lines;

  List<Rect> previewRectsForSourceSelection(_EquationPreviewSourceSelection selection) {
    if (targets.isEmpty) return const <Rect>[];
    final selectedTargets = targets
        .where((target) => target.intersects(selection.start, selection.end))
        .toList(growable: false);
    if (selectedTargets.isNotEmpty) {
      return selectedTargets.map((target) => target.rect).take(12).toList(growable: false);
    }

    if (!selection.isCollapsed) return const <Rect>[];
    _EquationPreviewSourceTokenTarget? containing;
    var smallestWidth = double.infinity;
    for (final target in targets) {
      if (!target.containsOffset(selection.start)) continue;
      final width = math.max(1.0, target.end - target.start).toDouble();
      if (width < smallestWidth) {
        smallestWidth = width;
        containing = target;
      }
    }
    if (containing != null) return <Rect>[containing.rect];
    return const <Rect>[];
  }
}

class _OwnedEquationInkGlyph {
  const _OwnedEquationInkGlyph({
    required this.text,
    required this.rect,
    required this.baseline,
    required this.fontSize,
    required this.italic,
    required this.bold,
    required this.sourceStart,
    required this.sourceEnd,
  });

  final String text;
  final Rect rect;
  final double baseline;
  final double fontSize;
  final bool italic;
  final bool bold;
  final int sourceStart;
  final int sourceEnd;

  _OwnedEquationInkGlyph shift({required double dx, required double dy}) {
    return _OwnedEquationInkGlyph(
      text: text,
      rect: rect.shift(Offset(dx, dy)),
      baseline: baseline,
      fontSize: fontSize,
      italic: italic,
      bold: bold,
      sourceStart: sourceStart,
      sourceEnd: sourceEnd,
    );
  }
}

class _OwnedEquationInkLine {
  const _OwnedEquationInkLine({
    required this.start,
    required this.end,
    required this.strokeWidth,
  });

  final Offset start;
  final Offset end;
  final double strokeWidth;

  _OwnedEquationInkLine shift({required double dx, required double dy}) {
    final delta = Offset(dx, dy);
    return _OwnedEquationInkLine(
      start: start + delta,
      end: end + delta,
      strokeWidth: strokeWidth,
    );
  }
}


class _EquationTeXPreview extends StatelessWidget {
  const _EquationTeXPreview({
    required this.source,
    required this.textStyle,
    required this.color,
    required this.errorColor,
  });

  final String source;
  final TextStyle textStyle;
  final Color color;
  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    final baseFontSize = textStyle.fontSize ?? 24.0;
    final mathStyle = textStyle.copyWith(
      color: color,
      fontSize: baseFontSize * 1.06,
      fontWeight: FontWeight.w500,
      height: 1.28,
    );
    final fallbackStyle = mathStyle.copyWith(
      color: errorColor,
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>[],
      fontSize: baseFontSize * 0.78,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
          child: Align(
            alignment: Alignment.center,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 4),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.max(0, constraints.maxWidth - 108),
                ),
                child: Center(
                  child: Math.tex(
                    source.trim().isEmpty ? r'{}' : source,
                    mathStyle: MathStyle.display,
                    textStyle: mathStyle,
                    onErrorFallback: (error) => Text(
                      source,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: fallbackStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OwnedEquationInkPreviewPainter extends CustomPainter {
  const _OwnedEquationInkPreviewPainter({
    required this.layout,
    required this.textStyle,
    required this.textScaler,
    required this.color,
    required this.structureColor,
    required this.accentColor,
  });

  final _OwnedEquationInkLayout layout;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final Color color;
  final Color structureColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = Offset.zero & size;
    canvas.save();
    canvas.clipRect(clip);

    final linePaint = Paint()
      ..color = structureColor.withValues(alpha: 0.86)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final line in layout.lines) {
      linePaint.strokeWidth = line.strokeWidth;
      canvas.drawLine(line.start, line.end, linePaint);
    }

    for (final glyph in layout.glyphs) {
      final effectiveStyle = _ownedEquationInkTextStyle(
        textStyle,
        fontSize: glyph.fontSize,
        italic: glyph.italic,
        bold: glyph.bold,
        color: color,
      );
      final painter = TextPainter(
        text: TextSpan(text: glyph.text, style: effectiveStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final lineMetrics = painter.computeLineMetrics();
      final actualBaseline = lineMetrics.isEmpty ? painter.height * 0.78 : lineMetrics.first.baseline;
      final paintOffset = Offset(
        glyph.rect.left,
        glyph.rect.top + glyph.baseline - actualBaseline,
      );
      painter.paint(canvas, paintOffset);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OwnedEquationInkPreviewPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.textStyle != textStyle ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.color != color ||
        oldDelegate.structureColor != structureColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _SemanticEquationPreviewBox {
  const _SemanticEquationPreviewBox({
    required this.width,
    required this.height,
    required this.baseline,
    this.targets = const <_EquationPreviewSourceTokenTarget>[],
    this.glyphs = const <_OwnedEquationInkGlyph>[],
    this.lines = const <_OwnedEquationInkLine>[],
  });

  final double width;
  final double height;
  final double baseline;
  final List<_EquationPreviewSourceTokenTarget> targets;
  final List<_OwnedEquationInkGlyph> glyphs;
  final List<_OwnedEquationInkLine> lines;
}

class _EquationPreviewUnitLayout {
  const _EquationPreviewUnitLayout({
    required this.unit,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.mathCenterY,
    required this.scale,
  });

  final _EquationPreviewVisualUnit unit;
  final double left;
  final double right;
  final double top;
  final double bottom;
  final double mathCenterY;
  final double scale;

  Rect get rect => Rect.fromLTRB(left, top, right, bottom);
}

class _EquationPreviewVisualUnit {
  const _EquationPreviewVisualUnit({
    required this.start,
    required this.end,
    required this.width,
    this.contentStart,
    this.contentEnd,
    this.numeratorStart,
    this.numeratorEnd,
    this.denominatorStart,
    this.denominatorEnd,
    this.environment,
    this.kind,
  });

  final int start;
  final int end;
  final double width;
  final int? contentStart;
  final int? contentEnd;
  final int? numeratorStart;
  final int? numeratorEnd;
  final int? denominatorStart;
  final int? denominatorEnd;
  final OwnedEquationEnvironmentStructure? environment;
  final OwnedEquationStructureKind? kind;

  bool get isFraction =>
      numeratorStart != null &&
      numeratorEnd != null &&
      denominatorStart != null &&
      denominatorEnd != null;

  int sourceOffsetForTap({
    required String body,
    required int sourceBaseOffset,
    required double x,
    required double y,
    required double left,
    required double right,
    required double mathCenterY,
  }) {
    return sourceSelectionForTap(
      body: body,
      sourceBaseOffset: sourceBaseOffset,
      x: x,
      y: y,
      left: left,
      right: right,
      mathCenterY: mathCenterY,
    ).start;
  }

  _EquationPreviewSourceSelection sourceSelectionForTap({
    required String body,
    required int sourceBaseOffset,
    required double x,
    required double y,
    required double left,
    required double right,
    required double mathCenterY,
  }) {
    final localRatio = right <= left
        ? 0.0
        : ((x - left) / (right - left)).clamp(0.0, 1.0).toDouble();

    if (isFraction) {
      final targetStart = y < mathCenterY ? numeratorStart! : denominatorStart!;
      final targetEnd = y < mathCenterY ? numeratorEnd! : denominatorEnd!;
      return _selectionInsideRange(
        body,
        targetStart,
        targetEnd,
        localRatio,
        sourceBaseOffset,
      );
    }

    final environmentInfo = environment;
    if (environmentInfo != null && environmentInfo.rows.isNotEmpty) {
      final rowCount = math.max(1, environmentInfo.rowCount);
      final columnCount = math.max(1, environmentInfo.columnCount);
      final visualHeight = math.max(24.0, rowCount * 17.0);
      final top = mathCenterY - visualHeight / 2;
      final rowIndex = ((y - top) / (visualHeight / rowCount))
          .floor()
          .clamp(0, rowCount - 1)
          .toInt();
      final columnIndex = (localRatio * columnCount)
          .floor()
          .clamp(0, columnCount - 1)
          .toInt();
      final row = environmentInfo.rows[rowIndex.clamp(0, environmentInfo.rows.length - 1).toInt()];
      if (columnIndex < row.cells.length) {
        final cell = row.cells[columnIndex];
        return _selectionInsideRange(
          body,
          cell.start,
          cell.end,
          0,
          sourceBaseOffset,
          fallback: cell.caretOffset,
        );
      }
      return _EquationPreviewSourceSelection.collapsed(
        sourceBaseOffset + row.end.clamp(0, body.length).toInt(),
      );
    }

    final targetStart = contentStart ?? start;
    final targetEnd = contentEnd ?? end;
    return _selectionInsideRange(
      body,
      targetStart,
      targetEnd,
      localRatio,
      sourceBaseOffset,
    );
  }

  static int _offsetInsideRange(String body, int start, int end, double ratio) {
    return _selectionInsideRange(body, start, end, ratio, 0).start;
  }

  static _EquationPreviewSourceSelection _selectionInsideRange(
    String body,
    int start,
    int end,
    double ratio,
    int sourceBaseOffset, {
    int? fallback,
  }) {
    final safeStart = start.clamp(0, body.length).toInt();
    final safeEnd = end.clamp(safeStart, body.length).toInt();
    if (safeEnd <= safeStart) {
      return _EquationPreviewSourceSelection.collapsed(
        sourceBaseOffset + (fallback ?? safeStart).clamp(0, body.length).toInt(),
      );
    }

    final tokens = <_EquationPreviewSourceToken>[];
    var i = safeStart;
    while (i < safeEnd) {
      final char = body[i];
      final unit = body.codeUnitAt(i);
      if (char == '{' || char == '}' || char == '[' || char == ']' || _EquationPreviewSourceMap._isWhitespace(unit)) {
        i++;
        continue;
      }
      if (char == '\\') {
        final commandStart = i;
        i++;
        while (i < safeEnd && _EquationPreviewSourceMap._isCommandLetter(body.codeUnitAt(i))) {
          i++;
        }
        tokens.add(_EquationPreviewSourceToken(commandStart, math.max(commandStart + 1, i)));
        continue;
      }
      // Keep rendered letters/numbers individually addressable. Clicking E,
      // f, x, y, or z should select that exact source token, not just move to
      // a rough sub-expression boundary.
      tokens.add(_EquationPreviewSourceToken(i, i + 1));
      i++;
    }

    if (tokens.isEmpty) {
      return _EquationPreviewSourceSelection.collapsed(
        sourceBaseOffset + (fallback ?? safeStart).clamp(0, body.length).toInt(),
      );
    }
    final index = (ratio * (tokens.length - 1)).round().clamp(0, tokens.length - 1).toInt();
    final token = tokens[index];
    return _EquationPreviewSourceSelection(
      start: sourceBaseOffset + token.start,
      end: sourceBaseOffset + token.end,
    );
  }
}

class _EquationPreviewSourceSelection {
  const _EquationPreviewSourceSelection({
    required this.start,
    required this.end,
  });

  const _EquationPreviewSourceSelection.collapsed(int offset)
      : start = offset,
        end = offset;

  final int start;
  final int end;

  bool get isRange => end > start;

  bool get isCollapsed => end <= start;
}

class _EquationPreviewSourceToken {
  const _EquationPreviewSourceToken(this.start, this.end);

  final int start;
  final int end;
}


class _EquationPreviewSourceTokenTarget {
  const _EquationPreviewSourceTokenTarget({
    required this.start,
    required this.end,
    required this.rect,
  });

  final int start;
  final int end;
  final Rect rect;

  _EquationPreviewSourceSelection get selection => _EquationPreviewSourceSelection(start: start, end: end);

  bool intersects(int selectionStart, int selectionEnd) {
    if (selectionEnd <= selectionStart) return containsOffset(selectionStart);
    final safeEnd = end <= start ? start + 1 : end;
    return start < selectionEnd && safeEnd > selectionStart;
  }

  bool containsOffset(int offset) {
    if (end <= start) return offset == start;
    return offset >= start && offset <= end;
  }

  double distanceTo(Offset point) {
    if (rect.contains(point)) return 0;
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : point.dx > rect.right
            ? point.dx - rect.right
            : 0.0;
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : point.dy > rect.bottom
            ? point.dy - rect.bottom
            : 0.0;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _EquationPreviewErrorPlaceholder extends StatelessWidget {
  const _EquationPreviewErrorPlaceholder({
    required this.message,
    required this.color,
    required this.textStyle,
  });

  final String message;
  final Color color;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 15, color: color),
            const SizedBox(width: 7),
            Text(
              message,
              style: textStyle?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EquationPreviewHighlightPainter extends CustomPainter {
  const _EquationPreviewHighlightPainter({
    required this.activeRects,
    required this.hoverRects,
    required this.diagnosticRects,
    required this.activeColor,
    required this.hoverColor,
    required this.diagnosticColor,
  });

  final List<Rect> activeRects;
  final List<Rect> hoverRects;
  final List<Rect> diagnosticRects;
  final Color activeColor;
  final Color hoverColor;
  final Color diagnosticColor;

  @override
  void paint(Canvas canvas, Size size) {
    void drawSoftTargets({
      required List<Rect> rects,
      required Color color,
      required bool active,
    }) {
      if (rects.isEmpty) return;
      final bounds = Offset.zero & size;
      final fillPaint = Paint()
        ..color = color.withValues(alpha: active ? 0.075 : 0.055)
        ..style = PaintingStyle.fill;
      final glowPaint = Paint()
        ..color = color.withValues(alpha: active ? 0.105 : 0.075)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.6 : 2.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
      final accentPaint = Paint()
        ..color = color.withValues(alpha: active ? 0.46 : 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 1.7 : 1.2
        ..strokeCap = StrokeCap.round;

      for (final rect in rects.take(16)) {
        final bounded = rect.intersect(bounds);
        if (bounded.isEmpty) continue;
        final compact = bounded.height < 26 || bounded.width < 18;
        final visualRect = compact
            ? Rect.fromCenter(
                center: bounded.center,
                width: math.max(12.0, math.min(bounded.width + 6.0, 28.0)),
                height: math.max(14.0, math.min(bounded.height + 5.0, 26.0)),
              ).intersect(bounds)
            : bounded.deflate(math.min(2.5, bounded.shortestSide / 8));
        if (visualRect.isEmpty) continue;

        final radius = Radius.circular(math.min(12.0, math.max(7.0, visualRect.shortestSide / 2.4)));
        final rrect = RRect.fromRectAndRadius(visualRect, radius);
        canvas.drawRRect(rrect, fillPaint);

        // A soft bottom accent reads as a selected math token without the
        // heavy boxed/square feel of a debugging overlay.
        final y = math.min(visualRect.bottom - 1.6, visualRect.top + visualRect.height * 0.78);
        final start = Offset(visualRect.left + 2.0, y);
        final end = Offset(visualRect.right - 2.0, y);
        if ((end.dx - start.dx).abs() >= 2.0) {
          canvas.drawLine(start, end, glowPaint);
          canvas.drawLine(start, end, accentPaint);
        }
      }
    }

    drawSoftTargets(rects: diagnosticRects, color: diagnosticColor, active: true);
    drawSoftTargets(rects: hoverRects, color: hoverColor, active: false);
    drawSoftTargets(rects: activeRects, color: activeColor, active: true);
  }

  @override
  bool shouldRepaint(covariant _EquationPreviewHighlightPainter oldDelegate) {
    return oldDelegate.activeRects != activeRects ||
        oldDelegate.hoverRects != hoverRects ||
        oldDelegate.diagnosticRects != diagnosticRects ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.hoverColor != hoverColor ||
        oldDelegate.diagnosticColor != diagnosticColor;
  }
}

class _BalancedSourceGroup {
  const _BalancedSourceGroup(this.start, this.end);

  final int start;
  final int end;

  int get contentStart => math.min(start + 1, end);

  int get contentEnd => math.max(start + 1, end - 1);
}

const List<(String, String)> _equationSymbols = <(String, String)>[
  ('α', r'\alpha '),
  ('β', r'\beta '),
  ('γ', r'\gamma '),
  ('δ', r'\delta '),
  ('λ', r'\lambda '),
  ('μ', r'\mu '),
  ('σ', r'\sigma '),
  ('π', r'\pi '),
  ('∞', r'\infty '),
  ('≈', r'\approx '),
  ('≤', r'\leq '),
  ('≥', r'\geq '),
  ('∑', r'\sum '),
  ('∫', r'\int '),
];


class _EquationAuthoringHeader extends StatelessWidget {
  const _EquationAuthoringHeader({
    required this.compact,
    required this.onInsertFraction,
    required this.onInsertSuperscript,
    required this.onInsertSubscript,
    required this.onInsertText,
    required this.onInsertDerivative,
    required this.onInsertMatrix,
    required this.onInsertAligned,
    required this.onInsertCases,
    required this.onInsertMatrixRow,
    required this.onInsertMatrixColumn,
    required this.onInsertAlignedLine,
    required this.onInsertAlignmentMarker,
    required this.onInsertCasesRow,
    required this.structureContext,
    required this.editingContext,
    required this.subexpressionTargets,
    required this.activeSourceOffset,
    required this.onJumpToSourceOffset,
    required this.onStructureCellSelected,
    required this.onInsertSymbol,
    required this.numbered,
    required this.numberLabel,
    required this.equationLabel,
    required this.onToggleNumbered,
    required this.onEditLabel,
    required this.onCopyReference,
    required this.onFormatSource,
    required this.onJumpToDiagnostic,
  });

  final bool compact;
  final VoidCallback? onInsertFraction;
  final VoidCallback? onInsertSuperscript;
  final VoidCallback? onInsertSubscript;
  final VoidCallback? onInsertText;
  final VoidCallback? onInsertDerivative;
  final VoidCallback? onInsertMatrix;
  final VoidCallback? onInsertAligned;
  final VoidCallback? onInsertCases;
  final VoidCallback? onInsertMatrixRow;
  final VoidCallback? onInsertMatrixColumn;
  final VoidCallback? onInsertAlignedLine;
  final VoidCallback? onInsertAlignmentMarker;
  final VoidCallback? onInsertCasesRow;
  final OwnedEquationStructureContext? structureContext;
  final _EquationEditingContext editingContext;
  final List<OwnedEquationSubexpressionTarget> subexpressionTargets;
  final int? activeSourceOffset;
  final ValueChanged<String>? onInsertSymbol;
  final bool numbered;
  final String? numberLabel;
  final String? equationLabel;
  final VoidCallback? onToggleNumbered;
  final VoidCallback? onEditLabel;
  final VoidCallback? onCopyReference;
  final VoidCallback? onFormatSource;
  final ValueChanged<OwnedEquationDiagnostic>? onJumpToDiagnostic;
  final ValueChanged<int>? onJumpToSourceOffset;
  final void Function(OwnedEquationStructureContext contextInfo, int rowIndex, int columnIndex)? onStructureCellSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.10,
    );
    final info = structureContext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Equation source',
                  style: labelStyle?.copyWith(color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                _EquationToolMenu(
                  label: 'Build',
                  tooltip: 'Insert common equation parts',
                  entries: <_EquationAction>[
                    _EquationAction(definition: OwnedEquationToolRegistry.fraction, onPressed: onInsertFraction),
                    _EquationAction(definition: OwnedEquationToolRegistry.superscript, onPressed: onInsertSuperscript),
                    _EquationAction(definition: OwnedEquationToolRegistry.subscript, onPressed: onInsertSubscript),
                    _EquationAction(definition: OwnedEquationToolRegistry.text, onPressed: onInsertText),
                    _EquationAction(definition: OwnedEquationToolRegistry.derivative, onPressed: onInsertDerivative),
                  ],
                ),
                const SizedBox(width: 6),
                _EquationSymbolsMenu(onInsertSymbol: onInsertSymbol),
                const SizedBox(width: 6),
                _EquationToolMenu(
                  label: 'Structures',
                  tooltip: 'Insert matrix, aligned, or cases structures',
                  entries: <_EquationAction>[
                    _EquationAction(definition: OwnedEquationToolRegistry.matrix, onPressed: onInsertMatrix, labelOverride: 'Matrix'),
                    _EquationAction(definition: OwnedEquationToolRegistry.aligned, onPressed: onInsertAligned, labelOverride: 'Aligned'),
                    _EquationAction(definition: OwnedEquationToolRegistry.cases, onPressed: onInsertCases, labelOverride: 'Cases'),
                  ],
                ),
                const SizedBox(width: 6),
                _EquationToolButton(
                  label: OwnedEquationToolRegistry.format.label,
                  tooltip: OwnedEquationToolRegistry.format.tooltip,
                  onPressed: onFormatSource,
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 18, color: colorScheme.outlineVariant.withValues(alpha: 0.75)),
                const SizedBox(width: 12),
                _EquationToolButton(
                  label: numbered ? 'Numbered' : 'Unnumbered',
                  tooltip: numbered
                      ? 'Turn equation numbering off'
                      : 'Turn equation numbering on',
                  onPressed: onToggleNumbered,
                ),
                const SizedBox(width: 6),
                _EquationToolButton(
                  label: (equationLabel?.trim().isNotEmpty ?? false) ? equationLabel!.trim() : 'Label',
                  tooltip: (equationLabel?.trim().isNotEmpty ?? false)
                      ? 'Edit equation label ${equationLabel!.trim()}'
                      : 'Add equation label',
                  onPressed: onEditLabel,
                ),
                const SizedBox(width: 6),
                _EquationToolMenu(
                  label: 'More',
                  tooltip: 'Reference and navigation tools',
                  entries: <_EquationAction>[
                    _EquationAction(
                      definition: OwnedEquationToolRegistry.copyReference,
                      onPressed: onCopyReference,
                      labelOverride: numberLabel?.trim().isNotEmpty == true
                          ? 'Copy ${numberLabel!.trim()}'
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 52,
          child: _EquationContextualToolStrip(
            contextInfo: info,
            editingContext: editingContext,
            compact: compact,
            onInsertFraction: onInsertFraction,
            onInsertSuperscript: onInsertSuperscript,
            onInsertSubscript: onInsertSubscript,
            onInsertText: onInsertText,
            onInsertDerivative: onInsertDerivative,
            onInsertMatrix: onInsertMatrix,
            onInsertAligned: onInsertAligned,
            onInsertCases: onInsertCases,
            onInsertMatrixRow: onInsertMatrixRow,
            onInsertMatrixColumn: onInsertMatrixColumn,
            onInsertAlignedLine: onInsertAlignedLine,
            onInsertAlignmentMarker: onInsertAlignmentMarker,
            onInsertCasesRow: onInsertCasesRow,
            onFormatSource: onFormatSource,
            onJumpToSourceOffset: onJumpToSourceOffset,
            onJumpToDiagnostic: onJumpToDiagnostic,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 56,
          child: _EquationStructureToolStrip(
            contextInfo: info,
            subexpressionTargets: subexpressionTargets,
            activeSourceOffset: activeSourceOffset,
            onJumpToSourceOffset: onJumpToSourceOffset,
            onStructureCellSelected: onStructureCellSelected,
            onInsertMatrix: onInsertMatrix,
            onInsertAligned: onInsertAligned,
            onInsertCases: onInsertCases,
            onInsertMatrixRow: onInsertMatrixRow,
            onInsertMatrixColumn: onInsertMatrixColumn,
            onInsertAlignedLine: onInsertAlignedLine,
            onInsertAlignmentMarker: onInsertAlignmentMarker,
            onInsertCasesRow: onInsertCasesRow,
          ),
        ),
      ],
    );
  }
}






class _EquationContextualToolStrip extends StatelessWidget {
  const _EquationContextualToolStrip({
    required this.contextInfo,
    required this.editingContext,
    required this.compact,
    required this.onInsertFraction,
    required this.onInsertSuperscript,
    required this.onInsertSubscript,
    required this.onInsertText,
    required this.onInsertDerivative,
    required this.onInsertMatrix,
    required this.onInsertAligned,
    required this.onInsertCases,
    required this.onInsertMatrixRow,
    required this.onInsertMatrixColumn,
    required this.onInsertAlignedLine,
    required this.onInsertAlignmentMarker,
    required this.onInsertCasesRow,
    required this.onFormatSource,
    required this.onJumpToSourceOffset,
    required this.onJumpToDiagnostic,
  });

  final OwnedEquationStructureContext? contextInfo;
  final _EquationEditingContext editingContext;
  final bool compact;
  final VoidCallback? onInsertFraction;
  final VoidCallback? onInsertSuperscript;
  final VoidCallback? onInsertSubscript;
  final VoidCallback? onInsertText;
  final VoidCallback? onInsertDerivative;
  final VoidCallback? onInsertMatrix;
  final VoidCallback? onInsertAligned;
  final VoidCallback? onInsertCases;
  final VoidCallback? onInsertMatrixRow;
  final VoidCallback? onInsertMatrixColumn;
  final VoidCallback? onInsertAlignedLine;
  final VoidCallback? onInsertAlignmentMarker;
  final VoidCallback? onInsertCasesRow;
  final VoidCallback? onFormatSource;
  final ValueChanged<int>? onJumpToSourceOffset;
  final ValueChanged<OwnedEquationDiagnostic>? onJumpToDiagnostic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final studioContext = editingContext;
    final actions = _contextActions(studioContext);
    final contextLabel = studioContext.headline;
    final contextDetail = studioContext.detail;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.46)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: compact ? 118 : 154,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: studioContext.primaryDiagnostic == null
                          ? (studioContext.structureContext == null ? colorScheme.onSurfaceVariant : colorScheme.primary)
                          : colorScheme.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    contextDetail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
                      fontSize: 9.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final action in actions) ...[
                      _EquationToolButton(
                        label: action.label,
                        tooltip: action.tooltip,
                        onPressed: action.onPressed,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (!compact && studioContext.primaryDiagnostic == null && studioContext.structureContext == null) ...[
                      Text(
                        'Structures live in the drawer until you are editing one.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_EquationAction> _contextActions(_EquationEditingContext context) {
    final diagnostic = context.primaryDiagnostic;
    if (diagnostic != null) {
      return <_EquationAction>[
        _EquationAction(
          definition: OwnedEquationToolRegistry.visualTargets,
          onPressed: onJumpToDiagnostic == null ? null : () => onJumpToDiagnostic!(diagnostic),
          labelOverride: 'Jump to issue',
          tooltipOverride: 'Select the source range that produced this problem',
        ),
        _EquationAction(
          definition: OwnedEquationToolRegistry.format,
          onPressed: onFormatSource,
          labelOverride: 'Format',
          tooltipOverride: 'Normalize display delimiters and source layout',
        ),
      ];
    }

    final info = context.structureContext;
    if (info == null) {
      final target = context.activeTarget;
      if (target != null) {
        return <_EquationAction>[
          _EquationAction(
            definition: OwnedEquationToolRegistry.visualTargets,
            onPressed: onJumpToSourceOffset == null ? null : () => onJumpToSourceOffset!(target.targetOffset),
            labelOverride: 'Select source',
            tooltipOverride: 'Move the source caret to this visual math part',
          ),
          _EquationAction(definition: OwnedEquationToolRegistry.superscript, onPressed: onInsertSuperscript),
          _EquationAction(definition: OwnedEquationToolRegistry.subscript, onPressed: onInsertSubscript),
          _EquationAction(definition: OwnedEquationToolRegistry.fraction, onPressed: onInsertFraction),
        ];
      }
      return <_EquationAction>[
        _EquationAction(definition: OwnedEquationToolRegistry.fraction, onPressed: onInsertFraction),
        _EquationAction(definition: OwnedEquationToolRegistry.superscript, onPressed: onInsertSuperscript),
        _EquationAction(definition: OwnedEquationToolRegistry.subscript, onPressed: onInsertSubscript),
        _EquationAction(definition: OwnedEquationToolRegistry.text, onPressed: onInsertText),
      ];
    }

    if (info.isMatrix) {
      return <_EquationAction>[
        _EquationAction(definition: OwnedEquationToolRegistry.matrixRow, onPressed: onInsertMatrixRow),
        _EquationAction(definition: OwnedEquationToolRegistry.matrixColumn, onPressed: onInsertMatrixColumn),
        _EquationAction(
          definition: OwnedEquationToolRegistry.format,
          onPressed: onFormatSource,
          labelOverride: 'Normalize',
          tooltipOverride: 'Normalize the matrix source while preserving the grid',
        ),
      ];
    }
    if (info.isAligned) {
      return <_EquationAction>[
        _EquationAction(definition: OwnedEquationToolRegistry.alignedLine, onPressed: onInsertAlignedLine),
        _EquationAction(definition: OwnedEquationToolRegistry.alignmentMarker, onPressed: onInsertAlignmentMarker),
        _EquationAction(
          definition: OwnedEquationToolRegistry.format,
          onPressed: onFormatSource,
          labelOverride: 'Format',
          tooltipOverride: 'Normalize aligned source layout',
        ),
      ];
    }
    if (info.isCases) {
      return <_EquationAction>[
        _EquationAction(definition: OwnedEquationToolRegistry.casesRow, onPressed: onInsertCasesRow),
        _EquationAction(
          definition: OwnedEquationToolRegistry.format,
          onPressed: onFormatSource,
          labelOverride: 'Format',
          tooltipOverride: 'Normalize cases source layout',
        ),
      ];
    }
    return <_EquationAction>[
      _EquationAction(definition: OwnedEquationToolRegistry.fraction, onPressed: onInsertFraction),
    ];
  }
}

class _EquationAction {
  const _EquationAction({
    required this.definition,
    required this.onPressed,
    this.labelOverride,
    this.tooltipOverride,
  });

  final OwnedEquationToolDefinition definition;
  final VoidCallback? onPressed;
  final String? labelOverride;
  final String? tooltipOverride;

  String get label => labelOverride ?? definition.label;

  String get tooltip => tooltipOverride ?? definition.tooltip;
}

class _EquationToolMenu extends StatelessWidget {
  const _EquationToolMenu({
    required this.label,
    required this.tooltip,
    required this.entries,
  });

  final String label;
  final String tooltip;
  final List<_EquationAction> entries;

  @override
  Widget build(BuildContext context) {
    final enabled = entries.any((entry) => entry.onPressed != null);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: PopupMenuButton<_EquationAction>(
        enabled: enabled,
        tooltip: tooltip,
        onSelected: (entry) => entry.onPressed?.call(),
        itemBuilder: (context) => <PopupMenuEntry<_EquationAction>>[
          for (final entry in entries)
            PopupMenuItem<_EquationAction>(
              value: entry,
              enabled: entry.onPressed != null,
              child: _EquationMenuItemLabel(action: entry),
            ),
        ],
        child: _EquationMenuChip(label: label, enabled: enabled),
      ),
    );
  }
}

class _EquationSymbolsMenu extends StatelessWidget {
  const _EquationSymbolsMenu({required this.onInsertSymbol});

  final ValueChanged<String>? onInsertSymbol;

  @override
  Widget build(BuildContext context) {
    final enabled = onInsertSymbol != null;
    return Tooltip(
      message: 'Insert common math symbols',
      waitDuration: const Duration(milliseconds: 350),
      child: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: 'Insert common math symbols',
        onSelected: (source) => onInsertSymbol?.call(source),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          for (final item in _equationSymbols)
            PopupMenuItem<String>(
              value: item.$2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      item.$1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.$2.trim(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: <String>['Consolas', 'Menlo', 'monospace'],
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: _EquationMenuChip(label: 'Symbols', enabled: enabled),
      ),
    );
  }
}

class _EquationMenuItemLabel extends StatelessWidget {
  const _EquationMenuItemLabel({required this.action});

  final _EquationAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          action.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: action.onPressed == null
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                : colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
            fontFamilyFallback: const <String>['Consolas', 'Menlo', 'monospace'],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 220,
          child: Text(
            action.tooltip,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EquationMenuChip extends StatelessWidget {
  const _EquationMenuChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: enabled ? 0.30 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: enabled ? 0.16 : 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: enabled
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: enabled
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}
class OwnedEquationStructureContext {
  const OwnedEquationStructureContext({
    required this.environment,
    required this.beginStart,
    required this.contentStart,
    required this.contentEnd,
    required this.endEnd,
    required this.rows,
  });

  final String environment;
  final int beginStart;
  final int contentStart;
  final int contentEnd;
  final int endEnd;
  final List<OwnedEquationStructureRow> rows;

  int get rowCount => math.max(1, rows.length);

  int get columnCount {
    if (rows.isEmpty) return 1;
    return rows
        .map((row) => math.max(1, row.cells.length))
        .fold<int>(1, (previous, value) => math.max(previous, value).toInt());
  }

  bool get isMatrix => const <String>{'matrix', 'pmatrix', 'bmatrix', 'vmatrix', 'Vmatrix', 'smallmatrix'}.contains(environment);

  bool get isAligned => const <String>{'aligned', 'alignedat', 'split', 'gathered'}.contains(environment);

  bool get isCases => environment == 'cases';

  String get displayName {
    if (isMatrix) return 'Matrix';
    if (isAligned) return 'Aligned';
    if (isCases) return 'Cases';
    return environment;
  }

  String get dimensionLabel {
    if (isMatrix) return '$rowCount×$columnCount';
    if (isCases) return '$rowCount cases';
    if (isAligned) return '$rowCount lines';
    return '$rowCount rows';
  }

  static OwnedEquationStructureContext? fromModel(
    OwnedEquationStructureModel model,
    int? activeOffset,
  ) {
    final environment = model.environmentForOffset(
      const <String>{
        'matrix',
        'pmatrix',
        'bmatrix',
        'vmatrix',
        'Vmatrix',
        'smallmatrix',
        'aligned',
        'alignedat',
        'split',
        'gathered',
        'cases',
      },
      activeOffset,
    );
    if (environment == null) return null;
    return OwnedEquationStructureContext(
      environment: environment.environment,
      beginStart: environment.beginStart,
      contentStart: environment.contentStart,
      contentEnd: environment.contentEnd,
      endEnd: environment.endEnd,
      rows: environment.rows.isEmpty
          ? <OwnedEquationStructureRow>[
              OwnedEquationStructureRow(
                start: environment.contentStart,
                end: environment.contentEnd,
                cells: <OwnedEquationStructureCell>[
                  OwnedEquationStructureCell(
                    start: environment.contentStart,
                    end: environment.contentStart,
                    text: '',
                  ),
                ],
              ),
            ]
          : <OwnedEquationStructureRow>[
              for (final row in environment.rows)
                OwnedEquationStructureRow(
                  start: row.start,
                  end: row.end,
                  cells: <OwnedEquationStructureCell>[
                    for (final cell in row.cells)
                      OwnedEquationStructureCell(
                        start: cell.start,
                        end: cell.end,
                        text: cell.text.trim(),
                      ),
                  ],
                ),
            ],
    );
  }

  static OwnedEquationStructureContext? fromSource(String source, int? activeOffset) {
    if (source.isEmpty) return null;
    final offset = activeOffset?.clamp(0, source.length).toInt();
    final stack = <_EquationEnvironmentSpan>[];
    final spans = <_EquationEnvironmentSpan>[];
    var i = 0;
    while (i < source.length) {
      final beginMatch = _beginEndPattern.matchAsPrefix(source, i);
      if (beginMatch == null) {
        i++;
        continue;
      }
      final command = beginMatch.group(1) ?? '';
      final environment = beginMatch.group(2) ?? '';
      if (command == 'begin') {
        stack.add(_EquationEnvironmentSpan(
          environment: environment,
          beginStart: beginMatch.start,
          contentStart: beginMatch.end,
          contentEnd: source.length,
          endEnd: source.length,
        ));
      } else {
        final index = stack.lastIndexWhere((candidate) => candidate.environment == environment);
        if (index >= 0) {
          final open = stack.removeAt(index);
          spans.add(open.copyWith(contentEnd: beginMatch.start, endEnd: beginMatch.end));
        }
      }
      i = beginMatch.end;
    }
    spans.addAll(stack);

    bool supported(_EquationEnvironmentSpan span) {
      return const <String>{
        'matrix',
        'pmatrix',
        'bmatrix',
        'vmatrix',
        'Vmatrix',
        'smallmatrix',
        'aligned',
        'alignedat',
        'split',
        'gathered',
        'cases',
      }.contains(span.environment);
    }

    final supportedSpans = spans.where(supported).toList(growable: false);
    if (supportedSpans.isEmpty) return null;

    if (offset != null) {
      final containing = supportedSpans.where((span) => offset >= span.beginStart && offset <= span.endEnd).toList();
      if (containing.isNotEmpty) {
        containing.sort((a, b) => (a.endEnd - a.beginStart).compareTo(b.endEnd - b.beginStart));
        return _contextForSpan(source, containing.first);
      }
    }

    // If the caret is outside the structure, still expose the first supported
    // structure in the equation. This makes structure controls operate on the
    // equation object rather than requiring an exact source caret position.
    supportedSpans.sort((a, b) => a.beginStart.compareTo(b.beginStart));
    return _contextForSpan(source, supportedSpans.first);
  }

  static OwnedEquationStructureContext _contextForSpan(String source, _EquationEnvironmentSpan span) {
    final contentStart = span.contentStart.clamp(0, source.length).toInt();
    final contentEnd = span.contentEnd.clamp(contentStart, source.length).toInt();
    final rows = _parseRows(source, contentStart, contentEnd);
    return OwnedEquationStructureContext(
      environment: span.environment,
      beginStart: span.beginStart,
      contentStart: contentStart,
      contentEnd: contentEnd,
      endEnd: span.endEnd,
      rows: rows.isEmpty
          ? <OwnedEquationStructureRow>[
              OwnedEquationStructureRow(
                start: contentStart,
                end: contentEnd,
                cells: <OwnedEquationStructureCell>[
                  OwnedEquationStructureCell(start: contentStart, end: contentStart, text: ''),
                ],
              ),
            ]
          : rows,
    );
  }

  static List<OwnedEquationStructureRow> _parseRows(String source, int contentStart, int contentEnd) {
    final rows = <OwnedEquationStructureRow>[];
    var rowStart = contentStart;
    var i = contentStart;
    while (i < contentEnd) {
      if (i + 1 < contentEnd && source[i] == r'\'[0] && source[i + 1] == r'\'[0]) {
        rows.add(_parseRow(source, rowStart, i));
        i += 2;
        rowStart = i;
        continue;
      }
      i++;
    }
    rows.add(_parseRow(source, rowStart, contentEnd));
    return rows;
  }

  static OwnedEquationStructureRow _parseRow(String source, int rowStart, int rowEnd) {
    final cells = <OwnedEquationStructureCell>[];
    var cellStart = rowStart;
    var i = rowStart;
    while (i < rowEnd) {
      final isEscaped = i > rowStart && source[i - 1] == r'\'[0];
      if (source[i] == '&' && !isEscaped) {
        cells.add(OwnedEquationStructureCell(
          start: cellStart,
          end: i,
          text: source.substring(cellStart, i).trim(),
        ));
        cellStart = i + 1;
      }
      i++;
    }
    cells.add(OwnedEquationStructureCell(
      start: cellStart,
      end: rowEnd,
      text: source.substring(cellStart, rowEnd).trim(),
    ));
    return OwnedEquationStructureRow(start: rowStart, end: rowEnd, cells: cells);
  }

  static final RegExp _beginEndPattern = RegExp(r'\\(begin|end)\{([^}]+)\}');
}

class OwnedEquationStructureRow {
  const OwnedEquationStructureRow({
    required this.start,
    required this.end,
    required this.cells,
  });

  final int start;
  final int end;
  final List<OwnedEquationStructureCell> cells;
}

class OwnedEquationStructureCell {
  const OwnedEquationStructureCell({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;

  int get caretOffset {
    final trimmedLeft = text.length - text.trimLeft().length;
    return math.min(end, start + trimmedLeft);
  }
}


class _EquationEditingContext {
  const _EquationEditingContext({
    required this.model,
    required this.structureContext,
    required this.activeTarget,
    required this.primaryDiagnostic,
    required this.activeSourceOffset,
    required this.activeRangeStart,
    required this.activeRangeEnd,
  });

  final OwnedEquationSourceModel model;
  final OwnedEquationStructureContext? structureContext;
  final OwnedEquationSubexpressionTarget? activeTarget;
  final OwnedEquationDiagnostic? primaryDiagnostic;
  final int? activeSourceOffset;
  final int? activeRangeStart;
  final int? activeRangeEnd;

  static _EquationEditingContext fromModel({
    required OwnedEquationSourceModel model,
    required OwnedEquationStructureContext? structureContext,
    required int? activeSourceOffset,
    required int? activeRangeStart,
    required int? activeRangeEnd,
  }) {
    final targets = model.structure.visualTargets(activeOffset: activeSourceOffset, limit: 18);
    OwnedEquationSubexpressionTarget? activeTarget;
    for (final target in targets) {
      if (target.containsOffset(activeSourceOffset)) {
        activeTarget = target;
        break;
      }
    }

    return _EquationEditingContext(
      model: model,
      structureContext: structureContext,
      activeTarget: activeTarget,
      primaryDiagnostic: _primaryErrorDiagnostic(
        model.diagnostics,
        activeSourceOffset: activeSourceOffset,
        activeRangeStart: activeRangeStart,
        activeRangeEnd: activeRangeEnd,
      ),
      activeSourceOffset: activeSourceOffset,
      activeRangeStart: activeRangeStart,
      activeRangeEnd: activeRangeEnd,
    );
  }

  String get headline {
    final diagnostic = primaryDiagnostic;
    if (diagnostic != null) return 'Problem';
    final structure = structureContext;
    if (structure != null) return '${structure.displayName} · ${structure.dimensionLabel}';
    final target = activeTarget;
    if (target != null) return _targetHeadline(target);
    return 'Editing expression';
  }

  String get detail {
    final diagnostic = primaryDiagnostic;
    if (diagnostic != null) return _compactDiagnosticMessage(diagnostic.message);
    final structure = structureContext;
    if (structure != null) {
      if (structure.isMatrix) return 'grid tools available';
      if (structure.isAligned) return 'line/alignment tools';
      if (structure.isCases) return 'case rows available';
      return 'structure-aware controls';
    }
    final target = activeTarget;
    if (target != null) return 'visual/source linked';
    return 'write common math parts';
  }

  _EquationPreviewSourceSelection? get diagnosticPreviewSelection {
    final diagnostic = primaryDiagnostic;
    if (diagnostic == null) return null;
    final safeStart = diagnostic.start.clamp(0, model.rawSource.length).toInt();
    var safeEnd = diagnostic.end.clamp(safeStart, model.rawSource.length).toInt();
    if (safeEnd <= safeStart) safeEnd = math.min(model.rawSource.length, safeStart + 1);
    return _EquationPreviewSourceSelection(start: safeStart, end: safeEnd);
  }

  static OwnedEquationDiagnostic? _primaryErrorDiagnostic(
    List<OwnedEquationDiagnostic> diagnostics, {
    required int? activeSourceOffset,
    required int? activeRangeStart,
    required int? activeRangeEnd,
  }) {
    final errors = diagnostics
        .where((diagnostic) => diagnostic.severity == OwnedEquationDiagnosticSeverity.error)
        .toList(growable: false);
    if (errors.isEmpty) return null;
    for (final diagnostic in errors) {
      if (_diagnosticTouchesFocus(
        diagnostic,
        activeSourceOffset: activeSourceOffset,
        activeRangeStart: activeRangeStart,
        activeRangeEnd: activeRangeEnd,
      )) {
        return diagnostic;
      }
    }
    return errors.first;
  }

  static bool _diagnosticTouchesFocus(
    OwnedEquationDiagnostic diagnostic, {
    required int? activeSourceOffset,
    required int? activeRangeStart,
    required int? activeRangeEnd,
  }) {
    final start = activeRangeStart;
    final end = activeRangeEnd;
    if (start != null && end != null && end > start) {
      return diagnostic.intersects(start, end);
    }
    final offset = activeSourceOffset;
    if (offset == null) return false;
    final safeEnd = diagnostic.end <= diagnostic.start ? diagnostic.start + 1 : diagnostic.end;
    return offset >= diagnostic.start && offset <= safeEnd;
  }

  static String _targetHeadline(OwnedEquationSubexpressionTarget target) {
    return switch (target.kind) {
      OwnedEquationStructureKind.fraction => 'Fraction',
      OwnedEquationStructureKind.squareRoot => 'Square root',
      OwnedEquationStructureKind.superscript => 'Superscript',
      OwnedEquationStructureKind.subscript => 'Subscript',
      OwnedEquationStructureKind.textCommand => 'Text group',
      OwnedEquationStructureKind.environment => target.label,
      _ => target.label,
    };
  }

  static String _compactDiagnosticMessage(String message) {
    final compact = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 34) return compact;
    return '${compact.substring(0, 33)}…';
  }
}

class _EquationEnvironmentSpan {
  const _EquationEnvironmentSpan({
    required this.environment,
    required this.beginStart,
    required this.contentStart,
    required this.contentEnd,
    required this.endEnd,
  });

  final String environment;
  final int beginStart;
  final int contentStart;
  final int contentEnd;
  final int endEnd;

  _EquationEnvironmentSpan copyWith({int? contentEnd, int? endEnd}) {
    return _EquationEnvironmentSpan(
      environment: environment,
      beginStart: beginStart,
      contentStart: contentStart,
      contentEnd: contentEnd ?? this.contentEnd,
      endEnd: endEnd ?? this.endEnd,
    );
  }
}

class _EquationStructureToolStrip extends StatelessWidget {
  const _EquationStructureToolStrip({
    required this.contextInfo,
    required this.subexpressionTargets,
    required this.activeSourceOffset,
    required this.onJumpToSourceOffset,
    required this.onStructureCellSelected,
    required this.onInsertMatrix,
    required this.onInsertAligned,
    required this.onInsertCases,
    required this.onInsertMatrixRow,
    required this.onInsertMatrixColumn,
    required this.onInsertAlignedLine,
    required this.onInsertAlignmentMarker,
    required this.onInsertCasesRow,
  });

  final OwnedEquationStructureContext? contextInfo;
  final List<OwnedEquationSubexpressionTarget> subexpressionTargets;
  final int? activeSourceOffset;
  final ValueChanged<int>? onJumpToSourceOffset;
  final void Function(OwnedEquationStructureContext contextInfo, int rowIndex, int columnIndex)? onStructureCellSelected;
  final VoidCallback? onInsertMatrix;
  final VoidCallback? onInsertAligned;
  final VoidCallback? onInsertCases;
  final VoidCallback? onInsertMatrixRow;
  final VoidCallback? onInsertMatrixColumn;
  final VoidCallback? onInsertAlignedLine;
  final VoidCallback? onInsertAlignmentMarker;
  final VoidCallback? onInsertCasesRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = contextInfo;
    final hasMap = info != null || subexpressionTargets.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 126,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.46)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    info != null ? 'Structure map' : 'Visual navigation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info == null ? 'preview → source' : '${info.displayName} · ${info.dimensionLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: info == null ? colorScheme.onSurfaceVariant : colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _EquationStructureAndExpressionMap(
            contextInfo: info,
            subexpressionTargets: subexpressionTargets,
            activeSourceOffset: activeSourceOffset,
            onJumpToSourceOffset: onJumpToSourceOffset,
            onStructureCellSelected: onStructureCellSelected,
          ),
        ),
      ],
    );
  }
}


class _EquationStructureAndExpressionMap extends StatelessWidget {
  const _EquationStructureAndExpressionMap({
    required this.contextInfo,
    required this.subexpressionTargets,
    required this.activeSourceOffset,
    required this.onJumpToSourceOffset,
    required this.onStructureCellSelected,
  });

  final OwnedEquationStructureContext? contextInfo;
  final List<OwnedEquationSubexpressionTarget> subexpressionTargets;
  final int? activeSourceOffset;
  final ValueChanged<int>? onJumpToSourceOffset;
  final void Function(OwnedEquationStructureContext contextInfo, int rowIndex, int columnIndex)? onStructureCellSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = contextInfo;

    if (info != null) {
      return _EquationStructureMiniMap(
        contextInfo: info,
        onJumpToSourceOffset: onJumpToSourceOffset,
        onStructureCellSelected: onStructureCellSelected,
      );
    }

    final activeTarget = _activePreviewTarget;
    final targetSummary = activeTarget == null
        ? (subexpressionTargets.isEmpty
            ? 'Click rendered symbols to select their source.'
            : 'Click the rendered equation for precise preview-to-source selection.')
        : 'Source context: ${activeTarget.label}. Click the rendered equation to select visual parts directly.';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Icon(
              Icons.ads_click_rounded,
              size: 14,
              color: colorScheme.primary.withValues(alpha: onJumpToSourceOffset == null ? 0.38 : 0.82),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                targetSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  OwnedEquationSubexpressionTarget? get _activePreviewTarget {
    for (final target in subexpressionTargets) {
      if (target.containsOffset(activeSourceOffset)) return target;
    }
    return null;
  }
}

class _EquationStructureMiniMap extends StatelessWidget {
  const _EquationStructureMiniMap({
    required this.contextInfo,
    required this.onJumpToSourceOffset,
    required this.onStructureCellSelected,
  });

  final OwnedEquationStructureContext contextInfo;
  final ValueChanged<int>? onJumpToSourceOffset;
  final void Function(OwnedEquationStructureContext contextInfo, int rowIndex, int columnIndex)? onStructureCellSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rows = contextInfo.rows;
    final maxRows = math.min(rows.length, 3);
    final columnCount = math.min(math.max(1, contextInfo.columnCount), 5);
    final caption = contextInfo.isMatrix
        ? 'click cells'
        : contextInfo.isCases
            ? 'value | condition'
            : 'left | aligned right';

    return Row(
      children: [
        Flexible(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.62)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var rowIndex = 0; rowIndex < maxRows; rowIndex++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) ...[
                            Expanded(
                              child: _EquationStructureCellChip(
                                cell: _cellAt(rows[rowIndex], columnIndex),
                                rowIndex: rowIndex,
                                columnIndex: columnIndex,
                                isMatrix: contextInfo.isMatrix,
                                onJumpToSourceOffset: onJumpToSourceOffset,
                                onSelectCell: onStructureCellSelected == null
                                    ? null
                                    : () => onStructureCellSelected!(contextInfo, rowIndex, columnIndex),
                              ),
                            ),
                            if (columnIndex + 1 < columnCount) const SizedBox(width: 3),
                          ],
                        ],
                      ),
                    ),
                  if (rows.length > maxRows)
                    Text(
                      '+ ${rows.length - maxRows} more rows',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  OwnedEquationStructureCell? _cellAt(OwnedEquationStructureRow row, int index) {
    if (index < row.cells.length) return row.cells[index];

    // Missing cells in uneven matrix rows must be shown as empty virtual slots,
    // not as duplicates of the previous cell. Returning the previous cell made
    // the visual map claim that a value existed where the LaTeX source had no
    // corresponding cell, which made matrix editing feel misleading.
    final anchor = row.cells.isEmpty ? row.start : row.end;
    return OwnedEquationStructureCell(start: anchor, end: anchor, text: '');
  }
}

class _EquationStructureCellChip extends StatelessWidget {
  const _EquationStructureCellChip({
    required this.cell,
    required this.rowIndex,
    required this.columnIndex,
    required this.isMatrix,
    required this.onJumpToSourceOffset,
    required this.onSelectCell,
  });

  final OwnedEquationStructureCell? cell;
  final int rowIndex;
  final int columnIndex;
  final bool isMatrix;
  final ValueChanged<int>? onJumpToSourceOffset;
  final VoidCallback? onSelectCell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _label;
    return Tooltip(
      message: 'Jump to ${isMatrix ? 'cell' : 'slot'} ${rowIndex + 1},${columnIndex + 1}',
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onSelectCell ??
            (cell == null || onJumpToSourceOffset == null
                ? null
                : () => onJumpToSourceOffset!(cell!.caretOffset)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: cell == null ? 0.14 : 0.34),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                fontSize: 9,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _label {
    final text = cell?.text.trim() ?? '';
    if (text.isEmpty) return '□';
    final compact = text.replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 8) return compact;
    return '${compact.substring(0, 7)}…';
  }
}

class OwnedEquationCommandPrefix {
  const OwnedEquationCommandPrefix({
    required this.start,
    required this.end,
    required this.typed,
  });

  final int start;
  final int end;
  final String typed;

  String get query => typed.startsWith('\\') ? typed.substring(1).toLowerCase() : typed.toLowerCase();

  static OwnedEquationCommandPrefix? fromSource(String source, int? activeOffset) {
    if (source.isEmpty || activeOffset == null) return null;
    final offset = activeOffset.clamp(0, source.length).toInt();
    if (offset <= 0) return null;

    var start = offset;
    while (start > 0 && _isCommandLetter(source.codeUnitAt(start - 1))) {
      start--;
    }
    if (start > 0 && source[start - 1] == '\\') {
      start--;
    } else if (offset > 0 && source[offset - 1] == '\\') {
      start = offset - 1;
    } else {
      return null;
    }

    final typed = source.substring(start, offset);
    if (!typed.startsWith('\\')) return null;
    // Do not treat delimiters/control symbols such as \[, \], \(, or \) as
    // autocomplete commands. Those are source syntax, not command words.
    if (typed.length > 1 && !_isCommandLetter(typed.codeUnitAt(1))) return null;
    return OwnedEquationCommandPrefix(start: start, end: offset, typed: typed);
  }

  static bool _isCommandLetter(int unit) {
    return (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122);
  }
}

class OwnedEquationCommandCompletion {
  const OwnedEquationCommandCompletion({
    required this.label,
    required this.completion,
    required this.caretOffset,
    required this.description,
    this.category = 'command',
    this.basePriority = 0,
    this.common = false,
  });

  final String label;
  final String completion;
  final int caretOffset;
  final String description;
  final String category;
  final int basePriority;
  final bool common;

  static List<OwnedEquationCommandCompletion> matchesFor(
    OwnedEquationCommandPrefix? prefix, {
    String source = '',
    int? activeOffset,
    Map<String, int> usageCounts = const <String, int>{},
  }) {
    if (prefix == null) return const <OwnedEquationCommandCompletion>[];
    final query = prefix.query;
    final scored = <_ScoredEquationCompletion>[];
    for (final completion in _all) {
      final label = completion.label.startsWith('\\')
          ? completion.label.substring(1).toLowerCase()
          : completion.label.toLowerCase();
      final description = completion.description.toLowerCase();
      if (query.isNotEmpty && !label.startsWith(query) && !description.contains(query)) {
        continue;
      }
      var score = completion.basePriority.toDouble();
      score += (usageCounts[completion.completion] ?? usageCounts[completion.label] ?? 0) * 1000;
      if (query.isEmpty) {
        score += completion.common ? 180 : 0;
      } else {
        if (label == query) score += 600;
        if (label.startsWith(query)) score += 420 - query.length;
        if (description.contains(query)) score += 90;
      }
      score += _contextScore(completion, source: source, activeOffset: activeOffset);
      scored.add(_ScoredEquationCompletion(completion, score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.completion.label.compareTo(b.completion.label);
    });
    return scored.take(9).map((item) => item.completion).toList(growable: false);
  }

  /// Suggestion popups should be helpful while the user is composing a command,
  /// not noisy after a complete command already exists in the source. Exact
  /// command matches such as `\frac` therefore hide the popup; partial prefixes
  /// such as `\fr` and a bare `\` still show suggestions.
  static bool isExactCompletedCommand(OwnedEquationCommandPrefix prefix) {
    if (prefix.typed.length <= 1) return false;
    final typed = prefix.typed.toLowerCase();
    return _all.any((completion) => completion.label.toLowerCase() == typed);
  }

  static double _contextScore(
    OwnedEquationCommandCompletion completion, {
    required String source,
    required int? activeOffset,
  }) {
    if (activeOffset == null || source.isEmpty) return 0;
    final offset = activeOffset.clamp(0, source.length).toInt();
    final before = source.substring(0, offset).toLowerCase();
    final recent = before.length > 40 ? before.substring(before.length - 40) : before;
    var score = 0.0;
    if (recent.contains(r'\begin{') && completion.category == 'environment') score += 260;
    if ((recent.endsWith('^') || recent.endsWith('_')) && completion.category == 'symbol') score += 80;
    if (recent.contains(r'\text{') && completion.category == 'text') score += 160;
    if ((recent.endsWith('d') || recent.endsWith('dt')) && completion.label == r'\frac') score += 80;
    if (before.contains(r'\frac') && completion.category == 'operator') score += 60;
    return score;
  }

  static const List<OwnedEquationCommandCompletion> _all = <OwnedEquationCommandCompletion>[
    OwnedEquationCommandCompletion(label: r'\frac', completion: r'\frac{}{}', caretOffset: 6, description: 'fraction', category: 'structure', basePriority: 120, common: true),
    OwnedEquationCommandCompletion(label: r'\sqrt', completion: r'\sqrt{}', caretOffset: 6, description: 'square root', category: 'structure', basePriority: 94, common: true),
    OwnedEquationCommandCompletion(label: r'\text', completion: r'\text{}', caretOffset: 6, description: 'text inside math', category: 'text', basePriority: 88, common: true),
    OwnedEquationCommandCompletion(label: r'\mathrm', completion: r'\mathrm{}', caretOffset: 8, description: 'roman text', category: 'text', basePriority: 42),
    OwnedEquationCommandCompletion(label: r'\mathbf', completion: r'\mathbf{}', caretOffset: 8, description: 'bold math text', category: 'text', basePriority: 40),
    OwnedEquationCommandCompletion(label: r'\begin{aligned}', completion: r'\begin{aligned}  &=  \\  &=  \end{aligned}', caretOffset: 16, description: 'aligned equations', category: 'environment', basePriority: 76, common: true),
    OwnedEquationCommandCompletion(label: r'\begin{cases}', completion: r'\begin{cases}  & \text{} \\  & \text{} \end{cases}', caretOffset: 14, description: 'piecewise cases', category: 'environment', basePriority: 72, common: true),
    OwnedEquationCommandCompletion(label: r'\begin{bmatrix}', completion: r'\begin{bmatrix}  &  \\  &  \end{bmatrix}', caretOffset: 16, description: 'bracket matrix', category: 'environment', basePriority: 68),
    OwnedEquationCommandCompletion(label: r'\begin{pmatrix}', completion: r'\begin{pmatrix}  &  \\  &  \end{pmatrix}', caretOffset: 16, description: 'parenthesis matrix', category: 'environment', basePriority: 58),
    OwnedEquationCommandCompletion(label: r'\begin{matrix}', completion: r'\begin{matrix}  &  \\  &  \end{matrix}', caretOffset: 15, description: 'plain matrix', category: 'environment', basePriority: 52),
    OwnedEquationCommandCompletion(label: r'\Delta', completion: r'\Delta ', caretOffset: 7, description: 'uppercase delta', category: 'symbol', basePriority: 60, common: true),
    OwnedEquationCommandCompletion(label: r'\alpha', completion: r'\alpha ', caretOffset: 7, description: 'alpha', category: 'symbol', basePriority: 54, common: true),
    OwnedEquationCommandCompletion(label: r'\beta', completion: r'\beta ', caretOffset: 6, description: 'beta', category: 'symbol', basePriority: 52, common: true),
    OwnedEquationCommandCompletion(label: r'\gamma', completion: r'\gamma ', caretOffset: 7, description: 'gamma', category: 'symbol', basePriority: 50, common: true),
    OwnedEquationCommandCompletion(label: r'\lambda', completion: r'\lambda ', caretOffset: 8, description: 'lambda', category: 'symbol', basePriority: 48, common: true),
    OwnedEquationCommandCompletion(label: r'\sigma', completion: r'\sigma ', caretOffset: 7, description: 'sigma', category: 'symbol', basePriority: 46, common: true),
    OwnedEquationCommandCompletion(label: r'\infty', completion: r'\infty ', caretOffset: 7, description: 'infinity', category: 'symbol', basePriority: 44, common: true),
    OwnedEquationCommandCompletion(label: r'\sum', completion: r'\sum ', caretOffset: 5, description: 'summation', category: 'operator', basePriority: 43, common: true),
    OwnedEquationCommandCompletion(label: r'\int', completion: r'\int ', caretOffset: 5, description: 'integral', category: 'operator', basePriority: 42, common: true),
    OwnedEquationCommandCompletion(label: r'\prime', completion: r'\prime ', caretOffset: 7, description: 'prime', category: 'operator', basePriority: 40),
    OwnedEquationCommandCompletion(label: r'\approx', completion: r'\approx ', caretOffset: 8, description: 'approximately', category: 'operator', basePriority: 36),
    OwnedEquationCommandCompletion(label: r'\leq', completion: r'\leq ', caretOffset: 5, description: 'less than or equal', category: 'operator', basePriority: 34),
    OwnedEquationCommandCompletion(label: r'\geq', completion: r'\geq ', caretOffset: 5, description: 'greater than or equal', category: 'operator', basePriority: 34),
  ];
}

class _ScoredEquationCompletion {
  const _ScoredEquationCompletion(this.completion, this.score);

  final OwnedEquationCommandCompletion completion;
  final double score;
}

class _EquationCompletionStrip extends StatelessWidget {
  const _EquationCompletionStrip({
    required this.prefix,
    required this.completions,
    required this.onAccept,
  });

  final OwnedEquationCommandPrefix prefix;
  final List<OwnedEquationCommandCompletion> completions;
  final void Function(String completion, int caretOffset)? onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            prefix.query.isEmpty ? 'Suggestions' : 'Suggestions for ${prefix.typed}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          if (completions.isEmpty)
            Text(
              'No automatic expansion — keep typing or choose a command.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            for (final completion in completions) ...[
              _EquationCompletionChip(
                completion: completion,
                onAccept: onAccept,
              ),
              const SizedBox(width: 6),
            ],
        ],
      ),
    );
  }
}

class _EquationCompletionChip extends StatelessWidget {
  const _EquationCompletionChip({
    required this.completion,
    required this.onAccept,
  });

  final OwnedEquationCommandCompletion completion;
  final void Function(String completion, int caretOffset)? onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: completion.description,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onAccept == null ? null : () => onAccept!(completion.completion, completion.caretOffset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Text(
              completion.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontFamily: 'monospace',
                fontFamilyFallback: const <String>['Consolas', 'Menlo', 'monospace'],
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _EquationCompletionDropdown extends StatelessWidget {
  const _EquationCompletionDropdown({
    required this.prefix,
    required this.completions,
    required this.highlightedIndex,
    required this.usageCounts,
    required this.onAccept,
  });

  final OwnedEquationCommandPrefix prefix;
  final List<OwnedEquationCommandCompletion> completions;
  final int highlightedIndex;
  final Map<String, int> usageCounts;
  final void Function(String completion, int caretOffset)? onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final safeIndex = completions.isEmpty ? -1 : highlightedIndex.clamp(0, completions.length - 1).toInt();
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.82)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: completions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  child: Text(
                    'No suggestions',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  itemExtent: 21,
                  itemCount: completions.length,
                  itemBuilder: (context, index) {
                    final completion = completions[index];
                    final selected = index == safeIndex;
                    final useCount = usageCounts[completion.completion] ?? usageCounts[completion.label] ?? 0;
                    return _EquationCompletionRow(
                      completion: completion,
                      selected: selected,
                      useCount: useCount,
                      onAccept: onAccept,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _EquationCompletionRow extends StatelessWidget {
  const _EquationCompletionRow({
    required this.completion,
    required this.selected,
    required this.useCount,
    required this.onAccept,
  });

  final OwnedEquationCommandCompletion completion;
  final bool selected;
  final int useCount;
  final void Function(String completion, int caretOffset)? onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: '${completion.label} · ${completion.description}',
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        onTap: onAccept == null ? null : () => onAccept!(completion.completion, completion.caretOffset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.62) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 7, right: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    completion.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                      fontFamily: 'monospace',
                      fontFamilyFallback: const <String>['Consolas', 'Menlo', 'monospace'],
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ),
                if (useCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$useCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? colorScheme.onPrimaryContainer.withValues(alpha: 0.72)
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EquationDiagnosticsStrip extends StatelessWidget {
  const _EquationDiagnosticsStrip({
    required this.diagnostics,
    required this.onJumpToDiagnostic,
    required this.onFormatSource,
  });

  final List<OwnedEquationDiagnostic> diagnostics;
  final ValueChanged<OwnedEquationDiagnostic>? onJumpToDiagnostic;
  final VoidCallback? onFormatSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primary = diagnostics.first;
    final count = diagnostics.length;
    final background = switch (primary.severity) {
      OwnedEquationDiagnosticSeverity.error => colorScheme.errorContainer.withValues(alpha: 0.72),
      OwnedEquationDiagnosticSeverity.warning => colorScheme.tertiaryContainer.withValues(alpha: 0.72),
      OwnedEquationDiagnosticSeverity.info => colorScheme.primaryContainer.withValues(alpha: 0.55),
    };
    final foreground = switch (primary.severity) {
      OwnedEquationDiagnosticSeverity.error => colorScheme.onErrorContainer,
      OwnedEquationDiagnosticSeverity.warning => colorScheme.onTertiaryContainer,
      OwnedEquationDiagnosticSeverity.info => colorScheme.onPrimaryContainer,
    };
    final label = switch (primary.severity) {
      OwnedEquationDiagnosticSeverity.error => 'Error',
      OwnedEquationDiagnosticSeverity.warning => 'Warning',
      OwnedEquationDiagnosticSeverity.info => 'Hint',
    };
    return Tooltip(
      message: diagnostics.map((diagnostic) => diagnostic.message).join('\n'),
      waitDuration: const Duration(milliseconds: 250),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: foreground.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            children: [
              Text(
                count == 1 ? label : '$label +${count - 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  primary.message,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onJumpToDiagnostic != null) ...[
                const SizedBox(width: 5),
                _EquationInlineActionChip(
                  label: 'Jump',
                  foreground: foreground,
                  onPressed: () => onJumpToDiagnostic!(primary),
                ),
              ],
              if (onFormatSource != null) ...[
                const SizedBox(width: 4),
                _EquationInlineActionChip(
                  label: 'Format',
                  foreground: foreground,
                  onPressed: onFormatSource!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EquationInlineActionChip extends StatelessWidget {
  const _EquationInlineActionChip({
    required this.label,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: 0.16)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _EquationToolButton extends StatelessWidget {
  const _EquationToolButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: onPressed == null ? 0.12 : 0.34),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.primary.withValues(alpha: onPressed == null ? 0.08 : 0.16)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              label,
              style: TextStyle(
                color: onPressed == null
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
                    : colorScheme.onPrimaryContainer,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                fontFamilyFallback: const <String>['Consolas', 'Menlo', 'monospace'],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EquationSymbolButton extends StatelessWidget {
  const _EquationSymbolButton({
    required this.symbol,
    required this.source,
    required this.onInsert,
  });

  final String symbol;
  final String source;
  final ValueChanged<String>? onInsert;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: source.trim(),
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onInsert == null ? null : () => onInsert!(source),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
          ),
          child: SizedBox(
            width: 22,
            height: 20,
            child: Center(
              child: Text(
                symbol,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
