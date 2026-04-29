class MappedSidecarY {
  final String mode;
  final int pageNumber;
  final double pdfSegmentTop;
  final double pdfSegmentHeight;
  final double segmentProgress;
  final double sidecarY;

  const MappedSidecarY({
    required this.mode,
    required this.pageNumber,
    required this.pdfSegmentTop,
    required this.pdfSegmentHeight,
    required this.segmentProgress,
    required this.sidecarY,
  });
}

class ContinuousSyncTarget {
  final String mode;
  final int pageNumber;
  final double pdfAnchorY;
  final double pdfSegmentTop;
  final double pdfSegmentHeight;
  final double segmentProgress;
  final double sidecarAnchorY;
  final double targetOffset;

  const ContinuousSyncTarget({
    required this.mode,
    required this.pageNumber,
    required this.pdfAnchorY,
    required this.pdfSegmentTop,
    required this.pdfSegmentHeight,
    required this.segmentProgress,
    required this.sidecarAnchorY,
    required this.targetOffset,
  });
}

class SyncDebugState {
  final String mode;
  final int pageNumber;
  final double pdfAnchorY;
  final double pdfSegmentTop;
  final double pdfSegmentHeight;
  final double segmentProgress;
  final double sidecarAnchorY;
  final double targetOffset;
  final double actualBefore;
  final double actualAfter;
  final double correctionBeforeJump;

  const SyncDebugState({
    required this.mode,
    required this.pageNumber,
    required this.pdfAnchorY,
    required this.pdfSegmentTop,
    required this.pdfSegmentHeight,
    required this.segmentProgress,
    required this.sidecarAnchorY,
    required this.targetOffset,
    required this.actualBefore,
    required this.actualAfter,
    required this.correctionBeforeJump,
  });

  @override
  bool operator ==(Object other) {
    return other is SyncDebugState &&
        other.mode == mode &&
        other.pageNumber == pageNumber &&
        other.pdfAnchorY == pdfAnchorY &&
        other.pdfSegmentTop == pdfSegmentTop &&
        other.pdfSegmentHeight == pdfSegmentHeight &&
        other.segmentProgress == segmentProgress &&
        other.sidecarAnchorY == sidecarAnchorY &&
        other.targetOffset == targetOffset &&
        other.actualBefore == actualBefore &&
        other.actualAfter == actualAfter &&
        other.correctionBeforeJump == correctionBeforeJump;
  }

  @override
  int get hashCode {
    return Object.hash(
      mode,
      pageNumber,
      pdfAnchorY,
      pdfSegmentTop,
      pdfSegmentHeight,
      segmentProgress,
      sidecarAnchorY,
      targetOffset,
      actualBefore,
      actualAfter,
      correctionBeforeJump,
    );
  }
}