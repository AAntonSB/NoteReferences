import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../text_system_editor_marked_text_layout.dart';
import 'owned_equation_source_model.dart';

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
    this.onAcceptCommandCompletion,
    this.onPreviewSourceOffset,
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
  final void Function(String completion, int caretOffset)? onAcceptCommandCompletion;
  final ValueChanged<int>? onPreviewSourceOffset;
  final void Function(OwnedEquationStructureContext contextInfo, int rowIndex, int columnIndex)? onStructureCellSelected;
  final Map<String, int> commandCompletionUsageCounts;
  final int highlightedCommandCompletionIndex;

  static const double sourceLeftInset = 18.0;
  static const double sourceTopInset = 148.0;

  @override
  State<OwnedEquationAuthoringSurface> createState() => _OwnedEquationAuthoringSurfaceState();
}

class _OwnedEquationAuthoringSurfaceState extends State<OwnedEquationAuthoringSurface> {
  Timer? _previewTimer;
  late OwnedEquationSourceModel _previewModel;
  int? _previewHoverSourceOffset;

  @override
  void initState() {
    super.initState();
    _previewModel = OwnedEquationSourceModel.analyze(widget.sourceText);
  }

  @override
  void didUpdateWidget(covariant OwnedEquationAuthoringSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceText != widget.sourceText) {
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
    final source = widget.sourceText.trim().isEmpty ? r'\[\]' : widget.sourceText.trim();
    final currentModel = OwnedEquationSourceModel.analyze(source);
    final previewModel = _previewModel.rawSource == widget.sourceText ? _previewModel : currentModel;
    final preview = previewModel.displayBody.trim().isEmpty ? currentModel.displayBody : previewModel.displayBody;
    final diagnostics = currentModel.diagnostics;
    final structureContext = OwnedEquationStructureContext.fromSource(
      widget.sourceText,
      widget.activeSourceOffset,
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
        final previewHeight = compact ? 66.0 : 74.0;
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
                          child: _EquationDiagnosticsStrip(diagnostics: diagnostics),
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
                    void jumpToPreviewSource(Offset localPosition) {
                      final targetOffset = _EquationPreviewSourceMap.sourceOffsetForPreviewTap(
                        model: currentModel,
                        localPosition: localPosition,
                        previewSize: Size(previewConstraints.maxWidth, previewHeight),
                      );
                      widget.onPreviewSourceOffset?.call(targetOffset);
                    }

                    return MouseRegion(
                      cursor: widget.onPreviewSourceOffset == null
                          ? MouseCursor.defer
                          : SystemMouseCursors.precise,
                      onHover: (event) {
                        if (widget.onPreviewSourceOffset == null) return;
                        final targetOffset = _EquationPreviewSourceMap.sourceOffsetForPreviewTap(
                          model: currentModel,
                          localPosition: event.localPosition,
                          previewSize: Size(previewConstraints.maxWidth, previewHeight),
                        );
                        if (_previewHoverSourceOffset != targetOffset) {
                          setState(() => _previewHoverSourceOffset = targetOffset);
                        }
                      },
                      onExit: (_) {
                        if (_previewHoverSourceOffset != null) {
                          setState(() => _previewHoverSourceOffset = null);
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapDown: widget.onPreviewSourceOffset == null
                            ? null
                            : (details) => jumpToPreviewSource(details.localPosition),
                        child: DecoratedBox(
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
                                  currentModel.hasErrors ? 'Live preview · source has errors' : 'Live preview',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: currentModel.hasErrors ? colorScheme.error : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Center(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 28),
                                  child: Math.tex(
                                    preview.isEmpty ? r'{}' : preview,
                                    mathStyle: MathStyle.display,
                                    textStyle: widget.previewTextStyle,
                                    onErrorFallback: (error) => Text(
                                      preview.isEmpty ? source : preview,
                                      style: widget.sourceTextStyle.copyWith(color: colorScheme.error),
                                    ),
                                  ),
                                ),
                              ),
                              if (_previewHoverSourceOffset != null && widget.onPreviewSourceOffset != null)
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
  }) {
    final body = model.displayBody;
    final rawBodyStart = model.bodyStartOffset.clamp(0, model.rawSource.length).toInt();
    final rawBodyEnd = model.bodyEndOffset.clamp(rawBodyStart, model.rawSource.length).toInt();
    final rawBody = model.rawSource.substring(rawBodyStart, rawBodyEnd);
    final leadingTrim = rawBody.length - rawBody.trimLeft().length;
    final sourceBaseOffset = (rawBodyStart + leadingTrim).clamp(0, model.rawSource.length).toInt();
    if (body.isEmpty) return sourceBaseOffset;

    final units = _visualUnitsFor(body);
    if (units.isEmpty) return sourceBaseOffset;

    // This mapper intentionally does more than a linear x-position heuristic.
    // flutter_math_fork does not expose sub-expression hit boxes, so we build a
    // small authoring-oriented visual model for the common structures users need
    // to navigate: fractions, text groups, roots, commands, variables, and
    // operators. This lets clicks on a rendered fraction numerator/denominator
    // jump to that source group, e.g. clicking rendered "f" in \frac{f}{x}
    // lands in the numerator and clicking "x" lands in the denominator.
    final layout = _layoutForUnits(units, previewSize);
    final x = localPosition.dx;
    final y = localPosition.dy;

    _EquationPreviewUnitLayout? closest;
    var closestDistance = double.infinity;
    for (final entry in layout) {
      if (x >= entry.left && x <= entry.right) {
        return entry.unit.sourceOffsetForTap(
          body: body,
          sourceBaseOffset: sourceBaseOffset,
          x: x,
          y: y,
          left: entry.left,
          right: entry.right,
          mathCenterY: entry.mathCenterY,
        );
      }
      final distance = x < entry.left ? entry.left - x : x - entry.right;
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = entry;
      }
    }

    if (closest == null) return sourceBaseOffset;
    return closest.unit.sourceOffsetForTap(
      body: body,
      sourceBaseOffset: sourceBaseOffset,
      x: x.clamp(closest.left, closest.right).toDouble(),
      y: y,
      left: closest.left,
      right: closest.right,
      mathCenterY: closest.mathCenterY,
    );
  }

  static List<_EquationPreviewUnitLayout> _layoutForUnits(
    List<_EquationPreviewVisualUnit> units,
    Size previewSize,
  ) {
    final totalWidth = units.fold<double>(0, (sum, unit) => sum + unit.width);
    final minimumMargin = math.min(28.0, math.max(8.0, previewSize.width * 0.06));
    final usableWidth = math.max(1.0, previewSize.width - minimumMargin * 2);
    final startLeft = totalWidth <= usableWidth
        ? (previewSize.width - totalWidth) / 2
        : minimumMargin;
    final mathCenterY = previewSize.height * 0.58;
    var cursor = startLeft;
    return <_EquationPreviewUnitLayout>[
      for (final unit in units)
        (() {
          final entry = _EquationPreviewUnitLayout(
            unit: unit,
            left: cursor,
            right: cursor + unit.width,
            mathCenterY: mathCenterY,
          );
          cursor += unit.width;
          return entry;
        })(),
    ];
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

class _EquationPreviewUnitLayout {
  const _EquationPreviewUnitLayout({
    required this.unit,
    required this.left,
    required this.right,
    required this.mathCenterY,
  });

  final _EquationPreviewVisualUnit unit;
  final double left;
  final double right;
  final double mathCenterY;
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
    final localRatio = right <= left
        ? 0.0
        : ((x - left) / (right - left)).clamp(0.0, 1.0).toDouble();

    if (isFraction) {
      final targetStart = y < mathCenterY ? numeratorStart! : denominatorStart!;
      final targetEnd = y < mathCenterY ? numeratorEnd! : denominatorEnd!;
      return sourceBaseOffset + _offsetInsideRange(body, targetStart, targetEnd, localRatio);
    }

    final targetStart = contentStart ?? start;
    final targetEnd = contentEnd ?? end;
    return sourceBaseOffset + _offsetInsideRange(body, targetStart, targetEnd, localRatio);
  }

  static int _offsetInsideRange(String body, int start, int end, double ratio) {
    final safeStart = start.clamp(0, body.length).toInt();
    final safeEnd = end.clamp(safeStart, body.length).toInt();
    if (safeEnd <= safeStart) return safeStart;

    // Prefer meaningful source positions over braces/whitespace. This makes
    // clicking a rendered numerator like "f" land on f rather than on a group
    // boundary, and keeps visual navigation useful for dense TeX structures.
    final meaningful = <int>[];
    for (var i = safeStart; i < safeEnd; i++) {
      final char = body[i];
      if (char == '{' || char == '}' || char == '[' || char == ']') continue;
      if (_EquationPreviewSourceMap._isWhitespace(body.codeUnitAt(i))) continue;
      meaningful.add(i);
    }
    if (meaningful.isEmpty) return safeStart;
    final index = (ratio * (meaningful.length - 1)).round().clamp(0, meaningful.length - 1).toInt();
    return meaningful[index];
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
  final ValueChanged<String>? onInsertSymbol;
  final bool numbered;
  final String? numberLabel;
  final String? equationLabel;
  final VoidCallback? onToggleNumbered;
  final VoidCallback? onEditLabel;
  final VoidCallback? onCopyReference;
  final VoidCallback? onFormatSource;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 27,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Equation source',
                  style: labelStyle?.copyWith(color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                _EquationToolButton(label: r'\frac', tooltip: 'Insert fraction', onPressed: onInsertFraction),
                const SizedBox(width: 6),
                _EquationToolButton(label: '^', tooltip: 'Insert superscript slot', onPressed: onInsertSuperscript),
                const SizedBox(width: 6),
                _EquationToolButton(label: '_', tooltip: 'Insert subscript slot', onPressed: onInsertSubscript),
                const SizedBox(width: 6),
                _EquationToolButton(label: r'\text{}', tooltip: 'Insert text mode', onPressed: onInsertText),
                const SizedBox(width: 6),
                _EquationToolButton(label: 'd/dt', tooltip: 'Insert derivative template', onPressed: onInsertDerivative),
                const SizedBox(width: 6),
                _EquationToolButton(label: 'matrix', tooltip: 'Insert matrix template', onPressed: onInsertMatrix),
                const SizedBox(width: 6),
                _EquationToolButton(label: 'align', tooltip: 'Insert aligned equation template', onPressed: onInsertAligned),
                const SizedBox(width: 6),
                _EquationToolButton(label: 'cases', tooltip: 'Insert cases/piecewise template', onPressed: onInsertCases),
                const SizedBox(width: 12),
                _EquationToolButton(label: 'Format', tooltip: 'Normalize display delimiters and spacing', onPressed: onFormatSource),
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
                _EquationToolButton(
                  label: numberLabel?.trim().isNotEmpty == true ? 'Copy ${numberLabel!.trim()}' : 'Copy ref',
                  tooltip: 'Copy equation cross-reference text',
                  onPressed: onCopyReference,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 28,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text('Symbols', style: labelStyle),
                const SizedBox(width: 10),
                for (final item in _equationSymbols) ...[
                  _EquationSymbolButton(symbol: item.$1, source: item.$2, onInsert: onInsertSymbol),
                  const SizedBox(width: 4),
                ],
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Tab jumps slots · Esc finishes · Ctrl/Cmd+Enter accepts',
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
        const SizedBox(height: 5),
        SizedBox(
          height: 50,
          child: _EquationStructureToolStrip(
            contextInfo: structureContext,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 238,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  info == null ? 'Structures' : '${info.displayName} · ${info.dimensionLabel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: info == null ? colorScheme.onSurfaceVariant : colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                if (info == null) ...[
                  _EquationToolButton(label: '2×2', tooltip: 'Insert a 2 by 2 matrix', onPressed: onInsertMatrix),
                  const SizedBox(width: 6),
                  _EquationToolButton(label: 'cases', tooltip: 'Insert piecewise/cases environment', onPressed: onInsertCases),
                  const SizedBox(width: 6),
                  _EquationToolButton(label: 'align', tooltip: 'Insert aligned equation environment', onPressed: onInsertAligned),
                ] else if (info.isMatrix) ...[
                  _EquationToolButton(label: '+ row', tooltip: 'Append a row to the current matrix', onPressed: onInsertMatrixRow),
                  const SizedBox(width: 6),
                  _EquationToolButton(label: '+ col', tooltip: 'Append a column to every matrix row', onPressed: onInsertMatrixColumn),
                ] else if (info.isAligned) ...[
                  _EquationToolButton(label: '+ line', tooltip: 'Append an aligned equation line', onPressed: onInsertAlignedLine),
                  const SizedBox(width: 6),
                  _EquationToolButton(label: '&=', tooltip: 'Insert or normalize an alignment marker', onPressed: onInsertAlignmentMarker),
                ] else if (info.isCases) ...[
                  _EquationToolButton(label: '+ case', tooltip: 'Append another cases row', onPressed: onInsertCasesRow),
                ] else ...[
                  _EquationToolButton(label: '+ row', tooltip: 'Append a structural row', onPressed: onInsertAlignedLine),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: info == null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Insert a structure, then use the visual map to jump between slots.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : _EquationStructureMiniMap(
                  contextInfo: info,
                  onJumpToSourceOffset: onJumpToSourceOffset,
                  onStructureCellSelected: onStructureCellSelected,
                ),
        ),
      ],
    );
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
  const _EquationDiagnosticsStrip({required this.diagnostics});

  final List<OwnedEquationDiagnostic> diagnostics;

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
            ],
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
