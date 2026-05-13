import 'package:flutter/widgets.dart';

enum TextSystemPageOrientation {
  portrait,
  landscape,
}

enum TextSystemPageSizeKind {
  a4,
  a5,
  letter,
  legal,
  custom,
}

@immutable
class TextSystemPageSize {
  const TextSystemPageSize({
    required this.kind,
    required this.label,
    required this.widthMm,
    required this.heightMm,
  });

  const TextSystemPageSize.a4()
      : kind = TextSystemPageSizeKind.a4,
        label = 'A4',
        widthMm = 210,
        heightMm = 297;

  const TextSystemPageSize.a5()
      : kind = TextSystemPageSizeKind.a5,
        label = 'A5',
        widthMm = 148,
        heightMm = 210;

  const TextSystemPageSize.letter()
      : kind = TextSystemPageSizeKind.letter,
        label = 'Letter',
        widthMm = 215.9,
        heightMm = 279.4;

  const TextSystemPageSize.legal()
      : kind = TextSystemPageSizeKind.legal,
        label = 'Legal',
        widthMm = 215.9,
        heightMm = 355.6;

  const TextSystemPageSize.custom({
    required String label,
    required double widthMm,
    required double heightMm,
  }) : this(
          kind: TextSystemPageSizeKind.custom,
          label: label,
          widthMm: widthMm,
          heightMm: heightMm,
        );

  final TextSystemPageSizeKind kind;
  final String label;
  final double widthMm;
  final double heightMm;

  double widthFor(TextSystemPageOrientation orientation) {
    return orientation == TextSystemPageOrientation.portrait ? widthMm : heightMm;
  }

  double heightFor(TextSystemPageOrientation orientation) {
    return orientation == TextSystemPageOrientation.portrait ? heightMm : widthMm;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'label': label,
      'widthMm': widthMm,
      'heightMm': heightMm,
    };
  }
}

@immutable
class TextSystemPageMargins {
  const TextSystemPageMargins({
    required this.topMm,
    required this.rightMm,
    required this.bottomMm,
    required this.leftMm,
  });

  const TextSystemPageMargins.all(double valueMm)
      : topMm = valueMm,
        rightMm = valueMm,
        bottomMm = valueMm,
        leftMm = valueMm;

  const TextSystemPageMargins.academic() : this.all(25.4);

  const TextSystemPageMargins.compact()
      : topMm = 18,
        rightMm = 18,
        bottomMm = 18,
        leftMm = 18;

  const TextSystemPageMargins.roomy()
      : topMm = 32,
        rightMm = 32,
        bottomMm = 32,
        leftMm = 32;

  const TextSystemPageMargins.binding()
      : topMm = 25.4,
        rightMm = 25.4,
        bottomMm = 25.4,
        leftMm = 32;

  final double topMm;
  final double rightMm;
  final double bottomMm;
  final double leftMm;

  double get horizontalMm => leftMm + rightMm;
  double get verticalMm => topMm + bottomMm;

  EdgeInsets toPagePadding(double pageWidthPx, double pageWidthMm) {
    final pxPerMm = pageWidthPx / pageWidthMm;
    return EdgeInsets.fromLTRB(
      leftMm * pxPerMm,
      topMm * pxPerMm,
      rightMm * pxPerMm,
      bottomMm * pxPerMm,
    );
  }

  String get shortLabel {
    final values = <double>{topMm, rightMm, bottomMm, leftMm};
    if (values.length == 1) return '${topMm.toStringAsFixed(1)} mm';
    if (leftMm > rightMm && topMm == rightMm && bottomMm == rightMm) {
      return '${rightMm.toStringAsFixed(1)} mm + ${leftMm.toStringAsFixed(1)} mm binding';
    }
    return 'T ${topMm.toStringAsFixed(1)} / R ${rightMm.toStringAsFixed(1)} / B ${bottomMm.toStringAsFixed(1)} / L ${leftMm.toStringAsFixed(1)} mm';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'topMm': topMm,
      'rightMm': rightMm,
      'bottomMm': bottomMm,
      'leftMm': leftMm,
      'shortLabel': shortLabel,
    };
  }

  @override
  String toString() => shortLabel;
}

