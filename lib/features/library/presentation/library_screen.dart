import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../infrastructure/database/app_database.dart';
import '../../pdf_reader/presentation/pdf_reader_screen.dart';
import '../data/document_import_service.dart';
import '../data/pdf_metadata_extractor.dart';

enum LibrarySortField {
  name,
  authors,
  addedAt,
  fileLastModifiedAt,
  subject,
}

class LibraryScreen extends StatefulWidget {
  final AppDatabase database;

  const LibraryScreen({
    super.key,
    required this.database,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibrarySortField _sortField = LibrarySortField.addedAt;
  bool _sortAscending = false;

  bool _isDragging = false;
  bool _isImporting = false;

  late final DocumentImportService _importService;

  @override
  void initState() {
    super.initState();

    _importService = DocumentImportService(
      database: widget.database,
      metadataExtractor: PdfMetadataExtractor(),
    );
  }

Future<void> _importPdf() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    allowMultiple: true,
    lockParentWindow: true,
  );

  if (result == null) {
    return;
  }

  final files = result.files
      .where((file) => file.path != null)
      .map((file) => File(file.path!))
      .toList();

  await _importFiles(files);
}

Future<void> _importDroppedItems(List<DropItem> items) async {
  debugPrint('Drop item count: ${items.length}');

  final files = <File>[];

  for (final item in items) {
    final rawPath = item.path;
    final path = _normalizeDroppedPath(rawPath);

    debugPrint('Dropped raw path: $rawPath');
    debugPrint('Dropped normalized path: $path');

    if (!path.toLowerCase().endsWith('.pdf')) {
      debugPrint('Skipped non-PDF: $path');
      continue;
    }

    final file = File(path);
    final exists = await file.exists();

    debugPrint('Dropped file exists: $exists');

    if (!exists) {
      debugPrint('Skipped missing file: $path');
      continue;
    }

    final type = await FileSystemEntity.type(path);
    debugPrint('Dropped entity type: $type');

    if (type != FileSystemEntityType.file) {
      debugPrint('Skipped non-file entity: $path');
      continue;
    }

    files.add(file);
  }

  debugPrint('Valid dropped PDF count: ${files.length}');

  await _importFiles(files);
}

  String _normalizeDroppedPath(String rawPath) {
  var path = rawPath.trim();

  if (path.startsWith('"') && path.endsWith('"')) {
    path = path.substring(1, path.length - 1);
  }

  if (path.startsWith('file://')) {
    return Uri.parse(path).toFilePath(windows: Platform.isWindows);
  }

  return Uri.decodeFull(path);
}

