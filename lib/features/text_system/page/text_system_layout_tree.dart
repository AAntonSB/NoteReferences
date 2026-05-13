import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';

import '../core/text_system_block.dart';
import 'text_system_page_furniture.dart';
import 'text_system_page_setup.dart';

enum TextSystemLayoutMeasurementMode {
  blockEstimated,
  lineMeasured;

  String get label {
    return switch (this) {
      TextSystemLayoutMeasurementMode.blockEstimated => 'Block-estimated',
      TextSystemLayoutMeasurementMode.lineMeasured => 'Line-measured',
    };
  }
}

@immutable
class TextSystemDocumentLayoutTree {
  const TextSystemDocumentLayoutTree({
    required this.documentId,
    required this.documentRevision,
    required this.generatedAt,
    required this.pageSetup,
    required this.pageFurniture,
    required this.measurementMode,
    required this.visualPageWidthPx,
    required this.visualPageHeightPx,
    required this.pages,
  });

  final String documentId;
  final int documentRevision;
  final DateTime generatedAt;
  final TextSystemPageSetup pageSetup;
  final TextSystemPageFurniture pageFurniture;
  final TextSystemLayoutMeasurementMode measurementMode;
  final double visualPageWidthPx;
  final double visualPageHeightPx;
  final List<TextSystemLayoutPage> pages;

  int get pageCount => pages.isEmpty ? 1 : pages.length;

  int get blockFragmentCount => pages.fold<int>(
        0,
        (count, page) => count + page.blockFragments.length,
      );

  int get lineFragmentCount => pages.fold<int>(
        0,
        (count, page) => count + page.lineFragments.length,
      );

  int get footnoteCount => pages.fold<int>(
        0,
        (count, page) => count + page.footnotes.length,
      );

  bool get isLineAccurate => measurementMode == TextSystemLayoutMeasurementMode.lineMeasured;

  String get compactLabel =>
      '$pageCount page${pageCount == 1 ? '' : 's'} · '
      '$blockFragmentCount block fragments · '
      '$lineFragmentCount line fragments · ${measurementMode.label}';

  Iterable<TextSystemLayoutBlockFragment> fragmentsForBlock(String blockId) sync* {
    for (final page in pages) {
      for (final fragment in page.blockFragments) {
        if (fragment.blockId == blockId) {
          yield fragment;
        }
      }
    }
  }

  TextSystemLayoutBlockFragment? firstFragmentForBlock(String blockId) {
    for (final page in pages) {
      for (final fragment in page.blockFragments) {
        if (fragment.blockId == blockId) return fragment;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'documentRevision': documentRevision,
      'generatedAt': generatedAt.toIso8601String(),
      'measurementMode': measurementMode.name,
      'visualPageWidthPx': visualPageWidthPx,
      'visualPageHeightPx': visualPageHeightPx,
      'pageCount': pageCount,
      'blockFragmentCount': blockFragmentCount,
      'lineFragmentCount': lineFragmentCount,
      'footnoteCount': footnoteCount,
      'pageSetup': pageSetup.toJson(),
      'pageFurniture': pageFurniture.toJson(),
      'pages': [for (final page in pages) page.toJson()],
    };
  }
}

@immutable
class TextSystemLayoutPage {
  const TextSystemLayoutPage({
    required this.pageIndex,
    required this.physicalPageNumber,
    required this.logicalPageNumber,
    required this.sectionIndex,
    required this.sectionId,
    required this.pageRect,
    required this.contentRect,
    required this.headerRect,
    required this.footerRect,
    required this.footnoteRect,
    required this.blockFragments,
    required this.lineFragments,
    required this.footnotes,
  });

  final int pageIndex;
  final int physicalPageNumber;
  final int logicalPageNumber;
  final int sectionIndex;
  final String? sectionId;
  final Rect pageRect;
  final Rect contentRect;
  final Rect headerRect;
  final Rect footerRect;
  final Rect footnoteRect;
  final List<TextSystemLayoutBlockFragment> blockFragments;
  final List<TextSystemLayoutLineFragment> lineFragments;
  final List<TextSystemLayoutFootnote> footnotes;

  bool get isEmpty => blockFragments.isEmpty && footnotes.isEmpty;

  String get pageLabel =>
      logicalPageNumber == physicalPageNumber
          ? 'Page $physicalPageNumber'
          : 'Page $logicalPageNumber · physical $physicalPageNumber';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pageIndex': pageIndex,
      'physicalPageNumber': physicalPageNumber,
      'logicalPageNumber': logicalPageNumber,
      'sectionIndex': sectionIndex,
      'sectionId': sectionId,
      'pageRect': _rectToJson(pageRect),
      'contentRect': _rectToJson(contentRect),
      'headerRect': _rectToJson(headerRect),
      'footerRect': _rectToJson(footerRect),
      'footnoteRect': _rectToJson(footnoteRect),
      'blockFragments': [for (final fragment in blockFragments) fragment.toJson()],
      'lineFragments': [for (final line in lineFragments) line.toJson()],
      'footnotes': [for (final footnote in footnotes) footnote.toJson()],
    };
  }
}