/// Typography contract used by the page system and premium writer.
///
/// This is intentionally attached to page setup rather than hard-coded in the
/// editor. Pages, measured pagination, and the visible fluent editor should all
/// use the same broad academic body/heading metrics.
@immutable
class TextSystemPageTypography {
  const TextSystemPageTypography({
    required this.id,
    required this.label,
    required this.description,
    required this.fontFamily,
    this.fontFamilyFallback = const <String>[],
    required this.bodyFontSizePt,
    required this.lineSpacing,
    required this.heading1FontSizePt,
    required this.heading2FontSizePt,
    required this.heading3FontSizePt,
    required this.headingLineHeight,
    required this.paragraphSpacingPt,
  });

  const TextSystemPageTypography.academicThesis()
      : id = 'academic-thesis',
        label = 'Thesis',
        description = '12 pt serif body, 1.5 line spacing, conservative academic hierarchy.',
        fontFamily = 'Times New Roman',
        fontFamilyFallback = const <String>['Georgia', 'Cambria', 'Times'],
        bodyFontSizePt = 12,
        lineSpacing = 1.5,
        heading1FontSizePt = 18,
        heading2FontSizePt = 15,
        heading3FontSizePt = 13.5,
        headingLineHeight = 1.25,
        paragraphSpacingPt = 8;

  const TextSystemPageTypography.academicPaper()
      : id = 'academic-paper',
        label = 'Paper',
        description = '11 pt serif body with tighter spacing for article-style papers.',
        fontFamily = 'Times New Roman',
        fontFamilyFallback = const <String>['Georgia', 'Cambria', 'Times'],
        bodyFontSizePt = 11,
        lineSpacing = 1.35,
        heading1FontSizePt = 16,
        heading2FontSizePt = 14,
        heading3FontSizePt = 12.5,
        headingLineHeight = 1.22,
        paragraphSpacingPt = 6;

  const TextSystemPageTypography.draftReview()
      : id = 'draft-review',
        label = 'Draft review',
        description = '12 pt readable body with generous line spacing for revision.',
        fontFamily = 'Georgia',
        fontFamilyFallback = const <String>['Times New Roman', 'Cambria', 'Times'],
        bodyFontSizePt = 12,
        lineSpacing = 1.7,
        heading1FontSizePt = 18,
        heading2FontSizePt = 15,
        heading3FontSizePt = 13.5,
        headingLineHeight = 1.25,
        paragraphSpacingPt = 10;

  const TextSystemPageTypography.screenWriting()
      : id = 'screen-writing',
        label = 'Screen writing',
        description = 'Comfortable screen-first prose style for pageless or early drafting.',
        fontFamily = null,
        fontFamilyFallback = const <String>[],
        bodyFontSizePt = 16,
        lineSpacing = 1.45,
        heading1FontSizePt = 28,
        heading2FontSizePt = 22,
        heading3FontSizePt = 18,
        headingLineHeight = 1.18,
        paragraphSpacingPt = 10;

  final String id;
  final String label;
  final String description;
  final String? fontFamily;
  final List<String> fontFamilyFallback;
  final double bodyFontSizePt;
  final double lineSpacing;
  final double heading1FontSizePt;
  final double heading2FontSizePt;
  final double heading3FontSizePt;
  final double headingLineHeight;
  final double paragraphSpacingPt;

  String get compactLabel => '$label · ${bodyFontSizePt.toStringAsFixed(1)} pt / ${lineSpacing.toStringAsFixed(2)}';

  double headingFontSizeForLevel(int level) {
    return switch (level) {
      1 => heading1FontSizePt,
      2 => heading2FontSizePt,
      _ => heading3FontSizePt,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'description': description,
      'fontFamily': fontFamily,
      'fontFamilyFallback': fontFamilyFallback,
      'bodyFontSizePt': bodyFontSizePt,
      'lineSpacing': lineSpacing,
      'heading1FontSizePt': heading1FontSizePt,
      'heading2FontSizePt': heading2FontSizePt,
      'heading3FontSizePt': heading3FontSizePt,
      'headingLineHeight': headingLineHeight,
      'paragraphSpacingPt': paragraphSpacingPt,
    };
  }

