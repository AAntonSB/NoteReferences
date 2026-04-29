import '../../../notes/data/note_repository.dart';
import 'note_creation_type.dart';

class SidecarExternalCreateRequest {
  final int requestId;
  final NoteCreationType creationType;
  final int pageNumber;
  final double normalizedY;
  final String? selectedText;
  final List<PdfSourceRect> sourceRects;

  const SidecarExternalCreateRequest({
    required this.requestId,
    required this.creationType,
    required this.pageNumber,
    required this.normalizedY,
    required this.selectedText,
    required this.sourceRects,
  });
}