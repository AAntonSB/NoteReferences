import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/text_mark.dart';
import '../core/text_system_controller.dart';
import '../core/text_system_range.dart';
import '../references/actions/text_system_reference_actions.dart';
import '../references/citations/text_system_citation.dart';
import 'text_system_inline_atom_renderer.dart';

/// Hover/click interaction controller for owned-editor inline references and
/// citations.
class TextSystemInlineReferenceInteractionController {
  TextSystemInlineReferenceInteractionController({
    required this.contextForOverlay,
    required this.textController,
    this.referenceActionRepository,
    this.onOpenReferenceTarget,
    this.onChanged,
  });

  final BuildContext Function() contextForOverlay;
  final TextSystemController textController;
  final TextSystemReferenceActionRepository? referenceActionRepository;
  final ValueChanged<TextSystemInlineReferenceMark>? onOpenReferenceTarget;
  final VoidCallback? onChanged;

  OverlayEntry? _entry;
  Timer? _closeTimer;
  TextSystemInlineAtom? _activeAtom;
  Offset? _activeGlobalPosition;
  bool _pinned = false;
  bool _pointerInsidePreview = false;

  bool get hasPreview => _entry != null;

  void showForAtom({
    required TextSystemInlineAtom atom,
    required Offset globalPosition,
    bool pinned = false,
  }) {
    if (!atom.isReference || atom.inlineReference == null || atom.referenceMark == null) return;
    _closeTimer?.cancel();
    final sameAtom = _activeAtom?.id == atom.id &&
        _activeAtom?.blockId == atom.blockId &&
        _activeAtom?.globalRange == atom.globalRange;
    _activeAtom = atom;
    _activeGlobalPosition = globalPosition;

    // Hover previews must remain transient. A previous pinned preview should not
    // accidentally make later hover previews sticky, but a deliberate click-pin
    // on the same atom should remain pinned until the user closes/unpins it.
    if (pinned) {
      _pinned = true;
    } else if (!sameAtom || !_pinned) {
      _pinned = false;
    }

    final overlay = Overlay.maybeOf(contextForOverlay());
    if (overlay == null) return;
    if (_entry == null) {
      _entry = OverlayEntry(builder: _buildOverlay);
      overlay.insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  void scheduleClose() {
    if (_pinned || _pointerInsidePreview) return;
    // Do not keep pushing the close timer forward while the pointer keeps
    // moving over non-atom page content. Continuous page-level hover events
    // would otherwise make transient previews feel sticky until the mouse left
    // the whole app window.
    if (_closeTimer != null) return;
    _closeTimer = Timer(const Duration(milliseconds: 160), () {
      _closeTimer = null;
      if (!_pinned && !_pointerInsidePreview) hide();
    });
  }

  void hide() {
    _closeTimer?.cancel();
    _closeTimer = null;
    _entry?.remove();
    _entry = null;
    _activeAtom = null;
    _activeGlobalPosition = null;
    _pinned = false;
    _pointerInsidePreview = false;
  }

  void dispose() {
    hide();
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final atom = _activeAtom;
    final position = _activeGlobalPosition;
    final inlineReference = atom?.inlineReference;
    final mark = atom?.referenceMark;
    if (atom == null || position == null || inlineReference == null || mark == null) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(overlayContext);
    const cardWidth = 360.0;
    const cardHeightEstimate = 310.0;
    final left = mathMin(
      mathMax(12.0, position.dx + 14.0),
      mathMax(12.0, size.width - cardWidth - 12.0),
    );
    final top = mathMin(
      mathMax(12.0, position.dy + 18.0),
      mathMax(12.0, size.height - cardHeightEstimate - 12.0),
    );

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: MouseRegion(
        onEnter: (_) {
          _pointerInsidePreview = true;
          _closeTimer?.cancel();
        },
        onExit: (_) {
          _pointerInsidePreview = false;
          scheduleClose();
        },
        child: _OwnedReferencePreviewCard(
          inlineReference: inlineReference,
          citationSettings: TextSystemCitationSettings.fromDocument(textController.document),
          pinned: _pinned,
          canEdit: referenceActionRepository != null,
          onTogglePinned: () {
            _pinned = !_pinned;
            _entry?.markNeedsBuild();
            if (!_pinned && !_pointerInsidePreview) scheduleClose();
          },
          onOpen: () => _openReferenceTarget(inlineReference),
          onCopy: () => _copyReferenceDetails(inlineReference),
          onEdit: referenceActionRepository == null ? null : () => unawaited(_editReference(atom, mark, inlineReference)),
          onUnlink: () => _unlinkReferenceMark(atom, mark, inlineReference),
          onRemoveGeneratedText: _shouldOfferRemoveGeneratedText(atom, inlineReference)
              ? () => _removeReferenceTextAndMark(atom, mark, inlineReference)
              : null,
          onCitationModeChanged: inlineReference.isCitation
              ? (mode) => _changeCitationModeForMark(atom, mark, inlineReference, mode)
              : null,
          onClose: hide,
        ),
      ),
    );
  }

  Future<void> _editReference(
    TextSystemInlineAtom atom,
    TextMark mark,
    TextSystemInlineReferenceMark inlineReference,
  ) async {
    final repository = referenceActionRepository;
    if (repository == null) return;
    final context = contextForOverlay();
    final result = await showTextSystemReferenceActionPicker(
      context: context,
      selectedText: atom.sourceText,
      repository: repository,
      initialActionType: _actionTypeForKind(inlineReference.kind),
      citationSettings: TextSystemCitationSettings.fromDocument(textController.document),
    );
    if (result == null) return;
    _applyReferenceEdit(atom, mark, inlineReference, result);
  }

  void _applyReferenceEdit(
    TextSystemInlineAtom atom,
    TextMark mark,
    TextSystemInlineReferenceMark original,
    TextSystemReferenceActionResult result,
  ) {
    if (result.actionType == TextSystemReferenceActionType.citation) {
      _replaceCitationMark(atom, mark, original, result);
      return;
    }

    final nextMark = result.inlineMark.copyWith(selectedText: atom.sourceText).toTextMarkAttributes();
    final nextDocument = textController.document.copyWith(
      blocks: textController.document.blocks.map((block) {
        if (block.id != atom.blockId) return block;
        final nextMarks = block.marks.map((candidate) {
          if (_isSameInlineReferenceTextMark(candidate, mark, original)) {
            return candidate.copyWith(attributes: nextMark);
          }
          return candidate;
        }).toList(growable: false);
        return block.copyWith(marks: nextMarks).normalizeMarks();
      }).toList(growable: false),
      updatedAt: DateTime.now(),
    );
    textController.replaceDocument(nextDocument, label: result.actionType.verbLabel);
    hide();
    onChanged?.call();
  }

  void _replaceCitationMark(
    TextSystemInlineAtom atom,
    TextMark mark,
    TextSystemInlineReferenceMark original,
    TextSystemReferenceActionResult result,
  ) {
    final settings = TextSystemCitationSettings.fromDocument(textController.document);
    final mode = TextSystemCitationInlineModeX.fromId(
      result.inlineMark.metadata['citationInlineMode'] as String?,
    );
    final source = TextSystemCitationSource.fromReferenceTarget(result.target);
    final registry = TextSystemCitationRegistry.fromDocument(textController.document);
    final sequenceNumber = registry.numberForTarget(result.target.id);
    final citationText = TextSystemCitationFormatter.inlineCitation(
      settings: settings,
      source: source,
      sequenceNumber: sequenceNumber,
      inlineMode: mode,
    );
    final refreshedReference = result.inlineMark.copyWith(
      selectedText: citationText,
      metadata: <String, Object?>{
        ...result.inlineMark.metadata,
        ...source.toMetadata(),
        'citationStyleId': settings.style.id,
        'citationInlineMode': mode.id,
        'citationText': citationText,
        'bibliographyManaged': true,
      },
    );
    _replaceReferenceTextAndMark(
      atom: atom,
      originalMark: mark,
      originalReference: original,
      replacementText: citationText,
      replacementAttributes: refreshedReference.toTextMarkAttributes(),
      label: 'Edit citation',
      settings: settings,
    );
  }

  void _changeCitationModeForMark(
    TextSystemInlineAtom atom,
    TextMark mark,
    TextSystemInlineReferenceMark inlineReference,
    TextSystemCitationInlineMode mode,
  ) {
    if (!inlineReference.isCitation) return;
    final settings = TextSystemCitationSettings.fromDocument(textController.document);
    final source = TextSystemCitationSource.fromInlineMark(inlineReference);
    final registry = TextSystemCitationRegistry.fromDocument(textController.document);
    final citationText = TextSystemCitationFormatter.inlineCitation(
      settings: settings,
      source: source,
      sequenceNumber: registry.numberForTarget(inlineReference.targetId),
      inlineMode: mode,
    );
    final refreshedReference = inlineReference.copyWith(
      selectedText: citationText,
      metadata: <String, Object?>{
        ...inlineReference.metadata,
        ...source.toMetadata(),
        'citationStyleId': settings.style.id,
        'citationInlineMode': mode.id,
        'citationText': citationText,
        'bibliographyManaged': true,
      },
    );
    _replaceReferenceTextAndMark(
      atom: atom,
      originalMark: mark,
      originalReference: inlineReference,
      replacementText: citationText,
      replacementAttributes: refreshedReference.toTextMarkAttributes(),
      label: 'Change citation format',
      settings: settings,
    );
  }

  void _replaceReferenceTextAndMark({
    required TextSystemInlineAtom atom,
    required TextMark originalMark,
    required TextSystemInlineReferenceMark originalReference,
    required String replacementText,
    required Map<String, String> replacementAttributes,
    required String label,
    required TextSystemCitationSettings settings,
  }) {
    final document = textController.document;
    final nextBlocks = document.blocks.map((block) {
      if (block.id != atom.blockId) return block;
      final start = originalMark.range.start.clamp(0, block.text.length).toInt();
      final end = originalMark.range.end.clamp(start, block.text.length).toInt();
      if (start >= end) return block;
      final delta = replacementText.length - (end - start);
      final nextText = block.text.replaceRange(start, end, replacementText);
      final nextMarks = block.marks.map((candidate) {
        if (_isSameInlineReferenceTextMark(candidate, originalMark, originalReference)) {
          return candidate.copyWith(
            range: TextSystemRange(start, start + replacementText.length),
            attributes: replacementAttributes,
          );
        }
        if (candidate.range.start >= end) return candidate.copyWith(range: candidate.range.shift(delta));
        if (candidate.range.end > end) {
          return candidate.copyWith(range: TextSystemRange(candidate.range.start, candidate.range.end + delta));
        }
        return candidate;
      }).toList(growable: false);
      return block.copyWith(text: nextText, marks: nextMarks).normalizeMarks();
    }).toList(growable: false);

    final nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(
      document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now()),
      settings: settings,
    );
    textController.replaceDocument(nextDocument, label: label);
    hide();
    onChanged?.call();
  }