  static const TextSystemPageTypography thesis = TextSystemPageTypography.academicThesis();
  static const TextSystemPageTypography paper = TextSystemPageTypography.academicPaper();
  static const TextSystemPageTypography draft = TextSystemPageTypography.draftReview();
  static const TextSystemPageTypography screen = TextSystemPageTypography.screenWriting();

  static const List<TextSystemPageTypography> builtIn = <TextSystemPageTypography>[
    thesis,
    paper,
    draft,
    screen,
  ];
}

@immutable
class TextSystemPageConstraint {
  const TextSystemPageConstraint({
    this.maxPages,
    this.label,
  });

  const TextSystemPageConstraint.none()
      : maxPages = null,
        label = null;

  final int? maxPages;
  final String? label;

  bool get hasPageLimit => maxPages != null && maxPages! > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'maxPages': maxPages,
      'label': label,
    };
  }
}

@immutable
class TextSystemPageSetup {
  const TextSystemPageSetup({
    this.size = const TextSystemPageSize.a4(),
    this.orientation = TextSystemPageOrientation.portrait,
    this.margins = const TextSystemPageMargins.academic(),
    this.constraint = const TextSystemPageConstraint.none(),
    this.typography = const TextSystemPageTypography.academicThesis(),
    this.lineSpacing = 1.5,
    this.defaultFontSize = 12,
    this.showPageNumbers = true,
  });

  final TextSystemPageSize size;
  final TextSystemPageOrientation orientation;
  final TextSystemPageMargins margins;
  final TextSystemPageConstraint constraint;
  final TextSystemPageTypography typography;
  final double lineSpacing;
  final double defaultFontSize;
  final bool showPageNumbers;

  double get pageWidthMm => size.widthFor(orientation);
  double get pageHeightMm => size.heightFor(orientation);
  double get contentWidthMm => pageWidthMm - margins.horizontalMm;
  double get contentHeightMm => pageHeightMm - margins.verticalMm;
  double get heightToWidthRatio => pageHeightMm / pageWidthMm;
  double get visualWidthScaleRelativeToA4Portrait => pageWidthMm / 210.0;

  TextSystemPageSetup copyWith({
    TextSystemPageSize? size,
    TextSystemPageOrientation? orientation,
    TextSystemPageMargins? margins,
    TextSystemPageConstraint? constraint,
    TextSystemPageTypography? typography,
    double? lineSpacing,
    double? defaultFontSize,
    bool? showPageNumbers,
  }) {
    final nextTypography = typography ?? this.typography;
    return TextSystemPageSetup(
      size: size ?? this.size,
      orientation: orientation ?? this.orientation,
      margins: margins ?? this.margins,
      constraint: constraint ?? this.constraint,
      typography: nextTypography,
      lineSpacing: lineSpacing ?? (typography == null ? this.lineSpacing : nextTypography.lineSpacing),
      defaultFontSize: defaultFontSize ?? (typography == null ? this.defaultFontSize : nextTypography.bodyFontSizePt),
      showPageNumbers: showPageNumbers ?? this.showPageNumbers,
    );
  }

  String get physicalSizeLabel {
    return '${pageWidthMm.toStringAsFixed(0)} × ${pageHeightMm.toStringAsFixed(0)} mm';
  }

  String get contentSizeLabel {
    return '${contentWidthMm.toStringAsFixed(0)} × ${contentHeightMm.toStringAsFixed(0)} mm content';
  }

  String get shortLabel {
    final limit = constraint.hasPageLimit ? ' · max ${constraint.maxPages} pages' : '';
    return '${size.label} ${orientation.name} · ${margins.toString()} margins · ${typography.compactLabel}$limit';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'size': size.toJson(),
      'orientation': orientation.name,
      'margins': margins.toJson(),
      'constraint': constraint.toJson(),
      'typography': typography.toJson(),
      'lineSpacing': lineSpacing,
      'defaultFontSize': defaultFontSize,
      'showPageNumbers': showPageNumbers,
      'physicalSizeLabel': physicalSizeLabel,
      'contentSizeLabel': contentSizeLabel,
    };
  }
}

