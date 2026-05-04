import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// Reusable LaTeX workspace modes.
///
/// This is intentionally not tied to the job-search workspace. Any document
/// surface can use this enum/service/widgets to offer Overleaf-like editing.
enum LatexWorkspaceMode { source, preview, split, pdf }

class LatexCompileResult {
  const LatexCompileResult({
    required this.success,
    required this.log,
    this.pdfPath,
    this.compiler,
    this.sourcePath,
    this.workDirectory,
    this.duration,
  });

  final bool success;
  final String log;
  final String? pdfPath;
  final String? compiler;
  final String? sourcePath;
  final String? workDirectory;
  final Duration? duration;

  String get durationLabel {
    final value = duration;
    if (value == null) return '';
    final seconds = value.inMilliseconds / 1000;
    return seconds < 10 ? '${seconds.toStringAsFixed(1)}s' : '${seconds.round()}s';
  }
}

class LatexCompilerService {
  const LatexCompilerService._();

  static const List<String> _pathCompilerPreference = <String>[
    'tectonic',
    'pdflatex',
    'xelatex',
    'lualatex',
  ];

  /// Finds a LaTeX compiler, preferring a project/app-bundled Tectonic binary.
  ///
  /// This intentionally checks local paths before PATH so development builds can
  /// ship `tectonic.exe` in the project root without requiring a global install.
  /// For packaged Windows builds, putting `tectonic.exe` next to the app exe also
  /// works.
  static Future<String?> findAvailableCompiler() async {
    final seen = <String>{};
    for (final candidate in await _localCompilerCandidates()) {
      if (candidate.trim().isEmpty || !seen.add(candidate)) continue;
      if (await _canRun(candidate)) return candidate;
    }
    for (final candidate in _pathCompilerPreference) {
      if (!seen.add(candidate)) continue;
      if (await _canRun(candidate)) return candidate;
    }
    return null;
  }

