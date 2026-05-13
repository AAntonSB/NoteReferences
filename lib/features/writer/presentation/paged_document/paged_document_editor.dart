import 'package:flutter/material.dart';

import 'document_page_spec.dart';
import 'paged_document_controller.dart';

class PagedDocumentEditor extends StatefulWidget {
  const PagedDocumentEditor({
    super.key,
    this.controller,
    this.showToolbar = true,
    this.autofocus = false,
    this.onChanged,
  });

  final PagedDocumentController? controller;
  final bool showToolbar;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<PagedDocumentEditor> createState() => _PagedDocumentEditorState();
}

class _PagedDocumentEditorState extends State<PagedDocumentEditor> {
  late bool _ownsController;
  late PagedDocumentController _controller;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? PagedDocumentController();
    _controller.addListener(_notifyPlainTextChanged);
  }

  @override
  void didUpdateWidget(covariant PagedDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_notifyPlainTextChanged);

      if (_ownsController) {
        _controller.dispose();
      }

      _ownsController = widget.controller == null;
      _controller = widget.controller ?? PagedDocumentController();
      _controller.addListener(_notifyPlainTextChanged);
    }
  }

  void _notifyPlainTextChanged() {
    widget.onChanged?.call(_controller.plainText);
  }

  @override
  void dispose() {
    _controller.removeListener(_notifyPlainTextChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final style = _controller.pageStyle;

        return Column(
          children: <Widget>[
            if (widget.showToolbar)
              _PagedDocumentToolbar(controller: _controller),
            Expanded(
              child: ColoredBox(
                color: style.workspaceColor,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      padding: style.workspacePadding,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (var index = 0;
                                index < _controller.pages.length;
                                index++)
                              _AcademicPageSurface(
                                page: _controller.pages[index],
                                pageIndex: index,
                                pageCount: _controller.pages.length,
                                pageStyle: style,
                                autofocus: widget.autofocus && index == 0,
                                onAddPageAfter: () {
                                  _controller.addPage(afterIndex: index);
                                },
                                onRemovePage: _controller.pages.length <= 1
                                    ? null
                                    : () => _controller.removePageAt(index),
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
        );
      },
    );
  }
}

class _PagedDocumentToolbar extends StatelessWidget {
  const _PagedDocumentToolbar({
    required this.controller,
  });

  final PagedDocumentController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = controller.pageStyle;
    final snapshot = controller.debugSnapshot;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: <Widget>[
            _ToolbarLabel(text: 'Page'),
            DropdownButton<DocumentPageSize>(
              value: style.pageSize,
              underline: const SizedBox.shrink(),
              items: DocumentPageSize.values
                  .map(
                    (size) => DropdownMenuItem<DocumentPageSize>(
                      value: size,
                      child: Text(size.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.setPageSize(value);
                }
              },
            ),
            const SizedBox(width: 20),
            _ToolbarLabel(text: 'Typography'),
            DropdownButton<AcademicTypographyPreset>(
              value: style.typographyPreset,
              underline: const SizedBox.shrink(),
              items: AcademicTypographyPreset.values
                  .map(
                    (preset) => DropdownMenuItem<AcademicTypographyPreset>(
                      value: preset,
                      child: Text(preset.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  controller.setTypographyPreset(value);
                }
              },
            ),
            const SizedBox(width: 20),
            FilterChip(
              label: const Text('Margins'),
              selected: style.showMarginGuides,
              onSelected: controller.setMarginGuidesVisible,
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => controller.addPage(focus: true),
              icon: const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('Writing room'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: controller.trimEmptyTrailingPages,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Trim trailing'),
            ),
            const SizedBox(width: 20),
            Center(
              child: Tooltip(
                message: snapshot.pageRanges.join('\n'),
                child: Text(
                  '${snapshot.pageCount} page${snapshot.pageCount == 1 ? '' : 's'} · ${snapshot.characterCount} chars',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarLabel extends StatelessWidget {
  const _ToolbarLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _AcademicPageSurface extends StatelessWidget {
  const _AcademicPageSurface({
    required this.page,
    required this.pageIndex,
    required this.pageCount,
    required this.pageStyle,
    required this.autofocus,
    required this.onAddPageAfter,
    required this.onRemovePage,
  });

  final DocumentPageModel page;
  final int pageIndex;
  final int pageCount;
  final AcademicPageStyle pageStyle;
  final bool autofocus;
  final VoidCallback onAddPageAfter;
  final VoidCallback? onRemovePage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: pageStyle.pageGap),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Stack(
          children: <Widget>[
            Container(
              width: pageStyle.pageWidthPt,
              height: pageStyle.pageHeightPt,
              decoration: BoxDecoration(
                color: pageStyle.pageColor,
                border: Border.all(color: pageStyle.pageBorderColor),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    blurRadius: 18,
                    spreadRadius: 0,
                    offset: Offset(0, 6),
                    color: Color(0x1A000000),
                  ),
                ],
              ),
              child: Stack(
                children: <Widget>[
                  if (pageStyle.showMarginGuides)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _MarginGuidePainter(
                            margins: pageStyle.margins,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: pageStyle.margins,
                    child: TextField(
                      controller: page.textController,
                      focusNode: page.focusNode,
                      autofocus: autofocus,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textAlignVertical: TextAlignVertical.top,
                      style: pageStyle.bodyStyle,
                      cursorHeight: (pageStyle.bodyStyle.fontSize ?? 12) *
                          (pageStyle.bodyStyle.height ?? 1.5),
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 22,
                    child: IgnorePointer(
                      child: Text(
                        '${pageIndex + 1}',
                        textAlign: TextAlign.center,
                        style: pageStyle.captionStyle.copyWith(
                          color: const Color(0x66000000),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: _PageActions(
                pageNumber: pageIndex + 1,
                pageCount: pageCount,
                startOffset: page.startOffset,
                endOffset: page.endOffset,
                onAddPageAfter: onAddPageAfter,
                onRemovePage: onRemovePage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageActions extends StatelessWidget {
  const _PageActions({
    required this.pageNumber,
    required this.pageCount,
    required this.startOffset,
    required this.endOffset,
    required this.onAddPageAfter,
    required this.onRemovePage,
  });

  final int pageNumber;
  final int pageCount;
  final int startOffset;
  final int endOffset;
  final VoidCallback onAddPageAfter;
  final VoidCallback? onRemovePage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(999),
      elevation: 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Tooltip(
            message: 'Text range $startOffset..$endOffset',
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Text(
                '$pageNumber/$pageCount',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add writing room after',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onAddPageAfter,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Remove this page text',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onRemovePage,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _MarginGuidePainter extends CustomPainter {
  const _MarginGuidePainter({
    required this.margins,
  });

  final EdgeInsets margins;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x220077FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rect = Rect.fromLTWH(
      margins.left,
      margins.top,
      size.width - margins.horizontal,
      size.height - margins.vertical,
    );

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _MarginGuidePainter oldDelegate) {
    return oldDelegate.margins != margins;
  }
}