@immutable
class TextSystemPagePreset {
  const TextSystemPagePreset({
    required this.id,
    required this.label,
    required this.description,
    required this.setup,
  });

  final String id;
  final String label;
  final String description;
  final TextSystemPageSetup setup;

  static const TextSystemPagePreset a4Academic = TextSystemPagePreset(
    id: 'a4-academic',
    label: 'A4 academic',
    description: 'A4 portrait with 25.4 mm margins and thesis typography.',
    setup: TextSystemPageSetup(
      size: TextSystemPageSize.a4(),
      orientation: TextSystemPageOrientation.portrait,
      margins: TextSystemPageMargins.academic(),
      typography: TextSystemPageTypography.thesis,
      lineSpacing: 1.5,
      defaultFontSize: 12,
      constraint: TextSystemPageConstraint.none(),
    ),
  );

  static const TextSystemPagePreset a4FivePages = TextSystemPagePreset(
    id: 'a4-five-pages',
    label: 'A4 max 5 pages',
    description: 'A4 academic setup with a 5-page assignment limit.',
    setup: TextSystemPageSetup(
      size: TextSystemPageSize.a4(),
      orientation: TextSystemPageOrientation.portrait,
      margins: TextSystemPageMargins.academic(),
      typography: TextSystemPageTypography.thesis,
      lineSpacing: 1.5,
      defaultFontSize: 12,
      constraint: TextSystemPageConstraint(maxPages: 5, label: 'Assignment limit'),
    ),
  );

  static const TextSystemPagePreset a4Compact = TextSystemPagePreset(
    id: 'a4-compact',
    label: 'A4 compact',
    description: 'A4 portrait with tighter 18 mm margins and paper typography.',
    setup: TextSystemPageSetup(
      size: TextSystemPageSize.a4(),
      orientation: TextSystemPageOrientation.portrait,
      margins: TextSystemPageMargins.compact(),
      typography: TextSystemPageTypography.paper,
      lineSpacing: 1.35,
      defaultFontSize: 11,
      constraint: TextSystemPageConstraint.none(),
    ),
  );

  static const TextSystemPagePreset a5Academic = TextSystemPagePreset(
    id: 'a5-academic',
    label: 'A5 academic',
    description: 'A5 portrait with academic margins. Useful for compact and thesis-notebook style writing.',
    setup: TextSystemPageSetup(
      size: TextSystemPageSize.a5(),
      orientation: TextSystemPageOrientation.portrait,
      margins: TextSystemPageMargins.academic(),
      typography: TextSystemPageTypography.paper,
      lineSpacing: 1.35,
      defaultFontSize: 11,
      constraint: TextSystemPageConstraint.none(),
    ),
  );

  static const TextSystemPagePreset letterStandard = TextSystemPagePreset(
    id: 'letter-standard',
    label: 'US Letter',
    description: 'US Letter portrait with academic margins and thesis typography.',
    setup: TextSystemPageSetup(
      size: TextSystemPageSize.letter(),
      orientation: TextSystemPageOrientation.portrait,
      margins: TextSystemPageMargins.academic(),
      typography: TextSystemPageTypography.thesis,
      lineSpacing: 1.5,
      defaultFontSize: 12,
      constraint: TextSystemPageConstraint.none(),
    ),
  );

  static const TextSystemPagePreset draftReview = TextSystemPagePreset(
    id: 'a4-draft-review',
    label: 'A4 draft review',
    description: 'A4 with roomy margins and generous spacing for revision.',
    setup: TextSystemPageSetup(
      size: TextSystemPageSize.a4(),
      orientation: TextSystemPageOrientation.portrait,
      margins: TextSystemPageMargins.roomy(),
      typography: TextSystemPageTypography.draft,
      lineSpacing: 1.7,
      defaultFontSize: 12,
      constraint: TextSystemPageConstraint.none(),
    ),
  );

  static const List<TextSystemPagePreset> builtIn = <TextSystemPagePreset>[
    a4Academic,
    a4FivePages,
    a4Compact,
    a5Academic,
    letterStandard,
    draftReview,
  ];
}
