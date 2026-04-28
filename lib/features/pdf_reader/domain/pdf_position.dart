class PdfPosition {
  final String documentId;
  final int pageNumber;
  final double scrollX;
  final double scrollY;
  final double zoomLevel;
  final DateTime updatedAt;

  const PdfPosition({
    required this.documentId,
    required this.pageNumber,
    required this.scrollX,
    required this.scrollY,
    required this.zoomLevel,
    required this.updatedAt,
  });

  PdfPosition copyWith({
    String? documentId,
    int? pageNumber,
    double? scrollX,
    double? scrollY,
    double? zoomLevel,
    DateTime? updatedAt,
  }) {
    return PdfPosition(
      documentId: documentId ?? this.documentId,
      pageNumber: pageNumber ?? this.pageNumber,
      scrollX: scrollX ?? this.scrollX,
      scrollY: scrollY ?? this.scrollY,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}