import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../latex/latex_compile_service.dart';

class LatexCompileOutputPane extends StatelessWidget {
  const LatexCompileOutputPane({
    super.key,
    required this.result,
    required this.isCompiling,
    required this.onCompile,
  });

  final SourceLatexCompileResult? result;
  final bool isCompiling;
  final VoidCallback onCompile;

  @override
  Widget build(BuildContext context) {
    final pdfPath = result?.pdfPath;
    if (result?.success == true && pdfPath != null) {
      return _CompiledPdfView(
        result: result!,
        pdfPath: pdfPath,
        isCompiling: isCompiling,
        onCompile: onCompile,
      );
    }

    return LatexCompileLogPane(
      result: result,
      isCompiling: isCompiling,
      onCompile: onCompile,
    );
  }
}

class _CompiledPdfView extends StatelessWidget {
  const _CompiledPdfView({
    required this.result,
    required this.pdfPath,
    required this.isCompiling,
    required this.onCompile,
  });

  final SourceLatexCompileResult result;
  final String pdfPath;
  final bool isCompiling;
  final VoidCallback onCompile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusParts = [
      if (result.compiler != null) result.compiler!,
      if (result.durationLabel.isNotEmpty) result.durationLabel,
      pdfPath,
    ];

    return Column(
      children: [
        Material(
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: isCompiling ? null : onCompile,
                  icon: isCompiling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(isCompiling ? 'Compiling' : 'Recompile'),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: pdfrx.PdfViewer.file(
            pdfPath,
            key: ValueKey(pdfPath),
          ),
        ),
      ],
    );
  }
}

class LatexCompileLogPane extends StatelessWidget {
  const LatexCompileLogPane({
    super.key,
    required this.result,
    required this.isCompiling,
    required this.onCompile,
  });

  final SourceLatexCompileResult? result;
  final bool isCompiling;
  final VoidCallback onCompile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final log = result?.log;
    final failed = result != null && result?.success != true;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Card(
          elevation: 0,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  failed ? Icons.error_outline_rounded : Icons.picture_as_pdf_outlined,
                  size: 34,
                  color: failed ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  isCompiling
                      ? 'Compiling LaTeX…'
                      : failed
                          ? 'LaTeX did not compile'
                          : 'No compiled PDF yet',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  isCompiling
                      ? 'The editor keeps your current view while the PDF is rebuilt.'
                      : 'Compile the canonical LaTeX source to render the output pane.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: isCompiling ? null : onCompile,
                  icon: isCompiling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(isCompiling ? 'Compiling…' : 'Compile PDF'),
                ),
                if (log != null && log.trim().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Compiler log'),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