@immutable
class TextSystemLayoutBlockFragment {
  const TextSystemLayoutBlockFragment({
    required this.blockId,
    required this.blockIndex,
    required this.blockType,
    required this.blockLevel,
    required this.fragmentIndexOnPage,
    required this.pageIndex,
    required this.physicalPageNumber,
    required this.logicalPageNumber,
    required this.textStartOffset,
    required this.textEndOffset,
    required this.rect,
    required this.visibleText,
    required this.isSplitFragment,
    required this.continuesFromPreviousPage,
    required this.continuesOnNextPage,
    required this.oversized,
    required this.styleId,
  });

  final String blockId;
  final int blockIndex;
  final TextSystemBlockType blockType;
  final int? blockLevel;
  final int fragmentIndexOnPage;
  final int pageIndex;
  final int physicalPageNumber;
  final int logicalPageNumber;
  final int textStartOffset;
  final int textEndOffset;
  final Rect rect;
  final String visibleText;
  final bool isSplitFragment;
  final bool continuesFromPreviousPage;
  final bool continuesOnNextPage;
  final bool oversized;
  final String styleId;

  int get textLength => textEndOffset - textStartOffset;
  bool get hasText => textLength > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'blockType': blockType.name,
      'blockLevel': blockLevel,
      'fragmentIndexOnPage': fragmentIndexOnPage,
      'pageIndex': pageIndex,
      'physicalPageNumber': physicalPageNumber,
      'logicalPageNumber': logicalPageNumber,
      'textStartOffset': textStartOffset,
      'textEndOffset': textEndOffset,
      'rect': _rectToJson(rect),
      'visibleText': visibleText,
      'isSplitFragment': isSplitFragment,
      'continuesFromPreviousPage': continuesFromPreviousPage,
      'continuesOnNextPage': continuesOnNextPage,
      'oversized': oversized,
      'styleId': styleId,
    };
  }
}

@immutable
class TextSystemLayoutLineFragment {
  const TextSystemLayoutLineFragment({
    required this.blockId,
    required this.blockIndex,
    required this.pageIndex,
    required this.physicalPageNumber,
    required this.logicalPageNumber,
    required this.lineIndexInBlock,
    required this.textStartOffset,
    required this.textEndOffset,
    required this.rect,
    required this.baseline,
    required this.text,
    required this.styleId,
  });

  final String blockId;
  final int blockIndex;
  final int pageIndex;
  final int physicalPageNumber;
  final int logicalPageNumber;
  final int lineIndexInBlock;
  final int textStartOffset;
  final int textEndOffset;
  final Rect rect;
  final double baseline;
  final String text;
  final String styleId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'blockId': blockId,
      'blockIndex': blockIndex,
      'pageIndex': pageIndex,
      'physicalPageNumber': physicalPageNumber,
      'logicalPageNumber': logicalPageNumber,
      'lineIndexInBlock': lineIndexInBlock,
      'textStartOffset': textStartOffset,
      'textEndOffset': textEndOffset,
      'rect': _rectToJson(rect),
      'baseline': baseline,
      'text': text,
      'styleId': styleId,
    };
  }
}

@immutable
class TextSystemLayoutFootnote {
  const TextSystemLayoutFootnote({
    required this.footnoteId,
    required this.blockId,
    required this.anchorBlockId,
    required this.anchorOffset,
    required this.number,
    required this.text,
    required this.rect,
  });

  final String footnoteId;
  final String blockId;
  final String anchorBlockId;
  final int anchorOffset;
  final int number;
  final String text;
  final Rect rect;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'footnoteId': footnoteId,
      'blockId': blockId,
      'anchorBlockId': anchorBlockId,
      'anchorOffset': anchorOffset,
      'number': number,
      'text': text,
      'rect': _rectToJson(rect),
    };
  }
}

String textSystemStyleIdForBlockType(TextSystemBlockType type, int? level) {
  return switch (type) {
    TextSystemBlockType.heading => 'heading-${level ?? 1}',
    TextSystemBlockType.paragraph => 'paragraph',
    TextSystemBlockType.listItem => 'list-item',
    TextSystemBlockType.todo => 'todo',
    TextSystemBlockType.quote => 'quote',
    TextSystemBlockType.code => 'code',
    TextSystemBlockType.divider => 'structural-divider',
    TextSystemBlockType.custom => 'custom',
  };
}

Map<String, Object?> _rectToJson(Rect rect) {
  return <String, Object?>{
    'left': rect.left,
    'top': rect.top,
    'right': rect.right,
    'bottom': rect.bottom,
    'width': rect.width,
    'height': rect.height,
  };
}

Map<String, Object?> sizeToJson(Size size) {
  return <String, Object?>{
    'width': size.width,
    'height': size.height,
  };
}
