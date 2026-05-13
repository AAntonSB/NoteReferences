import 'package:flutter/widgets.dart';

enum TextSystemPageNumberPosition {
  topRight,
  bottomCenter,
  bottomRight;

  String get label {
    return switch (this) {
      TextSystemPageNumberPosition.topRight => 'Top right',
      TextSystemPageNumberPosition.bottomCenter => 'Bottom center',
      TextSystemPageNumberPosition.bottomRight => 'Bottom right',
    };
  }

  String get shortLabel {
    return switch (this) {
      TextSystemPageNumberPosition.topRight => 'top right',
      TextSystemPageNumberPosition.bottomCenter => 'bottom center',
      TextSystemPageNumberPosition.bottomRight => 'bottom right',
    };
  }
}

enum TextSystemPageHeaderMode {
  none,
  documentTitle;

  String get label {
    return switch (this) {
      TextSystemPageHeaderMode.none => 'No header',
      TextSystemPageHeaderMode.documentTitle => 'Document title',
    };
  }
}

enum TextSystemHeaderFooterZoneKind {
  header,
  footer;

  String get label {
    return switch (this) {
      TextSystemHeaderFooterZoneKind.header => 'Header',
      TextSystemHeaderFooterZoneKind.footer => 'Footer',
    };
  }
}

@immutable
class TextSystemPageNumbering {
  const TextSystemPageNumbering({
    required this.enabled,
    required this.position,
    required this.startAt,
    required this.showOnFirstPage,
  });

  const TextSystemPageNumbering.defaults()
      : enabled = false,
        position = TextSystemPageNumberPosition.bottomCenter,
        startAt = 1,
        showOnFirstPage = true;

  final bool enabled;
  final TextSystemPageNumberPosition position;
  final int startAt;
  final bool showOnFirstPage;

  bool visibleOnPage(int physicalPageNumber) {
    if (!enabled) return false;
    if (physicalPageNumber <= 1 && !showOnFirstPage) return false;
    return true;
  }

  int numberForPage(int physicalPageNumber) {
    return startAt + physicalPageNumber - 1;
  }

  String labelForPage(int physicalPageNumber) {
    return 'Page ${numberForPage(physicalPageNumber)}';
  }

  TextSystemPageNumbering copyWith({
    bool? enabled,
    TextSystemPageNumberPosition? position,
    int? startAt,
    bool? showOnFirstPage,
  }) {
    return TextSystemPageNumbering(
      enabled: enabled ?? this.enabled,
      position: position ?? this.position,
      startAt: startAt ?? this.startAt,
      showOnFirstPage: showOnFirstPage ?? this.showOnFirstPage,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'position': position.name,
      'startAt': startAt,
      'showOnFirstPage': showOnFirstPage,
    };
  }
}

@immutable
class TextSystemHeaderFooterZone {
  const TextSystemHeaderFooterZone({
    required this.enabled,
    required this.text,
  });

  const TextSystemHeaderFooterZone.empty()
      : enabled = true,
        text = '';

  const TextSystemHeaderFooterZone.pageNumberFooter()
      : enabled = true,
        text = 'Page {{pageNumber}}';

  final bool enabled;
  final String text;

  bool get hasContent => text.trim().isNotEmpty;

  TextSystemHeaderFooterZone copyWith({
    bool? enabled,
    String? text,
  }) {
    return TextSystemHeaderFooterZone(
      enabled: enabled ?? this.enabled,
      text: text ?? this.text,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'text': text,
    };
  }
}

@immutable
class TextSystemHeaderFooterSettings {
  const TextSystemHeaderFooterSettings({
    required this.enabled,
    required this.differentFirstPage,
    required this.primaryHeader,
    required this.primaryFooter,
    required this.firstPageHeader,
    required this.firstPageFooter,
  });

  const TextSystemHeaderFooterSettings.defaults()
      : enabled = true,
        differentFirstPage = false,
        primaryHeader = const TextSystemHeaderFooterZone.empty(),
        primaryFooter = const TextSystemHeaderFooterZone.pageNumberFooter(),
        firstPageHeader = const TextSystemHeaderFooterZone.empty(),
        firstPageFooter = const TextSystemHeaderFooterZone.empty();

  final bool enabled;
  final bool differentFirstPage;
  final TextSystemHeaderFooterZone primaryHeader;
  final TextSystemHeaderFooterZone primaryFooter;
  final TextSystemHeaderFooterZone firstPageHeader;
  final TextSystemHeaderFooterZone firstPageFooter;

