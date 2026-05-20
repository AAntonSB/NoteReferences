class EpubReaderPaginationKind {
  static const String readerGeneratedPages = 'reader_generated_pages';
  static const String publisherPages = 'publisher_pages';
  static const String stableLocations = 'stable_locations';
}

class EpubReaderPaginationModel {
  final String kind;
  final int sectionIndex;
  final int sectionCount;
  final int pageCount;
  final int currentPageIndex;
  final bool layoutDependent;
  final String label;

  const EpubReaderPaginationModel({
    required this.kind,
    required this.sectionIndex,
    required this.sectionCount,
    required this.pageCount,
    required this.currentPageIndex,
    required this.layoutDependent,
    required this.label,
  });

  factory EpubReaderPaginationModel.readerGenerated({
    required int sectionIndex,
    required int sectionCount,
    required int pageCount,
    required int currentPageIndex,
  }) {
    return EpubReaderPaginationModel(
      kind: EpubReaderPaginationKind.readerGeneratedPages,
      sectionIndex: sectionIndex,
      sectionCount: sectionCount,
      pageCount: pageCount,
      currentPageIndex: currentPageIndex,
      layoutDependent: true,
      label: 'Reader pages',
    );
  }

  String get currentPageLabel => '${currentPageIndex + 1} of $pageCount';

  String get scopeLabel => 'Section ${sectionIndex + 1} of $sectionCount';

  String get stabilityLabel {
    if (kind == EpubReaderPaginationKind.publisherPages) {
      return 'Publisher page map';
    }
    if (kind == EpubReaderPaginationKind.stableLocations) {
      return 'Stable app locations';
    }
    return 'Depends on reader layout';
  }
}