  bool _shouldOfferRemoveGeneratedText(
    TextSystemInlineAtom atom,
    TextSystemInlineReferenceMark inlineReference,
  ) {
    if (inlineReference.isCitation) return true;
    final generated = inlineReference.metadata['generatedText']?.toString() == 'true' ||
        inlineReference.metadata['autoGeneratedText']?.toString() == 'true' ||
        inlineReference.metadata['bibliographyManaged']?.toString() == 'true';
    return generated && atom.sourceText.trim().isNotEmpty;
  }

  void _removeReferenceTextAndMark(
    TextSystemInlineAtom atom,
    TextMark mark,
    TextSystemInlineReferenceMark inlineReference,
  ) {
    final document = textController.document;
    final nextBlocks = document.blocks.map((block) {
      if (block.id != atom.blockId) return block;
      final start = mark.range.start.clamp(0, block.text.length).toInt();
      final end = mark.range.end.clamp(start, block.text.length).toInt();
      if (start >= end) {
        final nextMarks = block.marks
            .where((candidate) => !_isSameInlineReferenceTextMark(candidate, mark, inlineReference))
            .toList(growable: false);
        return block.copyWith(marks: nextMarks).normalizeMarks();
      }

      final nextText = block.text.replaceRange(start, end, '');
      final delta = start - end;
      final nextMarks = <TextMark>[];
      for (final candidate in block.marks) {
        if (_isSameInlineReferenceTextMark(candidate, mark, inlineReference)) continue;
        final adjusted = _rangeAfterDeletingText(candidate.range, start, end, delta);
        if (adjusted != null && !adjusted.isCollapsed) {
          nextMarks.add(candidate.copyWith(range: adjusted));
        }
      }
      return block.copyWith(text: nextText, marks: nextMarks).normalizeMarks();
    }).toList(growable: false);

    var nextDocument = document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now());
    if (inlineReference.isCitation) {
      nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(nextDocument);
    }
    textController.replaceDocument(
      nextDocument,
      label: inlineReference.isCitation ? 'Remove citation' : 'Remove reference text',
    );
    hide();
    onChanged?.call();
  }

  static TextSystemRange? _rangeAfterDeletingText(
    TextSystemRange range,
    int deleteStart,
    int deleteEnd,
    int delta,
  ) {
    if (range.end <= deleteStart) return range;
    if (range.start >= deleteEnd) return range.shift(delta);
    if (range.start >= deleteStart && range.end <= deleteEnd) return null;

    final nextStart = range.start < deleteStart ? range.start : deleteStart;
    final nextEnd = range.end > deleteEnd ? range.end + delta : deleteStart;
    if (nextEnd <= nextStart) return null;
    return TextSystemRange(nextStart, nextEnd);
  }

  void _unlinkReferenceMark(
    TextSystemInlineAtom atom,
    TextMark mark,
    TextSystemInlineReferenceMark inlineReference,
  ) {
    final document = textController.document;
    final nextBlocks = document.blocks.map((block) {
      if (block.id != atom.blockId) return block;
      final nextMarks = block.marks
          .where((candidate) => !_isSameInlineReferenceTextMark(candidate, mark, inlineReference))
          .toList(growable: false);
      return block.copyWith(marks: nextMarks).normalizeMarks();
    }).toList(growable: false);
    var nextDocument = document.copyWith(blocks: nextBlocks, updatedAt: DateTime.now());
    if (inlineReference.isCitation) {
      nextDocument = TextSystemCitationBibliographyGenerator.refreshDocument(nextDocument);
    }
    textController.replaceDocument(nextDocument, label: 'Unlink reference');
    hide();
    onChanged?.call();
  }

  void _openReferenceTarget(TextSystemInlineReferenceMark inlineReference) {
    final openTarget = onOpenReferenceTarget;
    if (openTarget != null) {
      openTarget(inlineReference);
      hide();
      return;
    }
    final context = contextForOverlay();
    final uri = inlineReference.uri?.toString();
    final title = _referencePreviewTitle(inlineReference);
    if (uri != null && uri.trim().isNotEmpty) {
      Clipboard.setData(ClipboardData(text: uri));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Copied target URI for $title. App navigation bridge is not attached here.')),
      );
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Open target: $title. No navigation bridge is attached here.')),
    );
  }

  void _copyReferenceDetails(TextSystemInlineReferenceMark inlineReference) {
    Clipboard.setData(ClipboardData(text: _referencePreviewClipboardText(inlineReference)));
    ScaffoldMessenger.maybeOf(contextForOverlay())?.showSnackBar(
      const SnackBar(content: Text('Reference details copied.')),
    );
  }

  static bool _isSameInlineReferenceTextMark(
    TextMark candidate,
    TextMark original,
    TextSystemInlineReferenceMark originalReference,
  ) {
    if (candidate.kind != TextMarkKind.link) return false;
    final candidateReference = TextSystemInlineReferenceMark.tryFromTextMarkAttributes(candidate.attributes);
    if (candidateReference == null) return false;
    return candidateReference.id == originalReference.id ||
        (candidate.range.start == original.range.start &&
            candidate.range.end == original.range.end &&
            candidateReference.targetId == originalReference.targetId &&
            candidateReference.kind == originalReference.kind);
  }

  static TextSystemReferenceActionType _actionTypeForKind(TextSystemReferenceTargetKind kind) {
    switch (kind) {
      case TextSystemReferenceTargetKind.citation:
        return TextSystemReferenceActionType.citation;
      case TextSystemReferenceTargetKind.source:
        return TextSystemReferenceActionType.source;
      case TextSystemReferenceTargetKind.document:
        return TextSystemReferenceActionType.document;
      case TextSystemReferenceTargetKind.project:
        return TextSystemReferenceActionType.project;
      case TextSystemReferenceTargetKind.todo:
        return TextSystemReferenceActionType.todo;
      case TextSystemReferenceTargetKind.link:
      case TextSystemReferenceTargetKind.figure:
      case TextSystemReferenceTargetKind.table:
      case TextSystemReferenceTargetKind.unknown:
        return TextSystemReferenceActionType.link;
    }
  }
}

