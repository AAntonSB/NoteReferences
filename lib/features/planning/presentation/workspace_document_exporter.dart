import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class WorkspaceDocumentExporter {
  const WorkspaceDocumentExporter._();

  static Future<String?> exportPlainTextPdf({
    required String title,
    required String body,
    required bool codeLike,
  }) async {
    final directory = await _chooseExportDirectory();
    if (directory == null) return null;
    final path = await _uniquePath(
      directory: directory,
      fileName: _safeFileName(title, extension: 'pdf'),
    );
    final bytes = _SimplePdfBuilder(
      title: title,
      body: body,
      codeLike: codeLike,
    ).build();
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static Future<String?> exportTextFile({
    required String title,
    required String body,
    required String extension,
    required String dialogTitle,
  }) async {
    final directory = await _chooseExportDirectory();
    if (directory == null) return null;
    final path = await _uniquePath(
      directory: directory,
      fileName: _safeFileName(title, extension: extension),
    );
    await File(path).writeAsString(body, flush: true);
    return path;
  }

  static Future<String?> pickPdfAttachment() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Attach exported PDF',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: false,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  static Future<Directory?> _chooseExportDirectory() async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose export folder',
        lockParentWindow: true,
      );
      if (selected != null && selected.trim().isNotEmpty) {
        return Directory(selected);
      }
    } catch (_) {
      // Older file_picker builds can differ by platform/version. Fall back to a
      // deterministic local export folder rather than blocking compilation.
    }

    final fallback = _fallbackExportDirectory();
    await fallback.create(recursive: true);
    return fallback;
  }

  static Directory _fallbackExportDirectory() {
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      final downloads = Directory('${home}${Platform.pathSeparator}Downloads');
      if (downloads.existsSync()) {
        return Directory('${downloads.path}${Platform.pathSeparator}NoteApp exports');
      }
      return Directory('${home}${Platform.pathSeparator}NoteApp exports');
    }
    return Directory('${Directory.current.path}${Platform.pathSeparator}exports');
  }

  static Future<String> _uniquePath({
    required Directory directory,
    required String fileName,
  }) async {
    await directory.create(recursive: true);
    final separator = Platform.pathSeparator;
    final dotIndex = fileName.lastIndexOf('.');
    final base = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
    final extension = dotIndex <= 0 ? '' : fileName.substring(dotIndex);
    var candidate = '${directory.path}$separator$fileName';
    var index = 2;
    while (await File(candidate).exists()) {
      candidate = '${directory.path}$separator$base ($index)$extension';
      index += 1;
    }
    return candidate;
  }

  static String _safeFileName(String title, {required String extension}) {
    final base = title.trim().isEmpty ? 'document' : title.trim();
    final safe = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '${safe.isEmpty ? 'document' : safe}.$extension';
  }
}

class _SimplePdfBuilder {
  _SimplePdfBuilder({
    required this.title,
    required this.body,
    required this.codeLike,
  });

  final String title;
  final String body;
  final bool codeLike;

  static const double _pageWidth = 595.28;
  static const double _pageHeight = 841.89;
  static const double _marginLeft = 64;
  static const double _marginTop = 64;
  static const double _marginBottom = 64;
  static const double _bodyFontSize = 11.2;
  static const double _codeFontSize = 9.6;
  static const double _titleFontSize = 16.5;