  static Future<List<String>> _localCompilerCandidates() async {
    final names = Platform.isWindows
        ? const <String>['tectonic.exe', 'tectonic']
        : const <String>['tectonic'];

    final roots = <String>[
      Directory.current.path,
      p.dirname(Platform.resolvedExecutable),
    ];

    try {
      roots.add((await getApplicationSupportDirectory()).path);
    } catch (_) {
      // Application support can be unavailable in tests/early startup.
    }

    final candidates = <String>[];
    for (final root in roots) {
      for (final name in names) {
        candidates.add(p.join(root, name));
        candidates.add(p.join(root, 'bin', name));
        candidates.add(p.join(root, 'tools', name));
        candidates.add(p.join(root, 'tools', 'tectonic', name));
        candidates.add(p.join(root, 'vendor', name));
        candidates.add(p.join(root, 'vendor', 'tectonic', name));
      }

      // In Flutter desktop builds the runtime exe often sits in
      // build/windows/x64/runner/Debug. Walking a few parents lets development
      // runs still discover a compiler placed in the project root.
      var current = Directory(root);
      for (var i = 0; i < 6; i++) {
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
        for (final name in names) {
          candidates.add(p.join(current.path, name));
          candidates.add(p.join(current.path, 'tools', 'tectonic', name));
          candidates.add(p.join(current.path, 'vendor', 'tectonic', name));
        }
      }
    }

    final existing = <String>[];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) existing.add(candidate);
    }
    return existing;
  }

  static Future<LatexCompileResult> compile({
    required String title,
    required String source,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final stopwatch = Stopwatch()..start();
    final compiler = await findAvailableCompiler();
    final safeTitle = _safeStem(title.isEmpty ? 'latex-document' : title);
    final workDir = await _persistentBuildDirectory(safeTitle);
    await workDir.create(recursive: true);

    final sourcePath = p.join(workDir.path, 'main.tex');
    final texSource = _ensureCompleteDocument(source);
    await File(sourcePath).writeAsString(texSource, flush: true);

    final pdfPath = p.join(workDir.path, 'main.pdf');
    try {
      final stalePdf = File(pdfPath);
      if (await stalePdf.exists()) await stalePdf.delete();
    } catch (_) {
      // Non-fatal. The compiler will overwrite or fail with a useful log.
    }

    if (compiler == null) {
      stopwatch.stop();
      return LatexCompileResult(
        success: false,
        sourcePath: sourcePath,
        workDirectory: workDir.path,
        duration: stopwatch.elapsed,
        log: [
          'No LaTeX compiler was found.',
          '',
          'The app checks for bundled Tectonic first:',
          '- ./tectonic.exe',
          '- ./bin/tectonic.exe',
          '- ./tools/tectonic/tectonic.exe',
          '- next to the Windows app executable',
          '',
          'Then it falls back to PATH compilers:',
          '- tectonic',
          '- pdflatex',
          '- xelatex',
          '- lualatex',
          '',
          'The .tex source was still written here:',
          sourcePath,
        ].join('\n'),
      );
    }

    final log = StringBuffer();
    log.writeln('Build directory: ${workDir.path}');
    log.writeln('Source: $sourcePath');
    log.writeln('Compiler: ${_displayCompilerName(compiler)}');
    log.writeln('');

    Future<int> runCompiler() async {
      final args = _compilerArgs(compiler, sourcePath, workDir.path);
      log.writeln('> ${_displayCompilerName(compiler)} ${args.join(' ')}');
      final process = await Process.start(
        compiler,
        args,
        workingDirectory: workDir.path,
        runInShell: _shouldRunInShell(compiler),
      );
      final stdoutFuture = process.stdout.transform(systemEncoding.decoder).join();
      final stderrFuture = process.stderr.transform(systemEncoding.decoder).join();
      final exitFuture = process.exitCode.timeout(timeout, onTimeout: () async {
        process.kill(ProcessSignal.sigkill);
        return 124;
      });
      final exitCode = await exitFuture;
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      if (stdout.trim().isNotEmpty) log.writeln(stdout.trimRight());
      if (stderr.trim().isNotEmpty) log.writeln(stderr.trimRight());
      log.writeln('Exit code: $exitCode');
      return exitCode;
    }

    var exitCode = await runCompiler();
    if (exitCode == 0 && !_isCompiler(compiler, 'tectonic')) {
      // A second pass resolves references/table-of-contents in ordinary TeX.
      exitCode = await runCompiler();
    }

    final pdfExists = await File(pdfPath).exists();
    stopwatch.stop();
    if (stopwatch.elapsedMilliseconds > 0) {
      log.writeln('');
      log.writeln('Duration: ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
    }
    return LatexCompileResult(
      success: exitCode == 0 && pdfExists,
      pdfPath: pdfExists ? pdfPath : null,
      compiler: _displayCompilerName(compiler),
      sourcePath: sourcePath,
      workDirectory: workDir.path,
      duration: stopwatch.elapsed,
      log: log.toString().trim().isEmpty ? 'No compiler log was produced.' : log.toString(),
    );
  }

  static Future<Directory> _persistentBuildDirectory(String safeTitle) async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'latex_builds', safeTitle));
    } catch (_) {
      final tempRoot = await getTemporaryDirectory();
      return Directory(p.join(tempRoot.path, 'noteapp_latex_builds', safeTitle));
    }
  }

  static Future<bool> _canRun(String executable) async {
    try {
      final process = await Process.start(
        executable,
        const <String>['--version'],
        runInShell: _shouldRunInShell(executable),
      );
      await process.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return 124;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _shouldRunInShell(String executable) {
    if (!Platform.isWindows) return false;
    // PATH-resolved commands work most reliably through the shell on Windows.
    // Absolute/local executables work better without shell quoting issues.
    return !p.isAbsolute(executable);
  }

  static bool _isCompiler(String compiler, String name) {
    final base = p.basenameWithoutExtension(compiler).toLowerCase();
    return base == name.toLowerCase();
  }

  static String _displayCompilerName(String compiler) {
    final base = p.basename(compiler);
    return base.isEmpty ? compiler : base;
  }

  static List<String> _compilerArgs(String compiler, String sourcePath, String outputDir) {
    if (_isCompiler(compiler, 'tectonic')) {
      return <String>[
        '--outdir',
        outputDir,
        '--keep-logs',
        '--keep-intermediates',
        sourcePath,
      ];
    }
    return <String>[
      '-interaction=nonstopmode',
      '-halt-on-error',
      '-output-directory',
      outputDir,
      sourcePath,
    ];
  }

  static String _ensureCompleteDocument(String source) {
    if (source.contains(r'\documentclass') && source.contains(r'\begin{document}')) {
      return source;
    }
    return '''\\documentclass[11pt,a4paper]{article}
\\usepackage[utf8]{inputenc}
\\usepackage[T1]{fontenc}
\\usepackage{amsmath,amssymb}
\\usepackage[margin=1in]{geometry}
\\begin{document}
$source
\\end{document}
''';
  }

  static String _safeStem(String value) {
    final safe = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
    return safe.isEmpty ? 'latex-document' : safe.substring(0, math.min(safe.length, 64));
  }
}

class LatexModeBar extends StatelessWidget {
  final LatexWorkspaceMode mode;
  final ValueChanged<LatexWorkspaceMode> onModeChanged;
  final VoidCallback onCompile;
  final bool isCompiling;
  final LatexCompileResult? compileResult;

  const LatexModeBar({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.onCompile,
    required this.isCompiling,
    required this.compileResult,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = compileResult;
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        child: Row(
          children: [
            const Icon(Icons.functions_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<LatexWorkspaceMode>(
                segments: const [
                  ButtonSegment(value: LatexWorkspaceMode.source, label: Text('Source'), icon: Icon(Icons.code_rounded)),
                  ButtonSegment(value: LatexWorkspaceMode.preview, label: Text('Preview'), icon: Icon(Icons.visibility_outlined)),
                  ButtonSegment(value: LatexWorkspaceMode.split, label: Text('Split'), icon: Icon(Icons.view_column_outlined)),
                  ButtonSegment(value: LatexWorkspaceMode.pdf, label: Text('PDF'), icon: Icon(Icons.picture_as_pdf_outlined)),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => onModeChanged(selection.first),
              ),
            ),
            const SizedBox(width: 10),
            if (result != null)
              Flexible(
                child: Text(
                  result.success
                      ? 'Compiled ${result.durationLabel.isEmpty ? '' : 'in ${result.durationLabel} · '}with ${result.compiler ?? 'LaTeX'}'
                      : 'Compile issue${result.durationLabel.isEmpty ? '' : ' · ${result.durationLabel}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: result.success ? theme.colorScheme.primary : theme.colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: isCompiling ? null : onCompile,
              icon: isCompiling
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(isCompiling ? 'Compiling' : 'Compile'),
            ),
          ],
        ),
      ),
    );
  }
}

class LatexPseudoPreview extends StatelessWidget {
  final String source;
  final String title;
  final bool embedded;

  const LatexPseudoPreview({
    super.key,
    required this.source,
    required this.title,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = _LatexPreviewParser.parse(source);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: embedded ? 14 : 32, vertical: embedded ? 14 : 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: embedded ? 680 : 820),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(embedded ? 12 : 18),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(180)),
                  boxShadow: [
                    if (!embedded) BoxShadow(color: Colors.black.withAlpha(14), blurRadius: 26, offset: const Offset(0, 14)),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: embedded ? 680 : 960),
                  child: Padding(
                    padding: EdgeInsets.all(embedded ? 26 : 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title.trim().isEmpty ? 'Untitled LaTeX document' : title.trim(),
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 20),
                        if (blocks.isEmpty)
                          Text(
                            'Nothing to preview yet. Start typing LaTeX source.',
                            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          )
                        else
                          for (final block in blocks) _LatexPreviewBlockView(block: block),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LatexCompiledPdfPreview extends StatelessWidget {
  final LatexCompileResult? result;
  final VoidCallback onCompile;
  final bool isCompiling;

  const LatexCompiledPdfPreview({
    super.key,
    required this.result,
    required this.onCompile,
    required this.isCompiling,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pdfPath = result?.pdfPath;
    if (result?.success == true && pdfPath != null) {
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
                      [
                        if (result?.compiler != null) result!.compiler!,
                        if (result?.durationLabel.isNotEmpty == true) result!.durationLabel,
                        pdfPath,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  TextButton.icon(onPressed: onCompile, icon: const Icon(Icons.refresh_rounded), label: const Text('Recompile')),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: pdfrx.PdfViewer.file(
              pdfPath,
              key: ValueKey(pdfPath),
              params: pdfrx.PdfViewerParams(
                margin: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      );
    }

    return LatexCompileLogPanel(
      result: result,
      isCompiling: isCompiling,
      onCompile: onCompile,
    );
  }
}

class LatexCompileLogPanel extends StatelessWidget {
  final LatexCompileResult? result;
  final bool isCompiling;
  final VoidCallback onCompile;

  const LatexCompileLogPanel({
    super.key,
    required this.result,
    required this.isCompiling,
    required this.onCompile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final log = result?.log;
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
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  result?.success == false ? Icons.error_outline_rounded : Icons.picture_as_pdf_outlined,
                  size: 44,
                  color: result?.success == false ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  result == null
                      ? 'Compile LaTeX to PDF'
                      : result!.success
                          ? 'PDF compiled successfully.'
                          : 'LaTeX did not compile.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'This uses the bundled/project Tectonic compiler when available, then falls back to PATH. Repeated compiles reuse a persistent build folder for this document title.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (log != null && log.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 320),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withAlpha(130),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        log,
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Consolas', height: 1.3),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.center,
                  child: FilledButton.icon(
                    onPressed: isCompiling ? null : onCompile,
                    icon: isCompiling
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(isCompiling ? 'Compiling…' : 'Compile now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LatexPreviewBlockView extends StatelessWidget {
  final _LatexPreviewBlock block;

  const _LatexPreviewBlockView({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (block.type) {
      case _LatexPreviewBlockType.section:
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(block.text, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        );
      case _LatexPreviewBlockType.subsection:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(block.text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        );
      case _LatexPreviewBlockType.meta:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            block.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        );
      case _LatexPreviewBlockType.item:
        return Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: _InlineLatexText(block.text)),
            ],
          ),
        );
      case _LatexPreviewBlockType.math:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(child: _SafeMathTex(block.text, display: true)),
        );
      case _LatexPreviewBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _InlineLatexText(block.text),
        );
    }
  }
}

class _InlineLatexText extends StatelessWidget {
  final String text;

  const _InlineLatexText(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pieces = _splitInlineMath(text);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final piece in pieces)
          if (piece.isMath)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _SafeMathTex(piece.text, display: false),
            )
          else
            Text(
              piece.text,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
      ],
    );
  }
}

class _SafeMathTex extends StatelessWidget {
  final String tex;
  final bool display;

  const _SafeMathTex(this.tex, {required this.display});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    try {
      return Math.tex(
        tex,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        textStyle: theme.textTheme.bodyLarge,
        onErrorFallback: (error) => Text(
          tex,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'Consolas', color: theme.colorScheme.error),
        ),
      );
    } catch (_) {
      return Text(
        tex,
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'Consolas', color: theme.colorScheme.error),
      );
    }
  }
}