class _OwnedReferencePreviewCard extends StatelessWidget {
  const _OwnedReferencePreviewCard({
    required this.inlineReference,
    required this.citationSettings,
    required this.pinned,
    required this.canEdit,
    required this.onTogglePinned,
    required this.onOpen,
    required this.onCopy,
    required this.onUnlink,
    required this.onClose,
    this.onEdit,
    this.onRemoveGeneratedText,
    this.onCitationModeChanged,
  });

  final TextSystemInlineReferenceMark inlineReference;
  final TextSystemCitationSettings citationSettings;
  final bool pinned;
  final bool canEdit;
  final VoidCallback onTogglePinned;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onUnlink;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onRemoveGeneratedText;
  final ValueChanged<TextSystemCitationInlineMode>? onCitationModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _referencePreviewTitle(inlineReference);
    final subtitle = _referencePreviewSubtitle(inlineReference, citationSettings);
    final locator = _referencePreviewLocator(inlineReference);
    final uri = inlineReference.uri?.toString();
    final sourceName = _referencePreviewSourceName(inlineReference);
    final excerpt = _referencePreviewExcerpt(inlineReference);
    final workStatePills = _referencePreviewWorkStatePills(inlineReference);
    final currentMode = TextSystemCitationInlineModeX.fromId(
      inlineReference.metadata['citationInlineMode'] as String?,
    );