  TextSystemHeaderFooterZone zoneFor({
    required TextSystemHeaderFooterZoneKind kind,
    required int physicalPageNumber,
  }) {
    final useFirstPage = differentFirstPage && physicalPageNumber == 1;
    return switch ((kind, useFirstPage)) {
      (TextSystemHeaderFooterZoneKind.header, true) => firstPageHeader,
      (TextSystemHeaderFooterZoneKind.footer, true) => firstPageFooter,
      (TextSystemHeaderFooterZoneKind.header, false) => primaryHeader,
      (TextSystemHeaderFooterZoneKind.footer, false) => primaryFooter,
    };
  }

  TextSystemHeaderFooterSettings updateZone({
    required TextSystemHeaderFooterZoneKind kind,
    required int physicalPageNumber,
    required TextSystemHeaderFooterZone zone,
  }) {
    final useFirstPage = differentFirstPage && physicalPageNumber == 1;
    return switch ((kind, useFirstPage)) {
      (TextSystemHeaderFooterZoneKind.header, true) => copyWith(firstPageHeader: zone),
      (TextSystemHeaderFooterZoneKind.footer, true) => copyWith(firstPageFooter: zone),
      (TextSystemHeaderFooterZoneKind.header, false) => copyWith(primaryHeader: zone),
      (TextSystemHeaderFooterZoneKind.footer, false) => copyWith(primaryFooter: zone),
    };
  }

  TextSystemHeaderFooterSettings copyWith({
    bool? enabled,
    bool? differentFirstPage,
    TextSystemHeaderFooterZone? primaryHeader,
    TextSystemHeaderFooterZone? primaryFooter,
    TextSystemHeaderFooterZone? firstPageHeader,
    TextSystemHeaderFooterZone? firstPageFooter,
  }) {
    return TextSystemHeaderFooterSettings(
      enabled: enabled ?? this.enabled,
      differentFirstPage: differentFirstPage ?? this.differentFirstPage,
      primaryHeader: primaryHeader ?? this.primaryHeader,
      primaryFooter: primaryFooter ?? this.primaryFooter,
      firstPageHeader: firstPageHeader ?? this.firstPageHeader,
      firstPageFooter: firstPageFooter ?? this.firstPageFooter,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'differentFirstPage': differentFirstPage,
      'primaryHeader': primaryHeader.toJson(),
      'primaryFooter': primaryFooter.toJson(),
      'firstPageHeader': firstPageHeader.toJson(),
      'firstPageFooter': firstPageFooter.toJson(),
    };
  }
}

@immutable
class TextSystemPageFurniture {
  const TextSystemPageFurniture({
    required this.pageNumbers,
    required this.headerMode,
    required this.headerFooter,
  });

  const TextSystemPageFurniture.defaults()
      : pageNumbers = const TextSystemPageNumbering.defaults(),
        headerMode = TextSystemPageHeaderMode.none,
        headerFooter = const TextSystemHeaderFooterSettings.defaults();

  final TextSystemPageNumbering pageNumbers;
  final TextSystemPageHeaderMode headerMode;
  final TextSystemHeaderFooterSettings headerFooter;

  bool get hasHeader => headerMode != TextSystemPageHeaderMode.none || headerFooter.primaryHeader.hasContent;
  bool get hasPageNumbers => pageNumbers.enabled || headerFooter.primaryFooter.text.contains('{{pageNumber}}');

  String get shortLabel {
    final parts = <String>[
      headerFooter.enabled ? 'editable H/F' : 'fixed chrome',
      headerFooter.differentFirstPage ? 'different first page' : 'same first page',
      pageNumbers.enabled ? 'legacy numbers ${pageNumbers.position.shortLabel}' : 'token numbers',
    ];
    return parts.join(' · ');
  }

  TextSystemPageFurniture copyWith({
    TextSystemPageNumbering? pageNumbers,
    TextSystemPageHeaderMode? headerMode,
    TextSystemHeaderFooterSettings? headerFooter,
  }) {
    return TextSystemPageFurniture(
      pageNumbers: pageNumbers ?? this.pageNumbers,
      headerMode: headerMode ?? this.headerMode,
      headerFooter: headerFooter ?? this.headerFooter,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'headerMode': headerMode.name,
      'pageNumbers': pageNumbers.toJson(),
      'headerFooter': headerFooter.toJson(),
      'shortLabel': shortLabel,
    };
  }
}