 Future<void> _importFiles(List<File> files) async {
  debugPrint('Import requested for ${files.length} file(s).');

  final pdfFiles = files
      .where((file) => file.path.toLowerCase().endsWith('.pdf'))
      .toList();

  debugPrint('PDF files after filtering: ${pdfFiles.length}');

  if (pdfFiles.isEmpty) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No PDF files found.'),
      ),
    );

    return;
  }

  setState(() {
    _isImporting = true;
  });

  var importedCount = 0;

  try {
    for (final file in pdfFiles) {
      debugPrint('Importing PDF: ${file.path}');

      final document = await _importService.importPdf(file);

      debugPrint(
        'Imported document: ${document.documentId} | ${document.name}',
      );

      final allDocuments = await widget.database.getAllDocuments();
      debugPrint('Documents in database after import: ${allDocuments.length}');

      importedCount++;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          importedCount == 1
              ? 'Imported 1 PDF.'
              : 'Imported $importedCount PDFs.',
        ),
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('Import failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Import failed: $error'),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isImporting = false;
      });
    }
  }
}

  List<PdfDocument> _sortDocuments(List<PdfDocument> documents) {
    final sorted = [...documents];

    int compareNullableStrings(String? a, String? b) {
      final left = a?.toLowerCase() ?? '';
      final right = b?.toLowerCase() ?? '';
      return left.compareTo(right);
    }

    int comparison(PdfDocument a, PdfDocument b) {
      switch (_sortField) {
        case LibrarySortField.name:
          return compareNullableStrings(a.name, b.name);
        case LibrarySortField.authors:
          return compareNullableStrings(a.authors, b.authors);
        case LibrarySortField.addedAt:
          return a.addedAt.compareTo(b.addedAt);
        case LibrarySortField.fileLastModifiedAt:
          final left = a.fileLastModifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.fileLastModifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return left.compareTo(right);
        case LibrarySortField.subject:
          return compareNullableStrings(a.subject, b.subject);
      }
    }

    sorted.sort((a, b) {
      final result = comparison(a, b);
      return _sortAscending ? result : -result;
    });

    return sorted;
  }

  void _setSort(LibrarySortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
    });
  }

  int? get _sortColumnIndex {
    switch (_sortField) {
      case LibrarySortField.name:
        return 0;
      case LibrarySortField.authors:
        return 1;
      case LibrarySortField.addedAt:
        return 2;
      case LibrarySortField.fileLastModifiedAt:
        return 3;
      case LibrarySortField.subject:
        return 4;
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '';

    final date = value.toLocal();

    String two(int number) => number.toString().padLeft(2, '0');

    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  void _openDocument(PdfDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfReaderScreen(
          documentId: document.documentId,
          filePath: document.filePath,
          title: document.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Library'),
actions: [
  IconButton(
    tooltip: 'Import PDF',
    onPressed: _isImporting ? null : _importPdf,
    icon: const Icon(Icons.upload_file),
  ),
],
      ),
body: DropTarget(
  onDragEntered: (_) {
    setState(() {
      _isDragging = true;
    });
  },
  onDragExited: (_) {
    setState(() {
      _isDragging = false;
    });
  },
  onDragDone: (details) async {
    setState(() {
      _isDragging = false;
    });

   debugPrint(
    'Dropped files: ${details.files.map((file) => file.path).toList()}',
    );

    await _importDroppedItems(details.files);
  },
child: SizedBox.expand(
  child: Stack(
    children: [
      StreamBuilder<List<PdfDocument>>(
        stream: widget.database.watchAllDocuments(),
        builder: (context, snapshot) {
          final documents = _sortDocuments(snapshot.data ?? []);

          if (documents.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: _isImporting ? null : _importPdf,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import your first PDF'),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: _sortColumnIndex,
                sortAscending: _sortAscending,
                columns: [
                  DataColumn(
                    label: const Text('Name'),
                    onSort: (_, __) => _setSort(LibrarySortField.name),
                  ),
                  DataColumn(
                    label: const Text('Authors'),
                    onSort: (_, __) => _setSort(LibrarySortField.authors),
                  ),
                  DataColumn(
                    label: const Text('Added'),
                    onSort: (_, __) => _setSort(LibrarySortField.addedAt),
                  ),
                  DataColumn(
                    label: const Text('Last modified'),
                    onSort: (_, __) =>
                        _setSort(LibrarySortField.fileLastModifiedAt),
                  ),
                  DataColumn(
                    label: const Text('Subject'),
                    onSort: (_, __) => _setSort(LibrarySortField.subject),
                  ),
                ],
                rows: [
                  for (final document in documents)
                    DataRow(
                      onSelectChanged: (_) => _openDocument(document),
                      cells: [
                        DataCell(Text(document.name)),
                        DataCell(Text(document.authors ?? '')),
                        DataCell(Text(_formatDateTime(document.addedAt))),
                        DataCell(
                          Text(_formatDateTime(document.fileLastModifiedAt)),
                        ),
                        DataCell(Text(document.subject ?? '')),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),

      if (_isDragging)
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.35),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Drop PDFs to import',
                        style: TextStyle(fontSize: 22),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

      if (_isImporting)
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: LinearProgressIndicator(),
        ),
    ],
  ),
),
),
    );
  }
}