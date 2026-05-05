import 'source_document_block.dart';

class SourceParseContext {
  const SourceParseContext({required this.source});

  final String source;
}

/// Converts canonical source into visual/source-mapped blocks.
abstract class SourceDocumentParser {
  const SourceDocumentParser();

  ParsedSourceDocument parse(SourceParseContext context);
}
