class SidecarRevealNoteRequest {
  final int requestId;
  final String noteId;
  final int? pageNumber;

  const SidecarRevealNoteRequest({
    required this.requestId,
    required this.noteId,
    this.pageNumber,
  });
}