  List<int> build() {
    final fontSize = codeLike ? _codeFontSize : _bodyFontSize;
    final lineHeight = codeLike ? 13.2 : 16.0;
    final maxLineWidth = _pageWidth - (_marginLeft * 2);
    final maxChars = math.max(
      24,
      (maxLineWidth / (fontSize * (codeLike ? 0.58 : 0.49))).floor(),
    );
    final lines = <_PdfTextLine>[
      _PdfTextLine(title.trim().isEmpty ? 'Untitled document' : title.trim(), _titleFontSize, true),
      _PdfTextLine('', fontSize, false),
      for (final paragraph in body.replaceAll('\r\n', '\n').split('\n'))
        ..._wrapLine(paragraph, maxChars).map((line) => _PdfTextLine(line, fontSize, false)),
    ];

    final pages = <List<_PdfTextLine>>[];
    var currentPage = <_PdfTextLine>[];
    var usedHeight = 0.0;
    final availableHeight = _pageHeight - _marginTop - _marginBottom;

    for (final line in lines) {
      final height = line.isTitle ? 24.0 : lineHeight;
      if (currentPage.isNotEmpty && usedHeight + height > availableHeight) {
        pages.add(currentPage);
        currentPage = <_PdfTextLine>[];
        usedHeight = 0;
      }
      currentPage.add(line);
      usedHeight += height;
    }
    if (currentPage.isNotEmpty) pages.add(currentPage);
    if (pages.isEmpty) pages.add(const <_PdfTextLine>[]);

    final objects = <String>[];
    final pageObjectIds = <int>[];
    objects.add('<< /Type /Catalog /Pages 2 0 R >>');
    objects.add(''); // pages tree placeholder
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>');

    for (final pageLines in pages) {
      final content = _pageContent(pageLines, lineHeight);
      final contentObjectId = objects.length + 1;
      objects.add('<< /Length ${_pdfBytes(content).length} >>\nstream\n$content\nendstream');
      final pageObjectId = objects.length + 1;
      pageObjectIds.add(pageObjectId);
      objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $_pageWidth $_pageHeight] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents $contentObjectId 0 R >>');
    }

    objects[1] = '<< /Type /Pages /Kids [${pageObjectIds.map((id) => '$id 0 R').join(' ')}] /Count ${pageObjectIds.length} >>';

    final buffer = BytesBuilder(copy: false);
    void writePdf(String value) => buffer.add(_pdfBytes(value));
    writePdf('%PDF-1.4\n%\u00e2\u00e3\u00cf\u00d3\n');
    final offsets = <int>[0];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(buffer.length);
      writePdf('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xrefOffset = buffer.length;
    writePdf('xref\n0 ${objects.length + 1}\n');
    writePdf('0000000000 65535 f \n');
    for (var i = 1; i < offsets.length; i++) {
      writePdf('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
    }
    writePdf('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n');
    return buffer.takeBytes();
  }

  String _pageContent(List<_PdfTextLine> lines, double lineHeight) {
    final buffer = StringBuffer();
    buffer.writeln('BT');
    var y = _pageHeight - _marginTop;
    for (final line in lines) {
      final font = codeLike && !line.isTitle ? 'F2' : 'F1';
      final fontSize = line.fontSize;
      buffer.writeln('/$font $fontSize Tf');
      buffer.writeln('${_num(_marginLeft)} ${_num(y)} Td');
      buffer.writeln('${_hexString(line.text)} Tj');
      y -= line.isTitle ? 24.0 : lineHeight;
      buffer.writeln('1 0 0 1 0 0 Tm');
    }
    buffer.writeln('ET');
    return buffer.toString();
  }

  List<String> _wrapLine(String value, int maxChars) {
    if (value.trim().isEmpty) return [''];
    final words = value.split(RegExp(r'(\s+)')).where((part) => part.isNotEmpty).toList();
    final lines = <String>[];
    final current = StringBuffer();
    for (final word in words) {
      final candidateLength = current.length + word.length;
      if (current.isNotEmpty && candidateLength > maxChars) {
        lines.add(current.toString().trimRight());
        current.clear();
      }
      if (word.length > maxChars) {
        if (current.isNotEmpty) {
          lines.add(current.toString().trimRight());
          current.clear();
        }
        var start = 0;
        while (start < word.length) {
          final end = math.min(start + maxChars, word.length);
          lines.add(word.substring(start, end));
          start = end;
        }
      } else {
        current.write(word);
      }
    }
    if (current.isNotEmpty) lines.add(current.toString().trimRight());
    return lines.isEmpty ? [''] : lines;
  }

  String _hexString(String text) {
    final bytes = _pdfBytes(text.replaceAll('\t', '    '));
    return '<${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}>';
  }

  static List<int> _pdfBytes(String value) {
    final bytes = <int>[];
    for (final codeUnit in value.codeUnits) {
      bytes.add(codeUnit <= 0xff ? codeUnit : 0x3f);
    }
    return bytes;
  }

  String _num(double value) => value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
}

class _PdfTextLine {
  const _PdfTextLine(this.text, this.fontSize, this.isTitle);

  final String text;
  final double fontSize;
  final bool isTitle;
}