class _LatexPreviewParser {
  const _LatexPreviewParser._();

  static const Set<String> _skipCommands = <String>{
    'documentclass',
    'usepackage',
    'geometry',
    'pagestyle',
    'thispagestyle',
    'newcommand',
    'renewcommand',
    'providecommand',
    'setlength',
    'vspace',
    'hspace',
    'hfill',
    'noindent',
    'maketitle',
  };

  static const Set<String> _dropEnvironments = <String>{
    'center',
    'flushleft',
    'flushright',
    'minipage',
    'tabular',
    'tabularx',
    'table',
    'small',
    'footnotesize',
  };

  static List<_LatexPreviewBlock> parse(String source) {
    final text = _preparePreviewText(_documentBody(source));
    if (text.trim().isEmpty) return const <_LatexPreviewBlock>[];

    final blocks = <_LatexPreviewBlock>[];
    final displayMathRegex = RegExp(r'(\$\$[\s\S]*?\$\$|\\\[[\s\S]*?\\\])');
    var cursor = 0;
    for (final match in displayMathRegex.allMatches(text)) {
      if (match.start > cursor) _parseTextChunk(text.substring(cursor, match.start), blocks);
      final raw = match.group(0) ?? '';
      blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.math, _stripDisplayMath(raw)));
      cursor = match.end;
    }
    if (cursor < text.length) _parseTextChunk(text.substring(cursor), blocks);
    return _mergeParagraphContinuations(blocks);
  }

  static String _preparePreviewText(String source) {
    var text = _stripLatexComments(source);

    // Convert visual line breaks before stripping environments.
    text = text.replaceAll(RegExp(r'\\\\(?:\[[^\]]*\])?'), '\n');

    for (final env in _dropEnvironments) {
      text = text
          .replaceAll(RegExp('\\\\begin\\{$env\\}(?:\\{[^}]*\\})*'), '\n')
          .replaceAll(RegExp('\\\\end\\{$env\\}'), '\n');
    }

    text = text
        .replaceAll(RegExp(r'\\begin\{itemize\}|\\end\{itemize\}'), '\n')
        .replaceAll(RegExp(r'\\begin\{enumerate\}|\\end\{enumerate\}'), '\n')
        .replaceAll(RegExp(r'\\begin\{document\}|\\end\{document\}'), '\n')
        .replaceAll(RegExp(r'\[[0-9.]+\s*(pt|em|ex|mm|cm|in)\]'), ' ')
        .replaceAll(RegExp(r'\\(Large|LARGE|huge|Huge|large|small|footnotesize|scriptsize|normalsize)\b'), '')
        .replaceAll(RegExp(r'\\(centering|raggedright|raggedleft)\b'), '')
        .replaceAll(RegExp(r'\\(vspace|hspace)\*?\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'\\(smallskip|medskip|bigskip|par)\b'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return text.trim();
  }

  static void _parseTextChunk(String chunk, List<_LatexPreviewBlock> blocks) {
    final paragraphs = chunk.split(RegExp(r'\n\s*\n'));
    for (final paragraph in paragraphs) {
      for (final rawLine in paragraph.split('\n')) {
        var line = rawLine.trim();
        if (line.isEmpty) continue;
        if (_shouldSkipLine(line)) continue;

        final section = _extractCommandArgument(line, 'section');
        if (section != null) {
          blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.section, section));
          continue;
        }
        final subsection = _extractCommandArgument(line, 'subsection');
        if (subsection != null) {
          blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.subsection, subsection));
          continue;
        }
        final subsubsection = _extractCommandArgument(line, 'subsubsection');
        if (subsubsection != null) {
          blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.subsection, subsubsection));
          continue;
        }

        final roleBlocks = _parseRoleCommand(line);
        if (roleBlocks.isNotEmpty) {
          blocks.addAll(roleBlocks);
          continue;
        }

        if (line.startsWith(r'\item')) {
          blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.item, _cleanupInline(line.substring(5).trim())));
          continue;
        }

        final unknownCommand = _parseUnknownCommandLine(line);
        if (unknownCommand != null) line = unknownCommand;

        if (line.contains('&')) line = _cleanupTableRow(line);
        line = _cleanupInline(line);
        if (line.trim().isEmpty) continue;
        blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.paragraph, line));
      }
    }
  }

  static List<_LatexPreviewBlock> _parseRoleCommand(String line) {
    if (!line.startsWith(r'\role')) return const <_LatexPreviewBlock>[];
    final args = _extractBraceArguments(line).map(_cleanupInline).where((value) => value.trim().isNotEmpty).toList();
    if (args.isEmpty) return const <_LatexPreviewBlock>[];
    final blocks = <_LatexPreviewBlock>[];
    final title = args.first;
    final meta = args.skip(1).take(4).where((value) => value.trim().isNotEmpty).join(' · ');
    blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.subsection, title));
    if (meta.isNotEmpty) blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.meta, meta));
    for (final item in args.skip(5)) {
      blocks.add(_LatexPreviewBlock(_LatexPreviewBlockType.item, item));
    }
    return blocks;
  }

  static String? _parseUnknownCommandLine(String line) {
    final match = RegExp(r'^\\([A-Za-z@]+)\*?').firstMatch(line);
    if (match == null) return null;
    final command = match.group(1) ?? '';
    if (_skipCommands.contains(command)) return '';

    final args = _extractBraceArguments(line).map(_cleanupInline).where((value) => value.trim().isNotEmpty).toList();
    if (args.isEmpty) {
      // Unknown layout command without useful content: hide it in clean preview.
      return '';
    }
    return args.join(' · ');
  }

  static bool _shouldSkipLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'^\[[0-9.]+\s*(pt|em|ex|mm|cm|in)\]$').hasMatch(trimmed)) return true;
    if (trimmed == r'\\' || trimmed == r'{}') return true;
    final command = RegExp(r'^\\([A-Za-z@]+)').firstMatch(trimmed)?.group(1);
    if (command != null && _skipCommands.contains(command)) return true;
    if (trimmed.startsWith(r'\begin{') || trimmed.startsWith(r'\end{')) return true;
    return false;
  }

  static String _cleanupTableRow(String line) {
    final row = line.replaceAll(RegExp(r'\\+$'), '').trim();
    final cells = row
        .split('&')
        .map(_cleanupInline)
        .where((cell) => cell.trim().isNotEmpty && cell.trim() != r'$1' && cell.trim() != r'#1')
        .toList();
    if (cells.isEmpty) return '';
    return cells.join(' — ');
  }

  static String _documentBody(String source) {
    final begin = source.indexOf(r'\begin{document}');
    final end = source.indexOf(r'\end{document}');
    if (begin != -1 && end != -1 && end > begin) {
      return source.substring(begin + r'\begin{document}'.length, end);
    }
    return source;
  }

  static String _stripLatexComments(String source) {
    return source.split('\n').map((line) {
      final buffer = StringBuffer();
      for (var i = 0; i < line.length; i++) {
        final char = line[i];
        if (char == '%' && (i == 0 || line.codeUnitAt(i - 1) != 92)) break;
        buffer.write(char);
      }
      return buffer.toString();
    }).join('\n');
  }

  static String _stripDisplayMath(String raw) {
    if (raw.startsWith(r'$$') && raw.endsWith(r'$$')) return raw.substring(2, raw.length - 2).trim();
    if (raw.startsWith(r'\[') && raw.endsWith(r'\]')) return raw.substring(2, raw.length - 2).trim();
    return raw.trim();
  }

  static String? _extractCommandArgument(String line, String command) {
    final regex = RegExp('\\\\$command\\*?\\{([^}]*)\\}');
    final match = regex.firstMatch(line);
    return match == null ? null : _cleanupInline(match.group(1) ?? '');
  }

  static List<String> _extractBraceArguments(String value) {
    final args = <String>[];
    var depth = 0;
    var start = -1;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      final escaped = i > 0 && value.codeUnitAt(i - 1) == 92;
      if (escaped) continue;
      if (char == '{') {
        if (depth == 0) start = i + 1;
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          args.add(value.substring(start, i));
          start = -1;
        }
      }
    }
    return args;
  }

  static String _cleanupInline(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';

    final protectedMath = <String, String>{};
    text = text.replaceAllMapped(
      RegExp(r'\$[^\$]+\$|\\\([^)]*\\\)'),
      (match) {
        final key = '@@MATH_${protectedMath.length}@@';
        protectedMath[key] = match.group(0) ?? '';
        return key;
      },
    );

    // Remove font wrappers like {\LARGE Name} while preserving content.
    text = text.replaceAllMapped(
      RegExp(r'\{\\(?:Large|LARGE|huge|Huge|large|small|footnotesize|scriptsize|normalsize)\s+([^{}]*)\}'),
      (match) => match.group(1) ?? '',
    );

    // Expand common one/two-argument text commands.
    var changed = true;
    while (changed) {
      final before = text;
      text = text
          .replaceAllMapped(RegExp(r'\\(?:textbf|textit|emph|textsc|underline)\{([^{}]*)\}'), (m) => m.group(1) ?? '')
          .replaceAllMapped(RegExp(r'\\href\{[^{}]*\}\{([^{}]*)\}'), (m) => m.group(1) ?? '')
          .replaceAllMapped(RegExp(r'\\url\{([^{}]*)\}'), (m) => m.group(1) ?? '')
          .replaceAllMapped(RegExp(r'\\(?:Large|LARGE|huge|Huge|large|small|footnotesize|scriptsize|normalsize)\s+'), (_) => '')
          .replaceAllMapped(RegExp(r'\\[a-zA-Z]+\*?\{([^{}]*)\}'), (m) => m.group(1) ?? '');
      changed = before != text;
    }

    text = text
        .replaceAll(RegExp(r'\\(?:quad|qquad|,|;|:|!)'), ' ')
        .replaceAll(RegExp(r'\\[a-zA-Z]+\*?'), '')
        .replaceAll(RegExp(r'\{([^{}]*)\}'), r'$1')
        .replaceAll(RegExp(r'\[[0-9.]+\s*(pt|em|ex|mm|cm|in)\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    for (final entry in protectedMath.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    return text;
  }

  static List<_LatexPreviewBlock> _mergeParagraphContinuations(List<_LatexPreviewBlock> blocks) {
    // Keep this conservative: preserve headings/items, but merge sequential tiny
    // paragraph fragments from layout-heavy LaTeX into easier reading blocks.
    final merged = <_LatexPreviewBlock>[];
    for (final block in blocks) {
      if (block.type != _LatexPreviewBlockType.paragraph || merged.isEmpty) {
        merged.add(block);
        continue;
      }
      final previous = merged.last;
      if (previous.type == _LatexPreviewBlockType.paragraph && previous.text.length < 80 && block.text.length < 80) {
        merged[merged.length - 1] = _LatexPreviewBlock(
          _LatexPreviewBlockType.paragraph,
          '${previous.text}\n${block.text}',
        );
      } else {
        merged.add(block);
      }
    }
    return merged;
  }
}

class _LatexPreviewBlock {
  const _LatexPreviewBlock(this.type, this.text);

  final _LatexPreviewBlockType type;
  final String text;
}

enum _LatexPreviewBlockType { section, subsection, meta, paragraph, item, math }

class _InlinePiece {
  const _InlinePiece(this.text, this.isMath);

  final String text;
  final bool isMath;
}

List<_InlinePiece> _splitInlineMath(String value) {
  final pieces = <_InlinePiece>[];
  final regex = RegExp(r'\$([^$]+)\$');
  var cursor = 0;
  for (final match in regex.allMatches(value)) {
    if (match.start > cursor) pieces.add(_InlinePiece(value.substring(cursor, match.start), false));
    pieces.add(_InlinePiece(match.group(1) ?? '', true));
    cursor = match.end;
  }
  if (cursor < value.length) pieces.add(_InlinePiece(value.substring(cursor), false));
  return pieces.where((piece) => piece.text.isNotEmpty).toList(growable: false);
}