    return Material(
      elevation: 10,
      color: colorScheme.surface,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.72)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_referencePreviewIcon(inlineReference.kind), size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inlineReference.kind.label,
                          style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: pinned ? 'Unpin preview' : 'Pin preview',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: onTogglePinned,
                    icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
              if (locator != null || uri != null || sourceName != null || workStatePills.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (sourceName != null) _ReferencePreviewPill(icon: Icons.picture_as_pdf_outlined, label: sourceName),
                    if (locator != null) _ReferencePreviewPill(icon: Icons.pin_drop_outlined, label: locator),
                    for (final pill in workStatePills) pill,
                    if (uri != null)
                      _ReferencePreviewPill(
                        icon: Icons.language,
                        label: Uri.tryParse(uri)?.host.isNotEmpty == true ? Uri.parse(uri).host : uri,
                      ),
                  ],
                ),
              ],
              if (excerpt != null) ...[
                const SizedBox(height: 8),
                Text(
                  excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (inlineReference.isCitation && onCitationModeChanged != null) ...[
                const SizedBox(height: 10),
                SegmentedButton<TextSystemCitationInlineMode>(
                  segments: TextSystemCitationInlineMode.values
                      .map(
                        (mode) => ButtonSegment<TextSystemCitationInlineMode>(
                          value: mode,
                          label: Text(mode == TextSystemCitationInlineMode.parenthetical ? 'Parenthetical' : 'Narrative'),
                        ),
                      )
                      .toList(growable: false),
                  selected: <TextSystemCitationInlineMode>{currentMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    onCitationModeChanged!(selection.single);
                  },
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(onPressed: onCopy, icon: const Icon(Icons.copy, size: 16), label: const Text('Copy')),
                  if (canEdit)
                    TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
                  TextButton.icon(
                    onPressed: onUnlink,
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Unlink, keep text'),
                  ),
                  if (onRemoveGeneratedText != null)
                    TextButton.icon(
                      onPressed: onRemoveGeneratedText,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(inlineReference.isCitation ? 'Remove citation' : 'Remove text'),
                    ),
                  FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.open_in_new, size: 16), label: Text(_referencePreviewOpenLabel(inlineReference))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferencePreviewPill extends StatelessWidget {
  const _ReferencePreviewPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label.length > 42 ? '${label.substring(0, 39)}…' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;
double mathMin(double a, double b) => a < b ? a : b;

String _referencePreviewTitle(TextSystemInlineReferenceMark inlineReference) {
  final metadataTitle = inlineReference.metadata['title']?.toString().trim();
  if (metadataTitle != null && metadataTitle.isNotEmpty) return metadataTitle;
  final citationText = inlineReference.metadata['citationText']?.toString().trim();
  if (inlineReference.isCitation && citationText != null && citationText.isNotEmpty) return citationText;
  final label = inlineReference.label.trim();
  if (label.isNotEmpty) return label;
  return inlineReference.kind.label;
}

String? _referencePreviewSubtitle(
  TextSystemInlineReferenceMark inlineReference,
  TextSystemCitationSettings citationSettings,
) {
  if (inlineReference.isCitation) {
    final source = TextSystemCitationSource.fromInlineMark(inlineReference);
    final parts = <String>[
      if (source.authors.isNotEmpty) source.authors.join(', '),
      if (source.year != null && source.year!.trim().isNotEmpty) source.year!.trim(),
      if (source.containerTitle != null && source.containerTitle!.trim().isNotEmpty) source.containerTitle!.trim(),
      if (_referencePreviewSourceName(inlineReference) != null) _referencePreviewSourceName(inlineReference)!,
      citationSettings.style.label,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
  final selectedText = inlineReference.selectedText?.trim();
  final target = inlineReference.targetId.trim();
  final parts = <String>[
    if (selectedText != null && selectedText.isNotEmpty) 'Text: $selectedText',
    if (target.isNotEmpty) 'Target: $target',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _referencePreviewLocator(TextSystemInlineReferenceMark inlineReference) {
  final sourceLocator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final sourcePageLabel = sourceLocator?.pageLabel?.trim();
  if (sourcePageLabel != null && sourcePageLabel.isNotEmpty) return sourcePageLabel;
  final sourcePage = sourceLocator?.effectivePageNumber;
  if (sourcePage != null && sourcePage > 0) return 'p. $sourcePage';
  final locator = inlineReference.metadata['locator']?.toString().trim();
  if (locator != null && locator.isNotEmpty) return locator.startsWith('p.') || locator.startsWith('pp.') ? locator : 'p. $locator';
  final page = inlineReference.metadata['page']?.toString().trim() ?? inlineReference.metadata['pageNumber']?.toString().trim();
  if (page != null && page.isNotEmpty) return 'p. $page';
  return null;
}

String? _referencePreviewSourceName(TextSystemInlineReferenceMark inlineReference) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final title = locator?.sourceTitle?.trim();
  if (title != null && title.isNotEmpty) return title;
  final metadataTitle = inlineReference.metadata['sourceTitle']?.toString().trim();
  if (metadataTitle != null && metadataTitle.isNotEmpty) return metadataTitle;
  return null;
}

String? _referencePreviewExcerpt(TextSystemInlineReferenceMark inlineReference) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final excerpt = locator?.excerpt?.trim() ?? inlineReference.metadata['excerpt']?.toString().trim();
  if (excerpt == null || excerpt.isEmpty) return null;
  return excerpt.length <= 180 ? '“$excerpt”' : '“${excerpt.substring(0, 177)}…”';
}

List<_ReferencePreviewPill> _referencePreviewWorkStatePills(TextSystemInlineReferenceMark inlineReference) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  final workState = locator?.workState ?? _mapFromMetadata(inlineReference.metadata['workState']);
  final sidecarNotes = _intFromObject(workState['sidecarNoteCount']);
  final highlights = _intFromObject(workState['highlightCount']);
  final openTodos = _intFromObject(workState['openTodoCount']);
  return <_ReferencePreviewPill>[
    if (sidecarNotes != null && sidecarNotes > 0)
      _ReferencePreviewPill(icon: Icons.sticky_note_2_outlined, label: '$sidecarNotes note${sidecarNotes == 1 ? '' : 's'}'),
    if (highlights != null && highlights > 0)
      _ReferencePreviewPill(icon: Icons.highlight_outlined, label: '$highlights highlight${highlights == 1 ? '' : 's'}'),
    if (openTodos != null && openTodos > 0)
      _ReferencePreviewPill(icon: Icons.check_circle_outline_rounded, label: '$openTodos TODO${openTodos == 1 ? '' : 's'}'),
  ];
}

String _referencePreviewOpenLabel(TextSystemInlineReferenceMark inlineReference) {
  final locator = TextSystemSourceLocator.tryFromInlineReference(inlineReference);
  if (locator?.hasPdfTarget == true ||
      inlineReference.metadata['pdfReferenceId'] != null ||
      inlineReference.metadata['pageNumber'] != null ||
      inlineReference.metadata['sourceRects'] != null) {
    return 'Open in PDF';
  }
  return 'Open';
}

Map<String, Object?> _mapFromMetadata(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?));
  return const <String, Object?>{};
}

int? _intFromObject(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _referencePreviewClipboardText(TextSystemInlineReferenceMark inlineReference) {
  final lines = <String>[
    '${inlineReference.kind.label}: ${_referencePreviewTitle(inlineReference)}',
    if (_referencePreviewSubtitle(inlineReference, const TextSystemCitationSettings()) != null)
      _referencePreviewSubtitle(inlineReference, const TextSystemCitationSettings())!,
    if (_referencePreviewSourceName(inlineReference) != null) _referencePreviewSourceName(inlineReference)!,
    if (_referencePreviewLocator(inlineReference) != null) _referencePreviewLocator(inlineReference)!,
    if (_referencePreviewExcerpt(inlineReference) != null) _referencePreviewExcerpt(inlineReference)!,
    if (inlineReference.uri != null) inlineReference.uri.toString(),
    'targetId: ${inlineReference.targetId}',
  ];
  return lines.join('\n');
}

IconData _referencePreviewIcon(TextSystemReferenceTargetKind kind) {
  return switch (kind) {
    TextSystemReferenceTargetKind.citation => Icons.format_quote,
    TextSystemReferenceTargetKind.source => Icons.picture_as_pdf_outlined,
    TextSystemReferenceTargetKind.document => Icons.description_outlined,
    TextSystemReferenceTargetKind.project => Icons.folder_open,
    TextSystemReferenceTargetKind.todo => Icons.check_circle_outline,
    TextSystemReferenceTargetKind.link => Icons.link,
    TextSystemReferenceTargetKind.figure => Icons.image_outlined,
    TextSystemReferenceTargetKind.table => Icons.table_chart_outlined,
    TextSystemReferenceTargetKind.unknown => Icons.bookmark_border,
  };
}
