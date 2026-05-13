import 'package:flutter/widgets.dart';

import '../core/text_system_block.dart';
import '../page/text_system_page_setup.dart';

enum TextSystemStyleRole {
  paragraph,
  heading,
  quote,
  code,
  listParagraph,
  todo,
  footnoteText,
  headerText,
  footerText,
  caption,
  bibliography,
  structural,
  custom,
}

enum TextSystemParagraphAlignment {
  left,
  center,
  right,
  justify,
}

enum TextSystemNumberingBehavior {
  none,
  bullet,
  ordered,
  checkbox,
}

class TextSystemTextStyleSpec {
  const TextSystemTextStyleSpec({
    required this.fontFamily,
    required this.fontSize,
    this.fontWeight = FontWeight.w400,
    this.fontStyle = FontStyle.normal,
    required this.lineHeight,
    this.color,
    this.backgroundColor,
  });

  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final double lineHeight;
  final Color? color;
  final Color? backgroundColor;

  TextStyle toTextStyle() {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: lineHeight,
      color: color,
      backgroundColor: backgroundColor,
    );
  }

  TextSystemTextStyleSpec copyWith({
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? lineHeight,
    Color? color,
    Color? backgroundColor,
  }) {
    return TextSystemTextStyleSpec(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      lineHeight: lineHeight ?? this.lineHeight,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'fontWeight': fontWeight.value,
      'fontStyle': fontStyle == FontStyle.italic ? 'italic' : 'normal',
      'lineHeight': lineHeight,
      'color': color?.value,
      'backgroundColor': backgroundColor?.value,
    };
  }
}

class TextSystemParagraphStyleSpec {
  const TextSystemParagraphStyleSpec({
    required this.id,
    required this.name,
    required this.role,
    required this.textStyle,
    this.headingLevel,
    this.spacingBefore = 0,
    this.spacingAfter = 0,
    this.indentStart = 0,
    this.indentEnd = 0,
    this.firstLineIndent = 0,
    this.markerGutter = 0,
    this.alignment = TextSystemParagraphAlignment.left,
    this.numbering = TextSystemNumberingBehavior.none,
    this.keepWithNext = false,
    this.allowSplitAcrossPages = true,
  });

  final String id;
  final String name;
  final TextSystemStyleRole role;
  final TextSystemTextStyleSpec textStyle;
  final int? headingLevel;
  final double spacingBefore;
  final double spacingAfter;
  final double indentStart;
  final double indentEnd;
  final double firstLineIndent;
  final double markerGutter;
  final TextSystemParagraphAlignment alignment;
  final TextSystemNumberingBehavior numbering;
  final bool keepWithNext;
  final bool allowSplitAcrossPages;

  TextStyle toTextStyle() => textStyle.toTextStyle();

  TextSystemParagraphStyleSpec copyWith({
    String? id,
    String? name,
    TextSystemStyleRole? role,
    TextSystemTextStyleSpec? textStyle,
    int? headingLevel,
    double? spacingBefore,
    double? spacingAfter,
    double? indentStart,
    double? indentEnd,
    double? firstLineIndent,
    double? markerGutter,
    TextSystemParagraphAlignment? alignment,
    TextSystemNumberingBehavior? numbering,
    bool? keepWithNext,
    bool? allowSplitAcrossPages,
  }) {
    return TextSystemParagraphStyleSpec(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      textStyle: textStyle ?? this.textStyle,
      headingLevel: headingLevel ?? this.headingLevel,
      spacingBefore: spacingBefore ?? this.spacingBefore,
      spacingAfter: spacingAfter ?? this.spacingAfter,
      indentStart: indentStart ?? this.indentStart,
      indentEnd: indentEnd ?? this.indentEnd,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      markerGutter: markerGutter ?? this.markerGutter,
      alignment: alignment ?? this.alignment,
      numbering: numbering ?? this.numbering,
      keepWithNext: keepWithNext ?? this.keepWithNext,
      allowSplitAcrossPages: allowSplitAcrossPages ?? this.allowSplitAcrossPages,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'role': role.name,
      'headingLevel': headingLevel,
      'textStyle': textStyle.toJson(),
      'spacingBefore': spacingBefore,
      'spacingAfter': spacingAfter,
      'indentStart': indentStart,
      'indentEnd': indentEnd,
      'firstLineIndent': firstLineIndent,
      'markerGutter': markerGutter,
      'alignment': alignment.name,
      'numbering': numbering.name,
      'keepWithNext': keepWithNext,
      'allowSplitAcrossPages': allowSplitAcrossPages,
    };
  }
}

