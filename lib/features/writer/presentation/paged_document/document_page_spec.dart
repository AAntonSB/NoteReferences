import 'package:flutter/material.dart';

/// Physical page presets expressed in PDF points.
///
/// 1 point = 1/72 inch. This keeps the editor close to print/PDF
/// expectations instead of arbitrary screen pixels.
enum DocumentPageSize {
  a4,
  letter,
  a5,
}

extension DocumentPageSizeLabel on DocumentPageSize {
  String get label {
    switch (this) {
      case DocumentPageSize.a4:
        return 'A4';
      case DocumentPageSize.letter:
        return 'US Letter';
      case DocumentPageSize.a5:
        return 'A5';
    }
  }

  double get widthPt {
    switch (this) {
      case DocumentPageSize.a4:
        return 595.276;
      case DocumentPageSize.letter:
        return 612.0;
      case DocumentPageSize.a5:
        return 419.528;
    }
  }

  double get heightPt {
    switch (this) {
      case DocumentPageSize.a4:
        return 841.89;
      case DocumentPageSize.letter:
        return 792.0;
      case DocumentPageSize.a5:
        return 595.276;
    }
  }
}

/// Academic typography presets.
///
/// These are intentionally conservative. They are not meant to be a visual
/// theme; they are layout contracts for academic writing.
enum AcademicTypographyPreset {
  thesis,
  paper,
  draft,
}

extension AcademicTypographyPresetLabel on AcademicTypographyPreset {
  String get label {
    switch (this) {
      case AcademicTypographyPreset.thesis:
        return 'Thesis';
      case AcademicTypographyPreset.paper:
        return 'Paper';
      case AcademicTypographyPreset.draft:
        return 'Draft';
    }
  }
}

@immutable
class AcademicPageStyle {
  const AcademicPageStyle({
    required this.pageSize,
    required this.typographyPreset,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.margins,
    required this.bodyStyle,
    required this.heading1Style,
    required this.heading2Style,
    required this.captionStyle,
    this.pageGap = 28.0,
    this.workspacePadding = const EdgeInsets.symmetric(
      horizontal: 48.0,
      vertical: 32.0,
    ),
    this.pageColor = Colors.white,
    this.workspaceColor = const Color(0xFFF3F1EC),
    this.pageBorderColor = const Color(0x1F000000),
    this.showMarginGuides = false,
  });

  factory AcademicPageStyle.from({
    DocumentPageSize pageSize = DocumentPageSize.a4,
    AcademicTypographyPreset typographyPreset = AcademicTypographyPreset.thesis,
    bool showMarginGuides = false,
  }) {
    final margins = _marginsFor(typographyPreset);
    final body = _bodyStyleFor(typographyPreset);

    return AcademicPageStyle(
      pageSize: pageSize,
      typographyPreset: typographyPreset,
      pageWidthPt: pageSize.widthPt,
      pageHeightPt: pageSize.heightPt,
      margins: margins,
      bodyStyle: body,
      heading1Style: body.copyWith(
        fontSize: body.fontSize! + 2,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      heading2Style: body.copyWith(
        fontSize: body.fontSize,
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
        height: 1.35,
      ),
      captionStyle: body.copyWith(
        fontSize: body.fontSize! - 1,
        height: 1.25,
        color: const Color(0xFF55514A),
      ),
      showMarginGuides: showMarginGuides,
    );
  }

  final DocumentPageSize pageSize;
  final AcademicTypographyPreset typographyPreset;

  final double pageWidthPt;
  final double pageHeightPt;
  final EdgeInsets margins;

  final TextStyle bodyStyle;
  final TextStyle heading1Style;
  final TextStyle heading2Style;
  final TextStyle captionStyle;

  final double pageGap;
  final EdgeInsets workspacePadding;

  final Color pageColor;
  final Color workspaceColor;
  final Color pageBorderColor;
  final bool showMarginGuides;

  double get contentWidthPt => pageWidthPt - margins.horizontal;
  double get contentHeightPt => pageHeightPt - margins.vertical;

  AcademicPageStyle copyWith({
    DocumentPageSize? pageSize,
    AcademicTypographyPreset? typographyPreset,
    EdgeInsets? margins,
    TextStyle? bodyStyle,
    TextStyle? heading1Style,
    TextStyle? heading2Style,
    TextStyle? captionStyle,
    double? pageGap,
    EdgeInsets? workspacePadding,
    Color? pageColor,
    Color? workspaceColor,
    Color? pageBorderColor,
    bool? showMarginGuides,
  }) {
    final resolvedPageSize = pageSize ?? this.pageSize;
    final resolvedTypographyPreset =
        typographyPreset ?? this.typographyPreset;

    return AcademicPageStyle(
      pageSize: resolvedPageSize,
      typographyPreset: resolvedTypographyPreset,
      pageWidthPt: resolvedPageSize.widthPt,
      pageHeightPt: resolvedPageSize.heightPt,
      margins: margins ?? this.margins,
      bodyStyle: bodyStyle ?? this.bodyStyle,
      heading1Style: heading1Style ?? this.heading1Style,
      heading2Style: heading2Style ?? this.heading2Style,
      captionStyle: captionStyle ?? this.captionStyle,
      pageGap: pageGap ?? this.pageGap,
      workspacePadding: workspacePadding ?? this.workspacePadding,
      pageColor: pageColor ?? this.pageColor,
      workspaceColor: workspaceColor ?? this.workspaceColor,
      pageBorderColor: pageBorderColor ?? this.pageBorderColor,
      showMarginGuides: showMarginGuides ?? this.showMarginGuides,
    );
  }

  static EdgeInsets _marginsFor(AcademicTypographyPreset preset) {
    switch (preset) {
      case AcademicTypographyPreset.thesis:
        // Standard 1 inch margins.
        return const EdgeInsets.fromLTRB(72, 72, 72, 72);
      case AcademicTypographyPreset.paper:
        // Slightly tighter bottom margin, still academic.
        return const EdgeInsets.fromLTRB(72, 72, 72, 54);
      case AcademicTypographyPreset.draft:
        // More breathing room for comments/revision.
        return const EdgeInsets.fromLTRB(72, 78, 72, 78);
    }
  }

  static TextStyle _bodyStyleFor(AcademicTypographyPreset preset) {
    const base = TextStyle(
      fontFamily: 'Times New Roman',
      fontFamilyFallback: <String>[
        'Georgia',
        'Cambria',
        'Times',
      ],
      color: Color(0xFF171512),
      letterSpacing: 0,
    );

    switch (preset) {
      case AcademicTypographyPreset.thesis:
        return base.copyWith(
          fontSize: 12,
          height: 1.5,
          fontWeight: FontWeight.w400,
        );
      case AcademicTypographyPreset.paper:
        return base.copyWith(
          fontSize: 11,
          height: 1.35,
          fontWeight: FontWeight.w400,
        );
      case AcademicTypographyPreset.draft:
        return base.copyWith(
          fontSize: 12,
          height: 1.7,
          fontWeight: FontWeight.w400,
        );
    }
  }
}