class TextSystemDocumentStyleSheet {
  const TextSystemDocumentStyleSheet({
    required this.id,
    required this.name,
    required this.styles,
    this.defaultStyleId = paragraph,
    this.inlineCodeFontFamily = 'Consolas',
    this.footnoteReferenceScale = 0.66,
  });

  static const String paragraph = 'paragraph';
  static const String heading1 = 'heading-1';
  static const String heading2 = 'heading-2';
  static const String heading3 = 'heading-3';
  static const String quote = 'quote';
  static const String code = 'code';
  static const String listParagraph = 'list-paragraph';
  static const String numberedList = 'numbered-list';
  static const String todo = 'todo';
  static const String footnoteText = 'footnote-text';
  static const String headerText = 'header-text';
  static const String footerText = 'footer-text';
  static const String caption = 'caption';
  static const String bibliography = 'bibliography';
  static const String structural = 'structural-divider';
  static const String custom = 'custom';

  final String id;
  final String name;
  final Map<String, TextSystemParagraphStyleSpec> styles;
  final String defaultStyleId;
  final String inlineCodeFontFamily;
  final double footnoteReferenceScale;

  TextSystemParagraphStyleSpec get defaultStyle => styles[defaultStyleId] ?? styles.values.first;

  TextSystemParagraphStyleSpec styleForId(String id) {
    return styles[id] ?? defaultStyle;
  }

  TextSystemParagraphStyleSpec styleForBlock(TextSystemBlock block) {
    if (block.metadata['styleId'] case final String explicitStyleId) {
      return styleForId(explicitStyleId);
    }

    return switch (block.type) {
      TextSystemBlockType.heading => styleForId('heading-${(block.level ?? 1).clamp(1, 3).toInt()}'),
      TextSystemBlockType.paragraph => styleForId(paragraph),
      TextSystemBlockType.listItem => styleForId(listParagraph),
      TextSystemBlockType.todo => styleForId(todo),
      TextSystemBlockType.quote => styleForId(quote),
      TextSystemBlockType.code => styleForId(code),
      TextSystemBlockType.divider => styleForId(structural),
      TextSystemBlockType.custom => block.metadata['kind'] == 'footnote'
          ? styleForId(footnoteText)
          : styleForId(custom),
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'defaultStyleId': defaultStyleId,
      'inlineCodeFontFamily': inlineCodeFontFamily,
      'footnoteReferenceScale': footnoteReferenceScale,
      'styles': <String, Object?>{
        for (final entry in styles.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  static TextSystemDocumentStyleSheet academicDefault({
    required TextSystemPageSetup pageSetup,
  }) {
    final baseSize = pageSetup.defaultFontSize;
    final baseLineHeight = pageSetup.lineSpacing;
    const bodyFont = 'Times New Roman';
    const codeFont = 'Consolas';

    TextSystemTextStyleSpec body({
      double sizeDelta = 0,
      FontWeight weight = FontWeight.w400,
      FontStyle fontStyle = FontStyle.normal,
      double? lineHeight,
      String fontFamily = bodyFont,
    }) {
      return TextSystemTextStyleSpec(
        fontFamily: fontFamily,
        fontSize: baseSize + sizeDelta,
        fontWeight: weight,
        fontStyle: fontStyle,
        lineHeight: lineHeight ?? baseLineHeight,
      );
    }

    final paragraphStyle = TextSystemParagraphStyleSpec(
      id: paragraph,
      name: 'Paragraph',
      role: TextSystemStyleRole.paragraph,
      textStyle: body(),
      spacingAfter: baseSize * 0.52,
    );

    final styles = <String, TextSystemParagraphStyleSpec>{
      paragraph: paragraphStyle,
      heading1: TextSystemParagraphStyleSpec(
        id: heading1,
        name: 'Heading 1',
        role: TextSystemStyleRole.heading,
        headingLevel: 1,
        textStyle: body(
          sizeDelta: 6,
          weight: FontWeight.w700,
          lineHeight: baseLineHeight * 0.92 < 1.08 ? 1.08 : baseLineHeight * 0.92,
        ),
        spacingBefore: baseSize * 0.70,
        spacingAfter: baseSize * 0.74,
        keepWithNext: true,
      ),
      heading2: TextSystemParagraphStyleSpec(
        id: heading2,
        name: 'Heading 2',
        role: TextSystemStyleRole.heading,
        headingLevel: 2,
        textStyle: body(
          sizeDelta: 4,
          weight: FontWeight.w700,
          lineHeight: baseLineHeight * 0.92 < 1.08 ? 1.08 : baseLineHeight * 0.92,
        ),
        spacingBefore: baseSize * 0.62,
        spacingAfter: baseSize * 0.64,
        keepWithNext: true,
      ),
      heading3: TextSystemParagraphStyleSpec(
        id: heading3,
        name: 'Heading 3',
        role: TextSystemStyleRole.heading,
        headingLevel: 3,
        textStyle: body(
          sizeDelta: 2,
          weight: FontWeight.w700,
          lineHeight: baseLineHeight * 0.92 < 1.08 ? 1.08 : baseLineHeight * 0.92,
        ),
        spacingBefore: baseSize * 0.55,
        spacingAfter: baseSize * 0.58,
        keepWithNext: true,
      ),
      quote: TextSystemParagraphStyleSpec(
        id: quote,
        name: 'Quote',
        role: TextSystemStyleRole.quote,
        textStyle: body(fontStyle: FontStyle.italic),
        spacingAfter: baseSize * 0.52,
        indentStart: baseSize * 1.35,
        indentEnd: baseSize * 0.80,
      ),
      code: TextSystemParagraphStyleSpec(
        id: code,
        name: 'Code',
        role: TextSystemStyleRole.code,
        textStyle: body(
          sizeDelta: -(baseSize * 0.08),
          lineHeight: 1.28,
          fontFamily: codeFont,
        ),
        spacingAfter: baseSize * 0.36,
      ),
      listParagraph: TextSystemParagraphStyleSpec(
        id: listParagraph,
        name: 'Bullet list',
        role: TextSystemStyleRole.listParagraph,
        textStyle: body(),
        spacingAfter: baseSize * 0.13,
        markerGutter: baseSize * 2.1 < 24.0 ? 24.0 : baseSize * 2.1,
        numbering: TextSystemNumberingBehavior.bullet,
      ),
      numberedList: TextSystemParagraphStyleSpec(
        id: numberedList,
        name: 'Numbered list',
        role: TextSystemStyleRole.listParagraph,
        textStyle: body(),
        spacingAfter: baseSize * 0.13,
        markerGutter: baseSize * 2.1 < 24.0 ? 24.0 : baseSize * 2.1,
        numbering: TextSystemNumberingBehavior.ordered,
      ),
      todo: TextSystemParagraphStyleSpec(
        id: todo,
        name: 'Todo',
        role: TextSystemStyleRole.todo,
        textStyle: body(),
        spacingAfter: baseSize * 0.13,
        markerGutter: baseSize * 2.1 < 24.0 ? 24.0 : baseSize * 2.1,
        numbering: TextSystemNumberingBehavior.checkbox,
      ),
      footnoteText: TextSystemParagraphStyleSpec(
        id: footnoteText,
        name: 'Footnote text',
        role: TextSystemStyleRole.footnoteText,
        textStyle: body(sizeDelta: -2, lineHeight: 1.16),
        spacingAfter: baseSize * 0.18,
      ),
      headerText: TextSystemParagraphStyleSpec(
        id: headerText,
        name: 'Header text',
        role: TextSystemStyleRole.headerText,
        textStyle: body(sizeDelta: -3, lineHeight: 1.0),
      ),
      footerText: TextSystemParagraphStyleSpec(
        id: footerText,
        name: 'Footer text',
        role: TextSystemStyleRole.footerText,
        textStyle: body(sizeDelta: -3, lineHeight: 1.0),
      ),
      caption: TextSystemParagraphStyleSpec(
        id: caption,
        name: 'Caption',
        role: TextSystemStyleRole.caption,
        textStyle: body(sizeDelta: -1, fontStyle: FontStyle.italic, lineHeight: 1.2),
        spacingAfter: baseSize * 0.32,
      ),
      bibliography: TextSystemParagraphStyleSpec(
        id: bibliography,
        name: 'Bibliography',
        role: TextSystemStyleRole.bibliography,
        textStyle: body(lineHeight: 1.25),
        spacingAfter: baseSize * 0.36,
        indentStart: baseSize * 2.0,
        firstLineIndent: -(baseSize * 2.0),
      ),
      structural: TextSystemParagraphStyleSpec(
        id: structural,
        name: 'Structural divider',
        role: TextSystemStyleRole.structural,
        textStyle: body(sizeDelta: -2, lineHeight: 1.0),
        spacingAfter: baseSize * 0.40,
      ),
      custom: paragraphStyle.copyWith(
        id: custom,
        name: 'Custom',
        role: TextSystemStyleRole.custom,
      ),
    };

    return TextSystemDocumentStyleSheet(
      id: 'academic-default',
      name: 'Academic default',
      styles: Map<String, TextSystemParagraphStyleSpec>.unmodifiable(styles),
      defaultStyleId: paragraph,
      inlineCodeFontFamily: codeFont,
      footnoteReferenceScale: 0.66,
    );
  }
}
